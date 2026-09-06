import AppKit
import SwiftUI
import QuartzCore

/// A view-owned display link follows the window's display and stops when detached.
struct DisplayRefreshDriver: NSViewRepresentable {
    let active: Bool
    let tick: () -> Void

    func makeNSView(context: Context) -> RefreshView { RefreshView() }
    func updateNSView(_ view: RefreshView, context: Context) {
        view.tick = tick
        view.active = active
        view.updateLink()
    }
    static func dismantleNSView(_ view: RefreshView, coordinator: ()) { view.stopLink() }

    final class RefreshView: NSView {
        var tick: (() -> Void)?
        var active = false
        private var link: CADisplayLink?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopLink()
            updateLink()
        }

        func updateLink() {
            guard active, window != nil else { stopLink(); return }
            guard link == nil else { return }
            let displayLink = self.displayLink(target: self, selector: #selector(refresh(_:)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
            displayLink.add(to: .main, forMode: .common)
            link = displayLink
        }

        func stopLink() {
            link?.invalidate()
            link = nil
        }

        @objc private func refresh(_ sender: CADisplayLink) {
            guard active, window != nil else { stopLink(); return }
            tick?()
        }
    }
}
