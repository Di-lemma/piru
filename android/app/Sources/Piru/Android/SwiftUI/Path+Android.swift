// Stroke outlines as fillable paths, for the shapes that fill a `strokedPath(_:)`, which
// SkipFuseUI marks unavailable (as it does `Path.forEach`, so a path cannot be walked and
// stroked generically). Each helper builds its outline directly: a circular arc as an annular
// band, a straight segment as a capsule. Round caps throughout, as the app's strokes use.

import SwiftUI

nonisolated extension Path {
    /// The outline of a stroke `width` wide along a circular arc from `startDegrees` to
    /// `endDegrees` (clockwise in screen space, as `addArc(clockwise: false)` draws).
    static func androidStrokedArc(center: CGPoint, radius: CGFloat, startDegrees: Double, endDegrees: Double, width: CGFloat) -> Path {
        let half = width / 2
        func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(x: center.x + r * CGFloat(cos(radians)), y: center.y + r * CGFloat(sin(radians)))
        }
        var outline = Path()
        outline.addArc(center: center, radius: radius + half, startAngle: .degrees(startDegrees), endAngle: .degrees(endDegrees), clockwise: false)
        outline.addArc(center: point(endDegrees, radius), radius: half, startAngle: .degrees(endDegrees), endAngle: .degrees(endDegrees + 180), clockwise: false)
        outline.addArc(center: center, radius: Swift.max(radius - half, 0), startAngle: .degrees(endDegrees), endAngle: .degrees(startDegrees), clockwise: true)
        outline.addArc(center: point(startDegrees, radius), radius: half, startAngle: .degrees(startDegrees + 180), endAngle: .degrees(startDegrees + 360), clockwise: false)
        outline.closeSubpath()
        return outline
    }

    /// The outline of round-capped strokes `width` wide along each segment.
    static func androidStrokedSegments(_ segments: [(CGPoint, CGPoint)], width: CGFloat) -> Path {
        var outline = Path()
        for (start, end) in segments {
            let dx = end.x - start.x, dy = end.y - start.y
            let length = sqrt(dx * dx + dy * dy)
            let capsule = Path(roundedRect: CGRect(x: -width / 2, y: -width / 2, width: length + width, height: width), cornerRadius: width / 2)
            let transform = CGAffineTransform(rotationAngle: atan2(dy, dx)).concatenating(CGAffineTransform(translationX: start.x, y: start.y))
            outline.addPath(capsule.applying(transform))
        }
        return outline
    }
}

/// SwiftUI animates any Double; SkipFuseUI's VectorArithmetic has no conformance for it.
extension Double: @retroactive VectorArithmetic {
    public mutating func scale(by rhs: Double) {
        self *= rhs
    }

    public var magnitudeSquared: Double {
        self * self
    }
}
