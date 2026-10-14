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

Raw ENet reliable packets carry JSON with `version: 1`. The server assigns a peer to blue_1 or red_1; a command claiming another slot is rejected. Commands include match generation and turn ID to reject duplicate or pre-reset actions. Nonfinite aim/power and malformed structures are rejected before state changes.

A shot result contains sampled projectile path, domain events, final voxel deltas and player/turn/inventory state. No full terrain is included. Separate chunk snapshots initialize a joining peer or repair desync on explicit request. The receiver validates the entire delta batch before applying it; a snapshot is staged separately before swapping the world.

Movement packets contain bounded input axes, camera yaw and a jump request, never client position. The server advances movement. Turns pause while a projectile is being presented or a player is disconnected. Local-dev uses the same match runner without transport.

`PlayerActionCommand`, `TerrainDelta` and explosion-event dictionaries are serialized by `MatchProtocol`; explosion events include turn, weapon, seed, radius and center metadata. Final deltas remain authoritative.
