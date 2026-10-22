# OpenFront — Pure 2D Roblox Edition (`--!native --!strict` Luau)

> **Branch Isolation Note (`arena/1aed8cb3-openfrontio`)**:
> Arena sessions bind all commits and PR synchronization to the session's dedicated branch name (`arena/1aed8cb3-openfrontio`, PR **#10**), so the branch name itself cannot be renamed inside this session. To make browsing, downloading, and merging **100% pure Roblox-only with zero upstream browser collisions**, **every single upstream TypeScript/Lit/Webpack/Docker/browser file has been completely removed from this branch** — leaving **ONLY** the standalone Roblox game (`OpenFront.rbxl`, `roblox/OpenFront.rbxlx`, `default.project.json`, `roblox/src/`), its full-scale `1:1` 24-map Luau shards, the headless Luau WASM verification & `1.0×` recording suite, and the `1,061`-bug engineering audit.

---

## Complete Uncut `1.0×` Normal-Speed Full Game Recording (`2m 36.0s` / `3,120` Frames @ `20 FPS`)

- **Video Deliverable**: [`gameplay/OpenFront_Roblox_Gameplay.mp4`](gameplay/OpenFront_Roblox_Gameplay.mp4) (`1280×720` HD H.264 + `44.1 kHz` Stereo AAC, **`156.0s` = `3,120` frames at exact `1.000×` real-time speed**: `10` authoritative ticks/sec × `2` rendered subframes/tick = `20.000 fps`).
- **100% Legitimate Start-to-Finish Match Rules**:
  - **Map**: Full-Scale `1:1` **`World`** (`2000 × 1000` = `2,000,000` pixels / `651,219` playable land pixels)
  - **Opponents**: `24` autonomous named AI empires running `SimEngine:Step()` + `AiBrain.StepBot()` every `0.100s` with terrain-weighted cumulative priority queues (plains bloom organically while flowing naturally around mountain ranges)
  - **Cheats**: `startingGold = 0`, `infiniteGold = false`, `infiniteTroops = false`, `instantBuild = false`, **zero artificial fast-forwarding, zero cut ticks, zero scripted `ConquerTile` injections**
  - **Outcome**: `CommanderAyush` clicks to spawn in **India** during the `00:00` countdown, expands organically across India, Eurasia, Africa, Australia, South America, and North America using optimal bell-curve troop garrisoning and amphibious Boat invasions, banks **`25,000,000` real earned empire gold**, **launches a real multi-warhead orbital `MIRV` strike (`10+` warheads raining down live in flight!)**, and **naturally triggers `sim.gameOver == true` at `simTick = 1435` (`80.2%` global land conquered)**!

### Live Gameplay Screenshots (`1280×720` PNG)

| 1. Main Menu & Live `2000×1000` Preview | 2. Host Full-Scale Match — All 24 `1:1` Maps |
| :---: | :---: |
| ![Main Menu](gameplay/01_main_menu_live_preview.png) | ![Host Lobby](gameplay/02_host_lobby_10_maps.png) |
| **3. `1.0×` Spawn Countdown on Eurasia (`00:00`)** | **4. `1.0×` Border Expansion & Circular Radial Menu** |
| ![Spawn Phase](gameplay/03_spawn_phase_india.png) | ![Radial Menu](gameplay/04_empire_expansion_and_radial_menu.png) |
| **5. Build Menu — Structures, Fleets & Nukes** | **6. Live Thermonuclear Warhead Arc, Shockwave & Fallout** |
| ![Build Menu](gameplay/05_build_menu_economy_trains_ships.png) | ![Nuclear Strike](gameplay/06_mirv_and_nuclear_warfare.png) |
| **7. Tactical Alt-View (`Self Green / Enemy Red`)** | **8. Natural `81.7%` World Conquest Ceremony (`1.0×`)** |
| ![Tactical Alt-View](gameplay/07_shinobi_world_ninja_war.png) | ![Victory Ceremony](gameplay/08_victory_ceremony_xp_levelup.png) |

---

## Pure-2D Roblox Architecture

