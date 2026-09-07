## Purpose

Define how Space Visualizer follows Apple Music playback automatically while keeping idle resource usage low and giving the user control over audio access.

## Requirements

### Requirement: Discover playback without starting Music

After permission onboarding, the app SHALL perform an initial local playback check and schedule idle checks every five seconds while its visualizer window is open. Checks SHALL NOT launch Music, control playback, overlap, accumulate delayed jobs, or repeatedly request denied permissions.

#### Scenario: Music is absent or paused
- **WHEN** the app is waiting and Music is absent, stopped, or paused
- **THEN** it remains in a static waiting state, with no capture session, analysis worker, or continuous animation, and one idle check scheduled per five-second interval

#### Scenario: Music begins playing
- **WHEN** an idle check finds Music playing and required permissions are available
- **THEN** the app cancels idle checking and begins one capture session without a manual Start capture action

#### Scenario: A check is slow
- **WHEN** a playback check exceeds its two-second end-to-end deadline, including provider queueing, helper launch, and any metadata fallback
- **THEN** the coordinator retires the request before canceling it, clears the in-flight guard, counts one failed check, and permits subsequent checks without a backlog

#### Scenario: An expired query completes late
- **WHEN** an expired or canceled request completes after its replacement has started
- **THEN** its result cannot change playback, reset the failure count, clear the replacement's in-flight guard, change permissions, or start a stale session

#### Scenario: A query completes or observation stops
- **WHEN** a query completes normally or observation is canceled by window close, sleep, or quit
- **THEN** its deadline is canceled and cannot later mutate the lifecycle

### Requirement: Observe active playback without the idle poller

The app SHALL stop idle polling during startup and active visualization. It SHALL use a two-second active watchdog for bounded playback-state observation sufficient to detect pause, stop, Music termination, and track transitions. No more than one current playback query SHALL be in flight; obsolete provider work SHALL be canceled on a best-effort basis and its callbacks ignored. Silence in PCM SHALL NOT be treated as proof that Music paused.

#### Scenario: Music pauses or stops
- **WHEN** Music pauses or stops during visualization
- **THEN** the app detects the change within five seconds under normal responsive-system conditions, completes capture/analysis/render teardown, and returns to five-second idle checks

#### Scenario: A song contains silence
- **WHEN** samples become silent but Music still reports playing
- **THEN** the scene settles without inventing motion, and the app does not incorrectly treat this as a player pause

#### Scenario: Music changes tracks
- **WHEN** Music continues playing a new track without a format or route change
- **THEN** the app updates available metadata without duplicating capture, observation, or render sessions

### Requirement: Recover playback state independently of optional metadata

The app SHALL read playback state independently of optional track metadata when the combined query returns a malformed response, an unrecognized playback state, oversized output, or a generic helper error such as a descriptor error. It SHALL attempt at most one fixed state-only fallback per query, without accessing current-track properties or artwork. It SHALL recheck that Music is running before the fallback, retain the original two-second end-to-end deadline, and bound fallback helper execution to half a second. Automation denial, timeout, and cancellation SHALL NOT trigger this fallback.

#### Scenario: Track metadata cannot be decoded
- **WHEN** the combined response fails and the fallback reports a recognized playing state
- **THEN** the query succeeds with playing state and no track details, allowing visualization without fabricating metadata

#### Scenario: Fallback reports paused or stopped
- **WHEN** the fallback reports a recognized non-playing state
- **THEN** the app handles that observation immediately rather than assuming playback continues

#### Scenario: Music quits before fallback
- **WHEN** Music is no longer running when fallback would begin
- **THEN** the app reports Music unavailable without launching another helper to address Music

#### Scenario: Fallback also fails
- **WHEN** the state-only fallback fails or returns an unrecognized state
- **THEN** the app reports the failure without guessing playback or recursively retrying, and the entire query counts as one failed check

#### Scenario: Fallback is canceled
- **WHEN** the enclosing query expires or observation stops during fallback
- **THEN** the fallback is canceled and its late response cannot alter current state

### Requirement: Recover automatically after consecutive observation failures

The app SHALL count consecutive failed playback checks, including timeouts and non-obsolete cancellation results. During active observation it SHALL preserve the existing capture session and active watchdog through the first two failures while reporting playback uncertainty. On the third consecutive failure it SHALL release capture, analysis, and rendering resources and enter five-second recovery polling. Further observation failures SHALL NOT disable recovery polling or repeatedly create capture resources. Any successful observation SHALL reset the failure count and apply Music's reported state immediately. Fresh PCM SHALL NOT reset observation failures. Permission denial SHALL bypass this policy and require user action. Independent audio-input and capture-failure safeguards SHALL remain in effect.

