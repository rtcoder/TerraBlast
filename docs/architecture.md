# Architecture

TerraBlast keeps gameplay-critical logic in pure GDScript classes under `game/scripts/core`.

Godot Nodes are runtime adapters for rendering, input, audio, UI, and process lifetime. Client code can display previews and collect player intent, but server code owns validation, simulation, terrain damage, player damage, turn results, and win conditions.

Initial flow:

```txt
Client -> server: PlayerActionCommand
Server -> core: validate and simulate
Core -> server: result events and TerrainDelta
Server -> clients: authoritative result
Clients -> runtime nodes: render outcome
```

