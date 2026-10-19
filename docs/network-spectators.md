# Spectating i czat lobby

Serwer pozostaje autorytatywny. Obserwator nie zajmuje miejsca gracza, nie ma własnej postaci ani inventory i nie bierze udziału w Ready/rematch. Jego wyjście nie pauzuje meczu i nie kasuje głosów graczy.

Uruchom lokalnie:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -- --mode server --port 19170 --players 2 --lobby --spectators 2 --lobby-chat --print-roster
/Applications/Godot.app/Contents/MacOS/Godot --path game -- --mode client --host 127.0.0.1 --port 19170 --role spectator
```

W F2 wybierz Player albo Spectator przed Connect. Rola dotyczy następnego połączenia; Retry zachowuje rolę istniejącej sesji. F7 pokazuje osobno graczy i widzów, nazwę widza oraz wybór gracza śledzonego kamerą. Free camera wyłącza śledzenie. Po utracie połączenia Retry odzyskuje tożsamość przez czas rezerwacji. Potwierdzone Leave wysyła zwolnienie miejsca i usuwa lokalny token; socket pozostaje przez maksymalnie300ms, aby dostarczyć reliable leave po zamknięciu sceny. Przy awarii sieci obowiązuje zwykły grace i serwer sam zwalnia rezerwację.

Domyślnie `--spectators 0` i wyłączony czat. Limit widzów to0–6, graczy2–10. Rezerwowany, rozłączony widz nadal zajmuje miejsce do wygaśnięcia grace (`--reservation-seconds`, domyślnie30). Token widza nie daje dostępu do slotu gracza. Zmiana roli lub endpointu usuwa poprzedni token i wymaga nowego połączenia.

Późny widz otrzymuje zamrożony snapshot świata i uporządkowane zmiany powstałe w trakcie transferu. Używa wspólnych limitów `--snapshot-chunks` i `--snapshot-bytes`; liczba widzów nie zwiększa budżetu wysyłki na klatkę. Luki rewizji powodują resync. Rematch ustalają wyłącznie gracze, a widzowie dostają snapshot nowej generation.

## Czat

`--lobby-chat` włącza tekst wspólny dla autoryzowanych graczy i widzów. Enter lub Send wysyła wiadomość; pole czyści dopiero echo serwera. Błąd, timeout i rate limit zachowują draft. Nazwa i rola autora pochodzą z ewidencji serwera. Czat używa zwykłego tekstu: `[url]`, znaczniki i nawiasy nie stają się linkami ani markup.

Limity:1–256znaków, maksymalnie1024bajtyUTF8, bez znaków sterujących. Jeden autor ma4wiadomości/10s, cały serwer32/10s. Historia zawiera najnowsze maksymalnie64wiadomości i maksymalnie64KiB zakodowanej listy. Późny join i reconnect odtwarzają aktualny tail. Rematch czyści historię do nowej generation. Nonce ogranicza duplikaty; client nie nadaje autora ani numeru kolejnego. Luka czatu odtwarza tylko historię, bez ponownej synchronizacji terenu.

## Diagnostyka i zgodność

`--print-roster` wypisuje jeden JSON roster na starcie. `--server-report /tmp/terrablast-server.json` zapisuje podczas graceful shutdown raport obejmujący roster i transfery. API `participant_roster()` i `diagnostic_roster_json()` są lokalnymi hookami; nie otwierają zdalnego panelu administracji. Raporty nie zawierają tokenów, adresów klientów ani treści czatu.

Wersja protokołu pozostaje2. Brak `role` w hello oznacza gracza; starzy gracze zachowują dotychczasowe sloty, snapshoty i quorum. `spectators_v1` i `chat_v1` są opcjonalnymi rozszerzeniami. Nowy widz wymaga potwierdzenia roli przez serwer: stary serwer nie obsługuje obserwacji, a klient odrzuca próbę przydzielenia mu slotu gracza. Na dawnym serwerze taka próba może pozostawić krótką zwykłą rezerwację gracza do wygaśnięcia grace.

To role lokalnego transportu ENet. Nie są uwierzytelnieniem użytkownika Nakama. Lobby Nakama nadal nie alokuje automatycznie serwera gameplay ani nie przesyła tych wiadomości czatu.

## Testy

Nowe testy integracyjne przydzielają wolny portUDP przez `PacketPeerUDP.bind(0,"127.0.0.1")`. Nie używają stałego portu i wymagają dostępu do localhost.

```sh
python3 tools/run_tests.py --include '*network*' --report /tmp/terrablast-network-report.json --timeout 90
python3 tools/run_network_process_test.py --port 0 --timeout 45
```

Testy sprawdzają dwóch graczy i późnego widza, strzał w czasie wolnego snapshotu, checksum i catchup, pełne miejsca, reconnect/leave/expiry, read-only guard, rematch oraz shutdown. Oddzielny czatUDP pokrywa legacy hello, przypisanie autora, spam, history/live race, reconnect i wyłączoną usługę. UI test sprawdza rolę, disabled quorum, nazwę, follow intent, focus tekstu i literalne wyświetlanie wiadomości.
