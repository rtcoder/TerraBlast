# Arena Workshop — plan 50 zadań

## Zakres i istniejące punkty rozszerzeń

Wyłącznie lokalny edytor istniejącego schematu `MapDefinition`: metadata, boxes, sferyczne carves i spawns. Natywne `Window` z listami i formularzami oraz voxelowym przekrojem XZ, a następnie rzeczywisty playtest w istniejącej scenie 3D. Podgląd przekroju świadomie zastępuje kosztowny drugi renderer 3D; playtest wykorzystuje normalny `VoxelWorld` i istniejącą kamerę. Nie tworzymy języka operacji ani formatów archiwum. Nie zmieniamy exported pól Rules/Weapon. Dokument ma maksymalnie 32 snapshoty historii; bez ciągłego zapisu każdego naciśnięcia klawisza.

Istniejące API do ponownego użycia, bez edycji:
- `MapDefinition.copy()` głęboko kopiuje wszystkie kolekcje.
- `MapLoader.load_from_file(path)` ma limit 1 MiB; `from_dictionary(data)` przyjmuje schemat dokumentu.
- `MapSerializer.to_dictionary(definition)` i `to_toml(definition)` zachowują istniejący TOML.
- `MapValidator.validate_definition(definition)` dla struktury i `ArenaGenerator.from_definition(definition)` dla spawnu/kolizji/świata.
- `MapRegistry.PATHS` i `MapRegistry.describe(id)` do listy shipped maps.
- `SpawnSelector.select(spawns,count)` do supported counts 2..10.
- `MatchFactory.from_definition(definition,count,preset,loadout)` tworzy runner custom mapy bez tymczasowego wpisu w registry.
- Scena ma `_replace_local_runner(replacement)` do rebindowania renderer/rules/player nodes, `_refresh_menu_state()`, `_close_overlays()` i `session.recorder`.

## Nowe pliki i API

### `game/scripts/core/workshop/workshop_document.gd`
`extends RefCounted`, bez Node/UI. Prywatny `definition`, `revision`, `selection := {kind,index}`, `saved_text`, `source_path`, `undo_stack`, `redo_stack`; stała `HISTORY_LIMIT := 32`.

- `new_document() -> Dictionary`: poprawny mały fixture 32×12×32, floor + 2 spawny.
- `replace_definition(candidate: RefCounted, path := "") -> Dictionary`: głęboka kopia, czyszczenie historii, saved baseline.
- `snapshot() -> RefCounted`: zwraca kopię; nie oddaje mutowalnego wnętrza do preview/UI.
- `set_metadata(patch: Dictionary) -> Dictionary`.
- `add_entry(kind: String, entry: Dictionary) -> Dictionary`.
- `update_entry(kind: String, index: int, patch: Dictionary) -> Dictionary`.
- `duplicate_entry(kind: String, index: int) -> Dictionary`.
- `remove_entry(kind: String, index: int) -> Dictionary`.
- `move_entry(kind: String, index: int, delta: int) -> Dictionary`: reorder boxes (carves mogą zachować stałą kolejność).
- `select(kind: String, index: int) -> void` z normalizacją po każdej zmianie.
- `undo() -> bool`, `redo() -> bool`, `can_undo()`, `can_redo()`, `is_dirty()`, `mark_saved(path)`, `history_summary()`.
- `validate() -> Dictionary {ok,errors,supported_counts,arena,revision}`: pełna walidacja + ograniczony build; cache dla danej revision.
- Każda mutacja zwraca `{ok,reason}`, jest atomowa i ignoruje no-op. Edycja wpisu kontroluje typy/zakresy; celowo pozwala na tymczasowe kolizje spawnów. Resize zachowuje wpisy i pokazuje ich problemy. Eksport/playtest wymagają walidacji stosownej do czynności.
- Dirty porównuje kanoniczny słownik (nie serializer odrzucający niepełny draft), aby Undo do saved baseline działało.

### `game/scripts/core/workshop/workshop_store.gd`
- `load_document(path: String) -> Dictionary {ok,definition,reason}`: bez zmiany bieżącego dokumentu w razie błędu, limit przed odczytem.
- `save_document(path: String, definition: RefCounted) -> Dictionary {ok,reason}`: `MapSerializer`, tylko lokalna ścieżka `.toml`, blokada `res://`, tymczasowy plik w docelowym folderze, flush/close/rename i cleanup.
- Jawny hook do deterministycznego wymuszenia awarii przed rename wyłącznie w testach store; alternatywnie filesystem fixture target-as-directory. Należy unikać testów, które udają sukces IO.

### `game/scripts/client/workshop/workshop_preview.gd`
`extends Control`, `_draw()` koloruje dane świata z `ArenaGenerator` (nie odtwarza MapBuilder), mierzy cell rect i renderuje obrys wybranej operacji, spawny/team/slot/yaw.
- `present(definition, validation, selection)`, `set_layer(y)`, `set_zoom(value)`, `fit()`.
- `cell_at_point(local_position) -> Variant` (Vector3i lub null) dla testów i click-to-form.
- `signal cell_selected(position: Vector3i)`; żadnej mutacji dokumentu bez Apply.
- Cache ostatniego poprawnego world; błędny dokument oznacza preview jako stale. Rysowany przekrój maks. 256×256, bez Node na voxel.

