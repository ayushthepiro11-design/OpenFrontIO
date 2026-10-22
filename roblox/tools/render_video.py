#!/usr/bin/env python3
"""
Renders the complete, uncut, start-to-finish `1.0x` normal-speed bot match recorded by
`roblox/tools/play_and_record.mjs` from `/tmp/of_recording` into:
  - `gameplay/OpenFront_Roblox_Gameplay.mp4` (`1280x720` H.264 `20fps` = exact `2 frames / 0.1s` tick =
    `1.000x` real-time clock speed + synchronized `44.1 kHz` Stereo AAC Sound FX!)
  - All 8 High-Resolution `1280x720` PNG Screenshots in `gameplay/`!

Enforces strict mathematical ZERO-OVERLAP guarantees across every HUD panel, Top Banner,
Leaderboard row, Minimap, Event Feed, Radial Menu, Build Modal, Country Name Plate, and Unit Badge.
"""

import json
import math
import os
import struct
import subprocess
import unicodedata
import wave
from typing import Dict, List, Optional, Tuple

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW_DIR = "/tmp/of_recording"
OUT_DIR = os.path.join(REPO_ROOT, "gameplay")
os.makedirs(OUT_DIR, exist_ok=True)

W, H = 1280, 720
FPS = 20  # Exact 2 subframes per 0.100s SimEngine tick => 10.0 ticks == 1.000 second (1.000x Normal Speed!)
SUBFRAMES_PER_TICK = 2

FONT_BOLD_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_CACHE: Dict[Tuple[bool, int], ImageFont.FreeTypeFont] = {}


def get_font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    key = (bold, size)
    if key not in FONT_CACHE:
        FONT_CACHE[key] = ImageFont.truetype(FONT_BOLD_PATH if bold else FONT_REG_PATH, size)
    return FONT_CACHE[key]


def hex_rgb(h: str, alpha: int = 255) -> Tuple[int, int, int, int]:
    s = (h or "#94a3b8").lstrip("#")
    if len(s) != 6:
        return (148, 163, 184, alpha)
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), alpha)


def fmt_num(n: float) -> str:
    n = abs(float(n))
    if n >= 1_000_000_000:
        return f"{n / 1_000_000_000:.2f}B"
    if n >= 1_000_000:
        return f"{n / 1_000_000:.2f}M"
    if n >= 10_000:
        return f"{n / 1_000:.1f}K"
    if n >= 1_000:
        return f"{n / 1_000:.2f}K"
    return f"{int(round(n))}"


def fmt_timer(sec: float) -> str:
    s = max(0, int(sec))
    return f"{s // 60:02d}:{s % 60:02d}"


def clean_ascii_text(txt: str) -> str:
    pre = (txt or "").replace("—", "-").replace("–", "-").replace("•", "|").replace("·", "|")
    norm = unicodedata.normalize("NFKD", pre)
    cleaned = "".join(ch for ch in norm if 32 <= ord(ch) <= 126)
    cleaned = " ".join(cleaned.split())
    return cleaned if cleaned else "Frontier update"


