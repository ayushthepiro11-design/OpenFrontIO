# OpenFront for Roblox (1:1 Pure-2D Browser-Exact Edition)

A complete **1:1 Luau recreation of OpenFront (`openfront.io`)** built natively for **Roblox** — delivering **both** a ready-to-open **Roblox Studio `.rbxl` place file** (zero setup — open & press **Play**) **and** a cleanly structured modular **Rojo** project (`roblox/default.project.json`).

---

## Quick Start (Zero Setup — Open & Press Play)

### Option A: Open `OpenFront.rbxl` Directly in Roblox Studio (Fastest)

1. Launch **Roblox Studio** -> **File -> Open from File...**
2. Select **`OpenFront.rbxl`** (at repository root `/OpenFront.rbxl` or `roblox/OpenFront.rbxl`).
3. Press **Play (`F5`)**!
   - The live AI preview world battle and authentic **OpenFront Main Menu** appear immediately in pure full-viewport 2D (zero 3D Baseplate/Avatar clutter).
   - **Works immediately even before publishing!** If `EditableImage` is not yet enabled on an unpublished local file, `MapCanvas.luau` automatically activates its built-in **`ScanlineCanvas2D` RLE Renderer** seamlessly with zero errors.
4. _(Optional — Recommended when publishing to Roblox)_ In **Home -> Game Settings -> Security**:
   - Enable **Allow Mesh / Image APIs** to unlock the primary **native RGBA8 `EditableImage:WritePixelsBuffer` 1px WebGL-identical pixel shader**.
   - Enable **Enable Studio Access to API Services** to persist player XP, Levels, Prestige, Wins, Flags, Colors, and Territory Patterns to cloud `DataStoreService` (`OpenFront_PlayerData_v1`) during Studio testing.

### Option B: Sync Live with Rojo (`default.project.json`)

```bash
cd roblox
rojo serve default.project.json
# Or build a standalone .rbxl directly via Rojo or Python compiler:
python3 tools/build_rbxl.py
```

---

## Included Real OpenFront Maps (10 Maps — 1,300,610 Verified Tiles)

Exported directly from `/resources/maps/` via `roblox/tools/export_maps.py`:

1. **World Map** (`World`) — 59 pre-scripted historical nations
2. **Shinobi World** (`ShinobiWorld`) — Full custom Naruto/Shinobi continent & villages (`Konohagakure`, `Sunagakure`, `Kirigakure`, `Kumogakure`, `Iwagakure`, `Amegakure`, `Land of Iron`, `Uzushiogakure`, etc.)
3. **Europe** (`Europe`) — 48 nations
4. **North America** (`NorthAmerica`) — 45 nations
5. **Asia** (`Asia`) — 46 nations
6. **Africa** (`Africa`) — 52 nations
7. **South America** (`SouthAmerica`) — 28 nations
8. **Australia & Oceania** (`Australia`) — 20 nations
9. **Britannia** (`Britannia`) — 26 nations
10. **Black Sea** (`BlackSea`) — 24 nations

_(You can export any additional maps from `/resources/maps/` at any time by adding their IDs to `MAPS_TO_EXPORT` in `roblox/tools/export_maps.py` and running `python3 roblox/tools/export_maps.py && python3 roblox/tools/build_rbxl.py`.)_

---

## Complete Feature Parity Matrix

