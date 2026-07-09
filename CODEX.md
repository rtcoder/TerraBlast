# TerraBlast — wytyczne dla Codexa

## 1. Cel projektu

**TerraBlast** to wieloosobowa gra online 3D łącząca:

- destrukcyjny voxelowy świat inspirowany Minecraftem,
- turową walkę artyleryjską inspirowaną Worms,
- krótkie mecze online na arenach,
- cross-platformowego klienta: najpierw macOS / Windows / Linux, później Android / iOS.

Projekt ma być prowadzony jako **desktop-first**, ale bez decyzji blokujących późniejsze mobile.

Główne założenie gameplayowe:

```txt
Turowa wojna na zniszczalnych voxelowych arenach.
```

---

## 2. Decyzje technologiczne

### 2.1. Silnik

Wybór główny:

```txt
Godot 4.x
```

Używać aktualnej stabilnej wersji Godot 4.x dostępnej w momencie startu projektu.

Powody wyboru:

- open-source,
- licencja MIT,
- lekki workflow na macOS,
- dobre tempo prototypowania,
- sensowny export na desktop i mobile,
- możliwość uruchamiania headless servera,
- naturalny fit pod indie voxel/low-poly game.

Nie używać Unity jako domyślnej ścieżki dla tego projektu.

### 2.2. Język

Główna ścieżka:

```txt
GDScript
```

Powody:

- najlepsza integracja z Godotem,
- najmniej tarcia przy exportach,
- bezpieczniejsza ścieżka pod mobile,
- szybkie iteracje,
- prostszy onboarding projektu.

Nie wybierać C# jako głównej ścieżki, chyba że zostanie jawnie podjęta decyzja architektoniczna.

C# można rozważyć tylko wtedy, gdy:
- projekt pozostaje desktop-only,
- konkretna funkcjonalność mocno korzysta z ekosystemu .NET,
- ograniczenia mobile/web są zaakceptowane.

### 2.3. Kod wydajnościowy

Jeżeli profiler pokaże realny problem, dopuszczalne jest dodanie:

```txt
GDExtension C++
GDExtension Rust
```

Ale dopiero po prototypie.

Nie zaczynać projektu od C++/Rust.

Kolejność:

```txt
1. GDScript
2. profilowanie
3. optymalizacja algorytmów
4. GDExtension tylko dla gorących ścieżek
```

---

## 3. Backend i multiplayer

### 3.1. Model sieciowy

Gra ma być:

```txt
server-authoritative
```

Serwer ma zawsze rację.

Klient wysyła intencję gracza, np.:

```txt
weapon_id
aim_direction
shot_power
turn_id
client_prediction_seed
```

Serwer liczy:

```txt
trajectory
collision
explosion
terrain damage
player damage
knockback
turn result
win condition
```

Klient dostaje zatwierdzony wynik tury.

Nie używać modelu client-authoritative dla logiki gameplay-critical.

### 3.2. Nakama

Backend meta-game:

```txt
Nakama
PostgreSQL
Docker / Docker Compose / OrbStack
```

Nakama odpowiada za:

- logowanie guest / użytkownik,
- matchmaking,
- lobby,
- profile graczy,
- rankingi,
- statystyki,
- storage,
- później: skiny, progres, sezony.

Nie wkładać całej logiki meczu do Nakama, jeśli lepiej utrzymać ją w Godot headless serverze.

### 3.3. Godot headless match server

Serwer meczu:

```txt
Godot headless dedicated server
Linux
Docker
```

Odpowiada za:

- stan meczu,
- system tur,
- walidację akcji,
- symulację pocisków,
- destrukcję voxelowego terenu,
- damage,
- synchronizację terrain delta,
- warunki zwycięstwa.

Architektura logiczna:

```txt
Client -> Nakama: auth / matchmaking / lobby
Nakama -> Match server: start / allocate match
Client -> Match server: gameplay input
Match server -> Clients: authoritative result
```

Na MVP dopuszczalne jest prostsze podejście:

```txt
Nakama local + ręczne joinowanie serwera meczu
```

Ale nie projektować gry jako peer-to-peer.

