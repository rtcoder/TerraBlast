# TB-6–TB-15: desktop MVP

Approved direction: one pure GDScript simulation shared by local-dev and the authoritative server; ENet gameplay transport; Nakama authentication/lobbies/matchmaking. Desktop first, no client damage authority, no full-world update after a shot.

## Subsystems and boundaries
- Rules and weapons (TB-15, TB-6): Resource defaults, immutable in a match. Base gravity 18, simulation 30 Hz, power 0.25–4, turn 45 s. Three configurable weapons selected with 1–3. Grenade uses a fuse and bounce; drill penetrates a bounded number of destructible voxels; metal stops it. Unlimited bazooka, finite grenade/drill inventory per player.
- Simulation and match (TB-7, TB-8): RefCounted projectile state and match runner. Fixed step sweep; explicit impact/miss results and domain events. Terrain, HP, turns, inventory, timeout, win/draw and reset owned here. Client Nodes only adapt input and show trajectories/results.
- Presentation (TB-9): HUD from match state; active player, health, weapon/ammunition, timer and shot phase. Restart restores initial world/players/inventory. Existing local movement retained through runner commands.
- Protocol (TB-13): versioned JSON-compatible commands/results, final voxel deltas, explosion metadata, chunk snapshots for start/reconnect. Validate payload shape, bounds, finite numbers; reject malformed data without partial application.
- Runtime (TB-10, TB-11): main bootstrap dispatches server/client/local-dev. Server initializes core without render/audio scenes. ENet peers map to player slots; never trust payload player_id. Only server resolves shots. Remote clients apply accepted state and deltas, not local damage. Initial/recovery snapshots explicit; subsequent turns send deltas.
- Backend (TB-12): pinned Nakama/Postgres images, migration, health checks, localhost development endpoints. Guest device auth, socket connection, create/join lobby, matchmaker 1v1 through a small Godot HTTP/WebSocket adapter. Dev credentials are documented, no production secrets. Local gameplay server allocation remains manual.
- Polish (TB-14): client-only short explosion visuals and synthesized sounds from match events, smooth camera transitions, updated controls/docs and macOS rendering smoke.

## Validation
Unit tests cover config validation, trajectories, collisions, weapon behavior, inventory, turns, timeout, wins/draw/reset and serialization. Integration tests cover local gameplay/UI, server bootstrap and real two-peer ENet authority. Backend smoke uses real Compose services and two guest accounts with lobby/matchmaking. Full Godot suite and macOS renderer smoke after integration. Mark a task Done only when its DoD is demonstrated; explicitly report external blockers.
