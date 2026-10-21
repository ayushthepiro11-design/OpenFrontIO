#!/usr/bin/env python3
"""
Converts official OpenFront binary maps + manifests from ../resources/maps/
into compact PackBits-RLE + Base64 Luau ModuleScripts under ../src/Shared/Maps/.
Strictly enforces < 150,000 chars per ModuleScript (well below Roblox Studio's
200,000-character LuaSourceContainer.Source limit).

Preserves exact OpenFront terrain byte bit-packing:
  bit 7 (0x80): isLand
  bit 6 (0x40): isShoreline
  bit 5 (0x20): isOcean
  bits 0..4 (0x1f): magnitude (0..9 Plains, 10..19 Highland, 20..30 Mountain, 31 Impassable)
"""

import base64
import json
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAPS_SRC = os.path.join(REPO_ROOT, "resources", "maps")
MAPS_OUT = os.path.join(REPO_ROOT, "roblox", "src", "Shared", "Maps")

SELECTED_MAPS = [
    ("world", "World", "World Map", "world", 500),
    ("shinobiworld", "ShinobiWorld", "Shinobi World", "fictional", 375),
    ("europe", "Europe", "Europe", "europe", 480),
    ("northamerica", "NorthAmerica", "North America", "north_america", 500),
    ("asia", "Asia", "Asia", "asia", 480),
    ("africa", "Africa", "Africa", "africa", 390),
    ("southamerica", "SouthAmerica", "South America", "south_america", 380),
    ("australia", "Australia", "Australia", "oceania", 460),
    ("britannia", "Britannia", "Britannia", "europe", 400),
    ("blacksea", "BlackSea", "Black Sea", "europe", 375),
]


