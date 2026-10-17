# Networking

The networking model is server-authoritative.

Clients send player intent:

```txt
player_id
turn_id
weapon_id
aim_direction
shot_power
```

The match server validates the active player, turn id, weapon use, shot power, and terrain/player results. Clients never decide gameplay-critical damage.


## Implemented development protocol

Raw ENet reliable packets carry JSON with `version: 2`. The server assigns each peer a unique slot among 2–10 configured players; a command claiming another slot is rejected. Commands include match generation and turn ID to reject duplicate or pre-reset actions. Nonfinite aim/power and malformed structures are rejected before state changes.

A shot result contains sampled projectile path, domain events, final voxel deltas and player/turn/inventory state. No full terrain is included. Separate chunk snapshots initialize a joining peer or repair desync on explicit request. The receiver validates the entire delta batch before applying it; a snapshot is staged separately before swapping the world.

Movement packets contain bounded input axes, camera yaw and a jump request, never client position. The server advances movement. Turns pause while a projectile is being presented or a player is disconnected. Local-dev uses the same match runner without transport.

`PlayerActionCommand`, `TerrainDelta` and explosion-event dictionaries are serialized by `MatchProtocol`; explosion events include turn, weapon, seed, radius and center metadata. Final deltas remain authoritative.

## Match lobby and full-roster gating

`MatchServer.start(port, map_path, preset, player_count = 2, require_ready = false)` validates capacity and available map spawns before binding. Slots are assigned in stable team order. The default is the compatible two-player auto mode; auto matches start when every configured slot connects.

The validated `lobby_state` contains `capacity`, `require_ready`, `started`, `generation` and a roster of `id`, `name`, `team`, `connected`, `ready`, `rematch`. Clients replace their displayed lobby only after validating types, bounds and unique IDs. Snapshots and reconnects carry current lobby state.

In explicit lobby mode (`--lobby`), each peer sends its own ready intent. Full capacity must be connected and ready before time, movement and shots begin. Ready can be withdrawn before start; disconnect and accepted name changes clear readiness. Names are trimmed, limited to 1–24 characters, bounded in UTF-8 and reject control characters. Names survive reconnect and rematch. Lobby intents are rate limited and cannot operate another peer's slot.

After start, loss of any required slot pauses match time, movement and shots. Restoring the full roster resumes without another ready round. An in-memory reconnect token reserves the original identity and state only for the configured grace period; expiry releases the reservation. A new process has no persisted token.

After a lobby match ends, every slot must be connected and vote for rematch. A false vote withdraws consent; disconnect invalidates votes and cannot reduce the quorum. Unanimity resets terrain, revision and match state exactly once, increments generation, preserves names and returns the roster to readiness selection. Legacy restart cannot bypass this quorum. Auto mode retains the existing blue_1 restart control.

Nakama remains a separate metagame backend. Gameplay endpoints are started and allocated manually; the current protocol provides no automatic match-server provisioning or production identity authentication.
