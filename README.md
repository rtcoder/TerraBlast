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

The runner fails on Godot script errors as well as nonzero exits. Network tests use UDP 19173; bootstrap smoke uses 19174. Set `GODOT_BIN` for another installation. Nakama smoke requires the local Compose stack. Render smoke saves `/tmp/terrablast-mvp.png`.

## Boundaries

- `scripts/core`: rules/resources, weapons, 30 Hz simulation, match state and resolution.
- `scripts/client`: input, HUD, preview/playback, temporary VFX and procedural audio; never authoritative network damage.
- `scripts/networking`: validated commands/results, terrain deltas, chunk snapshots and ENet adapters.
- `scripts/server`: headless entrypoint; no rendering or UI scenes.

Initial/recovery transfers use chunk snapshots. Normal shots send final voxel deltas and authoritative match results. ENet identities are assigned local development slots; production authentication, server allocation and internet deployment are outside this prototype.
