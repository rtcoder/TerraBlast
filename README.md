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

F5 selects **Hotseat** (default: both teams controlled locally) or **Solo**. In solo, you control the blue team; red players are bots. `easy` evaluates fewer candidate shots than `normal`. Both use the same weapon rules and ammunition as human players. Bots aim and fire from their current position; they do not move or jump. During a bot turn you can use the camera and menus, but cannot move or fire for the bot. Opening a local menu or losing focus pauses bot planning.

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
