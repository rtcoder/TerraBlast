# Acceptance — TB-182–231

50 tasks implemented and verified under advance user approval. Integration: local commit and main merge, no remote push.

## Verification

- Final complete suite: **32/32 passed**, exit0. Command: `RUN_NAKAMA_TESTS=1 RUN_RENDER_TESTS=1 bash tools/run_godot_tests.sh --log-dir /tmp/terrablast-oct17-final --report /tmp/terrablast-oct17-final/report.json`.
- Report: `/tmp/terrablast-oct17-final/report.json`; includes actual ENet, local Nakama, native renderer, CLI and prior replay/bot regressions.
- New UI integration drives four actual clients through lobby, readiness, end screen and unanimous rematch with active physics during snapshot replacement. Also covers port selection, local disconnect/token cleanup, old-source callbacks, map metadata and replay isolation.
- Native UI: 0 failures, `/tmp/client-oct17-render-final.log`; inspected `/tmp/terrablast-oct17-lobby.png` and `/tmp/terrablast-oct17-arena.png` at1280×720/HUD125%.
- Independent review: no open P1/P2 after correcting team validation to1..2. Reviewer independently connected ten clients on Canyon Bridge and started after all ready; clean log `/tmp/terrablast-review-oct17-closure.log`. Updated UI closure also passed `/tmp/terrablast-review-client-closure.log`.
- Integration fixes: bind-independent UDP test ports; lobby UI waits for matching runner generation; focus loss preserves existing overlays; rematch votes retain results panel until snapshot reset.
- `git diff --check` clean. Initial full run's one network timeout was caused by concurrent fixed-port test processes; final run uses dynamic port allocation.

## Scope

Default remains automatic2-player server. `--players2..10` selects capacity; `--lobby` opts into readiness and consensual rematch. All configured slots must connect; any missing slot pauses play until full capacity returns. Reconnect reservations remain in-memory/time-bounded. Canyon Bridge is80×24×64 with5+5spawnpoints. No spectator, production allocation, identity authentication, remote deployment or platform export added. Nakama remains separate metagame.

## Evidence by task

- [x] **TB-182 — Server: Mecze sieciowe od 2 do 10 graczy**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-183 — Server: Przydział wszystkich slotów drużyn**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-184 — Server: Reconnect dowolnego slotu w większym meczu**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-185 — Protocol: Walidowany stan lobby**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-186 — Client: Synchronizacja stanu lobby**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-187 — Server: Gotowość przypisana do peera**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-188 — Server: Start po gotowości pełnego składu**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-189 — Server: Odwołanie gotowości przed startem**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-190 — Server: Pauza po utracie klienta**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-191 — Server: Walidacja nazw graczy**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-192 — Network: Nazwy w snapshotach i reconnect**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-193 — Server: Głos na rewanż po zakończeniu**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-194 — Server: Reset rewanżu i ponowna gotowość**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-195 — Server: Czyszczenie głosów po disconnect**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-196 — Server: Ograniczenie wiadomości lobby**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-197 — Network: Regresje real ENet dla 4 klientów**: MatchServer/Client/Protocol; network_oct17_next_tests real four-client ENet, previous network regressions; independent ten-client ENet smoke.
- [x] **TB-198 — Maps: Wspólny rejestr aren**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-199 — Maps: Metadane wyboru areny**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-200 — Arena: Canyon Bridge — teren i przejścia**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-201 — Arena: Canyon Bridge — 10 bezpiecznych spawnów**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-202 — Factory: Jawne odrzucanie braku spawnów**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-203 — Factory: Stabilna kolejność składów**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-204 — Maps: Limit objętości zgodny z zapisem i siecią**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-205 — Maps: Ograniczenie liczby operacji budowy**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-206 — Arena: Deterministyczna destrukcja nowej mapy**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-207 — Arena: Test bota i replay na Canyon Bridge**: MapRegistry, Canyon Bridge TOML, ArenaGenerator/MapValidator/MatchFactory; arena_oct17_tests including bot and replay roundtrip.
- [x] **TB-208 — CLI: --players steruje pojemnością serwera**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-209 — CLI: Flaga --lobby dla gotowości i rewanżu**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-210 — CLI: Rejestr trzech aren we wszystkich trybach**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-211 — CLI: Opis konfiguracji startującego serwera**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-212 — Tools: Regresja konfiguracji większego serwera**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-213 — Tools: Audyt metadanych i pojemności map**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-214 — Tools: Symulacja botów i zapis na trzeciej arenie**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-215 — Tools: Aktualizacja oczekiwań istniejących testów map**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-216 — Docs: Instrukcja uruchomienia lobby 2v2 i 5v5**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-217 — Docs: Protokół i ograniczenia nowego lobby**: GameConfig/server_main/utility_cli, portable test runner and docs; test_lobby_cli, test_bot_cli, test_simulation_cli, test_devtools.
- [x] **TB-218 — UI: Panel sieciowego lobby**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-219 — UI: Rozróżnienie connected, ready i vacant**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-220 — UI: Przycisk gotowości**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-221 — UI: Edycja własnej nazwy przed meczem**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-222 — HUD: Powód oczekiwania w lobby**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-223 — UI: Otwarcie lobby klawiszem F7**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-224 — UI: Przycisk rewanżu po meczu**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-225 — UI: Przejście do lobby po rewanżu**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-226 — UI: Rozłączenie i powrót do gry lokalnej**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-227 — UI: Wybór portu połączenia**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-228 — UI: Nazwy i opis aren przy wyborze**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-229 — UI: Help dla lobby i rewanżu**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-230 — Client: Regresje panelu lobby i powrotu lokalnego**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
- [x] **TB-231 — Acceptance: Pełny przebieg lobby i nowej areny**: LobbyPanel/MatchPanels/DesktopInput/backend menu/voxel scene; client_oct17_next_tests including real four-client ready/end/rematch flow and stale callback cleanup; native 1280×720 HUD125% inspection.
