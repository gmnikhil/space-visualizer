import SwiftUI
import SpaceVisualizerCore

/// Canvas lighting, floor perspective, and depth-sorted audio-driven spheres.
enum SpatialStage {
    private static let floorGeometry: Path = {
        let size = CGSize(width: 1, height: 1)
        let horizon = CGPoint(x: 0.5, y: 0.38)
        var floor = Path()
        for index in 0...12 {
            floor.move(to: horizon)
            floor.addLine(to: CGPoint(x: size.width * CGFloat(index) / 6 - size.width * 0.5, y: size.height))
        }
        for index in 1...7 {
            let t = CGFloat(index) / 7
            let y = horizon.y + (size.height - horizon.y) * t * t
            floor.move(to: CGPoint(x: 0, y: y))
            floor.addLine(to: CGPoint(x: size.width, y: y))
        }
        return floor
    }()

    static func draw(context: GraphicsContext, size: CGSize, features: AudioFeatures, reduceMotion: Bool) {
        let colors: [Color] = [.orange, .mint, .purple]
        let floor = floorGeometry.applying(CGAffineTransform(scaleX: size.width, y: size.height))
        context.stroke(floor, with: .color(.mint.opacity(0.07)), lineWidth: 0.7)

        for ball in SpatialScene.balls(features: features, reduceMotion: reduceMotion) {
            let center = CGPoint(x: size.width * (0.5 + CGFloat(ball.x) * 0.5),
                                 y: size.height * (0.42 + CGFloat(ball.y) * 0.64))
            let floorPoint = CGPoint(x: center.x, y: size.height * (0.42 + CGFloat(ball.floorY) * 0.64))
            let radius = min(size.width, size.height) * CGFloat(ball.radius) * 1.4
            let color = colors[ball.palette]
            let shadow = CGRect(x: floorPoint.x - radius * 1.7, y: floorPoint.y,
                                width: radius * 3.4, height: radius * 0.45)
            context.fill(Path(ellipseIn: shadow), with: .color(color.opacity(0.12)))
            if ball.energy > 0.03 && !reduceMotion {
                var trail = Path()
                trail.move(to: floorPoint)
                trail.addQuadCurve(to: center, control: CGPoint(x: center.x - radius * 3, y: floorPoint.y - radius * 4))
                context.stroke(trail, with: .linearGradient(
                    Gradient(colors: [color.opacity(0), color.opacity(0.35)]),
                    startPoint: floorPoint, endPoint: center), lineWidth: 1.2)
            }
            let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let highlight = CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4)
            context.fill(Path(ellipseIn: bounds), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.95), color, color.opacity(0.2), .black.opacity(0.85)]),
                center: highlight, startRadius: 0, endRadius: radius * 1.8))
            context.stroke(Path(ellipseIn: bounds), with: .color(color.opacity(0.4 + ball.energy * 0.5)), lineWidth: 0.8)
        }
    }
}
