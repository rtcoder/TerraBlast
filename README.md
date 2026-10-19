# TerraBlast

Desktop-first Godot 4.6 voxel artillery with a shared pure GDScript simulation, local play and a dedicated ENet server. Nakama handles development guest accounts, lobbies and 1v1 matchmaking.

## Run

```sh
# Local 5v5 hot-seat match (default)
/Applications/Godot.app/Contents/MacOS/Godot --path game
# Dedicated server, two players, UDP 19170
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -- --mode server
# Run twice for two network players
/Applications/Godot.app/Contents/MacOS/Godot --path game -- --mode client --host 127.0.0.1
```

`--port 19170` overrides the gameplay port for server and client. `--mode local-dev` selects local play. See [Nakama setup](docs/backend.md) for guest login, lobbies and matchmaking; gameplay server allocation is manual in this development prototype.

## Controls

- Mouse: orbit/aim; wheel: zoom.
- WASD/arrows: move active player; Space: jump.
- Hold RMB: aim and display trajectory.
- While aiming, hold LMB to charge; release LMB to fire.
- Release RMB or press Esc to cancel charging. Esc releases cursor; recapturing it cannot fire.
- 1/2/3: bazooka / grenade / drill missile. Grenade bounces until its fuse; drill penetrates a bounded number of destructible voxels. Metal stops the drill.
- R: restart (network match: blue player only).
- F2: multiplayer panel, guest login, lobby create/join, 1v1 matchmaking and gameplay server connection.

HUD shows turn, team HP, weapon, ammo, timer and flight state. Dead players are skipped; eliminating the last opposing team ends the match. Unsupported players are eliminated. Restart restores terrain, players, ammo and turn state.

## Tests

```sh
bash tools/run_godot_tests.sh
# Also test running Nakama and actual macOS rendering:
RUN_NAKAMA_TESTS=1 RUN_RENDER_TESTS=1 bash tools/run_godot_tests.sh
```

The runner fails on Godot script errors as well as nonzero exits. Network tests use UDP 19173; bootstrap smoke uses 19174, and the separate-process gameplay smoke uses 19175. Set `GODOT_BIN` for another installation. Nakama smoke requires the local Compose stack. Render smoke saves `/tmp/terrablast-mvp.png`.

## Boundaries

- `scripts/core`: rules/resources, weapons, 30 Hz simulation, match state and resolution.
- `scripts/client`: input, HUD, preview/playback, temporary VFX and procedural audio; never authoritative network damage.
- `scripts/networking`: validated commands/results, terrain deltas, chunk snapshots and ENet adapters.
- `scripts/server`: headless entrypoint; no rendering or UI scenes.

Initial/recovery transfers use chunk snapshots. Normal shots send final voxel deltas and authoritative match results. ENet identities are assigned local development slots; production authentication, server allocation and internet deployment are outside this prototype.

## Extended local tools

- Tab (hold): individual HP and elimination scoreboard.
- F3: volume/mute, mouse sensitivity/invert Y, window/fullscreen. Validated preferences persist in Godot `user://preferences.cfg` and never change authoritative rules.
- F1: local diagnostics (gravity, weapon damage, turn and mesh counts); `[` / `]` adjust local gravity. Disabled for network clients.
- F4: retry the same gameplay connection and resume its reserved player slot. Reconnect token stays in memory; reservation expires after the server's configured grace period.
- Opening a panel, changing turn or losing application focus cancels charging. Weapon selection is remembered per pawn; restart clears it.
- F2 also provides matchmaking cancellation.

Choose an arena with `--map twin_forts`, `--map two_islands` or `--map canyon_bridge`. Local and dedicated player count is `--players 2` through `--players 10`; dedicated servers default to 2. Invalid modes, maps, ports and counts exit with code 2.

```sh
# Reproducible, renderer-free JSON summary
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -- --mode simulate --map two_islands --players 2 --shots 20 --seed 123
```

The extended tests also use UDP 19176 and verify CLI determinism on all three maps. See [terrain](docs/terrain.md) and [weapons](docs/weapons.md) for collision, damage falloff, replay and limits.

## Match controls and diagnostics

P opens the match menu: local time, movement and projectile playback pause; online matches keep running on the server. F5 configures a new local match (arena, 2–10 players, rules preset), F6 shows controls. The match menu also offers surrender. Match results show final statistics and a restart button; in auto mode only blue_1 can restart the server match; lobby mode uses unanimous rematch votes.

