# Space Visualizer release acceptance checklist

This checklist is for the signed local bundle produced by
`scripts/build-space-visualizer-app.sh`. It is evidence collection, not a
substitute for the debug/release tests. The scripts never launch or control
Music; the operator performs Music playback actions manually.

## Build and identity

- [ ] `scripts/verify-space-visualizer-on-mac.sh` passes in debug and release.
- [ ] `scripts/verify-space-visualizer-presentation-on-mac.sh` passes.
- [ ] `scripts/verify-space-visualizer-audio-pipeline-on-mac.sh` passes.
- [ ] `RUN_THREAD_SANITIZER=1 ./scripts/verify-space-visualizer-audio-pipeline-on-mac.sh` passes, or the native limitation is recorded.
- [ ] Bundle is `.build/Space Visualizer.app` and identifier is `com.spacevisualizer.app`.
- [ ] Record Mac model, macOS, Xcode, app build, display(s), window size, and selected refresh rate.

## Permission and observation

- [ ] With Music quit, launch Space Visualizer; Music is not launched by the app.
- [ ] Before choosing **Enable automatic following**, no Automation or system-audio prompt appears.
- [ ] Enable following explicitly and record the exact Automation attribution.
- [ ] Record the exact system-audio prompt attribution; do not approve microphone or screen capture.
- [ ] Deny each permission once; the app shows retry/settings guidance and does not reprompt on the idle interval.
- [ ] Revoke each permission while active; capture and observation stop safely and explicit Retry recovers when permission is restored.
- [ ] Close and reopen the app; stored consent is intent only and current TCC status is revalidated.

## Automatic playback following

For each case, record state transitions, time to live/stop, route, measured PCM
format, freshness, and whether Music playback remained unchanged.

- [ ] Music absent: static `WAITING FOR MUSIC`; one check every five seconds.
- [ ] Music paused/stopped: no capture session, no continuous visual animation.
- [ ] Music already playing at launch: automatic start after the initial check.
- [ ] Music starts while idle: automatic start within the initial/idle-check bound.
- [ ] Fresh audible control fixture: rings/spheres respond; source quality remains unknown unless independently exposed.
- [ ] Fresh silence: scene settles and remains active; silence is not treated as pause.
- [ ] Input stops while Music remains playing: live visuals clear within 250 ms; Music is not paused or stopped.
- [ ] Music pause/stop/quit: active watchdog tears down capture and returns to five-second idle discovery.
- [ ] Track change while playing: metadata/status changes without a second capture session.

## Routes and formats

Repeat where available for unprotected control, streamed subscription,
downloaded subscription, and AirPlay routes. Do not claim untested routes.

| Case | Route / output | Audibility | Measured rate/channels/format | Fresh samples | Limitations |
|---|---|---|---|---|---|
| Control |  |  |  |  |  |
| Streamed |  |  |  |  |  |
| Downloaded |  |  |  |  |  |
| AirPlay |  |  |  |  |  |

- [ ] 48 kHz stereo is correlated with the expected control band.
- [ ] 96/192 kHz behavior is recorded where available.
- [ ] Unsupported formats fail explicitly; no microphone, screen, legacy HAL, or all-system fallback is observed.
- [ ] Measured PCM format is not presented as Lossless, Hi-Res, 24-bit source precision, or Atmos.

## Lifecycle and resource cleanup

Run at least 20 play/pause cycles and record any deviation.

- [ ] Focus switching between Space Visualizer and Music does not stop a visible session.
- [ ] Minimize, hide, and fully occlude the window suspend expensive work.
- [ ] Restore visibility triggers a fresh playback validation.
- [ ] Sleep tears down; wake revalidates playback before capture resumes.
- [ ] Close/reopen leaves no extra taps, private aggregates, workers, timers, display links, helper processes, or pending queries.
- [ ] Quit during pending startup is terminal and destroys late resources.
- [ ] Resource counts return to the idle baseline after every cycle.

## Performance

Use the optimized app with diagnostics closed during the measurement. The
sampler only observes Space Visualizer and does not control Music.

```bash
./scripts/measure-space-visualizer-performance-on-mac.sh idle 60
./scripts/measure-space-visualizer-performance-on-mac.sh active 300
```

- [ ] Idle mean process CPU is below 2% of one core.
- [ ] Active mean process CPU is below 50% of one core on the recorded target configuration.
- [ ] Resident memory and resource counts do not grow monotonically during 15 minutes / 20 cycles.
- [ ] Optional Diagnostics reports display-tick p50/p95 and the p95 is below the selected display interval.
- [ ] No interaction stall exceeds 100 ms.
- [ ] No protected audio, artwork, microphone, or screen recording was captured.

## Export and handoff

- [ ] Export the optional in-app audio-free diagnostics JSON.
- [ ] Keep the verification logs, performance CSV/Markdown, Music-observation checklist, and this completed checklist together.
- [ ] List untested routes, permission attribution limitations, OS/build details, and any failed gate.
- [ ] Do not call the release production-ready while a required gate is failed or untested.
