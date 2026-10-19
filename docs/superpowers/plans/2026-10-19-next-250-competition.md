# Competition: 50 zadań — kontrakt do przeglądu

Stan bazowy: 0e274a2; Godot 4.6.2. Produkt obejmuje obecnie ręczny best-of 1/3/5 i 11 treningów; nie ma terminarzy ani turniejów. Propozycja nie powiela tych funkcji i nie dodaje kolejnych ćwiczeń.

## Zakres produktu

Lokalne wydarzenie hotseat, 2–8 nazwanych uczestników (każdy reprezentuje jeden z dwóch zespołów istniejącego pojedynczego meczu). Format `league`, `double_league` lub `knockout`; istniejące presety; 2/4/6/8/10 postaci z równą liczbą po stronach; 1–9 istniejących aren w rotacji. Tożsamość uczestnika jest niezależna od Blue/Red i graczy. Nie ma bot-v-bot, online, nowych zasad, broni, eksportowanych pól Rules/Weapon ani zmian archiwów.

Liga: 3/1/0 punktów, potem mała tabela grupy remisujących według punktów bezpośrednich, liczba wszystkich zwycięstw, rozstawienie. Kryteria są jawne w UI. Bez rekurencyjnego powtarzania małej tabeli podgrup. KO: wolne losy według rozstawienia; remis oznacza ponowne rozegranie tej samej pary na tej samej arenie, nie losowy awans. Przechowujemy tylko ostatni remis i numer próby, nie rosnącą historię powtórek. Brak korekt pucharowych po awansach; korekta ligi dostępna bez aktywnego runnera.

Maksimum 56 rzeczywistych fixtures (liga z rewanżami, n=8). Po jednej finalnej pozycji wyniku na fixture. Terminarz wynika z konfiguracji, nie z dowolnych par importowanych z pliku. W UI można wybrać dowolną gotową parę bieżącej kolejki/rundy; następna kolejka po zamknięciu bieżącej.

## Własność plików

Agent competition edytuje WYŁĄCZNIE nowe pliki:

- `game/scripts/core/competition/competition_config.gd`
- `game/scripts/core/competition/competition_schedule.gd`
- `game/scripts/core/competition/competition_event.gd`
- `game/scripts/core/competition/competition_results.gd`
- `game/scripts/core/competition/competition_standings.gd`
- `game/scripts/core/competition/competition_store.gd`
- `game/scripts/client/competition/competition_controller.gd`
- `game/scripts/client/competition/competition_panel.gd`
- `game/tests/unit/competition19_tests.gd`
- `game/tests/unit/competition_store19_tests.gd`
- `game/tests/integration/competition19_tests.gd`
- odpowiadające `.uid` i evidence JSON, jeżeli root zleci.

Root jest jedynym edytorem istniejących `client/debug/voxel_debug.gd`, `client/ui/match_panels.gd` i `client/session/client_workflows.gd`. Żadnych zmian `project.godot`, istniejących modeli sesji/archiwum lub magazynu replay.

## Czyste API core (RefCounted, brak scen)

Wszystkie operacje zwracają `{ok:bool, reason?:String, ...}`. Publiczne tablice i snapshoty są kopiami, nie referencjami do prywatnych danych.

### CompetitionConfig

`static validate(value:Variant)->Dictionary {ok,config?,reason?}`: dokładnie `title:String(1..64), format:String, entrants:Array[{id:String,name:String,seed:int}], maps:Array[String], count:int, preset:String`. Id `entrant_1`…`entrant_8`, seed 0..n-1 w jednoznacznej kolejności. Na etapie budowy draft panel sam tworzy id; reorder zmienia seed, nie id. Nazwy uczestników 1..32, unikalne po strip_edges/to_lower, brak znaków kontrolnych; nazwa wydarzenia również bez kontrolek. Mapy unikalne, znane i obsługujące count. `static defaults()->Dictionary`; `static preview(config)->Dictionary {rounds,fixtures,byes}`.

Walidacja map przez istniejący `MapRegistry.describe(...).supported_player_counts`. Core nie zależy od scene ani domyślnej ścieżki user://; map registry może ładować res:// zgodnie ze swoim istniejącym kontraktem.

### CompetitionSchedule

