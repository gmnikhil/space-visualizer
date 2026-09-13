## 1. Audio analysis

- [x] 1.1 Add backward-compatible stereo region payload and bounded channel analysis; deliver tests for isolation, frequency mapping, phase cancellation, mono/multichannel fallback, and invalid input.
- [x] 1.2 Add elapsed-time region smoothing with matched pair coefficients and reset behavior; deliver timing and reset tests.

## 2. Spatial presentation

- [x] 2.1 Replace shared three-group sphere motion with 14 fixed mirrored pairs; deliver layout, isolation, silence, and Reduce Motion tests.
- [x] 2.2 Document mapping, fallback, and Mac comparison procedure in README; verify documentation matches implementation.

## 3. Validation

- [ ] 3.1 Run automated tests and strict OpenSpec validation; record results and environment limitations.
- [ ] 3.2 On macOS, build and listen-test stereo fixtures at 30/60/120 FPS; measure release CPU and energy impact against the prior commit at the same window size and sample rate.

## 4. Follow-up menu and diagnostic corrections

- [x] 4.1 Move FPS and diagnostics to focused native menu commands; verify source wiring and update README.
- [x] 4.2 Bind diagnostics and export to active lifecycle capture facts; deliver regression coverage for live, silent, waiting, and teardown states.
- [ ] 4.3 On macOS, run tests and verify menu focus/disabled state, persisted FPS changes, live diagnostics, pause/resume, and exported active route/format.

## 5. Follow-up occlusion recovery

- [x] 5.1 Forward visibility events without stale presentation filtering and replace scenePhase suspension with AppKit visibility ownership; deliver source-contract regression assertions.
- [x] 5.2 Add coalesced foreground playback refresh without restarting healthy sessions; deliver rapid hide/reveal, prolonged occlusion, foreground coalescing, and hidden-event tests.
- [x] 5.3 Show/export last query timestamps, result, in-flight status, and scheduled poller alongside visibility; deliver success/timeout/cancellation/obsolete-result regression coverage.
- [ ] 5.4 On macOS, execute tests and reproduce prolonged covering, rapid cover/reveal, app switching, minimize/unhide, and sleep/wake. Confirm immediate recovery, no duplicate capture, truthful diagnostics, and no hidden polling.

### Validation status

Implementation and regression tests are delivered. `openspec validate stereo-frequency-balls --strict` passes, as does `git diff --check`. `swift test` cannot execute in this Linux environment (`swift: command not found`), so 3.1 remains incomplete. macOS compilation, executed tests, listening checks, and performance measurements remain required; no battery or production-readiness claim is made.
