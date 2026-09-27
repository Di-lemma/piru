import SwiftUI
import Synchronization

// Hebi's invaders: a formation marching over the snake and a ship on the
// horizon shooting at it. In the backdrop it plays itself, replayed from a
// tape like `SnakeGame`; tapping the ship hands it to you (`ArcadeCabinet`).

// MARK: - Sprites

/// Pixel art as rows of `X`. Original designs, drawn for this skin — the
/// arcade's invaders are an idea, not a sprite sheet to copy.
nonisolated enum ArcadeSprite {
    /// Three kinds, two frames each, 8 × 6.
    static let invaderRows: [[[String]]] = [
        [
            ["..XXXX..", ".XXXXXX.", "XX.XX.XX", "XXXXXXXX", ".X.XX.X.", "X......X"],
            ["..XXXX..", ".XXXXXX.", "XX.XX.XX", "XXXXXXXX", "..X..X..", ".X.XX.X."],
        ],
        [
            ["X......X", ".XXXXXX.", "XX.XX.XX", ".XXXXXX.", "..X..X..", ".X....X."],
            ["..X..X..", "XXXXXXXX", "XX.XX.XX", ".XXXXXX.", ".X.XX.X.", "X......X"],
        ],
        [
            ["...XX...", "..XXXX..", ".X.XX.X.", "XXXXXXXX", "..X..X..", ".X.XX.X."],
            ["...XX...", "..XXXX..", ".X.XX.X.", "XXXXXXXX", ".X.XX.X.", "X.X..X.X"],
        ],
    ]
    /// The red raiders — a little plane nosing down, 1942's formation.
    static let raiderRows = [".X.X.X.", "..XXX..", "XXXXXXX", "..XXX..", "...X..."]
    static let shipRows = ["....X....", "...XXX...", "...XXX...", ".X.XXX.X.", "XXXXXXXXX", "XXXXXXXXX", "X..XXX..X"]
    static let wingmanRows = ["..X..", ".XXX.", "XXXXX", "X.X.X"]
    /// One mark per power-up, drawn inside its capsule.
    static let powRows: [ArcadePower: [String]] = [
        .wide: ["X...X", ".X.X.", "..X..", "..X.."],
        .wingmen: ["..X..", "X.X.X", "XXXXX", "X...X"],
        .bomb: [".XXX.", "XXXXX", "XXXXX", ".XXX."],
        .loop: [".XXX.", "X...X", "X...X", ".XXX."],
        .laser: ["..X..", "..X..", "..X..", ".XXX."],
        .charm: [".X.X.", "XXXXX", ".XXX.", "..X.."],
    ]

    /// Play mode's extra aliens, from the second wave on.
    /// Armored: takes two hits, and shows the first as a crack.
    static let shieldedRows: [[String]] = [
        ["..XXXXXX..", ".XXXXXXXX.", "XX.XXXX.XX", "XXXXXXXXXX", "X.XX..XX.X", "X.X....X.X", "..XX..XX.."],
        ["..XXXXXX..", ".XXXXXXXX.", "XX.XXXX.XX", "XXXXXXXXXX", "X.XX..XX.X", "..X....X..", ".X......X."],
    ]
    /// Drawn dark over a shielded alien that has taken its first hit.
    static let crackRows = ["....X.....", ".....X....", "....X.....", "...X.X....", "..X...X...", "..........", ".........."]
    /// Two aliens holding hands: shot, it comes apart into two minis. Split
    /// down the seam so each half can take its own color.
    static let splitterRows: [[String]] = [
        [".XX...XX.", "XXXX.XXXX", "X.XX.XX.X", "XXXX.XXXX", ".X.X.X.X.", "X.......X"],
        [".XX...XX.", "XXXX.XXXX", "X.XX.XX.X", "XXXX.XXXX", ".X.X.X.X.", ".X.....X."],
    ]
    static let miniRows: [[String]] = [
        [".X.X.", "XXXXX", "X.X.X", ".X.X."],
        [".X.X.", "XXXXX", "X.X.X", "X...X"],
    ]
    /// The bonus ship across the top: points, and always a POW.
    static let mothershipRows = [
        ".....XXXXXX.....", "...XXXXXXXXXX...", "..XXXXXXXXXXXX..", ".XX.XX.XX.XX.XX.",
        "XXXXXXXXXXXXXXXX", "..XXX..XX..XXX..", "...X........X...",
    ]

    static let pixel: CGFloat = 2
    /// The mothership's portholes, the gaps in its fourth row.
    static let mothershipLights: [CGPoint] = [3, 6, 9, 12].map { CGPoint(x: (CGFloat($0) - 8 + 0.5) * pixel, y: 0) }
    static let invaders: [[Path]] = invaderRows.map { $0.map { path($0, pixel: pixel) } }
    static let raider = path(raiderRows, pixel: pixel)
    static let ship = path(shipRows, pixel: pixel)
    static let wingman = path(wingmanRows, pixel: pixel)
    static let pows: [ArcadePower: Path] = powRows.mapValues { path($0, pixel: 1.6) }
    static let shielded: [Path] = shieldedRows.map { path($0, pixel: pixel) }
    static let crack = path(crackRows, pixel: pixel)
    /// Left and right halves, per frame. Each half is padded back to the
    /// full width so both stay centered on the same point.
    static let splitter: [(left: Path, right: Path)] = splitterRows.map { rows in
        let left = rows.map { String($0.enumerated().map { $0.offset < 4 ? $0.element : "." }) }
        let right = rows.map { String($0.enumerated().map { $0.offset > 4 ? $0.element : "." }) }
        return (path(left, pixel: pixel), path(right, pixel: pixel))
    }
    static let mini: [Path] = miniRows.map { path($0, pixel: pixel) }
    static let mothership = path(mothershipRows, pixel: pixel)

    /// Invader footprint, for hits.
    static let invaderSize = CGSize(width: 16, height: 12)

    /// The lit pixels as one path, centered on the origin — one fill per sprite.
    static func path(_ rows: [String], pixel: CGFloat) -> Path {
        let w = CGFloat(rows.map(\.count).max() ?? 0) * pixel, h = CGFloat(rows.count) * pixel
        var p = Path()
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == "X" {
                p.addRect(CGRect(x: CGFloat(x) * pixel - w / 2, y: CGFloat(y) * pixel - h / 2, width: pixel, height: pixel))
            }
        }
        return p
    }
}

