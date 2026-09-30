import SwiftUI

// The round's parts as plain values, and one frame of it as a value that
// draws itself. The round (`ArcadeGame`) lives on the main actor; the
// backdrop's canvas draws off it, so what crosses over is a snapshot.

// MARK: - Parts

nonisolated struct ArcadeShot: Sendable { var p: CGPoint; var vx: CGFloat }
nonisolated struct ArcadeBomb: Sendable {
    var p: CGPoint
    var v: CGVector
    var orb = false
    /// How fast its heading turns, in radians a second: furious Bitjelly's
    /// flowers curl.
    var curl = 0.0
}
nonisolated struct ArcadePow: Sendable { var p: CGPoint; var kind: ArcadePower; var born: Double; var changedAt = -9.0 }
nonisolated struct ArcadeBurst: Sendable { var p: CGPoint; var age: Double; var life: Double; var color: Color; var reach: CGFloat }
/// The bonus ship across the top, from the second wave.
nonisolated struct ArcadeMothership: Sendable { var p: CGPoint; var vx: CGFloat; var hp = 3; var flash = 0.0 }

/// Five red raiders crossing on a wave; down all five and one drops a POW.
nonisolated struct ArcadeRaid: Sendable {
    var start: Double
    var fromLeft: Bool
    var alive = [Bool](repeating: true, count: 5)
    var fired = [Bool](repeating: false, count: 5)

    func position(_ i: Int, at clock: Double, top: CGFloat, width: CGFloat) -> (CGPoint, Double) {
        let t = clock - start - Double(i) * 0.3
        let x = fromLeft ? -20 + 110 * t : width + 20 - 110 * t
        return (CGPoint(x: x, y: top + 40 + 50 * sin(t * 2.4)), t)
    }
}

/// Every tenth wave: Bitjelly, from rocuronium, the size of the formation.
nonisolated struct ArcadeBoss: Sendable {
    var p: CGPoint
    var hp: Int
    let maxHP: Int
    let start: Double
    var beat = 0
    var aimedAt = 0.0
    var flash = 0.0
    var dyingAt: Double?
    var spiralAt = 0.0
    var summonAt = 0.0
    /// You came with everything (Wide at five-way and both wingmen), so it
    /// goes red and fills the screen. Only while you still have it all.
    var furious = false
    /// The health fractions still owed a POW, highest first.
    var drops: [Double] = [0.75, 0.5, 0.25]

    static let scale: CGFloat = 2.2
    /// Bitjelly's own beat, so the rings go out on its contractions.
    static let beatPeriod = JellySpecies.bitjelly.beat.period
    static let motion = JellyMotion(period: beatPeriod, amp: JellySpecies.bitjelly.beat.amp, sway: 0, swayPeriod: 1, rise: 0, phase: 0)
}

// MARK: - Snake

