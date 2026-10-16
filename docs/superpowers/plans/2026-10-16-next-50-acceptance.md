# Acceptance — TB-132–181

50 tasks implemented and verified. User preapproved commit and local main integration; no remote push.

## Verification

- Final full suite: **28/28 passed**, exit 0. Command: `RUN_NAKAMA_TESTS=1 RUN_RENDER_TESTS=1 bash tools/run_godot_tests.sh --log-dir /tmp/terrablast-oct16-final --report /tmp/terrablast-oct16-final/report.json`.
- Full report: `/tmp/terrablast-oct16-final/report.json`; includes real ENet process tests, local Nakama, renderer and CLI.
- Native client integration: 0 failures, `/tmp/client-oct16-render-exact.log`. Inspected `/tmp/terrablast-oct16-setup.png` and `/tmp/terrablast-oct16-session.png`, 1280×720 at HUD125%.
- Independent review: no open P1/P2. Fixed replay/network crossover, lost airborne checkpoint velocity, relative/absolute CLI output collision. Integrated tests also exposed lossy Godot JSON parsing; exact float64 codec retains unchanged hashes, with malformed/nonfinite/depth tests and legacy compatibility. Reviewer checked 10000 random finite float64 bit patterns.
- `git diff --check` clean.

## Scope and limits

Bots are stationary, deterministic, easy18/normal72 candidate search; human controls blue in solo. Hotseat remains the default. Replay is a local action inspector, not real-time video playback. Recording is bounded to100000 actions/256 shots and files32MiB; overflow is visible and does not halt play. Restart/load/debug rule changes begin a new recording. Local checkpoint/inspection is unavailable during authoritative network play. Checkpoint v2 retains player velocities; archive/session v1 remain readable. No desktop binary export, remote deployment or push performed.

## Task evidence

- [x] **TB-132 — Bot: Deterministyczny wybór żywego przeciwnika**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-133 — Bot: Generowanie ograniczonego zestawu strzałów**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-134 — Bot: Ocena strzału wspólną symulacją**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-135 — Bot: Kara za trafienie siebie i drużyny**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-136 — Bot: Wybór broni z dostępnej amunicji**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-137 — Bot: Poziomy easy i normal**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-138 — Bot: Planowanie porcjami**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-139 — Bot: Odrzucanie nieaktualnego planu**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-140 — Bot: Obsługa braku celu i końca meczu**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-141 — Bot: Wspólny synchroniczny interfejs CLI**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-142 — Bot: Test deterministyczności i niemutowania świata**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-143 — Bot: Test gry na obu arenach**: `bot_planner.gd`; `bot_oct16_tests` (both arenas, actual damage, determinism, no mutation, ammo, targeting, stale plans, budgets).
- [x] **TB-144 — Replay: Nagrywanie poddania gracza**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-145 — Replay: Limit nagrywania na żywo**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-146 — Replay: Bezstratna serializacja float**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-147 — Replay: Dostęp do zweryfikowanego nagrania**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-148 — Replay: Odtworzenie pojedynczej akcji**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-149 — Replay: Kursor odtwarzania krokowego**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-150 — Replay: Ograniczone przewijanie do indeksu**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-151 — Replay: Metadane postępu**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-152 — Save: Migawka do wznowienia lokalnego meczu**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-153 — Save: Walidacja ustawień sesji**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-154 — Save: Ograniczony odczyt i wersjonowanie sesji**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-155 — Replay: Testy roundtrip i błędnych zapisów**: `match_replay.gd`, `replay_playback.gd`, `replay_archive.gd`, `session_store.gd`, `exact_json.gd`; `core_replay_oct16_tests` (roundtrip, legacy v1, corrupt files, limits, airborne motion, exact floats).
- [x] **TB-156 — CLI: Tryb symulacji botów**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-157 — CLI: Eksport powtórki z symulacji**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-158 — CLI: Raport decyzji botów**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-159 — CLI: Walidacja nowych argumentów**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-160 — Tools: Launcher udostępnia boty i nagrywanie**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-161 — Tools: Regresja symulacji botów**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-162 — Tools: Test eksportu i weryfikacji replay**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-163 — Docs: Instrukcja gry solo i ograniczenia botów**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-164 — Docs: Instrukcja zapisów i powtórek**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-165 — Tools: Automatyczne uruchamianie nowych regresji**: `simulation_cli.gd`, `game_config.gd`, portable launcher/runner and README; `test_bot_cli`, `test_simulation_cli`, `test_devtools`.
- [x] **TB-166 — UI: Wybór hotseat lub solo**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-167 — UI: Wybór trudności botów**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-168 — Client: Harmonogram tur botów**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-169 — Client: Blokada sterowania turą bota**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-170 — Client: Pauza i anulowanie planu bota**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-171 — HUD: Stan myślenia bota**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-172 — Client: Automatyczne nagrywanie lokalnego meczu**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-173 — UI: Zapis powtórki do pliku**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-174 — UI: Zapis stanu gry**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-175 — UI: Wczytanie zapisanej gry**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-176 — UI: Otwarcie ostatniej powtórki**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-177 — UI: Sterowanie odtwarzaniem krokowym**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-178 — UI: Powrót z powtórki do meczu**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-179 — Client: Test sceny solo i zapisu**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-180 — UI: Aktualizacja pomocy i układu menu**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
- [x] **TB-181 — Acceptance: Sprawdzenie pełnego cyklu solo**: `local_session.gd`, `voxel_debug.gd`, `match_panels.gd`, desktop input; `client_oct16_next_tests`, previous client regressions, native Metal 1280×720 HUD125% screenshots.