`static generate(config:Dictionary)->Array[Dictionary]`; fixture `{id,round,index,a,b,map,source_a,source_b,bye}`. `a/b` id lub pusty string dla nierozstrzygniętych slotów. `source_a/source_b` id poprzednika albo pusty string. Byes są slotami drabinki, nie fixture z finalnym wynikiem; wynikowa lista rzeczywistych meczów nigdy nie przekracza 56. `static ready(fixtures,results)->Array[String]`; `static resolve(fixtures,results)->Array` zwraca kopię z wypełnionymi awansami.

Round-robin circle method; nieparzysta liczba ma wirtualny bye. Orientacja par ma różnicę A/B <=1 na uczestnika; rewanże odwracają oba zespoły. Numery fixture i przypisanie aren nie zależą od kolejności wpisów słownika.

### CompetitionEvent

Stan prywatny: `config`, `results`, `active`, `next_attempt`, `frozen`; harmonogram wyliczany, nie przechowywany jako zaufane dane.

- `create(config:Variant)->Dictionary` — pełna walidacja i zamiana po sukcesie.
- `snapshot()->Dictionary` — prymitywne, zagnieżdżone dane, bez runnera.
- `restore(value:Variant)->Dictionary` — pełna walidacja w kandydacie, zamiana dopiero po sukcesie.
- `update_draft(config:Variant)->Dictionary`, `rename_entrant(id,name)->Dictionary`.
- `fixtures()->Array`; `ready_ids()->Array`; `launch(fixture_id:String)->Dictionary {ok,token,fixture,config}`. Token `{fixture_id,attempt}`; next_attempt monotoniczny 1..1_000_000_000. Brak aktywnego meczu + aktualny draft zatwierdzony to warunek launch. Zamrożenie dopiero przy pierwszym zaakceptowanym launch.
- `record(token:Dictionary,winner_team:int)->Dictionary {ok,completed,draw_replay}`. Wymaga zgodności aktywnego tokenu. KO draw usuwa active i zachowuje last_draw bez awansu; kolejny launch tworzy nowy token.
- `abandon(token)->Dictionary` usuwa active bez wyniku.
- `correct(fixture_id,winner_team)->Dictionary` tylko league/double_league bez active, zastępuje finalny rezultat i przelicza tabelę.
- `is_complete()->bool`, `champion()->String`, `standings()->Array`, `report()->String`.

Konfig może być edytowany przed pierwszym launch. Potwierdzenie draft w UI nie blokuje pól na zawsze. Nazwy można zmieniać po zamrożeniu, bo wyniki wskazują id. Save/restore sprawdza, że wyniki są osiągalne w kolejności terminarza i nie zawierają slotów nierozwiązanych.

### CompetitionResults

`static validate_result(value:Variant,fixture:Dictionary)->Dictionary`; `static from_winner(fixture,token,winner_team)->Dictionary`; `static history(event_snapshot)->Array`. Nie pobiera wyniku z dowolnego runnera; adapter wcześniej sprawdza tożsamość i status ended.

### CompetitionStandings

`static calculate(config,results)->Array[Dictionary]` z `id,rank,played,wins,draws,losses,points,head_points,tiebreak`. `static matrix(config,results)->Array`; `static report(event_snapshot)->String`. Punkty małej tabeli liczone raz dla wszystkich osób z równą liczbą punktów głównych. KO raport pokazuje drabinkę i mistrza zamiast fikcyjnej ligi.

### CompetitionStore

`const DEFAULT_PATH='user://local_competition.json'`; `MAX_BYTES=SessionStore.MAX_BYTES+262144`.

`static save(path:String,event:RefCounted,match_payload:Dictionary={})->Dictionary`; `static load(path:String)->Dictionary {ok,event?,match?:Dictionary,reason?}`; `static encode(event_snapshot,match_payload)->Dictionary`; `static decode(payload:Variant)->Dictionary`.

