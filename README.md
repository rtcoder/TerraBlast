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

Choose an arena with `--map twin_forts` or `--map two_islands`. Local player count is `--players 2` through `--players 10`; dedicated gameplay remains 1v1. Invalid modes, maps, ports and counts exit with code 2.

```sh
# Reproducible, renderer-free JSON summary
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -- --mode simulate --map two_islands --players 2 --shots 20 --seed 123
```

The extended tests also use UDP 19176 and verify CLI determinism on both maps. See [terrain](docs/terrain.md) and [weapons](docs/weapons.md) for collision, damage falloff, replay and limits.

## Match controls and diagnostics

P opens the match menu: local time, movement and projectile playback pause; online matches keep running on the server. F5 configures a new local match (arena, 2–10 players, rules preset), F6 shows controls. The match menu also offers surrender. Match results show final statistics and a restart button; only the blue network slot can restart the server match.

Rule presets: `classic` preserves defaults, `quick` uses 20-second turns and a 30-turn draw limit, `training` starts players at 500 HP. Configure horizontal X-axis wind through `GameRulesConfig.wind` (default zero). The server transfers its validated configuration to clients. Protocol v2 requires complete configuration and transfer IDs; client and server must use the same version.

Scoreboard includes shots, hits, enemy HP damage and eliminations. The last 32 shot summaries are retained; HP labels update above living pawns. F3 now includes HUD text scaling, trajectory visibility, a high-contrast crosshair and Restore defaults. These preferences never alter core rules.

Use the [portable tools](tools/README.md) for launchers, map auditing, environment diagnostics, replay verification, export presets and test JSON reports. A full offline headless workflow is defined in `.github/workflows/godot.yml`; Nakama and renderer checks remain explicit local options.