---

## 4. Platformy

### 4.1. Dev machine

Główne środowisko developera:

```txt
macOS
Apple Silicon preferred
```

Codex ma zakładać macOS jako podstawowe środowisko pracy.

### 4.2. Pierwsze targety

Pierwszy etap:

```txt
macOS
Windows x86_64
Linux x86_64
```

Priorytet testowania:

```txt
1. macOS dev build
2. Linux headless server
3. Windows desktop build
4. Linux desktop build
```

### 4.3. Mobile później

Drugi etap:

```txt
Android
iOS
```

Kolejność:

```txt
1. Android
2. iOS
```

Mobile nie może wymuszać przepisywania core gameplayu.

Różnić się mogą:

- UI,
- input,
- jakość grafiki,
- draw distance,
- liczba particles,
- target FPS,
- rozmiary tekstur,
- detale VFX.

Nie mieszać mobile-only hacków z core simulation.

---

## 5. Struktura repozytorium

Preferowana struktura:

```txt
terrablast/
  game/
    project.godot
    scenes/
    scripts/
    assets/
    addons/
    tests/
  backend/
    docker-compose.yml
    nakama/
    postgres/
  server/
    Dockerfile
    scripts/
  docs/
    architecture.md
    networking.md
    terrain.md
    weapons.md
    mobile.md
    decisions/
  tools/
  README.md
  CODEX.md
  .gitignore
  .env.example
```

Na początku dopuszczalne:

```txt
terrablast/
  game/
  docs/
  README.md
  CODEX.md
```

Nie blokować późniejszego wydzielenia `backend/` i `server/`.

---

## 6. Struktura projektu Godot

W katalogu `game/`:

```txt
game/
  project.godot

  scenes/
    main/
      Main.tscn
    menu/
      MainMenu.tscn
      Lobby.tscn
    match/
      Match.tscn
      Arena.tscn
    player/
      PlayerPawn.tscn
    terrain/
      VoxelWorld.tscn
      VoxelChunk.tscn
    weapons/
      Projectile.tscn
    ui/
      Hud.tscn
      WeaponSelector.tscn
      TurnTimer.tscn

  scripts/
    core/
      terrain/
      chunks/
      voxels/
      weapons/
      projectiles/
      turns/
      damage/
      simulation/
      rules/
    client/
      camera/
      input/
      ui/
      vfx/
      audio/
      rendering/
    server/
      authority/
      match_runner/
      validation/
      state_sync/
    networking/
      messages/
      serialization/
      transport/
    shared/
      config/
      constants/
      utils/

  assets/
    materials/
    textures/
    models/
    audio/
    vfx/

  addons/
    nakama/

  tests/
    unit/
    integration/
```

Zasada:

```txt
scripts/core nie może zależeć od UI.
scripts/core nie może ufać klientowi.
scripts/server decyduje o wyniku meczu.
scripts/client tylko pokazuje i wysyła intencje.
```

---

## 7. Zasady architektury Godot

### 7.1. Node’y są warstwą wykonawczą, nie modelem domenowym

Nie trzymać całej logiki gry w scenach i Node’ach.

Preferować:

```txt
Pure GDScript classes dla danych i symulacji
Node’y jako adaptery do Godot runtime
```

Przykład:

```txt
VoxelWorldData.gd      -> dane świata
VoxelDestruction.gd    -> algorytm destrukcji
VoxelWorldNode.gd      -> Node3D renderujący świat
VoxelChunkMesh.gd      -> budowanie meshów
```

### 7.2. Nie robić wszystkiego w `_process`

Unikać ciężkiej logiki w:

```gdscript
func _process(delta):
    pass
```

i

```gdscript
func _physics_process(delta):
    pass
```

Ciężkie operacje:

- wykonywać zdarzeniowo,
- batchować,
- odpalać po turze,
- ograniczać do zmienionych chunków,
- ewentualnie przenieść do wątku po ustabilizowaniu.

### 7.3. Autoload tylko dla rzeczy globalnych

Autoload dopuszczalny dla:

```txt
GameConfig
NetworkManager
AudioManager
SceneLoader
SessionManager
```