Otoczka dokładnie `{format:'terrablast_competition',version:1,event:Dictionary,match:Dictionary}`. match puste bez aktywnego meczu, w przeciwnym razie `{token:Dictionary,payload:Dictionary}` z NIEZMIENIONYM outputem `SessionStore.encode`. Stan active wymaga payloadu i odwrotnie; token musi odpowiadać active. Sprawdzenie payloadu przez `SessionStore.decode`, options dokładnie hotseat/normal/1, liczba i rozkład zespołów zgodne z config, stan playing albo ended bez zaakceptowanego jeszcze wyniku. Zgodność areny/presetu zweryfikowana względem kanonicznej fabryki lub jawnego skrótu początkowego config w otoczce tylko jeżeli root zatwierdzi rozszerzenie. Nie można twierdzić, że sama liczba graczy udowadnia mapę; istniejący SessionStore potwierdza integralność runnera, nie jego pochodzenie.

Odczyt najpierw limit rozmiaru, potem JSON; wszelkie floaty wymagają numerycznej całkowitości w granicach. Atomowy write przez unikatowy temp/flush/error/close/rename, brak ścieżek z treści pliku i brak skanowania archiwów. Niepowodzenie decode nie mutuje eventu lub sceny.

## Adapter sceny — publiczne API i hooki roota

`CompetitionController.new(scene:Node, path:String=Store.DEFAULT_PATH)`; `setup()->void` tworzy własny panel w `scene/Hud`, własny pasek nazw drużyn i przycisk powrotu. Nie dopisuje potomków do match_panels poza jawnym root hookiem.

- `open()->bool` wstrzymuje grę przez widoczny panel; tylko local + brak playback/training/projectile.
- `close()->void` zamyka panel bez porzucania aktywnego fixture.
- `overlays_open()->bool` do scene._refresh_menu_state.
- `blocks_external_action()->bool` true podczas aktywnego fixture lub zachowanego kontekstu turnieju; służy do odrzucenia ścieżek, które nadpisałyby aktywny runner. UI obcych workflow może pozostać wyłączone z powodem.
- `close_overlays()->void` do scene._close_overlays, chowa wyłącznie panel/confirm, nie HUD meczu.
- `update(delta:float)->void` sprawdza tylko własny `fixture_runner == scene.runner`, status ended, brak pocisku/playback/remote; zapisuje wynik raz i pokazuje osobny przycisk Back to competition. Przy zakończeniu nie otwiera panelu co klatkę.
- `launch(fixture_id)->Dictionary`: zachowuje oryginalny kontekst, pre-save eventu, wewnętrzna flaga launching pozwala ominąć własny guard, istniejące `scene.start_local_match(map,count,preset,'hotseat','normal',1)`, a dopiero po sukcesie zatwierdza token i wiąże runner. Niepowodzenie start nie może pozostawić w pamięci lub pliku aktywnego fixture bez runnera. Szczegół kolejności save: przed launch zapis gotowego eventu, po sukcesie snapshot nowego runnera; błąd drugiego save daje dirty i możliwość Save, nie utratę kontekstu.
- `save()->Dictionary`, `resume()->Dictionary`, `abandon_active()->Dictionary`, `return_to_live()->Dictionary`.
- `is_internal_launch()->bool` dla guard w start_local_match i _replace_local_runner.

Kontekst live zachowuje oryginalne referencje runner/recorder, kopie options/velocities oraz `workflows.series` (cały obiekt, nie tylko scores), series_config, match_epoch, handoff. Na wejście turnieju podmienia `workflows.series` na nowy nieaktywny MatchSeries; starego obiektu nie mutuje. Na powrót `_replace_local_runner(live.runner)`, przywraca recorder/options/velocities i wcześniej zachowany obiekt serii; ustawia workflows.last_live_runner/last_turn tak, żeby następne update() nie wyzerowało przywróconej serii. Zapis na dysku wznawia turniej w nowym procesie, ale nie serializuje starego live-context; przy resume kontekst aktualnej gry zostaje zachowany przez ten sam mechanizm.

Minimalne edycje roota:

