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

