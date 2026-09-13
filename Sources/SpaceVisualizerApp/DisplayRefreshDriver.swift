import AppKit
import SwiftUI
import QuartzCore
import SpaceVisualizerCore

/// A view-owned display link follows the window's display and stops when detached.
struct DisplayRefreshDriver: NSViewRepresentable {
    let active: Bool
    let framesPerSecond: Int
    let telemetry: DisplayFrameTelemetry?
    let tick: () -> Void

    func makeNSView(context: Context) -> RefreshView {
        RefreshView(telemetry: telemetry)
    }
    func updateNSView(_ view: RefreshView, context: Context) {
        view.tick = tick
        view.active = active
        view.framesPerSecond = DisplayCadencePolicy.validatedFramesPerSecond(framesPerSecond)
        view.telemetry = telemetry
        view.updateLink()
    }
    static func dismantleNSView(_ view: RefreshView, coordinator: ()) { view.stopLink() }

    final class RefreshView: NSView {
        var tick: (() -> Void)?
        var telemetry: DisplayFrameTelemetry?
        var active = false
        var framesPerSecond = DisplayCadencePolicy.defaultFramesPerSecond
        private var link: CADisplayLink?

        init(telemetry: DisplayFrameTelemetry?) {
            self.telemetry = telemetry
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopLink()
            updateLink()
        }

        func updateLink() {
            guard active, window != nil else { stopLink(); return }
            let requested = Float(framesPerSecond)
            let range = CAFrameRateRange(minimum: 30, maximum: requested, preferred: requested)
            if let link {
                if link.preferredFrameRateRange.maximum != requested {
                    link.preferredFrameRateRange = range
                }
                return
            }
            let displayLink = self.displayLink(target: self, selector: #selector(refresh(_:)))
            displayLink.preferredFrameRateRange = range
            displayLink.add(to: .main, forMode: .common)
            link = displayLink
        }

        func stopLink() {
            link?.invalidate()
            link = nil
        }

        @objc private func refresh(_ sender: CADisplayLink) {
            guard active, window != nil else { stopLink(); return }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            tick?()
            let finishedAt = DispatchTime.now().uptimeNanoseconds
            telemetry?.recordFrame(workNanoseconds: finishedAt >= startedAt ? finishedAt - startedAt : 0)
        }
    }
}