### `game/scripts/client/workshop/workshop_window.gd`
`extends Window`, `force_native = true`, otwierany przez `popup_centered()` z rozmiarem zależnym od usable screen; ScrollContainer chroni formularze przy mniejszym oknie.
- `setup(document)`, `present()`, `refresh()`, `set_notice(text)`.
- `signal playtest_requested(count: int)`, `signal exit_requested`, `signal closed`.
- Metadane, shipped selector, New/Import/Save/Save As, Undo/Redo/Validate, ItemList trzech kolekcji, formularze z Apply/Add/Duplicate/Delete i reorder boxes.
- FileDialog dziedziczący natywne okno; ConfirmationDialog Save/Discard/Cancel dla niszczących akcji.
- Kontrolki jako jawne pola/nazwy Node, aby testy naciskały faktyczne przyciski i zmieniały formularze. Nie tylko testy prywatnych helperów.
- Input handled lokalnie; blokada zdarzeń w scenie przez pause/menu contract. Skróty Ctrl+Z i Ctrl+Shift+Z nie przechwytują edycji LineEdit, jeśli jego własna historia ma fokus; toolbar zawsze dostępny. Escape przechodzi dirty-close.

### `game/scripts/client/workshop/workshop_workflows.gd`
`extends RefCounted`, `_init(owner_scene)`, `setup()` tworzy Window jako dziecko sceny oraz mały `PanelContainer` w Hud z Return/Restart podczas testu.
- `open() -> bool`, `close() -> bool`, `start_playtest(count: int) -> bool`, `return_to_editor() -> void`, `restart_playtest() -> bool`, `shutdown() -> void`.
- `is_active() -> bool`, `is_playtesting() -> bool`, `overlays_open() -> bool`, `blocks_persistence() -> bool`, `blocked_reason() -> String`.
- Przed wejściem sprawdza remote_mode, projectile, playback, training i istniejące workflow. Zachowuje ref runner/recorder/bot/options oraz deep kopie velocities/weapon selection i camera/pause/mouse state. Otwarcie pauzuje fizykę meczu; preview nigdy nie podmienia runnera.
- Start test buduje kandydata PRZED zmianą sceny; dopiero sukces wywołuje `_replace_local_runner`, tworzy osobny recorder, zatrzymuje bot solo i odblokowuje lokalną grę. Dokument i oryginalny runner są odseparowane.
- Return zatrzymuje/purguje projectile przez istniejący scene helper, przywraca oryginalny runner+recorder/kontekst i ponownie otwiera Window; close wraca do oryginalnego stanu pauzy i myszy. Testowy runner nie może trafić do autosave/library/series/network.

## Kontrakt hooków sceny — do wykonania przez rodzica

Nie edytuję `voxel_debug.gd` ani `match_panels.gd` przed uzgodnieniem:
1. Scena `var workshop: RefCounted`, po pozostałych workflow: `.new(self); workshop.setup()`.
2. Panel/menu `signal workshop_requested` z przyciskiem `Arena Workshop`; scena łączy do `workshop.open`. Bez nowego skrótu klawiszowego z konfliktem.
3. `_refresh_menu_state()` bierze `workshop.overlays_open()` pod uwagę; `_close_overlays()` nie zamyka okna i nie niszczy retained context. Obsługa `Window` oddzielona od Control focus controller.
4. Przed startem remote/training/replay/start_local_match/reset-series oraz archive/save/autosave sprawdzenie `workshop.is_active()/blocks_persistence()`. Zwykły restart w playtest kierowany do `workshop.restart_playtest()`; normalny R/restart pozostaje bez zmian poza tym stanem.
5. `client_workflows.update()` pomija autosave/series/handoff w całym active workshop, a `local_session.can_archive()` zwraca false. `local_session.is_bot_turn()` false podczas playtest (hotseat test). Rodzic dodaje minimalne guards we wspólnych plikach.
6. Stan aktywny obejmuje okno i grę testową; overlays_open dotyczy tylko okna/promptu, żeby test mógł symulować ruch i strzały.
7. Scena wywołuje `workshop.shutdown()` przy `_exit_tree`, bez przywracania już niszczonych Node. Window.close_requested prowadzi do dirty prompt.

## Weryfikacja

Nowe suite `game/tests/unit/workshop_oct19_tests.gd` (dokument/store/roundtrip/budżet32/klony/validation) oraz `game/tests/integration/workshop_oct19_next_tests.gd` (rzeczywiste Window/form/buttons/preview/cycle/live-state guards). Co najmniej jedno nazwane check per każdy acceptance z JSON; testy przypadków brzegowych łączone tematycznie.

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script tests/unit/workshop_oct19_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script tests/integration/workshop_oct19_next_tests.gd
python3 tools/run_tests.py --include '*workshop*' --timeout 120
```

Godot wymaga eskalacji w tym środowisku; testy filesystem używają `/private/tmp` na macOS i `/tmp` na Linux. Rodzic uruchamia pełny suite po integracji. Osobny widoczny smoke natywnego Window potwierdza fokus, zamknięcie i dialog, bo headless nie dowodzi zachowania systemowego zarządcy okien.

## Wykonalność i tradeoffy

50 zadań to spójny lokalny produkt, nie 50 nowych systemów. Shared form/model mutation/history obsługują większość CRUD bez kopiowania kodu. Każde zadanie ma widoczną akcję, konkretny wynik i osobne asercje. Nie rozwijamy parsera, analiz aren ani multiplayer custom maps, więc nie dublujemy poprzednich 250. Największe ryzyko to lifecycle guards i natywne okno; wymagają powyższych hooków od rodzica oraz testu pełnego cyklu oryginalny mecz → edycja → test → edycja → oryginalny mecz. Brak zewnętrznych bibliotek, rozszerzeń Godota i generowania zasobów.