/// Play mode's cast. The backdrop plays with `.plain` only.
nonisolated enum ArcadeAlien: Sendable {
    case plain
    case shielded
    case splitter
    case mini

    var hp: Int { self == .shielded ? 2 : 1 }
    /// How hard it sidesteps a bullet on a dive: armor is slow, minis quick.
    var agility: CGFloat {
        switch self {
        case .plain: 0.6
        case .shielded: 0.35
        case .splitter: 0.5
        case .mini: 0.8
        }
    }
    var points: Int {
        switch self {
        case .plain: 30
        case .shielded: 60
        case .splitter: 40
        case .mini: 25
        }
    }
}

nonisolated enum ArcadePower: CaseIterable, Sendable {
    case wide
    case wingmen
    case bomb
    case loop
    /// Six seconds of a beam that pierces the whole column above the ship.
    case laser
    /// Ten seconds of the snake on your side. Rare, and it will not cycle.
    case charm

    /// What a shot turns a capsule into, in order. Charm stays out of it: it
    /// is rare, and shooting your way to it would make it common.
    static let cycle: [ArcadePower] = [.wide, .wingmen, .loop, .laser, .bomb]

    var next: ArcadePower {
        guard let i = Self.cycle.firstIndex(of: self) else { return self }
        return Self.cycle[(i + 1) % Self.cycle.count]
    }

    static func random(_ rng: inout SeededRNG) -> ArcadePower {
        rng.unit() < 0.08 ? .charm : cycle[Int(rng.next() % UInt64(cycle.count))]
    }
}

// MARK: - The self-playing round

