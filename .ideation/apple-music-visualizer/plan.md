# Interactive Planning: Resonant — Apple Music Visualizer

Status: **Native feasibility spike approved; full visualizer implementation not approved.**

## Artifact Index

- Plan: `.ideation/apple-music-visualizer/plan.md`
- HTML review: `.ideation/apple-music-visualizer/design-and-architecture.html`
- Feasibility/source notes: `.ideation/apple-music-visualizer/feasibility-notes.md`

## 1. Idea Map

### User Input

- Create a macOS app that visualizes music already playing in Apple Music.
- User already has an Apple Music subscription.
- Explain whether it is possible, then show architecture and screens in an HTML file for approval.
- Be creative, including 3D animation if useful; the visualization must genuinely follow the music.
- Follow-up: **do not use Blueprint Hero**; agent may design creatively.

### Agent Contribution

- Working title: Resonant. A cinematic, local-first native companion to Music rather than a replacement player.
- Conditional feasibility: metadata and rendering are supported building blocks, but actual subscription PCM capture must be proven on the user's Mac using permitted public APIs.
- A subscription/MusicKit alone does not expose decoded PCM for analysis. Do not substitute decorative, metadata-driven animation for genuine reactivity.
- Immediate alternative: Apple's built-in Window → Visualizer.
- User explicitly requested the full review artifact, so the HTML combines provisional idea, criteria, alternatives, and design. The user has now approved the native feasibility spike only; production choices remain provisional unless stated below.

### Decisions

- Confirmed user constraint: no Blueprint Hero styling.
- Confirmed deliverable: HTML architecture and screen proposal, not a native implementation.
- Native companion feasibility spike is approved in principle; the full visualizer remains unapproved.
- Target hardware is an M5 Pro; initial routes are built-in speakers and AirPlay.
- The visual direction should combine shapes with 2D and 3D motion; no single signature scene has been selected.

### Artifact Paths

- `.ideation/apple-music-visualizer/design-and-architecture.html#overview`
- `.ideation/apple-music-visualizer/feasibility-notes.md`

## 2. Success Criteria

### User Input

- Visuals should be creative and visualization should happen properly.

### Agent Contribution

Proposed criteria, not yet approved or demonstrated:

- Track details follow the actual Music app without a second login or replacement playback workflow.
- Fresh, permitted PCM from the actual subscription playback drives the visuals; otherwise show an honest unavailable state.
- Bass, mids, highs, and transient strength control distinct visual dimensions. Do not fabricate BPM or infer spectrum from elapsed position.
- Silence/pauses settle; route changes clear stale features; unrelated apps' audio does not drive a Music-only visualizer.
- Initial quality target: 60 fps at 1080p on Apple Silicon; adaptive 30 fps battery/thermal mode. Hardware support remains to be confirmed.
- Initial local/wired audible-to-visible lag goal: 50–100 ms, measured end to end and tuned. Bluetooth/AirPlay are not assumed supported or synchronized.
- No audio uploads or recording; bounded transient buffers; no microphone by default.
- Accessible controls, reduced-motion behavior, bounded brightness, and no strobes.
- Non-goals: library replacement, lyrics, social features, recording/export of protected music, cloud analysis, a scene editor, and guaranteed App Store delivery.

### Approved Criteria

- [ ] Pending user confirmation or revision.

### Artifact Paths

- `.ideation/apple-music-visualizer/design-and-architecture.html#architecture`
- `.ideation/apple-music-visualizer/design-and-architecture.html#review`

## 3. Variations

| Variation | Prioritizes | Gives Up | Best Fit | Risk |
| --- | --- | --- | --- | --- |
| Built-in Music visualizer | Immediate first-party experience | Our own product/UI | Visuals today | Limited customization |
| Ambient metadata companion | Simple atmosphere | True audio reactivity | Decorative background | Does not meet the stated signal requirement |
| Native Music companion | Existing listening workflow + real analysis | In-app catalog/queue | User's stated idea | Must prove subscription capture and route compatibility |
| In-app MusicKit player | Integrated search/playback | Small scope/passive following | Future music product | More scope; MusicKit still does not expose subscription PCM |
| Unprotected local-file studio | Direct analysis access | Subscription integration | Owned files/live performances | Changes core requirement |

### Selected Direction

- User-approved for the next change: native Music companion feasibility spike, conditional on evidence from the capture gate.
- Apple Music remains the player; Resonant observes metadata and attempts permitted audio analysis.
- The production visualizer variation is not approved until the spike result is reviewed.

### Artifact Paths

- `.ideation/apple-music-visualizer/design-and-architecture.html#feasibility`
- `.ideation/apple-music-visualizer/design-and-architecture.html#review`