Nie używać Autoload jako śmietnika na cały stan gry.

Stan meczu ma być jawny i możliwy do zresetowania.

---

## 8. Model świata voxelowego

### 8.1. Chunking

Świat składa się z chunków.

Startowe parametry:

```txt
Chunk size: 16x16x16
MVP arena: 128x64x128
Voxel representation: material_id + health
```

Nie zaczynać od ogromnych światów proceduralnych.

### 8.2. Voxel

Przykładowy model:

```gdscript
class_name Voxel

var material_id: int = 0
var health: int = 0
```

Uwaga: przy większej liczbie voxelów nie tworzyć jednego obiektu `Voxel` per voxel, jeśli profiler pokaże problem.

Na start czytelność jest ważniejsza, ale docelowo preferować zwarte tablice:

```txt
PackedInt32Array material_ids
PackedByteArray health_values
```

### 8.3. Materiały

Przykładowe material_id:

```txt
0 = Air
1 = Dirt
2 = Stone
3 = Metal
4 = Wood
5 = Sand
6 = Ice
7 = Hazard
```

Każdy materiał ma config:

```txt
id
code
display_name
max_health
blast_resistance
is_solid
is_destructible
material_resource_path
```

Nie hardcode’ować parametrów materiałów w algorytmach destrukcji.

### 8.4. Arena

MVP arena:

```txt
mała
czytelna
symetryczna albo półsymetryczna
bez proceduralnej złożoności
```

Przykład:

```txt
128 x 64 x 128 voxeli
kilka wysp / wzgórz
2 spawn pointy
proste przeszkody
```

---

## 9. Meshowanie voxelowego terenu

### 9.1. Na start

Na MVP wystarczy naiwny meshing:

```txt
Dla każdego solid voxela:
  dla każdej z 6 ścian:
    jeśli sąsiad jest Air/outside:
      dodaj quad do mesha
```

W Godot:

```txt
ArrayMesh
MeshInstance3D
Surface arrays
```

Nie tworzyć osobnego `Cube MeshInstance3D` per voxel.

To jest zabronione przy runtime terrain:

```txt
1 voxel = 1 Node3D
1 voxel = 1 MeshInstance3D
```

### 9.2. Po MVP

Optymalizacje po prototypie:

```txt
greedy meshing
mesh caching
dirty chunk queue
threaded mesh generation
mesh pooling
GDExtension for mesh generation
```

Kolejność optymalizacji zależy od profilera.

### 9.3. Dirty chunks

Po każdej zmianie terenu oznaczać tylko dotknięte chunki jako dirty.

Eksplozja blisko granicy chunka może zmienić kilka chunków.

Pseudo-model:

```gdscript
var dirty_chunks: Dictionary = {}

func mark_chunk_dirty(chunk_position: Vector3i) -> void:
    dirty_chunks[chunk_position] = true
```

Rebuildować tylko dirty chunki.

---

## 10. Destrukcja terenu

### 10.1. MVP

Na MVP destrukcja jest blocky:

```txt
Eksplozja uszkadza albo usuwa voxele w promieniu.
```

Pseudo-logika:

```gdscript
func apply_explosion(center: Vector3i, radius: int, base_damage: int) -> Array:
    var deltas := []

    for pos in get_voxels_in_sphere(center, radius):
        var material_id := world.get_material_id(pos)
        var material := material_registry.get_material(material_id)

        if not material.is_destructible:
            continue

        var distance := center.distance_to(pos)
        var factor := 1.0 - (distance / float(radius))
        var damage := int(base_damage * factor / material.blast_resistance)

        var old_health := world.get_health(pos)
        var new_health := max(0, old_health - damage)

        if new_health <= 0:
            world.set_voxel(pos, 0, 0)
        else:
            world.set_health(pos, new_health)

        deltas.append(TerrainDelta.new(pos, world.get_material_id(pos), world.get_health(pos)))

    return deltas
```

### 10.2. Czego nie robić na MVP

Nie implementować:

