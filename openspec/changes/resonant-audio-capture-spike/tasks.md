## 1. Test-first foundation

- [x] 1.1 Create the minimal native macOS app target plus unit-test and UI-test targets with the agreed deployment baseline, local/debug configuration, no third-party dependencies, and no network capability.
- [x] 1.2 Add the Apple Events and system-audio purpose strings and required Hardened Runtime configuration; add a static/configuration check that microphone and screen-capture permissions are not included.
- [x] 1.3 Create deterministic test doubles for Music metadata, audio capture, route changes, permission responses, clocks, and temporary capture resources so feature tests do not require Apple Music or Core Audio hardware.
- [x] 1.4 **RED:** Write failing contract tests for independent metadata/audio health, explicit capture states, and the requirement that cleanup cannot mutate Music playback state.
- [x] 1.5 **GREEN:** Implement the diagnostic models and state transitions required by the failing tests, including idle, permission-required, connecting, active, silent, metadata-unavailable, route-reconnecting, failed, and stopped states.
- [x] 1.6 **REFACTOR:** Make the state machine deterministic and side-effect free; keep resource ownership and Music playback commands outside pure state transitions while preserving all passing tests.

## 2. Apple Music metadata path (TDD)

- [x] 2.1 **RED:** Add unit tests for mapping Music responses into optional track identity, playback state, position, duration, artwork availability, and explicit unknown values; cover missing properties, malformed values, Music unavailable, and automation errors.
- [x] 2.2 **GREEN:** Implement the metadata normalization and adapter boundary behind the test double, using the supported Apple Music scripting interface without Apple ID credentials.
- [x] 2.3 **RED:** Add tests for bounded refresh behavior: permission pending/denied/revoked, Music launched/quit, playing/paused/stopped transitions, and audio remaining independently usable when metadata fails.
- [x] 2.4 **GREEN:** Implement the bounded metadata refresh coordinator and independent metadata health reporting so it never fabricates track values or treats metadata failure as audio failure.
- [x] 2.5 **RED:** Add UI tests for the metadata permission explanation, retry/settings recovery, explicit unknown fields, and the absence of repeated prompts without a user action.
- [x] 2.6 **GREEN:** Build the native metadata panel and permission/recovery actions against the tested state model without changing Music playback during observation.
- [x] 2.7 **REFACTOR:** Isolate scriptable-interface details behind the adapter, document the target Mac's actual Music dictionary/property coverage, and keep all metadata tests green.

## 3. Capture permissions, source, and lifecycle (TDD)

- [x] 3.1 **RED:** Add permission tests proving denied or revoked system-audio access prevents capture, exposes a recoverable state, avoids microphone requests, and does not interrupt Music.
- [x] 3.2 **GREEN:** Implement explicit system-audio permission handling and user-triggered retry/settings guidance using the configured purpose string.
- [x] 3.3 **RED:** Add route/source tests for built-in speakers, available AirPlay routes, missing routes, ambiguous Music sources, and route facts such as sample rate and channel count.
- [x] 3.4 **GREEN:** Implement route enumeration, display, and explicit Music-source resolution; require a user-visible retry/selection path rather than silently mixing all applications.
- [x] 3.5 **RED:** Add lifecycle tests against fake tap/device resources for start, repeated start, stop, failure, permission revocation, app termination, and sleep/wake; assert idempotent destruction and unchanged Music playback.
- [x] 3.6 **GREEN:** Implement the private, nonmuting Core Audio process-tap and temporary aggregate-device session with one idempotent cleanup path.
- [x] 3.7 **RED:** Add event-driven tests for output-route, source, sample-format, sample-rate, channel-count, and generation changes; assert that stale measurements are invalidated before reconnection.
- [x] 3.8 **GREEN:** Implement safe capture rebuild/reconnect behavior and visible states for connecting, invalid, route-changed, and failed sessions.
- [x] 3.9 **REFACTOR:** Review the capture adapter for source isolation, resource ownership, and absence of playback mutation; keep fake lifecycle and route tests passing.

## 4. Bounded PCM and DSP analysis (TDD)

- [x] 4.1 **RED:** Write ring-buffer tests for ordering, bounded capacity, overflow/drop behavior, reset, consumer lag, and concurrent producer/consumer access under deterministic test scheduling.
- [x] 4.2 **GREEN:** Implement the preallocated bounded PCM buffer and callback-to-worker handoff with no UI work, file I/O, FFT work, or unbounded blocking in the capture callback.
- [x] 4.3 **RED:** Write tests proving host-time, sample rate, channel count, format generation, freshness, and discontinuity metadata survive the handoff and reset correctly after a route/format change.
- [x] 4.4 **GREEN:** Implement timestamped audio frames and immutable latest-frame delivery, dropping stale frames rather than replaying them.
- [x] 4.5 **RED:** Add deterministic analyzer tests using low-, mid-, high-frequency tones and silence; assert dominant-band separation, actual sample-rate/Nyquist handling, stereo-aware levels, and no false energy during silence.
- [x] 4.6 **GREEN:** Implement local RMS/peak, Hann-windowed FFT, log-spaced bands, bass/mids/highs aggregation, and sample-format-aware analysis with the test fixtures.
- [x] 4.7 **RED:** Add tests for measured noise floor, attack/release smoothing, sustained-silence decay, stale-frame rejection, and feature reset on session/format generation changes.
- [x] 4.8 **GREEN:** Implement silence gating, bounded smoothing, generation checks, and immutable feature snapshots consumed without blocking capture.
- [ ] 4.9 **REFACTOR:** Run the automated DSP suite plus a native performance/instrumentation pass; remove avoidable allocations or locks from the real-time path without changing the tested measurements.

