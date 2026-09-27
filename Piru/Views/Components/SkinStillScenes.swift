import SwiftUI

// The vanity skins' scenes. Both are pictures: `SkinScene.isStill` keeps the
// backdrop's clock paused, so each is drawn once per size and appearance and
// then costs nothing.

// MARK: - Nocturne

nonisolated extension SceneRenderer {
    /// Gatsby: the night picture in dark mode, the dusk one in light, filling
    /// the screen, with a scrim under the navigation title so the gold reads
    /// and a light veil over the skyline so the timeline's labels hold.
    func drawNocturne(_ nocturne: SkinNocturne, in context: inout GraphicsContext) {
        guard size.width > 0, size.height > 0 else { return }
        let image = context.resolve(Image(dark ? nocturne.night : nocturne.dusk))
        guard image.size.width > 0, image.size.height > 0 else { return }
        // Aspect-fill, anchored to the foot so the car stays in frame on any
        // screen taller than the picture.
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        context.draw(image, in: CGRect(x: (size.width - width) / 2, y: size.height - height, width: width, height: height))

        let ground = nocturne.ground
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: ground.opacity(NocturneMetrics.titleScrim), location: 0),
                    .init(color: ground.opacity(NocturneMetrics.veil), location: 0.22),
                    .init(color: ground.opacity(NocturneMetrics.veil), location: 0.55),
                    .init(color: ground.opacity(0), location: 0.72),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height),
            ),
        )
    }
}

private nonisolated enum NocturneMetrics {
    static let titleScrim: Double = 0.6
    /// Over the skyline; the car below is left clear.
    static let veil: Double = 0.2
}

// MARK: - Velvet