- smooth terrain,
- marching cubes,
- realistycznego gruzu,
- dynamicznych płynów,
- pożarów rozprzestrzeniających się po mapie,
- zawalania konstrukcji,
- voxelowego raytracingu,
- skomplikowanych materiałów proceduralnych.

---

## 11. Terrain delta i synchronizacja

### 11.1. Nie synchronizować całej mapy

Po eksplozji nie wysyłać całego świata.

Dozwolone:

```txt
terrain delta
deterministic explosion event
chunk snapshot awaryjnie
```

### 11.2. TerrainDelta

Model:

```gdscript
class_name TerrainDelta

var position: Vector3i
var material_id: int
var health: int
```

Używać do:

- debugowania,
- małych zmian,
- reconnectu częściowego,
- potwierdzania stanu po turze.

### 11.3. ExplosionEvent

Model:

```gdscript
class_name ExplosionEvent

var turn_id: int
var center: Vector3i
var radius: int
var weapon_id: int
var seed: int
```

Klient może odtwarzać destrukcję lokalnie na podstawie zatwierdzonego eventu.

Serwer nadal jest źródłem prawdy.

### 11.4. Chunk snapshot

Snapshot tylko dla:

- reconnect,
- spectator join,
- desync recovery,
- start match,
- debug tools.

---

## 12. System broni

### 12.1. MVP weapons

Na start:

```txt
Bazooka
Grenade
Drill Missile
```

### 12.2. Weapon config

Nie hardcode’ować broni.

Przykład:

```gdscript
class_name WeaponConfig
extends Resource

@export var id: int
@export var code: String
@export var display_name: String
@export var projectile_speed: float
@export var gravity_scale: float
@export var explosion_radius: int
@export var terrain_damage: int
@export var player_damage: int
@export var knockback: float
@export var max_uses_per_match: int
```

Konfiguracje trzymać jako Godot Resource:

```txt
assets/config/weapons/bazooka.tres
assets/config/weapons/grenade.tres
assets/config/weapons/drill_missile.tres
```

### 12.3. Zasady

- Serwer symuluje strzał.
- Klient może pokazać preview trajektorii.
- Preview klienta jest niewiążące.
- Wynik serwera jest ostateczny.
- Każda broń musi mieć testowalne parametry.

---

## 13. Pociski i fizyka

### 13.1. Na MVP

Pociski można symulować własną prostą fizyką, zamiast opierać się w całości na Godot physics.

Powód:

- większa deterministyczność,
- łatwiejsze testy,
- łatwiejsza synchronizacja,
- prostsza walidacja po stronie serwera.

Pseudo-model:

```gdscript
position += velocity * delta
velocity += gravity * gravity_scale * delta
collision = terrain.raycast_or_voxel_sweep(previous_position, position)
```

### 13.2. Tickrate

Dla turowej gry nie potrzeba FPS-owego tickrate.

Start:

```txt
Simulation tick: 30 Hz
Network updates podczas lotu pocisku: 10–20 Hz
Po turze: authoritative result + terrain delta
```

### 13.3. Determinizm

Tam, gdzie używana jest losowość:

```txt
seed musi pochodzić z serwera
```

Nie używać niekontrolowanego randoma po stronie klienta dla gameplay-critical.

---

## 14. System tur

Minimalny flow:

```txt
Match created
Players joined
Arena generated
Players spawned
Turn starts
Active player selects weapon
Active player aims
Active player fires
Server validates
Server simulates
Server broadcasts result
Turn ends
Next player
Win condition
Match ends
```

Model:

```gdscript
class_name TurnState

var turn_id: int
var active_player_id: String
var time_remaining: float
var has_action_been_submitted: bool
```

Zasady:

- martwy gracz nie dostaje tury,
- akcja po czasie jest odrzucana,
- zbyt duża siła strzału jest clampowana,
- nieaktywny gracz nie może wykonać akcji,
- serwer waliduje `turn_id`.

---

## 15. Player state

Model:

```gdscript
class_name PlayerState

var player_id: String
var display_name: String
var position: Vector3
var rotation: Basis
var health: int
var is_alive: bool
var team_id: int
```

Nie zakładać tylko 1v1.

