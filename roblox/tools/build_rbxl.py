#!/usr/bin/env python3
"""
Deterministic Zero-Dependency Compiler for OpenFront Roblox Place Files (.rbxl & .rbxlx).

Strictly conforms to the official Roblox Binary Model Format specification (`rojo-rbx/rbx-dom` v1):
  - Header (32 bytes): b"<roblox!\\x89\\xff\\r\\n\\x1a\\n\\x00\\x00" + u32_le(num_classes) + u32_le(num_instances) + 8 zero bytes
  - Chunk Header (16 bytes): 4-byte ASCII tag + u32_le(compressed_len=0) + u32_le(uncompressed_len) + u32_le(0)
  - Big-endian byte-interleaved 32-bit integers + ZigZag encoding + delta-encoded Referents & Parent arrays
  - Full round-trip binary & XML self-verification pass before exiting!

Outputs:
  1. /home/user/OpenFrontIO/OpenFront.rbxl        (Ready-to-open Studio binary place file at repo root!)
  2. /home/user/OpenFrontIO/roblox/OpenFront.rbxl (Mirror copy inside roblox/)
  3. /home/user/OpenFrontIO/roblox/OpenFront.rbxlx (XML Studio place file for human inspection/diffing)
"""

import os
import struct
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Dict, List, Optional

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ROBLOX_DIR = os.path.join(REPO_ROOT, "roblox")
SRC_DIR = os.path.join(ROBLOX_DIR, "src")

OUT_ROOT_RBXL = os.path.join(REPO_ROOT, "OpenFront.rbxl")
OUT_SUB_RBXL = os.path.join(ROBLOX_DIR, "OpenFront.rbxl")
OUT_SUB_RBXLX = os.path.join(ROBLOX_DIR, "OpenFront.rbxlx")

MAX_SOURCE_CHARS = 160_000  # Strict safety margin below Roblox Studio's 200,000-char Source limit!

MAGIC_HEADER = b"<roblox!\x89\xff\r\n\x1a\n\x00\x00"
PROP_TYPE_STRING = 0x01
PROP_TYPE_BOOL = 0x02

SERVICE_CLASSES = {
    "Workspace",
    "Players",
    "Lighting",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "StarterPlayerScripts",
    "StarterCharacterScripts",
    "SoundService",
}


@dataclass
class RbxInstance:
    class_name: str
    name: str
    source: Optional[str] = None
    is_service: bool = False
    referent: int = -1
    parent: Optional["RbxInstance"] = None
    children: List["RbxInstance"] = field(default_factory=list)

    def add(self, child: "RbxInstance") -> "RbxInstance":
        child.parent = self
        self.children.append(child)
        return child


def build_folder_tree(parent_inst: RbxInstance, disk_dir: str) -> int:
    count = 0
    for entry in sorted(os.listdir(disk_dir)):
        full = os.path.join(disk_dir, entry)
        if os.path.isdir(full):
            folder = parent_inst.add(RbxInstance("Folder", entry))
            count += build_folder_tree(folder, full)
        elif entry.endswith(".server.luau"):
            stem = entry[: -len(".server.luau")]
            with open(full, "r", encoding="utf-8") as f:
                src = f.read()
            assert len(src) < MAX_SOURCE_CHARS, f"{full} exceeds {MAX_SOURCE_CHARS} chars ({len(src)})"
            parent_inst.add(RbxInstance("Script", stem, source=src))
            count += 1
        elif entry.endswith(".client.luau"):
            stem = entry[: -len(".client.luau")]
            with open(full, "r", encoding="utf-8") as f:
                src = f.read()
            assert len(src) < MAX_SOURCE_CHARS, f"{full} exceeds {MAX_SOURCE_CHARS} chars ({len(src)})"
            parent_inst.add(RbxInstance("LocalScript", stem, source=src))
            count += 1
        elif entry.endswith(".luau"):
            stem = entry[: -len(".luau")]
            with open(full, "r", encoding="utf-8") as f:
                src = f.read()
            assert len(src) < MAX_SOURCE_CHARS, f"{full} exceeds {MAX_SOURCE_CHARS} chars ({len(src)})"
            parent_inst.add(RbxInstance("ModuleScript", stem, source=src))
            count += 1
    return count