Rule presets: `classic` preserves defaults, `quick` uses 20-second turns and a 30-turn draw limit, `training` starts players at 500 HP. Configure horizontal X-axis wind through `GameRulesConfig.wind` (default zero). The server transfers its validated configuration to clients. Protocol v2 requires complete configuration and transfer IDs; client and server must use the same version.

Scoreboard includes shots, hits, enemy HP damage and eliminations. The last 32 shot summaries are retained; HP labels update above living pawns. F3 now includes HUD text scaling, trajectory visibility, a high-contrast crosshair and Restore defaults. These preferences never alter core rules.

Use the [portable tools](tools/README.md) for launchers, map auditing, environment diagnostics, replay verification, export presets and test JSON reports. A full offline headless workflow is defined in `.github/workflows/godot.yml`; Nakama and renderer checks remain explicit local options.

## Solo, saves and replay

F5 selects **Hotseat** (default: both teams controlled locally) or **Solo**. In solo, select the human team; the opposing team is controlled by bots. `easy` evaluates fewer candidate shots than `normal`. Both use the same weapon rules and ammunition as human players. Bots aim and fire from their current position; they do not move or jump. During a bot turn you can use the camera and menus, but cannot move or fire for the bot. Opening a local menu or losing focus pauses bot planning.

P opens the local match menu with checkpoint and replay controls:

- **Save game / Load game** stores or restores `user://last_session.json`: current terrain, players, turn, ammunition and solo settings. Loading verifies the file before replacing the match.
- **Export replay / Inspect last replay** uses `user://last_replay.json`: the initial state and recorded actions, verified against the final state hash. It is an action recording, not a resumable checkpoint.
- In replay, **Next action** advances one recorded action and **Beginning** returns to the start. The counter includes simulation ticks and movement as well as shots. Return restores the previous match; gameplay input is disabled while watching.

`user://` is Godot's application data directory (Project → Open User Data Folder in the editor), not the repository. These files are overwritten by the next successful save. Saving during projectile flight is disabled. Local checkpoint/replay operations are disabled during network play: the authoritative online match remains on the server. Recording is limited to 100000 actions and 256 shots; reaching a limit stops recording with a visible error while the match continues. Debug gravity changes start a new recording. After loading a checkpoint, a new replay starts from that checkpoint; it does not recover actions before the save.

```sh
# Both sides controlled by the planner; summary and replay are separate files
python3 tools/launch.py simulate --map two_islands --bots easy --shots 6 --record /tmp/solo-replay.json --output /tmp/solo-summary.json
python3 tools/launch.py replay --replay /tmp/solo-replay.json
```

Omit `--bots` to retain the original seeded diagnostic shooter. `--bots` and `--record` apply only to `simulate`; use F5 to select solo in the graphical client.

## Online match lobby: 2v2 and 5v5

```sh
python3 tools/launch.py server --map canyon_bridge --players 4 --lobby --port 19170
# Separate 5v5 server:
python3 tools/launch.py server --map canyon_bridge --players 10 --lobby --port 19171
```

Use F2 to connect each client to the server host and port. F7 opens the authoritative match lobby: set your display name (1–24 characters), then select Ready. Everyone must connect and be ready before the match starts. Editing a name clears that player's readiness. Names persist across reconnects and rematches. F7 displays all slots and their connection/readiness states; it does not pause the server.

Losing any player pauses match time and gameplay until the full configured roster reconnects. F4 retries using the in-memory resume token while its reservation is valid. After a lobby match ends, every connected player must vote for a rematch; votes can be cancelled. A successful vote resets the match and returns everyone to readiness selection. Disconnect clears readiness and rematch votes. The lobby offers **Disconnect to local** to start a fresh local match.

Omit `--lobby` for legacy auto start once all configured slots connect; the default remains 1v1. Nakama provides separate metagame services. Start and allocate gameplay servers manually; matchmaking does not provision these processes.

### Local library, playback and key bindings

**F8** opens the local library (also available from the match menu). Enter a name to save a checkpoint or replay. Select an entry to open, rename, or delete it; deletion asks for confirmation. The two import buttons copy the previous quick save / last replay into the library. Quick save and export remain available from the match menu. Saving and loading require a local match between shots.

The replay inspector supports Play/Pause, 0.25×–4× speed, time seeking, Next action, Next shot and Beginning. With the timeline focused, Left/Right step through actions and Home/End seek to the bounds. Return to match restores the live match and airborne velocities. Opening another overlay pauses playback. Recorded time measures simulation ticks; projectile presentation time is not part of this timeline. Seeking reconstructs state from the initial snapshot, so long recordings can take longer to seek.

