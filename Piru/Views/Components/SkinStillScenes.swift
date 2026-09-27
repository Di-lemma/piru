import SwiftUI

// The vanity skins' scenes. Both are pictures: `SkinScene.isStill` keeps the
// backdrop's clock paused, so each is drawn once per size and appearance and
// then costs nothing.

// MARK: - Nocturne

nonisolated extension SceneRenderer {
    /// Gatsby: the photograph across the top of the screen, a scrim under the
    /// title so the gold reads, the picture falling away into the ground, and
    /// a sunburst of gold rules rising from the foot of the screen.
    func drawNocturne(_ nocturne: SkinNocturne, in context: inout GraphicsContext) {
        guard size.width > 0, size.height > 0 else { return }
        let image = context.resolve(Image(nocturne.photo))
        guard image.size.width > 0, image.size.height > 0 else { return }
        // Fill the width, and at least the top 62% of the screen; the car sits
        // at the foot of the frame, so the picture anchors to the top.
        let reach = size.height * NocturneMetrics.photoReach
        let scale = max(size.width / image.size.width, reach / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        let rect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        context.drawLayer { layer in
            layer.opacity = dark ? NocturneMetrics.darkOpacity : NocturneMetrics.lightOpacity
            if !dark { layer.addFilter(.saturation(0.55)) }
            layer.draw(image, in: rect)
        }

        // Deepest under the navigation title, thinning behind the first cards,
        // clear over the car, then the ground rising over the picture's foot.
        let ground = nocturne.ground
        context.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: height + 1)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: ground.opacity(dark ? 0.75 : 0.55), location: 0),
                    .init(color: ground.opacity(dark ? 0.4 : 0.2), location: 0.3),
                    .init(color: ground.opacity(0), location: 0.58),
                    .init(color: ground.opacity(1), location: 1),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: height),
            ),
        )
        context.fill(
            Path(CGRect(x: 0, y: height, width: size.width, height: max(0, size.height - height))),
            with: .color(ground),
        )
        drawSunburst(nocturne.gold, in: &context, from: height * 0.78)
    }

    /// Rules fanning up from below the screen's foot — the deco sunburst on
    /// a lift door. Clipped to start at `top`, low in the picture, so the
    /// rules rise out of the ground it falls into.
    private func drawSunburst(_ gold: Color, in context: inout GraphicsContext, from top: CGFloat) {
        let origin = CGPoint(x: size.width / 2, y: size.height * 1.04)
        let length = size.height * 0.9
        var rays = Path()
        for i in 0 ..< NocturneMetrics.rays {
            let t = Double(i) / Double(NocturneMetrics.rays - 1)
            let angle = (-0.5 + t) * NocturneMetrics.fan - .pi / 2
            rays.move(to: origin)
            rays.addLine(to: CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length))
        }
        var arcs = Path()
        for radius in [0.18, 0.21, 0.42] {
            let r = size.height * radius
            arcs.addArc(center: origin, radius: r, startAngle: .radians(-.pi / 2 - NocturneMetrics.fan / 2), endAngle: .radians(-.pi / 2 + NocturneMetrics.fan / 2), clockwise: false)
        }
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)))
            // Fades out toward the top so the rules never reach a card's copy
            // at full strength.
            let fade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [gold.opacity(0), gold.opacity(dark ? 0.16 : 0.22)]),
                startPoint: CGPoint(x: 0, y: size.height * 0.2),
                endPoint: CGPoint(x: 0, y: size.height),
            )
            layer.stroke(rays, with: fade, lineWidth: 0.75)
            layer.stroke(arcs, with: fade, lineWidth: 1)
        }
    }
}

private nonisolated enum NocturneMetrics {
    /// The share of the screen's height the photograph covers at least.
    static let photoReach: CGFloat = 0.62
    static let darkOpacity: Double = 0.72
    /// By day the picture is a faded print on the ivory.
    static let lightOpacity: Double = 0.42
    static let rays = 25
    /// The fan's full angle.
    static let fan: Double = .pi * 0.78
}

// MARK: - Velvet