nonisolated extension SceneRenderer {
    /// Irie. A tab root gets the canopy: a record-label sunburst in the
    /// tricolor rising from a gold sun at the foot, and fan leaves in two
    /// depths framing the edges with the middle left open. A pushed screen or
    /// a sheet gets the quieter knit: a crocheted tam's stitch rows, clearing
    /// toward the middle, under one gold leaf. The pinstripe runs down the
    /// right gutter of both.
    func drawVelvet(_ velvet: SkinVelvet, in context: inout GraphicsContext) {
        guard size.width > 0, size.height > 0 else { return }
        drawGlows([
            SkinGlow(velvet.leafLight, at: UnitPoint(x: 0.5, y: 0.32), opacity: dark ? 0.45 : 0.4),
            SkinGlow(velvet.leafShade, at: UnitPoint(x: 0.5, y: 1.05), opacity: dark ? 0.6 : 0.3),
        ], in: &context)
        if presented {
            drawKnit(velvet, in: &context)
        } else {
            drawSunburst(velvet, in: &context)
            drawCanopy(velvet, in: &context)
            drawMotes(velvet, in: &context)
        }
        drawPinstripe(velvet.stripes, in: &context)
    }

    // MARK: Canopy

    /// Thin rays in the tricolor from a gold sun low on the screen, fading
    /// out with distance, the sun ringed like a record's grooves — a
    /// Kingston label.
    private func drawSunburst(_ velvet: SkinVelvet, in context: inout GraphicsContext) {
        let sun = CGPoint(x: size.width / 2, y: size.height * VelvetMetrics.sunHeight)
        let reach = hypot(size.width, size.height)
        let count = VelvetMetrics.wedges
        let step = 2 * Double.pi / Double(count)
        context.drawLayer { layer in
            layer.opacity = dark ? 0.3 : 0.2
            // Every other wedge is a ray; the gaps are the ground.
            for i in stride(from: 0, to: count, by: 2) {
                let start = Double(i) * step
                var ray = Path()
                ray.move(to: sun)
                ray.addArc(center: sun, radius: reach, startAngle: .radians(start), endAngle: .radians(start + step), clockwise: false)
                ray.closeSubpath()
                layer.fill(ray, with: .color(velvet.stripes[(i / 2) % velvet.stripes.count]))
            }
            // Strong at the sun, gone by the screen's edges.
            layer.blendMode = .destinationOut
            layer.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [.black.opacity(0), .black]),
                    center: sun,
                    startRadius: size.width * 0.12,
                    endRadius: size.height * 0.62,
                ),
            )
        }
        bloom(velvet.gold, at: sun, radius: size.width * 0.3, alpha: dark ? 0.45 : 0.4, in: &context)
        var rings = Path()
        for r in VelvetMetrics.sunRings {
            let radius = size.width * r
            rings.addEllipse(in: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))
        }
        context.stroke(rings, with: .color(velvet.gold.opacity(dark ? 0.45 : 0.6)), lineWidth: 1)
    }

    /// Big leaves reaching in from the edges, a dark far layer behind a lit
    /// near one, each with its veins; the middle of the screen stays open.
    private func drawCanopy(_ velvet: SkinVelvet, in context: inout GraphicsContext) {
        let unit = min(size.width, size.height * 0.55)
        for layer in [VelvetMetrics.farLeaves, VelvetMetrics.nearLeaves] {
            let near = layer.first?.near ?? false
            for leaf in layer {
                let radius = unit * leaf.size
                let transform = CGAffineTransform(rotationAngle: leaf.angle * .pi / 180)
                    .concatenating(CGAffineTransform(translationX: leaf.x * size.width, y: leaf.y * size.height))
                let blade = Self.fanLeaf(radius: radius).applying(transform)
                let veins = Self.fanLeafVeins(radius: radius).applying(transform)
                if near {
                    // Gold leaf: a dark blade, a gilt edge and gilt veins.
                    context.fill(blade, with: .color(velvet.leafShade.opacity(0.9)))
                    context.stroke(blade, with: .color(velvet.gold.opacity(dark ? 0.75 : 0.85)), lineWidth: 1.2)
                    context.stroke(veins, with: .color(velvet.gold.opacity(dark ? 0.5 : 0.6)), lineWidth: 0.8)
                } else {
                    // A silhouette a step off the ground, for depth.
                    context.fill(blade, with: .color(velvet.leafLight.opacity(dark ? 0.55 : 0.7)))
                }
            }
        }
    }

    /// Gold motes, as if caught in the sun's light.
    private func drawMotes(_ velvet: SkinVelvet, in context: inout GraphicsContext) {
        var rng = SeededRNG(seed: 0x1A11)
        for _ in 0 ..< VelvetMetrics.motes {
            let x = rng.unit() * size.width
            let y = size.height * (0.25 + rng.unit() * 0.65)
            let r = 0.8 + rng.unit() * 1.6
            bloom(velvet.gold, at: CGPoint(x: x, y: y), radius: r * 4, alpha: 0.25 + rng.unit() * 0.3, in: &context)
        }
    }

    // MARK: Knit

    /// A crocheted tam: rows of V stitches in red, gold and green with a row
    /// of the ground between each color, fading out toward the middle so copy
    /// sits on plain velvet. One gold leaf outline lies across it.
    private func drawKnit(_ velvet: SkinVelvet, in context: inout GraphicsContext) {
        let row = VelvetMetrics.stitchHeight
        let stitch = VelvetMetrics.stitchWidth
        var rows: [Path] = Array(repeating: Path(), count: velvet.stripes.count)
        var y: CGFloat = 0
        var band = 0
        while y < size.height {
            // Two rows per color, then a row of ground.
            let colorIndex = band / 3
            if band % 3 != 2 {
                var x: CGFloat = -stitch
                while x < size.width + stitch {
                    rows[colorIndex % rows.count].move(to: CGPoint(x: x, y: y))
                    rows[colorIndex % rows.count].addLine(to: CGPoint(x: x + stitch / 2, y: y + row * 0.8))
                    rows[colorIndex % rows.count].addLine(to: CGPoint(x: x + stitch, y: y))
                    x += stitch
                }
            }
            y += row
            band = (band + 1) % (3 * velvet.stripes.count)
        }
        context.drawLayer { layer in
            layer.opacity = dark ? 0.22 : 0.28
            for (i, path) in rows.enumerated() {
                layer.stroke(path, with: .color(velvet.stripes[i]), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            // Clear the middle: the ground over the knit, strongest at the center.
            layer.blendMode = .destinationOut
            layer.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [.black, .black.opacity(0.85), .black.opacity(0)]),
                    center: CGPoint(x: size.width / 2, y: size.height * 0.45),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.62,
                ),
            )
        }
        let radius = size.width * 0.55
        let leaf = Self.fanLeaf(radius: radius)
            .applying(CGAffineTransform(rotationAngle: -18 * .pi / 180))
            .applying(CGAffineTransform(translationX: size.width * 0.58, y: size.height * 0.62))
        context.stroke(leaf, with: .color(velvet.gold.opacity(dark ? 0.16 : 0.22)), lineWidth: 1)
    }

    // MARK: Shared

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

    /// The midrib of each leaflet in ``fanLeaf(radius:)``, stopping short of
    /// the tip, with a few side veins angled toward it.
    static func fanLeafVeins(radius: CGFloat) -> Path {
        var path = Path()
        for (angle, reach) in zip(VelvetMetrics.leafletAngles, VelvetMetrics.leafletReach) {
            let length = radius * reach
            let halfWidth = length * VelvetMetrics.leafletWidth
            var veins = Path()
            veins.move(to: .zero)
            veins.addLine(to: CGPoint(x: 0, y: -length * 0.92))
            for t in stride(from: 0.2, through: 0.75, by: 0.11) {
                let along = length * t
                let reachOut = halfWidth * pow(sin(.pi * t), 0.8) * 0.8
                veins.move(to: CGPoint(x: 0, y: -along))
                veins.addLine(to: CGPoint(x: reachOut, y: -along - reachOut * 1.2))
                veins.move(to: CGPoint(x: 0, y: -along))
                veins.addLine(to: CGPoint(x: -reachOut, y: -along - reachOut * 1.2))
            }
            path.addPath(veins.applying(CGAffineTransform(rotationAngle: angle * .pi / 180)))
        }
        return path
    }
}

