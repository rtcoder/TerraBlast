# Weapons

Weapons are configured through `WeaponConfig` resources, not hardcoded in simulation.

MVP weapon candidates:

- Bazooka.
- Grenade.
- Drill Missile.

The server simulates shots and explosions. Clients may show trajectory previews, but previews are advisory only.


## MVP configurations

Weapon resources live in `game/assets/config/weapons/`. Bazooka has unlimited uses, grenade has five uses and drill missile three per player per match. Speed, gravity scale, explosion radius, terrain/player damage, fuse, bounce and drill depth are configured per weapon. `GameRulesConfig` supplies global gravity, fixed 30 Hz step, turn duration and movement parameters.

Preview and actual resolution both use `ProjectileSimulation`. Prediction never mutates terrain. A miss does not create an artificial ground explosion; a drill may still return deltas for blocks it passed through. Grenade uses a fixed fuse; drill stops on indestructible material.

## Damage, motion and limits

Player damage has its own `player_damage_radius`, independent of terrain radius. For distance `d`, radius `r` and exponent `f`, damage is `round(player_damage * clamp(1 - d/r, 0, 1)^f)`. The default exponent is 1 (linear); higher exponents concentrate damage near the centre. A pawn outside the radius takes zero damage. Knockback uses the same radial attenuation, is swept against solid voxels, and is followed by settling; no surviving support means elimination.

The core uses semi-implicit Euler at 30 Hz, with sampled sweeps to avoid skipping thin walls. Grenades reflect velocity with the configured bounce coefficient and clip their final step at the exact fuse time. Grenade bounce is a point-projectile approximation, not a rigid-body solver. The drill removes at most its configured voxel count; even a later miss applies those deltas and settles affected players.

Config validation caps gravity, speeds, radii, duration, drill depth and ammo. A shot additionally has a 65,536-sample sweep budget. Invalid configs are rejected before consuming ammo; excessive legal simulation work terminates with `simulation_budget`. Catalogs reject duplicate IDs and codes.

`MatchReplay` captures the arena, configs, initial state and accepted shots/movement/time updates. `data` is JSON serializable; `replay()` reconstructs a runner and `state_hash()` compares terrain, HP, positions, turns and inventory. This is a local diagnostic format for trusted recordings, not a network upload format. The client preview and resolved path use the same simulator; previews never mutate the arena.

## Match diagnostics and recordings

`RulePresets.create` returns isolated classic/quick/training rule resources. `max_turns=0` disables the turn cap; reaching a positive cap produces a draw after the turn resolves. `wind` is a bounded X acceleration in the same fixed-step projectile integrator, shared by preview and server. Voxel raycasting and pawn/projectile collision honour `VoxelMaterialConfig.is_solid`.

`MatchRunner.statistics` records accepted shots, shots harming an enemy, actual enemy HP removed and enemy eliminations. Overkill is capped by the victim's previous HP; self/team damage is excluded from these metrics. `history` contains at most 32 compact authoritative shot summaries. Reset clears both; network snapshots preserve them. Surrender eliminates the requesting player without changing terrain, then checks turn and winner state.

`ReplayArchive.save(path, recorder, runner)` stores a versioned recording and final state hash using a temporary sibling and atomic rename. `load_verified(path)` rejects malformed, oversized or hash-mismatched recordings before returning a restored runner. Archives are limited to 32 MiB. Recording requires routing tick/move/shot calls through the recorder APIs; the live client does not automatically archive every match. The CLI verifies supplied archives with `--mode replay --replay path`.
