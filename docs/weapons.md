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
