import AppKit
import SwiftUI

/// Tracks actual window visibility, minimization, and occlusion. Key/focus
/// changes are deliberately not observed: selecting Music must not stop a
/// still-visible visualizer.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onVisibilityChanged: (Bool) -> Void

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
        var onVisibilityChanged: (Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var notificationTokens: [NSObjectProtocol] = []

        init(onVisibilityChanged: @escaping (Bool) -> Void) {
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
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.willCloseNotification
            ]
            notificationTokens = windowNames.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.reportVisibility(forceHidden: name == NSWindow.willCloseNotification)
                }
            }
            let applicationNames: [Notification.Name] = [
                NSApplication.didHideNotification,
                NSApplication.didUnhideNotification
            ]
            notificationTokens += applicationNames.map { name in
                center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    self?.reportVisibility(forceHidden: name == NSApplication.didHideNotification)
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

        private func reportVisibility(forceHidden: Bool = false) {
            guard let window = observedWindow else { return }
            let visible = !forceHidden && window.isVisible && !window.isMiniaturized &&
                window.occlusionState.contains(.visible)
            onVisibilityChanged(visible)
        }

        deinit { detach() }
    }
}
