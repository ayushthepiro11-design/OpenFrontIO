#!/usr/bin/env python3
"""Draws assets/maps/shinobiworld/image.png (and the nation spawn points).

All artwork is generated procedurally from primitives (polygons, fractal noise,
domain-warped distance fields), so the result is original art and not traced
from any copyrighted map.

Geometry follows the Naruto setting: the five great nations (Fire in the
centre, Earth north-west, Lightning north-east, Wind south-west, Water as an
archipelago in the east) with the minor nations wedged between them.

Requires numpy, scipy and pillow:

    pip install numpy scipy pillow
    python3 draw_image.py --write ../assets/maps/shinobiworld

Then regenerate the binaries from the repo root with `npm run gen-maps`.

The blue channel is the only channel the map generator reads, so the output is
written as an RGB image whose blue value encodes terrain + elevation
(140-200 = land elevation 0-30, 106 = ocean).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

W = H = 1500
SEED = 20261020
OUT_DIR = "."
for i, arg in enumerate(sys.argv):
    if arg in ("--write", "-w") and i + 1 < len(sys.argv):
        OUT_DIR = sys.argv[i + 1]

rng = np.random.default_rng(SEED)


# ── fractal value noise ──────────────────────────────────────────────────────
def fbm(shape, cells, octaves=5, persistence=0.5, seed=0):
    """Fractal value noise in [0, 1]."""
    r = np.random.default_rng(seed)
    out = np.zeros(shape, dtype=np.float64)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = max(2, int(cells * (2**o)))
        grid = r.random((c + 1, c + 1))
        zoomed = ndimage.zoom(grid, (shape[0] / c, shape[1] / c), order=3)
        zoomed = zoomed[: shape[0], : shape[1]]
        if zoomed.shape != shape:
            zoomed = np.pad(
                zoomed,
                ((0, shape[0] - zoomed.shape[0]), (0, shape[1] - zoomed.shape[1])),
                mode="edge",
            )
        out += amp * zoomed
        total += amp
        amp *= persistence
    return out / total


def norm(a):
    lo, hi = np.min(a), np.max(a)
    return (a - lo) / (hi - lo) if hi > lo else np.zeros_like(a)


# ── land shapes ─────────────────────────────────────────────────────────────
def blob_mask(blobs, size=W):
    """Rasterise a union of (cx, cy, rx, ry, angle) ellipses."""
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    for cx, cy, rx, ry, ang in blobs:
        pts = []
        for t in np.linspace(0, 2 * math.pi, 96, endpoint=False):
            x = rx * math.cos(t)
            y = ry * math.sin(t)
            xr = x * math.cos(ang) - y * math.sin(ang)
            yr = x * math.sin(ang) + y * math.cos(ang)
            pts.append((cx + xr, cy + yr))
        d.polygon(pts, fill=255)
    return np.asarray(img, dtype=np.float64) / 255.0


def warp_and_smooth(mask, amp, cells, seed, blur=2.2):
    """Organic coastline: domain-warp the mask, then blur + threshold."""
    ys, xs = np.mgrid[0:H, 0:W]
    dx = (fbm((H, W), cells, 4, 0.55, seed) - 0.5) * 2 * amp
    dy = (fbm((H, W), cells, 4, 0.55, seed + 1) - 0.5) * 2 * amp
    sx = np.clip(xs + dx, 0, W - 1).astype(np.int32)
    sy = np.clip(ys + dy, 0, H - 1).astype(np.int32)
    warped = mask[sy, sx]
    smooth = ndimage.gaussian_filter(warped, blur)
    return smooth > 0.5


def poly_mask(polys):
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for poly in polys:
        d.polygon([tuple(p) for p in poly], fill=255)
    return np.asarray(img, dtype=np.float64) / 255.0


# ── nations ────────────────────────────────────────────────────────────────
# name: (seed x, seed y, weight, base elevation, elevation amplitude)
NATIONS = {
    "Land of Earth": (330, 350, 265, 6, 4),
    "Land of Lightning": (975, 300, 235, 4, 4),
    "Land of Fire": (655, 715, 250, 2, 3),
    "Land of Wind": (300, 855, 250, 1, 2),
    "Land of Water": (1310, 780, 150, 3, 4),
    "Land of Iron": (610, 165, 95, 10, 4),
    "Land of Frost": (845, 165, 80, 6, 3),
    "Land of Hot Water": (905, 470, 78, 5, 5),
    "Land of Sound": (800, 545, 62, 4, 3),
    "Land of Waterfalls": (712, 450, 58, 8, 4),
    "Land of Grass": (545, 590, 72, 3, 4),
    "Land of Rain": (505, 700, 58, 5, 3),
    "Land of Stone": (150, 585, 70, 6, 3),
    "Land of Valley": (520, 925, 68, 5, 3),
    "Land of Rivers": (655, 960, 75, 3, 4),
    "Land of Tea": (825, 940, 62, 3, 4),
    "Land of Demons": (1000, 800, 62, 5, 3),
    "Land of Sky": (985, 600, 60, 6, 3),
    "Land of Bears": (430, 470, 60, 6, 3),
    "Land of Whirlpools": (1105, 1105, 55, 4, 4),
    "Land of Waves": (905, 1195, 45, 2, 3),
    "Land of the Sea": (430, 1215, 60, 3, 4),
}

ORDER = list(NATIONS)

# Desired land area (pixels) for each mainland nation; used to auto-balance the
# weighted Voronoi so no nation ends up a sliver. Islands are fixed geometry.
TARGET_AREA = {
    "Land of Earth": 148000,
    "Land of Lightning": 120000,
    "Land of Fire": 150000,
    "Land of Wind": 150000,
    "Land of Water": 80000,
    "Land of Iron": 44000,
    "Land of Frost": 34000,
    "Land of Hot Water": 27000,
    "Land of Sound": 21000,
    "Land of Waterfalls": 23000,
    "Land of Grass": 34000,
    "Land of Rain": 21000,
    "Land of Stone": 30000,
    "Land of Valley": 27000,
    "Land of Rivers": 40000,
    "Land of Tea": 26000,
    "Land of Demons": 26000,
    "Land of Sky": 26000,
    "Land of Bears": 23000,
    "Land of Whirlpools": 10000,
    "Land of Waves": 7000,
    "Land of the Sea": 17000,
}

ISLAND_OWNERS = ["Land of Water", "Land of Whirlpools", "Land of Waves", "Land of the Sea"]


def signed_field(mask, amp_large, amp_small, cells, seed):
    """Ragged, fjord-like coastline from a macro mask plus fractal noise."""
    inside = ndimage.distance_transform_edt(mask)
    outside = ndimage.distance_transform_edt(~mask.astype(bool))
    sdf = inside - outside
    big = (fbm((H, W), cells, 6, 0.55, seed) - 0.5) * 2
    small = (fbm((H, W), cells * 5, 3, 0.5, seed + 1) - 0.5) * 2
    return sdf + amp_large * big + amp_small * small


def clean_land(mask, min_component=80):
    mask = ndimage.binary_closing(mask, np.ones((3, 3)))
    mask = ndimage.binary_opening(mask, np.ones((3, 3)))
    mask = ndimage.binary_fill_holes(mask)
    lab, n = ndimage.label(mask, structure=np.ones((3, 3)))
    if n == 0:
        return mask
    sizes = ndimage.sum_labels(np.ones_like(lab), lab, index=np.arange(1, n + 1))
    keep = np.isin(lab, np.nonzero(sizes >= min_component)[0] + 1)
    return mask & keep


def draw_mask():
    """Continent silhouette + eastern archipelago, both procedurally eroded."""
    contour = [
        (110, 130), (300, 60), (470, 90), (600, 55), (760, 75), (930, 120),
        (1075, 195), (1170, 320), (1125, 425), (1175, 520), (1090, 605),
        (1135, 700), (1055, 790), (965, 870), (905, 965), (840, 1040),
        (720, 1075), (650, 1165), (520, 1190), (425, 1120), (330, 1165),
        (225, 1085), (145, 985), (90, 850), (55, 700), (72, 550), (55, 400),
        (85, 255),
    ]
    base = poly_mask([contour])
    bays = [
        (1155, 955, 205, 175, 0.0),
        (1060, 470, 105, 90, 0.0),
        (770, 1165, 175, 115, 0.0),
        (190, 1095, 150, 140, 0.0),
        (645, 375, 85, 62, 0.0),
        (520, 690, 70, 55, 0.0),
    ]
    base = np.clip(base - blob_mask(bays), 0, 1)
    field = signed_field(base, amp_large=52, amp_small=13, cells=6, seed=SEED + 11)
    land = clean_land(field > 0, min_component=120)

    islands = [
        # Land of Water archipelago (east)
        [(1170, 560), (1245, 520), (1320, 545), (1350, 620), (1310, 680),
         (1240, 690), (1185, 650)],
        [(1300, 720), (1400, 700), (1450, 780), (1435, 880), (1360, 905),
         (1290, 860), (1275, 780)],
        [(1200, 960), (1270, 930), (1330, 975), (1320, 1040), (1250, 1055),
         (1195, 1015)],
        [(1395, 950), (1460, 935), (1490, 990), (1455, 1030), (1395, 1015)],
        [(1140, 420), (1200, 400), (1225, 450), (1190, 500), (1135, 490)],
        # Land of Whirlpools
        [(1060, 1085), (1115, 1065), (1160, 1105), (1140, 1160), (1075, 1165),
         (1045, 1120)],
        # Land of Waves
        [(880, 1170), (930, 1155), (960, 1195), (925, 1235), (875, 1225)],
        [(840, 1235), (872, 1225), (884, 1258), (852, 1272)],
        [(950, 1240), (985, 1228), (1000, 1262), (968, 1278)],
        # Land of the Sea
        [(355, 1180), (440, 1160), (510, 1200), (495, 1265), (415, 1285),
         (350, 1255)],
        [(272, 1128), (312, 1112), (330, 1150), (292, 1172)],
    ]
    groups = {
        "Land of Water": islands[:5],
        "Land of Whirlpools": islands[5:6],
        "Land of Waves": islands[6:9],
        "Land of the Sea": islands[9:],
    }
    isl_masks = {}
    mainland_exclusion = ndimage.binary_dilation(land, np.ones((5, 5)))
    all_isl = np.zeros((H, W), dtype=bool)
    for name, polys in groups.items():
        m = poly_mask(polys) > 0.5
        f = signed_field(m, amp_large=17, amp_small=5, cells=22, seed=SEED + 12)
        m = clean_land(f > 0, min_component=350) & ~mainland_exclusion
        isl_masks[name] = m
        all_isl |= m
    return land, all_isl, isl_masks


# Hand-authored borders: every nation's outline is a polygon drawn in order,
# so later (smaller / central) nations overwrite the ones they sit inside.
BORDERS = {
    "Land of Earth": [(55, 55), (470, 55), (500, 290), (470, 420), (400, 470),
                      (300, 520), (200, 545), (120, 600), (55, 560)],
    "Land of Wind": [(55, 620), (240, 600), (360, 660), (430, 790), (450, 950),
                     (400, 1080), (330, 1150), (220, 1100), (120, 980), (55, 850)],
    "Land of Lightning": [(870, 55), (1170, 225), (1155, 420), (1075, 480),
                          (980, 520), (900, 470), (820, 330), (830, 150)],
    "Land of Iron": [(505, 55), (720, 55), (755, 200), (700, 300), (600, 320),
                     (525, 240)],
    "Land of Frost": [(720, 55), (895, 55), (915, 220), (860, 330), (780, 330),
                      (700, 300), (700, 200)],
    "Land of Bears": [(420, 360), (540, 335), (615, 370), (625, 440), (580, 505),
                      (480, 515), (430, 450)],
    "Land of Stone": [(55, 515), (185, 495), (240, 560), (230, 650), (170, 700),
                      (100, 680), (55, 620)],
    "Land of Waterfalls": [(618, 300), (722, 288), (775, 350), (762, 442),
                           (712, 502), (642, 482), (598, 400)],
    "Land of Hot Water": [(868, 415), (965, 398), (1045, 428), (1062, 520),
                          (1020, 600), (938, 618), (888, 558)],
    "Land of Sound": [(752, 465), (858, 448), (882, 540), (840, 612), (768, 622),
                      (738, 540)],
    "Land of Fire": [(540, 535), (680, 508), (792, 528), (872, 620), (892, 742),
                     (870, 842), (800, 920), (700, 952), (620, 918), (558, 828),
                     (518, 700)],
    "Land of Grass": [(478, 555), (582, 528), (662, 558), (672, 652), (620, 712),
                      (538, 702), (476, 650)],
    "Land of Rain": [(438, 658), (518, 638), (560, 700), (550, 782), (498, 822),
                     (448, 760)],
    "Land of Sky": [(948, 558), (1048, 548), (1090, 640), (1058, 722), (988, 742),
                    (948, 680)],
    "Land of Demons": [(875, 698), (958, 688), (1032, 740), (1042, 832),
                       (978, 892), (898, 870), (868, 778)],
    "Land of Valley": [(388, 858), (492, 848), (545, 908), (545, 982), (488, 1032),
                       (408, 1022), (368, 938)],
    "Land of Rivers": [(558, 928), (662, 898), (742, 938), (732, 1032),
                       (678, 1102), (598, 1090), (558, 1008)],
    "Land of Tea": [(758, 878), (858, 866), (902, 940), (878, 1012), (798, 1032),
                    (756, 968)],
}

# Paint order: outermost / largest first, smaller central nations overwrite.
PAINT_ORDER = [
    "Land of Earth", "Land of Wind", "Land of Lightning", "Land of Stone",
    "Land of Fire", "Land of Iron", "Land of Frost", "Land of Bears",
    "Land of Waterfalls", "Land of Hot Water", "Land of Sound", "Land of Grass",
    "Land of Rain", "Land of Sky", "Land of Demons", "Land of Valley",
    "Land of Rivers", "Land of Tea",
]


def voronoi_labels(land, isl_masks):
    """Rasterise the hand-authored borders, then domain-warp them so every
    frontier wriggles like a natural border instead of a straight polyline."""
    # -1 = not covered by any nation polygon yet.
    labels = np.full((H, W), -1, dtype=np.int16)
    for name in PAINT_ORDER:
        m = poly_mask([BORDERS[name]]) > 0.5
        labels[m] = ORDER.index(name)

    # Any remaining land (coast fringes, gaps between polygons) joins whichever
    # nation it is closest to, so borders stay continuous out to the sea.
    uncovered = labels < 0
    if uncovered.any():
        _, (iy, ix) = ndimage.distance_transform_edt(uncovered, return_indices=True)
        labels = labels[iy, ix]

    ys, xs = np.mgrid[0:H, 0:W]
    bx = ((fbm((H, W), 5, 4, 0.6, SEED + 21) - 0.5) * 2 * 26
          + (fbm((H, W), 18, 4, 0.55, SEED + 23) - 0.5) * 2 * 11)
    by = ((fbm((H, W), 5, 4, 0.6, SEED + 22) - 0.5) * 2 * 26
          + (fbm((H, W), 18, 4, 0.55, SEED + 24) - 0.5) * 2 * 11)
    sx = np.clip(xs + bx, 0, W - 1).astype(np.int32)
    sy = np.clip(ys + by, 0, H - 1).astype(np.int32)
    labels = labels[sy, sx]

    for name, mask in isl_masks.items():
        labels[mask] = ORDER.index(name)
    return labels


def nation_report(labels, land):
    areas = np.bincount(labels[land], minlength=len(ORDER))
    for idx, name in enumerate(ORDER):
        print(f"  {name:22s} area={areas[idx]:7d} target={TARGET_AREA[name]:7d} "
              f"({100 * areas[idx] / max(1, TARGET_AREA[name]):5.1f}%)")
    return areas


def ridge_field(points, width, strength, sharp=38.0):
    """Mountain range along `points`.

    Elevation falls off with distance from the polyline, but the distance is
    domain-warped and amplitude-modulated by noise, so the range grows uneven
    peaks, spurs and passes instead of reading as a smooth embankment.
    """
    canvas = Image.new("L", (W, H), 0)
    c = ImageDraw.Draw(canvas)
    for a, b in zip(points, points[1:]):
        c.line([tuple(a), tuple(b)], fill=255, width=width)
    for p in points:
        c.ellipse([p[0] - width / 2, p[1] - width / 2,
                   p[0] + width / 2, p[1] + width / 2], fill=255)
    masked = np.asarray(canvas) > 0
    d = ndimage.distance_transform_edt(~masked)

    warp = (fbm((H, W), 20, 4, 0.55, SEED + 41) - 0.5) * 2
    warp2 = (fbm((H, W), 55, 3, 0.5, SEED + 43) - 0.5) * 2
    dw = d + 16 * warp + 6 * warp2
    falloff = np.exp(-((dw / sharp) ** 2))

    amp = fbm((H, W), 12, 4, 0.55, SEED + 42)
    amp = 0.55 + 0.95 * amp
    return strength * falloff * amp


def draw_elevation(labels):
    """Low, gently rolling land with narrow mountain chains."""
    detail = norm(fbm((H, W), 16, 6, 0.55, SEED + 31))
    fine = norm(fbm((H, W), 52, 3, 0.5, SEED + 32))

    mag = np.zeros((H, W), dtype=np.float64)
    for idx, name in enumerate(ORDER):
        base, amp = NATIONS[name][3], NATIONS[name][4]
        sel = labels == idx
        mag[sel] = base + amp * (detail[sel] * 0.7 + fine[sel] * 0.3)

    chains = [
        ([(120, 165), (205, 245), (285, 320), (360, 385)], 13, 17.0),
        ([(180, 480), (280, 445), (360, 430)], 11, 11.0),           # Earth south
        ([(480, 130), (620, 112), (790, 125), (890, 175)], 12, 18.9),  # north wall
        ([(935, 240), (1010, 305), (1080, 395)], 14, 16.0),         # Lightning
        ([(880, 330), (862, 430), (845, 505)], 9, 12.8),           # Lightning south
        ([(695, 305), (720, 375), (733, 435)], 9, 11.0),           # Waterfalls
        ([(570, 335), (612, 415), (638, 490)], 8, 7.9),            # Bears rise
        ([(345, 650), (380, 720), (395, 780)], 9, 4.2),            # west shoulder
        ([(985, 725), (1010, 800), (1018, 858)], 8, 9.9),         # Demons
        ([(1305, 705), (1358, 762), (1388, 828)], 10, 12.0),        # Water volcano
        ([(1305, 955), (1350, 1000)], 7, 7.0),                     # Water south
        ([(240, 900), (320, 975), (370, 1040)], 15, 1.4),         # Wind dunes
        ([(605, 905), (678, 958), (728, 1015)], 8, 4.9),           # Rivers hills
        ([(1100, 1082), (1128, 1118)], 7, 4.9),                    # Whirlpools
        ([(882, 1182), (928, 1208)], 7, 2.9),                      # Waves
        ([(170, 620), (200, 665)], 7, 4.0),                         # Stone highland
        ([(755, 155), (825, 195), (875, 245)], 12, 18.7),           # Frost peaks
        ([(965, 255), (1025, 335), (1080, 405)], 14, 17.8),         # Lightning ridge
        ([(930, 380), (922, 445)], 8, 8.5),                        # Hot Water hills
        ([(700, 620), (760, 650), (800, 700)], 9, 7.0),            # Fire east rim
        ([(600, 760), (640, 820)], 8, 5.0),                        # Fire south
        ([(830, 470), (870, 500)], 7, 5.5),                        # Sound hills
        ([(980, 600), (1010, 620)], 7, 6.0),                       # Sky hills
        ([(1080, 730), (1120, 780)], 7, 5.0),                      # east coast
        ([(760, 950), (800, 990)], 7, 4.0),                        # Tea hills
        ([(640, 1080), (700, 1100)], 7, 4.0),                      # Rivers south
        ([(480, 960), (450, 1000)], 6, 4.0),                       # Valley hills
    ]
    # Chains overlap in dense areas; combine with a soft max so stacked
    # ranges do not pile into a single white plateau.
    ridge_total = np.zeros((H, W), dtype=np.float64)
    for pts, width, strength in chains:
        r = ridge_field(pts, width, strength)
        ridge_total = np.maximum(ridge_total, r)
    mag += ridge_total

    return np.clip(mag, 0, 30)


def main():
    land, isl, isl_masks = draw_mask()
    is_land = land | isl
    # Kill specks and fill pinholes so the generator has nothing to prune.
    is_land = ndimage.binary_opening(is_land, np.ones((3, 3)))
    is_land = ndimage.binary_closing(is_land, np.ones((3, 3)))
    is_land = ndimage.binary_fill_holes(is_land)

    labels = voronoi_labels(is_land, isl_masks)
    # Despeckle borders so no single-pixel nation dangling exists.
    nation_report(labels, is_land)
    # Keep only components that touch real land (island noise can leave specks).
    lab, n = ndimage.label(is_land, structure=np.ones((3, 3)))
    sizes = ndimage.sum_labels(np.ones_like(lab), lab, index=np.arange(1, n + 1))
    keep = np.isin(lab, np.nonzero(sizes >= 60)[0] + 1)
    is_land &= keep

    mag = draw_elevation(np.where(is_land, labels, 0))
    # Shoreline lowland: reduce height within ~12 px of the coast.
    dist_out = ndimage.distance_transform_edt(is_land)
    coast_fade = np.clip((dist_out - 4) / 22.0, 0, 1)
    mag = 3 + (mag - 3) * coast_fade
    mag[~is_land] = 0

    # Inland lakes.
    lake_img = Image.new("L", (W, H), 0)
    ld = ImageDraw.Draw(lake_img)
    lakes = [(585, 795, 40, 28), (392, 515, 43, 31), (1010, 380, 32, 23),
             (742, 872, 34, 25)]
    for cx, cy, rx, ry in lakes:
        pts = []
        for t in np.linspace(0, 2 * math.pi, 72, endpoint=False):
            wob = 1 + 0.28 * math.sin(3 * t + cx) + 0.18 * math.sin(5 * t + cy)
            pts.append((cx + rx * wob * math.cos(t), cy + ry * wob * math.sin(t)))
        ld.polygon(pts, fill=255)
    lake = (np.asarray(lake_img) > 0) & is_land
    lake = ndimage.binary_opening(lake, np.ones((3, 3)))

    blue = np.full((H, W), 106, dtype=np.uint8)  # water key colour
    land_blue = np.clip(140 + np.round(2 * mag), 140, 200).astype(np.uint8)
    blue[is_land] = land_blue[is_land]
    blue[lake] = 106

    img = Image.fromarray(np.stack([blue] * 3, axis=-1), mode="RGB")
    img.save(os.path.join(OUT_DIR, "image.png"))

    # ── spawn points: deepest interior pixel of each nation ──────────────────
    nations = []
    for idx, name in enumerate(ORDER):
        region = (labels == idx) & is_land & ~lake
        if not region.any():
            print("!! empty region", name)
            continue
        dt = ndimage.distance_transform_edt(region)
        # Prefer a roomy, land-locked spot; avoid mountains for spawn comfort.
        score = dt - 0.15 * mag
        score[~region] = -1e9
        y, x = np.unravel_index(np.argmax(score), score.shape)
        nations.append({"name": name, "coordinates": [int(x), int(y)], "flag": ""})
        print(f"{name:22s} -> [{x}, {y}]  area={int(region.sum())}")

    with open(os.path.join(OUT_DIR, "nations.json"), "w") as f:
        json.dump(nations, f, indent=2)

    # Debug preview with labels.
    prev = Image.fromarray(np.stack([blue] * 3, axis=-1), mode="RGB").convert("RGB")
    arr = np.asarray(prev).copy()
    pal = [
        (150, 111, 51), (222, 184, 135), (70, 130, 180), (178, 34, 34),
        (60, 179, 113), (105, 105, 105), (218, 165, 32), (32, 178, 170),
        (186, 85, 211), (210, 105, 30), (46, 139, 87), (100, 149, 237),
        (139, 90, 43), (255, 140, 0), (199, 21, 133), (0, 139, 139),
        (184, 134, 11), (106, 90, 205), (34, 139, 34), (72, 61, 139),
        (47, 79, 79), (165, 42, 42),
    ]
    palette = np.array(pal[: len(ORDER)], dtype=np.uint8)
    arr[is_land] = (0.55 * arr[is_land] + 0.45 * palette[labels[is_land]]).astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(OUT_DIR, "preview_labels.png"))

    print("land tiles:", int(is_land.sum()), "of", W * H)


if __name__ == "__main__":
    main()
