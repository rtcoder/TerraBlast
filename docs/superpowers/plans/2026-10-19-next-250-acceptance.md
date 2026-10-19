# Acceptance — TB-532–TB-781

250 new YouTrack issues, implemented in five groups of 50. Baseline: `0e274a29337c35fd1e574a72cbbdb9091d322b54`. Task descriptions, acceptance criteria and exact IDs: [manifest](2026-10-19-next-250-tasks.json).

| IDs | Delivered behavior | Per-ID evidence |
| --- | --- | --- |
| TB-532–581 | Native Arena Workshop, transactional document edits, undo/redo, TOML, voxel preview, private playtests and live-context restoration | [Workshop 50](../evidence/2026-10-19-next-250/workshop-evidence.json) |
| TB-582–631 | Offline leagues, return legs, knockout byes, fixtures, standings, correction, save/resume and actual match UI | [Competition 50](../evidence/2026-10-19-next-250/competition-evidence.json) |
| TB-632–681 | Role negotiation, up to six spectators, read-only gameplay, reconnect/reservations, bounded chat, roster diagnostics and native controls | [Network 50](../evidence/2026-10-19-next-250/network-evidence.json) |
| TB-682–731 | Replay notebooks, filtered navigation, verified clips, detailed comparison, bounded ZIP bundles, native inspector/library UI and three CLI modes | [Studio 50](../evidence/2026-10-19-next-250/studio-evidence.json) |
| TB-732–781 | Bounded scenario matrices, deterministic planning, workers/deadlines/cancellation, recording/verification, checksummed resume, reports and comparisons | [Scenarios 50](../evidence/2026-10-19-next-250/scenarios-evidence.json) |

All 250 manifest IDs are unique and match exactly 250 evidence records. Task evidence identifies implementation and relevant assertions rather than treating issue creation as implementation.

## Verification

- Full repository run with `RUN_NAKAMA_TESTS=1 RUN_RENDER_TESTS=1`: **71/71 passed**, 296.35 seconds summed execution time. [Report and retained logs](../evidence/2026-10-19-next-250/full-report.json).
- Targeted post-review verification: **12/12 passed**, covering Workshop, competition, Studio, bundle, scenario and CLI changes. [Report and retained logs](../evidence/2026-10-19-next-250/review-report.json).
- Final author checks also cover test isolation and additional malformed ZIP/notebook inputs: Workshop 140 assertions; Studio 291 assertions plus four real-engine CLI tests. Native viewport captures at 800×600/HUD125%, real UDP spectator/chat at 720p, and actual macOS Workshop close/discard interaction are retained in the [evidence directory](../evidence/2026-10-19-next-250/).
- Godot 4.6.2 editor import completed without errors; script UIDs generated. `git diff --check` passed.
- Scenario verification includes two real simulations with replay verification and deterministic comparison, tampered-resume artifacts, crashes, oversized output, timeouts and SIGTERM cancellation of parallel child process groups.

## Review corrections

Independent reviewers reproduced and verified fixes for: hotseat handoff leaking into Workshop; debug gravity changing retained match state; competition draft resume and abandon leaving orphan gameplay; impossible draw attempt ordering; filtered note navigation editing a hidden note; Unicode notebooks exceeding their own read limit; stale clip exports after marker edits; resume trusting inline summary over its artifact; new failing comparison cases being ignored; successful recovery compared against missing failed-baseline state; short-lived processes bypassing log limits; and huge numeric metrics escaping structured validation.

[Network/competition review](../evidence/2026-10-19-next-250/network-review-of-competition.md) and [resolution verification](../evidence/2026-10-19-next-250/network-review-resolution.md) preserve the findings and repro outcomes. The same-dimension terrain-origin observation is a documented model limitation, not a claimed validation guarantee.

## Scope and limits

Competition saves validate the event, active attempt, canonical rules/weapons, player configuration and arena dimensions. A legitimately mutated terrain snapshot cannot prove which same-sized arena it originated from; saves are not authenticated tournament records. Scenario reports likewise provide local integrity checks, not signed provenance. Spectator support defaults off; a legacy server cannot provide the new spectator role. These changes preserve existing replay/session codecs and server authority.

No platform release export or production deployment is part of this batch. Native UI was tested on macOS; Linux headless CI is the delivery gate after push. The final delivery response records the resulting commit, CI run and verified YouTrack states.
