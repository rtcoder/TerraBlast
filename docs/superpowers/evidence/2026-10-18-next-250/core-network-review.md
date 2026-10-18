# Independent review: core50 + network50

Reviewed manifest TB-432–481 and TB-482–531 against implementation, with emphasis on nine-map generation, spawn selection/loadouts, legacy simulation compatibility, endpoint/profile validation, Nakama async cancellation, frozen snapshot/catchup queues and budgets.

## Fixed findings

1. Nakama WebSocket send failure left socket, unrelated pending requests and matchmaking state alive (TB-512). Fixed request and ping-response send paths to close/invalidate session before exposing error. Added null check in receive loop because message handling can now close socket. Small I/O seam _send_socket_text permits deterministic injected failure. Regression observed 3 failures before fix; clean pass afterward.

2. Server sent_bytes/catchup/snapshot frame budgets omitted the version envelope added only in _send_packet (TB-523/526). Central _wire_size computes the actual serialized envelope without mutating caller data. Regression sends two messages whose unenveloped size exactly fills 65536 bytes; old code sent both although wire bytes exceeded budget. Tests observed both diagnostic and budget failures, then clean pass.

## Evidence

New game/tests/unit/network_review250_tests.gd: send-failure socket/request cleanup, generation cancellation, visible error after cleanup, actual wire byte counters, exact-boundary frame budget, pending HTTP login cancellation/no stale token.

Clean elevated targeted suites:
- network_review250_tests.gd
- network_backend250_tests.gd
- network_backend_next_tests.gd (frozen snapshot concurrent mutation, catchup convergence, stale transfers, overflow replacement, abort on send failure, token bucket)
- core250_tests.gd (all9 arenas, counts2–10, classic/artillery loadouts, shot/reset)
- core250_edges_tests.gd
- trajectory250_tests.gd
- core_tests.gd
- bot_oct16_tests.gd

Legacy core_replay_oct16_tests.gd run separately; result reported to parent after completion.
No new core-domain defects requiring a code change were found in reviewed scope. Full cross-domain suite and real Nakama integration remain parent-owned acceptance work. No git/YouTrack changes.
