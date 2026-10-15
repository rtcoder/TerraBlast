# TB-82–131 acceptance ledger

Exactly 50 tasks; user preapproved plan, implementation and local main integration. Baseline 638c66c.

| Task | Evidence |
|---|---|
| TB-82 — Map audit | tools/test_devtools.py malformed fixtures and both shipped arenas |
| TB-83 — Portable launchers | external cwd test, actual separate-process ENet smoke |
| TB-84 — Match: Statystyki strzałów, trafień, obrażeń i eliminacji | core_next_tests.gd and existing core50_tests.gd |
| TB-85 — Match: Ograniczona historia wyników tur | core_next_tests.gd and existing core50_tests.gd |
| TB-86 — Match: Autorytatywne poddanie gracza | core_next_tests.gd and existing core50_tests.gd |
| TB-87 — Rules: Limit tur kończący mecz remisem | core_next_tests.gd and existing core50_tests.gd |
| TB-88 — Rules: Presety classic, quick i training | core_next_tests.gd and existing core50_tests.gd |
| TB-89 — Projectile: Deterministyczny wiatr poziomy | core_next_tests.gd and existing core50_tests.gd |
| TB-90 — Core: Wspólny raycast voxelowy dla celowania | core_next_tests.gd and existing core50_tests.gd |
| TB-91 — Core: Respektować is_solid materiałów w kolizjach | core_next_tests.gd and existing core50_tests.gd |
| TB-92 — Replay: Atomowy zapis i ograniczony odczyt pliku | core_next_tests.gd and existing core50_tests.gd |
| TB-93 — Replay: Sprawdzać hash końcowego wyniku nagrania | core_next_tests.gd and existing core50_tests.gd |
| TB-94 — Network: Przesyłać reguły i konfigurację broni w snapshotach | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-95 — Network: Synchronizować statystyki i historię meczu | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-96 — Network: Komenda poddania przypisana do peera | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-97 — Network: Jawny stan oczekiwania na drugiego gracza | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-98 — Network: Ping/pong i pomiar opóźnienia | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-99 — Server: Diagnostyka obsłużonych i odrzuconych pakietów | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-100 — Network: Postęp pobierania snapshotu | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-101 — Protocol: Odrzucać duplikaty i nieoczekiwane chunki | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-102 — Protocol: Walidacja pozycji graczy względem areny | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-103 — Protocol: Walidacja ortonormalnej rotacji gracza | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-104 — Network: Czytelne powody odrzuconych intencji | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-105 — Server: Kontrolowane zamknięcie sesji | network_next_tests.gd, network50_tests.gd, real ENet |
| TB-106 — CI: Headless pipeline testów Godot | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-107 — Build: Presety eksportu desktop i Linux server | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-108 — Devtools: Doctor środowiska w JSON | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-109 — Tests: Limit czasu każdego procesu testowego | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-110 — Tests: Raport JSON z wynikami zestawu | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-111 — Tests: Przenośny runner osobnych procesów sieciowych | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-112 — CLI: Pomoc --help bez uruchamiania meczu | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-113 — CLI: Wersja --version bez uruchamiania sceny | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-114 — CLI: Atomowy zapis summary przez --output | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-115 — CLI: Weryfikacja nagrania replay z pliku | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-116 — CLI: Wybór presetów reguł przy uruchomieniu | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-117 — CLI: Lista dostępnych aren z metadanymi | test_devtools.py, devtools_next_tests.gd, doctor/CLI/export configuration checks |
| TB-118 — UI: Pauza lokalnego meczu | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-119 — UI: Panel nowego meczu z areną i presetem | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-120 — Settings: Przywrócenie domyślnych preferencji | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-121 — Accessibility: Skalowanie tekstu HUD | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-122 — Settings: Przełącznik preview trajektorii | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-123 — Accessibility: Kontrastowy wariant celownika | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-124 — UI: Pomoc sterowania w grze | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-125 — UI: Etykiety HP nad postaciami | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-126 — UI: Baner zmiany tury | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-127 — UI: Podsumowanie ostatniego strzału | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-128 — UI: Panel końca meczu z restartem | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-129 — UI: Statystyki meczu w scoreboardzie | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-130 — UI: Przycisk poddania w menu meczu | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |
| TB-131 — UI: Postęp synchronizacji i RTT połączenia | client_next_tests.gd, client50_tests.gd, rendered 1280×720 panels |

## Review fixes

Malformed player rows are rejected before summary dereference. Protocol v2 requires validated configuration and transfer IDs; configured arena/turn-limit checks cannot be bypassed. End-of-match UI is presented once per result, allowing settings/help/new-match overlays. Local pause freezes projectile playback; restart removes transient effects. Fresh reviewer reproduced each blocker and confirmed its correction.

## Verification boundary

Export presets were validated as configuration; desktop/server binaries were not exported. CI workflow was checked locally; no remote push or GitHub execution is claimed. Linux/Windows runtime verification remains separate from local macOS tests. Full suite passed 24/24 checks with RUN_NAKAMA_TESTS=1 RUN_RENDER_TESTS=1 bash tools/run_godot_tests.sh; report /tmp/terrablast-oct15-verified/report.json. This includes the real separate-process server/two-client test, Nakama, Metal renderer and CLI/tool regressions. After the final history-schema correction, core_next_tests and core50_tests passed again, including RED-to-GREEN mid-match capture/archive roundtrip. Settings at 125% and setup panel were rendered and inspected at1280×720. Fresh review confirmed no remaining P1/P2.

The final integration also fixes simultaneous ENet disconnect broadcasts (three repeated real-process regression runs), records destroyed voxels separately from damaged deltas, and accepts seven-field history rows in mid-match replay captures.