**F3** includes editable bindings for movement, jump, weapons, restart, scoreboard and the match menu. Select an action and press its new key; Escape cancels. Conflicts are rejected. Arrow movement, Escape, F1–F12 and debug brackets are reserved. Bindings use physical keys and are saved separately in `user://bindings.cfg`; defaults restore the original WASD/Space/1–3/R/Tab/P layout.

Library files live in `user://archive_library`: up to 100 entries, each at most 32 MiB, with an independent generated ID. Names are 1–48 characters. Existing v1/v2 quick saves and exact float64 replay archives remain readable. Corrupt entries are reported without replacing the current match.

Read-only CLI checks (paths containing spaces must be quoted):

```sh
python3 tools/launch.py library --library-dir /absolute/path/to/archive_library
python3 tools/launch.py library --library-dir /absolute/path/to/archive_library --verify-library
```

Listing validates envelopes and reports metadata; `--verify-library` also decodes checkpoints and re-simulates replays to verify their hashes. Both return JSON and exit 2 on invalid entries. Library paths must have no symlink components; on macOS use `/private/tmp`, rather than the `/tmp` alias, for temporary fixtures.

### Training, local series and accessibility

F5 remembers the last local configuration and supports named profiles, quick hotseat/solo templates, the human team and best-of 1/3/5 series. Restart, surrender and replacing a local match require confirmation. F3 can enable the hotseat handoff screen and three rotating autosave slots. **Continue autosave** restores the latest valid slot and reports skipped damaged saves.

Open **Training** from the local match menu. Eleven lessons cover movement, jumping, cancelling aim, accuracy, power, wind, weapons, safe fire, shots without trajectory help, streaks and an ammunition budget. Each lesson operates on a private copy of the current match. Retry lesson or Retry last shot restores its checkpoint; Return to original match restores the original runner and recording. Coach hints are budgeted and invalidated by state changes; demonstrations do not count as the user's attempts. Training completion is stored separately from gameplay settings.

F3 adds reduced animation, accessible team colors with letter labels, configurable crosshair, toggle aiming, two-click charging, event captions and separate effects/cue volume. Settings and match panels scroll in small windows, with keyboard focus kept within the visible panel.

### Archive search and analysis

The library supports title search, ordering, favorites, pages, details, duplicate entries, JSON file import/export and corrupt-entry diagnostics. Filters and favorites persist separately from archive payloads. Replay analysis reconstructs its own runner in bounded batches and can be cancelled; it reports players, weapons, turns, shots, terrain and eliminations. Shot bookmarks, previous-shot/next-turn navigation, looping and fingerprint-checked saved cursors extend the inspector. Analysis exports JSON or player/shot CSV. See [tool commands](tools/README.md#replay-analysis-and-library-inspection) for headless analysis and comparison.

F2 supports saved connection profiles and a persistent local guest identity. Connection feedback distinguishes authentication, websocket connection, snapshot loading and gameplay readiness. Snapshot transfers are queued with frame budgets, and later match results are applied after the frozen snapshot so joining clients cannot lose intervening shots.

### Arena Workshop, competitions and Replay Studio

The local match menu now opens **Arena Workshop** and **Local competition**. Workshop edits a private map document (boxes, carves, spawns, metadata), previews voxel slices, supports undo/redo and TOML import/export, and launches disposable playtests. Returning restores the original match and recording; unsaved edits require an explicit discard choice.

Local competitions support 2–8 teams, single/double round-robin leagues and seeded knockout brackets with byes. The hub shows fixtures, standings, results and corrections; active fixtures can be saved/resumed. Knockout draws are replayed. Team identities stay stable across display-name changes. Return to game restores the original live match and best-of series.

Replay Studio extends the existing inspector with fingerprint-bound notes, note navigation and verified action-range clips. The library can pin and compare replays, inspect player/inventory/terrain differences, and export or import validated ZIP bundles as new entries. Studio operates on private replay state; source archives stay protected. Details and CLI commands are in [portable tools](tools/README.md).

Servers can opt into up to six **spectators** and bounded **lobby chat**. Spectators receive authoritative snapshots and follow-camera controls but cannot act, vote or satisfy player readiness. See [spectators and chat](docs/network-spectators.md).

[Scenario matrices](docs/scenario-matrices.md) run bounded, reproducible batches with recording verification, checksummed resume, repeatability checks, regression comparisons and offline reports.