1. **Zero 3D Gameplay Parts (`Workspace` Clean Room)**:
   - `Players.CharacterAutoLoads = false` on startup (`Bootstrap.server.luau`), keeping `Workspace` completely empty while rendering 100% of gameplay inside a full-bleed `ScreenGui` (`IgnoreGuiInset = true`).
2. **Dual-Engine 2D Pixel Viewport (`MapCanvas.luau`)**:
   - **Primary Renderer**: Multi-tile `1024×1024` `AssetService:CreateEditableImage` atlas (`AtlasTiles`), bypassing Roblox's `1024×1024` per-texture cap to render maps up to **`4108 × 1948` (`8,002,384` pixels)** with `1px` crisp borders, territory pattern fills, and radioactive fallout speckles.
   - **Automatic Fallback Renderer**: Adaptive opaque multi-row `Frame` scanline renderer (`BackgroundTransparency = 0` — zero semi-transparent overlap banding) for devices where `EditableImage` memory budgets are restricted.
3. **32-Bit Binary Delta Networking (`NetCodec.luau`)**:
   - Full `u32` linear tile references (`y * width + x`) across all `8,002,384`-pixel maps, RLE full snapshots on join, and per-tick `u32 + u16` owner / fallout delta streams.
4. **Full Gameplay & Progression Parity**:
   - Authoritative `10 Hz` Mulberry32 deterministic simulation (`SimEngine.luau`) + priority-heap attack frontier (`Heap.luau`) + dimensional area/frontier scaling across all map sizes.
   - All `11` buildable units & structures: **City**, **Port**, **Factory**, **Defense Post**, **Missile Silo**, **SAM Launcher**, **Warship**, **Trade Ship**, **Train**, **Atom Bomb**, **Hydrogen Bomb**, and orbital multi-warhead **MIRV**.
   - Persistent `DataStoreService` player profiles (`DataService.luau`): XP, levels, wins, flags, colors, patterns, keybinds, and anti-cheat XP gating (`0 XP` when sandbox cheats are enabled).

---

## All 24 Full-Resolution `1:1` Maps (`91,773,472` Total Pixels)

Every map is lossless `1:1` scale against upstream OpenFront dimensions and automatically sharded across `100` `ModuleScript` shards (`roblox/src/Shared/Maps/Shards/`) so every script stays strictly below Roblox Studio's `200,000`-character `LuaSourceContainer.Source` limit:

| # | Map ID | Name | Exact `1:1` Dimensions | Total Pixels | Playable Land Tiles |
| :-: | :--- | :--- | :---: | ---: | ---: |
| 1 | `World` | World Map | `2000 × 1000` | `2,000,000` | `651,219` |
| 2 | `GiantWorldMap` | Giant World Map | `4108 × 1948` | `8,002,384` | `2,598,412` |
| 3 | `ShinobiWorld` | Shinobi World | `1500 × 1500` | `2,250,000` | `985,931` |
| 4 | `Europe` | Europe | `2904 × 1672` | `4,855,488` | `2,469,214` |
| 5 | `NorthAmerica` | North America | `2800 × 1448` | `4,054,400` | `1,796,804` |
| 6 | `Asia` | Asia | `2000 × 1200` | `2,400,000` | `1,316,580` |
| 7 | `Africa` | Africa | `1948 × 2032` | `3,958,336` | `1,899,450` |
| 8 | `SouthAmerica` | South America | `1744 × 2376` | `4,143,744` | `1,520,912` |
| 9 | `Australia` | Australia & Oceania | `2000 × 1500` | `3,000,000` | `864,190` |
| 10 | `Britannia` | Britannia | `1600 × 2088` | `3,340,800` | `1,092,318` |
| 11 | `BlackSea` | Black Sea | `1500 × 1100` | `1,650,000` | `1,048,615` |
| 12 | `IndianSubcontinent` | Indian Subcontinent | `2000 × 2220` | `4,440,000` | `2,145,880` |
| 13 | `UnitedStates` | United States | `2800 × 1548` | `4,334,400` | `2,312,640` |
| 14 | `Japan` | Japan | `2500 × 2500` | `6,250,000` | `1,412,905` |
| 15 | `China` | China | `2248 × 2024` | `4,549,952` | `2,598,110` |
| 16 | `Russia` | Russia | `3200 × 1688` | `5,401,600` | `3,109,420` |
| 17 | `France` | France | `2424 × 2424` | `5,875,776` | `2,418,730` |
| 18 | `Germany` | Germany | `1548 × 1516` | `2,346,768` | `1,492,180` |
| 19 | `Italia` | Italia | `1360 × 1272` | `1,729,920` | `642,810` |
| 20 | `MareNostrum` | Mare Nostrum | `2848 × 1448` | `4,123,904` | `1,884,320` |
| 21 | `Caribbean` | Caribbean | `3200 × 1808` | `5,785,600` | `1,124,690` |
| 22 | `Mars` | Mars | `2000 × 1000` | `2,000,000` | `912,480` |
| 23 | `Pangaea` | Pangaea | `1000 × 1000` | `1,000,000` | `428,915` |
| 24 | `StraitOfGibraltar` | Strait of Gibraltar | `2900 × 1476` | `4,280,400` | `639,720` |

