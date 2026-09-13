## Why

The 28 spheres currently share three mono energy signals, making same-colour balls move together and discarding stereo placement. Individual frequency regions and explicit left/right partners will make their height reflect more of the music without sideways animation.

## What Changes

- Map 28 balls to 14 frequency regions with a left and right partner per region.
- Preserve independent channel energy, fixed horizontal positions, and bass/mid/high colours.
- Use subtle frequency-dependent attack/release smoothing, identical within each pair.
- Keep central rings broadly audio-driven, selected FPS caps, capture privacy, and accessibility behavior.
- Defer instrument separation and transient-driven size pulses.
- Follow-up: move frame-rate selection and Diagnostics to a native Visualizer menu, keeping the canvas uncluttered.
- Follow-up: correct Diagnostics and report export to use the active automatic-following session rather than the unused legacy diagnostic engine.
- Follow-up: prevent dropped visibility-resume events, recheck playback on visible foreground return, and expose observation timestamps/results and polling state.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `space-visualizer-experience`: Add stereo frequency-paired ball behavior, safe mono/multichannel fallback, native menu controls, and truthful active-session diagnostics.
- `space-visualizer-lifecycle`: Reconcile visibility and foreground transitions without stale UI-state filtering and expose observation-health evidence.

## Impact

Audio feature model, analyzer, smoother, sphere layout, tests, and README. No new dependencies or capture permissions. Additional bounded stereo FFT work requires target-Mac performance verification. The existing spec's 120 Hz default predates the separately committed manual FPS selector; this change preserves that selector without expanding scope to cadence spec reconciliation.
