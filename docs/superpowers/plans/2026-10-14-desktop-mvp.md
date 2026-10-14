# Desktop MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Implement and verify TB-6 through TB-15.
**Architecture:** Pure core rules, weapons, projectile simulation and match runner. Client presentation adapters and ENet server authority. Nakama is separate meta-game infrastructure.
**Tech Stack:** Godot 4.6, GDScript, ENet, Nakama, PostgreSQL, Docker Compose.
**Spec:** docs/superpowers/specs/2026-10-14-desktop-mvp.md

## Global Constraints
- Desktop first; pure core has no rendering/UI dependencies.
- Server owns damage/destruction and maps peer identity to player identity.
- 30 Hz fixed simulation; no full-world broadcast after shots.
- Resources for rules/weapons; no production secrets.

## Review Focus
- Nonfinite/oversized/malformed wire data: reject without mutations (tasks 6, 8).
- Duplicate/stale actions and peer spoofing: reject (tasks 4, 8).
- Reset during a projectile: no stale callback alters new match (task 5).
- No survivors, no support and timeout: explicit draw/next turn (task 4).
- Backend unavailable/disconnect: actionable UI, no frozen gameplay (task 9).

## Task 1: TB-15 Rules
Files: game/scripts/core/rules/game_rules_config.gd; game/assets/config/game_rules.tres; game/tests/unit/mvp_tests.gd.
Produces: GameRulesConfig Resource, validate() -> bool; turn_time=45, base_gravity=18, projectile_step=1/30, min/max power=.25/4, default_explosion_radius=5, movement and damage defaults.
- [x] RED tests invalid rules and valid defaults.
- [x] Implement rules; consume in debug scene; full suite; commit.

## Task 2: TB-6 Weapons
Files: core/weapons/weapon_config.gd, weapon_catalog.gd; assets/config/weapons/{bazooka,grenade,drill_missile}.tres; mvp_tests.gd.
Consumes rules; produces WeaponCatalog.load_all() -> Dictionary keyed by id, WeaponConfig.validate().
- [x] RED tests distinct valid configs, invalid speeds/IDs/limits.
- [x] Implement configs and selection; inventory owned by task 4; suite; commit.

## Task 3: TB-7 Projectile core
Files: core/projectiles/projectile_simulation.gd; client/debug/debug_projectile.gd; mvp_tests.gd.
Consumes weapon/rules/world; produces simulate(world, origin, direction, power, weapon, rules) -> Dictionary {path, position, hit, reason, deltas}.
- [x] RED tests gravity at fixed step, fast thin-wall hit, miss, grenade fuse, drill bounded penetration/metal.
- [x] Implement fixed-step sweep, bounded lifetime and same prediction path; suite; commit.

## Task 4: TB-8 Match
Files: core/rules/match_state.gd, match_runner.gd, match_factory.gd; mvp_tests.gd.
Produces runner.submit(command) -> Dictionary {ok, reason, events, deltas, path, state}; tick(delta), reset(), state_snapshot(). MatchState owns players, turn, status, inventory/time. Factory loads map/materials/spawns without Nodes.
- [x] RED tests inactive/stale/nonfinite commands, clamps, inventory, damage, team/FFA win/draw, dead skip, timeout and reset.
- [x] Implement runner and events TurnStarted/ShotResolved/PlayerDamaged/MatchEnded; suite; commit.

## Task 5: TB-9 HUD integration
Files: client/debug/voxel_debug.gd, client/rendering/voxel_world_node.gd, tests/integration/artillery_flow_tests.gd, debug_scene_smoke.gd.
Consumes runner; no UI authority. 1–3 selection, R restart, timer/state/HP/ammo HUD; render accepted paths and deltas; preserve movement/aim.
- [x] RED integration selection, reset during playback, UI mirrors core.
- [x] Implement adapter integration, shared rules, no client damage; suite; commit.

## Task 6: TB-13 Protocol
Files: networking/messages/match_protocol.gd; mvp_tests.gd.
Produces encode/decode commands, deltas, snapshots, explosion events; apply_deltas(world,data) -> bool and apply_chunk(world,data) -> bool with atomic validation.
- [x] RED round trips, malformed/bounds/nonfinite/oversized inputs and final voxel values.
- [x] Implement versioned plain-data protocol; suite; commit.

## Task 7: TB-10 Bootstrap
Files: scenes/main/Main.tscn, scripts/client/main.gd, server/server_main.gd, project.godot, tests/integration/server_smoke.gd.
Consumes MatchFactory; parses server/client/local-dev; server scene has no visual children.
- [x] RED command-line mode/server initialization smoke.
- [x] Implement bootstrap and headless loop; suite; commit.

## Task 8: TB-11 ENet
Files: networking/transport/match_server.gd, match_client.gd; client integration; tests/integration/network_smoke.gd.
Consumes runner/protocol. Identity assigned by server, 2 peers; initial snapshot, action request, accepted delta/result; explicit recovery.
- [x] RED real ENet handshake, spoof/stale rejection, identical replicated state/deltas and reconnect snapshot.
- [x] Implement transport/client adapter, no client resolution; suite; commit.

## Task 9: TB-12 Nakama
Files: backend/docker-compose.yml, client/backend/nakama_client.gd, client/backend/backend_menu.gd, tests/integration/nakama_smoke.gd, docs/backend.md.
Produces guest_login(device), create_lobby(), join_lobby(id), find_match() async; HTTP/WebSocket error/status signals. Connect UI to client flow, manual gameplay server address.
- [x] RED real-service guest/lobby/matchmaker smoke, unavailable service handling.
- [x] Pin images, migration/health, implement adapter/UI; start isolated dev stack and run two-account integration; commit.

## Task 10: TB-14 Polish
Files: client/vfx/match_effects.gd; debug integration; README.md; tests/integration/mvp_smoke.gd.
Consumes authoritative domain events only. Short transient VFX/audio, camera follows active player, no core side effects.
- [x] RED event->effect lifecycle and unchanged core state.
- [x] Implement and run full suite plus actual Metal render smoke; commit.

## Execution record
User authorized planning and implementation with “dzialaj”; execute inline, continue across tasks. Existing checkout is clean. Work on a dedicated branch in current checkout; preserve user-visible project location. Final independent review before completion. Do not push/merge.

## Completion evidence
Full Godot suite, two-peer ENet state/delta/recovery tests, separate-process server plus two gameplay clients, live Nakama guest/lobby/matchmaking smoke and actual macOS Metal rendering passed. Independent review found four P2 issues; regression tests reproduced all four, then passed after atomic event validation, representable-vector checks, latched jump and shared local/server movement fixes.

Decisions: branch isolation in current checkout; resource/inventory integration completed together with match/HUD; Nakama allocation and ENet identity binding remain manual local-dev limitations. No push/merge performed. Render screenshot `/tmp/terrablast-mvp.png` inspected; synthesized audio execution tested, subjective listening not performed.
Final additional regressions: a dead active pawn now advances the turn immediately; headless clients skip audio to avoid engine playback-resource leaks at shutdown. Full final run (including separate-process clients) passed without errors or leak warnings. No deferred review findings.
