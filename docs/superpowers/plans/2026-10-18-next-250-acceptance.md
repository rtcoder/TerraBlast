# TB-282–TB-531: implementation and verification

Scope: 250 tasks, five groups of 50. All250 YouTrack issues were set to Done and read back to verify their state; [receipt](../evidence/2026-10-18-next-250/youtrack-done.json). Exact requirements and YouTrack IDs are in [the task manifest](2026-10-18-next-250-tasks.json). No gameplay authority or archive-format migration was introduced.

| Group | YouTrack range | Evidence |
| --- | --- | --- |
| Delivery tools | TB-282–TB-331 | [50 records](2026-10-18-next-250-tools-evidence.json) |
| Archive library and replay analysis | TB-332–TB-381 | [50 records](2026-10-18-next-250-archives-evidence.json) |
| Local setup, training and accessibility | TB-382–TB-431 | [50 records](2026-10-18-next-250-client-evidence.json) |
| Maps, terrain and trajectories | TB-432–TB-481 | [50 records](2026-10-18-next-250-core-evidence.json) |
| Network lifecycle and profiles | TB-482–TB-531 | [50 records](2026-10-18-next-250-network-evidence.json) |

## Delivered behavior

- Nine registered arenas, including six new arenas; each supports 2–10 players. Bounded TOML parsing/build validation, map analysis/serialization, material queries, trajectory analysis and an isolated artillery loadout.
- Named local configurations, human-team selection, match confirmations, rotating autosaves and best-of series. Eleven training lessons run on a private checkpoint, with retry/return, coach hints and independent progress. Accessibility preferences affect presentation and input only.
- Searchable, sortable, paginated archive library with favorites, file dialogs, duplicate detection and diagnostics. Replay analysis has private state, action budgets, cancellation, bookmarks, JSON/CSV output and fingerprint-checked cursor restoration. Legacy v1/v2 codecs and exact replay hashes remain enforced.
- Connection profiles and guest identity, bounded authentication/websocket callbacks, frozen queued snapshots followed by ordered catch-up, lifecycle metrics and graceful server reports.
- Selected/rerun/fail-fast test execution, incremental JSON/JUnit/JSONL reports, environment checks, release planning/export/manifest verification/deterministic packaging, constrained Docker context and checksum-verified CI engine download.

## Review and corrections

Independent reviews covered core/network, tools/archive APIs, and archive UI. Confirmed issues were reproduced and fixed:

- Nakama send failures left websocket/pending requests alive.
- Server byte budgets omitted the protocol envelope.
- Release output directories and doctor reports could follow symlink aliases; nested manifest files escaped verification.
- Replay terrain analysis observed a mutated PackedInt32Array instead of the pre-shot material snapshot.
- Missing Godot stopped the runner without the required failure report.
- Archive diagnostics missed malformed payloads and counted them as valid.
- UI double-click analysis, raw error messages and test filter isolation needed correction.
- Caption deduplication survived a new match; configuration UI unnecessarily reparsed maps each frame.

The final tests include 40-shot replay aggregation beyond the 32-entry match history, legacy analysis, surrender eliminations, invalid-action diagnostics, real UDP snapshot/catch-up, local Nakama, process-tree timeout cleanup, symlink containment and actual scene/modal flows.

## Native UI evidence

800×600, HUD125%; controls remain reachable through vertical scrolling:

- [Library](../evidence/2026-10-18-next-250/library-800x600.png)
- [Replay inspector](../evidence/2026-10-18-next-250/replay-800x600.png)
- [File dialog](../evidence/2026-10-18-next-250/file-dialog-800x600.png)
- [Training](../evidence/2026-10-18-next-250/training-800x600.png)

## Verification and limits

**53/53 checks passed after targeted retry**, including real UDP, local Nakama and native render. The final full run passed52/53; restoring the documented map example repaired the remaining help-text assertion, and `--rerun-failed` passed1/1. See [verification summary](../evidence/2026-10-18-next-250/verification-summary.json), [full report](../evidence/2026-10-18-next-250/full-suite.json) and [retry](../evidence/2026-10-18-next-250/retry.json). Editor import, Python compilation and whitespace validation passed. The first integration run passed 47/48 checks; its missing-engine report regression was repaired and retested before the final run. Review-specific tests were added to automatic discovery.

Godot4.6.2, Python3.14.7, nine map audits, 133 valid UID sidecars, export-preset validation and the local Nakama health check passed. Export templates are not installed: actual macOS/Windows/Linux binaries and the release Docker container were not built or executed. Export invocation/failure handling, manifests, PCK retention, checksums and deterministic packaging were verified with isolated fake exporters. Hosted CI is separate from local evidence.

One initial legacy UI test wrote a new replay cursor to the default library preferences before its path was isolated. No archives or live match data were changed; existing preferences were not deleted. Subsequent UI runs use separate temporary preferences and do not modify that file.