| System                      | Implemented Mechanics                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| :-------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pure 2D Canvas & Camera** | `IgnoreGuiInset = true` full-viewport 2D surface; `EditableImage` RGBA8 pixel shader (`ResampleMode.Pixelated`) + automatic per-row RLE `ScanlineCanvas2D` fallback; cursor-anchored scroll wheel zoom, drag pan, `WASD`/Arrows pan, 2-finger mobile pinch-to-zoom, Alt-View (`Space`), territory patterns, and interactive viewport Minimap.                                                                                                                                      |
| **Core Simulation (10 Hz)** | Exact OpenFront formulas from `Config.ts` & `EngineConfig.ts`: non-linear troop cap `2 * (tiles^0.6 * 1000 + 50,000) + cityBonus`, peak growth curve `(10 + troops^0.73 / 4) * (1 - troops / maxTroops)`, `FlatBinaryHeap` priority frontier expansion, elevation/traitor/DefensePost/fallout combat math, head-on attack cancellation, attack merging, pocket auto-collapse, `O(1)` border set updates, and `O(W*H)` **Maximal Inscribed Square** dynamic nation label placement. |
| **Structures & Economy**    | **City** (`+250,000` Max Troops + upgrades), **Port** (coastal A* **Trade Ships** with distance sigmoid + allied revenue bonus), **Factory** (automatic land A* **Railroad** network connecting hubs + **Gold Trains**), **Defense Post** (`5x` border defense aura), structure capture upon tile conquest, smart spiral placement snapping, upgrading, and deletion.                                                                                                              |
| **Naval Warfare**           | Amphibious **Transport Ship** invasions (`V` or Radial Menu), boat retreats, **Warship** construction & patrol relocation, shell combat against enemy boats/warships, **Trade Ship piracy**, passive port healing, and 3-star **Veterancy** progression.                                                                                                                                                                                                                           |
| **Nuclear & Air Defense**   | **Missile Silo** cooldown scaling by level, **Atom Bomb** (`☢️`), **Hydrogen Bomb** (`💥`), **MIRV** (`☄️` ballistic arc splitting at apex into multi-warhead carpet strikes across the target empire), pulsing red ground blast rings, expanding shockwaves, radioactive **Fallout** stamping & decay, and **SAM Launcher** rational range curve (`150x / (x + 2)`) launching **SAM Missiles** for mid-air interception.                                                          |
| **Diplomacy, AI & Modes**   | Pre-scripted **AI Nations** (`Easy`, `Medium`, `Hard`, `Impossible`) + **Minor Bots**, 5-minute **Alliances**, renewal prompts, **Betrayal / Traitor** debuff (`💀 50%` defense for `30s`), **Trade Embargoes**, **Gold & Troop Donations**, **Target Pings**, **Emojis**, **Quick Chat**, **FFA / 2–4 Teams / Humans vs Nations**, **Doomsday Clock**, **Overtime**, **80% Conquest Victory**, and persistent **`DataStoreService` XP / Level / Prestige** progression.           |

---

## Controls Reference (Desktop & Mobile)

| Input                                     | Action                                                                                                                              |
| :---------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------- |
| **Left Click / Tap**                      | Pick spawn spot (Spawn Phase), expand into unclaimed land, attack rival territory, place armed unit, or select/relocate own Warship |
| **Right Click / Long-Press**              | Open circular **OpenFront Radial Menu** (`Attack`, `Boat`, `Build`, `Ally/Betray`, `Info/Donate`, `Upgrade`, `Delete`)              |
| **Ctrl + Click** or **`B`**               | Open **Build & Nuclear Arsenal Menu**                                                                                               |
| **Scroll Wheel / Two-Finger Pinch**       | Cursor-anchored Zoom In / Out (`+` / `-` keys also supported)                                                                       |
| **Drag / Middle Mouse / `WASD` / Arrows** | Smooth 2D Map Pan                                                                                                                   |
| **`Q` / `E`** or **`1`–`9`**              | Adjust Attack Ratio (`10%`–`90%` or `-10%` / `+10%`)                                                                                |
| **`V`**                                   | Arm Amphibious Boat Invasion Mode                                                                                                   |
| **`R`**                                   | Retreat active outgoing land & boat attacks                                                                                         |
| **`Space`**                               | Toggle Affiliation Alt-View (`Green` Self / `Yellow` Ally / `Red` Enemy)                                                            |
| **`M` / `T`**                             | Toggle Emoji Grid / Quick Chat Menu                                                                                                 |
| **`C` / `0`**                             | Center camera on own Empire / Fit entire World                                                                                      |
| **`Esc`**                                 | Cancel armed build/boat mode & close open modals                                                                                    |

---

## Project Layout & Verification Tooling

```text
OpenFront.rbxl                      # Ready-to-open binary Roblox Studio place file (zero setup!)
roblox/
├── OpenFront.rbxl                  # Binary Studio place mirror
├── OpenFront.rbxlx                 # XML Studio place file for diffing/inspection
├── default.project.json            # Modular Rojo v7 project configuration
├── src/
│   ├── Shared/                     # Types, Config formulas, Theme LUTs, Format/Flags, MapCodec, NetCodec & 10 Maps
│   ├── Server/                     # SimEngine (10Hz), AiBrain, Heap, DataService & Bootstrap.server.luau
│   └── Client/                     # MapCanvas (Dual Shader/Scanline), Camera2D, MenuUI, HudUI, SoundFX & Main.client.luau
├── tools/
│   ├── export_maps.py              # Compresses binary OpenFront maps into <116 KB Base64+PackBits Luau modules
│   └── build_rbxl.py               # Deterministic binary .rbxl & XML .rbxlx compiler with full round-trip verification
└── tests/
    └── run_tests.mjs               # Headless WebAssembly Luau (`luau-web`) compiler, simulation & full Client+Server E2E suite
```
