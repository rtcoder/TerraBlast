# TerraBlast

TerraBlast is a desktop-first Godot 4 project for turn-based voxel artillery battles on destructible arenas.

Project pillars:

- Godot 4.x and GDScript.
- Server-authoritative gameplay.
- Pure core simulation separated from client UI and runtime Nodes.
- Chunked voxel terrain with blocky destruction for MVP.
- Nakama and PostgreSQL for auth, matchmaking, lobby, and meta-game later.

## Current State

This repository contains the initial Godot project structure, core voxel data models, explosion logic, and a lightweight Godot test runner for coordinate and destruction behavior.

## Run

Open `game/project.godot` in Godot 4.

From macOS, if Godot is installed as an app:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

The default scene is now the voxel debug arena:

- mouse movement rotates the third-person camera,
- WASD or arrow keys move the active player,
- space jumps,
- hold right mouse button to aim and see the trajectory,
- while aiming, hold left mouse button to charge shot power,
- release left mouse button to fire from the crosshair,
- mouse wheel zooms,
- release right mouse button or press Esc to cancel aiming and charging,
- Esc releases the mouse cursor; clicking to recapture it does not fire.

Run unit tests:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script tests/unit/core_tests.gd
```
