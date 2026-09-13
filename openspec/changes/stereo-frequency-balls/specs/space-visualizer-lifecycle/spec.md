## ADDED Requirements

### Requirement: Reconcile visible foreground playback without stale presentation state
Visibility transitions SHALL be reconciled against authoritative lifecycle state rather than discarded using asynchronously published UI state. Returning from full occlusion SHALL perform a fresh playback check without waiting for a periodic interval. Returning a visible waiting or active window to the foreground SHALL request an immediate playback check, coalescing with any current query and preserving healthy capture. Focus loss alone SHALL NOT suspend a still-visible window. Foreground events for a hidden window SHALL NOT resume capture or polling. Permission-blocked, failed, and terminated states SHALL retain their existing explicit recovery policies.

#### Scenario: Hide and reveal precede presentation delivery
- **WHEN** hide and reveal events occur before the UI receives the hidden-state presentation
- **THEN** the reveal is processed and playback discovery resumes without restarting the app

#### Scenario: Prolonged full occlusion
- **WHEN** the window remains fully covered for ten minutes and becomes visible again
- **THEN** hidden capture and polling remain stopped, and reveal triggers immediate playback discovery without accumulated checks

#### Scenario: Foreground while a check is in flight
- **WHEN** the app or visible window regains focus while a playback check is already in progress
- **THEN** that check remains the only current query and a healthy capture session is not recreated

### Requirement: Expose playback observation health
Diagnostics and audio-free exports SHALL expose the last playback-check start and completion timestamps, last accepted result, whether a check is in progress, and whether idle or active polling is scheduled. Diagnostics SHALL also display authoritative window visibility. Historical results SHALL remain identifiable as historical through their timestamps and SHALL NOT be substituted for current in-progress status. Obsolete query callbacks SHALL NOT overwrite this evidence.

#### Scenario: Observation succeeds or times out
- **WHEN** a current playback query starts and then succeeds or reaches its deadline
- **THEN** diagnostics records its timestamps and result, clears its in-progress status, and reports the currently scheduled poller

#### Scenario: Observation canceled while hiding
- **WHEN** a window is hidden during a playback query
- **THEN** diagnostics records lifecycle cancellation, reports no check in progress and polling stopped, and ignores any late result