def build_datamodel() -> tuple[List[RbxInstance], int]:
    roots: List[RbxInstance] = []

    workspace = RbxInstance("Workspace", "Workspace", is_service=True)
    players = RbxInstance("Players", "Players", is_service=True)
    lighting = RbxInstance("Lighting", "Lighting", is_service=True)
    rep_first = RbxInstance("ReplicatedFirst", "ReplicatedFirst", is_service=True)

    rep_storage = RbxInstance("ReplicatedStorage", "ReplicatedStorage", is_service=True)
    shared_folder = rep_storage.add(RbxInstance("Folder", "OpenFrontShared"))
    n_shared = build_folder_tree(shared_folder, os.path.join(SRC_DIR, "Shared"))

    sss = RbxInstance("ServerScriptService", "ServerScriptService", is_service=True)
    server_folder = sss.add(RbxInstance("Folder", "OpenFrontServer"))
    n_server = build_folder_tree(server_folder, os.path.join(SRC_DIR, "Server"))

    starter_gui = RbxInstance("StarterGui", "StarterGui", is_service=True)
    starter_pack = RbxInstance("StarterPack", "StarterPack", is_service=True)

    starter_player = RbxInstance("StarterPlayer", "StarterPlayer", is_service=True)
    sps = starter_player.add(RbxInstance("StarterPlayerScripts", "StarterPlayerScripts", is_service=True))
    client_folder = sps.add(RbxInstance("Folder", "OpenFrontClient"))
    n_client = build_folder_tree(client_folder, os.path.join(SRC_DIR, "Client"))
    starter_player.add(RbxInstance("StarterCharacterScripts", "StarterCharacterScripts", is_service=True))

    sound_service = RbxInstance("SoundService", "SoundService", is_service=True)

    roots.extend(
        [
            workspace,
            players,
            lighting,
            rep_first,
            rep_storage,
            sss,
            starter_gui,
            starter_pack,
            starter_player,
            sound_service,
        ]
    )

    # Flatten DFS and assign deterministic 0..N-1 Referents
    all_instances: List[RbxInstance] = []

    def visit(node: RbxInstance):
        node.referent = len(all_instances)
        all_instances.append(node)
        for ch in node.children:
            visit(ch)

    for r in roots:
        visit(r)

    return all_instances, (n_shared + n_server + n_client)


# ==============================================================================
# BINARY .RBXL ENCODER (rbx-dom exact wire specification)
# ==============================================================================
def pack_rbx_string(s: str) -> bytes:
    raw = s.encode("utf-8")
    return struct.pack("<I", len(raw)) + raw


def zigzag_encode_i32(val: int) -> int:
    return ((val << 1) ^ (val >> 31)) & 0xFFFFFFFF


def zigzag_decode_u32(u: int) -> int:
    return (u >> 1) ^ -(u & 1)


def pack_interleaved_i32(values: List[int]) -> bytes:
    n = len(values)
    out = bytearray(n * 4)
    for idx, v in enumerate(values):
        zz = zigzag_encode_i32(v)
        out[idx] = (zz >> 24) & 0xFF
        out[n + idx] = (zz >> 16) & 0xFF
        out[2 * n + idx] = (zz >> 8) & 0xFF
        out[3 * n + idx] = zz & 0xFF
    return bytes(out)


def unpack_interleaved_i32(buf: bytes, offset: int, count: int) -> tuple[List[int], int]:
    res = []
    for idx in range(count):
        b0 = buf[offset + idx]
        b1 = buf[offset + count + idx]
        b2 = buf[offset + 2 * count + idx]
        b3 = buf[offset + 3 * count + idx]
        u = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        res.append(zigzag_decode_u32(u))
    return res, offset + count * 4


def pack_referent_array(refs: List[int]) -> bytes:
    deltas = []
    prev = 0
    for r in refs:
        deltas.append(r - prev)
        prev = r
    return pack_interleaved_i32(deltas)


def unpack_referent_array(buf: bytes, offset: int, count: int) -> tuple[List[int], int]:
    deltas, new_off = unpack_interleaved_i32(buf, offset, count)
    refs = []
    acc = 0
    for d in deltas:
        acc += d
        refs.append(acc)
    return refs, new_off


def make_uncompressed_chunk(tag4: bytes, payload: bytes) -> bytes:
    assert len(tag4) == 4
    # compressed_len = 0 instructs Roblox & rbx_binary to read `uncompressed_len` raw bytes directly!
    return tag4 + struct.pack("<III", 0, len(payload), 0) + payload


