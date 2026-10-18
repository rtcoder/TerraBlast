# Network 50 implementation handoff (TB-482–TB-531)

All 50 manifest behaviors implemented in owned files. No Git/YouTrack operations performed.

## Features
- ConnectionProfiles: strict endpoints/IDs, 20-record/64KiB versioned JSON, immutable snapshots, CRUD, atomic persistence, last successful endpoint without credentials.
- GuestIdentity bounded stable load/create and atomic repair, failure surfaced.
- BackendMenu: favorite CRUD/confirmation, last-success selection, editable Nakama endpoint, explicit copy actions, gameplay status/retry hooks, bounded scroll, state-aware buttons, cancellation generation guards.
- Nakama: canceled/superseded HTTP cannot commit stale token, body/token limits, URL/ID validation, bounded inbound loop, active-CID correlation/cap, nested response validation, send failure propagation.
- Lobby: authoritative ready/name/rematch ack, duplicate intent suppression, generation/rejection/timeout release, draft preservation, disconnect confirmation, sync/RTT/retry presentation.
- MatchClient: pre-close endpoint validation, source peer check, control envelope validation, bounded/coalesced recovery, independent overall/idle watchdog, stale transfer ignore, RTT expiry, immutable safe status snapshot, deliberate leave vs reconnect token lifetime.
- MatchServer: validated runtime options, continuous token buckets, receive byte/frame cap, round-robin lazy chunk serialization over frozen terrain, immutable begin/end and ordered catchup state/result, bounded backlog replacement, send error abort, fatal hello cleanup, safe diagnostics.
- ServerMain: validated CLI options supplied by root, shutdown deadline/native-close hook, graceful transport close, atomic explicit JSON report, exit failure on report error. Reject report inside project or through symlink components.

## Verification completed
- tests/unit/network_backend250_tests.gd: 0 failures.
- tests/integration/backend_profiles_next_tests.gd: 0 failures; injected stalled HTTP + superseded completion tests (no live backend required).
- tests/integration/network_backend_next_tests.gd: 0 failures; simultaneous shot while frozen snapshot pending, ordered catchup converges terrain checksum, stale transfer ignore, hard queue bounds, failed send abort, continuous rate refill, lobby ack/timeout/confirmation.
- Existing network_oct17_next_tests.gd: 0 failures, real four-peer UDP on ephemeral port.
- Existing network50_tests.gd: 0 failures, temp copy replacing fixed port with ephemeral port; fixture active-token changed to actual legal hex64 token in repository.
- Existing network_next_tests.gd and network_smoke.gd: 0 failures, temp copies with ephemeral ports.
- Existing nakama50_tests.gd: 0 failures against local backend.
- Existing client_oct17_next_tests.gd: 0 failures, real scene flow, temp copy on isolated ephemeral port. Persisted profile fixture now injects unique /private/tmp store, cleans up.
- Actual server subprocess --snapshot-chunks 2 --reservation-seconds 15 --shutdown-after 0.2 --server-report /private/tmp/tb250-server-report.json: exit0, JSON shutdown_reason deadline, shutting_down true, no secrets.
- git diff --check for owned files: clean.

Sandboxed Godot emits its known macOS certificate-store warning; network tests were run with approved localhost access and did not emit script errors. Full-suite and native/render QA belong to root integration.

## Integration hooks
Root/client agent has integrated retry_requested, present_game_connection, record_connection_success (only first synchronized), LobbyPanel present_connection/operation_rejected, MatchClient rejected + metrics_changed. Existing connect_game(host)/selected_port() preserved. Explicit leave clears token; ordinary close/retry preserves it.

## Material behavior details
- Snapshot byte budget permits one indivisible protocol packet even if that packet exceeds configured byte threshold; subsequent packets wait. Hard chunk count/frame and protocol packet size bound remain. No splitting/changed wire protocol.
- Snapshot catchup cap128 messages/8MiB supersedes with newest frozen snapshot instead of unbounded allocation.
- Server report path must be absolute .json with existing parent outside project and no symlink components. Use resolved /private/tmp rather than /tmp on macOS.
- Native close hook plus explicit --shutdown-after are supported; no claim of a custom POSIX SIGTERM bridge.
- No automatic networking retries/background backend connections introduced; gameplay authority remains entirely server-side.