nonisolated extension SceneRenderer {
    /// Irie: a lit patch in the velvet, the tricolor pinstripe down the right
    /// edge, and a scatter of embossed fan leaves, two of them in gold.
    func drawVelvet(_ velvet: SkinVelvet, in context: inout GraphicsContext) {
        guard size.width > 0, size.height > 0 else { return }
        drawGlows([
            SkinGlow(velvet.leafLight, at: UnitPoint(x: 0.5, y: 0.32), opacity: dark ? 0.55 : 0.45),
            SkinGlow(velvet.leafShade, at: UnitPoint(x: 0.5, y: 1.05), opacity: dark ? 0.6 : 0.3),
        ], in: &context)
        drawLeaves(velvet, in: &context)
        drawPinstripe(velvet.stripes, in: &context)
    }

    /// Three bands, red, gold, green, down the right-hand gutter: inside the
    /// screen's margin, so no card, title or bar button ever sits on them.
    private func drawPinstripe(_ stripes: [Color], in context: inout GraphicsContext) {
        let band = VelvetMetrics.bandWidth
        let gap = VelvetMetrics.bandGap
        let total = CGFloat(stripes.count) * band + CGFloat(stripes.count - 1) * gap
        let left = size.width - VelvetMetrics.gutterInset - total
        context.drawLayer { layer in
            layer.opacity = dark ? 0.9 : 0.8
            for (i, color) in stripes.enumerated() {
                let x = left + CGFloat(i) * (band + gap)
                layer.fill(Path(CGRect(x: x, y: 0, width: band, height: size.height)), with: .color(color))
            }
        }
    }

    /// Leaves on a jittered grid, each embossed — the shade a point down and
    /// right, the lit face over it — and two outlined in gold.
    private func drawLeaves(_ velvet: SkinVelvet, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x1E1E)
        let columns = 3
        let rows = max(4, Int(size.height / 190))
        let cellW = size.width / CGFloat(columns)
        let cellH = size.height / CGFloat(rows)
        var index = 0
        for row in 0 ..< rows {
            for col in 0 ..< columns {
                let keep = rng.unit()
                let x = (CGFloat(col) + 0.2 + rng.unit() * 0.6) * cellW
                let y = (CGFloat(row) + 0.2 + rng.unit() * 0.6) * cellH
                let radius = 38 + rng.unit() * 46
                let turn = (rng.unit() - 0.5) * 110
                defer { index += 1 }
                guard keep < VelvetMetrics.leafShare else { continue }
                let leaf = Self.fanLeaf(radius: radius)
                    .applying(CGAffineTransform(rotationAngle: turn * .pi / 180))
                    .applying(CGAffineTransform(translationX: x, y: y))
                if index % 5 == 2 {
                    context.stroke(leaf, with: .color(velvet.gold.opacity(dark ? 0.32 : 0.45)), lineWidth: 1)
                } else {
                    context.fill(leaf.applying(CGAffineTransform(translationX: 1.5, y: 1.5)), with: .color(velvet.leafShade.opacity(0.9)))
                    context.fill(leaf, with: .color(velvet.leafLight.opacity(dark ? 0.75 : 0.85)))
                }
            }
        }
    }

    /// A seven-leaflet fan leaf pointing up from the origin, its stem below.
    /// Each leaflet is a serrated lance: the half-width follows a sine
    /// swelling, notched by a sawtooth along both edges.
    static func fanLeaf(radius: CGFloat) -> Path {
        var path = Path()
        for (angle, reach) in zip(VelvetMetrics.leafletAngles, VelvetMetrics.leafletReach) {
            let length = radius * reach
            let halfWidth = length * VelvetMetrics.leafletWidth
            var right: [CGPoint] = []
            var left: [CGPoint] = []
            let steps = VelvetMetrics.leafletSteps
            for step in 0 ... steps {
                let t = Double(step) / Double(steps)
                let swell = pow(sin(.pi * t), 0.8)
                // A tooth every two steps: out on even steps, back in on odd.
                let tooth = step.isMultiple(of: 2) ? 1.0 : 0.72
                let w = halfWidth * swell * tooth
                let along = length * t
                right.append(CGPoint(x: w, y: -along))
                left.append(CGPoint(x: -w, y: -along))
            }
            var leaflet = Path()
            leaflet.move(to: .zero)
            right.forEach { leaflet.addLine(to: $0) }
            left.reversed().forEach { leaflet.addLine(to: $0) }
            leaflet.closeSubpath()
            path.addPath(leaflet.applying(CGAffineTransform(rotationAngle: angle * .pi / 180)))
        }
        var stem = Path()
        stem.move(to: CGPoint(x: -1, y: 0))
        stem.addLine(to: CGPoint(x: -0.6, y: radius * 0.38))
        stem.addLine(to: CGPoint(x: 0.6, y: radius * 0.38))
        stem.addLine(to: CGPoint(x: 1, y: 0))
        stem.closeSubpath()
        path.addPath(stem)
        return path
    }
}

private nonisolated enum VelvetMetrics {
    static let bandWidth: CGFloat = 2.5
    static let bandGap: CGFloat = 1.5
    /// From the screen's right edge to the outermost band.
    static let gutterInset: CGFloat = 4
    /// The share of grid cells that hold a leaf.
    static let leafShare: Double = 0.5
    /// Degrees from vertical, outermost pair first.
    static let leafletAngles: [Double] = [-84, -56, -28, 0, 28, 56, 84]
    static let leafletReach: [CGFloat] = [0.36, 0.62, 0.86, 1, 0.86, 0.62, 0.36]
    /// Half-width at the swell, as a share of the leaflet's length.
    static let leafletWidth: CGFloat = 0.13
    static let leafletSteps = 18
}