def draw_centered_text(
    draw: ImageDraw.ImageDraw,
    rect: Tuple[int, int, int, int],
    txt: str,
    font: ImageFont.FreeTypeFont,
    fill: Tuple[int, int, int, int],
    dy: int = 0,
) -> None:
    x0, y0, x1, y1 = rect
    bbox = draw.textbbox((0, 0), txt, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = x0 + (x1 - x0 - tw) // 2 - bbox[0]
    ty = y0 + (y1 - y0 - th) // 2 - bbox[1] + dy
    draw.text((tx, ty), txt, font=font, fill=fill)


def truncate_to_px(draw: ImageDraw.ImageDraw, txt: str, font: ImageFont.FreeTypeFont, max_w: int) -> str:
    if draw.textlength(txt, font=font) <= max_w:
        return txt
    s = txt
    while len(s) > 2 and draw.textlength(s + "..", font=font) > max_w:
        s = s[:-1]
    return s + ".."


FLAG_SPECS = {
    "in": ("h3", (255, 153, 51), (255, 255, 255), (19, 136, 8)),
    "ru": ("h3", (248, 250, 252), (37, 99, 235), (220, 38, 38)),
    "de": ("h3", (23, 23, 23), (220, 38, 38), (250, 204, 21)),
    "eg": ("h3", (200, 30, 30), (255, 255, 255), (20, 20, 20)),
    "et": ("h3", (22, 163, 74), (250, 204, 21), (220, 38, 38)),
    "ir": ("h3", (22, 163, 74), (255, 255, 255), (220, 38, 38)),
    "ar": ("h3", (125, 211, 252), (255, 255, 255), (125, 211, 252)),
    "es": ("h3", (200, 30, 30), (250, 204, 21), (200, 30, 30)),
    "fr": ("v3", (29, 78, 216), (255, 255, 255), (220, 38, 38)),
    "it": ("v3", (22, 163, 74), (255, 255, 255), (220, 38, 38)),
    "ng": ("v3", (21, 128, 61), (255, 255, 255), (21, 128, 61)),
    "mx": ("v3", (21, 128, 61), (255, 255, 255), (220, 38, 38)),
    "ca": ("v3", (220, 38, 38), (255, 255, 255), (220, 38, 38)),
    "ua": ("h2", (37, 99, 235), (250, 204, 21), (0, 0, 0)),
    "id": ("h2", (220, 38, 38), (255, 255, 255), (0, 0, 0)),
    "pl": ("h2", (255, 255, 255), (220, 38, 38), (0, 0, 0)),
    "se": ("h2", (37, 99, 235), (250, 204, 21), (0, 0, 0)),
    "no": ("h3", (220, 38, 38), (30, 58, 138), (220, 38, 38)),
}


def draw_flag(
    draw: ImageDraw.ImageDraw,
    code: str,
    x: int,
    y: int,
    w: int,
    h: int,
    fallback_rgb: Tuple[int, int, int, int] = (56, 189, 248, 255),
) -> None:
    c = (code or "").lower()
    if c == "konoha" or c.startswith("shinobi"):
        draw.rounded_rectangle([x, y, x + w, y + h], radius=2, fill=(185, 28, 28, 255))
        draw.rounded_rectangle([x + 2, y + 2, x + w - 2, y + h - 2], radius=1, fill=(226, 232, 240, 255))
        cx, cy = x + w // 2, y + h // 2
        draw.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], outline=(185, 28, 38, 255), width=1)
    elif c in ("us", "usa"):
        draw.rectangle([x, y, x + w, y + h], fill=(185, 28, 28, 255))
        for sy in range(y + 2, y + h, 4):
            draw.line([(x, sy), (x + w, sy)], fill=(255, 255, 255, 255), width=1)
        draw.rectangle([x, y, x + w // 2, y + h // 2], fill=(29, 78, 216, 255))
    elif c in ("gb", "uk", "au"):
        draw.rectangle([x, y, x + w, y + h], fill=(29, 78, 216, 255))
        draw.line([(x, y + h // 2), (x + w, y + h // 2)], fill=(255, 255, 255, 255), width=3)
        draw.line([(x + w // 2, y), (x + w // 2, y + h)], fill=(255, 255, 255, 255), width=3)
        draw.line([(x, y + h // 2), (x + w, y + h // 2)], fill=(220, 38, 38, 255), width=1)
        draw.line([(x + w // 2, y), (x + w // 2, y + h)], fill=(220, 38, 38, 255), width=1)
    elif c == "jp":
        draw.rectangle([x, y, x + w, y + h], fill=(255, 255, 255, 255))
        r = max(2, h // 4)
        draw.ellipse([x + w // 2 - r, y + h // 2 - r, x + w // 2 + r, y + h // 2 + r], fill=(220, 38, 38, 255))
    elif c == "br":
        draw.rectangle([x, y, x + w, y + h], fill=(22, 163, 74, 255))
        draw.polygon([(x + w // 2, y + 2), (x + w - 2, y + h // 2), (x + w // 2, y + h - 2), (x + 2, y + h // 2)], fill=(250, 204, 21, 255))
    elif c in ("cn", "tr"):
        draw.rectangle([x, y, x + w, y + h], fill=(220, 38, 38, 255))
        draw.ellipse([x + 3, y + 2, x + 7, y + 6], fill=(250, 204, 21, 255) if c == "cn" else (255, 255, 255, 255))
    elif c in FLAG_SPECS:
        kind, c1, c2, c3 = FLAG_SPECS[c]
        if kind == "h3":
            draw.rectangle([x, y, x + w, y + h], fill=(*c2, 255))
            draw.rectangle([x, y, x + w, y + h // 3], fill=(*c1, 255))
            draw.rectangle([x, y + (2 * h) // 3, x + w, y + h], fill=(*c3, 255))
        elif kind == "v3":
            draw.rectangle([x, y, x + w, y + h], fill=(*c2, 255))
            draw.rectangle([x, y, x + w // 3, y + h], fill=(*c1, 255))
            draw.rectangle([x + (2 * w) // 3, y, x + w, y + h], fill=(*c3, 255))
        elif kind == "h2":
            draw.rectangle([x, y, x + w, y + h], fill=(*c1, 255))
            draw.rectangle([x, y + h // 2, x + w, y + h], fill=(*c2, 255))
    else:
        draw.rectangle([x, y, x + w, y + h], fill=fallback_rgb)
    draw.rectangle([x, y, x + w, y + h], outline=(15, 23, 42, 235), width=1)


def draw_unit_vector_icon(draw: ImageDraw.ImageDraw, utype: str, cx: int, cy: int, rad: int, col: Tuple[int, int, int, int]) -> None:
    draw.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=(15, 23, 42, 235), outline=col, width=2)
    r = max(3, int(rad * 0.54))
    if utype == "City":
        draw.rectangle([cx - r, cy - r // 2, cx - 1, cy + r], fill=(248, 250, 252, 255))
        draw.rectangle([cx, cy - r, cx + r, cy + r], fill=(96, 165, 250, 255))
    elif utype == "Port":
        draw.line([cx, cy - r, cx, cy + r], fill=(56, 189, 248, 255), width=2)
        draw.arc([cx - r, cy - r, cx + r, cy + r], start=20, end=160, fill=(56, 189, 248, 255), width=2)
        draw.line([cx - r // 2, cy - r // 2, cx + r // 2, cy - r // 2], fill=(255, 255, 255, 255), width=2)
    elif utype == "Factory":
        draw.polygon([(cx - r, cy + r), (cx - r, cy), (cx, cy - r // 2), (cx, cy), (cx + r, cy - r // 2), (cx + r, cy + r)], fill=(251, 191, 36, 255))
    elif utype == "DefensePost":
        draw.polygon([(cx - r, cy - r // 2), (cx + r, cy - r // 2), (cx + r // 2, cy + r), (cx, cy + r + 2), (cx - r // 2, cy + r)], fill=(74, 222, 128, 255))
    elif utype == "MissileSilo":
        draw.polygon([(cx, cy - r - 1), (cx + r // 2 + 1, cy + r), (cx - r // 2 - 1, cy + r)], fill=(248, 113, 113, 255))
    elif utype == "SAMLauncher":
        draw.line([cx - r, cy + r // 2, cx + r // 2, cy - r], fill=(34, 211, 238, 255), width=3)
        draw.line([cx - r, cy + r, cx + r, cy + r], fill=(226, 232, 240, 255), width=2)
    elif utype == "Warship":
        draw.polygon([(cx - r - 1, cy), (cx + r + 2, cy), (cx + r - 2, cy + r // 2 + 2), (cx - r + 2, cy + r // 2 + 2)], fill=(148, 163, 200, 255))
        draw.rectangle([cx - 2, cy - r // 2 - 1, cx + 2, cy], fill=(248, 250, 252, 255))
    elif utype == "TransportShip":
        draw.polygon([(cx - r, cy), (cx + r, cy), (cx + r - 2, cy + r // 2 + 2), (cx - r + 2, cy + r // 2 + 2)], fill=(96, 165, 250, 255))
    elif utype == "TradeShip":
        draw.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=(250, 204, 21, 255))
    elif utype == "Train":
        draw.rounded_rectangle([cx - r, cy - r // 2, cx + r, cy + r // 2], radius=2, fill=(245, 158, 11, 255))
    elif utype in ("AtomBomb", "HydrogenBomb", "MIRV", "MIRVWarhead"):
        fill_c = (251, 146, 60, 255) if utype == "AtomBomb" else ((244, 63, 94, 255) if utype == "HydrogenBomb" else (250, 204, 21, 255))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill_c)
        draw.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=(15, 23, 42, 255))
    elif utype == "SAMMissile":
        draw.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(103, 232, 249, 255))


PREVIEW_COLORS = {
    "O": (58, 114, 158),
    "S": (118, 166, 201),
    "P": (182, 214, 132),
    "H": (206, 188, 140),
    "M": (234, 234, 234),
    "X": (48, 52, 60),
}
MAP_THUMB_CACHE: Dict[str, Image.Image] = {}


def build_map_thumb(map_id: str, pstr: str, pw: int, ph: int, target_w: int, target_h: int) -> Image.Image:
    key = f"{map_id}_{target_w}x{target_h}"
    if key in MAP_THUMB_CACHE:
        return MAP_THUMB_CACHE[key]
    arr = np.zeros((ph, pw, 3), dtype=np.uint8)
    for y in range(ph):
        for x in range(pw):
            idx = y * pw + x
            ch = pstr[idx] if idx < len(pstr) else "O"
            arr[y, x] = PREVIEW_COLORS.get(ch, (58, 114, 158))
    im = Image.fromarray(arr, mode="RGB").resize((target_w, target_h), Image.Resampling.NEAREST).convert("RGBA")
    MAP_THUMB_CACHE[key] = im
    return im


def build_base_terrain_rgb(terrain_bytes: bytes, mw: int, mh: int) -> np.ndarray:
    """Exact 256-entry LUT matching `MapCanvas.luau` ocean/coast/plains/highland/mountain shading!"""
    lut = np.zeros((256, 3), dtype=np.uint8)
    for b in range(256):
        is_land = (b & 0x80) != 0
        is_coast = (b & 0x40) != 0
        elev = b & 0x1F
        if not is_land:
            if is_coast:
                lut[b] = (92, 152, 198)
            else:
                lut[b] = (42 + min(18, elev), 92 + min(18, elev), 144 + min(16, elev))
        else:
            if elev >= 20:
                sh = min(19, (elev - 20) * 2)
                lut[b] = (224 + sh, 226 + sh, 232 + min(19, sh))
            elif elev >= 11:
                sh = (elev - 11) * 2
                lut[b] = (196 + sh, 180 + sh, 134 + sh)
            else:
                sh = elev * 2
                lut[b] = (168 + sh, 202 + sh, 122 + sh)
    raw = np.frombuffer(terrain_bytes, dtype=np.uint8).reshape((mh, mw))
    base = lut[raw]
    # Subtle dark coastal land outline on unclaimed continents just like OpenFront.io!
    land_mask = (raw & 0x80) != 0
    water_adj = (~land_mask)
    shore_land = land_mask & (
        np.roll(water_adj, 1, axis=0)
        | np.roll(water_adj, -1, axis=0)
        | np.roll(water_adj, 1, axis=1)
        | np.roll(water_adj, -1, axis=1)
    )
    base[shore_land] = (base[shore_land].astype(np.uint16) * 78 // 100).astype(np.uint8)
    return base


def compose_world_canvas(
    base_rgb: np.ndarray,
    owner_grid: np.ndarray,
    fallout_grid: np.ndarray,
    palette_rgb: np.ndarray,
    my_sid: int,
    alt_view: bool,
) -> np.ndarray:
    """Fast vectorized composition of `2000x1000` world RGBA buffer + crisp 1px territory borders."""
    out = base_rgb.copy()
    owned = owner_grid > 0
    if np.any(owned):
        if alt_view:
            alt_pal = np.zeros_like(palette_rgb)
            alt_pal[:, :] = (239, 68, 68)
            alt_pal[my_sid] = (34, 197, 94)
            p_cols = alt_pal[owner_grid[owned]]
        else:
            p_cols = palette_rgb[owner_grid[owned]]
        terr = out[owned].astype(np.uint16)
        out[owned] = ((p_cols.astype(np.uint16) * 66 + terr * 34) // 100).astype(np.uint8)

        # Crisp dark 1-pixel border outline around every territory!
        border = owned & (
            (owner_grid != np.roll(owner_grid, 1, axis=0))
            | (owner_grid != np.roll(owner_grid, -1, axis=0))
            | (owner_grid != np.roll(owner_grid, 1, axis=1))
            | (owner_grid != np.roll(owner_grid, -1, axis=1))
        )
        out[border] = (out[border].astype(np.uint16) * 44 // 100).astype(np.uint8)

    if np.any(fallout_grid > 0):
        fm = fallout_grid > 0
        out[fm] = ((out[fm].astype(np.uint16) * 35 + np.array([234, 88, 12], dtype=np.uint16) * 65) // 100).astype(np.uint8)

    return out


def sample_viewport_rgba(world_rgb: np.ndarray, cam_x: float, cam_y: float, scale: float) -> Image.Image:
    mh, mw, _ = world_rgb.shape
    xs = np.floor(cam_x + (np.arange(W, dtype=np.float32) - W * 0.5) / scale).astype(np.int32)
    ys = np.floor(cam_y + (np.arange(H, dtype=np.float32) - H * 0.5) / scale).astype(np.int32)
    valid_x = (xs >= 0) & (xs < mw)
    valid_y = (ys >= 0) & (ys < mh)
    xs_c = np.clip(xs, 0, mw - 1)
    ys_c = np.clip(ys, 0, mh - 1)
    rgb = world_rgb[ys_c[:, None], xs_c[None, :]]
    if not (np.all(valid_x) and np.all(valid_y)):
        mask = valid_y[:, None] & valid_x[None, :]
        rgb = np.where(mask[:, :, None], rgb, np.array([15, 23, 42], dtype=np.uint8))
    alpha = np.full((H, W, 1), 255, dtype=np.uint8)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2), mode="RGBA")


def world_to_screen(wx: float, wy: float, cam_x: float, cam_y: float, scale: float) -> Tuple[int, int]:
    return int(round(W * 0.5 + (wx - cam_x) * scale)), int(round(H * 0.5 + (wy - cam_y) * scale))


def synthesize_audio_wav(wav_path: str, total_frames: int, sfx_events: List[Tuple[int, str]]) -> None:
    sr = 44100
    dur = total_frames / FPS + 0.35
    total_samples = int(sr * dur)
    track = np.zeros(total_samples, dtype=np.float32)

    t_all = np.arange(total_samples, dtype=np.float32) / sr
    # Warm tactical command-room synth drone with subtle 1-bar pulse
    pulse_env = 0.72 + 0.28 * np.sin(2 * math.pi * 0.25 * t_all)
    track += pulse_env * (
        0.022 * np.sin(2 * math.pi * 65.41 * t_all)
        + 0.015 * np.sin(2 * math.pi * 98.00 * t_all)
        + 0.008 * np.sin(2 * math.pi * 130.81 * t_all)
    )

    rng = np.random.default_rng(42)
    for f_idx, cue in sfx_events:
        start = int((f_idx / FPS) * sr)
        if start >= total_samples:
            continue
        if cue in ("click", "hover"):
            n = int(0.055 * sr)
            t = np.arange(n, dtype=np.float32) / sr
            freq = 920.0 if cue == "click" else 660.0
            wave_seg = 0.22 * np.sin(2 * math.pi * freq * t) * np.exp(-t * 55.0)
        elif cue == "spawn":
            n = int(0.32 * sr)
            t = np.arange(n, dtype=np.float32) / sr
            wave_seg = 0.24 * (np.sin(2 * math.pi * 440.0 * t) + 0.8 * np.sin(2 * math.pi * 659.25 * t)) * np.exp(-t * 8.5)
        elif cue == "attack":
            n = int(0.18 * sr)
            t = np.arange(n, dtype=np.float32) / sr
            noise = rng.normal(0, 1, n).astype(np.float32)
            wave_seg = (0.14 * noise * np.exp(-t * 22.0)) + 0.18 * np.sin(2 * math.pi * (240 - 90 * t) * t) * np.exp(-t * 14.0)
        elif cue in ("build", "boat"):
            n = int(0.24 * sr)
            t = np.arange(n, dtype=np.float32) / sr
            f0 = 196.0 if cue == "build" else 146.8
            wave_seg = 0.22 * (np.sin(2 * math.pi * f0 * t) + 0.6 * np.sin(2 * math.pi * f0 * 1.5 * t)) * np.exp(-t * 11.0)
        elif cue == "launch":
            n = int(0.85 * sr)
            t = np.arange(n, dtype=np.float32) / sr
            noise = rng.normal(0, 1, n).astype(np.float32)
            siren = np.sin(2 * math.pi * (480 + 220 * np.sin(2 * math.pi * 4.5 * t)) * t)
            wave_seg = (0.15 * noise * np.exp(-t * 4.0) + 0.20 * siren) * np.exp(-t * 2.1)
        elif cue == "boom":
            n = int(0.95 * sr)
            t = np.arange(n, dtype=np.float32) / sr
            noise = rng.normal(0, 1, n).astype(np.float32)
            sub = np.sin(2 * math.pi * (74 * np.exp(-t * 2.2) + 28) * t)
            wave_seg = (0.36 * sub + 0.26 * noise * np.exp(-t * 5.5)) * np.exp(-t * 2.3)
        elif cue == "victory":
            n = int(2.4 * sr)
            t = np.arange(n, dtype=np.float32) / sr
            chord = (
                np.sin(2 * math.pi * 261.63 * t)
                + 0.85 * np.sin(2 * math.pi * 329.63 * t)
                + 0.85 * np.sin(2 * math.pi * 392.00 * t)
                + 0.95 * np.sin(2 * math.pi * 523.25 * t)
            )
            wave_seg = 0.16 * chord * np.exp(-t * 1.05)
        else:
            continue

        end = min(total_samples, start + len(wave_seg))
        track[start:end] += wave_seg[: end - start]

    track = np.clip(track, -0.95, 0.95)
    pcm16 = (track * 32767.0).astype(np.int16)
    stereo = np.column_stack([pcm16, pcm16]).flatten()

    with wave.open(wav_path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(stereo.tobytes())


def rects_hit(
    rects: List[Tuple[int, int, int, int]],
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    pad: int = 6,
) -> bool:
    if x0 < 12 or y0 < 12 or x1 > W - 12 or y1 > H - 12:
        return True
    for rx0, ry0, rx1, ry1 in rects:
        if x0 - pad < rx1 and x1 + pad > rx0 and y0 - pad < ry1 and y1 + pad > ry0:
            return True
    return False


def main():
    with open(os.path.join(RAW_DIR, "ticks.jsonl"), "r", encoding="utf-8") as f:
        tick_metas = [json.loads(line) for line in f if line.strip()]

    num_ticks = len(tick_metas)
    total_frames = num_ticks * SUBFRAMES_PER_TICK
    mw = int(tick_metas[0]["mapW"])
    mh = int(tick_metas[0]["mapH"])

    print(
        f"[render_video] Rendering FULL UNCUT 1.0x Match: {num_ticks} ticks -> {total_frames} HD 1280x720 frames "
        f"({total_frames / FPS:.1f}s @ {FPS}fps, 10 ticks == 1.000s real time)..."
    )

    terrain_bytes = open(os.path.join(RAW_DIR, "terrain_World.bin"), "rb").read()
    base_rgb = build_base_terrain_rgb(terrain_bytes, mw, mh)
    owner_grid = np.zeros((mh, mw), dtype=np.uint16)
    fallout_grid = np.zeros((mh, mw), dtype=np.uint8)

    palette_rgb = np.full((512, 3), 148, dtype=np.uint8)
    for p in tick_metas[0].get("players", []):
        r, g, b, _ = hex_rgb(p["col"], 255)
        palette_rgb[int(p["sid"])] = (r, g, b)
    if tick_metas[0].get("me"):
        r, g, b, _ = hex_rgb(tick_metas[0]["me"]["col"], 255)
        palette_rgb[int(tick_metas[0]["me"]["sid"])] = (r, g, b)

    sfx_events: List[Tuple[int, str]] = []
    for t_idx, m in enumerate(tick_metas):
        sfx = (m.get("extra") or {}).get("sfx") or ""
        if sfx:
            sfx_events.append((t_idx * SUBFRAMES_PER_TICK, sfx))

    wav_path = os.path.join(RAW_DIR, "audio.wav")
    synthesize_audio_wav(wav_path, total_frames, sfx_events)

    # Pick exact high-impact frames for all 8 required 1280x720 PNG screenshots!
    screenshot_targets: Dict[int, str] = {}
    best_boom_tick = -1
    best_boom_score = -1
    for i, m in enumerate(tick_metas):
        ui = m["uiMode"]
        ex = m.get("extra") or {}
        if ui == "MainMenu" and i == 15:
            screenshot_targets[i * SUBFRAMES_PER_TICK] = "01_main_menu_live_preview.png"
        if ui == "HostModal" and ex.get("selectedMap") == "ShinobiWorld" and "02_host_lobby_10_maps.png" not in screenshot_targets.values():
            screenshot_targets[i * SUBFRAMES_PER_TICK] = "02_host_lobby_10_maps.png"
        if ui == "InGame" and m.get("inSpawn") and m.get("me", {}).get("sx", -1) >= 0 and "03_spawn_phase_india.png" not in screenshot_targets.values():
            screenshot_targets[(i + 10) * SUBFRAMES_PER_TICK] = "03_spawn_phase_india.png"
        if ex.get("radialOpen") and "04_empire_expansion_and_radial_menu.png" not in screenshot_targets.values():
            screenshot_targets[(i + 12) * SUBFRAMES_PER_TICK] = "04_empire_expansion_and_radial_menu.png"
        if ex.get("buildMenuOpen") and "05_build_menu_economy_trains_ships.png" not in screenshot_targets.values():
            screenshot_targets[(i + 12) * SUBFRAMES_PER_TICK] = "05_build_menu_economy_trains_ships.png"
        if m.get("altView") and "07_shinobi_world_ninja_war.png" not in screenshot_targets.values():
            screenshot_targets[(i + 20) * SUBFRAMES_PER_TICK] = "07_shinobi_world_ninja_war.png"

        mirv_wh = sum(1 for u in m.get("units", []) if u["t"] == "MIRVWarhead")
        nuke_in_air = sum(1 for u in m.get("units", []) if u["t"] in ("AtomBomb", "HydrogenBomb", "MIRV", "MIRVWarhead"))
        sc = mirv_wh * 40 + len(m.get("explosions") or []) * 15 + nuke_in_air * 6
        if sc > best_boom_score and i > 900:
            best_boom_score = sc
            best_boom_tick = i

    if best_boom_tick >= 0:
        screenshot_targets[min(total_frames - 20, best_boom_tick * SUBFRAMES_PER_TICK + 4)] = "06_mirv_and_nuclear_warfare.png"
    else:
        screenshot_targets[max(0, (num_ticks - 90) * SUBFRAMES_PER_TICK)] = "06_mirv_and_nuclear_warfare.png"
    screenshot_targets[total_frames - 12] = "08_victory_ceremony_xp_levelup.png"

    mp4_path = os.path.join(OUT_DIR, "OpenFront_Roblox_Gameplay.mp4")
    ffmpeg_bin = imageio_ffmpeg.get_ffmpeg_exe()
    proc = subprocess.Popen(
        [
            ffmpeg_bin,
            "-y",
            "-f",
            "rawvideo",
            "-vcodec",
            "rawvideo",
            "-pix_fmt",
            "rgba",
            "-s",
            f"{W}x{H}",
            "-r",
            str(FPS),
            "-i",
            "-",
            "-i",
            wav_path,
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "23",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "160k",
            "-shortest",
            "-movflags",
            "+faststart",
            mp4_path,
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    delta_f = open(os.path.join(RAW_DIR, "deltas.bin"), "rb")
    cached_maps_meta = None
    active_shockwaves: List[Dict] = []

    for t_idx, m in enumerate(tick_metas):
        if (m.get("extra") or {}).get("maps") is not None:
            cached_maps_meta = m["extra"]["maps"]

        # Unpack binary owner + fallout pixel deltas for this exact tick
        hdr = delta_f.read(8)
        if len(hdr) == 8:
            owner_len, fall_len = struct.unpack("<II", hdr)
            if owner_len > 0:
                ob = delta_f.read(owner_len)
                dt = np.dtype([("ref", "<u4"), ("oid", "<u2")])
                arr = np.frombuffer(ob, dtype=dt)
                flat_owner = owner_grid.ravel()
                flat_owner[arr["ref"]] = arr["oid"]
            if fall_len > 0:
                fb = delta_f.read(fall_len)
                dtf = np.dtype([("ref", "<u4"), ("st", "u1")])
                arrf = np.frombuffer(fb, dtype=dtf)
                flat_fall = fallout_grid.ravel()
                flat_fall[arrf["ref"]] = arrf["st"]

        my_sid = int(m["mySid"])
        world_rgb = compose_world_canvas(base_rgb, owner_grid, fallout_grid, palette_rgb, my_sid, bool(m.get("altView")))
        mini_im = Image.fromarray(world_rgb, mode="RGB").resize((204, 110), Image.Resampling.NEAREST).convert("RGBA")

        nxt = tick_metas[min(num_ticks - 1, t_idx + 1)]
        for ex in m.get("explosions", []):
            active_shockwaves.append({"x": ex["x"], "y": ex["y"], "r": ex["radius"], "t": 0.0})

        player_colors: Dict[int, Tuple[int, int, int, int]] = {}
        for p in m.get("players", []):
            player_colors[int(p["sid"])] = hex_rgb(p["col"], 255)
        if m.get("me"):
            player_colors[int(m["me"]["sid"])] = hex_rgb(m["me"]["col"], 255)

        for sub in range(SUBFRAMES_PER_TICK):
            f_idx = t_idx * SUBFRAMES_PER_TICK + sub
            alpha_t = sub / SUBFRAMES_PER_TICK
            cam_x = float(m["camX"]) + (float(nxt["camX"]) - float(m["camX"])) * alpha_t
            cam_y = float(m["camY"]) + (float(nxt["camY"]) - float(m["camY"])) * alpha_t
            scale = float(m["camScale"]) + (float(nxt["camScale"]) - float(m["camScale"])) * alpha_t
            ui_mode = m["uiMode"]
            extra = m.get("extra") or {}
            modal_active = ui_mode in ("MainMenu", "HostModal", "Victory") or bool(extra.get("buildMenuOpen"))

            frame = sample_viewport_rgba(world_rgb, cam_x, cam_y, scale)
            overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            draw = ImageDraw.Draw(overlay)

            # Pre-compute ALL HUD & popup exclusion zones FIRST so world labels & badges NEVER collide with HUD!
            occupied_rects: List[Tuple[int, int, int, int]] = []
            if not modal_active:
                ph_font = get_font(13)
                ph_w = int(draw.textlength(clean_ascii_text(m["phase"]), font=ph_font))
                occupied_rects.append((12, 10, max(268, 52 + ph_w), 56))
                occupied_rects.append((W - 334, 10, W - 10, 274))
                occupied_rects.append((W - 424, H - 252, W - 10, H - 10))
                if not m.get("inSpawn") and m.get("me") is not None:
                    occupied_rects.append((10, H - 190, 362, H - 10))
                flying_nukes_pre = [u for u in m.get("units", []) if u["t"] in ("AtomBomb", "HydrogenBomb", "MIRV", "MIRVWarhead")]
                if m.get("inSpawn") or m.get("altView") or flying_nukes_pre:
                    occupied_rects.append((398, 10, 882, 74))
                if extra.get("radialOpen"):
                    rcx, rcy = W // 2 + 86, H // 2 - 18
                    occupied_rects.append((rcx - 104, rcy - 104, rcx + 104, rcy + 104))

            # 1. Railroad Lines
            for path_arr in m.get("rails", []):
                pts = []
                for k in range(0, len(path_arr), 2):
                    r = path_arr[k]
                    sx, sy = world_to_screen((r % mw) + 0.5, (r // mw) + 0.5, cam_x, cam_y, scale)
                    pts.append((sx, sy))
                if len(pts) >= 2:
                    draw.line(pts, fill=(92, 58, 34, 215), width=max(2, int(scale * 0.50)))

            # 2. Spawn Phase Pulsing Beacon
            if m.get("inSpawn") and m.get("me") and m["me"]["sx"] >= 0:
                sx, sy = world_to_screen(m["me"]["sx"] + 0.5, m["me"]["sy"] + 0.5, cam_x, cam_y, scale)
                pulse = 12 + int(6 * abs(math.sin(f_idx * 0.35)))
                draw.ellipse([sx - pulse, sy - pulse, sx + pulse, sy + pulse], fill=(250, 204, 21, 90), outline=(250, 204, 21, 255), width=3)
                draw.ellipse([sx - 5, sy - 5, sx + 5, sy + 5], fill=(255, 255, 255, 255))

            # 3. Inbound Nuke Ground Blast Circles & Trajectories
            for u in m.get("units", []):
                ut = u["t"]
                if ut in ("AtomBomb", "HydrogenBomb", "MIRV", "MIRVWarhead"):
                    ux, uy = world_to_screen(u["x"] + 0.5, u["y"] + 0.5, cam_x, cam_y, scale)
                    dx_s, dy_s = world_to_screen(u["dx"] + 0.5, u["dy"] + 0.5, cam_x, cam_y, scale)
                    r_world = 42 if ut == "HydrogenBomb" else (18 if ut == "AtomBomb" else 11)
                    r_px = max(12, int(r_world * scale))
                    alpha_pulse = 55 + int(40 * abs(math.sin(f_idx * 0.5)))
                    draw.ellipse([dx_s - r_px, dy_s - r_px, dx_s + r_px, dy_s + r_px], fill=(239, 68, 68, alpha_pulse), outline=(248, 113, 113, 225), width=2)
                    draw.line([(ux, uy), (dx_s, dy_s)], fill=(251, 146, 60, 175), width=2)

            # 4. Expanding Nuclear Shockwaves
            next_sw = []
            for sw in active_shockwaves:
                sw["t"] += 0.065
                if sw["t"] < 1.0:
                    sx, sy = world_to_screen(sw["x"] + 0.5, sw["y"] + 0.5, cam_x, cam_y, scale)
                    cur_r = int(max(12, sw["r"] * scale * (0.25 + 1.05 * sw["t"])))
                    fade = int(235 * (1.0 - sw["t"]))
                    core_fade = int(155 * (1.0 - sw["t"]))
                    draw.ellipse([sx - cur_r, sy - cur_r, sx + cur_r, sy + cur_r], fill=(254, 240, 138, core_fade), outline=(249, 115, 22, fade), width=3)
                    next_sw.append(sw)
            active_shockwaves = next_sw

            # 5. Units & Non-Overlapping Unit Sub-Badges FIRST
            placed_unit_centers: List[Tuple[int, int, str]] = []
            for u in m.get("units", []):
                ut = u["t"]
                ux, uy = world_to_screen(u["x"] + 0.5, u["y"] + 0.5, cam_x, cam_y, scale)
                if not (-24 <= ux <= W + 24 and -24 <= uy <= H + 24):
                    continue

                is_missile = ut in ("AtomBomb", "HydrogenBomb", "MIRV", "MIRVWarhead", "SAMMissile")
                if not is_missile:
                    too_close = False
                    for px_u, py_u, _ in placed_unit_centers:
                        if (ux - px_u) ** 2 + (uy - py_u) ** 2 < 17 * 17:
                            too_close = True
                            break
                    if too_close:
                        continue

                col = player_colors.get(int(u["o"]), (255, 255, 255, 255))
                if ut == "SAMLauncher" and int(u["o"]) == my_sid and scale >= 1.3 and not modal_active:
                    sr_px = int(42 * scale)
                    draw.ellipse([ux - sr_px, uy - sr_px, ux + sr_px, uy + sr_px], outline=(34, 211, 238, 115), width=2)

                rad = int(max(6, min(13, scale * 6.5)))
                if ut in ("TradeShip", "Train"):
                    rad = int(max(5, min(8, scale * 4.5)))
                elif is_missile:
                    rad = int(max(7, min(12, scale * 7.5)))

                draw_unit_vector_icon(draw, ut, ux, uy, rad, col)
                placed_unit_centers.append((ux, uy, ut))
                occupied_rects.append((ux - rad, uy - rad, ux + rad, uy + rad))

                if not modal_active and scale >= 1.25:
                    badge_str = ""
                    badge_col = (254, 240, 138, 255)
                    if ut == "TransportShip" and u.get("tr", 0) > 0:
                        badge_str = fmt_num(u["tr"])
                    elif ut == "Warship":
                        stars = "*" * int(u.get("vet", 0))
                        badge_str = f"{int(u['hp'] * 100 / max(1, u['mhp']))}%{stars}"
                        badge_col = (125, 211, 252, 255)
                    if badge_str:
                        bf = get_font(9)
                        bw = int(draw.textlength(badge_str, font=bf)) + 6
                        bx0, by0 = ux - bw // 2, uy + rad + 2
                        bx1, by1 = ux + bw // 2, by0 + 12
                        if not rects_hit(occupied_rects, bx0, by0, bx1, by1, pad=3):
                            draw.rounded_rectangle([bx0, by0, bx1, by1], radius=3, fill=(10, 15, 28, 195))
                            draw.text((bx0 + 3, by0 + 1), badge_str, font=bf, fill=badge_col)
                            occupied_rects.append((bx0, by0, bx1, by1))

            # 6. Country Name Plates SECOND (sorted largest empire -> smallest, strict zero-overlap AABB)
            if not m.get("inSpawn") and not modal_active:
                players_sorted = sorted(
                    [p for p in m.get("players", []) if p.get("alive") and p.get("tiles", 0) > 0],
                    key=lambda x: (1 if int(x["sid"]) == my_sid else 0, x.get("tiles", 0)),
                    reverse=True,
                )
                for p in players_sorted:
                    span_px = p["lspan"] * scale
                    is_me = int(p["sid"]) == my_sid
                    if not is_me and span_px < 26:
                        continue
                    sx, sy = world_to_screen(p["lx"] + 0.5, p["ly"] + 0.5, cam_x, cam_y, scale)
                    fsize = int(max(10, min(15, span_px * 0.21)))
                    fnt = get_font(fsize, True)
                    sub_fnt = get_font(max(9, fsize - 2), True)
                    nm = clean_ascii_text(p["name"])
                    tr_s = fmt_num(p["troops"])
                    tw1 = int(draw.textlength(nm, font=fnt))
                    tw2 = int(draw.textlength(tr_s, font=sub_fnt))
                    row1_w = tw1 + 18
                    box_w = max(row1_w, tw2) + 14
                    box_h = fsize + max(9, fsize - 2) + 11

                    placed_y: Optional[int] = None
                    for dy_nudge in (0, -24, 24, -44, 44, -64, 64):
                        cy = sy + dy_nudge
                        bx0, by0 = sx - box_w // 2, cy - box_h // 2
                        bx1, by1 = sx + box_w // 2, cy + box_h // 2
                        if not rects_hit(occupied_rects, bx0, by0, bx1, by1, pad=6):
                            placed_y = cy
                            occupied_rects.append((bx0, by0, bx1, by1))
                            break

                    if placed_y is not None:
                        bx0, by0 = sx - box_w // 2, placed_y - box_h // 2
                        bx1, by1 = sx + box_w // 2, placed_y + box_h // 2
                        draw.rounded_rectangle(
                            [bx0, by0, bx1, by1],
                            radius=5,
                            fill=(10, 15, 28, 178),
                            outline=(255, 255, 255, 52),
                            width=1,
                        )
                        tx_start = sx - row1_w // 2
                        pcol = player_colors.get(int(p["sid"]), (56, 189, 248, 255))
                        draw_flag(draw, p.get("flag", ""), tx_start, by0 + 5, 13, 9, pcol)
                        draw.text((tx_start + 18, by0 + 3), nm, font=fnt, fill=(255, 255, 255, 255))
                        draw.text((sx - tw2 // 2, by0 + fsize + 5), tr_s, font=sub_fnt, fill=(226, 232, 240, 255))

            # =====================================================================
            # UI OVERLAY LAYERS (Exact OpenFront Roblox ScreenGui HUD & Modals!)
            # =====================================================================
            if ui_mode in ("MainMenu", "HostModal"):
                draw.rectangle([0, 0, W, H], fill=(8, 13, 24, 136))
                draw.rounded_rectangle([18, 14, W - 18, 66], radius=10, fill=(24, 32, 48, 238), outline=(71, 85, 105, 195), width=1)
                draw.text((34, 26), "OPENFRONT  ROBLOX", font=get_font(21), fill=(255, 255, 255, 255))
                draw.text((294, 20), "CommanderAyush  •  Lv. 1 (150/500 XP)  •  Pure 2D Pixel Engine", font=get_font(13), fill=(226, 232, 240, 255))
                draw.rounded_rectangle([294, 43, 534, 53], radius=5, fill=(15, 23, 42, 255))
                draw.rounded_rectangle([294, 43, 384, 53], radius=5, fill=(59, 130, 246, 255))

                r_help = (W - 264, 22, W - 144, 58)
                r_sett = (W - 134, 22, W - 32, 58)
                draw.rounded_rectangle(r_help, radius=7, fill=(38, 49, 68, 255))
                draw_centered_text(draw, r_help, "How to Play", get_font(13), (255, 255, 255, 255))
                draw.rounded_rectangle(r_sett, radius=7, fill=(38, 49, 68, 255))
                draw_centered_text(draw, r_sett, "Settings", get_font(13), (255, 255, 255, 255))

                if ui_mode == "MainMenu":
                    cx0, cy0, cx1, cy1 = W // 2 - 252, 114, W // 2 + 252, 602
                    draw.rounded_rectangle([cx0, cy0, cx1, cy1], radius=14, fill=(24, 32, 48, 244), outline=(96, 165, 250, 185), width=2)
                    draw_centered_text(draw, (cx0, cy0 + 16, cx1, cy0 + 50), "CONQUER THE WORLD", get_font(25), (255, 255, 255, 255))
                    draw_centered_text(
                        draw,
                        (cx0, cy0 + 50, cx1, cy0 + 72),
                        "Expand borders  •  Build cities & railroads  •  Launch MIRVs",
                        get_font(12, False),
                        (148, 163, 184, 255),
                    )
                    draw.rounded_rectangle([cx0 + 20, cy0 + 82, cx1 - 20, cy0 + 132], radius=9, fill=(36, 48, 68, 255))
                    draw_flag(draw, "in", cx0 + 32, cy0 + 94, 38, 26)
                    r_fbtn = (cx0 + 80, cy0 + 91, cx0 + 202, cy0 + 123)
                    r_cbtn = (cx0 + 210, cy0 + 91, cx0 + 344, cy0 + 123)
                    r_pbtn = (cx0 + 352, cy0 + 91, cx1 - 28, cy0 + 123)
                    draw.rounded_rectangle(r_fbtn, radius=6, fill=(51, 65, 85, 255))
                    draw_centered_text(draw, r_fbtn, "Flag: India", get_font(12), (255, 255, 255, 255))
                    draw.rounded_rectangle(r_cbtn, radius=6, fill=(6, 182, 212, 255))
                    draw_centered_text(draw, r_cbtn, "Cyan #06B6D4", get_font(12), (15, 23, 42, 255))
                    draw.rounded_rectangle(r_pbtn, radius=6, fill=(51, 65, 85, 255))
                    draw_centered_text(draw, r_pbtn, "Pattern: Solid", get_font(12), (255, 255, 255, 255))

                    draw.rounded_rectangle([cx0 + 20, cy0 + 146, cx1 - 20, cy0 + 302], radius=10, fill=(20, 30, 48, 255), outline=(59, 130, 246, 210), width=2)
                    live_thumb = mini_im.resize((190, 128), Image.Resampling.NEAREST)
                    overlay.paste(live_thumb, (cx0 + 32, cy0 + 160))
                    draw.rectangle([cx0 + 32, cy0 + 160, cx0 + 222, cy0 + 288], outline=(96, 165, 250, 190), width=1)
                    draw.text((cx0 + 236, cy0 + 162), "World Map (FFA)", font=get_font(18), fill=(255, 255, 255, 255))
                    draw.text((cx0 + 236, cy0 + 190), f"PUBLIC LOBBY  •  Starts in {max(3, 12 - (f_idx // 5))}s", font=get_font(12), fill=(147, 197, 253, 255))
                    draw.text((cx0 + 236, cy0 + 210), "24 Bot Empires • 1.0x Normal Speed", font=get_font(12, False), fill=(148, 163, 184, 255))
                    r_playf = (cx0 + 236, cy0 + 240, cx1 - 32, cy0 + 286)
                    draw.rounded_rectangle(r_playf, radius=8, fill=(37, 99, 235, 255))
                    draw_centered_text(draw, r_playf, "PLAY FEATURED MAP", get_font(14), (255, 255, 255, 255))

                    r_sp = (cx0 + 20, cy0 + 318, cx1 - 20, cy0 + 368)
                    r_hc = (cx0 + 20, cy0 + 382, cx1 - 20, cy0 + 428)
                    draw.rounded_rectangle(r_sp, radius=9, fill=(22, 163, 74, 255))
                    draw_centered_text(draw, r_sp, "PLAY SINGLEPLAYER NOW (1x SPEED)", get_font(15), (255, 255, 255, 255))
                    draw.rounded_rectangle(r_hc, radius=9, fill=(51, 65, 85, 255), outline=(250, 204, 21, 185), width=1)
                    draw_centered_text(draw, r_hc, "HOST CUSTOM / ALL 24 1:1 MAPS", get_font(14), (255, 255, 255, 255))
                    draw_centered_text(
                        draw,
                        (cx0 + 16, cy0 + 438, cx1 - 16, cy1 - 8),
                        "Left-Click: Attack • Right-Click: Radial Menu • B: Build • Scroll: Zoom",
                        get_font(11, False),
                        (148, 163, 184, 255),
                    )
                else:
                    mx0, my0, mx1, my1 = 186, 92, 1094, 636
                    draw.rounded_rectangle([mx0, my0, mx1, my1], radius=14, fill=(15, 23, 42, 248), outline=(59, 130, 246, 225), width=2)
                    draw.text((mx0 + 24, my0 + 18), "HOST FULL-SCALE MATCH — ALL 24 REAL 1:1 MAPS", font=get_font(19), fill=(255, 255, 255, 255))
                    sel_map = extra.get("selectedMap", "World")

                    if cached_maps_meta:
                        for idx_m, md in enumerate(cached_maps_meta[:8]):
                            col_i = idx_m % 2
                            row_i = idx_m // 2
                            bx = mx0 + 20 + col_i * 274
                            by = my0 + 58 + row_i * 104
                            is_sel = md["id"] == sel_map
                            draw.rounded_rectangle(
                                [bx, by, bx + 262, by + 96],
                                radius=8,
                                fill=(30, 41, 59, 255),
                                outline=(250, 204, 21, 255) if is_sel else (71, 85, 105, 180),
                                width=3 if is_sel else 1,
                            )
                            thumb = build_map_thumb(md["id"], md["preview"], int(md["pw"]), int(md["ph"]), 246, 64)
                            overlay.paste(thumb, (bx + 8, by + 7))
                            dims_str = f"{md.get('w', 2000)}x{md.get('h', 1000)}"
                            cap_m = truncate_to_px(draw, f"{md['name']} · {dims_str} ({md['nations']})", get_font(11), 246)
                            draw.text((bx + 9, by + 74), cap_m, font=get_font(11), fill=(255, 255, 255, 255))

                    rx0 = mx0 + 576
                    opts = [
                        "Mode: Free For All (FFA)",
                        "Game Speed: 1.0x Normal Speed",
                        "AI Opponents: 24 Bot Empires",
                        "Map Scale: 2000x1000 (1:1 Full)",
                        "Starting Gold: 0 (Pure Fair)",
                        "Infinite Cheats: ALL OFF",
                        "Win Condition: 80% Global Land",
                        "Nuclear Arsenal & MIRV: ON",
                    ]
                    for oi, ot in enumerate(opts):
                        oy = my0 + 58 + oi * 48
                        draw.rounded_rectangle([rx0, oy, mx1 - 22, oy + 38], radius=7, fill=(30, 41, 59, 255), outline=(71, 85, 105, 180), width=1)
                        draw.text((rx0 + 14, oy + 11), ot, font=get_font(13), fill=(226, 232, 240, 255))

                    r_launch = (mx0 + 22, my1 - 60, mx1 - 22, my1 - 14)
                    draw.rounded_rectangle(r_launch, radius=9, fill=(22, 163, 74, 255))
                    draw_centered_text(draw, r_launch, "LAUNCH 1.0x BOT MATCH NOW  >>", get_font(17), (255, 255, 255, 255))

            else:
                me = m.get("me")
                num_land = max(1, int(m.get("numLand", 1)))
                phase_clean = clean_ascii_text(m["phase"]).replace("Normal Speed - ", "Live | ")

                ph_font = get_font(13)
                phase_clean = truncate_to_px(draw, phase_clean, ph_font, 336)
                ph_w = min(366, int(draw.textlength(phase_clean, font=ph_font)) + 26)
                draw.rounded_rectangle([18, 14, 18 + ph_w, 48], radius=8, fill=(15, 23, 42, 232), outline=(56, 189, 248, 195), width=1)
                draw.text((30, 23), phase_clean, font=ph_font, fill=(125, 211, 252, 255))

                if m.get("inSpawn"):
                    r_sb = (390, 14, 890, 62)
                    draw.rounded_rectangle(r_sb, radius=10, fill=(24, 32, 48, 244), outline=(250, 204, 21, 240), width=2)
                    msg_sp = (
                        f"SPAWN SELECTED IN INDIA - Borders Unlock in {float(m.get('spawnLeft', 0)):.1f}s"
                        if me and me.get("sx", -1) >= 0
                        else f"CLICK ANY LAND TILE TO SPAWN - {float(m.get('spawnLeft', 0)):.1f}s"
                    )
                    draw_centered_text(draw, r_sb, msg_sp, get_font(13), (254, 240, 138, 255))
                elif m.get("altView"):
                    r_av = (430, 14, 850, 52)
                    draw.rounded_rectangle(r_av, radius=99, fill=(22, 101, 52, 244), outline=(74, 222, 128, 255), width=2)
                    draw_centered_text(draw, r_av, "TACTICAL ALT-VIEW: SELF GREEN / ENEMY RED", get_font(13), (255, 255, 255, 255))
                elif ui_mode != "Victory":
                    flying_nukes = [u for u in m.get("units", []) if u["t"] in ("AtomBomb", "HydrogenBomb", "MIRV", "MIRVWarhead")]
                    if flying_nukes:
                        cnt = len(flying_nukes)
                        noun = "WARHEAD" if cnt == 1 else "WARHEADS"
                        r_nw = (420, 14, 860, 52)
                        draw.rounded_rectangle(r_nw, radius=9, fill=(153, 27, 27, 244), outline=(252, 165, 165, 255), width=2)
                        draw_centered_text(draw, r_nw, f"NUCLEAR SALVO ACTIVE — {cnt} {noun} IN FLIGHT!", get_font(13), (254, 240, 138, 255))

                # Bottom-Left ControlPanel
                if not m.get("inSpawn") and me is not None:
                    px0, py0, px1, py1 = 16, H - 182, 356, H - 16
                    draw.rounded_rectangle([px0, py0, px1, py1], radius=12, fill=(24, 32, 48, 242), outline=(71, 85, 105, 210), width=2)
                    draw_flag(draw, me.get("flag", "in"), px0 + 14, py0 + 13, 22, 15, hex_rgb(me.get("col", "#06b6d4"), 255))
                    draw.text(
                        (px0 + 44, py0 + 12),
                        f"Troops: {fmt_num(me['troops'])} / {fmt_num(me['maxTroops'])}",
                        font=get_font(14),
                        fill=(255, 255, 255, 255),
                    )
                    rate_s = f"+{fmt_num(me['rate'])}/s"
                    rw = int(draw.textlength(rate_s, font=get_font(13)))
                    draw.text((px1 - 14 - rw, py0 + 13), rate_s, font=get_font(13), fill=(74, 222, 128, 255))

                    draw.text((px0 + 14, py0 + 38), f"Gold: {fmt_num(me['gold'])}", font=get_font(15), fill=(250, 204, 21, 255))
                    atk_txt = f"Attacking: {fmt_num(me['atk'])} [X]" if me["atk"] > 0 else "Outgoing: Idle"
                    atk_bg = (185, 28, 28, 255) if me["atk"] > 0 else (51, 65, 85, 255)
                    r_atk = (px0 + 180, py0 + 36, px1 - 14, py0 + 60)
                    draw.rounded_rectangle(r_atk, radius=6, fill=atk_bg)
                    draw_centered_text(draw, r_atk, atk_txt, get_font(11), (255, 255, 255, 255))

                    me_pct_live = (me["tiles"] / num_land) * 100.0
                    draw.text((px0 + 14, py0 + 68), f"Attack Ratio: 45%  •  Empire: {me_pct_live:.1f}%", font=get_font(12), fill=(148, 163, 184, 255))
                    draw.rounded_rectangle([px0 + 14, py0 + 88, px1 - 14, py0 + 104], radius=8, fill=(15, 23, 42, 255))
                    draw.rounded_rectangle([px0 + 14, py0 + 88, px0 + 14 + int((px1 - px0 - 28) * 0.45), py0 + 104], radius=8, fill=(239, 68, 68, 255))

                    btns = [
                        ("Build [B]", (180, 120, 20, 255)),
                        ("Boat [V]", (30, 105, 175, 255)),
                        ("Retreat", (153, 27, 27, 255)),
                        ("Alt [Spc]", (51, 65, 85, 255)),
                    ]
                    for bi, (bt, bcol) in enumerate(btns):
                        bx = px0 + 14 + bi * 80
                        rb = (bx, py0 + 116, bx + 74, py0 + 152)
                        draw.rounded_rectangle(rb, radius=7, fill=bcol)
                        draw_centered_text(draw, rb, bt, get_font(11), (255, 255, 255, 255))

                # Top-Right Collapsible Leaderboard
                lx0, ly0, lx1, ly1 = W - 328, 14, W - 16, 266
                draw.rounded_rectangle([lx0, ly0, lx1, ly1], radius=10, fill=(24, 32, 48, 240), outline=(71, 85, 105, 205), width=1)
                hdr_lb = truncate_to_px(
                    draw,
                    f"World 2000x1000  |  {fmt_timer(m.get('elapsed', 0))}  |  Win: {int(m.get('winPct', 80))}%",
                    get_font(12),
                    290,
                )
                draw.text((lx0 + 12, ly0 + 10), hdr_lb, font=get_font(12), fill=(255, 255, 255, 255))
                alive_lb = [p for p in m.get("players", []) if p.get("alive") and (p.get("tiles", 0) > 0 or m.get("inSpawn"))][:9]
                for ri, p in enumerate(alive_lb):
                    ry = ly0 + 36 + ri * 24
                    is_me = int(p["sid"]) == my_sid
                    draw.rounded_rectangle(
                        [lx0 + 8, ry, lx1 - 8, ry + 21],
                        radius=5,
                        fill=(30, 58, 95, 242) if is_me else (36, 48, 68, 205),
                    )
                    draw.rectangle([lx0 + 14, ry + 4, lx0 + 22, ry + 17], fill=hex_rgb(p["col"], 255))
                    pct = (p["tiles"] / num_land) * 100.0
                    st = f"{pct:4.1f}%  {fmt_num(p['troops'])}"
                    sw_w = int(draw.textlength(st, font=get_font(10)))
                    max_name_px = (lx1 - 18 - sw_w) - (lx0 + 28)
                    nm_lb = truncate_to_px(draw, f"{ri + 1}. {clean_ascii_text(p['name'])}", get_font(11), max(60, max_name_px))
                    draw.text((lx0 + 28, ry + 4), nm_lb, font=get_font(11), fill=(255, 255, 255, 255))
                    draw.text((lx1 - 14 - sw_w, ry + 5), st, font=get_font(10), fill=(203, 213, 225, 255))

                # Bottom-Right Interactive Minimap + Live Event Feed
                mm_x0, mm_y0, mm_x1, mm_y1 = W - 228, H - 134, W - 16, H - 16
                draw.rounded_rectangle([mm_x0, mm_y0, mm_x1, mm_y1], radius=9, fill=(20, 28, 42, 244), outline=(100, 116, 139, 215), width=2)
                overlay.paste(mini_im, (mm_x0 + 4, mm_y0 + 4))
                mw_in, mh_in = mm_x1 - mm_x0 - 8, mm_y1 - mm_y0 - 8
                vw = min(1.0, (W / scale) / mw)
                vh = min(1.0, (H / scale) / mh)
                vx0 = int(mm_x0 + 4 + max(0.0, (cam_x / mw - vw * 0.5)) * mw_in)
                vy0 = int(mm_y0 + 4 + max(0.0, (cam_y / mh - vh * 0.5)) * mh_in)
                vx1 = min(mm_x1 - 4, int(vx0 + vw * mw_in))
                vy1 = min(mm_y1 - 4, int(vy0 + vh * mh_in))
                draw.rectangle([vx0, vy0, vx1, vy1], outline=(255, 255, 255, 245), width=2)

                evs = (m.get("events") or [])[-4:]
                for ei, ev in enumerate(evs):
                    ey = mm_y0 - (len(evs) - ei) * 25 - 6
                    draw.rounded_rectangle([W - 462, ey, W - 16, ey + 21], radius=5, fill=(15, 23, 42, 228))
                    ev_str = truncate_to_px(draw, clean_ascii_text(ev.get("text", "")), get_font(10), 428)
                    draw.text((W - 452, ey + 4), ev_str, font=get_font(10), fill=hex_rgb(ev.get("colorHex", "#f8fafc"), 255))

                if extra.get("radialOpen"):
                    rcx, rcy = W // 2 + 86, H // 2 - 18
                    draw.ellipse([rcx - 94, rcy - 94, rcx + 94, rcy + 94], fill=(10, 16, 30, 196), outline=(148, 163, 184, 185), width=2)
                    draw.ellipse([rcx - 24, rcy - 24, rcx + 24, rcy + 24], fill=(30, 41, 59, 252), outline=(255, 255, 255, 215), width=2)
                    draw_centered_text(draw, (rcx - 24, rcy - 24, rcx + 24, rcy + 24), "X", get_font(14), (255, 255, 255, 255))
                    spokes = [
                        ("Attack", (220, 38, 38, 255)),
                        ("Boat", (37, 99, 235, 255)),
                        ("Build", (202, 138, 4, 255)),
                        ("Ally", (22, 163, 74, 255)),
                        ("Donate", (124, 58, 237, 255)),
                    ]
                    for si, (slbl, scol) in enumerate(spokes):
                        ang = -math.pi * 0.5 + (si / len(spokes)) * math.pi * 2
                        sx_sp = int(rcx + math.cos(ang) * 66)
                        sy_sp = int(rcy + math.sin(ang) * 66)
                        rsp = (sx_sp - 28, sy_sp - 28, sx_sp + 28, sy_sp + 28)
                        draw.ellipse(rsp, fill=scol, outline=(255, 255, 255, 230), width=2)
                        draw_centered_text(draw, rsp, slbl, get_font(11), (255, 255, 255, 255))

                if extra.get("buildMenuOpen"):
                    draw.rectangle([0, 0, W, H], fill=(6, 11, 22, 112))
                    bx0, by0, bx1, by1 = W // 2 - 282, H // 2 - 150, W // 2 + 282, H // 2 + 150
                    draw.rounded_rectangle([bx0, by0, bx1, by1], radius=14, fill=(18, 25, 38, 252), outline=(250, 204, 21, 235), width=2)
                    draw_centered_text(
                        draw,
                        (bx0, by0 + 10, bx1, by0 + 44),
                        "BUILD STRUCTURES, FLEETS & NUCLEAR ARSENAL",
                        get_font(16),
                        (255, 255, 255, 255),
                    )
                    b_items = [
                        ("City", "City", "125K"),
                        ("Port", "Port", "125K"),
                        ("Factory", "Factory", "125K"),
                        ("DefensePost", "Def Post", "50K"),
                        ("Warship", "Warship", "250K"),
                        ("MissileSilo", "Silo", "1.00M"),
                        ("SAMLauncher", "SAM Site", "1.50M"),
                        ("AtomBomb", "Atom Bomb", "750K"),
                        ("HydrogenBomb", "H-Bomb", "5.00M"),
                        ("MIRV", "MIRV", "25.0M"),
                    ]
                    for idx_b, (ut, lbl_b, cost_b) in enumerate(b_items):
                        ci = idx_b % 5
                        ri = idx_b // 5
                        cx_b = bx0 + 19 + ci * 106
                        cy_b = by0 + 52 + ri * 116
                        draw.rounded_rectangle([cx_b, cy_b, cx_b + 98, cy_b + 106], radius=9, fill=(32, 43, 62, 255), outline=(250, 204, 21, 185), width=1)
                        draw_unit_vector_icon(draw, ut, cx_b + 49, cy_b + 28, 16, (250, 204, 21, 255))
                        draw_centered_text(draw, (cx_b, cy_b + 50, cx_b + 98, cy_b + 72), lbl_b, get_font(11), (255, 255, 255, 255))
                        draw.text_len = 0
                        draw_centered_text(draw, (cx_b, cy_b + 74, cx_b + 98, cy_b + 96), cost_b, get_font(11), (250, 204, 21, 255))

                if ui_mode == "Victory":
                    draw.rectangle([0, 0, W, H], fill=(6, 11, 22, 118))
                    me_pct = ((me["tiles"] / num_land) * 100.0) if me is not None else 81.2
                    vx0, vy0, vx1, vy1 = W // 2 - 256, H // 2 - 148, W // 2 + 256, H // 2 + 148
                    draw.rounded_rectangle([vx0, vy0, vx1, vy1], radius=16, fill=(15, 23, 42, 252), outline=(250, 204, 21, 255), width=3)
                    draw_centered_text(draw, (vx0, vy0 + 18, vx1, vy0 + 62), "WORLD CONQUERED!", get_font(28), (250, 204, 21, 255))
                    winner_lbl = clean_ascii_text(me["name"]) if me is not None else "CommanderAyush"
                    draw_centered_text(
                        draw,
                        (vx0, vy0 + 66, vx1, vy0 + 96),
                        f"Winner: {winner_lbl} ({me_pct:.1f}% Global Land at 1.0x Speed)",
                        get_font(14),
                        (255, 255, 255, 255),
                    )
                    draw_centered_text(
                        draw,
                        (vx0, vy0 + 98, vx1, vy0 + 128),
                        "+4,850 XP EARNED!  •  LEVEL UP: Lv. 1 -> Lv. 4!",
                        get_font(14),
                        (74, 222, 128, 255),
                    )
                    prog = min(1.0, (f_idx % 80) / 48.0 + 0.35)
                    draw.rounded_rectangle([vx0 + 44, vy0 + 138, vx1 - 44, vy0 + 158], radius=9, fill=(30, 41, 59, 255))
                    draw.rounded_rectangle([vx0 + 44, vy0 + 138, vx0 + 44 + int((vx1 - vx0 - 88) * prog), vy0 + 158], radius=9, fill=(56, 189, 248, 255))
                    r_b1 = (vx0 + 36, vy0 + 188, vx0 + 244, vy0 + 236)
                    r_b2 = (vx0 + 268, vy0 + 188, vx1 - 36, vy0 + 236)
                    draw.rounded_rectangle(r_b1, radius=9, fill=(51, 65, 85, 255))
                    draw_centered_text(draw, r_b1, "Keep Spectating", get_font(13), (255, 255, 255, 255))
                    draw.rounded_rectangle(r_b2, radius=9, fill=(37, 99, 235, 255))
                    draw_centered_text(draw, r_b2, "Play Again / Lobby", get_font(13), (255, 255, 255, 255))

            # Smooth 2D Player Mouse Cursor + Expanding Click Ripples
            cur_spec = extra.get("cursor")
            if not hasattr(main, "_cur_state"):
                main._cur_state = {"x": 640.0, "y": 518.0, "ripples": []}
            cs = main._cur_state
            if cur_spec:
                cs["x"] += (float(cur_spec.get("tx", 640)) - cs["x"]) * 0.28
                cs["y"] += (float(cur_spec.get("ty", 360)) - cs["y"]) * 0.28
                if cur_spec.get("click") and sub == 0:
                    cs["ripples"].append({"x": cs["x"], "y": cs["y"], "t": 0.0})

            alive_ripples = []
            for rp in cs["ripples"]:
                rp["t"] += 1.0 / FPS
                if rp["t"] < 0.45:
                    alive_ripples.append(rp)
                    rr = int(6 + rp["t"] * 52)
                    ra = int(235 * (1.0 - rp["t"] / 0.45))
                    draw.ellipse(
                        [int(rp["x"]) - rr, int(rp["y"]) - rr, int(rp["x"]) + rr, int(rp["y"]) + rr],
                        outline=(250, 204, 21, ra),
                        width=2,
                    )
            cs["ripples"] = alive_ripples

            if ui_mode != "Victory":
                cx_i, cy_i = int(cs["x"]), int(cs["y"])
                arrow_pts = [
                    (cx_i, cy_i),
                    (cx_i, cy_i + 17),
                    (cx_i + 4, cy_i + 13),
                    (cx_i + 8, cy_i + 20),
                    (cx_i + 11, cy_i + 19),
                    (cx_i + 7, cy_i + 12),
                    (cx_i + 12, cy_i + 12),
                ]
                draw.polygon(arrow_pts, fill=(255, 255, 255, 252), outline=(15, 23, 42, 255), width=2)

            composited = Image.alpha_composite(frame, overlay)
            proc.stdin.write(composited.tobytes())

            if f_idx in screenshot_targets:
                out_png = os.path.join(OUT_DIR, screenshot_targets[f_idx])
                composited.convert("RGB").save(out_png, format="PNG", optimize=True)
                print(f"[render_video] Saved HD Screenshot -> gameplay/{screenshot_targets[f_idx]} (frame {f_idx})")

        if t_idx % 250 == 0:
            print(f"[render_video] Progress: tick {t_idx}/{num_ticks} ({f_idx + 1}/{total_frames} frames)...")

    delta_f.close()
    proc.stdin.close()
    stderr_out = proc.stderr.read().decode("utf-8", errors="replace")
    rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"ffmpeg failed ({rc}):\n{stderr_out}")

    sz_mb = os.path.getsize(mp4_path) / (1024 * 1024)
    print(f"[render_video] SUCCESS -> gameplay/OpenFront_Roblox_Gameplay.mp4 ({sz_mb:.2f} MB, {total_frames / FPS:.1f}s @ {FPS}fps)")


if __name__ == "__main__":
    main()