#### Scenario: One or two active checks fail
- **WHEN** fewer than three consecutive playback checks fail while capture is active
- **THEN** the existing session and active watchdog remain, playback uncertainty is visible, and no duplicate session is created

#### Scenario: Three checks fail consecutively
- **WHEN** the third consecutive playback check fails during active observation
- **THEN** the app tears down the active session, cancels the active watchdog, shows lost-connection recovery status, and retains one five-second idle poller

#### Scenario: Recovery checks continue failing
- **WHEN** subsequent five-second recovery checks fail
- **THEN** automatic polling continues without a manual Retry action, repeated permission prompts, a backlog, or capture creation

#### Scenario: A successful check breaks the failure streak
- **WHEN** a current query succeeds before or after the threshold
- **THEN** the failure count resets, playback uncertainty clears, and playing state preserves an existing session or starts one session if waiting

#### Scenario: Confirmed pause or permission denial follows a failure
- **WHEN** the next query confirms paused/stopped playback or reports Automation denial
- **THEN** capture stops immediately without waiting for three failures; confirmed non-playing state returns to idle discovery, while denial stops observation and exposes permission guidance

### Requirement: Request permissions with explicit user consent

On first launch the app SHALL explain automatic Music observation and in-memory system-audio analysis before a user enables them. It SHALL request only Automation and system-audio access. Known denial or revocation SHALL stop affected work and expose settings/retry guidance without repeated prompts or automatic capture retries.

#### Scenario: Permission is denied
- **WHEN** the user denies a required permission
- **THEN** the app shows a recoverable permission state, does not repeatedly prompt on five-second intervals, and leaves Music playback unchanged

#### Scenario: Permissions were previously granted
- **WHEN** the app launches with previously enabled automatic observation and usable permissions
- **THEN** it begins playback discovery without requiring a capture button or a new consent prompt

### Requirement: Own resources for the visible listening session

The app SHALL support one visualizer window and idempotent cleanup on pause, stop, capture or permission error, the observation-failure threshold, window close, sleep, and quit. Closing the window SHALL suspend all app-owned polling and audio/visual work even if the process stays open. Reopening SHALL perform a fresh playback check. Switching focus to Music while the visualizer remains visible SHALL NOT stop visualization solely due to loss of focus.

#### Scenario: Close or quit during capture
- **WHEN** the user closes the window or quits during an active or starting session
- **THEN** capture stops, temporary resources are released, transient samples and pending results are discarded, observation is canceled, and late completions cannot restart capture

#### Scenario: Sleep and wake
- **WHEN** the Mac sleeps and subsequently wakes
- **THEN** the prior session is torn down and the visible app rechecks current playback and route before creating a new session

#### Scenario: Window becomes fully hidden
- **WHEN** the app is hidden, minimized, or fully occluded
- **THEN** it suspends continuous rendering and capture/analysis, keeps at most bounded playback observation, and revalidates playback before resuming when visible

### Requirement: Recover honestly from invalid audio

The app SHALL stop invalid streams and clear stale visual data on source, route, format, permission, or capture failure. Successful session setup SHALL NOT be labeled live until fresh usable samples arrive. Persistent audio-input or capture failure SHALL require explicit retry instead of repeated resource creation every five seconds. Playback-observation failures SHALL instead follow the bounded consecutive-failure recovery policy and SHALL NOT be treated as confirmed capture failure.

#### Scenario: Capture starts without samples
- **WHEN** setup succeeds but no usable frame arrives within one second
- **THEN** the app exposes a no-signal state; after five seconds without usable input it releases the session and offers retry rather than spinning indefinitely

#### Scenario: Route or format changes
- **WHEN** the active route or PCM format changes
- **THEN** old samples are invalidated before teardown and a single revalidated session is started only when current playback, source, and permissions permit it

#### Scenario: Late work completes after stop
- **WHEN** a query, worker result, or capture-start operation completes for an obsolete session
- **THEN** its result is discarded and any resources it created are cleaned up without making the scene live

### Requirement: Keep operation local and nonmuting

The app SHALL analyze only the explicitly resolved Music source with bounded transient buffers, never write captured PCM, never send network requests, and never request microphone, screen capture, Apple ID credentials, private APIs, or DRM workarounds. It SHALL NOT mute, seek, pause, reroute, or otherwise mutate Music playback.

#### Scenario: Automatic start and cleanup
- **WHEN** automatic observation starts or stops visualization
- **THEN** Music continues its listening session unchanged, and no captured audio is saved or transmitted