/// The snake on its 12pt grid. It chases a goal with the three turns the real
/// game allows and never reverses. It may roam the whole screen, so nothing
/// but its own body can box it in: a wall always leaves a free turn along it.
/// When its body has closed every way out it crashes into itself, and a new
/// snake drops in at the top. That is the only way it ever resets.
nonisolated struct ArcadeSnake {
    typealias Cell = (x: Int, y: Int)

    static let cell: CGFloat = 12
    static let startLength = 6, maxLength = 48

    var body: [Cell]
    var dir: Cell = (1, 0)
    var food: Cell?
    /// Where the fruit after this one lands, rolled ahead so the round can
    /// mark the spot before anything is there to shoot.
    var nextFood: Cell?
    var growth = 0
    let cols: Int, rows: Int
    /// The fruit lands in the sky, above the horizon.
    let skyRows: Int

    enum Outcome { case moved, ate, crashed(at: CGPoint) }

    init(cols: Int, rows: Int, skyRows: Int) {
        self.cols = cols
        self.rows = rows
        self.skyRows = skyRows
        body = Self.fresh(cols: cols, row: skyRows / 2)
    }

    static func fresh(cols: Int, row: Int) -> [Cell] {
        (0 ..< startLength).map { (x: cols / 2 - $0, y: row) }
    }

    static func center(_ c: Cell) -> CGPoint {
        CGPoint(x: (CGFloat(c.x) + 0.5) * cell, y: (CGFloat(c.y) + 0.5) * cell)
    }

    var head: CGPoint { Self.center(body[0]) }

    func inside(_ c: Cell) -> Bool {
        c.x >= 0 && c.x < cols && c.y >= 0 && c.y < rows
    }

    /// Its own body in the way; the tail cell frees up unless this move eats.
    func blocked(_ c: Cell) -> Bool {
        let eats = food.map { $0 == c } ?? false
        return body.dropLast(eats || growth > 0 ? 0 : 1).contains { $0 == c }
    }

    mutating func step(toward goal: Cell, rng: inout SeededRNG) -> Outcome {
        let h = body[0]
        var best: (Cell, Int)?
        let turns: [Cell] = [dir, (-dir.y, dir.x), (dir.y, -dir.x)]
        for d in turns {
            let next: Cell = (h.x + d.x, h.y + d.y)
            guard inside(next), !blocked(next) else { continue }
            // A little waver, so the path reads as play rather than a ruler.
            let score = abs(next.x - goal.x) + abs(next.y - goal.y) + (rng.unit() < 0.1 ? 2 : 0)
            if best == nil || score < best!.1 { best = (d, score) }
        }
        guard let move = best?.0 else {
            let at = head
            body = Self.fresh(cols: cols, row: 1)
            dir = (1, 0)
            return .crashed(at: at)
        }
        dir = move
        let next: Cell = (h.x + move.x, h.y + move.y)
        body.insert(next, at: 0)
        var outcome = Outcome.moved
        if let f = food, f == next {
            growth += 1
            food = nil
            outcome = .ate
        }
        if growth > 0, body.count <= Self.maxLength {
            growth -= 1
        } else {
            body.removeLast()
        }
        return outcome
    }

    /// Serves the fruit that was waiting (unless the body has since moved
    /// onto its spot) and rolls the one after it.
    mutating func placeFood(_ rng: inout SeededRNG) {
        let waiting = nextFood.flatMap { c in body.contains { $0 == c } ? nil : c }
        let served = waiting ?? roll(&rng, avoiding: nil)
        food = served
        nextFood = roll(&rng, avoiding: served)
    }

    private func roll(_ rng: inout SeededRNG, avoiding other: Cell?) -> Cell {
        for _ in 0 ..< 64 {
            let c: Cell = (Int(rng.next() % UInt64(max(cols, 1))), Int(rng.next() % UInt64(max(skyRows, 1))))
            if !body.contains(where: { $0 == c }), other.map({ $0 != c }) ?? true { return c }
        }
        return (0, 0)
    }
}

// MARK: - A frame