## 5. Combined 2D/3D feasibility preview (TDD)

- [x] 5.1 **RED:** Write pure mapping tests asserting bass changes scale/expansion, mids change deformation, highs change bounded edge detail, and invalid/silent input settles both 2D and 3D values.
- [x] 5.2 **GREEN:** Implement the shared feature-to-visual mapping layer used by both proof views, with clamped values and no elapsed-track-time substitute for audio features.
- [x] 5.3 **RED:** Add UI tests for visible signal state, RMS/freshness, sample format, route, bass/mids/highs, metadata status, and explicit feasibility-preview labeling.
- [x] 5.4 **GREEN:** Build the native 2D signal panel and lightweight projected 3D wireframe/shape preview from the shared feature snapshots; keep it separate from the production Metal scene engine.
- [x] 5.5 **RED:** Add UI/accessibility tests for start/stop, test-phase and route selection, permission retry, 2D/3D switching, reduced-motion behavior, and preventing synthetic/metadata-only motion from being labeled live.
- [x] 5.6 **GREEN:** Add the tested controls, recovery copy, accessibility labels, reduced-motion handling, and visible event log to the diagnostic window without adding playback side effects.
- [x] 5.7 **REFACTOR:** Simplify view composition and ensure all visual updates consume immutable snapshots on the UI side; preserve the pure mapping and UI test suite.

## 6. Evidence records and result classification (TDD)

- [x] 6.1 **RED:** Write classifier tests for control-pass, control-failure/inconclusive, correlated subscription-pass, audible-but-unsampled fail/inconclusive, permission failure, source/route failure, silence, and metadata-unavailable cases; assert that no test emits a DRM diagnosis from silence alone.
- [x] 6.2 **GREEN:** Implement explicit pass/fail/inconclusive classification with separate evidence for audibility, metadata, permission, source, route, freshness, and measured band response.
- [x] 6.3 **RED:** Write serialization/privacy tests proving reports include test labels, timestamps/build context, route/format/permission/metadata facts, measurements, events, and classification while excluding PCM, recordings, uploads, and artwork by default.
- [x] 6.4 **GREEN:** Implement user-initiated local report creation/export and separate records for the unprotected control, streamed Apple Music playback, and downloaded Apple Music playback.
- [x] 6.5 **GREEN:** Add the documented unprotected fixture or fixture instructions with distinct low, middle, high, and silent intervals and expected bands; make the fixture usable without storing protected Apple Music content.
- [x] 6.6 **REFACTOR:** Run classifier, serialization, and privacy tests with representative failure combinations; make evidence wording clear enough to distinguish unverified protected playback from permission, source, route, or silence failures.

## 7. Native acceptance checks and handoff

- [ ] 7.1 Run the complete unit, UI, privacy/configuration, and fixture-analysis test suites on the target M5 Pro before any Apple Music conclusion is recorded.
- [ ] 7.2 Manually inspect the Music scripting dictionary and verify metadata with Music playing, paused, stopped, unavailable, and permission-denied states; attach the actual property coverage to the evidence report.
- [ ] 7.3 Execute the unprotected control through built-in speakers and verify fresh samples, expected frequency bands, silence behavior, audibility, and uninterrupted Music playback before testing subscription content.
- [ ] 7.4 Execute separate streamed and downloaded Apple Music subscription tests through built-in speakers; record whether the user hears playback and whether correlated samples arrive.
- [ ] 7.5 Repeat the control and subscription checks on AirPlay when available; record route, format, channel, freshness, synchronization/latency observations, and any route-specific limitations.
- [ ] 7.6 Run permission-denial, Music-unavailable, paused/silent, source-ambiguous, route-change, format-change, capture-error, repeated-start/stop, app-background, sleep/wake, and quit tests; confirm recovery and unchanged Music playback.
- [ ] 7.7 Run a native stress/instrumentation pass for callback safety, bounded memory, temporary tap/device cleanup, stale-feature prevention, and no network/microphone/screen/DRM/private-API path.
- [ ] 7.8 Export the final sanitized evidence packet and document the tested Mac/macOS/build, Music version, playback mode, routes, results, limitations, and recommended next action.
- [ ] 7.9 Review the evidence with the user and decide whether to create a separately approved production visualizer change; do not mark the full visualizer or production 2D/3D renderer complete in this spike.
