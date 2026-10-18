# archives implementation plan

Spec: ../specs/2026-10-18-next-250-design.md

## 1. Biblioteka: wyszukiwanie nazw

Query case-insensitive i whitespace normalization filtruje metadata bez wykonywania symulacji.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Query case-insensitive i whitespace normalization filtruje metadata bez wykonywania symulacji.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 2. Biblioteka: sortowanie listy

Sort newest/oldest/title/kind stabilny po ID; nie mutuje zapisów.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Sort newest/oldest/title/kind stabilny po ID; nie mutuje zapisów.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 3. Biblioteka: paginacja

Offset/limit ograniczone, wyniki zawierają total i stronę; bez utraty wybranego ID po refresh.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Offset/limit ograniczone, wyniki zawierają total i stronę; bez utraty wybranego ID po refresh.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 4. Biblioteka: statystyka przestrzeni

Raport liczby poprawnych/uszkodzonych plików i bajtów, bez podążania za symlinkami.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Raport liczby poprawnych/uszkodzonych plików i bajtów, bez podążania za symlinkami.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 5. Biblioteka: szczegóły wybranej pozycji

UI pokazuje datę UTC, typ, rozmiar i ID, nie tylko tooltip.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: UI pokazuje datę UTC, typ, rozmiar i ID, nie tylko tooltip.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 6. Biblioteka: eksport surowego zapisu

export_entry(id,path) wyodrębnia zgodny ReplayArchive/SessionStore, bez modyfikowania źródła.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: export_entry(id,path) wyodrębnia zgodny ReplayArchive/SessionStore, bez modyfikowania źródła.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 7. Biblioteka: duplikowanie wpisu

duplicate_entry(id,title) nadaje nowe ID i datę, zachowuje dokładny payload.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: duplicate_entry(id,title) nadaje nowe ID i datę, zachowuje dokładny payload.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 8. Biblioteka: wykrywanie duplikatów treści

Fingerprint payload pozwala wskazać duplikaty niezależnie od tytułów i dat.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Fingerprint payload pozwala wskazać duplikaty niezależnie od tytułów i dat.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 9. Biblioteka: lista błędnych pozycji

Osobny diagnostics zwraca ID/pliki i przyczynę korupcji, nie ukrywa ich z listy napraw.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Osobny diagnostics zwraca ID/pliki i przyczynę korupcji, nie ukrywa ich z listy napraw.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 10. Biblioteka: usuwanie uszkodzonego wpisu w UI

Wybranie poprawnego ID uszkodzonego pliku i osobne potwierdzenie umożliwia odzyskanie limitu miejsca.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Wybranie poprawnego ID uszkodzonego pliku i osobne potwierdzenie umożliwia odzyskanie limitu miejsca.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 11. Biblioteka: import wybranego pliku

FileDialog importu .json zamiast wyłącznie dwóch stałych quick paths; rodzaj walidowany.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: FileDialog importu .json zamiast wyłącznie dwóch stałych quick paths; rodzaj walidowany.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 12. Biblioteka: eksport wybranego pliku w UI

Save dialog potwierdza overwrite i raportuje błąd bez utraty wpisu.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Save dialog potwierdza overwrite i raportuje błąd bez utraty wpisu.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 13. Biblioteka: ulubione

Oddzielny mały plik preferencji z walidowanymi ID, togglefavorite nie zmienia payload.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Oddzielny mały plik preferencji z walidowanymi ID, togglefavorite nie zmienia payload.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 14. Biblioteka: filtr ulubionych

Lista pokazuje starred entries; brakujące ID są pomijane, nie blokują biblioteki.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Lista pokazuje starred entries; brakujące ID są pomijane, nie blokują biblioteki.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 15. Biblioteka: zapamiętanie filtrów

query/kind/sort są wczytywane walidowane i zapisywane niezależnie od archiwów.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: query/kind/sort są wczytywane walidowane i zapisywane niezależnie od archiwów.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 16. Biblioteka: szybki podgląd checkpointu

Preview zwraca turn, status, teamsHP, liczba graczy po walidacji bez podmiany sceny.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Preview zwraca turn, status, teamsHP, liczba graczy po walidacji bez podmiany sceny.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 17. Replay: podsumowanie nagrania