/// One frame of a round, as values: what `ArcadeGame` hands the canvas.
nonisolated struct ArcadeScene: Sendable {
    struct Alien: Sendable { var alien: ArcadeAlien; var hp: Int; var tint: Int; var frame: Int; var p: CGPoint }

    let arcade: SkinArcade
    let size: CGSize
    let clock: Double
    let top: CGFloat
    /// The idle round, with the pilot flying: the ship wears the halo that
    /// asks to be tapped.
    let idle: Bool
    let isOver: Bool

    let snake: [ArcadeSnake.Cell]
    let food: ArcadeSnake.Cell?
    let nextFood: ArcadeSnake.Cell?
    let foodAt: Double
    let egg: (at: Double, p: CGPoint)?
    let charmedUntil: Double

    let aliens: [Alien]
    let brood: [BroodJelly]
    let mothership: ArcadeMothership?
    let raiders: [CGPoint]
    let pows: [ArcadePow]
    let shots: [ArcadeShot]
    let bombs: [ArcadeBomb]
    let bursts: [ArcadeBurst]
    let boss: ArcadeBoss?

    let ship: CGPoint
    let wingmen: [CGPoint]
    let shields: Int
    let shield: Int
    let rollStart: Double
    let invulnerableUntil: Double
    let laserUntil: Double
    let wideLevel: Int
    /// Where each beam starts while the laser is on: the nose, then the wingmen.
    let beams: [CGPoint]
    let beamReach: CGFloat

    private var rolling: Bool { clock - rollStart < 1.0 }
    private var charmed: Bool { clock < charmedUntil }

    func draw(in context: inout GraphicsContext, dark: Bool) {
        let t = clock
        // The fruit's blast shakes the whole field for half a second.
        // Negative until the fruit is shot, so nothing below fires early.
        let sinceEgg = egg.map { t - $0.at } ?? -1
        if sinceEgg >= 0, sinceEgg < 0.5 {
            let a = 6 * (1 - sinceEgg / 0.5)
            context.translateBy(x: a * sin(t * 90), y: a * cos(t * 73))
        }
        drawSnake(in: &context, sinceEgg: sinceEgg, dark: dark)
        for a in aliens { drawAlien(a, in: &context) }
        let marquee = [arcade.snake, arcade.border, arcade.pow]
        for j in brood {
            ArcadeDraw.brood(j, t: t, bottom: size.height, marquee: marquee, lure: arcade.pow, in: &context)
        }
        if let m = mothership {
            ArcadeDraw.sprite(ArcadeSprite.mothership, at: m.p, color: m.flash > 0 ? arcade.star : arcade.pow, glow: false, in: &context)
            // Its portholes run left to right.
            let lit = Int(t * 8) % ArcadeSprite.mothershipLights.count
            for (k, light) in ArcadeSprite.mothershipLights.enumerated() {
                let r = CGRect(x: m.p.x + light.x - 1, y: m.p.y + light.y - 1, width: 2, height: 2)
                context.fill(Path(r), with: .color(k == lit ? arcade.raider : arcade.star.opacity(0.7)))
            }
        }
        for r in raiders {
            ArcadeDraw.sprite(ArcadeSprite.raider, at: r, color: arcade.raider, glow: false, in: &context)
        }
        for p in pows {
            let at = CGPoint(x: p.p.x + 6 * sin((t - p.born) * 3), y: p.p.y)
            // A shot that turns it swells it for a beat, so the change reads.
            let swell: CGFloat = t - p.changedAt < 0.15 ? 1.25 : 1
            capsule(p.kind, at: at, swell: swell, in: &context)
        }
        for s in shots { ArcadeDraw.shot(at: s.p, color: arcade.star, in: &context) }
        if let b = boss { drawBoss(b, in: &context, dark: dark) }
        // Orbs go down as three paths, however many there are: a furious
        // Bitjelly keeps hundreds in the air.
        var edges = Path(), orbs = Path(), cores = Path()
        for b in bombs {
            if b.orb {
                edges.addEllipse(in: CGRect(x: b.p.x - 4, y: b.p.y - 4, width: 8, height: 8))
                orbs.addEllipse(in: CGRect(x: b.p.x - 3, y: b.p.y - 3, width: 6, height: 6))
                cores.addRect(CGRect(x: b.p.x - 1, y: b.p.y - 1, width: 2, height: 2))
            } else {
                ArcadeDraw.bomb(at: b.p, color: arcade.raider, time: t, in: &context)
            }
        }
        context.fill(edges, with: .color(ArcadeDraw.outline))
        context.fill(orbs, with: .color(boss?.furious == true ? arcade.raider : arcade.border))
        context.fill(cores, with: .color(arcade.star))
        for b in bursts { ArcadeDraw.burst(at: b.p, age: b.age, life: b.life, color: b.color, reach: b.reach, in: &context) }
        if let egg, sinceEgg < 0.7 {
            // A shockwave ring, and the screen going the fruit's color for a beat.
            let u = sinceEgg / 0.7
            let r = 10 + 170 * CGFloat(1 - pow(1 - u, 2))
            context.stroke(Path(ellipseIn: CGRect(x: egg.p.x - r, y: egg.p.y - r, width: r * 2, height: r * 2)), with: .color(arcade.food.opacity(0.8 * (1 - u))), lineWidth: 3 * (1 - u) + 1)
            if sinceEgg < 0.3 {
                context.fill(Path(CGRect(x: -20, y: -20, width: size.width + 40, height: size.height + 40)), with: .color(arcade.food.opacity(0.28 * (1 - sinceEgg / 0.3))))
            }
        }
        if !idle { drawPowers(in: &context) }
        guard !isOver else { return }
        drawShip(in: &context, dark: dark)
    }

    private func drawSnake(in context: inout GraphicsContext, sinceEgg: Double, dark: Bool) {
        let t = clock, cell = ArcadeSnake.cell
        // Charmed it wears the invaders' green, flickering as it wears off.
        let charm = charmed && (charmedUntil - t > 2 || Int(t * 8) % 2 == 0)
        var edge = Path()
        for c in snake {
            edge.addRoundedRect(in: CGRect(x: CGFloat(c.x) * cell + 1, y: CGFloat(c.y) * cell + 1, width: cell - 2, height: cell - 2), cornerSize: CGSize(width: 2, height: 2))
        }
        context.stroke(edge, with: .color(ArcadeDraw.outline), lineWidth: 2)
        for (k, c) in snake.enumerated() {
            let rect = CGRect(x: CGFloat(c.x) * cell + 1, y: CGFloat(c.y) * cell + 1, width: cell - 2, height: cell - 2)
            let isHead = k == 0
            // Once the fruit is shot it is your enemy, and it turns red from
            // the head back, one segment every 30 ms.
            let red = sinceEgg >= 0 && sinceEgg > Double(k) * 0.03
            let color = switch (isHead, charm, red) {
            case (true, true, _): arcade.invader
            case (false, true, _): arcade.invader.mix(with: .black, by: 0.3)
            case (true, false, true): arcade.raider
            case (false, false, true): arcade.raider.mix(with: .black, by: 0.25)
            case (true, false, false): arcade.snake
            case (false, false, false): arcade.snakeBody
            }
            if dark, idle, k < 12 {
                context.fill(
                    Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)),
                    with: .radialGradient(Gradient(colors: [color.opacity(isHead ? 0.35 : 0.18), color.opacity(0)]), center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: rect.width),
                )
            }
            let fade = max(0.45, 0.95 - Double(k) * 0.025)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(isHead ? 1 : fade)))
            if isHead {
                for ex in [0.3, 0.7] {
                    context.fill(Path(CGRect(x: rect.minX + rect.width * ex - 1, y: rect.minY + 3, width: 2, height: 2)), with: .color(red || charm ? arcade.pow : .black.opacity(0.8)))
                }
            }
        }
        if let f = food {
            // It grows in while it ripens, and only blinks once it can be burst.
            let u = min(1, (t - foodAt) / ArcadeRules.ripen)
            let inset = 2 + (cell / 2 - 2) * (1 - u) * 0.7
            let r = CGRect(x: CGFloat(f.x) * cell, y: CGFloat(f.y) * cell, width: cell, height: cell).insetBy(dx: inset, dy: inset)
            let blink = u < 1 ? 0.55 + 0.45 * u : 0.6 + 0.4 * (sin(t * 2 * 6.28) > 0 ? 1 : 0)
            let fruit = Path(roundedRect: r, cornerRadius: 2)
            context.stroke(fruit, with: .color(ArcadeDraw.outline), lineWidth: 3)
            context.fill(fruit, with: .color(arcade.food.opacity(blink)))
        }
        // Where the next one will land, for the player: corner ticks, so it
        // reads as a spot to keep your fire off rather than a fruit.
        if !idle, food != nil, let n = nextFood {
            let r = CGRect(x: CGFloat(n.x) * cell, y: CGFloat(n.y) * cell, width: cell, height: cell)
            var ticks = Path()
            for (x, y, sx, sy) in [(r.minX, r.minY, CGFloat(1), CGFloat(1)), (r.maxX, r.minY, -1, 1), (r.minX, r.maxY, 1, -1), (r.maxX, r.maxY, -1, -1)] {
                ticks.move(to: CGPoint(x: x + 4 * sx, y: y))
                ticks.addLine(to: CGPoint(x: x, y: y))
                ticks.addLine(to: CGPoint(x: x, y: y + 4 * sy))
            }
            context.stroke(ticks, with: .color(ArcadeDraw.outline), lineWidth: 3)
            context.stroke(ticks, with: .color(arcade.food.opacity(0.5 + 0.25 * sin(t * 4))), lineWidth: 1.5)
        }
    }

    private func drawAlien(_ a: Alien, in context: inout GraphicsContext) {
        switch a.alien {
        case .plain:
            ArcadeDraw.sprite(ArcadeSprite.invaders[a.tint % 3][a.frame], at: a.p, color: ArcadeDraw.invaderTint(arcade, row: a.tint), glow: false, in: &context)
        case .shielded:
            ArcadeDraw.sprite(ArcadeSprite.shielded[a.frame], at: a.p, color: arcade.star, glow: false, in: &context)
            if a.hp < a.alien.hp {
                ArcadeDraw.sprite(ArcadeSprite.crack, at: a.p, color: .black.opacity(0.75), glow: false, outlined: false, in: &context)
            }
        case .splitter:
            let halves = ArcadeSprite.splitter[a.frame]
            ArcadeDraw.sprite(halves.left, at: a.p, color: arcade.invader, glow: false, in: &context)
            ArcadeDraw.sprite(halves.right, at: a.p, color: arcade.border, glow: false, in: &context)
        case .mini:
            ArcadeDraw.sprite(ArcadeSprite.mini[a.frame], at: a.p, color: a.tint == 0 ? arcade.invader : arcade.border, glow: false, in: &context)
        }
    }

    private func capsule(_ kind: ArcadePower, at p: CGPoint, swell: CGFloat = 1, in context: inout GraphicsContext) {
        let rect = CGRect(x: p.x - 11 * swell, y: p.y - 8 * swell, width: 22 * swell, height: 16 * swell)
        // Charm is the rare one: the fruit's magenta, not the POW yellow.
        let shell = Path(roundedRect: rect, cornerRadius: 4)
        context.stroke(shell, with: .color(ArcadeDraw.outline), lineWidth: 2)
        context.fill(shell, with: .color((kind == .charm ? arcade.food : arcade.pow).opacity(0.9)))
        context.fill(ArcadeSprite.pows[kind]!.applying(CGAffineTransform(translationX: p.x, y: p.y)), with: .color(.black.opacity(0.8)))
    }

    private func drawBoss(_ b: ArcadeBoss, in context: inout GraphicsContext, dark: Bool) {
        let t = clock - b.start, s = ArcadeBoss.scale
        let fury = b.furious && b.dyingAt == nil
        // Furious, it shakes with it.
        let shake = fury ? CGSize(width: 1.5 * sin(clock * 53), height: 1.5 * cos(clock * 47)) : .zero
        context.drawLayer { layer in
            layer.translateBy(x: b.p.x + shake.width, y: b.p.y + shake.height)
            layer.scaleBy(x: s, y: s)
            if let dying = b.dyingAt { layer.opacity = max(0, 1 - (clock - dying) / 1.5) }
            JellySpecies.bitjelly.draw(in: &layer, time: t, motion: ArcadeBoss.motion, bell: arcade.snake, dark: dark, showFace: true)
            guard fury else { return }
            // Red all through, glow and all: the hue at its own lightness,
            // deepened, then cut back to its shape by drawing it again as the
            // mask, in a layer of its own so the mask goes on in one piece.
            let cover = Path(CGRect(x: -44, y: -44, width: 88, height: 110))
            layer.blendMode = .color
            layer.fill(cover, with: .color(ArcadeDraw.fury))
            layer.blendMode = .multiply
            layer.fill(cover, with: .color(ArcadeDraw.furyDepth))
            layer.blendMode = .destinationIn
            layer.drawLayer { mask in
                JellySpecies.bitjelly.draw(in: &mask, time: t, motion: ArcadeBoss.motion, bell: arcade.snake, dark: dark, showFace: true)
            }
            layer.blendMode = .normal
            // And mad: eyes gone hot under brows that slant down to the middle.
            var eyes = Path(), brows = Path()
            for q in [4, 9] { eyes.addRect(JellySpecies.bitjellyCell(q, 4).union(JellySpecies.bitjellyCell(q, 5))) }
            for (q, r) in [(3, 2), (4, 3), (10, 2), (9, 3)] { brows.addRect(JellySpecies.bitjellyCell(q, r)) }
            layer.fill(eyes, with: .color(arcade.pow))
            layer.fill(brows, with: .color(.black.opacity(0.85)))
        }
        // A hit flashes the bell white for a frame or two.
        if b.flash > 0 {
            let bell = CGRect(x: b.p.x - 27 * s, y: b.p.y - 20 * s, width: 54 * s, height: 36 * s)
            context.fill(Path(roundedRect: bell, cornerRadius: 12), with: .color(arcade.star.opacity(0.18)))
        }
        guard b.dyingAt == nil else { return }
        // Its health, across the whole field, in tenths.
        let bar = CGRect(x: 20, y: top - 26, width: size.width - 40, height: 9)
        let left = CGFloat(b.hp) / CGFloat(b.maxHP)
        context.fill(Path(bar), with: .color(arcade.star.opacity(0.12)))
        context.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * left, height: bar.height)), with: .color(b.hp * 2 < b.maxHP || b.furious ? arcade.raider : arcade.border))
        var ticks = Path()
        for k in 1 ..< 10 {
            let x = bar.minX + bar.width * CGFloat(k) / 10
            ticks.move(to: CGPoint(x: x, y: bar.minY))
            ticks.addLine(to: CGPoint(x: x, y: bar.maxY))
        }
        context.stroke(ticks, with: .color(.black.opacity(0.45)), lineWidth: 1)
        context.stroke(Path(bar.insetBy(dx: -1.5, dy: -1.5)), with: .color(arcade.star.opacity(0.7)), lineWidth: 1.5)
    }

    /// What you are carrying, in the bottom-left corner: a capsule per power,
    /// pips for the spread's level, a draining bar for the timed ones.
    private func drawPowers(in context: inout GraphicsContext) {
        let t = clock
        var held: [(ArcadePower, Double?, Int)] = []
        if wideLevel > 0 { held.append((.wide, nil, wideLevel)) }
        if !wingmen.isEmpty { held.append((.wingmen, nil, shields)) }
        if shield > 0 { held.append((.shield, nil, shield)) }
        if t < laserUntil { held.append((.laser, (laserUntil - t) / 6, 0)) }
        if charmed { held.append((.charm, (charmedUntil - t) / 10, 0)) }
        for (i, (power, left, pips)) in held.enumerated() {
            let at = CGPoint(x: 26 + CGFloat(i) * 30, y: size.height - 46)
            capsule(power, at: at, in: &context)
            let below = at.y + 11
            if let left {
                let bar = CGRect(x: at.x - 11, y: below, width: 22, height: 2)
                context.fill(Path(bar), with: .color(arcade.star.opacity(0.2)))
                context.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(max(0, min(1, left))), height: bar.height)), with: .color(arcade.star))
            }
            for k in 0 ..< pips {
                context.fill(Path(CGRect(x: at.x - 9 + CGFloat(k) * 5, y: below, width: 3, height: 3)), with: .color(arcade.snake))
            }
        }
    }

    private func drawShip(in context: inout GraphicsContext, dark: Bool) {
        let t = clock
        // The laser, from each gun to the top of the field, as wide as Wide makes it.
        if t < laserUntil, !rolling {
            let flick = 0.8 + 0.2 * sin(t * 50)
            for b in beams {
                let beam = CGRect(x: b.x - 4 - beamReach, y: 0, width: 8 + beamReach * 2, height: b.y)
                context.fill(Path(beam), with: .color(arcade.border.opacity(0.35 * flick)))
                context.fill(Path(beam.insetBy(dx: 2.5 + beamReach * 0.75, dy: 0)), with: .color(arcade.star.opacity(flick)))
            }
        }
        // Blinks while it cannot be hit; a roll turns it over and lifts it.
        guard !(t < invulnerableUntil && Int(t * 10) % 2 == 1) else { return }
        if idle {
            // The invitation to take it: a breathing halo, and a ring that goes
            // out from it every four seconds. In light mode too.
            let breath = 0.5 + 0.5 * sin(t * 2.4)
            let r: CGFloat = 26
            context.fill(
                Path(ellipseIn: CGRect(x: ship.x - r, y: ship.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(Gradient(colors: [arcade.snake.opacity((dark ? 0.35 : 0.25) + 0.2 * breath), arcade.snake.opacity(0)]), center: ship, startRadius: 0, endRadius: r),
            )
            let pulse = (t / 4).truncatingRemainder(dividingBy: 1)
            if pulse < 0.4 {
                let u = pulse / 0.4, ring = 12 + 22 * u
                context.stroke(Path(ellipseIn: CGRect(x: ship.x - ring, y: ship.y - ring, width: ring * 2, height: ring * 2)), with: .color(arcade.snake.opacity(0.6 * (1 - u))), lineWidth: 1.5)
            }
        }
        let u = min(1, (t - rollStart) / 1.0)
        let lift: CGFloat = rolling ? 1 + 0.5 * CGFloat(sin(u * .pi)) : 1
        let spin: Angle = rolling ? .radians(u * 2 * .pi) : .zero
        for (i, w) in wingmen.enumerated() {
            ArcadeDraw.sprite(ArcadeSprite.wingman, at: w, color: arcade.snake, glow: false, rotation: spin, scale: lift, in: &context)
            if i < shields {
                context.stroke(Path(ellipseIn: CGRect(x: w.x - 9, y: w.y - 9, width: 18, height: 18)), with: .color(arcade.snake.opacity(0.5 + 0.3 * sin(t * 6))), lineWidth: 1.2)
            }
        }
        ArcadeDraw.ship(at: ship, arcade: arcade, time: t, glow: dark && !idle, rotation: spin, scale: lift, in: &context)
        // Against a furious Bitjelly only the core can be hit, so show it.
        if boss?.furious == true {
            let core = CGRect(x: ship.x - 3, y: ship.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: core.insetBy(dx: -1.5, dy: -1.5)), with: .color(arcade.raider))
            context.fill(Path(ellipseIn: core), with: .color(arcade.star))
        }
        // The bubble: a ring per layer.
        for k in 0 ..< shield {
            let r = (15 + CGFloat(k) * 3.5) * lift
            let ring = Path(ellipseIn: CGRect(x: ship.x - r, y: ship.y - r, width: r * 2, height: r * 2))
            context.stroke(ring, with: .color(ArcadeDraw.outline), lineWidth: 3)
            context.stroke(ring, with: .color(arcade.snake.opacity(0.6 + 0.3 * sin(t * 6 + Double(k)))), lineWidth: 1.5)
        }
    }
}