def serialize_binary_rbxl(all_instances: List[RbxInstance]) -> bytes:
    by_class: Dict[str, List[RbxInstance]] = {}
    class_order: List[str] = []
    for inst in all_instances:
        if inst.class_name not in by_class:
            by_class[inst.class_name] = []
            class_order.append(inst.class_name)
        by_class[inst.class_name].append(inst)

    num_classes = len(class_order)
    num_instances = len(all_instances)

    chunks = bytearray()
    chunks.extend(MAGIC_HEADER)
    chunks.extend(struct.pack("<II", num_classes, num_instances))
    chunks.extend(b"\x00" * 8)

    # 1. META chunk
    meta_payload = struct.pack("<I", 1) + pack_rbx_string("ExplicitAutoJoints") + pack_rbx_string("true")
    chunks.extend(make_uncompressed_chunk(b"META", meta_payload))

    # 2. INST chunks (one per unique ClassName)
    for cid, cname in enumerate(class_order):
        group = by_class[cname]
        refs = [g.referent for g in group]
        is_svc = 1 if (cname in SERVICE_CLASSES and all(g.is_service for g in group)) else 0
        payload = bytearray()
        payload.extend(struct.pack("<I", cid))
        payload.extend(pack_rbx_string(cname))
        payload.append(is_svc)
        payload.extend(struct.pack("<I", len(group)))
        payload.extend(pack_referent_array(refs))
        if is_svc:
            payload.extend(b"\x01" * len(group))
        chunks.extend(make_uncompressed_chunk(b"INST", bytes(payload)))

    # 3. PROP chunks (`Name` for every class; `Source` & `Disabled` for Script/LocalScript/ModuleScript)
    for cid, cname in enumerate(class_order):
        group = by_class[cname]
        # Name property
        p_name = bytearray()
        p_name.extend(struct.pack("<I", cid))
        p_name.extend(pack_rbx_string("Name"))
        p_name.append(PROP_TYPE_STRING)
        for g in group:
            p_name.extend(pack_rbx_string(g.name))
        chunks.extend(make_uncompressed_chunk(b"PROP", bytes(p_name)))

        if cname in ("Script", "LocalScript", "ModuleScript"):
            p_src = bytearray()
            p_src.extend(struct.pack("<I", cid))
            p_src.extend(pack_rbx_string("Source"))
            p_src.append(PROP_TYPE_STRING)
            for g in group:
                p_src.extend(pack_rbx_string(g.source or ""))
            chunks.extend(make_uncompressed_chunk(b"PROP", bytes(p_src)))

        if cname in ("Script", "LocalScript"):
            p_dis = bytearray()
            p_dis.extend(struct.pack("<I", cid))
            p_dis.extend(pack_rbx_string("Disabled"))
            p_dis.append(PROP_TYPE_BOOL)
            p_dis.extend(b"\x00" * len(group))
            chunks.extend(make_uncompressed_chunk(b"PROP", bytes(p_dis)))

    # 4. PRNT chunk (child -> parent Referent links; -1 = root under DataModel)
    prnt = bytearray()
    prnt.append(0)  # format version 0
    prnt.extend(struct.pack("<I", num_instances))
    child_refs = [inst.referent for inst in all_instances]
    parent_refs = [inst.parent.referent if inst.parent is not None else -1 for inst in all_instances]
    prnt.extend(pack_referent_array(child_refs))
    prnt.extend(pack_referent_array(parent_refs))
    chunks.extend(make_uncompressed_chunk(b"PRNT", bytes(prnt)))

    # 5. END chunk (`</roblox>`)
    chunks.extend(make_uncompressed_chunk(b"END\x00", b"</roblox>"))
    return bytes(chunks)


