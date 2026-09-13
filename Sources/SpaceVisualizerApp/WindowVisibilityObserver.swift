import AppKit
import SwiftUI

/// Tracks actual window visibility, minimization, and occlusion. Key/focus
/// regain resamples visibility and requests playback reconciliation. Losing
/// focus never hides a still-visible visualizer.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onVisibilityChanged: (Bool, Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onVisibilityChanged: onVisibilityChanged)
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onVisibilityChanged = onVisibilityChanged
        view.attachIfNeeded()
    }

    static func dismantleNSView(_ view: TrackingView, coordinator: ()) {
        view.detach()
    }

    final class TrackingView: NSView {
        var onVisibilityChanged: (Bool, Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var notificationTokens: [NSObjectProtocol] = []

        init(onVisibilityChanged: @escaping (Bool, Bool) -> Void) {
            self.onVisibilityChanged = onVisibilityChanged
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            guard let window, observedWindow !== window else { return }
            observedWindow = window
            let center = NotificationCenter.default
            let windowNames: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.willCloseNotification
            ]
            notificationTokens = windowNames.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.reportVisibility(forceHidden: name == NSWindow.willCloseNotification,
                                           recheckPlayback: name == NSWindow.didBecomeKeyNotification)
                }
            }
            let applicationNames: [Notification.Name] = [
                NSApplication.didHideNotification,
                NSApplication.didUnhideNotification,
                NSApplication.didBecomeActiveNotification
            ]
            notificationTokens += applicationNames.map { name in
                center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    self?.reportVisibility(forceHidden: name == NSApplication.didHideNotification,
                                           recheckPlayback: name == NSApplication.didBecomeActiveNotification)
                }
            }
            reportVisibility()
        }

        func detach() {
            let center = NotificationCenter.default
            notificationTokens.forEach(center.removeObserver)
            notificationTokens.removeAll()
            observedWindow = nil
        }

        private func reportVisibility(forceHidden: Bool = false, recheckPlayback: Bool = false) {
            guard let window = observedWindow else { return }
            let visible = !forceHidden && !NSApp.isHidden && window.isVisible && !window.isMiniaturized &&
                window.occlusionState.contains(.visible)
            onVisibilityChanged(visible, visible && recheckPlayback)
        }

        deinit { detach() }
    }
}
