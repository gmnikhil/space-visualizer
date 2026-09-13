## Context

The analyzer mixes channels before its FFT and publishes three broad energies plus 64 mono bands. SpatialScene repeats those three energies across 28 balls and adds shared mid-driven sway. Feature smoothing already uses elapsed audio time, independently of rendering.

## Goals / Non-Goals

**Goals:** Channel-isolated height, stable frequency identity, matched pair geometry and response, bounded worker cost, safe stale/silent behavior.

**Non-Goals:** Instrument isolation, panning-driven sideways motion, beat simulation, transient size pulses, new rendering loops, changing the FPS selector.

## Decisions

- Add optional stereo region levels to AudioFeatures, preserving decoding of older audio-free reports and existing constructors. Use 14 shared regions with edges 20, 60, 110, 180, 250, 400, 650, 1000, 1600, 2500, 4000, 6000, 9000, 12000, 16000 Hz. Four bass, six mid, four treble regions avoid excessive subdivision of poorly resolved bass bins. Aggregate nonoverlapping bin centers; use smooth bounded energy compression rather than early hard clipping.
- For stereo, perform one FFT per channel for sphere regions, retaining the existing mono FFT for unchanged central-ring features. This deliberately favors compatibility over optimizing away the mono transform. Stereo RMS gates silence so opposite-phase channels cannot silence the balls. For mono, reuse the existing FFT and duplicate levels. For more than two channels, use the existing mono downmix for both partners rather than pretending channel order implies left/right.
- Smooth stereo levels on the existing worker with time-adjusted coefficients: attack/release 0.7/0.14 bass, 0.6/0.2 mids, 0.85/0.35 highs per existing reference interval. Match both channels; reset on stale input, discontinuity, and generation changes. No display-dependent smoothing or additional timers.
- Place mirrored partners at fixed x, equal depth, radius and lift gain. Distribute frequency regions through depth and lane positions, retain orange/mint/purple palette, remove shared sway. Existing size/outline energy response remains; no new transient pulse. Add static resting lift of 0.12 scene units before perspective, plus the existing proportional audio lift. Unlike clamping energy or height, an additive baseline preserves small reactions and truthful zero energy. Threads remain visible at zero energy with a faint gradient (opacity 0.04 at the floor and 0.14 at the ball), rising to 0.35 at the ball with full energy. Only Reduce Motion hides threads. This is static artwork and adds no idle rendering loop; verify resting and low-energy curve appearance on Mac.
- Missing stereo payload falls back to existing broad levels for legacy fixtures/reports. Silent/stale/Reduce Motion still produces settled geometry.

## Risks / Trade-offs

- [Extra FFT work] → One bounded stereo analysis per worker window, never per ball; benchmark 30/60 FPS and 48/96/192 kHz on Mac before readiness claims.
- [Frequency overlap and low resolution] → Nonoverlapping bin-center regions; no promise of instrument isolation or perfectly independent music signals.
- [Quiet treble or hot masters] → Smooth bounded compression and fixture tests; listening-based tuning remains a Mac acceptance step.
- [Unknown multichannel layout] → Symmetric downmix fallback, not inferred spatial labels.
- [Old mono cancellation] → Stereo silence gate is independent of the mono ring path; rings otherwise retain their existing mixed response.

## Follow-up: Menu commands and truthful diagnostics

Use a native Visualizer command menu with the existing AppStorage FPS preference; remove the duplicate canvas controls. A focused-scene action opens the existing diagnostics sheet and disables the command without a focused visualizer scene. Export Image stays in the window.

Expose measured route/format through a capture-facts protocol and the lifecycle presentation snapshot, read only on the coordinator queue. Derive signal labels from actual lifecycle state, not Music's playing flag. Clear active facts naturally when resources are torn down. The diagnostics panel and exported report use these facts instead of the unused legacy diagnostic engine; the engine remains only for existing build context and compatibility. Optional report fields preserve decoding older exports. Do not add polling, FFT work, or high-rate UI publications for this fix.

## Follow-up: Occlusion resume and observation health

The SwiftUI visibility callback previously compared each notification with an asynchronously delivered presentation. A hide/reveal burst could discard reveal against an outdated visible=true snapshot. Forward all events and rely on coordinator idempotency instead. Remove the competing scenePhase-based sleep path; actual AppKit visibility owns occlusion and NSWorkspace notifications retain real system sleep/wake handling.

Observe app activation and window becoming key only to resample actual visibility and request a foreground playback refresh. Never suspend merely for losing key focus. Hidden/minimized/occluded checks still prevent unnecessary work. The coordinator's refresh ensures the appropriate timer exists and reuses its existing one-query-in-flight guard without recreating healthy capture or bypassing explicit error/permission retry.

Publish a bounded observation-health snapshot (last start/completion Date, last result, in-flight flag, scheduled poller) alongside lifecycle presentation. Completion and lifecycle cancellation update the historical evidence; obsolete callbacks do not. Diagnostics includes window visibility and absolute timestamps, avoiding a new refresh timer. Export the same snapshot with an optional field for backward decoding compatibility. A scheduled timer is not claimed to prove successful polling: timestamps and results provide that evidence. The original incident is not reproduced here; these changes address a demonstrable race and improve future diagnosis without claiming all potential stalls are fixed.

## Migration Plan

No persisted preference migration. Optional feature payload remains backward-decodable. Revert this change to restore the old three-group mapping.
