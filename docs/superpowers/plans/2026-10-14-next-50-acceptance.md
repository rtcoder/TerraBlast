# Next 50 acceptance ledger

Scope: TB-16–44 and TB-61–81. Implementation completed and verified on codex/next-50 for local fast-forward integration into main.

| Task | Implementation / acceptance evidence |
|---|---|
| TB-16 — Tuning: Dodać regulację grawitacji pocisków | core50_tests, mvp_tests |
| TB-17 — Tuning: Dodać parametry eksplozji i damage falloff do configu | core50_tests, mvp_tests |
| TB-18 — Tuning: Dodać debug panel do podglądu parametrów gry | client50_tests, artillery_flow_tests, rendered smoke |
| TB-19 — Input: Rozdzielić tryb kamery i tryb celowania | client50_tests, artillery_flow_tests, rendered smoke |
| TB-20 — Aiming: Dodać wizualny wskaźnik kierunku strzału | client50_tests, artillery_flow_tests, rendered smoke |
| TB-21 — Aiming: Dodać preview łuku trajektorii | client50_tests, artillery_flow_tests, rendered smoke |
| TB-22 — Weapons: Utworzyć Resource dla Bazooka | core50_tests, mvp_tests |
| TB-23 — Weapons: Utworzyć Resource dla Grenade | core50_tests, mvp_tests |
| TB-24 — Weapons: Utworzyć Resource dla Drill Missile | core50_tests, mvp_tests |
| TB-25 — Weapons: Dodać lokalny wybór broni 1-3 | match_ui_tests, client50_tests |
| TB-26 — Weapons: Dodać testy konfiguracji broni | core50_tests, mvp_tests |
| TB-27 — Projectile: Przenieść symulację trajektorii do core | core50_tests, mvp_tests |
| TB-28 — Projectile: Dodać voxel sweep z małym krokiem czasowym | core50_tests, mvp_tests |
| TB-29 — Terrain: Dodać dirty chunks przy eksplozji na granicy chunka | terrain50_tests; second arena render |
| TB-30 — Terrain: Dodać debug overlay liczby dirty/rebuilt chunków | terrain50_tests; second arena render |
| TB-31 — Terrain: Dodać prostą drugą arenę testową | terrain50_tests; second arena render |
| TB-32 — Terrain: Wyciągnąć generator areny z VoxelWorldNode | terrain50_tests; second arena render |
| TB-33 — Players: Dodać spawn point model | terrain50_tests; second arena render |
| TB-34 — Players: Dodać knockback po eksplozji | core50_tests, mvp_tests |
| TB-35 — Players: Dodać stabilizację pozycji gracza po zniszczeniu terenu | core50_tests, mvp_tests |
| TB-36 — Match: Dodać limit czasu tury | core50_tests, mvp_tests |
| TB-37 — Match: Dodać komendę restartu lokalnego meczu | match_ui_tests, mvp_tests |
| TB-38 — Match: Dodać prosty ekran/komunikat końca meczu | match_ui_tests, mvp_tests |
| TB-39 — Server: Rozdzielić client debug runtime od core match runnera | core50_tests, mvp_tests |
| TB-40 — Server: Dodać walidację komendy strzału | core50_tests, mvp_tests |
| TB-41 — Networking: Zdefiniować PlayerActionCommand serialization | mvp_tests, network50_tests, network_smoke |
| TB-42 — Networking: Zdefiniować TurnResult serialization | mvp_tests, network50_tests, network_smoke |
| TB-43 — QA: Dodać smoke test lokalnej tury ze strzałem | client50_tests (scene shot + turn + terrain delta) |
| TB-44 — Docs: Zaktualizować docs/terrain.md i docs/weapons.md po configach | docs/terrain.md and docs/weapons.md checked against code |
| TB-61 — Rules: Ograniczyć zakresy konfiguracji i koszt symulacji | core50_tests |
| TB-62 — UI: Tab scoreboard z indywidualnym HP i stanem graczy | client50_tests; rendered panels |
| TB-63 — Settings: Regulacja i wyciszenie master audio | client50_tests; rendered panels |
| TB-64 — Settings: Czułość myszy i odwrócenie osi Y | client50_tests; rendered panels |
| TB-65 — Settings: Tryb okna i fullscreen | client50_tests; rendered panels |
| TB-66 — Settings: Trwały i walidowany zapis preferencji klienta | client50_tests; rendered panels |
| TB-67 — Input: Anulować ładowanie po utracie fokusu okna | client50_tests; rendered panels |
| TB-68 — Weapons: Zapamiętywać wybór broni osobno dla graczy | client50_tests; rendered panels |
| TB-69 — Movement: Zablokować przenikanie przez pionowe ściany | core50_tests |
| TB-70 — Grenade: Stabilne odbicia na podłożu i narożnikach | core50_tests |
| TB-71 — Protocol: Walidować spójność pełnego stanu meczu | network50_tests; real ENet |
| TB-72 — Networking: Wykrywać lukę revision i żądać resynchronizacji | network50_tests; real ENet |
| TB-73 — Networking: Snapshoty niezależne od wymiarów areny | network50_tests; real ENet |
| TB-74 — Networking: Checksum terenu przy pełnej resynchronizacji | network50_tests; real ENet |
| TB-75 — Server: Limity częstotliwości pakietów i snapshotów | network50_tests; real ENet |
| TB-76 — Networking: Reconnect klienta z zachowaniem slotu | network50_tests; real ENet |
| TB-77 — Nakama: Anulowanie matchmakingu i sprzątanie ticketów | nakama50_tests; real Nakama cancel/requeue |
| TB-78 — Replay: Deterministyczny zapis i odtworzenie komend lokalnych | core50_tests |
| TB-79 — Bootstrap: Walidacja CLI mode/port/map/players | config50_tests, test_simulation_cli.py |
| TB-80 — Client: Czytelny stan połączenia i ponowienie po błędzie | network50_tests; HUD status and F4 retry |
| TB-81 — Devtools: Headless smoke symulacji z wynikiem JSON | test_simulation_cli.py; deterministic both arenas |

## Explicit decisions

TB-19 predates the user-approved RMB aim + LMB charge scheme. Retain the approved controls and isolate desktop input; camera motion and cursor recapture cannot fire. TB-21 uses the full weapon simulator, so grenade bounce/drill penetration previews follow their configured behaviours rather than incorrectly terminating at the first destructible block.

## Verification

Full suite with RUN_NAKAMA_TESTS=1 and RUN_RENDER_TESTS=1 passed, including real Metal and separate server/two-client processes. Final review follow-ups are recorded below before integration.

Review follow-ups fixed: expired-token retry now permits a fresh slot; exact Nakama missing-ticket response terminates cancellation and allows requeue; malformed replay input is rejected before replay. Fresh reviewer found no open P1/P2 issues after re-review. Final integrated suite passed with exit 0: RUN_NAKAMA_TESTS=1 RUN_RENDER_TESTS=1 bash tools/run_godot_tests.sh. This includes real Nakama race/cancel/requeue tests, ENet recovery/reconnect, Metal rendering, separate server/two gameplay processes and deterministic CLI runs on both maps. Client panels were also rendered and visually inspected on two_islands. No desktop exports or remote deployment were performed.