Pure analyzer zwraca actioncounts,duration,shots,players i wynik, nie mutuje recordera.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Pure analyzer zwraca actioncounts,duration,shots,players i wynik, nie mutuje recordera.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 18. Replay: oś tur

Zwraca granice zmian aktywnego gracza/tury z czasem i indeksem akcji.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Zwraca granice zmian aktywnego gracza/tury z czasem i indeksem akcji.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 19. Replay: zakładki strzałów

Zwraca index,time,player,weapon,damage,kills z wykonanych akcji, spójnie z playback.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Zwraca index,time,player,weapon,damage,kills z wykonanych akcji, spójnie z playback.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 20. Replay: statystyki graczy

Agreguje shots/hits/damage/kills z całego nagrania, nie tylko ostatnich32history.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Agreguje shots/hits/damage/kills z całego nagrania, nie tylko ostatnich32history.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 21. Replay: wykorzystanie broni

Agreguje liczbę strzałów i efekty według weapon_id, obsługuje dowolny walidowany katalog.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Agreguje liczbę strzałów i efekty według weapon_id, obsługuje dowolny walidowany katalog.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 22. Replay: dystans ruchu

Sumuje rzeczywiste przemieszczenie akcji move perplayer, wyklucza knockback od shots.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Sumuje rzeczywiste przemieszczenie akcji move perplayer, wyklucza knockback od shots.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 23. Replay: czas aktywnych graczy

Rozdziela ticktime według aktywnego gracza, nie dubluje move.delta.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Rozdziela ticktime według aktywnego gracza, nie dubluje move.delta.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 24. Replay: bilans destrukcji

Podsumowuje zmienione/zniszczone voxele i materiały na podstawie deltas.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Podsumowuje zmienione/zniszczone voxele i materiały na podstawie deltas.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 25. Replay: punkty eliminacji

Timeline wskazuje akcje i graczy zmieniających alive true->false, również surrender/tick.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Timeline wskazuje akcje i graczy zmieniających alive true->false, również surrender/tick.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 26. Replay: porównanie nagrań

Porównuje końcowe hashe, wynik, długość, metryki bez sugerowania zgodności różnych initialstates.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Porównuje końcowe hashe, wynik, długość, metryki bez sugerowania zgodności różnych initialstates.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 27. Replay: eksport analizy JSON

Walidowany wynik analizera zapisuje atomowo, z wersją i czytelnym błędem.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Walidowany wynik analizera zapisuje atomowo, z wersją i czytelnym błędem.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 28. Replay: eksport tabel CSV

CSV perplayer/shot, poprawne quote/commas/newlines i ochrona formuł nazw graczy.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: CSV perplayer/shot, poprawne quote/commas/newlines i ochrona formuł nazw graczy.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 29. Replay: diagnostyka pierwszego błędu

Analyzer zwraca index/type/reason pierwszej niewykonalnej akcji, bez fałszywego success.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Analyzer zwraca index/type/reason pierwszej niewykonalnej akcji, bez fałszywego success.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 30. Replay: budżet analizy

Begin/step(max_actions) inkrementalnie liczy statystyki, cap4096 na krok; progres/cancel.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Begin/step(max_actions) inkrementalnie liczy statystyki, cap4096 na krok; progres/cancel.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 31. Replay: UI listy strzałów

Inspector pokazuje shotbookmarks i wybór przenosi do dokładnej granicy akcji.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Inspector pokazuje shotbookmarks i wybór przenosi do dokładnej granicy akcji.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 32. Replay: UI statystyk nagrania

Panel analizy pokazuje duration,turns,players,weapons,destruction bez zakrywania live HUD.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Panel analizy pokazuje duration,turns,players,weapons,destruction bez zakrywania live HUD.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 33. Replay: UI postępu analizy

Cięższe nagrania analizowane porcjami z cancel; wyjście z inspectora usuwa zadanie.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Cięższe nagrania analizowane porcjami z cancel; wyjście z inspectora usuwa zadanie.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 34. Replay: keyboard previous shot

Przycisk Previous shot wyszukuje poprzednią granicę strzału; brak wcześniejszego nie mutuje.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Przycisk Previous shot wyszukuje poprzednią granicę strzału; brak wcześniejszego nie mutuje.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 35. Replay: skok do następnej tury

