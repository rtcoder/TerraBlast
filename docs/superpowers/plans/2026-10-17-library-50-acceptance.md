# Acceptance — TB-232–281

50 tasks implemented under advance user approval. Local commit and merge to main; no remote push.

## Verification

- Effective final verification: **37/37 passed**. Full suite includes actual ENet, Nakama, native render, old core/replay/bot/client tests and six CLI/tool checks.
- Command: `RUN_NAKAMA_TESTS=1 RUN_RENDER_TESTS=1 bash tools/run_godot_tests.sh --log-dir /private/tmp/terrablast-library-final --report /private/tmp/terrablast-library-final/report.json`.
- Final report: `/private/tmp/terrablast-library-final/verified-report.json`. Original attempt preserved as `initial-attempt.json`: 36/37; the new keyboard regression fixture reused an InputEvent twice in one frame. Corrected each dispatch to use a distinct event, then reran that test with the same bounded test runner (exit0, 0 failures). `previous_attempts` records this history. Earlier full run also passed 37/37 before the last review additions.
- Native final client integration: exit0, 0 failures, `/private/tmp/library-native-final.log`. Inspected library and scrolled binding controls at 1280×720/HUD125%: `/private/tmp/terrablast-library-ui.png`, `/private/tmp/terrablast-bindings-ui.png`.
- Independent review closed with no outstanding confirmed P1/P2. Actual dispatched events verify title editing, Enter capture, End/Right navigation, exact timeline endpoint and speed reset.
- Review fixes: text focus suppresses remapped gameplay shortcuts; capture consumes GUI events; exact slider endpoint avoids rounding; keyboard seek reads after GUI handling; Left/Right traverse action boundaries; reopened playback resets speed selector.
- `git diff --check` clean. No test changes real user archives or persisted preferences; temporary fixtures and no-save bindings adapters isolate writes.

## Scope and limits

Library stores max100 entries/32MiB per entry; title1–48; generated IDs independent of names. Symlink path components are rejected. Listing parses envelopes without simulation; load/import/CLI verification checks payload. Replay time counts original simulation ticks, not projectile presentation. Seek rebuilds from the initial snapshot, so large recordings take longer. Input remapping applies to eleven desktop actions; fixed F-keys, arrows, Escape and debug brackets stay reserved. Existing quick-save/replay files remain compatible.

## Task evidence

- [x] **TB-232 — Wspólny kodek archiwum powtórki**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-233 — Wspólny kodek checkpointu**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-234 — Format biblioteki lokalnej**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-235 — Bezpieczne identyfikatory wpisów**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-236 — Nazwane checkpointy**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-237 — Nazwane powtórki**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-238 — Lista i filtrowanie biblioteki**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-239 — Odczyt wpisu biblioteki**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-240 — Zmiana nazwy wpisu**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-241 — Usuwanie wpisu**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-242 — Import istniejących plików**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-243 — Regresje biblioteki**: LocalArchiveLibrary + shared encode/decode; library_oct17_tests and core_replay_oct16_tests (exact f64, legacy, malformed/path/size/count limits, import/rename/delete).
- [x] **TB-244 — Indeks czasu nagrania**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-245 — Play i pause powtórki**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-246 — Prędkość odtwarzania**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-247 — Odtwarzanie według czasu**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-248 — Budżet pracy odtwarzacza**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-249 — Agregacja zmian przy odtwarzaniu**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-250 — Przewijanie według czasu**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-251 — Przejście do kolejnego strzału**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-252 — Koniec odtwarzania i błędy**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-253 — Regresje osi czasu**: ReplayPlayback; replay_timeline_tests + core_replay_oct16_tests (time/speed/budget/seek/shot/hash), client_library_next_tests (actual UI).
- [x] **TB-254 — Model przypisań klawiszy**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-255 — Walidacja konfliktów klawiszy**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-256 — Trwałe przypisania**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-257 — Odczyt fizycznych klawiszy**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-258 — Konfigurowalny ruch**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-259 — Konfigurowalne akcje gry**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-260 — Konfigurowalne pause i scoreboard**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-261 — Lista klawiszy w ustawieniach**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-262 — Przechwytywanie nowego klawisza**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-263 — Komunikaty konfliktów i zapisu**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-264 — Reset i anulowanie konfiguracji**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-265 — Regresje konfiguracji sterowania**: InputBindings/SettingsPanel/DesktopInput; input_bindings_tests (persistence, conflicts, physical events, actual GUI capture, text focus) and client_library_next_tests (help integration).
- [x] **TB-266 — Panel biblioteki F8**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-267 — Lista zapisów w UI**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-268 — Zapisywanie nazwanych pozycji z UI**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-269 — Ładowanie checkpointu z biblioteki**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-270 — Otwieranie powtórki z biblioteki**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-271 — Zmiana nazwy i usunięcie z UI**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-272 — Import szybkich zapisów w UI**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-273 — Przyciski play pause speed**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-274 — Oś czasu i next shot w UI**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-275 — Bezpieczny powrót i overlay powtórki**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-276 — Integracja konfiguracji klawiszy**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-277 — Narzędzie odczytu biblioteki**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-278 — Testy CLI biblioteki**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-279 — Testy przepływu klienta**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-280 — Dokumentacja biblioteki i sterowania**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
- [x] **TB-281 — Akceptacja paczki i review**: LibraryPanel/MatchPanels/voxel_debug; client_library_next_tests, test_library_cli, existing client/network suites and native UI review.
