# GameSpice Timer

Speedrun timers for Godot 4: bunny-hop, surf, climb courses, and anything else run against the clock. Zones, tracks and stages, styles, practice checkpoints, records in memory, a file or SQL, points and ranks, replays, and a HUD, for 2D and 3D alike.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to timing. The reasoning is in [docs/](docs/README.md).

**Only GameSpice Core is a dependency.** Not GameSpice Player Controller, not GameSpice Net, not GameSpice Server, not GameSpice SQL (its driver is held duck-typed). That is load-bearing: [timing.md](docs/timing.md#why-it-depends-on-nothing).

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/timing.md](docs/timing.md) | `GSTimer`, `GSTimerRun`, the tick rate, start/finish/pause rules, `can_record`, wiring to a controller, 2D |
| [docs/zones.md](docs/zones.md) | zones and zone files, the painter, zone checks, stages, practice checkpoints |
| [docs/records.md](docs/records.md) | `GSTimerStore` and its three implementations, points, the manager's filing |
| [docs/replays.md](docs/replays.md) | the replay container, recorder, player, and writing them to disk |
| [docs/hud.md](docs/hud.md) | `GSTimerHud` |
| [docs/testing.md](docs/testing.md) | the suites, the store contract, adding a check |
| [docs/history.md](docs/history.md) | the bugs the suites and the games found, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/gs_timer/core/` | data and pure functions: config, track, zone, zone set, style (the records half), run, record, sample, rules, points, rank titles |
| `addons/gs_timer/runtime/` | `GSTimer` (one player), `GSTimerManager` (the node a game adds), zone index, practice checkpoints |
| `addons/gs_timer/zones/` | authoring: `GSTimerZoneVolume3D` / `2D`, `GSTimerZonePainter` (in-game, two marks a zone) |
| `addons/gs_timer/store/` | `GSTimerStore` (abstract, every read awaited), memory, file, SQL |
| `addons/gs_timer/replay/` | container (quantised, delta-encoded), recorder, player |
| `addons/gs_timer/net/` | `GSTimerNet`: what replicates, without importing GameSpice Net |
| `addons/gs_timer/ui/` | `GSTimerHud` and `GSTimerSplitsPanel` (stage-splits sidebar): no art |
| `examples/` | `timer_selftest`, `timer_2d_selftest`, `timer_records_selftest`, `timer_sql_live`, `timer_store_contract.gd`, `hud_preview`, `splits_preview` (for a screenshot) |

## Running and testing

- The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timer_selftest.tscn`, `timer_2d_selftest.tscn` and `timer_records_selftest.tscn`; `../gs-sql/tools/test_live.sh . res://examples/timer_sql_live.tscn` against the three databases for anything in the SQL store. [testing](docs/testing.md)
- The 2D suite is not a formality: it found a bug in the shared code on its first run.
- A change here is not done until game-airdrift's and game-playlot's suites agree; three of the bugs here were found from a game.
- The HUD is checked by a picture: `tools/screenshot.sh gs-timer out.png --scene res://examples/hud_preview.tscn` from game-dev.

## Rules that bite

Short forms; the reasoning is in the linked file.

**Time**

