## 1. Checkpoint and in-place product migration

- [x] 1.1 Confirm checkpoint `7c4b0b5` and preserve uncommitted work; create an implementation branch and record baseline debug/release test and performance results before changes.
- [x] 1.2 RED: Add configuration contracts for one Space Visualizer product, consistent executable/bundle/module naming, required purpose strings, and no network/microphone/screen-capture capabilities.
- [x] 1.3 GREEN: Rename the existing source and test targets, product, plist, entitlements, and user-facing identity in place; use `Space Visualizer.app` and `com.spacevisualizer.app` without creating a parallel application.
- [x] 1.4 REFACTOR: Update build/verification scripts and README, document renewed TCC prompts and checkpoint rollback, and verify the renamed app builds with both debug and release tests passing.

## 2. Deterministic playback-following coordinator

- [x] 2.1 RED: Add fake monotonic scheduler, playback query, visibility events, permissions, session factory, worker, and renderer resources; test onboarding/waiting/starting/visualizing/silent/suspended/blocked/failed/terminated invariants.
- [x] 2.2 GREEN: Implement a single lifecycle coordinator with generation-tagged asynchronous work and serialized non-UI resource ownership.
- [x] 2.3 RED: Test initial playback check, exact five-second idle scheduling, no overlapping checks or catch-up backlog, idle timer cancellation on playing, and exactly one active session.
- [x] 2.4 GREEN: Implement initial and five-second idle discovery and the transition to automatic capture without manual test controls.
- [x] 2.5 RED: Test active pause/stop, track transition, Music quit, and fresh silent samples; prove the idle timer stays canceled while active and silent passages do not trigger false pause handling.
- [x] 2.6 GREEN: Implement a separate two-second active watchdog and coalesced optional notification hints, with one query in flight and return to idle only after teardown.
- [x] 2.7 REFACTOR: Consolidate scheduler/observer ownership and assert bounded handles across repeated start/stop transitions; retain deterministic passing tests.

## 3. Bounded Music observation and permission onboarding

- [x] 3.1 RED: Test absent Music without launching it; independently readable player state when no current track exists; optional track fields; malformed results; denied, timed-out, canceled, and obsolete responses.
- [x] 3.2 GREEN: Implement a local off-main-thread query adapter with fixed script input, bounded output, one-second timeout, cancellation, and no shell interpolation; query player state independently from current-track properties.
- [ ] 3.3 Verify the installed Music dictionary and optional playback notification behavior on the target Mac; retain the watchdog if notifications lack a reliable supported contract, and document actual coverage.
- [x] 3.4 RED: Add onboarding/retry contracts proving no permission prompt before consent, no repeated prompts after denial, safe permission revocation, and automatic following after previously enabled consent.
- [x] 3.5 GREEN: Implement first-run explanations, enable action, settings/retry controls, and persisted consent intent without treating preferences as current TCC authorization.
- [ ] 3.6 Verify Automation attribution and system-audio prompts from the signed renamed bundle, including the local query helper; stop implementation of that adapter if attribution cannot meet the consent contract.
- [x] 3.7 REFACTOR: Remove the synchronous UI polling path, cancel helper processes on teardown, and verify no timer or event-log growth when Music is unavailable.

## 4. Production capture ownership and recovery

- [x] 4.1 RED: Add lifecycle tests for close/quit during pending startup, repeated stop, sleep/wake, stale completions, failure during partial resource creation, and delayed teardown; assert no playback mutation.
- [x] 4.2 GREEN: Connect the direct Music-only tap session to coordinator ownership; serialize start/stop away from the main thread and clean obsolete resources before discarding late results.
- [x] 4.3 RED: Test source ambiguity, route removal/change, format/channel/sample-rate changes, generation invalidation, one-second no-input status, and five-second no-input teardown into explicit retry.
- [x] 4.4 GREEN: Implement route/format monitoring, explicit source resolution, missing-input deadlines, and bounded single-session reconnect behavior; never fall back to all-system audio.
- [x] 4.5 REFACTOR: Remove dead HAL AudioUnit capture code; audit Core Foundation ownership, callback buffer bounds, stop/destroy errors, nonmuting configuration, and idempotence against the installed SDK.

## 5. Freshness, concurrency, and latency