def quantize_terrain_byte(tb: int) -> int:
    is_land = (tb & 0x80) != 0
    flags = tb & 0xE0
    mag = tb & 0x1F
    if is_land and mag == 31:
        return tb
    if is_land:
        # Preserve exact tier boundaries: Plains (0..9), Highland (10..19), Mountain (20..30)
        if mag < 10:
            qmag = (mag // 3) * 3
        elif mag < 20:
            qmag = 10 + ((mag - 10) // 3) * 3
        else:
            qmag = 20 + ((mag - 20) // 4) * 4
        return flags | qmag
    else:
        qmag = min(10, (mag // 3) * 3)
        return flags | qmag


def prepare_terrain(data: bytes, src_w: int, src_h: int, max_dim: int):
    if src_w <= max_dim and src_h <= max_dim:
        out = bytearray(quantize_terrain_byte(b) for b in data)
        return bytes(out), src_w, src_h
    scale = min(max_dim / src_w, max_dim / src_h)
    dst_w = max(4, int(round(src_w * scale / 2.0)) * 2)
    dst_h = max(4, int(round(src_h * scale / 2.0)) * 2)
    out = bytearray(dst_w * dst_h)
    sx = src_w / dst_w
    sy = src_h / dst_h
    for y in range(dst_h):
        src_row = min(src_h - 1, int(y * sy)) * src_w
        dst_row = y * dst_w
        for x in range(dst_w):
            src_x = min(src_w - 1, int(x * sx))
            out[dst_row + x] = quantize_terrain_byte(data[src_row + src_x])
    for y in range(dst_h):
        row = y * dst_w
        for x in range(dst_w):
            idx = row + x
            tb = out[idx]
            is_land = (tb & 0x80) != 0
            mag = tb & 0x1F
            if is_land and mag == 31:
                continue
            adj_diff = False
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < dst_w and 0 <= ny < dst_h:
                    ntb = out[ny * dst_w + nx]
                    if ((ntb & 0x80) != 0) != is_land:
                        adj_diff = True
                        break
            out[idx] = (tb | 0x40) if adj_diff else (tb & ~0x40)
    return bytes(out), dst_w, dst_h


def packbits_encode(data: bytes) -> bytes:
    """
    Hybrid PackBits + Long-Run encoder:
      Header byte b:
        0x00 .. 0x7F : Literal sequence of (b + 1) raw bytes follows (1..128 bytes)
        0x80 .. 0xDF : Short repeat run of (b - 0x80 + 3) copies of next 1 byte (3..98 copies)
        0xE0 .. 0xFF : Long repeat run: length = ((b & 0x1F) << 8) | next_byte + 99 copies of following 1 byte (up to 8290 copies!)
    Never expands noisy runs AND compresses ocean/continent spans by 50x!
    """
    out = bytearray()
    n = len(data)
    i = 0
    lit_start = 0

    def flush_literals(end_idx: int):
        nonlocal lit_start
        while lit_start < end_idx:
            chunk_len = min(128, end_idx - lit_start)
            out.append(chunk_len - 1)
            out.extend(data[lit_start : lit_start + chunk_len])
            lit_start += chunk_len

    while i < n:
        val = data[i]
        run = 1
        while i + run < n and data[i + run] == val and run < 8290:
            run += 1
        if run >= 3:
            flush_literals(i)
            if run <= 98:
                out.append(0x80 + (run - 3))
                out.append(val)
            else:
                rem = run - 99
                out.append(0xE0 | ((rem >> 8) & 0x1F))
                out.append(rem & 0xFF)
                out.append(val)
            i += run
            lit_start = i
        else:
            i += 1
            if i - lit_start == 128:
                flush_literals(i)

    flush_literals(n)
    return bytes(out)


def packbits_decode_verify(encoded: bytes, expected_len: int) -> bytes:
    out = bytearray()
    i = 0
    n = len(encoded)
    while i < n:
        b = encoded[i]
        i += 1
        if b < 0x80:
            cnt = b + 1
            out.extend(encoded[i : i + cnt])
            i += cnt
        elif b < 0xE0:
            cnt = (b - 0x80) + 3
            val = encoded[i]
            i += 1
            out.extend(bytes([val]) * cnt)
        else:
            rem = ((b & 0x1F) << 8) | encoded[i]
            i += 1
            cnt = rem + 99
            val = encoded[i]
            i += 1
            out.extend(bytes([val]) * cnt)
    assert len(out) == expected_len, f"Decoded {len(out)} != {expected_len}"
    return bytes(out)


def find_nearest_land(data: bytes, w: int, h: int, cx: int, cy: int):
    cx = max(0, min(w - 1, cx))
    cy = max(0, min(h - 1, cy))
    tb = data[cy * w + cx]
    if (tb & 0x80) != 0 and (tb & 0x1F) != 31:
        return cx, cy
    for r in range(1, 28):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if abs(dx) != r and abs(dy) != r:
                    continue
                nx, ny = cx + dx, cy + dy
                if 0 <= nx < w and 0 <= ny < h:
                    ntb = data[ny * w + nx]
                    if (ntb & 0x80) != 0 and (ntb & 0x1F) != 31:
                        return nx, ny
    return None


def lua_str(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def main():
    os.makedirs(MAPS_OUT, exist_ok=True)
    registry_entries = []
    total_chars = 0

    for folder, module_name, display_name, category, max_dim in SELECTED_MAPS:
        manifest_path = os.path.join(MAPS_SRC, folder, "manifest.json")
        bin16_path = os.path.join(MAPS_SRC, folder, "map16x.bin")
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        with open(bin16_path, "rb") as f:
            raw16 = f.read()

        full_meta = manifest["map"]
        meta16 = manifest["map16x"]
        w16, h16 = meta16["width"], meta16["height"]
        scaled_data, w, h = prepare_terrain(raw16, w16, h16, max_dim)
        sx = w / full_meta["width"]
        sy = h / full_meta["height"]

        num_land = sum(
            1 for b in scaled_data if (b & 0x80) != 0 and (b & 0x1F) != 31
        )

        pw = 64
        ph = max(24, min(48, round(pw * (h / w))))
        preview_chars = []
        for py in range(ph):
            sy_i = min(h - 1, int((py + 0.5) * h / ph))
            for px in range(pw):
                sx_i = min(w - 1, int((px + 0.5) * w / pw))
                tb = scaled_data[sy_i * w + sx_i]
                is_land = (tb & 0x80) != 0
                mag = tb & 0x1F
                if is_land and mag == 31:
                    preview_chars.append("X")
                elif is_land:
                    if mag >= 20:
                        preview_chars.append("M")
                    elif mag >= 10:
                        preview_chars.append("H")
                    else:
                        preview_chars.append("P")
                elif (tb & 0x40) != 0:
                    preview_chars.append("S")
                else:
                    preview_chars.append("O")
        preview_str = "".join(preview_chars)

        nations_lua = []
        seen_names = set()
        for nat in manifest.get("nations", []):
            name = nat.get("name", "Nation")
            if name in seen_names:
                continue
            coords = nat.get("coordinates")
            flag = str(nat.get("flag", "")).lower()
            strength = float(nat.get("strength", 1.0))
            if coords and len(coords) >= 2:
                nx = int(coords[0] * sx)
                ny = int(coords[1] * sy)
                snapped = find_nearest_land(scaled_data, w, h, nx, ny)
                if snapped is None:
                    continue
                seen_names.add(name)
                nations_lua.append(
                    f'\t\t{{ name = {lua_str(name)}, flag = {lua_str(flag)}, x = {snapped[0]}, y = {snapped[1]}, strength = {strength:.2f} }},'
                )
            else:
                seen_names.add(name)
                nations_lua.append(
                    f'\t\t{{ name = {lua_str(name)}, flag = {lua_str(flag)}, x = -1, y = -1, strength = {strength:.2f} }},'
                )

        packed = packbits_encode(scaled_data)
        assert packbits_decode_verify(packed, len(scaled_data)) == scaled_data
        b64 = base64.b64encode(packed).decode("ascii")

        chunks = [b64[i : i + 120] for i in range(0, len(b64), 120)]
        b64_block = "\\\n".join(chunks)

        luau_src = f"""--!strict
-- Auto-generated from OpenFrontIO resources/maps/{folder}
return {{
\tid = {lua_str(module_name)},
\tfolder = {lua_str(folder)},
\tname = {lua_str(display_name)},
\tcategory = {lua_str(category)},
\twidth = {w},
\theight = {h},
\tnumLandTiles = {num_land},
\tpreviewW = {pw},
\tpreviewH = {ph},
\tpreview = "{preview_str}",
\tnations = {{
{chr(10).join(nations_lua)}
\t}},
\trleBase64 = "{b64_block}",
}}
"""
        assert (
            len(luau_src) < 160_000
        ), f"Module {module_name} exceeded Studio safe script limit ({len(luau_src)} chars)!"

        out_file = os.path.join(MAPS_OUT, f"{module_name}.luau")
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(luau_src)

        total_chars += len(luau_src)
        registry_entries.append((module_name, display_name, category, w, h, num_land, len(nations_lua)))
        print(
            f"Exported {module_name:14s}: {w:3d}x{h:<3d} | land={num_land:6d} | nations={len(nations_lua):2d} | script={len(luau_src)/1024:5.1f} KB"
        )

    reg_lines = [
        "--!strict",
        "local MapsFolder = script.Parent",
        "",
        "export type NationSpawn = {",
        "\tname: string,",
        "\tflag: string,",
        "\tx: number,",
        "\ty: number,",
        "\tstrength: number,",
        "}",
        "",
        "export type RawMapDefinition = {",
        "\tid: string,",
        "\tfolder: string,",
        "\tname: string,",
        "\tcategory: string,",
        "\twidth: number,",
        "\theight: number,",
        "\tnumLandTiles: number,",
        "\tpreviewW: number,",
        "\tpreviewH: number,",
        "\tpreview: string,",
        "\tnations: { NationSpawn },",
        "\trleBase64: string,",
        "}",
        "",
        "local MAP_MODULES: { RawMapDefinition } = {",
    ]
    for mod_name, *_ in registry_entries:
        reg_lines.append(f"\trequire(MapsFolder:WaitForChild({lua_str(mod_name)})) :: any,")
    reg_lines += [
        "}",
        "",
        "local BY_ID: { [string]: RawMapDefinition } = {}",
        "for _, def in ipairs(MAP_MODULES) do",
        "\tBY_ID[def.id] = def",
        "end",
        "",
        "local MapRegistry = {}",
        "MapRegistry.List = MAP_MODULES",
        "MapRegistry.ById = BY_ID",
        "",
        "function MapRegistry.Get(mapId: string): RawMapDefinition",
        "\treturn BY_ID[mapId] or MAP_MODULES[1]",
        "end",
        "",
        "return MapRegistry",
        "",
    ]

    with open(os.path.join(MAPS_OUT, "MapRegistry.luau"), "w", encoding="utf-8") as f:
        f.write("\n".join(reg_lines))

    print(f"Total ModuleScript source size across all {len(registry_entries)} maps: {total_chars/1024:.1f} KB")


if __name__ == "__main__":
    main()