/// The backdrop's round: a 6 × 3 formation marching over the sky, and a ship
/// on the horizon that lines up under a column, fires, and sidesteps bombs.
/// A pure function of (size, step), simulated once per size into a tape the
/// way `SnakeGame` is, so a frame is one array read.
nonisolated struct InvaderTape {
    struct Frame {
        var shipX: CGFloat
        var origin: CGPoint
        /// Bit `row * cols + col` is a live invader.
        var alive: UInt32
        var shots: [CGPoint]
        var bombs: [CGPoint]
        var bursts: [Burst]
        /// Seconds since the ship was last hit; it blinks for one.
        var sinceHit: Double
        var march: Int
        var divers: [Diver]
    }

    /// An invader out of its slot: it swoops, dives at the ship, and if it
    /// misses comes back in over the top to take its place again.
    struct Diver {
        var p: CGPoint
        var v: CGVector
        var col: Int, row: Int
        var age: Double
        /// Swings out left (-1) or right (1) before it dives.
        var side: CGFloat
        var returning = false
        /// Play mode only: which alien this is and what it has left.
        var alien: ArcadeAlien = .plain
        var hp = 1
        /// Play mode: whether this one watches for bullets at all.
        var dodges = false
    }

    struct Burst {
        var at: CGPoint
        var age: Double
        var tint: Int
    }

    static let rate: Double = 30
    /// Sixty seconds, then the replay loops.
    static let tapeLength = 1_800
    static let cols = 6, rows = 3
    static let spacing = CGSize(width: 26, height: 20)
    static var formationWidth: CGFloat {
        CGFloat(cols - 1) * spacing.width + ArcadeSprite.invaderSize.width
    }

    let size: CGSize

    /// Where the ship patrols: just over the horizon, the floor's own line.
    static func shipY(in size: CGSize) -> CGFloat {
        size.height * 0.52 - 16
    }

    static func top(in size: CGSize) -> CGFloat {
        size.height * 0.1
    }

    /// The formation's pace: quicker as it thins, the way the arcade's did.
    static func marchSpeed(alive: UInt32, wave: Int = 1) -> CGFloat {
        let left = CGFloat(alive.nonzeroBitCount)
        return 20 + CGFloat(wave) * 4 + (CGFloat(cols * rows) - left) * 2.2
    }

    /// One step of a dive toward `prey`, shared with the playable round.
    /// Returns false when the diver is back in its slot.
    static func steer(_ d: inout Diver, toward prey: CGPoint, slot: CGPoint, bottom: CGFloat, dt: Double, speed: CGFloat = 1) -> Bool {
        d.age += dt
        if d.returning {
            let dx = slot.x - d.p.x, dy = slot.y - d.p.y
            let dist = hypot(dx, dy)
            if dist < 4 { return false }
            let step = min(dist, 170 * speed * dt)
            d.v = CGVector(dx: dx / dist * 170 * speed, dy: dy / dist * 170 * speed)
            d.p.x += dx / dist * step
            d.p.y += dy / dist * step
            return true
        }
        if d.age < 0.7 {
            // The peel-off: a half loop out to the side, rising a little.
            let a = d.age / 0.7 * .pi
            d.v = CGVector(dx: d.side * 110 * speed * cos(a * 0.5), dy: (-60 * cos(a) + 40) * speed)
        } else {
            // The dive: down hard, bending toward the ship.
            let pull = max(-170, min(170, (prey.x - d.p.x) * 2.6)) * speed
            d.v = CGVector(dx: d.v.dx + (pull - d.v.dx) * min(1, 5 * dt), dy: 150 * speed)
        }
        d.p.x += d.v.dx * dt
        d.p.y += d.v.dy * dt
        if d.p.y > bottom {
            // Missed: round the back of the screen and in over the top.
            d.returning = true
            d.p = CGPoint(x: slot.x, y: -14)
        }
        return true
    }

    static func invaderCenter(origin: CGPoint, col: Int, row: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(col) * spacing.width + ArcadeSprite.invaderSize.width / 2, y: origin.y + CGFloat(row) * spacing.height)
    }

    /// The step on screen at `time`, on the backdrop's clock.
    static func step(at time: TimeInterval) -> Int {
        Int((time * rate).rounded(.down)) % tapeLength
    }

    private struct TapeKey: Hashable { let w: Int, h: Int }
    private static let tapes = Mutex<[TapeKey: [Frame]]>([:])

    func frame(atStep target: Int) -> Frame {
        let key = TapeKey(w: Int(size.width), h: Int(size.height))
        let step = max(0, min(target, Self.tapeLength - 1))
        if let tape = Self.tapes.withLock({ $0[key] }) { return tape[step] }
        let tape = simulateTape()
        Self.tapes.withLock { $0[key] = tape }
        return tape[step]
    }

    func simulateTape() -> [Frame] {
        var rng = SeededRNG(seed: 0x14A5E)
        let dt = 1 / Self.rate
        let shipY = Self.shipY(in: size)
        let full: UInt32 = (1 << UInt32(Self.cols * Self.rows)) - 1
        let fresh = CGPoint(x: (size.width - Self.formationWidth) / 2, y: Self.top(in: size))
        var f = Frame(shipX: size.width / 2, origin: fresh, alive: full, shots: [], bombs: [], bursts: [], sinceHit: 9, march: 0, divers: [])
        var dir: CGFloat = 1
        var cooldown = 0.0
        var marchClock = 0.0
        var nextDive = 2.5
        var clock = 0.0
        // What the ship is after: a column, or the first diver. Re-picked
        // every second or two, not always the nearest, so it roams.
        var focus = 0
        var chasesDiver = false
        // Some focus spells the ship holds its line against a diver and
        // shoots it, rather than dodging — so a dive can land.
        var holds = false
        var refocusAt = 0.0
        var shipV: CGFloat = 0
        var tape: [Frame] = []
        tape.reserveCapacity(Self.tapeLength)
        func bit(_ col: Int, _ row: Int) -> UInt32 { 1 << UInt32(row * Self.cols + col) }
        while tape.count < Self.tapeLength {
            tape.append(f)
            clock += dt
            // March, stepping down at each wall, faster as it thins.
            let speed = Self.marchSpeed(alive: f.alive)
            f.origin.x += dir * speed * dt
            if f.origin.x < 8 || f.origin.x + Self.formationWidth > size.width - 8 {
                dir = -dir
                f.origin.x += dir * speed * dt
                f.origin.y += 14
            }
            marchClock += dt
            if marchClock > max(0.2, 0.5 - Double(18 - f.alive.nonzeroBitCount) * 0.02) { marchClock = 0; f.march ^= 1 }
            // A new formation when this one is gone or has come down on the ship.
            if (f.alive == 0 && f.divers.isEmpty) || f.origin.y + CGFloat(Self.rows) * Self.spacing.height > shipY - 50 {
                f.origin = fresh
                f.alive = full
                f.divers.removeAll()
                dir = 1
            }
            // Dives: one invader every few seconds peels off and goes for the ship.
            if clock >= nextDive, f.divers.count < 2 {
                let live = (0 ..< Self.cols * Self.rows).filter { f.alive & (1 << UInt32($0)) != 0 }
                if !live.isEmpty {
                    let slot = live[Int(rng.next() % UInt64(live.count))]
                    let col = slot % Self.cols, row = slot / Self.cols
                    f.alive &= ~bit(col, row)
                    let at = Self.invaderCenter(origin: f.origin, col: col, row: row)
                    f.divers.append(Diver(p: at, v: .zero, col: col, row: row, age: 0, side: at.x < size.width / 2 ? -1 : 1))
                }
                nextDive = clock + 2.2 + rng.unit() * 2.5
            }
            let ship = CGPoint(x: f.shipX, y: shipY)
            f.divers = f.divers.compactMap { d in
                var d = d
                let slot = Self.invaderCenter(origin: f.origin, col: d.col, row: d.row)
                guard Self.steer(&d, toward: ship, slot: slot, bottom: shipY + 40, dt: dt) else {
                    f.alive |= bit(d.col, d.row)
                    return nil
                }
                return d
            }

            // The ship. Lead the target: a shot takes a while to climb, and the
            // formation keeps marching while it does.
            if clock >= refocusAt {
                refocusAt = clock + 1 + rng.unit() * 1.6
                chasesDiver = !f.divers.isEmpty && rng.unit() < 0.45
                holds = rng.unit() < 0.4
                focus = Int(rng.next() % UInt64(Self.cols))
            }
            var aim: CGFloat?
            if chasesDiver, let d = f.divers.first(where: { !$0.returning && $0.p.y < shipY - 40 }) {
                let t = (shipY - 10 - d.p.y) / 320
                aim = d.p.x + d.v.dx * t
            } else {
                // The focused column, or the next live one along.
                for k in 0 ..< Self.cols {
                    let col = (focus + k) % Self.cols
                    if let row = (0 ..< Self.rows).reversed().first(where: { f.alive & bit(col, $0) != 0 }) {
                        let c = Self.invaderCenter(origin: f.origin, col: col, row: row)
                        let t = (shipY - 10 - c.y) / 320
                        aim = c.x + dir * speed * t
                        break
                    }
                }
            }
            var target = aim.map { max(16, min(size.width - 16, $0)) } ?? size.width / 2 + sin(clock * 0.7) * size.width * 0.3
            // Get out from under bombs and away from anything diving in low.
            if let threat = f.bombs.first(where: { abs($0.x - f.shipX) < 18 && $0.y > shipY - 120 && $0.y < shipY }) {
                target = f.shipX + (threat.x < f.shipX ? 50 : -50)
            } else if !holds, let d = f.divers.first(where: { !$0.returning && abs($0.p.x - f.shipX) < 44 && $0.p.y > shipY - 90 }) {
                target = f.shipX + (d.p.x < f.shipX ? 70 : -70)
            }
            // Accelerates and brakes, rather than sliding at one pace.
            let want = max(-160, min(160, (target - f.shipX) * 4))
            shipV += (want - shipV) * min(1, 8 * dt)
            f.shipX = max(16, min(size.width - 16, f.shipX + shipV * dt))
            cooldown -= dt
            if cooldown <= 0, let aim, abs(aim - f.shipX) < 6, f.shots.count < 3 {
                f.shots.append(CGPoint(x: f.shipX, y: shipY - 10))
                cooldown = 0.32
            }
            // Shots up, bombs down.
            f.shots = f.shots.map { CGPoint(x: $0.x, y: $0.y - 320 * dt) }.filter { $0.y > 0 }
            f.bombs = f.bombs.map { CGPoint(x: $0.x, y: $0.y + 120 * dt) }.filter { $0.y < shipY + 20 }
            f.bursts = f.bursts.map { Burst(at: $0.at, age: $0.age + dt, tint: $0.tint) }.filter { $0.age < 0.4 }
            f.sinceHit += dt
            // Hits.
            var spent: [Int] = []
            for (i, shot) in f.shots.enumerated() {
                if let d = f.divers.firstIndex(where: { abs(shot.x - $0.p.x) < 10 && abs(shot.y - $0.p.y) < 9 }) {
                    f.bursts.append(Burst(at: f.divers[d].p, age: 0, tint: f.divers[d].row))
                    f.divers.remove(at: d)
                    spent.append(i)
                    continue
                }
                hit: for row in 0 ..< Self.rows {
                    for col in 0 ..< Self.cols where f.alive & bit(col, row) != 0 {
                        let c = Self.invaderCenter(origin: f.origin, col: col, row: row)
                        if abs(shot.x - c.x) < 9, abs(shot.y - c.y) < 8 {
                            f.alive &= ~bit(col, row)
                            f.bursts.append(Burst(at: c, age: 0, tint: row))
                            spent.append(i)
                            break hit
                        }
                    }
                }
            }
            for i in spent.reversed() { f.shots.remove(at: i) }
            if let i = f.bombs.firstIndex(where: { abs($0.x - f.shipX) < 9 && abs($0.y - shipY) < 8 }) {
                f.bombs.remove(at: i)
                f.sinceHit = 0
            }
            // A diver that reaches the ship takes a bite and is spent.
            if let d = f.divers.firstIndex(where: { !$0.returning && abs($0.p.x - f.shipX) < 14 && abs($0.p.y - shipY) < 12 }) {
                f.bursts.append(Burst(at: f.divers[d].p, age: 0, tint: f.divers[d].row))
                f.divers.remove(at: d)
                f.sinceHit = 0
            }
            // A bomb from the lowest invader of a random column.
            if rng.unit() < 0.018 {
                let col = Int(rng.next() % UInt64(Self.cols))
                if let row = (0 ..< Self.rows).reversed().first(where: { f.alive & bit(col, $0) != 0 }) {
                    f.bombs.append(Self.invaderCenter(origin: f.origin, col: col, row: row))
                }
            }
        }
        return tape
    }
}