- [x] 5.1 RED: Test atomic PCM/timestamp/format handoff, overflow/discontinuity behavior, overlapping windows, slow-worker backlog skipping, and generation reset without concurrent stale publication.
- [x] 5.2 GREEN: Harden the bounded callback-to-worker handoff and overwrite-only mailbox; prohibit callback allocations, unbounded waits, file I/O, and per-frame main-queue work accumulation.
- [x] 5.3 RED: Test real sample-age expiration at 250 ms, host-tick conversion, time-based attack/release across differing analysis cadences, silent settling, and reset behavior.
- [x] 5.4 GREEN: Base freshness on actual input timestamps, implement time-based smoothing without a delayed interpolation queue, and clear stale visuals on the display side.
- [x] 5.5 RED: Extend deterministic FFT/level tests across 48/96/192 kHz, supported channel layouts, opposite-phase stereo, and unsupported formats; keep captured PCM format distinct from source-quality labels.
- [x] 5.6 GREEN: Correct analyzer format/level handling required by those tests, preserve frequency resolution and overlapping windows, and report unsupported capture formats honestly.
- [x] 5.7 REFACTOR: Add bounded local timing/resource instrumentation for callback age, analysis duration, mailbox age, worker/task counts, and memory; run available race/sanitizer checks and document native-only gaps.

## 6. Full-canvas product experience and display lifecycle

- [x] 6.1 RED: Add UI/presentation contracts for automatic waiting-to-live transitions, fullscreen, permission recovery, optional diagnostics, unknown source quality, and absence of required Start capture or test-phase controls.
- [x] 6.2 GREEN: Build the Space Visualizer full-canvas shell using existing rings, spheres, shading, and trails; move detailed diagnostics behind an explicit action with audio-free export.
- [x] 6.3 RED: Test 120 Hz preference with system-selected cadence, 60 Hz fallback, display migration, deduplicated visual publication, and diagnostic updates capped at four per second.
- [x] 6.4 GREEN: Isolate the renderer from controls/status updates and bind its display link to active visible playback; preserve latest-result-only consumption and the preferred per-segment appearance.
- [x] 6.5 RED: Test Reduce Motion, keyboard/accessibility controls, focus switching versus visibility loss, close/reopen, minimize/hide/occlusion, and terminal quit cancellation.
- [x] 6.6 GREEN: Implement explicit single-window visibility and sleep/wake hooks; stop expensive work when hidden, all work on close/quit, and revalidate before resuming; keep Reduce Motion geometry static.
- [x] 6.7 REFACTOR: Remove redundant scene timers and observers, retain immutable bounded geometry caches, and verify diagnostics cannot recreate the prior whole-window high-frequency update problem.

## 7. Native acceptance and release handoff

- [x] 7.1 Run complete debug and optimized release unit/configuration/UI tests on the target Mac; record failures rather than treating authored tests as passed.
- [ ] 7.2 Verify initial launch with Music absent, paused, and already playing; automatic start within the idle-check interval; pause/stop detection within five seconds; denied/revoked permissions; and explicit retry after failure.
- [ ] 7.3 Verify unprotected control, streamed subscription, downloaded subscription, and available AirPlay routes independently; record route, format, audibility, freshness, limitations, and unchanged Music playback.
- [ ] 7.4 Run 20 play/pause cycles plus close/reopen, focus switching, minimize/hide, sleep/wake, route/format changes, and quit during startup; inspect that temporary taps/devices, workers, display links, helpers, and pending queries return to baseline.
- [ ] 7.5 Measure a 15-minute release run for monotonic memory/resource growth, a 60-second idle mean below 2 percent of one core, and a five-minute 48 kHz stereo active mean below 50 percent on the recorded M5 Pro/display/window configuration; profile and fix failures before declaring readiness.
- [ ] 7.6 Measure p95 main-thread frame work against the selected display interval and interaction stalls against 100 ms; compare p50/p95 sample/worker/display timing and transient-fixture alignment with the checkpoint, with no accumulating visual lag or forbidden audio/screen recording.
- [ ] 7.7 Export an audio-free acceptance summary, update launch/privacy/recovery/rollback documentation, list untested routes and distribution limitations, and review the first production-oriented local release with the user.
