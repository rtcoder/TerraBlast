# Network TB-632–681

50 implementation/evidence rows: `docs/superpowers/plans/2026-10-19-next-250-network-evidence.json`.

- `network-regressions.json`:13/13passes, including existing network50, Oct17 multiplayer lobby/rematch, backend queue tests and separate-process server+two clients.
- `network-new-suites.json`:6/6passes, new spectator/chat models, spectatorUDP, chatUDP, full VoxelDebug sceneUDP and UI.
- `network-review-cases.json`:2/2passes after final changes, explicitly includes a real unauthenticated pending peer receiving zero chat and latest spectator panel.
- `network-cli.json`:6/6expected exit statuses plus parsed server report; ephemeral port, no deployment.
- `network-native720.png`, `network-native125.png`:native Metal4 viewport from real two-player+spectatorUDP scene,1280x720. Visual inspection confirms role/counters/name/follow, literal `[url]`, readable history, scroll and accessible Send/Disconnect/Close at125%. Native run ended `network_scene19_next:0 failures`.

All sockets used localhost and dynamically allocated ports. Tests require permission to bind localhost outside the restricted filesystem/network sandbox. The first restricted attempt could not bind; subsequent approved local executions passed. No internet account, deployment or new Nakama dependency.

Important behavior tested: legacy hello still admits a player; a spectator never changes player count/quorum, damages terrain or sends gameplay intent. A shot during1chunk/frame snapshot converges by checksum and revision. Capacity, retained identity/name, explicit leave, expiry, resync, rematch and shutdown converge over realUDP. Reliable leave survives destruction of the source scene using a bounded300ms socket owner. Chat validates length/UTF8/control characters/author/generation, limits memory and rate, rejects duplicates, orders snapshot history+live events, repairs sequence gaps without terrain rebuild and clears on rematch.

Scope limitation: observing a pre-extension server is unsupported. A new client rejects a player-role response to its spectator request; the older server may retain its ordinary player reservation until its grace expires. Documented in `docs/network-spectators.md`.

Final isolation correction: the full-scene test now injects a fresh ConnectionProfiles store at a unique /private/tmp/tb19-network-scene-profiles-PID.json before starting networking, asserts that it is not the normal user:// profile path, and removes it after the test. This applies to both headless and native --smoke paths. Rerun network_scene19_next_tests passed6.102s; see network-scene-isolation.json and network-scene-isolation.out.