// MARK: - Drawing

/// The pieces both the backdrop and the cabinet draw, so a ship you pick up is
/// the same ship that was playing.
nonisolated enum ArcadeDraw {
    static func invaderTint(_ arcade: SkinArcade, row: Int) -> Color {
        [arcade.invader, arcade.wall, arcade.border][row % 3]
    }

    static func sprite(_ path: Path, at p: CGPoint, color: Color, glow: Bool, rotation: Angle = .zero, scale: CGFloat = 1, in context: inout GraphicsContext) {
        if glow {
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - 14 * scale, y: p.y - 14 * scale, width: 28 * scale, height: 28 * scale)),
                with: .radialGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0)]), center: p, startRadius: 0, endRadius: 14 * scale),
            )
        }
        let t = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: rotation.radians).scaledBy(x: scale, y: scale)
        context.fill(path.applying(t), with: .color(color))
    }

    static func ship(at p: CGPoint, arcade: SkinArcade, time: Double, glow: Bool, rotation: Angle = .zero, scale: CGFloat = 1, in context: inout GraphicsContext) {
        // The engine: two pixels of the snake's cyan, flickering.
        let flame: CGFloat = sin(time * 40) > 0 ? 5 : 3
        context.fill(Path(CGRect(x: p.x - 1.5, y: p.y + 7, width: 3, height: flame)), with: .color(arcade.snake.opacity(0.9)))
        sprite(ArcadeSprite.ship, at: p, color: arcade.star, glow: glow, rotation: rotation, scale: scale, in: &context)
    }

    static func shot(at p: CGPoint, color: Color, in context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: p.x - 1, y: p.y - 4, width: 2, height: 8)), with: .color(color))
    }

    /// An invader's bomb: a zigzag, the arcade's own shorthand.
    static func bomb(at p: CGPoint, color: Color, time: Double, in context: inout GraphicsContext) {
        let flip: CGFloat = sin(time * 20 + p.y) > 0 ? 1 : -1
        var z = Path()
        z.move(to: CGPoint(x: p.x, y: p.y - 5))
        z.addLine(to: CGPoint(x: p.x + 2 * flip, y: p.y - 2))
        z.addLine(to: CGPoint(x: p.x - 2 * flip, y: p.y + 1))
        z.addLine(to: CGPoint(x: p.x, y: p.y + 4))
        context.stroke(z, with: .color(color), lineWidth: 1.5)
    }

    /// Eight pixels thrown outward, fading over `life`.
    static func burst(at p: CGPoint, age: Double, life: Double = 0.4, color: Color, reach: CGFloat = 14, in context: inout GraphicsContext) {
        let u = age / life
        guard u < 1 else { return }
        let r = reach * CGFloat(0.3 + u)
        for k in 0 ..< 8 {
            let a = Double(k) / 8 * 2 * .pi
            let q = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r)
            context.fill(Path(CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3)), with: .color(color.opacity(1 - u)))
        }
    }
}

