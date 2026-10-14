# Local Nakama / OrbStack

Start isolated development services:

```sh
docker compose -f backend/docker-compose.yml up -d --wait
```

Pinned versions: Nakama 3.37.0, PostgreSQL 17.7. Migrations run before server startup; Postgres readiness gates Nakama. Ports bind to localhost only. No host PostgreSQL port is used. Console: http://127.0.0.1:7351 (admin / terrablast-local-only). Server key: terrablast-dev-key. These are public local-development credentials, never deploy them.

In the game press F2. Guest login opens a Nakama WebSocket. Create a lobby and copy its ID to the second player, or choose Find opponent on both clients. Matchmaker pairs exactly two users; both join the matched lobby.

The normal guest ID is saved under Godot user data. For two clients on the same machine use different `--guest-id terrablast-player-one` / `--guest-id terrablast-player-two` arguments.

Gameplay server allocation is manual in this prototype: start one Godot server and connect both lobby members to its address. Nakama does not simulate gameplay. ENet peer slots are local-dev identities, not verified Nakama identities; this prototype is not a public authenticated game service.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -- --mode server
/Applications/Godot.app/Contents/MacOS/Godot --path game -- --mode client --guest-id terrablast-player-one
/Applications/Godot.app/Contents/MacOS/Godot --path game -- --mode client --guest-id terrablast-player-two
```

Test real guest auth, lobby create/join and matchmaking:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /tmp/terrablast-nakama.log --path game --script tests/integration/nakama_smoke.gd
```

Stop without deleting saved development accounts:

```sh
docker compose -f backend/docker-compose.yml stop
```

References: [official Docker setup](https://heroiclabs.com/docs/nakama/getting-started/install/docker/), [realtime protocol](https://github.com/heroiclabs/nakama-common/blob/master/rtapi/realtime.proto).