1. `voxel_debug.gd`: zmienna `competition`; po utworzeniu workflows `competition=preload(...controller...).new(self); competition.setup()`.
2. `match_panels.gd`: sygnał `competition_requested`; jeden przycisk pauzy „Local competition”. Scene łączy go z `competition.open`.
3. `voxel_debug.gd`: w `_refresh_menu_state` uwzględnij `competition.overlays_open()`, w `_close_overlays` `competition.close_overlays()`, w physics/process po zakończeniu aktualizacji `competition.update(delta)`.
4. Guard `blocks_external_action` + komunikat w istniejących restart/new-match/load/replay/training/network/library load/continue-autosave; bypass wyłącznie jawnej wewnętrznej flagi adaptera. W `client_workflows.gd` wejścia begin_training, continue_autosave, next_round i request(action) odrzucają aktywne rozgrywki. Nie blokować pojedynczego surrender: jest normalnym zakończeniem turniejowego meczu.
5. Podczas turnieju end-panel Restart i Next round in series wyłączone; własny przycisk Back to competition działa po zakończeniu. Stara best-of seria nie dostaje turniejowego wyniku.
6. Escape może zamknąć hub i wznowić aktywny fixture; wyjście z wydarzenia/porzucenie próby wymaga istniejącej własnej sekcji potwierdzenia (zgodnie z zaakceptowanym wzorcem produktu, bez pytań do użytkownika w czacie).

Root nie powinien kodować logiki terminarza/tabeli; wszystkie zdarzenia panelu obsługuje adapter. Plan wymaga rzeczywistego przycisku w scenie, a nie jedynie helpera dostępnego w testach.

## UI

CompetitionPanel extends PanelContainer, ScrollContainer/VBox; zakładki Create/Schedule/Standings/Results realizowane przyciskami w tym samym panelu. `configure(config,event_view)`, `set_status(text,is_error=false)`, `refresh(event_view)`, `fit(viewport,hud_scale)`; sygnały create_requested(config), rename_requested(id,name), play_requested(id), save_requested, resume_requested, correction_requested(id,winner), abandon_requested, exit_requested, close_requested, copy_report_requested. Pola formularza pozostają dostępne w testach przez nazwy węzłów. Checkboxy map wykluczają te z za małą pojemnością. Natywne Label/LineEdit/OptionButton/SpinBox/Button, bez HTML/web.

Oddzielna sekcja potwierdzenia posiada kopię tokenu revision/id; zatwierdzenie po zmianie wydarzenia jest odrzucane. Dirty feedback i disabled reason widoczne. Raport w TextEdit(readonly/selectable) + Copy przez DisplayServer.clipboard_set w obsłudze jawnego przycisku. Nie polegać wyłącznie na kolorach.

## Weryfikacja i dowody

Godot executable: `/Applications/Godot.app/Contents/MacOS/Godot`.

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/unit/competition19_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/unit/competition_store19_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/integration/competition19_tests.gd
```

Każdy suite SceneTree kończy się bounded quit(0/1). Izolowane katalogi `/private/tmp/terrablast-competition19-<pid>`; adapter otrzymuje ścieżkę fixture przed setup/resume. Żadnego realnego user://local_competition.json podczas testów.

Core: wszystkie n=2..8, oba formaty ligowe i KO; pary, strony, pauzy, kolejki, rotacja aren, stabilność przy permutacji Dictionary, 3-team tiebreak, korekta, stale token, dedupe, KO draw replay, pełny puchar z byes.

Store: roundtrip draft/partial/completed/active; exact session_hash i velocities; uszkodzona wersja/klucze/rozmiar/id/attempt/token/hash/pair/advance; atomic failure zachowuje plik; decode failure zachowuje event. Prawdziwe SessionStore.encode/decode i MatchFactory, brak fake runnerów.

Integration: rzeczywista VoxelDebug scene, kliknięcie natywnego przycisku menu i panelu; launch właściwej pary/areny; skończenie meczów przez recorder.surrender lub legalny stan finalny, nigdy tylko bezpośrednie wpisywanie winner w samym teście UI; powrót do tabeli, save/resume, obsługa blokad i powrót oryginalnego live runnera/recorder/serii. Test chociaż pełnej ligi 3 osób i pucharu 3 osób. Weryfikacja guardów wymaga root hooków przed końcowym uruchomieniem suite.

Native QA po zintegrowaniu: 800x600 + 125% HUD, keyboard Tab/Enter/Escape, długie nazwy, formularz, terminarz, tabela, wynik, potwierdzenie; screenshoty tylko do wyznaczonego katalogu evidence. Root koordynuje pełny regresyjny suite, review, YouTrack, commit i push. Ten etap jest wyłącznie planem: brak kodu produktu, Git i YouTrack.