Projektować pod:

```txt
1v1
2v2
FFA 4 players
bots later
spectators later
```

---

## 16. Input

### 16.1. Desktop

Na desktop:

```txt
WASD / QE       kamera lub ruch zależnie od trybu
Mouse           kamera / celowanie
LPM             potwierdzenie / fire
PPM             anulowanie / alternatywna kamera
Scroll          wybór broni
1-9             szybki wybór broni
Esc             menu
Tab             scoreboard
```

### 16.2. Mobile

Nie implementować w MVP, ale nie blokować.

Docelowo:

```txt
drag to aim
hold to charge
release to fire
large weapon icons
minimal HUD
touch-friendly buttons
```

### 16.3. Warstwa inputu

Core gameplay nie może zależeć od urządzenia wejścia.

Input ma kończyć się wspólnym commandem:

```gdscript
class_name PlayerActionCommand

var player_id: String
var turn_id: int
var weapon_id: int
var aim_direction: Vector3
var shot_power: float
```

---

## 17. UI

### 17.1. MVP UI

Wymagane:

```txt
Main Menu
Guest Login
Create Match
Join Match
Lobby
HUD
Weapon Selector
Turn Timer
Health Bars
End Match Screen
Settings
```

### 17.2. Desktop vs mobile

Nie robić jednego layoutu 1:1 dla desktop i mobile.

Projektować:

```txt
Desktop HUD
Mobile HUD later
shared presenter/view model where useful
```

UI nie może przechowywać jedynego źródła prawdy o stanie meczu.

---

## 18. Rendering i styl

Styl:

```txt
stylized voxel
low-poly
toy war
czytelne kolory
krótkie efekty
lekki humor
```

Nie iść w realizm.

Powody:

- niższy koszt assetów,
- lepsza wydajność,
- lepsza czytelność,
- łatwiejszy mobile port,
- prostsza destrukcja.

### 18.1. PC settings

```txt
większy draw distance
więcej particles
cienie
ambient occlusion jeśli tanie
lepsze tekstury
post-processing opcjonalnie
```

### 18.2. Mobile settings

```txt
mniejszy draw distance
mniej particles
prostsze shadery
brak ciężkiego post-processingu
mniejsze tekstury
mniej dynamicznych świateł
```

---

## 19. Audio

Na MVP:

```txt
weapon fire
explosion
terrain hit
player hit
turn start
turn warning
match win/loss
button click
```

AudioManager jako Autoload jest dopuszczalny.

Nie mieszać audio eventów z core simulation.

Core simulation może emitować eventy typu:

```txt
ExplosionResolved
PlayerDamaged
TurnStarted
```

Client decyduje, jaki dźwięk odtworzyć.

---

## 20. Testy

### 20.1. Co testować

Priorytet testów:

- world position → voxel position,
- voxel position → chunk position,
- local voxel position in chunk,
- bounds checking,
- explosion falloff,
- material resistance,
- terrain delta count,
- turn validation,
- next player selection,
- dead player skipping,
- projectile collision,
- serialization/deserialization messages.

### 20.2. Przykłady testów

Testy wymagane dla core:

```txt
Explosion outside world does not crash
Explosion radius 0 affects only center
Explosion does not modify indestructible material
Dead player does not receive turn
Inactive player action is rejected
Shot power is clamped by server validation
TerrainDelta contains final voxel values
Same seed produces same random weapon spread
```

### 20.3. Zasada

Jeśli Codex zmienia logikę w `scripts/core`, powinien dodać albo zaktualizować testy.

---

## 21. Standardy GDScript

### 21.1. Ogólne

- Pisać prosto.
- Unikać nadmiernej abstrakcji.
- Preferować małe klasy.
- Nie tworzyć „frameworka pod wszystko”.
- Rozdzielać Core / Client / Server.
- Utrzymywać czytelne typowanie.
- Używać typed GDScript tam, gdzie to praktyczne.

### 21.2. Nazewnictwo

```txt
snake_case      zmienne, funkcje, pliki .gd
PascalCase      class_name
SCREAMING_SNAKE_CASE stałe
```