/// One leaf of the canopy, placed in unit coordinates of the screen.
private nonisolated struct CanopyLeaf {
    let x: CGFloat
    let y: CGFloat
    /// Radius as a share of the screen's shorter reach.
    let size: CGFloat
    /// Degrees; 0 points up, 180 hangs down.
    let angle: Double
    var near = false
}

private nonisolated enum VelvetMetrics {
    static let bandWidth: CGFloat = 2.5
    static let bandGap: CGFloat = 1.5
    /// From the screen's right edge to the outermost band.
    static let gutterInset: CGFloat = 4
    /// Wedges around the full circle; every other one is a ray.
    static let wedges = 36
    /// The sun's height as a share of the screen's.
    static let sunHeight: CGFloat = 0.7
    static let sunRings: [CGFloat] = [0.1, 0.13, 0.2]
    static let motes = 26
    static let stitchHeight: CGFloat = 9
    static let stitchWidth: CGFloat = 10

    /// Hanging from the top corners and rising from the bottom ones, reaching
    /// in from both edges at mid-height.
    static let farLeaves: [CanopyLeaf] = [
        CanopyLeaf(x: 0.08, y: -0.02, size: 0.62, angle: 150),
        CanopyLeaf(x: 0.95, y: 0.0, size: 0.58, angle: -155),
        CanopyLeaf(x: -0.05, y: 0.5, size: 0.5, angle: 110),
        CanopyLeaf(x: 1.05, y: 0.42, size: 0.52, angle: -105),
        CanopyLeaf(x: 0.02, y: 1.02, size: 0.6, angle: 35),
        CanopyLeaf(x: 1.0, y: 1.04, size: 0.64, angle: -30),
    ]
    static let nearLeaves: [CanopyLeaf] = [
        CanopyLeaf(x: -0.04, y: 0.08, size: 0.5, angle: 125, near: true),
        CanopyLeaf(x: 1.04, y: 0.16, size: 0.44, angle: -120, near: true),
        CanopyLeaf(x: -0.02, y: 0.78, size: 0.46, angle: 70, near: true),
        CanopyLeaf(x: 1.02, y: 0.86, size: 0.5, angle: -60, near: true),
    ]

    /// Degrees from vertical, outermost pair first.
    static let leafletAngles: [Double] = [-84, -56, -28, 0, 28, 56, 84]
    static let leafletReach: [CGFloat] = [0.36, 0.62, 0.86, 1, 0.86, 0.62, 0.36]
    /// Half-width at the swell, as a share of the leaflet's length.
    static let leafletWidth: CGFloat = 0.13
    static let leafletSteps = 18
}

// MARK: - Stained glass

/// The pane over a picture scene on every screen past a tab root: the picture
/// is the tab's, and a pushed screen or a sheet reads its copy through glass
/// instead. A blur, a wash of the ground, and faint leading in the skin's
/// rule color.
struct StainedGlass: View {
    let tint: Color
    let lead: Color

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            tint.opacity(StainedGlassMetrics.wash)
            Canvas { context, size in
                context.stroke(Self.leading(in: size), with: .color(lead.opacity(StainedGlassMetrics.leadOpacity)), lineWidth: 0.75)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Art-deco leading: tall arched panes side by side, each split by a
    /// transom, the arch closing a fan of rays from the transom's middle.
    static func leading(in size: CGSize) -> Path {
        var path = Path()
        let panes = StainedGlassMetrics.panes
        let width = size.width / CGFloat(panes)
        let transom = size.height * StainedGlassMetrics.transom
        for i in 0 ... panes {
            let x = CGFloat(i) * width
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        path.move(to: CGPoint(x: 0, y: transom))
        path.addLine(to: CGPoint(x: size.width, y: transom))
        for i in 0 ..< panes {
            let center = CGPoint(x: (CGFloat(i) + 0.5) * width, y: transom)
            let radius = width / 2
            path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            for ray in 1 ..< StainedGlassMetrics.rays {
                let angle = Double.pi + Double.pi * Double(ray) / Double(StainedGlassMetrics.rays)
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
        }
        return path
    }
}

private enum StainedGlassMetrics {
    static let wash: Double = 0.45
    static let leadOpacity: Double = 0.18
    static let panes = 3
    /// The transom's height, as a share of the screen's.
    static let transom: CGFloat = 0.3
    static let rays = 6
}