nonisolated extension SceneRenderer {
    /// The self-playing round over the arcade's sky.
    func drawInvaders(_ arcade: SkinArcade, in context: inout GraphicsContext) {
        let tape = InvaderTape(size: size)
        let f = tape.frame(atStep: InvaderTape.step(at: time))
        let shift = parallax(0.6)
        let shipY = InvaderTape.shipY(in: size)
        func at(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + shift.width, y: p.y + shift.height) }
        for row in 0 ..< InvaderTape.rows {
            let tint = ArcadeDraw.invaderTint(arcade, row: row)
            for col in 0 ..< InvaderTape.cols where f.alive & (1 << UInt32(row * InvaderTape.cols + col)) != 0 {
                let c = InvaderTape.invaderCenter(origin: f.origin, col: col, row: row)
                ArcadeDraw.sprite(ArcadeSprite.invaders[row % 3][f.march], at: at(c), color: tint.opacity(0.85), glow: false, in: &context)
            }
        }
        for d in f.divers {
            ArcadeDraw.sprite(ArcadeSprite.invaders[d.row % 3][Int(d.age * 6) % 2], at: at(d.p), color: ArcadeDraw.invaderTint(arcade, row: d.row).opacity(0.9), glow: false, in: &context)
        }
        for s in f.shots { ArcadeDraw.shot(at: at(s), color: arcade.star, in: &context) }
        for b in f.bombs { ArcadeDraw.bomb(at: at(b), color: arcade.raider, time: time, in: &context) }
        for b in f.bursts { ArcadeDraw.burst(at: at(b.at), age: b.age, color: ArcadeDraw.invaderTint(arcade, row: b.tint), in: &context) }
        // Blinks for a second after a hit.
        if f.sinceHit > 1 || Int(f.sinceHit * 10) % 2 == 0 {
            let ship = at(CGPoint(x: f.shipX, y: shipY))
            // The invitation to tap it: a breathing halo, and a ring that
            // goes out from it every four seconds. In light mode too.
            let breath = 0.5 + 0.5 * sin(time * 2.4)
            bloom(arcade.snake, at: ship, radius: 26, alpha: (dark ? 0.35 : 0.25) + 0.2 * breath, in: &context)
            let pulse = (time / 4).truncatingRemainder(dividingBy: 1)
            if pulse < 0.4 {
                let u = pulse / 0.4
                let r = 12 + 22 * u
                context.stroke(Path(ellipseIn: CGRect(x: ship.x - r, y: ship.y - r, width: r * 2, height: r * 2)), with: .color(arcade.snake.opacity(0.6 * (1 - u))), lineWidth: 1.5)
            }
            ArcadeDraw.ship(at: ship, arcade: arcade, time: time, glow: false, in: &context)
        }
    }
}