- A time is whole ticks minus the start fraction plus the finish fraction (the finishing tick is never counted by `advance`, so its fraction is ADDED). One formula: `GSTimerNet.Finish` uses the run's, never a copy. [timing](docs/timing.md#a-time-is-a-tick-count-plus-two-fractions)
- A signed distance of exactly zero is the boundary, neither side. [timing](docs/timing.md#a-time-is-a-tick-count-plus-two-fractions)
- `sv_tickrate` goes in `server.cfg`, never `autoexec.cfg`; `GSTimerConfig.tick_rate = 0` asks the engine. A wrong rate errors nowhere and doubles every time. [timing](docs/timing.md#the-tick-rate)
- `set_tick_rate` abandons runs in progress, on purpose. The engine-rate warning is for an authoritative timer only. [timing](docs/timing.md#the-tick-rate)
- A run starts on LEAVING the start zone; standing in it again ends a live run as a reset. [timing](docs/timing.md#the-timer)
- Zones on another track are reported, never acted on. [timing](docs/timing.md#the-timer)
- **The timer never moves, kills or teleports anybody.** It emits `effect_requested`, `stage_requested`, `teleport_requested`; the host acts. [timing](docs/timing.md#the-timer)
- `authoritative` is a security boundary: a non-authoritative timer never files. [timing](docs/timing.md#what-can_record-refuses)
- `is_inside(kind)` answers for EFFECT zones only; `in_zone(kind)` is membership. [timing](docs/timing.md#the-timer)
- `clamp_prespeed` caps HORIZONTAL speed only, and runs inside the simulation on both machines. [timing](docs/timing.md#wiring-it-to-a-controller)
- Call `tick_player` from the simulated tick, never `_process`. [timing](docs/timing.md#wiring-it-to-a-controller)
- A 2D game's zones are flattened on Z (`flatten_for_2d`, automatic in `GSTimerZoneVolume2D`); a zero-thickness box contains nothing. [timing](docs/timing.md#2d)

**Zones**

- A zone is data, not a node. Zone ids are never reused. [zones](docs/zones.md#zones-are-data)
- `problems()` is per zone, `route_problems()` per track (START, END, SPAWN, RESPAWN, stages); there is no track-agnostic respawn. `meta.pitless_tracks` exempts a route. [zones](docs/zones.md#checking-a-zone-file)
- `thin_zones()` is judged per axis; the fall speed defaults to the run speed on purpose. `hull_extent` widens only RESPAWN/TELEPORT (hull-overlap kinds), default 0. [zones](docs/zones.md#checking-a-zone-file)
- `fingerprint()` ignores comments and ids. [zones](docs/zones.md#checking-a-zone-file)
- A stage zone without a `destination` sends the player to `Vector3.ZERO`, silently. A stage out of range is refused, never clamped; going to a stage stops the run. [zones](docs/zones.md#stages)
- Saving a checkpoint is free, loading taints the attempt, and the taint is sticky. `GSTimerManager.allow_checkpoints` (does practice exist) is not `GSTimerStyle.allow_checkpoints` (may a practised run rank). [zones](docs/zones.md#practice-checkpoints)

**Records and replays**

- A store never decides whether a record is allowed; `can_record` does, on the authoritative timer. [records](docs/records.md#the-store)
- Every store read is awaited; only `peek_*` is synchronous, and `null` there means "not known yet". [records](docs/records.md#the-store)
- `examples/timer_store_contract.gd` runs unchanged against every store: add a check there, never a copy. [records](docs/records.md#one-contract-three-stores)
- Filenames from ids go through `GSTimerStoreFile.safe_component`, never a second sanitiser. [records](docs/records.md#the-file-store)
- The file store must be flushed (the manager does it every `flush_seconds` and on exit) and refuses an empty directory. [records](docs/records.md#the-file-store)
- SQL: improvements are conditional (`WHERE time > ?`); never write `SET a = ..., b = a + ...` (MySQL reads the new `a`). [records](docs/records.md#the-sql-store)
- A board is re-scored whenever its record changes. Ranks are shared by ties. [records](docs/records.md#points)
- `player_id` is a per-scope pseudonymous id, never a site user id. [records](docs/records.md#the-store)
- Replays sample at a time, never step per frame; yaw the short way round; never blend across a teleport frame. [replays](docs/replays.md#playback)
- Only a kept run's replay is written, after its run-out; a failed write is logged, never turned into a refused record. [replays](docs/replays.md#writing-to-disk)

## Where a game plugs in

| To change | Where |
| --- | --- |
| How a server is configured | `GSTimerConfig`, layered like every `GSConfig` |
| What the tick rate is | `sv_tickrate` in `server.cfg`; `GSTimerConfig.tick_rate = 0` asks the engine |
| Whether practice mode exists | `GSTimerManager.allow_checkpoints` |
| Whether a practised run may rank | `GSTimerStyle.allow_checkpoints` |
| Where records live | `GSTimerStore` subclass on `GSTimerManager.store`; `GSTimerStoreSql` for a database |
| How records are scored | `GSTimerConfig.points_formula` (curve / tiered / placement), `points_weighting` |
| What standings are called | `GSTimerManager.titles = GSTimerRankTitles.from_array(...)` |
| Start rules | `GSTimerStyle.start_speed_cap`, `start_ground_seconds`, `refuse_vertical_start`; a start zone's payload overrides |
| Whether every stage must be passed | `GSTimerConfig.enforce_stages`, or the zone file's `meta.enforce_stages` |
| A shortcut a map closes | `VALIDATOR` / `CHECKER` zones, paired by `number` |
| What a style is worth | `GSTimerStyle`, and `points_for` to change the formula |
| How the movement changes per style | `GSFpsStyle` in GameSpice Player Controller |
| A new kind of volume | `GSTimerZone.Kind.CUSTOM` plus `payload`, read on `effect_requested` |
| What a teleport / respawn / slay does | `effect_requested`, always |
| The map's difficulty tier | `GSTimerZoneSet.meta["tier"]`, or override `GSTimerManager.map_tier` |
| How zones are authored | `GSTimerZoneVolume3D` / `2D`, or `GSTimerZonePainter` |
| What the HUD looks like | `GSTimerHud` exports, or a subclass |
| Speed units on the HUD | `GSTimerHud._stats_line` and the `u/s` conversion |
| What replicates | `GSTimerNet.RunState` / `Finish`, written by a GameSpice Net bridge |
| Replay flags (ducked, jumped, teleported) | the `replay_flags` argument of `tick_player` |

Deliberately not here: chat commands, menus, a cross-game ranking, sending records off the server (GameSpice Leaderboard), drawing a ghost, the save-and-restore of a segmented run's position, and anti-cheat beyond the structural refusals. [timing](docs/timing.md#deliberately-not-here)