Przykłady:

```gdscript
class_name VoxelWorldData

const CHUNK_SIZE := 16

var material_ids: PackedInt32Array

func get_voxel_material(position: Vector3i) -> int:
    return 0
```

### 21.3. Pliki

Jeden główny koncept na plik.

Dobre:

```txt
voxel_world_data.gd
voxel_chunk_data.gd
terrain_delta.gd
weapon_config.gd
turn_state.gd
```

Złe:

```txt
game_utils_everything.gd
manager.gd
data.gd
misc.gd
```

### 21.4. Typowanie

Preferować:

```gdscript
func apply_damage(amount: int) -> void:
    health = max(0, health - amount)
```

Zamiast:

```gdscript
func apply_damage(amount):
    health -= amount
```

### 21.5. Sygnały

Sygnały są OK dla warstwy client/UI.

Nie używać sygnałów jako głównego mechanizmu core simulation, jeśli utrudnia to testy.

---

## 22. Zasady dla Codexa

### 22.1. Codex ma robić

- Proponować małe, iteracyjne zmiany.
- Utrzymywać Godot jako główny engine.
- Zakładać macOS jako dev machine.
- Utrzymywać desktop-first, mobile-aware.
- Oddzielać core simulation od scen/UI.
- Dodawać testy do core logic.
- Nie ufać klientowi.
- Nie synchronizować pełnego świata po każdej zmianie.
- Trzymać gameplay-critical state po stronie serwera.
- Dopisywać dokumentację dla większych decyzji.
- Używać prostych, jawnych struktur danych.
- Preferować konfigurację przez Resources/JSON zamiast magic numbers.

### 22.2. Codex nie ma robić

- Nie przenosić projektu na Unity/Unreal bez jawnej decyzji.
- Nie dodawać C# jako głównej ścieżki bez ADR.
- Nie dodawać GDExtension przed profilowaniem.
- Nie mieszać UI z core simulation.
- Nie trzymać całego stanu meczu w Node’ach sceny.
- Nie implementować peer-to-peer.
- Nie robić client-authoritative damage.
- Nie tworzyć jednego Node’a per voxel.
- Nie synchronizować całej mapy po eksplozji.
- Nie dodawać marching cubes na MVP.
- Nie dodawać realistycznej fizyki gruzu na MVP.
- Nie robić mobile UI przed grywalnym desktop MVP.
- Nie dodawać losowych addonów bez uzasadnienia.

---

## 23. Środowisko developerskie macOS

### 23.1. Narzędzia

Zalecane:

```bash
brew install git
brew install --cask godot
brew install --cask visual-studio-code
brew install --cask orbstack
```

Opcjonalnie:

```bash
brew install just
brew install jq
brew install ripgrep
```

Jeżeli Godot z Homebrew Cask jest nieaktualny, pobrać aktualną stabilną wersję z oficjalnej strony Godota.

### 23.2. Docker / OrbStack

Do lokalnego backendu:

```txt
OrbStack albo Docker Desktop
```

Preferowane na macOS:

```txt
OrbStack
```

Użycie:

- PostgreSQL,
- Nakama,
- później headless game server,
- lokalne testy integracyjne.

### 23.3. Edytor

Preferowane:

```txt
Godot Editor
VS Code
```

VS Code:
- GDScript extension,
- EditorConfig,
- Markdown lint opcjonalnie.

---

## 24. Docker Compose dla backendu

Docelowo `backend/docker-compose.yml`:

```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: nakama
      POSTGRES_USER: nakama
      POSTGRES_PASSWORD: nakama
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  nakama:
    image: heroiclabs/nakama:latest
    depends_on:
      - postgres
    entrypoint:
      - /bin/sh
      - -ecx
      - >
        /nakama/nakama
        --database.address nakama:nakama@postgres:5432/nakama
        --logger.level DEBUG
        --session.token_expiry_sec 7200
    ports:
      - "7349:7349"
      - "7350:7350"
      - "7351:7351"

volumes:
  postgres_data:
```

Uwaga:

