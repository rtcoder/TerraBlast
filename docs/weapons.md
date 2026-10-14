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