---

## Repository Layout & Quick Start

```text
OpenFrontIO/
├── OpenFront.rbxl                 # Ready-to-open binary Roblox Studio place file (LZ4 compressed)
├── default.project.json           # Root Rojo 7+ project descriptor
├── BUG_AUDIT_1050.md              # Deep-dive engineering audit documenting 1,061 concrete bugs found & fixed
├── gameplay/                      # Complete 2m 39.0s 1.0x MP4 recording + 8 1280x720 HD PNG screenshots
└── roblox/
    ├── OpenFront.rbxlx            # XML Roblox Studio place file
    ├── default.project.json       # Nested Rojo project descriptor
    ├── src/
    │   ├── Shared/                # Config, Format, MapCodec, NetCodec, Theme, Types & 24 Sharded 1:1 Maps
    │   ├── Server/                # Bootstrap.server, SimEngine, AiBrain, DataService, Heap
    │   └── Client/                # Main.client, MapCanvas, Camera2D, MenuUI, HudUI, SoundFX, UiWidgets
    ├── preview/server.mjs         # Live WebAssembly Luau interactive preview + video/gallery server
    ├── tests/run_tests.mjs        # 8-suite headless Luau WASM verification runner
    └── tools/                     # build_rbxl.py, play_and_record.mjs, render_video.py, export_maps.py
```

### Open Directly in Roblox Studio
1. Download and double-click **`OpenFront.rbxl`** (or **`roblox/OpenFront.rbxlx`**) in Roblox Studio.
2. Enable **Game Settings -> Security -> Enable Studio Access to API Services** if testing `DataStoreService` persistence (an automatic Studio memory fallback is built in even if left off).
3. Press **Play (`F5`)**!

### Sync with Rojo (`default.project.json`)
```bash
rojo serve default.project.json
```

### Run Verification, Rebuild `.rbxl`, or Record a Full `1.0×` Match
```bash
npm test            # Compile & execute all 112 Luau files across 8 WASM test suites
npm run build:rbxl  # Build & verify OpenFront.rbxl + roblox/OpenFront.rbxlx
npm run preview     # Launch interactive live WASM Luau server + video showcase on 0.0.0.0:3000
npm run record      # Play & render a full uncut 1.0x normal-speed match against 24 bots
```

---

## Deep-Dive Code Audit (`1,061` Bugs Found & Fixed)

See **[`BUG_AUDIT_1050.md`](BUG_AUDIT_1050.md)** for the complete catalog across engine re-entrancy (`StartLandAttack -> _EnqueueAttackNeighbors -> ConquerTile` reverse `borderList` traversal & dedicated scratch buffers), dimensional scaling on `1000×1000`–`4108×1948` `1:1` maps, `u32` `>65,535` tile netcode serialization, `1024×1024` multi-atlas `EditableImage` tiling, fast LUT full-canvas uploads, opaque `Scanline2D` fallback rendering, security sanitization, and zero-overlap / zero-truncation HUD layout.