## 4. Architecture Or Experience

### User Input

- Show architecture and all proposed screens in a creative HTML review surface.
- Explicitly rejected Blueprint Hero; creative freedom for the design.

### Agent Proposal

- Visual document: warm, noir-ink editorial panels, ink borders, sepia paper, restrained captions; no blueprint grid. Product mockups are dark, cinematic, luminous, and spatial.
- Three creative directions: Orbital Bloom (recommended), Spectral Terrain, Prism Drift.
- Self-contained, offline HTML: stable URL-fragment sections; canvas 3D-coordinate motion studies; labeled silent synthetic default; optional unprotected local audio with actual browser Web Audio FFT; no Apple Music/browser system capture claims.
- Screens: transparent onboarding, live viewer with tuning, scene library, immersive focus mode, settings, mini companion, and signal-state diagnostics.
- Native stack proposal: SwiftUI + MTKView/Metal + Accelerate/vDSP.
- Music metadata/transport via Apple events/ScriptingBridge on a bounded worker, separate from realtime PCM.
- Private, nonmuting Core Audio process tap + private aggregate device → preallocated bounded ring buffer → serial DSP → timestamped features → display-paced Metal rendering.
- Playback remains in Music; no microphone, server, audio recording, or cloud analysis. Optional MusicKit enrichment later; no private MediaRemote APIs.
- Proposed baseline macOS 14.2+, initially Apple Silicon quality target, direct distribution after local development. Verify actual SDK/symbol/deployment and permission behavior on a Mac.
- Mandatory native feasibility gate requires separate explicit authorization. Public documentation is not evidence that the user's protected playback is capturable.
- Review form can copy/download choices and save them browser-locally where supported. It does not send approval or update this plan automatically.

### Approved Direction

- Native companion feasibility spike only; Apple Music remains the playback app.
- Target: M5 Pro with built-in speakers and AirPlay test coverage.
- Combine 2D and 3D motion with layered shapes; keep the exact production scene open for later review.
- The warm cinematic/noir-ink document direction and the HTML review surface are accepted as the current design reference.
- Full production renderer, polished scenes, and full app implementation remain unapproved.

### Artifact Paths

- `.ideation/apple-music-visualizer/design-and-architecture.html`
- `.ideation/apple-music-visualizer/feasibility-notes.md`

## 5. Test Strategy

### User Input

- Proper, accurate music visualization is required; no detailed test strategy supplied.

### Agent Proposal

- Full native test-strategy discussion is intentionally deferred until architecture/experience review, as required by the interactive planning flow.
- The HTML describes a feasibility **go/no-go gate**, not an approved test plan: inspect real Music metadata and permitted PCM; use an unprotected control; test actual streamed/downloaded subscription playback on the user's route; stop if inaccessible.
- HTML artifact QA is separate from native feasibility and must never be reported as proof of Apple Music integration.

### Approved Test Plan

- [ ] Pending design approval and user discussion.

### Artifact Paths

- `.ideation/apple-music-visualizer/feasibility-notes.md` (gate only)

## 6. Implementation Plan

### Summary

- OpenSpec change created for the approved native feasibility spike; no native code has been implemented yet.
- Build the small diagnostic → report real-Mac evidence from the M5 Pro/speakers/AirPlay → agree the test strategy and next change → request separate full-implementation approval.
- A failed capture gate requires scope revision with the user; unprotected files or ambient mode are not silently accepted substitutes.

### Deliverables

- Completed: feasibility explanation, HTML screen/architecture review, interactive visual concepts, and approval worksheet.
- Approved next deliverable: native audio/metadata feasibility spike and evidence report.
- Full visualizer app: not authorized by this approval.

### Open Questions And Risks

1. Does the companion direction match the user's intended workflow?
2. Which visual world should lead: Orbital Bloom, Terrain, Prism, or a combination?
3. What Mac, macOS version, and listening output are used (speakers, wired, Bluetooth, AirPlay)?
4. Are lossless/Spatial Audio or remote playback important on day one?
5. Can public capture APIs receive usable subscription audio in that environment?
6. Personal/local use, direct distribution, or Mac App Store? Apple Music and Developer Program subscriptions are different.
7. Native Music artwork/metadata coverage, process ownership, sandbox/automation compatibility, and route-specific synchronization remain unverified.

### User Approval

- Approved in conversation: **Approve the direction and native feasibility spike only**.
- Chosen approach: **Native companion (recommended)**.
- Visual revision: **combination of shapes with 2D/3D motion**.
- Environment supplied: **M5 Pro; speakers and AirPlay**.
- Full-app implementation remains explicitly unapproved.

### Artifact Paths

- `.ideation/apple-music-visualizer/design-and-architecture.html#review`