Next turn przenosi po zmianie turn/generation, obsługuje EOF bez zapętlenia.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Next turn przenosi po zmianie turn/generation, obsługuje EOF bez zapętlenia.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 36. Replay: tryb loop

Jawna opcja po EOF przewija do początku, nie robi busyloop dla pustego nagrania.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Jawna opcja po EOF przewija do początku, nie robi busyloop dla pustego nagrania.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 37. Replay: przywracanie ostatniej pozycji

Per-entry cursor preference waliduje fingerprint/index, zmieniony wpis ignoruje stary cursor.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Per-entry cursor preference waliduje fingerprint/index, zmieniony wpis ignoruje stary cursor.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 38. Replay: marker wybranej akcji

Czytelny opis tick/move/shot/surrender z nazwą gracza i broni zamiast pustego typu.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Czytelny opis tick/move/shot/surrender z nazwą gracza i broni zamiast pustego typu.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 39. Replay: nieudane seek widoczne

UI pokazuje przyczynę invalid/no next shot, zachowuje kursor i runner.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: UI pokazuje przyczynę invalid/no next shot, zachowuje kursor i runner.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 40. Checkpoint: porównanie zapisów

Compare raportuje zgodność world/state/options/velocities jako osobne wyniki.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Compare raportuje zgodność world/state/options/velocities jako osobne wyniki.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 41. Biblioteka CLI: query i sort

CLI list options zgodne z core query/sort, odrzuca niewłaściwe wartości.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: CLI list options zgodne z core query/sort, odrzuca niewłaściwe wartości.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 42. Biblioteka CLI: preview ID

Wskazane --entry zwraca tylko zweryfikowany preview, błąd ID ->exit2.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Wskazane --entry zwraca tylko zweryfikowany preview, błąd ID ->exit2.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 43. Biblioteka CLI: analiza replay

Tryb analyze-replay na jawnej ścieżce zwraca JSON bez uruchomienia klienta.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Tryb analyze-replay na jawnej ścieżce zwraca JSON bez uruchomienia klienta.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 44. Biblioteka CLI: porównanie replay

Tryb compare-replays przyjmuje dwie ścieżki i zwraca wersjonowany raport.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Tryb compare-replays przyjmuje dwie ścieżki i zwraca wersjonowany raport.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 45. Biblioteka CLI: raport stanu katalogu

--library-health zwraca rozmiary, malformed i duplikaty bez zapisu do biblioteki.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: --library-health zwraca rozmiary, malformed i duplikaty bez zapisu do biblioteki.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 46. Analiza: kontrakty legacy archive

Analiza ładuje v1/v2 przez istniejący codec, nie osłabia finalhash.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Analiza ładuje v1/v2 przez istniejący codec, nie osłabia finalhash.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 47. Biblioteka: unicode i długie nazwy w UI

Lista skraca wyłącznie display, tooltip/details zachowują całe48unicode znaków.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Lista skraca wyłącznie display, tooltip/details zachowują całe48unicode znaków.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 48. Biblioteka: blokada podwójnych operacji

UI disable podczas analyze/import/export, drugi click nie duplikuje zadania ani wpisów.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: UI disable podczas analyze/import/export, drugi click nie duplikuje zadania ani wpisów.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 49. Biblioteka: komunikaty błędów dla użytkownika

Known errors mapped na konkretne wskazówki capacity/title/corrupt/path zamiast surowych code.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Known errors mapped na konkretne wskazówki capacity/title/corrupt/path zamiast surowych code.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
## 50. Analiza: izolacja live session

Integracyjny przebieg save/export/analyze/seek/return sprawdza hash+velocities i brak wpływu na onlineauthority.

Files: game/scripts/core/storage/local_archive_library.gd, game/scripts/core/replay/replay_analyzer.gd, game/scripts/core/replay/replay_playback.gd, game/scripts/client/ui/library_panel.gd, game/scripts/client/session/library_preferences.gd, game/scripts/server/utility_cli.gd, game/tests/unit/archive_analysis_tests.gd, tools/test_analysis_cli.py

- [x] Regression: Integracyjny przebieg save/export/analyze/seek/return sprawdza hash+velocities i brak wpływu na onlineauthority.
- [x] Implement behavior within existing API compatibility.
- [x] Run domain suite; require exit0 and no script errors.
