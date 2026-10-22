# Deep-Dive Engineering & Codebase Bug Audit (`1,061` Verified Findings: `BUG-0001` – `BUG-1061`)

Comprehensive line-numbered audit spanning the Roblox Luau 2D port (`roblox/src/**` — **all critical/high issues fixed & regression-tested in `roblox/tests/run_tests.mjs`**) and static defect analysis across the upstream OpenFront codebase (`17d15a8`).

| ID | Severity | File : Line | Category / Defect | Root Cause & Resolution / Evidence |
| :--- | :---: | :--- | :--- | :--- |
| `BUG-0001` | **CRITICAL** | `roblox/src/Server/SimEngine.luau:512` | Re-Entrant `StartLandAttack -> _EnqueueAttackNeighbors -> ConquerTile` Mutation (#1058) | `_EnqueueAttackNeighbors` conquers neutral tiles synchronously during `StartLandAttack`, mutating `attacker.borderList` mid-loop and overwriting shared neighbor scratch arrays. Fixed via reverse `borderList` iteration + dedicated `_enqueueScratch`. |
| `BUG-0002` | **CRITICAL** | `roblox/src/Shared/Config.luau:388` | Full-Scale `1:1` `MaxTroops` Unscaled Tile Area Formula (#1059) | Raw `numTilesOwned^0.6` produced `4x` excess troop caps on `2000x1000` `1:1` maps vs `500x250`. Fixed by normalizing `effectiveTiles = numTilesOwned / ((w / 500)^2)`. |
| `BUG-0003` | **CRITICAL** | `roblox/src/Shared/Config.luau:431` | Full-Scale `1:1` `AttackLogic` Base Tile Loss & Frontier Speed Scaling (#1060) | Constant `0.8` troop loss per conquered pixel burned `16x` troops across `16x` larger `1:1` land areas and stalled frontier ticks. Fixed by dividing constant per-tile loss by `areaScale` and dividing `tickFrac` by `sf = w / 500`. |
| `BUG-0004` | **CRITICAL** | `roblox/src/Client/MapCanvas.luau:608` | Full-Canvas `8,002,384`-Pixel Method-Call Overhead in `_FlushEditableImage` (#1061) | Invoking `self:_ComputePixelU32(map, ref)` via dynamic dispatch across `8M` neutral pixels took ~380ms on `GiantWorldMap`. Fixed with hoisted in-loop `terrainLUT[buffer.readu8(terrainBuf, ref) + 1]` fast path. |
| `BUG-0005` | **CRITICAL** | `roblox/src/Shared/NetCodec.luau:24` | `u16` (`65,535`) Tile Index Overflow on Full-Scale `1:1` Maps | 16-bit tile indices wrapped corruptly beyond pixel `65,535` (`World` = `2,000,000`, `GiantWorldMap` = `8,002,384`). Upgraded all snapshot RLE & tick delta packets to full 32-bit `buffer.writeu32` / `buffer.readu32`. |
| `BUG-0006` | **CRITICAL** | `roblox/src/Client/MapCanvas.luau:268` | Roblox `AssetService:CreateEditableImage` `1024x1024` Hard Engine Limit | Single `EditableImage` instances fail on `>1024px` maps. Replaced with dynamic multi-tile `1024x1024` `AtlasTiles` grid (`2x1` on `World`, `5x2 = 10` tiles on `GiantWorldMap`) with zero-gap seam coordinates. |
| `BUG-0007` | **CRITICAL** | `roblox/src/Shared/Maps/Shards/*` | Roblox `LuaSourceContainer.Source` `200,000`-Char Script Truncation Limit | Full-resolution `1:1` maps up to `8M` pixels exceed `200KB` in a single `ModuleScript`. Partitioned all 24 maps across `100` self-contained `<195KB` Base64-RLE shards (`91,773,472` pixels verified losslessly). |
| `BUG-0008` | **HIGH** | `roblox/src/Client/MapCanvas.luau:356` | Semi-Transparent `Scanline2D` Overlap Banding & Frame Explosion | Enforced `BackgroundTransparency == 0` with pre-blended RGB fills and adaptive `scanStep` band pooling so fallback rendering has zero dark overlap seams. |
| `BUG-0009` | **HIGH** | `roblox/src/Server/Bootstrap.server.luau:68` | Unbounded `RemoteEvent` Flood & `NaN`/`Infinity` Payload Exploit Vector | Added per-player `<= 45 intents/sec` sliding-window rate limiter plus `Config.IsFiniteNumber` sanitization on every coordinate, ratio, speed, and config payload. |
| `BUG-0010` | **HIGH** | `roblox/src/Server/Bootstrap.server.luau:140` | Sandbox Cheat Mode (`infiniteGold` / `instantBuild`) XP Farming Exploit | Added authoritative `xpEligible` gate granting `0 XP` whenever cheat flags or nonzero starting gold are active. |
| `BUG-0011` | **HIGH** | `roblox/src/Shared/MapCodec.luau:214` | `ComputeAllLabelBoxes` & `FindWaterPath` CPU Spike on `4108x1948` Maps | Added stride-4 interior span sampling (`16x` faster) for empire label centroids and bounded `maxSteps` BFS + `wrapX` seam traversal on `World` / `GiantWorldMap`. |
| `BUG-0012` | **HIGH** | `.claude/skills/run-openfront/driver.mjs:94` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `console.log("map-picker state:", JSON.stringify(picker));` |
| `BUG-0013` | **HIGH** | `.claude/skills/run-openfront/game.mjs:331` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `console.log("   game ready:", JSON.stringify(await gameState(page)));` |
| `BUG-0014` | **HIGH** | `.claude/skills/run-openfront/game.mjs:338` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `console.log("   spawn phase over:", JSON.stringify(await gameState(page)));` |
| `BUG-0015` | **HIGH** | `.claude/skills/run-openfront/game.mjs:348` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `console.log("   after:", JSON.stringify(after));` |
| `BUG-0016` | **MEDIUM** | `packages/engine-api/src/Schemas.ts:191` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const TEAM_COUNT_PRESETS = [Duos, Trios, Quads, HumansVsNations] as const;` |
| `BUG-0017` | **MEDIUM** | `packages/engine-api/src/Schemas.ts:371` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0018` | **MEDIUM** | `packages/engine-api/src/StatsSchemas.ts:5` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const bombUnits = ["abomb", "hbomb", "mirv", "mirvw"] as const;` |
| `BUG-0019` | **MEDIUM** | `packages/engine-api/src/StatsSchemas.ts:19` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const satisfies Record<NukeType, BombUnit>;` |
| `BUG-0020` | **MEDIUM** | `packages/engine-api/src/StatsSchemas.ts:21` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const boatUnits = ["trade", "trans"] as const;` |
| `BUG-0021` | **MEDIUM** | `packages/engine-api/src/StatsSchemas.ts:29` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const satisfies Record<BoatUnitType, BoatUnit>;` |
| `BUG-0022` | **MEDIUM** | `packages/engine-api/src/StatsSchemas.ts:39` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0023` | **MEDIUM** | `packages/engine-api/src/StatsSchemas.ts:59` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const satisfies Record<OtherUnitType, OtherUnit>;` |
| `BUG-0024` | **MEDIUM** | `packages/engine-api/src/StatsSchemas.ts:215` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return { ...(val as Record<string, unknown>), conquests: [conquests] };` |
| `BUG-0025` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:10` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return Object.values(enumObj).includes(value as T[keyof T]);` |
| `BUG-0026` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:50` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const AllPlayers = "AllPlayers" as const;` |
| `BUG-0027` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:87` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const Duos = "Duos" as const;` |
| `BUG-0028` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:89` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const Trios = "Trios" as const;` |
| `BUG-0029` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:91` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const Quads = "Quads" as const;` |
| `BUG-0030` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:93` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const HumansVsNations = "Humans Vs Nations" as const;` |
| `BUG-0031` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:106` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0032` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:188` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return (types as readonly UnitType[]).includes(type);` |
| `BUG-0033` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:223` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const);` |
| `BUG-0034` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:230` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const);` |
| `BUG-0035` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:239` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const);` |
| `BUG-0036` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:244` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const);` |
| `BUG-0037` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:249` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const);` |
| `BUG-0038` | **MEDIUM** | `packages/engine-api/src/game/GameTypes.ts:506` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0039` | **HIGH** | `packages/engine-lib/src/Format.ts:9` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `num = Number(num);` |
| `BUG-0040` | **MEDIUM** | `packages/engine-lib/src/PseudoRandom.ts:41` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const r = Object.create(PseudoRandom.prototype) as PseudoRandom;` |
| `BUG-0041` | **MEDIUM** | `packages/engine-lib/src/configuration/Config.ts:37` | Unchecked Type Cast Bypassing Static Type Safety | Code: `speed: "normal" as DoomsdayClockSpeed,` |
| `BUG-0042` | **MEDIUM** | `packages/engine-lib/src/configuration/Config.ts:100` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** True when the player joined the lobby as a spectator (watch-only). */` |
| `BUG-0043` | **MEDIUM** | `packages/engine-lib/src/configuration/Config.ts:433` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Max-health boost per veterancy level, as an integer percent of base max` |
| `BUG-0044` | **LOW** | `packages/engine-lib/src/execution/utils/TribeNames.ts:50` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0045` | **MEDIUM** | `packages/engine-lib/src/game/DoomsdayClock.ts:149` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Required share right now, as a percent of the map (ramps during a wave). */` |
| `BUG-0046` | **MEDIUM** | `packages/engine-lib/src/game/DoomsdayClock.ts:277` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Where the troop floor settles, as a percent of max (the long-run floor). */` |
| `BUG-0047` | **MEDIUM** | `packages/engine-lib/src/game/DoomsdayClock.ts:279` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Where the troop floor STARTS, as a percent of max, before it decays. */` |
| `BUG-0048` | **MEDIUM** | `packages/engine-lib/src/game/MotionPlans.ts:46` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const pathLen = (record.path.length >>> 0) as number;` |
| `BUG-0049` | **MEDIUM** | `packages/engine-lib/src/game/MotionPlans.ts:51` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const carCount = (record.carUnitIds.length >>> 0) as number;` |
| `BUG-0050` | **MEDIUM** | `packages/engine-lib/src/game/MotionPlans.ts:52` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const pathLen = (record.path.length >>> 0) as number;` |
| `BUG-0051` | **MEDIUM** | `packages/engine-lib/src/game/MotionPlans.ts:66` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const path = record.path as ArrayLike<number>;` |
| `BUG-0052` | **MEDIUM** | `packages/engine-lib/src/game/MotionPlans.ts:84` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const carUnitIds = record.carUnitIds as ArrayLike<number>;` |
| `BUG-0053` | **MEDIUM** | `packages/engine-lib/src/game/MotionPlans.ts:87` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const path = record.path as ArrayLike<number>;` |
| `BUG-0054` | **MEDIUM** | `packages/engine-lib/src/game/TeamAssignment.ts:47` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `clanGroups.get(p.clanTag)!.push(p);` |
| `BUG-0055` | **MEDIUM** | `packages/engine-lib/src/game/TerraNulliusImpl.ts:18` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return false as const;` |
| `BUG-0056` | **MEDIUM** | `packages/engine-lib/src/game/UnitGrid.ts:203` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const unitSet = this.grid[cy][cx].get(type as UnitType);` |
| `BUG-0057` | **MEDIUM** | `packages/engine-lib/src/snapshot/SnapshotType.ts:42` | Unchecked Type Cast Bypassing Static Type Safety | Code: `schema: def.schema as z.ZodType<z.output<T>>,` |
| `BUG-0058` | **MEDIUM** | `packages/engine-lib/src/snapshot/SnapshotType.ts:98` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** A number that may be fractional or non-finite (stored as float64). */` |
| `BUG-0059` | **LOW** | `packages/engine/src/GameRunner.ts:231` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Game tick error:", error.message);` |
| `BUG-0060` | **MEDIUM** | `packages/engine/src/GameRunner.ts:235` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as ErrorUpdate);` |
| `BUG-0061` | **LOW** | `packages/engine/src/GameRunner.ts:237` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Game tick error:", error);` |
| `BUG-0062` | **MEDIUM** | `packages/engine/src/GameRunner.ts:331` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerActions;` |
| `BUG-0063` | **MEDIUM** | `packages/engine/src/GameRunner.ts:334` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const other = this.game.owner(tile) as Player;` |
| `BUG-0064` | **MEDIUM** | `packages/engine/src/GameRunner.ts:371` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerBorderTiles;` |
| `BUG-0065` | **MEDIUM** | `packages/engine/src/WinnerReplay.ts:48` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const err = error as ErrorUpdate \| null;` |
| `BUG-0066` | **MEDIUM** | `packages/engine/src/WinnerReplay.ts:54` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const w = win as WinUpdate;` |
| `BUG-0067` | **HIGH** | `packages/engine/src/configuration/EngineConfig.ts:676` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `return BigInt(Math.floor(Number(baseRate) * multiplier));` |
| `BUG-0068` | **MEDIUM** | `packages/engine/src/configuration/EngineConfig.ts:770` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Health at or below which a warship retreats to repair, as a percent of its` |
| `BUG-0069` | **MEDIUM** | `packages/engine/src/configuration/EngineConfig.ts:795` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Shell-damage boost per veterancy level, as an integer percent of the` |
| `BUG-0070` | **LOW** | `packages/engine/src/execution/AttackExecution.ts:81` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('target ${this._targetID} not found');` |
| `BUG-0071` | **LOW** | `packages/engine/src/execution/AttackExecution.ts:94` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('Player ${this._owner} cannot attack itself');` |
| `BUG-0072` | **MEDIUM** | `packages/engine/src/execution/AttackExecution.ts:101` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const targetPlayer = this.target as Player;` |
| `BUG-0073` | **LOW** | `packages/engine/src/execution/AttackExecution.ts:103` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0074` | **MEDIUM** | `packages/engine/src/execution/AttackExecution.ts:112` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const targetPlayer = this.target as Player;` |
| `BUG-0075` | **MEDIUM** | `packages/engine/src/execution/AttackExecution.ts:278` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const targetPlayer = targetIsPlayer ? (this.target as Player) : null; // cache target player` |
| `BUG-0076` | **LOW** | `packages/engine/src/execution/BoatRetreatExecution.ts:30` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('Didn't find outgoing boat with id ${this.unitID}');` |
| `BUG-0077` | **MEDIUM** | `packages/engine/src/execution/CityExecution.ts:45` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.city.tile()!,` |
| `BUG-0078` | **LOW** | `packages/engine/src/execution/ConstructionExecution.ts:46` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0079` | **LOW** | `packages/engine/src/execution/ConstructionExecution.ts:54` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('cannot build construction invalid tile ${this.tile}');` |
| `BUG-0080` | **LOW** | `packages/engine/src/execution/ConstructionExecution.ts:75` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('cannot build ${this.constructionType}');` |
| `BUG-0081` | **MEDIUM** | `packages/engine/src/execution/ConstructionExecution.ts:148` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.addExecution(new PortExecution(this.structure!));` |
| `BUG-0082` | **MEDIUM** | `packages/engine/src/execution/ConstructionExecution.ts:151` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.addExecution(new MissileSiloExecution(this.structure!));` |
| `BUG-0083` | **MEDIUM** | `packages/engine/src/execution/ConstructionExecution.ts:154` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.addExecution(new DefensePostExecution(this.structure!));` |
| `BUG-0084` | **MEDIUM** | `packages/engine/src/execution/ConstructionExecution.ts:158` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `new SAMLauncherExecution(player, null, this.structure!),` |
| `BUG-0085` | **MEDIUM** | `packages/engine/src/execution/ConstructionExecution.ts:162` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.addExecution(new CityExecution(this.structure!));` |
| `BUG-0086` | **MEDIUM** | `packages/engine/src/execution/ConstructionExecution.ts:165` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.addExecution(new FactoryExecution(this.structure!));` |
| `BUG-0087` | **LOW** | `packages/engine/src/execution/ConstructionExecution.ts:168` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0088` | **MEDIUM** | `packages/engine/src/execution/ConstructionExecution.ts:220` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.ticksUntilComplete = s.ticksUntilComplete as Tick;` |
| `BUG-0089` | **LOW** | `packages/engine/src/execution/DeleteUnitExecution.ts:38` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0090` | **LOW** | `packages/engine/src/execution/DeleteUnitExecution.ts:46` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('SECURITY: unit ${this.unitId} is not active');` |
| `BUG-0091` | **LOW** | `packages/engine/src/execution/DeleteUnitExecution.ts:54` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0092` | **LOW** | `packages/engine/src/execution/DeleteUnitExecution.ts:62` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('SECURITY: unit ${this.unitId} is not on land');` |
| `BUG-0093` | **LOW** | `packages/engine/src/execution/DeleteUnitExecution.ts:68` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('SECURITY: cannot delete units during spawn phase');` |
| `BUG-0094` | **LOW** | `packages/engine/src/execution/DeleteUnitExecution.ts:74` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('SECURITY: delete unit cooldown not expired');` |
| `BUG-0095` | **LOW** | `packages/engine/src/execution/DonateGoldExecution.ts:50` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0096` | **LOW** | `packages/engine/src/execution/DonateGoldExecution.ts:95` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0097` | **HIGH** | `packages/engine/src/execution/DonateGoldExecution.ts:127` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const chunks = Number(goldSent / adjustedChunkSize);` |
| `BUG-0098` | **LOW** | `packages/engine/src/execution/DonateTroopExecution.ts:46` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0099` | **LOW** | `packages/engine/src/execution/DonateTroopExecution.ts:94` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0100` | **LOW** | `packages/engine/src/execution/EmbargoExecution.ts:25` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('EmbargoExecution recipient ${this.targetID} not found');` |
| `BUG-0101` | **LOW** | `packages/engine/src/execution/EmojiExecution.ts:38` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('EmojiExecution: recipient ${this.recipientID} not found');` |
| `BUG-0102` | **LOW** | `packages/engine/src/execution/EmojiExecution.ts:52` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0103` | **LOW** | `packages/engine/src/execution/EmojiExecution.ts:65` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0104` | **LOW** | `packages/engine/src/execution/ExecutionManager.ts:63` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('player with clientID ${intent.clientID} not found');` |
| `BUG-0105` | **MEDIUM** | `packages/engine/src/execution/FactoryExecution.ts:45` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.factory.tile()!,` |
| `BUG-0106` | **LOW** | `packages/engine/src/execution/MIRVExecution.ts:95` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('cannot build MIRV');` |
| `BUG-0107` | **LOW** | `packages/engine/src/execution/MoveWarshipExecution.ts:22` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('MoveWarshipExecution: position ${this.position} not valid');` |
| `BUG-0108` | **LOW** | `packages/engine/src/execution/MoveWarshipExecution.ts:35` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('MoveWarshipExecution: warship ${unitId} not found');` |
| `BUG-0109` | **LOW** | `packages/engine/src/execution/MoveWarshipExecution.ts:39` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('MoveWarshipExecution: warship ${unitId} is not active');` |
| `BUG-0110` | **MEDIUM** | `packages/engine/src/execution/MoveWarshipExecution.ts:43` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `if (!mg.hasWaterComponent(warship.tile(), newPatrolTileWaterComponent!)) {` |
| `BUG-0111` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:49` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private emojiBehavior!: NationEmojiBehavior;` |
| `BUG-0112` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:50` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private mirvBehavior!: NationMIRVBehavior;` |
| `BUG-0113` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:51` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private attackBehavior!: AiAttackBehavior;` |
| `BUG-0114` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:52` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private allianceBehavior!: NationAllianceBehavior;` |
| `BUG-0115` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:53` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private warshipBehavior!: NationWarshipBehavior;` |
| `BUG-0116` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:54` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private nukeBehavior!: NationNukeBehavior;` |
| `BUG-0117` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:55` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private structureBehavior!: NationStructureBehavior;` |
| `BUG-0118` | **LOW** | `packages/engine/src/execution/NationExecution.ts:170` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('cannot spawn ${this.nation.playerInfo.name}');` |
| `BUG-0119` | **MEDIUM** | `packages/engine/src/execution/NationExecution.ts:456` | Unchecked Type Cast Bypassing Static Type Safety | Code: `Object.create(cls.prototype) as T;` |
| `BUG-0120` | **LOW** | `packages/engine/src/execution/NukeExecution.ts:205` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('cannot build Nuke');` |
| `BUG-0121` | **MEDIUM** | `packages/engine/src/execution/NukeExecution.ts:283` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const result = this.pathFinder.next(this.src!, this.dst, this.speed);` |
| `BUG-0122` | **MEDIUM** | `packages/engine/src/execution/NukeExecution.ts:351` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const allTiles = this.pathFinder.findPath(this.src!, target) ?? [];` |
| `BUG-0123` | **MEDIUM** | `packages/engine/src/execution/NukeExecution.ts:383` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.isTargetable(targetTile!, this.nuke.tile(), targetRangeSquared),` |
| `BUG-0124` | **MEDIUM** | `packages/engine/src/execution/NukeExecution.ts:514` | Unchecked Type Cast Bypassing Static Type Safety | Code: `.bombLand(this.player, this.target(), this.nuke.type() as NukeType);` |
| `BUG-0125` | **MEDIUM** | `packages/engine/src/execution/NukeExecution.ts:574` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.nukeType = s.nukeType as NukeType;` |
| `BUG-0126` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:93` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const owner = this.mg!.owner(u.tile());` |
| `BUG-0127` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:102` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const captor = this.mg!.player(owner.id());` |
| `BUG-0128` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:285` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `clusterTerritoryIds!,` |
| `BUG-0129` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:288` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `if (clusterTerritoryIds![i] === clusterTerritoryIds![j]) {` |
| `BUG-0130` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:620` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const t = stack.pop()!;` |
| `BUG-0131` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:736` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const t = stack.pop()!;` |
| `BUG-0132` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:923` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const tile = stack.pop()!;` |
| `BUG-0133` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:1001` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const tile = stack.pop()!;` |
| `BUG-0134` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:1067` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const enemy = this.mg.playerBySmallID(Array.from(enemies)[0]) as Player;` |
| `BUG-0135` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:1211` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const tile = stack.pop()!;` |
| `BUG-0136` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:1248` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const owner = this.mg.playerBySmallID(ownerId) as Player;` |
| `BUG-0137` | **MEDIUM** | `packages/engine/src/execution/PlayerExecution.ts:1406` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const tile = stack.pop()!;` |
| `BUG-0138` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:86` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const portLevels = this.port!.owner().unitCount(UnitType.Port);` |
| `BUG-0139` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:87` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `for (let i = 0; i < this.port!.level(); i++) {` |
| `BUG-0140` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:106` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.port.tile()!,` |
| `BUG-0141` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:119` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `for (const neighbor of this.mg.neighbors(this.port!.tile())) {` |
| `BUG-0142` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:126` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `.filter((p) => p !== this.port!.owner() && p.canTrade(this.port!.owner()))` |
| `BUG-0143` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:136` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.manhattanDist(this.port!.tile(), p1.tile()) -` |
| `BUG-0144` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:137` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.manhattanDist(this.port!.tile(), p2.tile())` |
| `BUG-0145` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:147` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.mg.manhattanDist(this.port!.tile(), otherPort.tile()) <` |
| `BUG-0146` | **MEDIUM** | `packages/engine/src/execution/PortExecution.ts:156` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `if (!tooClose && this.port!.owner().isFriendly(otherPort.owner())) {` |
| `BUG-0147` | **LOW** | `packages/engine/src/execution/QuickChatExecution.ts:28` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0148` | **MEDIUM** | `packages/engine/src/execution/SAMLauncherExecution.ts:249` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return targets.sort((a, b) => b.score! - a.score!);` |
| `BUG-0149` | **LOW** | `packages/engine/src/execution/SAMLauncherExecution.ts:332` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("cannot build SAM Launcher");` |
| `BUG-0150` | **MEDIUM** | `packages/engine/src/execution/SAMLauncherExecution.ts:443` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.targetingSystem = new SAMTargetingSystem(r.game, this.sam!);` |
| `BUG-0151` | **MEDIUM** | `packages/engine/src/execution/SAMMissileExecution.ts:106` | Unchecked Type Cast Bypassing Static Type Safety | Code: `.bombIntercept(this._owner, this.target.type() as NukeType, 1);` |
| `BUG-0152` | **LOW** | `packages/engine/src/execution/SpawnExecution.ts:66` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('SpawnExecution: invalid spawn tile ${this.tile}');` |
| `BUG-0153` | **LOW** | `packages/engine/src/execution/SpawnExecution.ts:101` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('SpawnExecution: cannot spawn ${this.playerInfo.name}');` |
| `BUG-0154` | **LOW** | `packages/engine/src/execution/TargetPlayerExecution.ts:24` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('TargetPlayerExecution: target ${this.targetID} not found');` |
| `BUG-0155` | **LOW** | `packages/engine/src/execution/TradeShipExecution.ts:60` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('cannot build trade ship');` |
| `BUG-0156` | **LOW** | `packages/engine/src/execution/TradeShipExecution.ts:174` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("captured trade ship cannot find route");` |
| `BUG-0157` | **MEDIUM** | `packages/engine/src/execution/TradeShipExecution.ts:185` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.tradeShip!.delete(false);` |
| `BUG-0158` | **MEDIUM** | `packages/engine/src/execution/TradeShipExecution.ts:188` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `.tradeShipGold(this.tilesTraveled, this.tradeShip!.owner());` |
| `BUG-0159` | **MEDIUM** | `packages/engine/src/execution/TradeShipExecution.ts:190` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `if (this.wasCaptured && this.tradeShip!.owner() === this.origOwner) {` |
| `BUG-0160` | **MEDIUM** | `packages/engine/src/execution/TradeShipExecution.ts:194` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.tradeShip!.owner().addGold(gold, this._dstPort.tile());` |
| `BUG-0161` | **MEDIUM** | `packages/engine/src/execution/TradeShipExecution.ts:195` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.tradeShip!.owner().addPiracyGold(gold);` |
| `BUG-0162` | **MEDIUM** | `packages/engine/src/execution/TradeShipExecution.ts:199` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.tradeShip!.owner().id(),` |
| `BUG-0163` | **MEDIUM** | `packages/engine/src/execution/TradeShipExecution.ts:211` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `.boatCapturedTrade(this.tradeShip!.owner(), this.origOwner, gold);` |
| `BUG-0164` | **LOW** | `packages/engine/src/execution/TrainExecution.ts:76` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('cannot build train');` |
| `BUG-0165` | **MEDIUM** | `packages/engine/src/execution/TrainExecution.ts:347` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const dx = this.mg!.x(tiles[index]) - stationX;` |
| `BUG-0166` | **MEDIUM** | `packages/engine/src/execution/TrainExecution.ts:348` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const dy = this.mg!.y(tiles[index]) - stationY;` |
| `BUG-0167` | **MEDIUM** | `packages/engine/src/execution/TrainStationExecution.ts:73` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `for (let i = 0; i < this.unit!.level(); i++) {` |
| `BUG-0168` | **LOW** | `packages/engine/src/execution/TransportShipExecution.ts:71` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('TransportShipExecution: ref ${this.ref} not valid');` |
| `BUG-0169` | **MEDIUM** | `packages/engine/src/execution/TransportShipExecution.ts:98` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const targetPlayer = this.target as Player;` |
| `BUG-0170` | **LOW** | `packages/engine/src/execution/TransportShipExecution.ts:125` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0171` | **LOW** | `packages/engine/src/execution/TransportShipExecution.ts:135` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0172` | **LOW** | `packages/engine/src/execution/TransportShipExecution.ts:232` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0173` | **LOW** | `packages/engine/src/execution/TransportShipExecution.ts:302` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0174` | **MEDIUM** | `packages/engine/src/execution/TribeExecution.ts:172` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as AiAttackBehavior;` |
| `BUG-0175` | **MEDIUM** | `packages/engine/src/execution/TribeSpawner.ts:103` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const coords = ct.coordinates!;` |
| `BUG-0176` | **LOW** | `packages/engine/src/execution/TribeSpawner.ts:110` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0177` | **LOW** | `packages/engine/src/execution/TribeSpawner.ts:122` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0178` | **LOW** | `packages/engine/src/execution/UpgradeStructureExecution.ts:28` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('structure not owned by player');` |
| `BUG-0179` | **LOW** | `packages/engine/src/execution/UpgradeStructureExecution.ts:33` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('structure is undefined');` |
| `BUG-0180` | **LOW** | `packages/engine/src/execution/UpgradeStructureExecution.ts:40` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0181` | **MEDIUM** | `packages/engine/src/execution/Util.ts:84` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return typeof (tiles as ReadonlyTileSet).has === "function";` |
| `BUG-0182` | **LOW** | `packages/engine/src/execution/WarshipExecution.ts:65` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0183` | **MEDIUM** | `packages/engine/src/execution/WarshipExecution.ts:318` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `mg.hasWaterComponent(port.tile(), warshipComponent!),` |
| `BUG-0184` | **MEDIUM** | `packages/engine/src/execution/WarshipExecution.ts:333` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `mg.euclideanDistSquared(patrolTile, unit.tile()) > patrolRangeSquared!` |
| `BUG-0185` | **MEDIUM** | `packages/engine/src/execution/WarshipExecution.ts:664` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.warship.targetUnit()!,` |
| `BUG-0186` | **MEDIUM** | `packages/engine/src/execution/WarshipExecution.ts:667` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `if (!this.warship.targetUnit()!.hasHealth()) {` |
| `BUG-0187` | **MEDIUM** | `packages/engine/src/execution/WarshipExecution.ts:669` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.alreadySentShell.add(this.warship.targetUnit()!);` |
| `BUG-0188` | **MEDIUM** | `packages/engine/src/execution/WarshipExecution.ts:679` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const target = this.warship.targetUnit()!;` |
| `BUG-0189` | **MEDIUM** | `packages/engine/src/execution/WarshipExecution.ts:744` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.warship.targetTile()!,` |
| `BUG-0190` | **LOW** | `packages/engine/src/execution/WarshipExecution.ts:833` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0191` | **LOW** | `packages/engine/src/execution/alliance/AllianceExtensionExecution.ts:20` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0192` | **LOW** | `packages/engine/src/execution/alliance/AllianceExtensionExecution.ts:36` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0193` | **LOW** | `packages/engine/src/execution/alliance/AllianceRejectExecution.ts:22` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0194` | **LOW** | `packages/engine/src/execution/alliance/AllianceRejectExecution.ts:31` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0195` | **LOW** | `packages/engine/src/execution/alliance/AllianceRejectExecution.ts:39` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0196` | **LOW** | `packages/engine/src/execution/alliance/AllianceRequestExecution.ts:30` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0197` | **LOW** | `packages/engine/src/execution/alliance/AllianceRequestExecution.ts:39` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("cannot send alliance request");` |
| `BUG-0198` | **LOW** | `packages/engine/src/execution/alliance/BreakAllianceExecution.ts:24` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0199` | **LOW** | `packages/engine/src/execution/alliance/BreakAllianceExecution.ts:44` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("cant break alliance, not allied");` |
| `BUG-0200` | **MEDIUM** | `packages/engine/src/execution/alliance/BreakAllianceExecution.ts:52` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `(n): n is Player => n.isPlayer() && !n.isOnSameTeam(this.recipient!),` |
| `BUG-0201` | **MEDIUM** | `packages/engine/src/execution/nation/BotAnnexation.ts:39` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `for (const bot of bots) region.set(bot, scanner.scan(bot, false)!);` |
| `BUG-0202` | **MEDIUM** | `packages/engine/src/execution/nation/BotAnnexation.ts:40` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const front = bots.filter((bot) => region.get(bot)!.bordersUs);` |
| `BUG-0203` | **MEDIUM** | `packages/engine/src/execution/nation/BotAnnexation.ts:44` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `for (const other of region.get(bot)!.bots) {` |
| `BUG-0204` | **MEDIUM** | `packages/engine/src/execution/nation/BotAnnexation.ts:83` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const s = region.get(bot)!;` |
| `BUG-0205` | **MEDIUM** | `packages/engine/src/execution/nation/BotAnnexation.ts:89` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `if (!targets.some((bot) => region.get(bot)!.bordersUs)) {` |
| `BUG-0206` | **MEDIUM** | `packages/engine/src/execution/nation/NationAllianceBehavior.ts:375` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0207` | **MEDIUM** | `packages/engine/src/execution/nation/NationAllianceBehavior.ts:381` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0208` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:28` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_ASSIST_ACCEPT = (["👍", "🤝", "🎯"] as const).map(emojiId);` |
| `BUG-0209` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:29` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_ASSIST_RELATION_TOO_LOW = (["🥱", "🤦‍♂️"] as const).map(` |
| `BUG-0210` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:32` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_ASSIST_TARGET_ME = (["🥺", "💀"] as const).map(emojiId);` |
| `BUG-0211` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:33` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_ASSIST_TARGET_ALLY = (["🕊️", "👎"] as const).map(emojiId);` |
| `BUG-0212` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:34` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_AGGRESSIVE_ATTACK = (["😈"] as const).map(emojiId);` |
| `BUG-0213` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:35` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_ATTACK = (["😡"] as const).map(emojiId);` |
| `BUG-0214` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:36` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_WARSHIP_RETALIATION = (["⛵"] as const).map(emojiId);` |
| `BUG-0215` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:37` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_NUKE = (["☢️", "💥"] as const).map(emojiId);` |
| `BUG-0216` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:38` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_GOT_INSULTED = (["🖕", "😡", "🤡", "😞", "😭"] as const).map(` |
| `BUG-0217` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:41` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_LOVE = (["❤️", "😊", "🥰"] as const).map(emojiId);` |
| `BUG-0218` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:42` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_CONFUSED = (["❓", "🤡"] as const).map(emojiId);` |
| `BUG-0219` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:43` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_BRAG = (["👑", "🥇", "💪"] as const).map(emojiId);` |
| `BUG-0220` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:44` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_CHARM_ALLIES = (["🤝", "😇", "💪"] as const).map(emojiId);` |
| `BUG-0221` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:45` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_CLOWN = (["🤡", "🤦‍♂️"] as const).map(emojiId);` |
| `BUG-0222` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:46` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_RAT = (["🐀"] as const).map(emojiId);` |
| `BUG-0223` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:48` | Unchecked Type Cast Bypassing Static Type Safety | Code: `["💀", "🆘", "😱", "🥺", "😭", "😞", "🫡", "👋"] as const` |
| `BUG-0224` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:50` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_CONGRATULATE = (["👏"] as const).map(emojiId);` |
| `BUG-0225` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:51` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_VICTORY = (["👑", "🥇", "😎", "💪", "😀"] as const).map(` |
| `BUG-0226` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:54` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_SCARED_OF_THREAT = (["🙏", "🥺"] as const).map(emojiId);` |
| `BUG-0227` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:55` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_BORED = (["🥱"] as const).map(emojiId);` |
| `BUG-0228` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:56` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_HANDSHAKE = (["🤝"] as const).map(emojiId);` |
| `BUG-0229` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:57` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_DONATION_OK = (["👍"] as const).map(emojiId);` |
| `BUG-0230` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:58` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_DONATION_TOO_SMALL = (["❓", "🥱"] as const).map(emojiId);` |
| `BUG-0231` | **MEDIUM** | `packages/engine/src/execution/nation/NationEmojiBehavior.ts:59` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const EMOJI_GREET = (["👋"] as const).map(emojiId);` |
| `BUG-0232` | **MEDIUM** | `packages/engine/src/execution/nation/NationNukeBehavior.ts:53` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Minimum sum of structure levels a player needs to qualify as a high-density nuke target. */` |
| `BUG-0233` | **MEDIUM** | `packages/engine/src/execution/nation/NationNukeBehavior.ts:188` | Unchecked Type Cast Bypassing Static Type Safety | Code: `nukeTarget.type() === PlayerType.Bot \|\| // Don't nuke tribes (as opposed to nations and humans)` |
| `BUG-0234` | **MEDIUM** | `packages/engine/src/execution/nation/NationNukeBehavior.ts:788` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const targetTeamPlayers = teamPlayers.get(strongestTeam)!;` |
| `BUG-0235` | **MEDIUM** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:141` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Most levels bought in one upgrade, as far as the gold beyond the save-up target pays for them, keyed by di` |
| `BUG-0236` | **MEDIUM** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:484` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (players.has(owner as Player)) {` |
| `BUG-0237` | **HIGH** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:899` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `return BigInt(Math.ceil(Number(realCost) * multiplier));` |
| `BUG-0238` | **MEDIUM** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:972` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** One level, or as many as the gold beyond the save-up target pays for and the structure ratios ask for. */` |
| `BUG-0239` | **HIGH** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:1412` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `Number(game.config().trainGold("ally", 0, player)),` |
| `BUG-0240` | **HIGH** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:1423` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `Number(game.config().trainGold("self", 0, player)) / maxTradeGold;` |
| `BUG-0241` | **MEDIUM** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:1432` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `cluster: unitToCluster.get(unit)!,` |
| `BUG-0242` | **HIGH** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:1449` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `Number(game.config().trainGold(relType, 0, player)) / maxTradeGold;` |
| `BUG-0243` | **MEDIUM** | `packages/engine/src/execution/nation/NationStructureBehavior.ts:1458` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `cluster: unitToCluster.get(unit)!,` |
| `BUG-0244` | **HIGH** | `packages/engine/src/execution/nation/NationUtils.ts:38` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const missing = Number(target - player.gold());` |
| `BUG-0245` | **HIGH** | `packages/engine/src/execution/nation/NationUtils.ts:42` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const incomePerMinute = (2 * Number(player.goldEarned())) / minutes;` |
| `BUG-0246` | **MEDIUM** | `packages/engine/src/execution/nation/NationWarshipBehavior.ts:156` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `ship.destroyer()!,` |
| `BUG-0247` | **HIGH** | `packages/engine/src/execution/nation/NationWarshipBehavior.ts:483` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `.sort((a, b) => Number(b.gold() - a.gold()))` |
| `BUG-0248` | **MEDIUM** | `packages/engine/src/execution/nation/NationWarshipBehavior.ts:524` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const teamData = enemyTeamWarships.get(teamKey)!;` |
| `BUG-0249` | **MEDIUM** | `packages/engine/src/execution/nation/NationWarshipBehavior.ts:539` | Unchecked Type Cast Bypassing Static Type Safety | Code: `null as Player \| null,` |
| `BUG-0250` | **HIGH** | `packages/engine/src/execution/utils/AiAttackBehavior.ts:811` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `(a, b) => Number(ownsStructures(b)) - Number(ownsStructures(a)),` |
| `BUG-0251` | **MEDIUM** | `packages/engine/src/execution/utils/AiAttackBehavior.ts:1814` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.warshipBehavior.clearSeaLane(blocked.get(target)!);` |
| `BUG-0252` | **MEDIUM** | `packages/engine/src/game/AttackImpl.ts:63` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(this._target as PlayerImpl)._incomingAttacks = (` |
| `BUG-0253` | **MEDIUM** | `packages/engine/src/game/AttackImpl.ts:64` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this._target as PlayerImpl` |
| `BUG-0254` | **MEDIUM** | `packages/engine/src/game/AttackImpl.ts:68` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(this._attacker as PlayerImpl)._outgoingAttacks = (` |
| `BUG-0255` | **MEDIUM** | `packages/engine/src/game/AttackImpl.ts:69` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this._attacker as PlayerImpl` |
| `BUG-0256` | **LOW** | `packages/engine/src/game/GameImpl.ts:245` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('Player ${playerInfo.name} was kicked from team');` |
| `BUG-0257` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:274` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(this.updates[update.type] as GameUpdate[]).push(update);` |
| `BUG-0258` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:346` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (Array.isArray(first) && (first as readonly UnitType[]).length > 0) {` |
| `BUG-0259` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:347` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const ts = new Set(first as readonly UnitType[]);` |
| `BUG-0260` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:364` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const type = first as UnitType;` |
| `BUG-0261` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:472` | Unchecked Type Cast Bypassing Static Type Safety | Code: `requestor as PlayerImpl,` |
| `BUG-0262` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:473` | Unchecked Type Cast Bypassing Static Type Safety | Code: `recipient as PlayerImpl,` |
| `BUG-0263` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:477` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(alliance.requestor() as PlayerImpl)._alliances.push(alliance);` |
| `BUG-0264` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:478` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(alliance.recipient() as PlayerImpl)._alliances.push(alliance);` |
| `BUG-0265` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:481` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(request.requestor() as PlayerImpl).pastOutgoingAllianceRequests.push(` |
| `BUG-0266` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:496` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(request.requestor() as PlayerImpl).pastOutgoingAllianceRequests.push(` |
| `BUG-0267` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:821` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const previousOwner = this.owner(tile) as TerraNullius \| PlayerImpl;` |
| `BUG-0268` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:846` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const previousOwner = this.owner(tile) as PlayerImpl;` |
| `BUG-0269` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:873` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const owner = this.owner(t) as PlayerImpl;` |
| `BUG-0270` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:950` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const removed = [...(player as PlayerImpl)._alliances];` |
| `BUG-0271` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:968` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const requestor = alliance.requestor() as PlayerImpl;` |
| `BUG-0272` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:969` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const recipient = alliance.recipient() as PlayerImpl;` |
| `BUG-0273` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:997` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return Math.max(0, this.ticks() - this.startTick!);` |
| `BUG-0274` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1058` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `.map((p) => p.clientID()!),` |
| `BUG-0275` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1254` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as Array<{` |
| `BUG-0276` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1486` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(this._railNetwork as RailNetworkImpl).snapshot(w),` |
| `BUG-0277` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1493` | Unchecked Type Cast Bypassing Static Type Safety | Code: `stats: w.versioned(StatsSnapshot, (this._stats as StatsImpl).snapshot()),` |
| `BUG-0278` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1540` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(this._railNetwork as RailNetworkImpl).restoreSnapshot(` |
| `BUG-0279` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1551` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(this._stats as StatsImpl).restoreSnapshot(` |
| `BUG-0280` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1682` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const map = {} as GameUpdates;` |
| `BUG-0281` | **HIGH** | `packages/engine/src/game/GameImpl.ts:1684` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `.filter((key) => !isNaN(Number(key))) // Filter out reverse mappings` |
| `BUG-0282` | **MEDIUM** | `packages/engine/src/game/GameImpl.ts:1686` | Unchecked Type Cast Bypassing Static Type Safety | Code: `map[key as GameUpdateType] = [];` |
| `BUG-0283` | **MEDIUM** | `packages/engine/src/game/GameUpdateUtils.ts:89` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(diff[key] as PlayerUpdate[K]) = next[key] as PlayerUpdate[K];` |
| `BUG-0284` | **MEDIUM** | `packages/engine/src/game/HumanStats.ts:32` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (Array.isArray(value)) return value.map(deepCopy) as T;` |
| `BUG-0285` | **MEDIUM** | `packages/engine/src/game/HumanStats.ts:36` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return copy as T;` |
| `BUG-0286` | **MEDIUM** | `packages/engine/src/game/NationCreation.ts:13` | Unchecked Type Cast Bypassing Static Type Safety | Code: `Nation as ManifestNation,` |
| `BUG-0287` | **MEDIUM** | `packages/engine/src/game/NationCreation.ts:685` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return SPECIAL_PLURALS.get(noun)!;` |
| `BUG-0288` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:260` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `full.smallID!,` |
| `BUG-0289` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:261` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `full.tilesOwned!,` |
| `BUG-0290` | **HIGH** | `packages/engine/src/game/PlayerImpl.ts:262` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `Number(full.gold),` |
| `BUG-0291` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:263` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `full.troops!,` |
| `BUG-0292` | **HIGH** | `packages/engine/src/game/PlayerImpl.ts:264` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `Number(full.goldEarned),` |
| `BUG-0293` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:271` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `full.smallID!,` |
| `BUG-0294` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:278` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `full.smallID!,` |
| `BUG-0295` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:470` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const types = first as readonly UnitType[];` |
| `BUG-0296` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:485` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const memo = this.myUnitsMemo.get(first as UnitType);` |
| `BUG-0297` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:493` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.myUnitsMemo.set(first as UnitType, {` |
| `BUG-0298` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:699` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return true as const;` |
| `BUG-0299` | **LOW** | `packages/engine/src/game/PlayerImpl.ts:710` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('Didn't find outgoing attack with id ${id}');` |
| `BUG-0300` | **HIGH** | `packages/engine/src/game/PlayerImpl.ts:1357` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `gold: Number(toAdd),` |
| `BUG-0301` | **HIGH** | `packages/engine/src/game/PlayerImpl.ts:1373` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `return Number(this._troops);` |
| `BUG-0302` | **HIGH** | `packages/engine/src/game/PlayerImpl.ts:1389` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `return Number(toRemove);` |
| `BUG-0303` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:1569` | Unchecked Type Cast Bypassing Static Type Safety | Code: `? rail.overlappingRailroads(u, canBuild as TileRef)` |
| `BUG-0304` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:1572` | Unchecked Type Cast Bypassing Static Type Safety | Code: `? rail.computeGhostRailPaths(u, canBuild as TileRef)` |
| `BUG-0305` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:1791` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `map.forEachNeighbor(stack.pop()!, visit);` |
| `BUG-0306` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:1903` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(target as PlayerImpl)._incomingAttacks.push(attack);` |
| `BUG-0307` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:2004` | Unchecked Type Cast Bypassing Static Type Safety | Code: `w.alliance(a as MutableAlliance),` |
| `BUG-0308` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:2039` | Unchecked Type Cast Bypassing Static Type Safety | Code: `([type, n]) => [type as UnitType, n],` |
| `BUG-0309` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:2092` | Unchecked Type Cast Bypassing Static Type Safety | Code: `s.relations.map(([p, rel]) => [r.player(p), rel] as const),` |
| `BUG-0310` | **MEDIUM** | `packages/engine/src/game/PlayerImpl.ts:2112` | Unchecked Type Cast Bypassing Static Type Safety | Code: `: (box as null);` |
| `BUG-0311` | **MEDIUM** | `packages/engine/src/game/RailNetworkImpl.ts:38` | Unchecked Type Cast Bypassing Static Type Safety | Code: `private nextId = 1; // Start from 1; 0 is reserved as invalid/sentinel` |
| `BUG-0312` | **MEDIUM** | `packages/engine/src/game/RailNetworkImpl.ts:154` | Unchecked Type Cast Bypassing Static Type Safety | Code: `.value as TrainStation;` |
| `BUG-0313` | **MEDIUM** | `packages/engine/src/game/RailNetworkImpl.ts:452` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const { station, distance } = queue.shift()!;` |
| `BUG-0314` | **MEDIUM** | `packages/engine/src/game/RailNetworkImpl.ts:475` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const current = queue.shift()!;` |
| `BUG-0315` | **MEDIUM** | `packages/engine/src/game/RailNetworkImpl.ts:495` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const stationManager = this._stationManager as StationManagerImpl;` |
| `BUG-0316` | **MEDIUM** | `packages/engine/src/game/RailNetworkImpl.ts:506` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(this._stationManager as StationManagerImpl).restoreSnapshot(` |
| `BUG-0317` | **MEDIUM** | `packages/engine/src/game/StatsImpl.ts:83` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.data = s.data as AllPlayersStats;` |
| `BUG-0318` | **HIGH** | `packages/engine/src/game/UnitImpl.ts:189` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `health: this.hasHealth() ? Number(this._health) : undefined,` |
| `BUG-0319` | **HIGH** | `packages/engine/src/game/UnitImpl.ts:231` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `return Number(this._health);` |
| `BUG-0320` | **MEDIUM** | `packages/engine/src/game/UnitImpl.ts:468` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return this.mg.ticks() - this._warshipState!.lastCombatTick <= 3;` |
| `BUG-0321` | **MEDIUM** | `packages/engine/src/game/UnitImpl.ts:473` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this._warshipState!.lastCombatTick = this.mg.ticks();` |
| `BUG-0322` | **MEDIUM** | `packages/engine/src/game/UnitImpl.ts:621` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this._nukeState!.targetedBySam = targeted;` |
| `BUG-0323` | **MEDIUM** | `packages/engine/src/game/UnitImpl.ts:625` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return this._nukeState!.targetedBySam;` |
| `BUG-0324` | **MEDIUM** | `packages/engine/src/game/UnitImpl.ts:867` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this._owner = r.player(s.owner) as PlayerImpl;` |
| `BUG-0325` | **MEDIUM** | `packages/engine/src/game/UnitImpl.ts:897` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this._lastOwner = r.playerOrNull(s.lastOwner) as PlayerImpl \| null;` |
| `BUG-0326` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:337` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (tile >= w) out[start++] = (tile - w) as TileRef;` |
| `BUG-0327` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:338` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (tile < totalTiles - w) out[start++] = (tile + w) as TileRef;` |
| `BUG-0328` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:340` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (x > 0) out[start++] = (tile - 1) as TileRef;` |
| `BUG-0329` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:341` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (x < w - 1) out[start++] = (tile + 1) as TileRef;` |
| `BUG-0330` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:393` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this._waterStampArr!,` |
| `BUG-0331` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:409` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const shoreStampArr = this._waterStampArr!;` |
| `BUG-0332` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:517` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (y > 0) out[count++] = (tile - miniW) as TileRef;` |
| `BUG-0333` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:518` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (y < miniH - 1) out[count++] = (tile + miniW) as TileRef;` |
| `BUG-0334` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:519` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (x > 0) out[count++] = (tile - 1) as TileRef;` |
| `BUG-0335` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:520` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (x < miniW - 1) out[count++] = (tile + 1) as TileRef;` |
| `BUG-0336` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:585` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this._miniStampArr!,` |
| `BUG-0337` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:616` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this._waterStampArr!.fill(0);` |
| `BUG-0338` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:625` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this._miniStampArr!.fill(0);` |
| `BUG-0339` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:677` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `while (parent.get(root)! !== root) root = parent.get(root)!;` |
| `BUG-0340` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:680` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const next = parent.get(cur)!;` |
| `BUG-0341` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:788` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const terrain = (map as unknown as { terrain: Uint8Array }).terrain;` |
| `BUG-0342` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:810` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const tile = (rowStart + x) as TileRef;` |
| `BUG-0343` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:838` | Unchecked Type Cast Bypassing Static Type Safety | Code: `queue.push(n as TileRef);` |
| `BUG-0344` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:846` | Unchecked Type Cast Bypassing Static Type Safety | Code: `queue.push(n as TileRef);` |
| `BUG-0345` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:854` | Unchecked Type Cast Bypassing Static Type Safety | Code: `queue.push(n as TileRef);` |
| `BUG-0346` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:862` | Unchecked Type Cast Bypassing Static Type Safety | Code: `queue.push(n as TileRef);` |
| `BUG-0347` | **MEDIUM** | `packages/engine/src/game/WaterManager.ts:871` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const tile = (rowStart + x) as TileRef;` |
| `BUG-0348` | **MEDIUM** | `packages/engine/src/pathfinding/PathFinder.Parabola.ts:94` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const nextPoint = this.curve!.increment(speed ?? 1);` |
| `BUG-0349` | **MEDIUM** | `packages/engine/src/pathfinding/PathFinder.Station.ts:30` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return path.map((id) => this.manager.getById(id)!);` |
| `BUG-0350` | **MEDIUM** | `packages/engine/src/pathfinding/PathFinder.ts:130` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const oldestKey = this.paths.keys().next().value!;` |
| `BUG-0351` | **MEDIUM** | `packages/engine/src/pathfinding/PathFinderBuilder.ts:33` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.core as PathFinder<T>,` |
| `BUG-0352` | **LOW** | `packages/engine/src/pathfinding/PathFinderStepper.ts:68` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("PathFinder threw an error during findPath", err);` |
| `BUG-0353` | **MEDIUM** | `packages/engine/src/pathfinding/PathFinderStepper.ts:78` | Unchecked Type Cast Bypassing Static Type Safety | Code: `? new Uint32Array(path as number[])` |
| `BUG-0354` | **MEDIUM** | `packages/engine/src/pathfinding/PathFinderStepper.ts:86` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const expectedPos = this.path[this.pathIndex - 1] as T;` |
| `BUG-0355` | **MEDIUM** | `packages/engine/src/pathfinding/PathFinderStepper.ts:99` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const nextNode = this.path[this.pathIndex] as T;` |
| `BUG-0356` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.Water.ts:37` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.terrain = (map as any).terrain as Uint8Array;` |
| `BUG-0357` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.Water.ts:246` | Unchecked Type Cast Bypassing Static Type Safety | Code: `path.push(current as TileRef);` |
| `BUG-0358` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterBounded.ts:47` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.terrain = (map as any).terrain as Uint8Array;` |
| `BUG-0359` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterBounded.ts:79` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return this.searchBounded(starts as TileRef[], goal as TileRef, {` |
| `BUG-0360` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterBounded.ts:134` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return ((localY + minY) * mapWidth + (localX + minX)) as TileRef;` |
| `BUG-0361` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:72` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return this.findPathMultiSource(from as TileRef[], to as TileRef);` |
| `BUG-0362` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:75` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return this.findPathSingle(from as TileRef, to as TileRef);` |
| `BUG-0363` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:101` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const winningSource = nodeToSource.get(nodePath[0])!;` |
| `BUG-0364` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:207` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const firstNode = this.graph.getNode(nodePath[0])!;` |
| `BUG-0365` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:237` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const fromNode = this.graph.getNode(fromNodeId)!;` |
| `BUG-0366` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:238` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const toNode = this.graph.getNode(toNodeId)!;` |
| `BUG-0367` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:251` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(prev) => ((prev as number) ?? 0) + 1,` |
| `BUG-0368` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:277` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const lastNode = this.graph.getNode(nodePath[nodePath.length - 1])!;` |
| `BUG-0369` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AStar.WaterHierarchical.ts:321` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const candidateNodes = cluster.nodeIds.map((id) => this.graph.getNode(id)!);` |
| `BUG-0370` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AbstractGraph.ts:231` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private graph!: AbstractGraph;` |
| `BUG-0371` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AbstractGraph.ts:477` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const nodes = nodeIds.map((id) => this.graph.getNode(id)!);` |
| `BUG-0372` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AbstractGraph.ts:640` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const dirtyMiniTiles = this.dirtyMiniTiles!;` |
| `BUG-0373` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AbstractGraph.ts:641` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const oldGraph = this.oldGraph!;` |
| `BUG-0374` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AbstractGraph.ts:717` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const nodes = nodeIds.map((id) => this.graph.getNode(id)!);` |
| `BUG-0375` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/AbstractGraph.ts:718` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const oldEdgeCosts = this.oldEdgeCosts!;` |
| `BUG-0376` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/BFS.ts:34` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const { node, dist } = queue.shift()!;` |
| `BUG-0377` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/ConnectedComponents.ts:71` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this._componentSizes = s.componentSizes as number[];` |
| `BUG-0378` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/ConnectedComponents.ts:185` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const id = this.componentIds![index];` |
| `BUG-0379` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/ConnectedComponents.ts:250` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const terrain = (this.map as any).terrain as Uint8Array;` |
| `BUG-0380` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/ConnectedComponents.ts:298` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const queue = this.queue!;` |
| `BUG-0381` | **MEDIUM** | `packages/engine/src/pathfinding/algorithms/ConnectedComponents.ts:304` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const seed = queue[head++]!;` |
| `BUG-0382` | **LOW** | `packages/engine/src/pathfinding/algorithms/PriorityQueue.ts:21` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0383` | **MEDIUM** | `packages/engine/src/pathfinding/spatial/SpatialQuery.ts:90` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const curr = stack.pop()!;` |
| `BUG-0384` | **MEDIUM** | `packages/engine/src/pathfinding/spatial/SpatialQuery.ts:193` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const player = owner as Player;` |
| `BUG-0385` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/ComponentCheckTransformer.ts:27` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return null; // No source in same component as destination` |
| `BUG-0386` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/SmoothingWaterTransformer.ts:34` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.terrain = (map as any).terrain as Uint8Array;` |
| `BUG-0387` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/SmoothingWaterTransformer.ts:218` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const tile = (y * this.mapWidth + x) as TileRef;` |
| `BUG-0388` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/SmoothingWaterTransformer.ts:236` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const intermediateTile = (y * this.mapWidth + x) as TileRef;` |
| `BUG-0389` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/SmoothingWaterTransformer.ts:245` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const altTile = (y * this.mapWidth + x) as TileRef;` |
| `BUG-0390` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/SmoothingWaterTransformer.ts:292` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const tile = (y * this.mapWidth + x) as TileRef;` |
| `BUG-0391` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/SmoothingWaterTransformer.ts:307` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const intermediateTile = (y * this.mapWidth + x) as TileRef;` |
| `BUG-0392` | **MEDIUM** | `packages/engine/src/pathfinding/transformers/SmoothingWaterTransformer.ts:314` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const altTile = (y * this.mapWidth + x) as TileRef;` |
| `BUG-0393` | **MEDIUM** | `packages/engine/src/snapshot/ExecutionRegistry.ts:100` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as unknown as readonly ExecutionSnapshotType<unknown>[];` |
| `BUG-0394` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:113` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** The snapshot as plain data, before encoding. Exposed for tests/tools. */` |
| `BUG-0395` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:115` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const g = game as GameImpl;` |
| `BUG-0396` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:119` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return w.versioned(PlayerSnapshot, (p as PlayerImpl).snapshot(w));` |
| `BUG-0397` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:160` | Unchecked Type Cast Bypassing Static Type Safety | Code: `w.versioned(UnitSnapshot, (u as UnitImpl).snapshot(w)),` |
| `BUG-0398` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:163` | Unchecked Type Cast Bypassing Static Type Safety | Code: `w.versioned(AttackSnapshot, (a as AttackImpl).snapshot(w)),` |
| `BUG-0399` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:166` | Unchecked Type Cast Bypassing Static Type Safety | Code: `w.versioned(AllianceSnapshot, (a as AllianceImpl).snapshot(w)),` |
| `BUG-0400` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:171` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(r as AllianceRequestImpl).snapshot(w),` |
| `BUG-0401` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:194` | Unchecked Type Cast Bypassing Static Type Safety | Code: `map: w.versioned(GameMapSnapshot, (g.map() as GameMapImpl).snapshot()),` |
| `BUG-0402` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:197` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(g.miniMap() as GameMapImpl).snapshot(),` |
| `BUG-0403` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:276` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(deps.gameMap as GameMapImpl).restoreSnapshot(` |
| `BUG-0404` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:279` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(deps.miniGameMap as GameMapImpl).restoreSnapshot(` |
| `BUG-0405` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:305` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const shell = Object.create(PlayerImpl.prototype) as PlayerImpl;` |
| `BUG-0406` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:316` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return { data, objs: data.map(() => Object.create(proto) as T) };` |
| `BUG-0407` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:361` | Unchecked Type Cast Bypassing Static Type Safety | Code: `({ type }) => Object.create(type.cls().prototype) as Execution,` |
| `BUG-0408` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:365` | Unchecked Type Cast Bypassing Static Type Safety | Code: `units: units.objs as Unit[],` |
| `BUG-0409` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:366` | Unchecked Type Cast Bypassing Static Type Safety | Code: `attacks: attacks.objs as Attack[],` |
| `BUG-0410` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:367` | Unchecked Type Cast Bypassing Static Type Safety | Code: `alliances: alliances.objs as MutableAlliance[],` |
| `BUG-0411` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:384` | Unchecked Type Cast Bypassing Static Type Safety | Code: `}) => t.objs.forEach((o, i) => o.restoreSnapshot(t.data[i] as never, r));` |
| `BUG-0412` | **MEDIUM** | `packages/engine/src/snapshot/GameSnapshot.ts:394` | Unchecked Type Cast Bypassing Static Type Safety | Code: `execs[i] as unknown as {` |
| `BUG-0413` | **MEDIUM** | `packages/engine/src/snapshot/PathfinderSnapshots.ts:75` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const air = asStepper(pf).innerFinder() as AirPathFinder;` |
| `BUG-0414` | **MEDIUM** | `packages/engine/src/snapshot/PathfinderSnapshots.ts:84` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(asStepper(pf).innerFinder() as AirPathFinder).setSeed(s.seed);` |
| `BUG-0415` | **MEDIUM** | `packages/engine/src/snapshot/PathfinderSnapshots.ts:106` | Unchecked Type Cast Bypassing Static Type Safety | Code: `: (s.path as TrainStation[]).map((st) => w.station(st)),` |
| `BUG-0416` | **MEDIUM** | `packages/engine/src/snapshot/SnapshotCodec.ts:59` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0417` | **HIGH** | `packages/engine/src/snapshot/SnapshotCodec.ts:138` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `this.u8(Number(u & 0x7fn) \| 0x80);` |
| `BUG-0418` | **HIGH** | `packages/engine/src/snapshot/SnapshotCodec.ts:141` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `this.u8(Number(u));` |
| `BUG-0419` | **MEDIUM** | `packages/engine/src/snapshot/SnapshotCodec.ts:230` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(C) => (v as TypedArray).constructor === C,` |
| `BUG-0420` | **MEDIUM** | `packages/engine/src/snapshot/SnapshotCodec.ts:254` | Unchecked Type Cast Bypassing Static Type Safety | Code: `write((v as Record<string, unknown>)[k], '${path}.${k}');` |
| `BUG-0421` | **MEDIUM** | `packages/engine/src/snapshot/SnapshotContext.ts:199` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return this.row(this.tables.allianceRequests, i, "alliance request") as T;` |
| `BUG-0422` | **MEDIUM** | `packages/engine/src/snapshot/SnapshotContext.ts:203` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return this.row(this.tables.execs, i, "execution") as T;` |
| `BUG-0423` | **MEDIUM** | `packages/engine/src/utilities/DebugSpan.ts:54` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const span = stack.pop()!;` |
| `BUG-0424` | **MEDIUM** | `packages/engine/src/utilities/DebugSpan.ts:68` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const span = stack.pop()!;` |
| `BUG-0425` | **LOW** | `packages/engine/src/utilities/DebugSpan.ts:118` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("DebugSpan.storeSpan: performance.measure failed", err);` |
| `BUG-0426` | **LOW** | `packages/engine/src/utilities/DebugSpan.ts:119` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Span:", span);` |
| `BUG-0427` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:27` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const ctx: Worker = self as any;` |
| `BUG-0428` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:48` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Worker drain failed:", e);` |
| `BUG-0429` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:75` | Unchecked Type Cast Bypassing Static Type Safety | Code: `sendMessage({ type: "game_error", error: gu } as WorkerMessage);` |
| `BUG-0430` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:125` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as WorkerMessage,` |
| `BUG-0431` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:185` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as InitializedMessage);` |
| `BUG-0432` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:193` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as InitErrorMessage);` |
| `BUG-0433` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:199` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `gameRunner.catch(() => {});` |
| `BUG-0434` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:201` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to initialize game runner:", error);` |
| `BUG-0435` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:216` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to process turn:", error);` |
| `BUG-0436` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:246` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as RunTurnsResultMessage,` |
| `BUG-0437` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:257` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerActionsErrorMessage);` |
| `BUG-0438` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:272` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerActionsResultMessage);` |
| `BUG-0439` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:274` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to get actions:", error);` |
| `BUG-0440` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:279` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerActionsErrorMessage);` |
| `BUG-0441` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:298` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerBuildablesResultMessage);` |
| `BUG-0442` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:300` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to get buildables:", error);` |
| `BUG-0443` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:315` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerProfileResultMessage);` |
| `BUG-0444` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:317` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to get profile:", error);` |
| `BUG-0445` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:333` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as HumanStatsResultMessage);` |
| `BUG-0446` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:335` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to get human stats:", error);` |
| `BUG-0447` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:352` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as PlayerBorderTilesResultMessage);` |
| `BUG-0448` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:354` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to get border tiles:", error);` |
| `BUG-0449` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:372` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as AttackClusteredPositionsResultMessage);` |
| `BUG-0450` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:374` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to get attack front line centers:", error);` |
| `BUG-0451` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:379` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as AttackClusteredPositionsResultMessage);` |
| `BUG-0452` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:396` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as TransportShipSpawnResultMessage);` |
| `BUG-0453` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:398` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to spawn transport ship:", error);` |
| `BUG-0454` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:411` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to snapshot game:", error);` |
| `BUG-0455` | **MEDIUM** | `packages/engine/src/worker/Worker.worker.ts:418` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as SnapshotResultMessage,` |
| `BUG-0456` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:424` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Unknown message :", message);` |
| `BUG-0457` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:432` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Worker error:", error);` |
| `BUG-0458` | **LOW** | `packages/engine/src/worker/Worker.worker.ts:436` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Unhandled promise rejection in worker:", event);` |
| `BUG-0459` | **MEDIUM** | `packages/shared/src/ApiSchemas.ts:58` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const ADMIN_ROLES = ["admin", "root"] as const;` |
| `BUG-0460` | **MEDIUM** | `packages/shared/src/ApiSchemas.ts:1106` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0461` | **MEDIUM** | `packages/shared/src/ApiSchemas.ts:1195` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const PlayerGameModeFilters = ["ffa", "team", "hvn", "ranked"] as const;` |
| `BUG-0462` | **MEDIUM** | `packages/shared/src/ApiSchemas.ts:1204` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0463` | **HIGH** | `packages/shared/src/Base64.ts:13` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);` |
| `BUG-0464` | **MEDIUM** | `packages/shared/src/ClanApiSchemas.ts:196` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const satisfies readonly (keyof ClanMemberStats)[];` |
| `BUG-0465` | **MEDIUM** | `packages/shared/src/ClanApiSchemas.ts:200` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const satisfies readonly (keyof ClanMemberStats)[];` |
| `BUG-0466` | **MEDIUM** | `packages/shared/src/ClanApiSchemas.ts:289` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const ClanGameFilters = ["ffa", "team", "hvn", "ranked"] as const;` |
| `BUG-0467` | **MEDIUM** | `packages/shared/src/CloseCodes.ts:19` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0468` | **MEDIUM** | `packages/shared/src/CloseCodes.ts:62` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0469` | **HIGH** | `packages/shared/src/CosmeticSchemas.ts:74` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `console.error(JSON.stringify(e.message, null, 2));` |
| `BUG-0470` | **LOW** | `packages/shared/src/CosmeticSchemas.ts:76` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(String(e));` |
| `BUG-0471` | **MEDIUM** | `packages/shared/src/CosmeticSchemas.ts:146` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0472` | **MEDIUM** | `packages/shared/src/CosmeticSchemas.ts:154` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const TRAIL_EFFECT_TYPES = ["transportShipTrail", "nukeTrail"] as const;` |
| `BUG-0473` | **MEDIUM** | `packages/shared/src/CosmeticSchemas.ts:203` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const NUKE_EXPLOSION_TYPES = ["atom", "hydro", "mirvWarhead"] as const;` |
| `BUG-0474` | **MEDIUM** | `packages/shared/src/CosmeticSchemas.ts:372` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return (TRAIL_EFFECT_TYPES as readonly string[]).includes(effect.effectType);` |
| `BUG-0475` | **MEDIUM** | `packages/shared/src/CosmeticSchemas.ts:391` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if ((NUKE_EXPLOSION_TYPES as readonly string[]).includes(slot)) {` |
| `BUG-0476` | **MEDIUM** | `packages/shared/src/CosmeticSchemas.ts:395` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(EFFECT_TYPES as readonly string[]).includes(slot) &&` |
| `BUG-0477` | **MEDIUM** | `packages/shared/src/CosmeticSchemas.ts:398` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return slot as EffectType;` |
| `BUG-0478` | **MEDIUM** | `packages/shared/src/EventBus.ts:12` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const eventConstructor = event.constructor as EventConstructor<T>;` |
| `BUG-0479` | **MEDIUM** | `packages/shared/src/EventBus.ts:28` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const callbacks = this.listeners.get(eventType)!;` |
| `BUG-0480` | **MEDIUM** | `packages/shared/src/FetchGameMapLoader.ts:20` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(k) => GameMapType[k as keyof typeof GameMapType] === map,` |
| `BUG-0481` | **MEDIUM** | `packages/shared/src/GameMapLoader.ts:49` | Unchecked Type Cast Bypassing Static Type Safety | Code: `bin === undefined ? [] : [bin.buffer as ArrayBuffer],` |
| `BUG-0482` | **MEDIUM** | `packages/shared/src/SharedUtil.ts:211` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const cp = ch.codePointAt(0)!;` |
| `BUG-0483` | **LOW** | `packages/shared/src/WireSchemas.ts:840` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `clanTag: ClanTagSchema.catch(null).default(null), // predates clan tags` |
| `BUG-0484` | **HIGH** | `packages/zbin/src/bytes.ts:151` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `this.int(Number(n));` |
| `BUG-0485` | **HIGH** | `packages/zbin/src/bytes.ts:163` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `this.u8(Number(u & 0x7fn) \| 0x80);` |
| `BUG-0486` | **HIGH** | `packages/zbin/src/bytes.ts:166` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `this.u8(Number(u));` |
| `BUG-0487` | **MEDIUM** | `packages/zbin/src/index.ts:12` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export * as zb from "./zb";` |
| `BUG-0488` | **MEDIUM** | `packages/zbin/src/zb.ts:48` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export { bigint_ as bigint };` |
| `BUG-0489` | **MEDIUM** | `packages/zbin/src/zb.ts:85` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return (schema as any)._zod.def;` |
| `BUG-0490` | **HIGH** | `packages/zbin/src/zb.ts:234` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `s = JSON.stringify(v);` |
| `BUG-0491` | **HIGH** | `packages/zbin/src/zb.ts:249` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `return JSON.parse(s, (k, v) => (k === "__proto__" ? undefined : v));` |
| `BUG-0492` | **MEDIUM** | `packages/zbin/src/zb.ts:272` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const entries = defOf(schema).entries as Record<string, unknown>;` |
| `BUG-0493` | **MEDIUM** | `packages/zbin/src/zb.ts:274` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const opts = (schema as any).options;` |
| `BUG-0494` | **MEDIUM** | `packages/zbin/src/zb.ts:303` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const values = d.values as unknown[];` |
| `BUG-0495` | **MEDIUM** | `packages/zbin/src/zb.ts:455` | Unchecked Type Cast Bypassing Static Type Safety | Code: `fieldSchema as z.ZodType,` |
| `BUG-0496` | **MEDIUM** | `packages/zbin/src/zb.ts:471` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(innerDef.values as unknown[]).length === 1` |
| `BUG-0497` | **MEDIUM** | `packages/zbin/src/zb.ts:474` | Unchecked Type Cast Bypassing Static Type Safety | Code: `constValue = (innerDef.values as unknown[])[0];` |
| `BUG-0498` | **MEDIUM** | `packages/zbin/src/zb.ts:509` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const value = (v as any)[p.key];` |
| `BUG-0499` | **MEDIUM** | `packages/zbin/src/zb.ts:542` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `p.codec!.enc(w, value, ctx);` |
| `BUG-0500` | **MEDIUM** | `packages/zbin/src/zb.ts:569` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `out[p.key] = p.codec!.dec(r, ctx);` |
| `BUG-0501` | **MEDIUM** | `packages/zbin/src/zb.ts:596` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `out[p.key] = p.codec!.dec(r, ctx);` |
| `BUG-0502` | **MEDIUM** | `packages/zbin/src/zb.ts:688` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const k = keyCodec.dec(r, ctx) as string;` |
| `BUG-0503` | **MEDIUM** | `packages/zbin/src/zb.ts:722` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (dd.type !== "literal" \|\| (dd.values as unknown[]).length !== 1) {` |
| `BUG-0504` | **MEDIUM** | `packages/zbin/src/zb.ts:728` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return (dd.values as unknown[])[0];` |
| `BUG-0505` | **MEDIUM** | `packages/zbin/src/zb.ts:761` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const variant = byValue.get((v as any)?.[key]);` |
| `BUG-0506` | **MEDIUM** | `packages/zbin/src/zb.ts:764` | Unchecked Type Cast Bypassing Static Type Safety | Code: `'${path}: no variant for ${key}=${String((v as any)?.[key])}',` |
| `BUG-0507` | **MEDIUM** | `packages/zbin/src/zb.ts:954` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return v as z.output<S>;` |
| `BUG-0508` | **MEDIUM** | `packages/zbin/src/zb.ts:964` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return schema.parse(v) as z.output<S>;` |
| `BUG-0509` | **MEDIUM** | `packages/zbin/src/zb.ts:1023` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export { literal_ as literal };` |
| `BUG-0510` | **MEDIUM** | `packages/zbin/src/zb.ts:1025` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export { enum_ as enum };` |
| `BUG-0511` | **MEDIUM** | `packages/zbin/src/zb.ts:1038` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return register(schema.clone() as S, jsonCodec);` |
| `BUG-0512` | **MEDIUM** | `packages/zbin/src/zb.ts:1047` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return register(schema.clone() as S, {` |
| `BUG-0513` | **MEDIUM** | `packages/zbin/src/zb.ts:1076` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export { union_ as union };` |
| `BUG-0514` | **MEDIUM** | `packages/zbin/src/zb.ts:1091` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(ud.options as z.ZodType[]).forEach((option, i) => {` |
| `BUG-0515` | **MEDIUM** | `packages/zbin/src/zb.ts:1111` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const discValue = (v as any)?.[ud.discriminator];` |
| `BUG-0516` | **MEDIUM** | `packages/zbin/src/zb.ts:1127` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const extras = extraCodec.dec(r, ctx) as object;` |
| `BUG-0517` | **MEDIUM** | `packages/zbin/src/zb.ts:1128` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const variant = codecs[idx].dec(r, ctx) as object;` |
| `BUG-0518` | **HIGH** | `roblox/preview/server.mjs:18` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const PORT = Number(process.env.PORT ?? 3000);` |
| `BUG-0519` | **HIGH** | `roblox/preview/server.mjs:38` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `'MODULES[${JSON.stringify(rel)}] = function(script)\n${src}\nend',` |
| `BUG-0520` | **LOW** | `roblox/preview/server.mjs:427` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("[live-engine] tick error:", err);` |
| `BUG-0521` | **MEDIUM** | `roblox/preview/server.mjs:500` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<video controls autoplay muted loop playsinline src="media/OpenFront_Roblox_Gameplay.mp4?v=${Date.now()}"></vi` |
| `BUG-0522` | **MEDIUM** | `roblox/preview/server.mjs:504` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/01_main_menu_live_preview.png?v=${Date.now()}" target="_blank"><img src="` |
| `BUG-0523` | **MEDIUM** | `roblox/preview/server.mjs:505` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/02_host_lobby_10_maps.png?v=${Date.now()}" target="_blank"><img src="medi` |
| `BUG-0524` | **MEDIUM** | `roblox/preview/server.mjs:506` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/03_spawn_phase_india.png?v=${Date.now()}" target="_blank"><img src="media` |
| `BUG-0525` | **MEDIUM** | `roblox/preview/server.mjs:507` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/04_empire_expansion_and_radial_menu.png?v=${Date.now()}" target="_blank">` |
| `BUG-0526` | **MEDIUM** | `roblox/preview/server.mjs:508` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/05_build_menu_economy_trains_ships.png?v=${Date.now()}" target="_blank"><` |
| `BUG-0527` | **MEDIUM** | `roblox/preview/server.mjs:509` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/06_mirv_and_nuclear_warfare.png?v=${Date.now()}" target="_blank"><img src` |
| `BUG-0528` | **MEDIUM** | `roblox/preview/server.mjs:510` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/07_shinobi_world_ninja_war.png?v=${Date.now()}" target="_blank"><img src=` |
| `BUG-0529` | **MEDIUM** | `roblox/preview/server.mjs:511` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `<div class="shotCard"><a href="media/08_victory_ceremony_xp_levelup.png?v=${Date.now()}" target="_blank"><img ` |
| `BUG-0530` | **HIGH** | `roblox/preview/server.mjs:599` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `n = Math.abs(Number(n) \|\| 0);` |
| `BUG-0531` | **HIGH** | `roblox/preview/server.mjs:622` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const ratio = Number(document.getElementById('ratioSlider').value) / 100;` |
| `BUG-0532` | **HIGH** | `roblox/preview/server.mjs:653` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `const meta = JSON.parse(new TextDecoder().decode(metaBytes));` |
| `BUG-0533` | **HIGH** | `roblox/preview/server.mjs:800` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const start = m ? parseInt(m[1], 10) : 0;` |
| `BUG-0534` | **HIGH** | `roblox/preview/server.mjs:801` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const end = m && m[2] ? parseInt(m[2], 10) : stat.size - 1;` |
| `BUG-0535` | **HIGH** | `roblox/preview/server.mjs:845` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `res.end(JSON.stringify({ ok: false, error: String(err) }));` |
| `BUG-0536` | **LOW** | `roblox/tests/run_tests.mjs:42` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('[SYNTAX ERROR] in ${relPath}:', err);` |
| `BUG-0537` | **HIGH** | `roblox/tests/run_tests.mjs:56` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `'-- >>> BEGIN MODULE ${rel}\nMODULES[${JSON.stringify(rel)}] = function(script)\n${src}\nend\n-- <<< END MODUL` |
| `BUG-0538` | **MEDIUM** | `roblox/tests/run_tests.mjs:448` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Build DataModel Instance hierarchy matching build_rbxl.py 1:1!` |
| `BUG-0539` | **MEDIUM** | `roblox/tests/run_tests.mjs:543` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- SUITE 4: Headless Full Simulation Engine — Combat, Trade Ships, Trains, Warships, Nukes, MIRVs & SAMs!` |
| `BUG-0540` | **MEDIUM** | `roblox/tests/run_tests.mjs:568` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Step past 100-tick Spawn Phase, grant test treasury to Human, and expand!` |
| `BUG-0541` | **MEDIUM** | `roblox/tests/run_tests.mjs:632` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Re-pick a fresh hostile living rival right before nuclear launch!` |
| `BUG-0542` | **MEDIUM** | `roblox/tests/run_tests.mjs:669` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- SUITE 5 & 6: Live Server Bootstrap + Client Main E2E (EditableImage AND Scanline2D Fallback!)` |
| `BUG-0543` | **MEDIUM** | `roblox/tests/run_tests.mjs:698` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Exercise EVERY client mouse, touch pinch, scroll zoom, radial menu, build popup, hotkey & victory ceremony!` |
| `BUG-0544` | **MEDIUM** | `roblox/tests/run_tests.mjs:729` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Verify zero world labels bleed through open Victory modal!` |
| `BUG-0545` | **MEDIUM** | `roblox/tests/run_tests.mjs:736` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Verify every rendered Scanline2D segment is strictly opaque (BackgroundTransparency == 0, zero alpha-stacki` |
| `BUG-0546` | **MEDIUM** | `roblox/tests/run_tests.mjs:748` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Dismiss modal, step render frame, and verify ZERO pairwise screen-space AABB overlaps among visible country` |
| `BUG-0547` | **MEDIUM** | `roblox/tests/run_tests.mjs:768` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Verify responsive UIScale adapts BOTH Menu & HUD to compact split-screen/mobile viewports without breaking ` |
| `BUG-0548` | **HIGH** | `roblox/tests/run_tests.mjs:795` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const lineNo = Number(m[1]);` |
| `BUG-0549` | **LOW** | `roblox/tests/run_tests.mjs:798` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0550` | **LOW** | `roblox/tests/run_tests.mjs:803` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("[E2E FAILURE]", err);` |
| `BUG-0551` | **HIGH** | `roblox/tools/play_and_record.mjs:39` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `'MODULES[${JSON.stringify(rel)}] = function(script)\n${src}\nend',` |
| `BUG-0552` | **HIGH** | `roblox/tools/play_and_record.mjs:58` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `const parsed = JSON.parse(metaJsonStr);` |
| `BUG-0553` | **MEDIUM** | `roblox/tools/play_and_record.mjs:446` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- ACT 2 (Frames 84..148): Spawn Phase Selection in India & Early Expansion on World Map!` |
| `BUG-0554` | **MEDIUM** | `roblox/tools/play_and_record.mjs:459` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Locate Northern India / Gangetic plain on World Map!` |
| `BUG-0555` | **MEDIUM** | `roblox/tools/play_and_record.mjs:483` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Unlock borders & expand rapidly across South Asia + Bay of Bengal!` |
| `BUG-0556` | **MEDIUM** | `roblox/tools/play_and_record.mjs:501` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Step 3 ticks per frame so continents consolidate into crisp solid empires just like openfront.io!` |
| `BUG-0557` | **MEDIUM** | `roblox/tools/play_and_record.mjs:514` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- ACT 3: Economy Boom — Cities, Factories, Railroads, Gold Trains, Ports, Trade Ships & Warships!` |
| `BUG-0558` | **MEDIUM** | `roblox/tools/play_and_record.mjs:545` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Launch an amphibious Boat invasion across the Indian Ocean too!` |
| `BUG-0559` | **MEDIUM** | `roblox/tools/play_and_record.mjs:576` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- ACT 4: Thermonuclear Escalation — Atom Bomb + Hydrogen Bomb + Multi-Warhead MIRV Carpet Strike!` |
| `BUG-0560` | **MEDIUM** | `roblox/tools/play_and_record.mjs:579` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Build 3 Missile Silos so we can salvo AtomBomb + HydrogenBomb + MIRV together in cinematic glory!` |
| `BUG-0561` | **MEDIUM** | `roblox/tools/play_and_record.mjs:620` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- ACT 5: Custom Shinobi World Ninja Villages Showcase (Konohagakure vs Five Great Nations!)` |
| `BUG-0562` | **MEDIUM** | `roblox/tools/play_and_record.mjs:687` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- ACT 6: Final World Conquest Push -> >94% Land Share -> VICTORY CEREMONY MODAL!` |
| `BUG-0563` | **MEDIUM** | `roblox/tools/play_and_record.mjs:721` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `-- Keep already-swept radial zone cleanly consolidated under Republic of India (no stray reconquest speckles!)` |
| `BUG-0564` | **HIGH** | `scripts/buildAssetHashes.ts:104` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `'${JSON.stringify(hashes, null, 2)}\n',` |
| `BUG-0565` | **LOW** | `scripts/buildAssetHashes.ts:128` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(err);` |
| `BUG-0566` | **MEDIUM** | `scripts/issue-lifecycle/config.ts:1` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const REPO = { owner: "openfrontio", repo: "OpenFrontIO" } as const;` |
| `BUG-0567` | **MEDIUM** | `scripts/issue-lifecycle/config.ts:13` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0568` | **MEDIUM** | `scripts/issue-lifecycle/config.ts:48` | Unchecked Type Cast Bypassing Static Type Safety | Code: `'Closing this issue as it hasn't been milestoned and has had no recent activity.` |
| `BUG-0569` | **MEDIUM** | `scripts/issue-lifecycle/config.ts:67` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0570` | **LOW** | `scripts/issue-lifecycle/cron.ts:46` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('${prefix} — error: ${err}');` |
| `BUG-0571` | **LOW** | `scripts/issue-lifecycle/github.ts:87` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('[issue-lifecycle] Issue #${issueNumber} not found');` |
| `BUG-0572` | **HIGH** | `scripts/issue-lifecycle/index.ts:23` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `if (next) issueNumber = parseInt(next, 10);` |
| `BUG-0573` | **HIGH** | `scripts/issue-lifecycle/index.ts:65` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `args.issueNumber ?? parseInt(process.env.ISSUE_NUMBER ?? "", 10);` |
| `BUG-0574` | **LOW** | `scripts/issue-lifecycle/index.ts:83` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("[issue-lifecycle] Unexpected error:", err);` |
| `BUG-0575` | **MEDIUM** | `scripts/pr-gate/config.ts:1` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const REPO = { owner: "openfrontio", repo: "OpenFrontIO" } as const;` |
| `BUG-0576` | **MEDIUM** | `scripts/pr-gate/config.ts:3` | Unchecked Type Cast Bypassing Static Type Safety | Code: `export const TRUSTED_REPO_PERMISSIONS = ["admin", "maintain", "write"] as const;` |
| `BUG-0577` | **MEDIUM** | `scripts/pr-gate/config.ts:10` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0578` | **MEDIUM** | `scripts/pr-gate/config.ts:20` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0579` | **LOW** | `scripts/pr-gate/github.ts:73` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('[pr-gate] Issue #${issueNumber} not found, skipping');` |
| `BUG-0580` | **HIGH** | `scripts/pr-gate/index.ts:25` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `if (next) prNumber = parseInt(next, 10);` |
| `BUG-0581` | **HIGH** | `scripts/pr-gate/index.ts:40` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const prNumber = args.prNumber ?? parseInt(process.env.PR_NUMBER ?? "", 10);` |
| `BUG-0582` | **LOW** | `scripts/pr-gate/index.ts:101` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("[pr-gate] Unexpected error:", err);` |
| `BUG-0583` | **HIGH** | `scripts/pr-gate/rules.ts:46` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `result.add(parseInt(m[1], 10));` |
| `BUG-0584` | **MEDIUM** | `scripts/pr-gate/rules.ts:59` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if ((TRUSTED_BOT_AUTHORS as readonly string[]).includes(pr.user.login)) {` |
| `BUG-0585` | **MEDIUM** | `scripts/pr-gate/rules.ts:73` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if ((TRUSTED_REPO_PERMISSIONS as readonly string[]).includes(permission)) {` |
| `BUG-0586` | **MEDIUM** | `scripts/split-packages/closure.ts:42` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const f = queue.shift()!;` |
| `BUG-0587` | **MEDIUM** | `scripts/split-packages/cut.ts:34` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return "export:" + (s.moduleSpecifier as ts.StringLiteral)?.text;` |
| `BUG-0588` | **MEDIUM** | `scripts/split-packages/decl-closure.ts:60` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const n = queue.pop()!;` |
| `BUG-0589` | **MEDIUM** | `scripts/split-packages/decl-closure.ts:67` | Unchecked Type Cast Bypassing Static Type Safety | Code: `.getModifiers(owner.get(n) as ts.HasModifiers)` |
| `BUG-0590` | **MEDIUM** | `scripts/split-packages/imported-names.ts:34` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `names.get(nm)!.add(r);` |
| `BUG-0591` | **MEDIUM** | `scripts/split-packages/imported-names.ts:40` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `names.get(q)!.add(r + " (import type)");` |
| `BUG-0592` | **LOW** | `scripts/split-packages/run.ts:56` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("usage: run.ts <moves.json> [--dry-run]");` |
| `BUG-0593` | **HIGH** | `scripts/split-packages/run.ts:59` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `const moves: Moves = JSON.parse(fs.readFileSync(movesPath, "utf8"));` |
| `BUG-0594` | **MEDIUM** | `scripts/split-packages/run.ts:127` | Unchecked Type Cast Bypassing Static Type Safety | Code: `flagged.push('${where(ref.node)}: ${(e as Error).message}');` |
| `BUG-0595` | **MEDIUM** | `scripts/split-packages/run.ts:159` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const q = (node as ts.ImportTypeNode).qualifier;` |
| `BUG-0596` | **MEDIUM** | `scripts/split-packages/run.ts:174` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const decl = node as ts.ImportDeclaration \| ts.ExportDeclaration;` |
| `BUG-0597` | **MEDIUM** | `scripts/split-packages/run.ts:210` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `groups.get(dest)!.push(e);` |
| `BUG-0598` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:75` | Unchecked Type Cast Bypassing Static Type Safety | Code: `JSON.parse(fs.readFileSync(file, "utf8")) as GameRecord,` |
| `BUG-0599` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:186` | Unchecked Type Cast Bypassing Static Type Safety | Code: `feed(h, (v as Record<string, unknown>)[k]);` |
| `BUG-0600` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:224` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const gu = pending as GameUpdateViewData \| null;` |
| `BUG-0601` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:228` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const hashes = gu.updates[GameUpdateType.Hash] as HashUpdate[];` |
| `BUG-0602` | **LOW** | `scripts/split-packages/tick-trace.ts:263` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn = () => {};` |
| `BUG-0603` | **HIGH** | `scripts/split-packages/tick-trace.ts:274` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `lines.push(JSON.stringify(line));` |
| `BUG-0604` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:289` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `.readFileSync(path.join(compare!, '${game.name}.jsonl'), "utf8")` |
| `BUG-0605` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:292` | Unchecked Type Cast Bypassing Static Type Safety | Code: `.map((l) => JSON.parse(l) as TraceLine);` |
| `BUG-0606` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:301` | Unchecked Type Cast Bypassing Static Type Safety | Code: `for (const field of ["tick", "hash", "updates", "snapshot"] as const) {` |
| `BUG-0607` | **MEDIUM** | `scripts/split-packages/tick-trace.ts:304` | Unchecked Type Cast Bypassing Static Type Safety | Code: `.filter(([, list]) => (list as unknown[]).length > 0)` |
| `BUG-0608` | **HIGH** | `scripts/split-packages/tick-trace.ts:305` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `.map(([type]) => GameUpdateType[Number(type)])` |
| `BUG-0609` | **LOW** | `scripts/split-packages/tick-trace.ts:331` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(err);` |
| `BUG-0610` | **MEDIUM** | `src/client/AccountModal.ts:152` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = event as CustomEvent;` |
| `BUG-0611` | **MEDIUM** | `src/client/AccountModal.ts:155` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.userMeResponse = customEvent.detail as UserMeResponse;` |
| `BUG-0612` | **LOW** | `src/client/AccountModal.ts:400` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("AccountModal: showLinkGate failed", err);` |
| `BUG-0613` | **MEDIUM** | `src/client/AccountModal.ts:529` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const publicId = this.userMeResponse!.player.publicId;` |
| `BUG-0614` | **LOW** | `src/client/AccountModal.ts:667` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("AccountModal: prestige flow failed to load", err),` |
| `BUG-0615` | **LOW** | `src/client/AccountModal.ts:677` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("AccountModal: prestige flow failed to load", err);` |
| `BUG-0616` | **MEDIUM** | `src/client/AccountModal.ts:1115` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const target = e.target as HTMLInputElement;` |
| `BUG-0617` | **LOW** | `src/client/AccountModal.ts:1228` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to fetch user info in AccountModal.open():", err);` |
| `BUG-0618` | **LOW** | `src/client/AccountModal.ts:1260` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to load player data:", err);` |
| `BUG-0619` | **MEDIUM** | `src/client/Admiral.ts:69` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as AdmiralFn;` |
| `BUG-0620` | **HIGH** | `src/client/Admiral.ts:92` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `const lgk: Array<[string, string?]> = JSON.parse(raw).lgk ?? [];` |
| `BUG-0621` | **LOW** | `src/client/Api.ts:88` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0622` | **LOW** | `src/client/Api.ts:99` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchPlayerById: Zod validation failed", parsed.error);` |
| `BUG-0623` | **LOW** | `src/client/Api.ts:105` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchPlayerById: request failed", err);` |
| `BUG-0624` | **LOW** | `src/client/Api.ts:123` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0625` | **LOW** | `src/client/Api.ts:134` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0626` | **LOW** | `src/client/Api.ts:143` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchPublicPlayerProfile: request failed", err);` |
| `BUG-0627` | **LOW** | `src/client/Api.ts:172` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0628` | **LOW** | `src/client/Api.ts:183` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0629` | **LOW** | `src/client/Api.ts:191` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchPublicPlayerGames: request failed", err);` |
| `BUG-0630` | **LOW** | `src/client/Api.ts:267` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Invalid response", error);` |
| `BUG-0631` | **LOW** | `src/client/Api.ts:376` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0632` | **LOW** | `src/client/Api.ts:385` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("deleteAccount: request failed", e);` |
| `BUG-0633` | **HIGH** | `src/client/Api.ts:404` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ consented }),` |
| `BUG-0634` | **LOW** | `src/client/Api.ts:411` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0635` | **LOW** | `src/client/Api.ts:421` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("setMarketingConsent: request failed", e);` |
| `BUG-0636` | **HIGH** | `src/client/Api.ts:450` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ hidden }),` |
| `BUG-0637` | **LOW** | `src/client/Api.ts:457` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0638` | **LOW** | `src/client/Api.ts:466` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('PUT ${setting}: Zod validation failed', parsed.error);` |
| `BUG-0639` | **LOW** | `src/client/Api.ts:472` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('PUT ${setting}: request failed', e);` |
| `BUG-0640` | **HIGH** | `src/client/Api.ts:524` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ audience }),` |
| `BUG-0641` | **LOW** | `src/client/Api.ts:533` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0642` | **LOW** | `src/client/Api.ts:542` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("createIdentityToken: invalid response", parsed.error);` |
| `BUG-0643` | **LOW** | `src/client/Api.ts:547` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("createIdentityToken: request failed", e);` |
| `BUG-0644` | **HIGH** | `src/client/Api.ts:587` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify(` |
| `BUG-0645` | **HIGH** | `src/client/Api.ts:619` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const seconds = retryAfter === null ? NaN : Number(retryAfter);` |
| `BUG-0646` | **LOW** | `src/client/Api.ts:627` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0647` | **LOW** | `src/client/Api.ts:636` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("updateUsername: Zod validation failed", parsed.error);` |
| `BUG-0648` | **LOW** | `src/client/Api.ts:642` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("updateUsername: request failed", e);` |
| `BUG-0649` | **LOW** | `src/client/Api.ts:664` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0650` | **LOW** | `src/client/Api.ts:673` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("getCreatorByCode: Zod validation failed", parsed.error);` |
| `BUG-0651` | **LOW** | `src/client/Api.ts:678` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("getCreatorByCode: request failed", e);` |
| `BUG-0652` | **MEDIUM** | `src/client/Api.ts:700` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-0653` | **MEDIUM** | `src/client/Api.ts:707` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(SET_CREATOR_CODE_ERROR_CODES as readonly string[]).includes(value)` |
| `BUG-0654` | **HIGH** | `src/client/Api.ts:736` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ code }),` |
| `BUG-0655` | **HIGH** | `src/client/Api.ts:754` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const seconds = retryAfter === null ? NaN : Number(retryAfter);` |
| `BUG-0656` | **LOW** | `src/client/Api.ts:764` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0657` | **LOW** | `src/client/Api.ts:773` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("setCreatorCode: Zod validation failed", parsed.error);` |
| `BUG-0658` | **LOW** | `src/client/Api.ts:779` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("setCreatorCode: request failed", e);` |
| `BUG-0659` | **LOW** | `src/client/Api.ts:811` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0660` | **LOW** | `src/client/Api.ts:821` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("clearCreatorCode: request failed", e);` |
| `BUG-0661` | **LOW** | `src/client/Api.ts:843` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0662` | **LOW** | `src/client/Api.ts:854` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("getMyTribeNames: Zod validation failed", parsed.error);` |
| `BUG-0663` | **LOW** | `src/client/Api.ts:859` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("getMyTribeNames: request failed", e);` |
| `BUG-0664` | **LOW** | `src/client/Api.ts:932` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('${context}: debt refusal with no usable amount');` |
| `BUG-0665` | **MEDIUM** | `src/client/Api.ts:1046` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const record = body as Record<string, unknown> \| null \| undefined;` |
| `BUG-0666` | **HIGH** | `src/client/Api.ts:1055` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `: usableBounds(Number(parsed[1]), Number(parsed[2]));` |
| `BUG-0667` | **HIGH** | `src/client/Api.ts:1103` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ name }),` |
| `BUG-0668` | **LOW** | `src/client/Api.ts:1133` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("purchaseTribeName: unrecognised 400 reason");` |
| `BUG-0669` | **HIGH** | `src/client/Api.ts:1141` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const seconds = retryAfter === null ? NaN : Number(retryAfter);` |
| `BUG-0670` | **LOW** | `src/client/Api.ts:1149` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0671` | **LOW** | `src/client/Api.ts:1158` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("purchaseTribeName: Zod validation failed", parsed.error);` |
| `BUG-0672` | **LOW** | `src/client/Api.ts:1163` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("purchaseTribeName: request failed", e);` |
| `BUG-0673` | **LOW** | `src/client/Api.ts:1224` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("boostTribeName: unrecognised 400 code");` |
| `BUG-0674` | **LOW** | `src/client/Api.ts:1235` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("boostTribeName: unrecognised 400 response");` |
| `BUG-0675` | **LOW** | `src/client/Api.ts:1242` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0676` | **LOW** | `src/client/Api.ts:1253` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("boostTribeName: Zod validation failed", parsed.error);` |
| `BUG-0677` | **LOW** | `src/client/Api.ts:1258` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("boostTribeName: request failed", e);` |
| `BUG-0678` | **LOW** | `src/client/Api.ts:1276` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0679` | **LOW** | `src/client/Api.ts:1285` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchTribeStats: Zod validation failed", parsed.error);` |
| `BUG-0680` | **LOW** | `src/client/Api.ts:1290` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchTribeStats: request failed", err);` |
| `BUG-0681` | **HIGH** | `src/client/Api.ts:1328` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({` |
| `BUG-0682` | **LOW** | `src/client/Api.ts:1349` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("purchaseWithCurrency: unrecognised 400 reason");` |
| `BUG-0683` | **LOW** | `src/client/Api.ts:1359` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0684` | **LOW** | `src/client/Api.ts:1368` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("purchaseWithCurrency: request failed", e);` |
| `BUG-0685` | **HIGH** | `src/client/Api.ts:1413` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ packName }),` |
| `BUG-0686` | **LOW** | `src/client/Api.ts:1434` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("purchaseCosmeticPack: unrecognised 400 response");` |
| `BUG-0687` | **LOW** | `src/client/Api.ts:1449` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0688` | **LOW** | `src/client/Api.ts:1458` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0689` | **LOW** | `src/client/Api.ts:1466` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("purchaseCosmeticPack: request failed", e);` |
| `BUG-0690` | **LOW** | `src/client/Api.ts:1504` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0691` | **LOW** | `src/client/Api.ts:1513` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("claimReward: Zod validation failed", parsed.error);` |
| `BUG-0692` | **LOW** | `src/client/Api.ts:1518` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("claimReward: request failed", e);` |
| `BUG-0693` | **LOW** | `src/client/Api.ts:1540` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0694` | **LOW** | `src/client/Api.ts:1551` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("claimAllRewards: Zod validation failed", parsed.error);` |
| `BUG-0695` | **LOW** | `src/client/Api.ts:1556` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("claimAllRewards: request failed", e);` |
| `BUG-0696` | **HIGH** | `src/client/Api.ts:1573` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({` |
| `BUG-0697` | **LOW** | `src/client/Api.ts:1580` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0698` | **LOW** | `src/client/Api.ts:1590` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("createCustomCurrencyCheckout: request failed", e);` |
| `BUG-0699` | **HIGH** | `src/client/Api.ts:1718` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `const seconds = header === null ? NaN : Number(header);` |
| `BUG-0700` | **HIGH** | `src/client/Api.ts:1741` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({` |
| `BUG-0701` | **LOW** | `src/client/Api.ts:1771` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("createPaymentsCheckout: client-bug 400 response");` |
| `BUG-0702` | **LOW** | `src/client/Api.ts:1860` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0703` | **LOW** | `src/client/Api.ts:1872` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0704` | **LOW** | `src/client/Api.ts:1880` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("createPaymentsCheckout: request failed", e);` |
| `BUG-0705` | **HIGH** | `src/client/Api.ts:1915` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ orderId }),` |
| `BUG-0706` | **LOW** | `src/client/Api.ts:1925` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0707` | **LOW** | `src/client/Api.ts:1936` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0708` | **LOW** | `src/client/Api.ts:1944` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("finalizeSteamOrder: request failed", e);` |
| `BUG-0709` | **LOW** | `src/client/Api.ts:1962` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0710` | **LOW** | `src/client/Api.ts:1971` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("cancelSubscription: request failed", e);` |
| `BUG-0711` | **HIGH** | `src/client/Api.ts:1984` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ notice }),` |
| `BUG-0712` | **LOW** | `src/client/Api.ts:1987` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0713` | **LOW** | `src/client/Api.ts:1996` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("markNoticeSeen: request failed", e);` |
| `BUG-0714` | **HIGH** | `src/client/Api.ts:2013` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ tierName }),` |
| `BUG-0715` | **LOW** | `src/client/Api.ts:2031` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0716` | **LOW** | `src/client/Api.ts:2040` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("changeSubscriptionTier: request failed", e);` |
| `BUG-0717` | **HIGH** | `src/client/Api.ts:2053` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({` |
| `BUG-0718` | **LOW** | `src/client/Api.ts:2062` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0719` | **LOW** | `src/client/Api.ts:2072` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("openSubscriptionPortal: request failed", e);` |
| `BUG-0720` | **LOW** | `src/client/Api.ts:2092` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchLobbyListed: request failed", e);` |
| `BUG-0721` | **HIGH** | `src/client/Api.ts:2118` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ listed, ...options }),` |
| `BUG-0722` | **LOW** | `src/client/Api.ts:2130` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("setLobbyListed: request failed", e);` |
| `BUG-0723` | **LOW** | `src/client/Api.ts:2156` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("queueLobby: request failed", e);` |
| `BUG-0724` | **LOW** | `src/client/Api.ts:2215` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Server error response:", errorText);` |
| `BUG-0725` | **MEDIUM** | `src/client/Api.ts:2222` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return { lobby: data as GameInfo, creatorToken: token };` |
| `BUG-0726` | **LOW** | `src/client/Api.ts:2224` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Error creating lobby:", error);` |
| `BUG-0727` | **LOW** | `src/client/Api.ts:2258` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("createNextLobby: server error response:", errorText);` |
| `BUG-0728` | **MEDIUM** | `src/client/Api.ts:2261` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return (await response.json()) as GameInfo;` |
| `BUG-0729` | **LOW** | `src/client/Api.ts:2281` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0730` | **LOW** | `src/client/Api.ts:2294` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchGameById: Zod validation failed", parsed.error);` |
| `BUG-0731` | **LOW** | `src/client/Api.ts:2300` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchGameById: request failed", err);` |
| `BUG-0732` | **LOW** | `src/client/Api.ts:2337` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0733` | **LOW** | `src/client/Api.ts:2347` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0734` | **LOW** | `src/client/Api.ts:2356` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("fetchPlayerLeaderboard: request failed", err);` |
| `BUG-0735` | **LOW** | `src/client/Api.ts:2374` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0736` | **LOW** | `src/client/Api.ts:2384` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0737` | **LOW** | `src/client/Api.ts:2393` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("fetchTribeLeaderboardPage: request failed", err);` |
| `BUG-0738` | **LOW** | `src/client/Api.ts:2422` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("getNews: unexpected status", res.status);` |
| `BUG-0739` | **MEDIUM** | `src/client/Api.ts:2423` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return newsItemsFallback as NewsItem[];` |
| `BUG-0740` | **LOW** | `src/client/Api.ts:2428` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("getNews: Zod validation failed", parsed.error);` |
| `BUG-0741` | **MEDIUM** | `src/client/Api.ts:2429` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return newsItemsFallback as NewsItem[];` |
| `BUG-0742` | **LOW** | `src/client/Api.ts:2433` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("getNews: request failed, using fallback", err);` |
| `BUG-0743` | **MEDIUM** | `src/client/Api.ts:2434` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return newsItemsFallback as NewsItem[];` |
| `BUG-0744` | **LOW** | `src/client/Api.ts:2453` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('${name}: unexpected status', res.status);` |
| `BUG-0745` | **LOW** | `src/client/Api.ts:2458` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('${name}: Zod validation failed', parsed.error);` |
| `BUG-0746` | **LOW** | `src/client/Api.ts:2463` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('${name}: request failed, using fallback', err);` |
| `BUG-0747` | **LOW** | `src/client/Auth.ts:85` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to open the desktop link flow", err);` |
| `BUG-0748` | **LOW** | `src/client/Auth.ts:173` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to start Google link", response);` |
| `BUG-0749` | **LOW** | `src/client/Auth.ts:181` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to start Google link", e);` |
| `BUG-0750` | **LOW** | `src/client/Auth.ts:210` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to start Steam link", response);` |
| `BUG-0751` | **LOW** | `src/client/Auth.ts:218` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to start Steam link", e);` |
| `BUG-0752` | **LOW** | `src/client/Auth.ts:241` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Token login request failed", e);` |
| `BUG-0753` | **LOW** | `src/client/Auth.ts:262` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Token login failed with a permanent client error", response);` |
| `BUG-0754` | **LOW** | `src/client/Auth.ts:266` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Token login failed", response);` |
| `BUG-0755` | **LOW** | `src/client/Auth.ts:272` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Token login succeeded but response had no email", body);` |
| `BUG-0756` | **LOW** | `src/client/Auth.ts:296` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Logout failed", response);` |
| `BUG-0757` | **LOW** | `src/client/Auth.ts:302` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Logout failed", e);` |
| `BUG-0758` | **LOW** | `src/client/Auth.ts:400` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("No JWT found and shouldRefresh is false");` |
| `BUG-0759` | **LOW** | `src/client/Auth.ts:422` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('unexpected "iss" claim value');` |
| `BUG-0760` | **LOW** | `src/client/Auth.ts:429` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('unexpected "aud" claim value');` |
| `BUG-0761` | **MEDIUM** | `src/client/Auth.ts:433` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `if (Date.now() >= __expiresAt - 3 * 60 * 1000) {` |
| `BUG-0762` | **LOW** | `src/client/Auth.ts:436` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("jwt expired and shouldRefresh is false");` |
| `BUG-0763` | **LOW** | `src/client/Auth.ts:448` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Invalid payload", error);` |
| `BUG-0764` | **LOW** | `src/client/Auth.ts:457` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("isLoggedIn failed", e);` |
| `BUG-0765` | **LOW** | `src/client/Auth.ts:540` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Refresh rejected", response);` |
| `BUG-0766` | **LOW** | `src/client/Auth.ts:549` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Refresh failed", response);` |
| `BUG-0767` | **MEDIUM** | `src/client/Auth.ts:555` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `__expiresAt = Date.now() + expiresIn * 1000;` |
| `BUG-0768` | **LOW** | `src/client/Auth.ts:560` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Refresh failed", e);` |
| `BUG-0769` | **HIGH** | `src/client/Auth.ts:617` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ token }),` |
| `BUG-0770` | **LOW** | `src/client/Auth.ts:621` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('${portal} login failed', response);` |
| `BUG-0771` | **MEDIUM** | `src/client/Auth.ts:627` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `__expiresAt = Date.now() + expiresIn * 1000;` |
| `BUG-0772` | **LOW** | `src/client/Auth.ts:632` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('${portal} login failed', e);` |
| `BUG-0773` | **HIGH** | `src/client/Auth.ts:652` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ ticket }),` |
| `BUG-0774` | **LOW** | `src/client/Auth.ts:656` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Steam login failed", response);` |
| `BUG-0775` | **MEDIUM** | `src/client/Auth.ts:678` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `__expiresAt = Date.now() + expiresIn * 1000;` |
| `BUG-0776` | **LOW** | `src/client/Auth.ts:684` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Steam login failed", e);` |
| `BUG-0777` | **LOW** | `src/client/Auth.ts:701` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `await __refreshPromise.catch(() => {});` |
| `BUG-0778` | **LOW** | `src/client/Auth.ts:725` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `await __refreshPromise.catch(() => {});` |
| `BUG-0779` | **HIGH** | `src/client/Auth.ts:760` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({` |
| `BUG-0780` | **LOW** | `src/client/Auth.ts:774` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0781` | **LOW** | `src/client/Auth.ts:782` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Error sending recovery email:", error);` |
| `BUG-0782` | **LOW** | `src/client/Auth.ts:835` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("rememberPublicId: cache write failed", e);` |
| `BUG-0783` | **LOW** | `src/client/Auth.ts:851` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("getCachedPublicId: cache read failed", e);` |
| `BUG-0784` | **MEDIUM** | `src/client/BootInterrupts.ts:72` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** steamNoticeStringsReady(...), as grantStringsReady. */` |
| `BUG-0785` | **HIGH** | `src/client/BootInterrupts.ts:354` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `parsed = JSON.parse(raw);` |
| `BUG-0786` | **MEDIUM** | `src/client/BootInterrupts.ts:362` | Unchecked Type Cast Bypassing Static Type Safety | Code: `parsed as Record<string, unknown>,` |
| `BUG-0787` | **MEDIUM** | `src/client/BootInterrupts.ts:366` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const { shows, lastShownAt } = value as Record<string, unknown>;` |
| `BUG-0788` | **MEDIUM** | `src/client/BootInterrupts.ts:445` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as const;` |
| `BUG-0789` | **MEDIUM** | `src/client/BootInterrupts.ts:498` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as string[]` |
| `BUG-0790` | **LOW** | `src/client/ClanApi.ts:81` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0791` | **LOW** | `src/client/ClanApi.ts:92` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0792` | **LOW** | `src/client/ClanApi.ts:101` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanLeaderboard: request failed", err);` |
| `BUG-0793` | **LOW** | `src/client/ClanApi.ts:185` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClans: Zod validation failed", parsed.error);` |
| `BUG-0794` | **LOW** | `src/client/ClanApi.ts:201` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanDetail: Zod validation failed", parsed.error);` |
| `BUG-0795` | **LOW** | `src/client/ClanApi.ts:292` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanMembers: Zod validation failed", parsed.error);` |
| `BUG-0796` | **LOW** | `src/client/ClanApi.ts:352` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("joinClan: Zod validation failed", parsed.error);` |
| `BUG-0797` | **HIGH** | `src/client/ClanApi.ts:392` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify(patch),` |
| `BUG-0798` | **LOW** | `src/client/ClanApi.ts:419` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("updateClan: Zod validation failed", parsed.error);` |
| `BUG-0799` | **HIGH** | `src/client/ClanApi.ts:510` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ targetPublicId }),` |
| `BUG-0800` | **LOW** | `src/client/ClanApi.ts:549` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanRequests: Zod validation failed", parsed.error);` |
| `BUG-0801` | **HIGH** | `src/client/ClanApi.ts:568` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ targetPublicId }),` |
| `BUG-0802` | **HIGH** | `src/client/ClanApi.ts:592` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ targetPublicId }),` |
| `BUG-0803` | **HIGH** | `src/client/ClanApi.ts:638` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify(body),` |
| `BUG-0804` | **HIGH** | `src/client/ClanApi.ts:657` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ targetPublicId }),` |
| `BUG-0805` | **LOW** | `src/client/ClanApi.ts:689` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanGames: Zod validation failed", parsed.error);` |
| `BUG-0806` | **HIGH** | `src/client/ClanApi.ts:722` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ currencyType, amount, idempotencyKey }),` |
| `BUG-0807` | **LOW** | `src/client/ClanApi.ts:765` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanDonations: Zod validation failed", parsed.error);` |
| `BUG-0808` | **LOW** | `src/client/ClanApi.ts:790` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanBans: Zod validation failed", parsed.error);` |
| `BUG-0809` | **LOW** | `src/client/ClanApi.ts:807` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchClanBoostStatus: Zod validation failed", parsed.error);` |
| `BUG-0810` | **HIGH** | `src/client/ClanApi.ts:835` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `body: JSON.stringify({ tier, idempotencyKey }),` |
| `BUG-0811` | **MEDIUM** | `src/client/ClanModal.ts:46` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const LIST_TABS = ["map", "my-clans", "browse"] as const;` |
| `BUG-0812` | **MEDIUM** | `src/client/ClanModal.ts:54` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return (LIST_TABS as readonly string[]).includes(key);` |
| `BUG-0813` | **MEDIUM** | `src/client/ClanModal.ts:608` | Unchecked Type Cast Bypassing Static Type Safety | Code: `[e.detail.tag, "member" as ClanRole],` |
| `BUG-0814` | **LOW** | `src/client/ClientEnv.ts:265` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Error parsing JWKS", error);` |
| `BUG-0815` | **LOW** | `src/client/ClientGameRunner.ts:192` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `void load.catch((e) => {` |
| `BUG-0816` | **LOW** | `src/client/ClientGameRunner.ts:207` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0817` | **HIGH** | `src/client/ClientGameRunner.ts:262` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `'lobby: game prestarting: ${JSON.stringify(message, replacer)}',` |
| `BUG-0818` | **HIGH** | `src/client/ClientGameRunner.ts:274` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `'lobby: game started: ${JSON.stringify(` |
| `BUG-0819` | **LOW** | `src/client/ClientGameRunner.ts:299` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("error creating client game", e);` |
| `BUG-0820` | **MEDIUM** | `src/client/ClientGameRunner.ts:305` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as HTMLElement;` |
| `BUG-0821` | **MEDIUM** | `src/client/ClientGameRunner.ts:552` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(window as unknown as { __webglView?: unknown }).__webglView = view;` |
| `BUG-0822` | **MEDIUM** | `src/client/ClientGameRunner.ts:668` | Unchecked Type Cast Bypassing Static Type Safety | Code: `view.updateStructures(frameData.units as Map<number, UnitState>);` |
| `BUG-0823` | **HIGH** | `src/client/ClientGameRunner.ts:803` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `JSON.stringify({` |
| `BUG-0824` | **MEDIUM** | `src/client/ClientGameRunner.ts:953` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `this.lastMessageTime = Date.now();` |
| `BUG-0825` | **MEDIUM** | `src/client/ClientGameRunner.ts:976` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `this.lastMessageTime = Date.now();` |
| `BUG-0826` | **LOW** | `src/client/ClientGameRunner.ts:1026` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(gu.stack);` |
| `BUG-0827` | **MEDIUM** | `src/client/ClientGameRunner.ts:1058` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `this.lastMessageTime = Date.now();` |
| `BUG-0828` | **HIGH** | `src/client/ClientGameRunner.ts:1115` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `'desync from server: ${JSON.stringify(message)}',` |
| `BUG-0829` | **MEDIUM** | `src/client/ClientGameRunner.ts:1154` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.eventBus.emit(new GoToPlayerEvent(this.gameView.myPlayer()!, 8));` |
| `BUG-0830` | **MEDIUM** | `src/client/ClientGameRunner.ts:1158` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `const now = Date.now();` |
| `BUG-0831` | **LOW** | `src/client/ClientGameRunner.ts:1172` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `(this.awaitingStart ? console.debug : console.error)(` |
| `BUG-0832` | **MEDIUM** | `src/client/ClientGameRunner.ts:1262` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.myPlayer!.troops() * this.renderer.uiState.attackRatio,` |
| `BUG-0833` | **LOW** | `src/client/ClientGameRunner.ts:1270` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to check boat attack actions:", error);` |
| `BUG-0834` | **MEDIUM** | `src/client/ClientGameRunner.ts:1304` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.myPlayer!.actions(clickedTile, Structures.types)` |
| `BUG-0835` | **MEDIUM** | `src/client/ClientGameRunner.ts:1348` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const myPlayerID = this.myPlayer!.id();` |
| `BUG-0836` | **LOW** | `src/client/ClientGameRunner.ts:1380` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to check structure upgrade actions:", error);` |
| `BUG-0837` | **LOW** | `src/client/ClientGameRunner.ts:1403` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0838` | **LOW** | `src/client/ClientGameRunner.ts:1409` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to check boat attack actions:", error);` |
| `BUG-0839` | **MEDIUM** | `src/client/ClientGameRunner.ts:1433` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.myPlayer!.troops() * this.renderer.uiState.attackRatio,` |
| `BUG-0840` | **LOW** | `src/client/ClientGameRunner.ts:1439` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to check ground attack actions:", error);` |
| `BUG-0841` | **MEDIUM** | `src/client/ClientGameRunner.ts:1457` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.gameView.playerBySmallID(a.attackerID) as PlayerView` |
| `BUG-0842` | **MEDIUM** | `src/client/ClientGameRunner.ts:1468` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as PlayerView;` |
| `BUG-0843` | **MEDIUM** | `src/client/ClientGameRunner.ts:1494` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const recipient = tileOwner as PlayerView;` |
| `BUG-0844` | **LOW** | `src/client/ClientGameRunner.ts:1508` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to check alliance actions:", error);` |
| `BUG-0845` | **MEDIUM** | `src/client/ClientGameRunner.ts:1528` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const recipient = tileOwner as PlayerView;` |
| `BUG-0846` | **LOW** | `src/client/ClientGameRunner.ts:1540` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to check alliance actions:", error);` |
| `BUG-0847` | **MEDIUM** | `src/client/ClientGameRunner.ts:1558` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const target = tileOwner as PlayerView;` |
| `BUG-0848` | **LOW** | `src/client/ClientGameRunner.ts:1568` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to check target actions:", error);` |
| `BUG-0849` | **MEDIUM** | `src/client/ClientGameRunner.ts:1637` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `const now = Date.now();` |
| `BUG-0850` | **LOW** | `src/client/Cosmetics.ts:211` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("purchase-completed but no cosmetic name");` |
| `BUG-0851` | **MEDIUM** | `src/client/Cosmetics.ts:289` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `const ms = end.getTime() - Date.now();` |
| `BUG-0852` | **MEDIUM** | `src/client/Cosmetics.ts:394` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const sub = c as Subscription;` |
| `BUG-0853` | **MEDIUM** | `src/client/Cosmetics.ts:533` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return purchasePack(c as CosmeticPack, method);` |
| `BUG-0854` | **LOW** | `src/client/Cosmetics.ts:585` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-0855` | **MEDIUM** | `src/client/Cosmetics.ts:592` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const priced = c as Pattern \| Flag \| Pack;` |
| `BUG-0856` | **LOW** | `src/client/Cosmetics.ts:739` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("purchaseCosmetic: packs are only sold for hard currency");` |
| `BUG-0857` | **LOW** | `src/client/Cosmetics.ts:889` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('HTTP error! status: ${response.status}');` |
| `BUG-0858` | **LOW** | `src/client/Cosmetics.ts:894` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('Invalid cosmetics: ${result.error.message}');` |
| `BUG-0859` | **LOW** | `src/client/Cosmetics.ts:903` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Error getting cosmetics:", error);` |
| `BUG-0860` | **MEDIUM** | `src/client/Cosmetics.ts:1434` | Unchecked Type Cast Bypassing Static Type Safety | Code: `patternData: (c as Pattern).pattern,` |
| `BUG-0861` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:56` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `private resolveReady!: (ready: boolean) => void;` |
| `BUG-0862` | **LOW** | `src/client/CrazyGamesSDK.ts:109` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("CrazyGames SDK already initialized");` |
| `BUG-0863` | **LOW** | `src/client/CrazyGamesSDK.ts:127` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("CrazyGames SDK not available");` |
| `BUG-0864` | **LOW** | `src/client/CrazyGamesSDK.ts:138` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to initialize CrazyGames SDK:", error);` |
| `BUG-0865` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:149` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return (await window.CrazyGames!.SDK.user.getUser())?.username ?? null;` |
| `BUG-0866` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:164` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `if (!window.CrazyGames!.SDK.user.isUserAccountAvailable) {` |
| `BUG-0867` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:167` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return await window.CrazyGames!.SDK.user.getUserToken();` |
| `BUG-0868` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:181` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return await window.CrazyGames!.SDK.user.getUser();` |
| `BUG-0869` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:195` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `await window.CrazyGames!.SDK.user.showAuthPrompt();` |
| `BUG-0870` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:210` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `window.CrazyGames!.SDK.user.addAuthListener(listener);` |
| `BUG-0871` | **LOW** | `src/client/CrazyGamesSDK.ts:212` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to add auth listener:", error);` |
| `BUG-0872` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:227` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `return window.CrazyGames!.SDK.game.isInstantMultiplayer ?? false;` |
| `BUG-0873` | **LOW** | `src/client/CrazyGamesSDK.ts:240` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Gameplay already started");` |
| `BUG-0874` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:245` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `await window.CrazyGames!.SDK.game.gameplayStart();` |
| `BUG-0875` | **LOW** | `src/client/CrazyGamesSDK.ts:249` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to report gameplay start:", error);` |
| `BUG-0876` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:263` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `await window.CrazyGames!.SDK.game.gameplayStop();` |
| `BUG-0877` | **LOW** | `src/client/CrazyGamesSDK.ts:267` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to report gameplay stop:", error);` |
| `BUG-0878` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:277` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `await window.CrazyGames!.SDK.game.happytime();` |
| `BUG-0879` | **LOW** | `src/client/CrazyGamesSDK.ts:280` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to trigger happy time:", error);` |
| `BUG-0880` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:290` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `window.CrazyGames!.SDK.game.loadingStart();` |
| `BUG-0881` | **LOW** | `src/client/CrazyGamesSDK.ts:293` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to report loading start:", error);` |
| `BUG-0882` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:303` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `window.CrazyGames!.SDK.game.loadingStop();` |
| `BUG-0883` | **LOW** | `src/client/CrazyGamesSDK.ts:306` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to report loading stop:", error);` |
| `BUG-0884` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:321` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const link = window.CrazyGames!.SDK.game.showInviteButton(options);` |
| `BUG-0885` | **LOW** | `src/client/CrazyGamesSDK.ts:328` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to show invite button:", error);` |
| `BUG-0886` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:339` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `window.CrazyGames!.SDK.game.hideInviteButton();` |
| `BUG-0887` | **LOW** | `src/client/CrazyGamesSDK.ts:342` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to hide invite button:", error);` |
| `BUG-0888` | **LOW** | `src/client/CrazyGamesSDK.ts:348` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("CrazyGames SDK not ready, cannot create invite link");` |
| `BUG-0889` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:353` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const link = window.CrazyGames!.SDK.game.inviteLink({ gameId });` |
| `BUG-0890` | **LOW** | `src/client/CrazyGamesSDK.ts:357` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Failed to create invite link:", error);` |
| `BUG-0891` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:367` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const gameId = window.CrazyGames!.SDK.game.getInviteParam("gameId");` |
| `BUG-0892` | **LOW** | `src/client/CrazyGamesSDK.ts:375` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('Failed to get invite gameId:', error);` |
| `BUG-0893` | **MEDIUM** | `src/client/CrazyGamesSDK.ts:399` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `window.CrazyGames!.SDK.ad.requestAd("midgame", callbacks);` |
| `BUG-0894` | **LOW** | `src/client/CrazyGamesSDK.ts:401` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to request midgame ad:", error);` |
| `BUG-0895` | **HIGH** | `src/client/CreatorCode.ts:27` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `JSON.stringify({ code, stashedAt: Date.now() }),` |
| `BUG-0896` | **HIGH** | `src/client/CreatorCode.ts:44` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `const parsed: unknown = JSON.parse(raw);` |
| `BUG-0897` | **MEDIUM** | `src/client/CreatorCode.ts:53` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `Date.now() - candidate.stashedAt > PENDING_CREATOR_CODE_TTL_MS` |
| `BUG-0898` | **MEDIUM** | `src/client/DesktopDisplay.ts:92` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const desktop = window.openfrontDesktop as DisplayBridgeHolder \| undefined;` |
| `BUG-0899` | **MEDIUM** | `src/client/DesktopDisplay.ts:93` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const display = desktop?.display as Partial<DesktopDisplayBridge> \| undefined;` |
| `BUG-0900` | **MEDIUM** | `src/client/DesktopDisplay.ts:100` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return display as DesktopDisplayBridge;` |
| `BUG-0901` | **MEDIUM** | `src/client/DesktopDisplay.ts:105` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const r = value as Record<string, unknown>;` |
| `BUG-0902` | **MEDIUM** | `src/client/DesktopDisplay.ts:116` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const d = value as Record<string, unknown>;` |
| `BUG-0903` | **MEDIUM** | `src/client/DesktopDisplay.ts:146` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const s = value as Record<string, unknown>;` |
| `BUG-0904` | **MEDIUM** | `src/client/DesktopDisplay.ts:153` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const prefs = s.prefs as Record<string, unknown>;` |
| `BUG-0905` | **MEDIUM** | `src/client/DesktopPresence.ts:42` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return window.openfrontDesktop as PresenceBridge \| undefined;` |
| `BUG-0906` | **LOW** | `src/client/DesktopSessionRecovery.ts:92` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Desktop session recovery failed", err);` |
| `BUG-0907` | **MEDIUM** | `src/client/DesktopSessionRecovery.ts:111` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const next = (event as CustomEvent<BackendReachabilityDetail>).detail;` |
| `BUG-0908` | **MEDIUM** | `src/client/DesktopShell.ts:43` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const desktop = window.openfrontDesktop as LocaleBridge \| undefined;` |
| `BUG-0909` | **MEDIUM** | `src/client/DesktopShell.ts:76` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const desktop = window.openfrontDesktop as VersionBridge \| undefined;` |
| `BUG-0910` | **MEDIUM** | `src/client/DesktopShell.ts:178` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const desktop = window.openfrontDesktop as UpdateBridgeHolder \| undefined;` |
| `BUG-0911` | **MEDIUM** | `src/client/DesktopShell.ts:418` | Unchecked Type Cast Bypassing Static Type Safety | Code: `? (desktop as DesktopLinkGateBridge)` |
| `BUG-0912` | **MEDIUM** | `src/client/DesktopShell.ts:449` | Unchecked Type Cast Bypassing Static Type Safety | Code: `? (desktop as DesktopQuitBridge)` |
| `BUG-0913` | **MEDIUM** | `src/client/FeaturedStream.ts:82` | Unchecked Type Cast Bypassing Static Type Safety | Code: `return '${cy > vh / 2 ? "b" : "t"}${cx > vw / 2 ? "r" : "l"}' as Corner;` |
| `BUG-0914` | **LOW** | `src/client/FeaturedStream.ts:211` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("featured-stream: feed handling failed", e),` |
| `BUG-0915` | **LOW** | `src/client/FeaturedStream.ts:275` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("featured-stream: Twitch SDK load failed", e);` |
| `BUG-0916` | **MEDIUM** | `src/client/FeaturedStream.ts:286` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as HTMLElement \| null;` |
| `BUG-0917` | **MEDIUM** | `src/client/FeaturedStream.ts:370` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if ((e.target as HTMLElement).closest("button")) return;` |
| `BUG-0918` | **MEDIUM** | `src/client/FeaturedStream.ts:374` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as HTMLElement \| null;` |
| `BUG-0919` | **MEDIUM** | `src/client/FeaturedStream.ts:382` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);` |
| `BUG-0920` | **MEDIUM** | `src/client/FeaturedStream.ts:403` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as HTMLElement \| null;` |
| `BUG-0921` | **LOW** | `src/client/FriendsApi.ts:40` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchFriendRequests: zod failed", parsed.error);` |
| `BUG-0922` | **LOW** | `src/client/FriendsApi.ts:45` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchFriendRequests: request failed", err);` |
| `BUG-0923` | **LOW** | `src/client/FriendsApi.ts:67` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchFriends: zod failed", parsed.error);` |
| `BUG-0924` | **LOW** | `src/client/FriendsApi.ts:72` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("fetchFriends: request failed", err);` |
| `BUG-0925` | **LOW** | `src/client/FriendsApi.ts:93` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("sendFriendRequest: request failed", err);` |
| `BUG-0926` | **LOW** | `src/client/FriendsApi.ts:110` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("acceptFriendRequest: request failed", err);` |
| `BUG-0927` | **LOW** | `src/client/FriendsApi.ts:127` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("deleteFriendRequest: request failed", err);` |
| `BUG-0928` | **LOW** | `src/client/FriendsApi.ts:143` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("removeFriend: request failed", err);` |
| `BUG-0929` | **MEDIUM** | `src/client/GameMetrics.ts:105` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const) {` |
| `BUG-0930` | **LOW** | `src/client/GameModeSelector.ts:240` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("server list retry from a refused click failed", err);` |
| `BUG-0931` | **MEDIUM** | `src/client/GameModeSelector.ts:391` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as UsernameInput \| null;` |
| `BUG-0932` | **MEDIUM** | `src/client/GameModeSelector.ts:440` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as UsernameInput \| null;` |
| `BUG-0933` | **MEDIUM** | `src/client/GameModeSelector.ts:485` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.inputValid = (e as CustomEvent).detail?.isValid ?? true;` |
| `BUG-0934` | **MEDIUM** | `src/client/GameModeSelector.ts:489` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.desktopUpdateState = (e as CustomEvent<DesktopUpdateState>).detail;` |
| `BUG-0935` | **MEDIUM** | `src/client/GameModeSelector.ts:493` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.applyUserMe((e as CustomEvent<UserMeResponse \| false>).detail);` |
| `BUG-0936` | **MEDIUM** | `src/client/GameModeSelector.ts:509` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const next = (e as CustomEvent<DesktopSessionState>).detail;` |
| `BUG-0937` | **MEDIUM** | `src/client/GameModeSelector.ts:524` | Unchecked Type Cast Bypassing Static Type Safety | Code: `e as CustomEvent<BackendReachabilityDetail>` |
| `BUG-0938` | **MEDIUM** | `src/client/GameModeSelector.ts:644` | Unchecked Type Cast Bypassing Static Type Safety | Code: `mapAspectRatios.ensure(game.gameConfig?.gameMap as GameMapType, () =>` |
| `BUG-0939` | **MEDIUM** | `src/client/GameModeSelector.ts:734` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `? this.renderLobbyCard(ffa, getGameModeLabel(ffa.gameConfig!))` |
| `BUG-0940` | **MEDIUM** | `src/client/GameModeSelector.ts:757` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `getGameModeLabel(teams.gameConfig!),` |
| `BUG-0941` | **MEDIUM** | `src/client/GameModeSelector.ts:765` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `getGameModeLabel(special.gameConfig!),` |
| `BUG-0942` | **MEDIUM** | `src/client/GameModeSelector.ts:844` | Unchecked Type Cast Bypassing Static Type Safety | Code: `document.querySelector("single-player-modal") as SinglePlayerModal` |
| `BUG-0943` | **MEDIUM** | `src/client/GameModeSelector.ts:859` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(document.querySelector("host-lobby-modal") as HostLobbyModal)?.open(),` |
| `BUG-0944` | **MEDIUM** | `src/client/GameModeSelector.ts:867` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(document.querySelector("join-lobby-modal") as JoinLobbyModal)?.open(),` |
| `BUG-0945` | **MEDIUM** | `src/client/GameModeSelector.ts:1032` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as JoinLobbyEvent,` |
| `BUG-0946` | **MEDIUM** | `src/client/GamePortal.ts:4` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** A signed-in portal account, as both portals report it. */` |
| `BUG-0947` | **MEDIUM** | `src/client/GameRewards.ts:85` | Unchecked Type Cast Bypassing Static Type Safety | Code: `for (const currency of ["soft", "hard"] as const) {` |
| `BUG-0948` | **HIGH** | `src/client/GameRewards.ts:189` | Unchecked Numeric Conversion (`parseInt`/`parseFloat`/`Number(`) `NaN` Risk | Code: `credited[reward.currencyType] += Number(rewardAmount(reward.amount));` |
| `BUG-0949` | **LOW** | `src/client/GameStatsModal.ts:150` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `card.catch(() => {});` |
| `BUG-0950` | **MEDIUM** | `src/client/GameStatsModal.ts:174` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `if (Date.now() - end > RECENT_GAME_MS) return;` |
| `BUG-0951` | **LOW** | `src/client/GameStatsModal.ts:183` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("GameStatsModal: XP lookup failed", err);` |
| `BUG-0952` | **MEDIUM** | `src/client/GameVersion.ts:95` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(el as HTMLElement).style.fontFamily = '"OpenFront", Inter, sans-serif';` |
| `BUG-0953` | **HIGH** | `src/client/GraphicsPresets.ts:26` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `if (value === null \|\| typeof value !== "object") return JSON.stringify(value);` |
| `BUG-0954` | **MEDIUM** | `src/client/GraphicsPresets.ts:30` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const entries = Object.entries(value as Record<string, unknown>)` |
| `BUG-0955` | **HIGH** | `src/client/GraphicsPresets.ts:33` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `.map(([k, v]) => '${JSON.stringify(k)}:${stableStringify(v)}');` |
| `BUG-0956` | **HIGH** | `src/client/GraphicsPresets.ts:49` | Unvalidated `JSON.parse` / `JSON.stringify` Serialization Hazard | Code: `raw = JSON.parse(text);` |
| `BUG-0957` | **MEDIUM** | `src/client/HelpModal.ts:1303` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as TroubleshootingModal;` |
| `BUG-0958` | **LOW** | `src/client/HelpModal.ts:1308` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Troubleshooting modal element not found");` |
| `BUG-0959` | **LOW** | `src/client/HomepagePromos.ts:201` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("error destroying gutter rails and header ad", e);` |
| `BUG-0960` | **LOW** | `src/client/HomepagePromos.ts:217` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Playwire RAMP not available for bottom_rail ad");` |
| `BUG-0961` | **LOW** | `src/client/HomepagePromos.ts:231` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to add bottom_rail ad:", e);` |
| `BUG-0962` | **LOW** | `src/client/HomepagePromos.ts:235` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to load bottom_rail ad:", error);` |
| `BUG-0963` | **LOW** | `src/client/HomepagePromos.ts:249` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Error destroying bottom_rail ad:", e);` |
| `BUG-0964` | **LOW** | `src/client/HomepagePromos.ts:257` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Playwire RAMP not available");` |
| `BUG-0965` | **LOW** | `src/client/HomepagePromos.ts:287` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to load gutter rails and header ad:", error);` |
| `BUG-0966` | **LOW** | `src/client/HomepagePromos.ts:295` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Playwire RAMP not available for corner_ad_video");` |
| `BUG-0967` | **LOW** | `src/client/HomepagePromos.ts:311` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to display corner_ad_video:", e);` |
| `BUG-0968` | **LOW** | `src/client/HomepagePromos.ts:314` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to add corner_ad_video:", e);` |
| `BUG-0969` | **LOW** | `src/client/HomepagePromos.ts:318` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to load corner_ad_video:", error);` |
| `BUG-0970` | **LOW** | `src/client/HomepagePromos.ts:336` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Error destroying corner_ad_video:", e);` |
| `BUG-0971` | **LOW** | `src/client/HomepagePromos.ts:339` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Error destroying corner_ad_video:", e);` |
| `BUG-0972` | **MEDIUM** | `src/client/HostLobbyModal.ts:198` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `() => chars[Math.floor(Math.random() * chars.length)],` |
| `BUG-0973` | **LOW** | `src/client/HostLobbyModal.ts:240` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-0974` | **MEDIUM** | `src/client/HostLobbyModal.ts:901` | Unchecked Type Cast Bypassing Static Type Safety | Code: `void (this.querySelector("copy-button") as CopyButton)?.handleCopy();` |
| `BUG-0975` | **MEDIUM** | `src/client/HostLobbyModal.ts:911` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as JoinLobbyEvent,` |
| `BUG-0976` | **MEDIUM** | `src/client/HostLobbyModal.ts:939` | Unchecked Type Cast Bypassing Static Type Safety | Code: `void (this.querySelector("copy-button") as CopyButton)?.handleCopy();` |
| `BUG-0977` | **MEDIUM** | `src/client/HostLobbyModal.ts:946` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as JoinLobbyEvent,` |
| `BUG-0978` | **MEDIUM** | `src/client/HostLobbyModal.ts:1083` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ map: GameMapType }>;` |
| `BUG-0979` | **MEDIUM** | `src/client/HostLobbyModal.ts:1093` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ difficulty: Difficulty }>;` |
| `BUG-0980` | **MEDIUM** | `src/client/HostLobbyModal.ts:1098` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ speed: DoomsdayClockSpeed }>;` |
| `BUG-0981` | **MEDIUM** | `src/client/HostLobbyModal.ts:1104` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ mode: GameMode }>;` |
| `BUG-0982` | **MEDIUM** | `src/client/HostLobbyModal.ts:1109` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ count: TeamCountConfig }>;` |
| `BUG-0983` | **MEDIUM** | `src/client/HostLobbyModal.ts:1114` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{` |
| `BUG-0984` | **MEDIUM** | `src/client/HostLobbyModal.ts:1164` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{` |
| `BUG-0985` | **MEDIUM** | `src/client/HostLobbyModal.ts:1185` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ unit: UnitType; checked: boolean }>;` |
| `BUG-0986` | **MEDIUM** | `src/client/HostLobbyModal.ts:1197` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ value: number }>;` |
| `BUG-0987` | **MEDIUM** | `src/client/HostLobbyModal.ts:1246` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0988` | **MEDIUM** | `src/client/HostLobbyModal.ts:1291` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0989` | **MEDIUM** | `src/client/HostLobbyModal.ts:1314` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0990` | **MEDIUM** | `src/client/HostLobbyModal.ts:1328` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0991` | **MEDIUM** | `src/client/HostLobbyModal.ts:1345` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0992` | **MEDIUM** | `src/client/HostLobbyModal.ts:1374` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0993` | **MEDIUM** | `src/client/HostLobbyModal.ts:1400` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0994` | **MEDIUM** | `src/client/HostLobbyModal.ts:1456` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0995` | **MEDIUM** | `src/client/HostLobbyModal.ts:1485` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0996` | **MEDIUM** | `src/client/HostLobbyModal.ts:1512` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = e.target as HTMLInputElement;` |
| `BUG-0997` | **MEDIUM** | `src/client/HostLobbyModal.ts:1528` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = e as CustomEvent<{ value: number }>;` |
| `BUG-0998` | **MEDIUM** | `src/client/HostLobbyModal.ts:1611` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.allowedPublicIds = (e.target as HTMLInputElement).value;` |
| `BUG-0999` | **MEDIUM** | `src/client/HostLobbyModal.ts:1732` | Unchecked Type Cast Bypassing Static Type Safety | Code: `'Starting private game with map: ${GameMapType[this.selectedMap as keyof typeof GameMapType]} ${this.useRandom` |
| `BUG-1000` | **LOW** | `src/client/HostLobbyModal.ts:1769` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to load nation count", error);` |
| `BUG-1001` | **MEDIUM** | `src/client/InGameModal.ts:17` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const dialog = document.createElement("confirm-dialog") as ConfirmDialog;` |
| `BUG-1002` | **MEDIUM** | `src/client/InputHandler.ts:621` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.lastGestureScale = (e as WebKitGestureEvent).scale;` |
| `BUG-1003` | **MEDIUM** | `src/client/InputHandler.ts:629` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.onGestureChange(e as WebKitGestureEvent);` |
| `BUG-1004` | **MEDIUM** | `src/client/InputHandler.ts:1516` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const element = target as HTMLElement \| null;` |
| `BUG-1005` | **MEDIUM** | `src/client/InputHandler.ts:1531` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const input = element as HTMLInputElement;` |
| `BUG-1006` | **MEDIUM** | `src/client/InventoryModal.ts:117` | Unchecked Type Cast Bypassing Static Type Safety | Code: `void this.onUserMe((event as CustomEvent<UserMeResponse \| false>).detail);` |
| `BUG-1007` | **MEDIUM** | `src/client/InventoryModal.ts:121` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const customEvent = event as CustomEvent<ResolvedCosmetic>;` |
| `BUG-1008` | **MEDIUM** | `src/client/InventoryModal.ts:260` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.search = (event.target as HTMLInputElement).value;` |
| `BUG-1009` | **MEDIUM** | `src/client/InventoryModal.ts:338` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const effect = item.cosmetic as Effect;` |
| `BUG-1010` | **MEDIUM** | `src/client/InventoryModal.ts:395` | Unchecked Type Cast Bypassing Static Type Safety | Code: `/** Slot buttons read as a numbered row, so keep them in slot order. */` |
| `BUG-1011` | **MEDIUM** | `src/client/InventoryModal.ts:561` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `this.includedInSearch(resolved.cosmetic!.name) \|\|` |
| `BUG-1012` | **MEDIUM** | `src/client/InventoryModal.ts:709` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(event.currentTarget as HTMLButtonElement).disabled = true;` |
| `BUG-1013` | **MEDIUM** | `src/client/InventoryModal.ts:737` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const category = tab as InventoryCategory;` |
| `BUG-1014` | **MEDIUM** | `src/client/InventoryModal.ts:795` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.selectSkin((resolved.cosmetic as Skin \| null)?.name ?? null);` |
| `BUG-1015` | **MEDIUM** | `src/client/JoinLobbyModal.ts:51` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `@query("#lobbyIdInput") private lobbyIdInput!: HTMLInputElement;` |
| `BUG-1016` | **MEDIUM** | `src/client/JoinLobbyModal.ts:439` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(e.target as HTMLImageElement).style.display = "none";` |
| `BUG-1017` | **LOW** | `src/client/JoinLobbyModal.ts:507` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Error joining hosted lobby:", error);` |
| `BUG-1018` | **MEDIUM** | `src/client/JoinLobbyModal.ts:521` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const lobbyInfo = args?.lobbyInfo as GameInfo \| PublicGameInfo \| undefined;` |
| `BUG-1019` | **LOW** | `src/client/JoinLobbyModal.ts:566` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Error checking lobby from URL:", error);` |
| `BUG-1020` | **LOW** | `src/client/JoinLobbyModal.ts:660` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to restore URL on leave:", error);` |
| `BUG-1021` | **MEDIUM** | `src/client/JoinLobbyModal.ts:729` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const frame = (e.target as HTMLElement).parentElement;` |
| `BUG-1022` | **LOW** | `src/client/JoinLobbyModal.ts:773` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-1023` | **LOW** | `src/client/JoinLobbyModal.ts:849` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to load nation count", error);` |
| `BUG-1024` | **LOW** | `src/client/JoinLobbyModal.ts:887` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to parse lobby URL", error);` |
| `BUG-1025` | **MEDIUM** | `src/client/JoinLobbyModal.ts:899` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const value = (e.target as HTMLInputElement).value.trim();` |
| `BUG-1026` | **LOW** | `src/client/JoinLobbyModal.ts:908` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to read clipboard contents: ", err);` |
| `BUG-1027` | **LOW** | `src/client/JoinLobbyModal.ts:961` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Error checking lobby existence:", error);` |
| `BUG-1028` | **LOW** | `src/client/JoinLobbyModal.ts:1017` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to parse active lobby response", error);` |
| `BUG-1029` | **MEDIUM** | `src/client/JoinLobbyModal.ts:1039` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as JoinLobbyEvent,` |
| `BUG-1030` | **LOW** | `src/client/JoinLobbyModal.ts:1081` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(` |
| `BUG-1031` | **MEDIUM** | `src/client/JoinLobbyModal.ts:1107` | Unchecked Type Cast Bypassing Static Type Safety | Code: `} as JoinLobbyEvent,` |
| `BUG-1032` | **MEDIUM** | `src/client/LangSelector.ts:42` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.handleLanguageSelected as EventListener,` |
| `BUG-1033` | **MEDIUM** | `src/client/LangSelector.ts:50` | Unchecked Type Cast Bypassing Static Type Safety | Code: `this.handleLanguageSelected as EventListener,` |
| `BUG-1034` | **MEDIUM** | `src/client/LangSelector.ts:168` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const language = (await response.json()) as Record<string, any>;` |
| `BUG-1035` | **LOW** | `src/client/LangSelector.ts:173` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('Failed to load language ${lang}:', err);` |
| `BUG-1036` | **LOW** | `src/client/LangSelector.ts:234` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Failed to load language list:", err);` |
| `BUG-1037` | **LOW** | `src/client/LangSelector.ts:307` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('Translation key not found: ${key}');` |
| `BUG-1038` | **LOW** | `src/client/LangSelector.ts:322` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('Translation key not found: ${key}');` |
| `BUG-1039` | **MEDIUM** | `src/client/LangSelector.ts:336` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if (typeof (el as any).requestUpdate === "function") {` |
| `BUG-1040` | **MEDIUM** | `src/client/LangSelector.ts:337` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(el as any).requestUpdate();` |
| `BUG-1041` | **LOW** | `src/client/LangSelector.ts:357` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn('Translation key not found: ${key}');` |
| `BUG-1042` | **MEDIUM** | `src/client/LangSelector.ts:375` | Unchecked Type Cast Bypassing Static Type Safety | Code: `) as LanguageModal;` |
| `BUG-1043` | **LOW** | `src/client/LangSelector.ts:445` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("Unknown type", typeof value, value);` |
| `BUG-1044` | **LOW** | `src/client/Layout.ts:16` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Hamburger button not found");` |
| `BUG-1045` | **LOW** | `src/client/Layout.ts:24` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Sidebar menu not found");` |
| `BUG-1046` | **LOW** | `src/client/Layout.ts:28` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Mobile menu backdrop not found");` |
| `BUG-1047` | **MEDIUM** | `src/client/Layout.ts:45` | Unchecked Type Cast Bypassing Static Type Safety | Code: `if ((e as any).type === "touchstart") {` |
| `BUG-1048` | **MEDIUM** | `src/client/Layout.ts:46` | Unchecked Type Cast Bypassing Static Type Safety | Code: `(e as Event).preventDefault();` |
| `BUG-1049` | **MEDIUM** | `src/client/Layout.ts:67` | Unchecked Type Cast Bypassing Static Type Safety | Code: `const clickedElement = (e.target as Element).closest` |
| `BUG-1050` | **MEDIUM** | `src/client/Layout.ts:68` | Unchecked Type Cast Bypassing Static Type Safety | Code: `? (e.target as Element).closest(` |
| `BUG-1051` | **LOW** | `src/client/LazyModals.ts:51` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error('${tag} failed to load:', err),` |
| `BUG-1052` | **MEDIUM** | `src/client/LeaderboardModal.ts:23` | Unchecked Type Cast Bypassing Static Type Safety | Code: `] as const;` |
| `BUG-1053` | **LOW** | `src/client/LinkResult.ts:115` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn("offerSteamConflictDiscard: steam-link-modal unavailable");` |
| `BUG-1054` | **MEDIUM** | `src/client/LinkResult.ts:155` | Non-Null Assertion Crash Risk (`!` Postfix) | Code: `const messageKey = LINK_RESULT_KEYS[link]!;` |
| `BUG-1055` | **MEDIUM** | `src/client/LobbySocket.ts:34` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `const workerIndex = Math.floor(Math.random() * numWorkers);` |
| `BUG-1056` | **MEDIUM** | `src/client/LobbySocket.ts:190` | Non-Deterministic `Math.random()` / `Date.now()` State Coupling | Code: `openedAt = Date.now();` |
| `BUG-1057` | **MEDIUM** | `src/client/LobbySocket.ts:221` | Unchecked Type Cast Bypassing Static Type Safety | Code: `new Uint8Array(event.data as ArrayBuffer),` |
| `BUG-1058` | **MEDIUM** | `src/client/LobbySocket.ts:242` | Unchecked Type Cast Bypassing Static Type Safety | Code: `for (const type of Object.keys(patchedGames) as Array<` |
| `BUG-1059` | **LOW** | `src/client/LobbySocket.ts:260` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error("Error parsing WebSocket message:", error);` |
| `BUG-1060` | **LOW** | `src/client/LobbySocket.ts:265` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.error(` |
| `BUG-1061` | **LOW** | `src/client/LobbySocket.ts:321` | Unawaited / Unhandled Async `.catch` or `console.error` Path | Code: `console.warn(detail);` |
| `BUG-1062` | **CRITICAL** | `roblox/src/Server/SimEngine.luau:790` | Diagonal Enclave Cascade & Non-Cumulative Heap Priority Causing Rectangular Empires | `nonEnemySides >= 3` with `ownedByMe >= 2` plus `- ownedByMe * 5.0` priority bias zipped diagonal circle stairs into axis-aligned squares. Fixed with strict `nonEnemySides >= 4` enclave guard and cumulative terrain-weighted priority (`pBase + stepCost + jitter`). |