- W produkcji nie używać `latest`.
- W produkcji nie trzymać sekretów w repo.
- Dodać `.env.example`.

---

## 25. Headless server

### 25.1. Założenie

Godot server export ma odpalać match server bez renderingu.

Przykład uruchomienia lokalnego:

```bash
godot --headless --path game
```

Docelowo:

```bash
./terrablast-server --headless
```

### 25.2. Tryby uruchomienia

Projekt powinien wspierać tryby:

```txt
client
server
local-dev
```

Przykład argumentów:

```bash
godot --path game -- --mode client
godot --headless --path game -- --mode server
godot --path game -- --mode local-dev
```

### 25.3. Server entrypoint

W projekcie dodać scenę albo skrypt startowy:

```txt
scenes/server/ServerMain.tscn
scripts/server/server_main.gd
```

Serwer nie powinien ładować:

- UI,
- audio,
- VFX,
- assetów graficznych niepotrzebnych do symulacji.

---

## 26. Roadmap MVP

### Milestone 0 — repo i Godot base

- utworzyć repo,
- utworzyć projekt Godot,
- dodać `CODEX.md`,
- dodać `.gitignore`,
- dodać `README.md`,
- dodać strukturę katalogów,
- dodać pustą scenę main,
- dodać podstawowy autoload `GameConfig`.

### Milestone 1 — core voxel data

- `VoxelWorldData`,
- `VoxelChunkData`,
- `VoxelMaterialConfig`,
- `TerrainDelta`,
- world → voxel conversion,
- voxel → chunk conversion,
- bounds checking,
- unit tests.

### Milestone 2 — renderowanie terenu

- `VoxelWorldNode`,
- `VoxelChunkMeshBuilder`,
- naiwny visible-face meshing,
- `ArrayMesh`,
- dirty chunks,
- debug arena.

### Milestone 3 — destrukcja

- `apply_explosion`,
- material resistance,
- health per voxel,
- terrain delta,
- dirty chunk rebuild,
- debug click-to-explode.

### Milestone 4 — lokalne tury

- 2 lokalnych graczy,
- system tur,
- HP,
- spawn points,
- bazooka,
- granat,
- warunek zwycięstwa.

### Milestone 5 — lokalny server-authoritative prototype

- headless server mode,
- client connects locally,
- player action command,
- server validation,
- server simulation,
- client receives turn result.

### Milestone 6 — Nakama local

- docker compose,
- guest login,
- create/join lobby,
- matchmaking 1v1,
- start match.

### Milestone 7 — desktop builds

- macOS build,
- Linux desktop build,
- Windows build,
- Linux headless server export,
- smoke test.

### Milestone 8 — polish desktop MVP

- 3–5 broni,
- lepszy HUD,
- camera polish,
- VFX,
- audio,
- reconnect basic,
- spectator optional.

### Milestone 9 — Android

- mobile input,
- mobile HUD,
- quality settings,
- Android export,
- performance pass.

### Milestone 10 — iOS

- iOS export,
- provisioning,
- App Store prep,
- iOS performance pass.

---

## 27. Krytyczne ryzyka

### 27.1. Voxel mesh performance

Ryzyko:

```txt
naiwny mesh może być za ciężki
```

Mitigacja:

```txt
chunk size 16
dirty chunks only
visible faces only
greedy meshing later
threaded mesh generation later
GDExtension only after profiling
```

### 27.2. Network desync

Ryzyko:

```txt
klient i serwer mogą widzieć inny teren
```

Mitigacja:

```txt
server authoritative
terrain delta
chunk snapshot recovery
turn_id validation
seed from server
deterministic core where possible
```

### 27.3. Scope creep

Ryzyko:

```txt
projekt urośnie przed grywalnością
```

Mitigacja:

```txt
2 players first
1 arena
3 weapons
blocky destruction
no map editor in MVP
no progression in MVP
no skins in MVP
no mobile before desktop MVP
```

### 27.4. Mobile performance

Ryzyko:

```txt
mobile nie uciągnie PC arena settings
```

Mitigacja:

```txt
quality tiers
small arenas
short draw distance
limited particles
simple shaders
stylized visuals
```

