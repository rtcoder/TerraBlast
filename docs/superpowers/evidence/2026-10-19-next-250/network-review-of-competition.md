# Independent review: competition + shared session guards

Status: actionable findings fixed and independently rechecked; see `network-review-resolution.md`. The text below records the original review.

Reviewed current working files against `docs/superpowers/plans/2026-10-19-next-250-competition.md` and accepted250-design. No competition/product edits made during review. Reproduction script `/private/tmp/tb19_competition_review_probe.gd`, output `/private/tmp/tb19-competition-review-probe.log` (Godot4.6.2, real Factory/Session/VoxelDebug).

## P1 — Draft resume leaves an orphan fixture running

`game/scripts/client/competition/competition_controller.gd:198` (`resume`, empty loaded.match branch).

When an active competition/context already exists and the saved file is a valid draft or completed event with no active match, resume clears fixture_runner/token but leaves scene.runner on the previous fixture and retains live. Closing the panel unpauses the old fixture even though event.active is empty and update will no longer recognize its result. The scene remains blocked from other workflows because live is nonempty. This is a reachable workflow through Resume saved and its confirmation; it does not require malformed data.

Reproduction: launch real fixture; save a valid separate draft into the configured competition path; call resume(); close(). Actual output:

```
draft_resume_ok=true orphan_runner_kept=true fixture_runner_null=true active_empty=true game_unpaused=true live_context_kept=true
```

Required: on successful replacement by a no-active save, restore the retained live runner/context (without applying abandoned old-event mutations to the newly loaded event), or keep the hub modal until another fixture/explicit return is chosen. Add real-scene coverage for active→draft and active→completed resume, not only active→active.

## Accepted limitation — Mutable snapshots do not prove same-size arena provenance

`game/scripts/core/competition/competition_store.gd:33`–42.

The decoder compares size/rules/weapons/player IDs/team IDs but not arena provenance. `two_islands` and `twin_forts` both have96×24×96 and the same preset roster, so a normal Session.encode of a fresh twin_forts runner is accepted for a fixture configured as two_islands. The earlier plan text requested map binding, but root confirmed that the final contract explicitly narrows this to canonical rules/weapons/dimensions, because mutable snapshots cannot prove the initial arena. This is therefore an accepted limitation, not a blocking finding. The `dimensions` test intentionally checks dimensions rather than terrain provenance.

Actual probe output:

```
same_dimensions_wrong_map_accepted=true configured=two_islands actual=twin_forts
```

Follow-up: document the narrowed guarantee in the accepted spec and user-facing save description. A metadata hash by itself does not prove current terrain came from that arena; do not add a check that rejects valid changed terrain. Root owns this clarification.

## P2 — Restore accepts a draw from the future relative to active attempt

`game/scripts/core/competition/competition_event.gd:113`–122.

The active token is validated before last_draw, but last_draw only checks duplicate attempt and final next_attempt. A state with active.attempt2, last_draw.attempt3 and next_attempt4 is accepted even though record() must clear active to produce a draw, so attempt3 cannot have completed while attempt2 remains active. Runtime-generated snapshots always have active newer than the stored last draw.

Actual output:

```
impossible_future_draw_accepted=true active_attempt=2 future_draw_attempt=3
```

Required: if active is present, reject last_draw.attempt >= active.attempt; retain valid older last_draw across abandon/relaunch, including gaps in attempts. Add forged-order store/event tests that preserve the previous valid object on rejection.

## Shared guards inspected

Normal menu new-match/restart, begin_training, continue_autosave, next_round, online connection, archive entry and debug gravity are guarded during retained competition context. Surrender remains available, as required. Internal launch uses _internal_launch to bypass its own guard, and normal return restores runner/recorder/options/velocities/series/config/epoch/handoff plus last_live_runner/last_turn. The existing integration proves original hash and series identity restoration.

`_replace_local_runner` itself is unguarded despite the plan requesting an internal-launch guard there; current visible workflow entry points inspected are guarded. `_inspect_recording` also has no direct special-session guard; current open/load call sites use can_archive. Consider defense at these two central replacement entry points if adding more call sites, but this review does not present an additional confirmed user-path bypass.