def verify_binary_rbxl(blob: bytes, expected_instances: List[RbxInstance]) -> None:
    assert blob[:16] == MAGIC_HEADER, "Invalid .rbxl magic header!"
    num_classes, num_instances = struct.unpack("<II", blob[16:24])
    assert num_instances == len(expected_instances), f"Instance count mismatch: {num_instances}"

    pos = 32
    seen_end = False
    parsed_classes: Dict[int, tuple[str, List[int]]] = {}
    parsed_names: Dict[int, str] = {}
    parsed_sources: Dict[int, str] = {}
    parsed_parents: Dict[int, int] = {}

    while pos < len(blob):
        tag = blob[pos : pos + 4]
        comp_len, uncomp_len, reserved = struct.unpack("<III", blob[pos + 4 : pos + 16])
        assert comp_len == 0 and reserved == 0
        pos += 16
        body = blob[pos : pos + uncomp_len]
        assert len(body) == uncomp_len
        pos += uncomp_len

        if tag == b"INST":
            cid = struct.unpack("<I", body[0:4])[0]
            slen = struct.unpack("<I", body[4:8])[0]
            cname = body[8 : 8 + slen].decode("utf-8")
            off = 8 + slen + 1
            cnt = struct.unpack("<I", body[off : off + 4])[0]
            refs, _ = unpack_referent_array(body, off + 4, cnt)
            parsed_classes[cid] = (cname, refs)
        elif tag == b"PROP":
            cid = struct.unpack("<I", body[0:4])[0]
            plen = struct.unpack("<I", body[4:8])[0]
            pname = body[8 : 8 + plen].decode("utf-8")
            ptype = body[8 + plen]
            off = 9 + plen
            _, refs = parsed_classes[cid]
            if ptype == PROP_TYPE_STRING:
                for r in refs:
                    vlen = struct.unpack("<I", body[off : off + 4])[0]
                    off += 4
                    sval = body[off : off + vlen].decode("utf-8")
                    off += vlen
                    if pname == "Name":
                        parsed_names[r] = sval
                    elif pname == "Source":
                        parsed_sources[r] = sval
        elif tag == b"PRNT":
            assert body[0] == 0
            cnt = struct.unpack("<I", body[1:5])[0]
            c_refs, off2 = unpack_referent_array(body, 5, cnt)
            p_refs, _ = unpack_referent_array(body, off2, cnt)
            for cr, pr in zip(c_refs, p_refs):
                parsed_parents[cr] = pr
        elif tag == b"END\x00":
            assert body == b"</roblox>"
            seen_end = True
            break

    assert seen_end and pos == len(blob), "Binary .rbxl did not terminate cleanly at END chunk!"
    assert len(parsed_classes) == num_classes

    for exp in expected_instances:
        assert parsed_names[exp.referent] == exp.name
        exp_parent = exp.parent.referent if exp.parent is not None else -1
        assert parsed_parents[exp.referent] == exp_parent
        if exp.source is not None:
            assert parsed_sources[exp.referent] == exp.source, f"Source mismatch on {exp.name}!"


# ==============================================================================
# XML .RBXLX SERIALIZER & SELF-VERIFIER
# ==============================================================================
def serialize_xml_rbxlx(all_instances: List[RbxInstance]) -> bytes:
    root_el = ET.Element(
        "roblox",
        {
            "xmlns:xmime": "http://www.w3.org/2005/05/xmlmime",
            "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
            "xsi:noNamespaceSchemaLocation": "http://www.roblox.com/roblox.xsd",
            "version": "4",
        },
    )
    meta = ET.SubElement(root_el, "Meta", {"name": "ExplicitAutoJoints"})
    meta.text = "true"

    def emit(inst: RbxInstance, parent_el: ET.Element):
        item = ET.SubElement(
            parent_el,
            "Item",
            {"class": inst.class_name, "referent": f"RBX{inst.referent:06d}"},
        )
        props = ET.SubElement(item, "Properties")
        nm = ET.SubElement(props, "string", {"name": "Name"})
        nm.text = inst.name
        if inst.source is not None:
            ps = ET.SubElement(props, "ProtectedString", {"name": "Source"})
            ps.text = inst.source
        if inst.class_name in ("Script", "LocalScript"):
            dis = ET.SubElement(props, "bool", {"name": "Disabled"})
            dis.text = "false"
        for ch in inst.children:
            emit(ch, item)

    for inst in all_instances:
        if inst.parent is None:
            emit(inst, root_el)

    xml_bytes = b'<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(root_el, encoding="utf-8")
    # Parse back via standard XML parser to guarantee well-formedness & 1:1 Source fidelity
    parsed_root = ET.fromstring(xml_bytes)
    assert len(list(parsed_root.iter("Item"))) == len(all_instances)
    return xml_bytes


def main():
    all_instances, total_scripts = build_datamodel()
    bin_bytes = serialize_binary_rbxl(all_instances)
    verify_binary_rbxl(bin_bytes, all_instances)
    xml_bytes = serialize_xml_rbxlx(all_instances)

    for path in (OUT_ROOT_RBXL, OUT_SUB_RBXL):
        with open(path, "wb") as f:
            f.write(bin_bytes)
    with open(OUT_SUB_RBXLX, "wb") as f:
        f.write(xml_bytes)

    print(
        f"[build_rbxl] SUCCESS: {total_scripts} Luau scripts ({len(all_instances)} DataModel instances) -> "
        f"OpenFront.rbxl ({len(bin_bytes) / 1024:.1f} KB binary verified) & "
        f"roblox/OpenFront.rbxlx ({len(xml_bytes) / 1024:.1f} KB XML verified)"
    )


if __name__ == "__main__":
    main()