---

## 28. Decyzje zamrożone na start

```txt
Game name: TerraBlast
Engine: Godot 4.x
Language: GDScript
Backend: Nakama
Database: PostgreSQL
Server: Godot headless Linux dedicated server
Terrain: voxel chunks
Destruction: blocky voxel destruction
Gameplay: turn-based
Networking model: server-authoritative
Dev machine: macOS
First targets: macOS / Windows / Linux
Later targets: Android / iOS
```

Zmiana tych decyzji wymaga ADR w:

```txt
docs/decisions/
```

---

## 29. ADR format

Każda większa decyzja:

```md
# ADR-000X: Title

## Status

Accepted / Proposed / Rejected

## Context

Why this decision is needed.

## Decision

What we choose.

## Consequences

Benefits, trade-offs, limitations.

## Alternatives considered

What else was considered.
```

Proponowane ADR-y:

```txt
0001-engine-godot.md
0002-language-gdscript.md
0003-backend-nakama.md
0004-server-authoritative.md
0005-voxel-terrain.md
0006-mobile-later.md
```

---

## 30. Definition of Done

Zmiana jest gotowa, gdy:

- projekt uruchamia się w Godot Editorze na macOS,
- nie łamie aktualnej sceny testowej,
- core logic ma testy, jeśli zmiana dotyczy symulacji,
- nie dodaje nieuzasadnionej zależności,
- nie miesza Client/Server/Core,
- nie zakłada Windows-only ścieżek,
- nie synchronizuje pełnej mapy bez potrzeby,
- nowe configi mają sensowne defaulty,
- większe decyzje są opisane w docs,
- build/server scripts nie zawierają sekretów.

---

## 31. Pierwsze zadania dla Codexa

### Task 1 — repo base

Utwórz strukturę:

```txt
game/
  scenes/
  scripts/
  assets/
  addons/
  tests/
docs/
  decisions/
backend/
tools/
README.md
CODEX.md
.gitignore
.env.example
```

Dodaj `.gitignore` dla Godot.

### Task 2 — Godot project

Utwórz projekt Godot w `game/`.

Dodaj:

```txt
scenes/main/Main.tscn
scripts/shared/config/game_config.gd
```

Opcjonalnie Autoload:

```txt
GameConfig
```

### Task 3 — core voxel models

Dodaj pure GDScript classes:

```txt
voxel_world_data.gd
voxel_chunk_data.gd
voxel_material_config.gd
voxel_position.gd
chunk_position.gd
terrain_delta.gd
```

Nie używać Node3D w core data.

### Task 4 — coordinate tests

Dodaj testy:

```txt
world position -> voxel position
voxel position -> chunk position
voxel position -> local position in chunk
bounds checking
```

### Task 5 — explosion core

Dodaj:

```txt
voxel_destruction.gd
apply_explosion(center, radius, damage) -> Array[TerrainDelta]
```

Z testami.

### Task 6 — terrain renderer

Dodaj:

```txt
VoxelWorldNode
VoxelChunkMeshBuilder
```

Na start naiwny visible-face meshing przez `ArrayMesh`.

### Task 7 — debug scene

Dodaj scenę debug:

```txt
scenes/debug/VoxelDebug.tscn
```

Wymagania:

- generuje prostą arenę,
- pokazuje voxele jako mesh chunków,
- pozwala odpalić eksplozję w wybranym miejscu,
- rebuilduje tylko dirty chunki.

---

## 32. Hasło projektu

```txt
TerraBlast — turn-based voxel warfare across destructible worlds.
```

Opis po polsku:

```txt
TerraBlast to turowa gra online 3D, w której gracze walczą na zniszczalnych voxelowych arenach, używając broni artyleryjskiej i taktycznej destrukcji terenu.
```

---

## 33. Zasada nadrzędna

Najpierw grywalność.

Nie optymalizować, nie rozbudowywać i nie dekorować przed osiągnięciem pętli:

```txt
gracz celuje
gracz strzela
pocisk leci
teren wybucha
postać dostaje obrażenia
tura przechodzi dalej
ktoś wygrywa
```
