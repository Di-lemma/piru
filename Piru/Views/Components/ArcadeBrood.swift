import SwiftUI

/// Bitjelly's brood: the four mini-jellies it summons in the boss fight, in
/// its own colors. Each is two frames, relaxed and contracted; only the lower
/// rows draw in, so the dome holds its shape. Tendrils are not in the rows —
/// they root on the lit cells of whichever hem is showing, so they never come
/// away from the bell.
nonisolated enum BroodKind: CaseIterable, Sendable {
    /// Bitjelly's own, small: nearly still, then a lunge on every pulse.
    case bitling
    /// Pink, quick, in threes; weaves as it comes.
    case pip
    /// Slow; fires an orb straight down on each pulse. Two hits.
    case lantern
    /// Flies a saucer: hovers over the ship and switches on a tractor beam.
    case saucer

    /// `1` bell, `2` a light, `3` the highlight (the saucer's glass), `L` a
    /// marquee light, `e` an eye. The last row is the hem.
    var rows: [[String]] {
        switch self {
        case .bitling: [
                ["..11111..", ".1133311.", "121e1e121", "111111111", "111111111", "1.1.1.1.1"],
                ["..11111..", ".1133311.", "121e1e121", ".1111111.", ".1111111.", ".1.1.1.1."],
            ]
        case .pip: [
                ["..111..", ".13311.", "11e1e11", "1111111", "1.1.1.1"],
                ["..111..", ".13311.", "11e1e11", ".11111.", ".1.1.1."],
            ]
        case .lantern: [
                ["..111..", ".13231.", "11e1e11", "1111111", "1111111", "1111111", "1.1.1.1"],
                ["..111..", ".13231.", "11e1e11", "1111111", ".11111.", ".11111.", ".1.1.1."],
            ]
        case .saucer: [
                ["....333....", "...3e3e3...", "..1111111..", "1L1L1L1L1L1", ".111111111.", "..1.1.1.1.."],
                ["....333....", "...3e3e3...", "..1111111..", "1L1L1L1L1L1", "..1111111..", "...1.1.1..."],
            ]
        }
    }

    var period: Double {
        switch self {
        case .bitling: 1.6
        case .pip: 1.1
        case .lantern: 2.2
        case .saucer: 2.0
        }
    }

    var hp: Int { self == .lantern || self == .saucer ? 2 : 1 }
    var points: Int {
        switch self {
        case .bitling: 40
        case .pip: 30
        case .lantern: 80
        case .saucer: 150
        }
    }

    var strands: (count: Int, length: Int) {
        switch self {
        case .bitling: (3, 3)
        case .pip: (2, 3)
        case .lantern: (3, 5)
        case .saucer: (3, 3)
        }
    }

    /// Half the hit box, in points.
    var reach: CGSize {
        let r = rows[0]
        return CGSize(width: CGFloat(r[0].count) * ArcadeSprite.pixel / 2 + 1, height: CGFloat(r.count) * ArcadeSprite.pixel / 2 + 2)
    }

    /// The pixels of each frame, one path per color key, built once.
    static let paths: [BroodKind: [[Character: Path]]] = Dictionary(uniqueKeysWithValues: allCases.map { kind in
        (kind, kind.rows.map { rows in
            var byKey: [Character: Path] = [:]
            let px = ArcadeSprite.pixel
            let w = CGFloat(rows[0].count) * px, h = CGFloat(rows.count) * px
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() where c != "." && c != "L" {
                    byKey[c, default: Path()].addRect(CGRect(x: CGFloat(x) * px - w / 2, y: CGFloat(y) * px - h / 2, width: px, height: px))
                }
            }
            return byKey
        })
    })

    /// How hard the bell squeezes, 0 … 1: a quick contraction, then rest.
    func contraction(at t: Double, phase: Double) -> Double {
        let u = ((t / period + phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        return u < 0.3 ? sin(u / 0.3 * .pi) : 0
    }
}

/// One of the brood in play.
nonisolated struct BroodJelly: Sendable {
    let kind: BroodKind
    var p: CGPoint
    var v: CGVector
    var phase: Double
    var hp: Int
    var firedAt = -9.0
    /// Saucer: beaming until this time; free to beam again after `restUntil`.
    var beamUntil = -1.0
    var restUntil = 0.0
    /// A beam takes one wingman at most.
    var tookWingman = false
    /// Whether this one sidesteps bullets; only some do.
    var dodges = false
    var flash = 0.0

    init(_ kind: BroodKind, at p: CGPoint, v: CGVector = .zero, phase: Double) {
        self.kind = kind
        self.p = p
        self.v = v
        self.phase = phase
        hp = kind.hp
    }

    func beaming(at t: Double) -> Bool { t < beamUntil }

    /// The saucer's beam: a cone from its underside to the bottom of the field.
    func inBeam(_ q: CGPoint, bottom: CGFloat) -> Bool {
        guard q.y > p.y + 8 else { return false }
        let f = (q.y - p.y - 8) / max(1, bottom - p.y - 8)
        return abs(q.x - p.x) < 8 + 26 * f
    }

    /// One step of how it swims. Returns an orb to fire, if it lets one go.
    mutating func swim(toward ship: CGPoint, hover: CGFloat, t: Double, dt: Double) -> CGPoint? {
        let c = kind.contraction(at: t, phase: phase)
        let dx = ship.x - p.x
        flash = max(0, flash - dt)
        var orb: CGPoint?
        switch kind {
        case .bitling:
            // Drifts, then lunges at the ship on each contraction.
            v.dx += (CGFloat(dx > 0 ? 1 : -1) * 90 * c - v.dx * 0.9) * dt * 3
            v.dy = 18 + 150 * c
        case .pip:
            v.dx = max(-120, min(120, dx * 0.9)) + CGFloat(sin(t * 5 + phase * 6)) * 90
            v.dy = 95
        case .lantern:
            v.dx = max(-40, min(40, dx * 0.3))
            v.dy = 30 + 30 * c
            if c > 0.9, t - firedAt > 0.8 {
                firedAt = t
                orb = CGPoint(x: p.x, y: p.y + 10)
            }
        case .saucer:
            v = .zero
            if p.y < hover { v.dy = 60 }
            if !beaming(at: t) {
                v.dx = max(-110, min(110, dx * 1.4))
                if abs(dx) < 6, t > restUntil, p.y >= hover {
                    beamUntil = t + 1.6
                    restUntil = t + 3.6
                    tookWingman = false
                }
            }
        }
        p.x += v.dx * dt
        p.y += v.dy * dt
        return orb
    }
}

nonisolated extension ArcadeDraw {
    static func brood(_ j: BroodJelly, t: Double, bottom: CGFloat, marquee: [Color], lure: Color, in context: inout GraphicsContext) {
        let kind = j.kind
        let c = kind.contraction(at: t, phase: j.phase)
        let frame = c > 0.45 ? 1 : 0
        let rows = kind.rows[frame]
        let px = ArcadeSprite.pixel
        let w = CGFloat(rows[0].count) * px, h = CGFloat(rows.count) * px
        let left = j.p.x - w / 2, top = j.p.y - h / 2
        let (body, light, strand): (Color, Color, Color) = switch kind {
        case .bitling: (BroodPalette.bell, BroodPalette.rim, BroodPalette.rim)
        case .pip: (BroodPalette.pink, BroodPalette.top, BroodPalette.pink)
        case .lantern: (BroodPalette.rim, lure, BroodPalette.rim)
        case .saucer: (BroodPalette.bell, BroodPalette.rim, BroodPalette.rim)
        }

        if kind == .saucer, j.beaming(at: t) {
            // The tractor beam, flickering, with rungs running down it.
            var cone = Path()
            cone.move(to: CGPoint(x: j.p.x - 8, y: j.p.y + 8))
            cone.addLine(to: CGPoint(x: j.p.x + 8, y: j.p.y + 8))
            cone.addLine(to: CGPoint(x: j.p.x + 34, y: bottom))
            cone.addLine(to: CGPoint(x: j.p.x - 34, y: bottom))
            cone.closeSubpath()
            let flick = 0.24 + 0.06 * sin(t * 30)
            context.fill(cone, with: .linearGradient(Gradient(colors: [BroodPalette.rim.opacity(flick), BroodPalette.rim.opacity(0)]), startPoint: CGPoint(x: 0, y: j.p.y), endPoint: CGPoint(x: 0, y: bottom)))
            for r in 0 ..< 5 {
                let f = (t * 0.9 + Double(r) * 0.2).truncatingRemainder(dividingBy: 1)
                let y = j.p.y + 10 + CGFloat(f) * (bottom - j.p.y - 10)
                let half = 8 + 26 * CGFloat(f)
                context.fill(Path(CGRect(x: j.p.x - half, y: y, width: half * 2, height: 1.5)), with: .color(BroodPalette.rim.opacity(0.5 * (1 - f))))
            }
        }

        let paths = BroodKind.paths[kind]![frame]
        let at = CGAffineTransform(translationX: j.p.x, y: j.p.y)
        if let p = paths["1"] { context.fill(p.applying(at), with: .color(j.flash > 0 ? .white : body)) }
        if let p = paths["3"] { context.fill(p.applying(at), with: .color(BroodPalette.top.opacity(kind == .saucer ? 0.7 : 0.85))) }
        if let p = paths["2"] { context.fill(p.applying(at), with: .color(light)) }
        if let p = paths["e"] { context.fill(p.applying(at), with: .color(BroodPalette.eye)) }
        // The saucer's marquee runs left to right.
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "L" {
                let k = ((x - Int(t * 8 + j.phase * 4)) % marquee.count + marquee.count) % marquee.count
                context.fill(Path(CGRect(x: left + CGFloat(x) * px, y: top + CGFloat(y) * px, width: px, height: px)), with: .color(marquee[k]))
            }
        }
        // Lantern's forehead light: a halo that swells on each pulse.
        if kind == .lantern, let ry = rows.firstIndex(where: { $0.contains("2") }), let rx = rows[ry].firstIndex(of: "2") {
            let lx = left + (CGFloat(rows[ry].distance(from: rows[ry].startIndex, to: rx)) + 0.5) * px
            let ly = top + (CGFloat(ry) + 0.5) * px
            let glow = 0.25 + 0.45 * pow(max(c, 0.5 + 0.5 * sin(t * 3 + j.phase * 6)), 2)
            context.fill(
                Path(ellipseIn: CGRect(x: lx - px * 3.2, y: ly - px * 3.2, width: px * 6.4, height: px * 6.4)),
                with: .radialGradient(Gradient(colors: [lure.opacity(glow), lure.opacity(0)]), center: CGPoint(x: lx, y: ly), startRadius: 0, endRadius: px * 3.2),
            )
        }
        // Tendrils from the lit cells of this hem, each pixel at most one
        // column from the one above.
        let hem = Array(rows[rows.count - 1])
        let lit = hem.indices.filter { hem[$0] != "." }
        guard !lit.isEmpty else { return }
        let (count, length) = kind.strands
        let roots = count >= lit.count ? lit : (0 ..< count).map { lit[Int((Double($0) * Double(lit.count - 1) / Double(max(1, count - 1))).rounded())] }
        var tendrils: [Path] = Array(repeating: Path(), count: length)
        for (i, root) in roots.enumerated() {
            var col = root
            for k in 1 ... length {
                let want = Double(root) + sin(t * 2.6 - Double(k) * 0.9 + Double(i) * 1.7 + j.phase * 6) * min(1.6, Double(k) * 0.55)
                if want > Double(col) + 0.5 { col += 1 } else if want < Double(col) - 0.5 { col -= 1 }
                tendrils[k - 1].addRect(CGRect(x: left + CGFloat(col) * px, y: top + CGFloat(rows.count - 1 + k) * px, width: px, height: px))
            }
        }
        for (k, path) in tendrils.enumerated() {
            context.fill(path, with: .color(strand.opacity(max(0.25, 0.95 - Double(k) * (0.7 / Double(length))))))
        }
    }
}
