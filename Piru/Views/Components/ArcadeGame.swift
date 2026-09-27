import SwiftUI

// MARK: - The round

/// One round, stepped by its view's clock. Not observed: the view reads it
/// every frame anyway, so observation would only add bookkeeping.
@MainActor
final class ArcadeGame {
    struct Shot { var p: CGPoint; var vx: CGFloat }
    struct Bomb { var p: CGPoint; var v: CGVector; var orb = false }
    /// The backdrop's divers. A swarmer from the top edge has no slot
    /// (`col` -1) and is gone when it misses, instead of going home.
    typealias Diver = InvaderTape.Diver
    struct Pow { var p: CGPoint; var kind: ArcadePower; var born: Double; var changedAt = -9.0 }
    struct Burst { var p: CGPoint; var age: Double; var life: Double; var color: Color; var reach: CGFloat }
    /// Five red raiders crossing on a wave; down all five and one drops a POW.
    struct Raid {
        var start: Double
        var fromLeft: Bool
        var alive = [Bool](repeating: true, count: 5)
        var fired = [Bool](repeating: false, count: 5)
        var lastKill: CGPoint?
    }

    let size: CGSize
    let arcade: SkinArcade

    private var clock = 0.0
    private var lastDate: Double
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var loops = 3
    private var overAt: Double?
    var isOver: Bool { overAt != nil }
    var finished: Bool { overAt.map { clock - $0 > 2.6 } ?? false }

    /// The ship.
    private(set) var ship: CGPoint
    /// Where the finger is steering the ship, clamped to the playfield.
    var target: CGPoint {
        get { aim }
        set { aim = CGPoint(x: max(16, min(size.width - 16, newValue.x)), y: max(80, min(size.height - 50, newValue.y))) }
    }

    private var aim: CGPoint
    /// 0 single, 1 three-way, 2 five-way.
    private var wideLevel = 0
    private var wingmen = 0
    /// A second Wingmen pickup shields them: each shield takes a hit first.
    private var shields = 0
    private var laserUntil = -1.0
    private var laserTick = 0.0
    private var charmedUntil = -1.0
    private var laserOn: Bool { clock < laserUntil }
    private var charmed: Bool { clock < charmedUntil }
    /// The word a pickup flashes up, and when.
    private(set) var callout: (text: LocalizedStringResource, at: Double)?
    private var invulnerableUntil = 0.0
    private var rollStart = -9.0
    private var cooldown = 0.0

    private var formation: ArcadeFormation
    private var nextFormationAt: Double?
    private var wave = 1
    private var formationTop: CGFloat { max(110, size.height * 0.14) }

    /// The bonus ship across the top, from the second wave.
    struct Mothership { var p: CGPoint; var vx: CGFloat; var hp = 3; var flash = 0.0 }
    private var mothership: Mothership?
    private var nextMothershipAt = 16.0

    /// Every tenth wave: Bitjelly, from rocuronium, the size of the formation.
    struct Boss {
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
        /// The health fractions still owed a POW, highest first.
        var drops: [Double] = [0.75, 0.5, 0.25]
    }

    private var boss: Boss?
    private static let bossScale: CGFloat = 2.2
    /// Bitjelly's `beat`, so the rings go out on its contractions.
    private static let bossBeat = JellySpecies.bitjelly.beat.period
    private static let bossMotion = JellyMotion(period: bossBeat, amp: JellySpecies.bitjelly.beat.amp, sway: 0, swayPeriod: 1, rise: 0, phase: 0)
    private var shots: [Shot] = []
    private var bombs: [Bomb] = []
    private var divers: [Diver] = []
    /// Bitjelly's summons.
    private var brood: [BroodJelly] = []
    private var summons = 0
    /// How far a saucer's beam has lifted the ship off where you are steering it.
    private var tractor: CGFloat = 0
    private var raid: Raid?
    private var nextRaidAt = 7.0
    private var nextDiveAt = 3.0
    private var pows: [Pow] = []
    private var bursts: [Burst] = []

    // The snake, on the backdrop's 12pt grid.
    private let cell: CGFloat = 12
    private var snake: [(Int, Int)]
    private var snakeDir: (Int, Int)
    private var food: (Int, Int)?
    /// The fruit was shot: the snake hunts the ship and the invaders swarm.
    private(set) var hunting = false
    /// When and where the fruit went up: the blast, the flash, the shake,
    /// and the red running down the snake all time from it.
    private var egg: (at: Double, p: CGPoint)?
    private var snakeClock = 0.0
    private var growth = 0
    private let cols: Int, skyRows: Int, allRows: Int

    private var rng: SeededRNG

    init(size: CGSize, arcade: SkinArcade, handoff frame: InvaderTape.Frame, time: Double) {
        self.size = size
        self.arcade = arcade
        lastDate = time
        rng = SeededRNG(seed: UInt64(bitPattern: Int64(time * 1_000)))
        let start = CGPoint(x: frame.shipX, y: InvaderTape.shipY(in: size))
        ship = start
        aim = start
        let everyone: UInt32 = (1 << UInt32(InvaderTape.cols * InvaderTape.rows)) - 1
        formation = .handoff(origin: frame.origin, alive: frame.alive == 0 ? everyone : frame.alive)
        formation.march = frame.march
        // Pick the snake up exactly where the backdrop had it.
        let vp = size.height * 0.52
        cols = Int(size.width / cell)
        skyRows = Int(vp * 0.9 / cell)
        allRows = Int(size.height / cell)
        let tape = SnakeGame(cols: cols, rows: skyRows, seed: 0x5AAE).state(atStep: Int(time / 0.16) % SnakeGame.tapeLength)
        snake = tape.body
        food = tape.food
        snakeDir = tape.body.count > 1 ? (tape.body[0].0 - tape.body[1].0, tape.body[0].1 - tape.body[1].1) : (1, 0)
        // Hand the backdrop's bombs over too, so nothing blinks out on the tap.
        bombs = frame.bombs.map { Bomb(p: $0, v: CGVector(dx: 0, dy: 150)) }
        // The backdrop's divers keep their slots, renumbered for this formation.
        divers = frame.divers.map { d in
            var d = d
            let slot = ArcadeFormation.handoffIndex(col: d.col, row: d.row)
            formation.members[slot].alive = true
            formation.members[slot].away = true
            d.col = slot
            return d
        }
        invulnerableUntil = 1.5
        #if DEBUG
            // `-piruArcadeWave <n>` starts the round at wave n, and
            // `-piruArcadeBoss` at the tenth, Bitjelly's — for recording a wave
            // without playing up to it.
            let args = ProcessInfo.processInfo.arguments
            let startWave = args.contains("-piruArcadeBoss") ? 10 : args.firstIndex(of: "-piruArcadeWave").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
            if let startWave, startWave > 1 {
                wave = startWave - 1
                for i in formation.members.indices { formation.members[i].alive = false }
                divers = []
            }
        #endif
    }

    // MARK: Controls

    /// 1942's loop: a second or so of flying through everything.
    func roll() {
        guard !isOver, loops > 0, clock - rollStart > 1.0 else { return }
        loops -= 1
        rollStart = clock
        PlatformHaptics.impact()
    }

    private var rolling: Bool { clock - rollStart < 1.0 }

    // MARK: Step

    /// Steps the round up to `date` and returns its clock.
    func advance(to date: Double) -> Double {
        // Clamped, so a frame after the app was away does not teleport anything.
        let dt = min(1 / 20, max(0, date - lastDate))
        lastDate = date
        guard dt > 0 else { return clock }
        clock += dt
        bursts = bursts.compactMap { var b = $0; b.age += dt; return b.age < b.life ? b : nil }
        guard !isOver else { return clock }
        moveShip(dt)
        fire(dt)
        moveFormation(dt)
        spawn()
        moveEnemies(dt)
        moveProjectiles(dt)
        stepSnake(dt)
        collide(dt)
        return clock
    }

    private func moveShip(_ dt: Double) {
        let k = min(1, dt * 18)
        ship = CGPoint(x: ship.x + (aim.x - ship.x) * k, y: ship.y + (aim.y - tractor - ship.y) * k)
    }

    private var wingmanSpots: [CGPoint] {
        Array([CGPoint(x: ship.x - 26, y: ship.y + 8), CGPoint(x: ship.x + 26, y: ship.y + 8)].prefix(wingmen))
    }

    private func fire(_ dt: Double) {
        cooldown -= dt
        guard cooldown <= 0, !rolling, shots.count < 64 else { return }
        cooldown = 0.2
        // The laser replaces the main gun while it lasts; wingmen keep firing.
        if !laserOn {
            let nose = CGPoint(x: ship.x, y: ship.y - 10)
            let spread: [CGFloat] = switch wideLevel {
            case 0: [0]
            case 1: [-120, 0, 120]
            default: [-200, -100, 0, 100, 200]
            }
            for vx in spread { shots.append(Shot(p: nose, vx: vx)) }
        }
        for w in wingmanSpots { shots.append(Shot(p: CGPoint(x: w.x, y: w.y - 6), vx: 0)) }
    }

    private func moveFormation(_ dt: Double) {
        // Cleared only once the divers are down too; one still out comes home.
        if formation.isCleared, boss == nil {
            if nextFormationAt == nil {
                nextFormationAt = clock + 1.2
                wave += 1
            }
            if let at = nextFormationAt, clock >= at {
                nextFormationAt = nil
                if wave % 10 == 0 {
                    let hp = 260 + wave * 10
                    boss = Boss(p: CGPoint(x: size.width / 2, y: -80), hp: hp, maxHP: hp, start: clock, summonAt: clock + 4)
                    // A long fight: something to go into it with.
                    pows.append(Pow(p: CGPoint(x: ship.x, y: formationTop), kind: rng.unit() < 0.5 ? .wide : .wingmen, born: clock))
                } else {
                    formation = .wave(wave, width: size.width, top: formationTop, rng: &rng)
                }
            }
            return
        }
        moveBoss(dt)
        guard !formation.presentIndices.isEmpty else { return }
        formation.step(dt, wave: wave, width: size.width, hurry: hunting ? 1.3 : 1)
        // Landed: it costs a life, and the formation goes back up.
        if let lowest = formation.lowestY, lowest > size.height - 90 {
            hurt()
            formation.origin.y = formationTop
        }
        let rate = (0.5 + 0.12 * Double(wave)) * (hunting ? 1.8 : 1)
        let present = formation.presentIndices
        if rng.unit() < rate * dt, !present.isEmpty {
            let i = present[Int(rng.next() % UInt64(present.count))]
            bombs.append(Bomb(p: formation.center(i), v: CGVector(dx: 0, dy: 150)))
        }
    }

    private func moveBoss(_ dt: Double) {
        guard var b = boss else { return }
        let t = clock - b.start
        b.flash = max(0, b.flash - dt)
        if let dying = b.dyingAt {
            // Comes apart in bursts for a second and a half, then drops two POWs.
            if rng.unit() < 0.5 {
                let at = CGPoint(x: b.p.x + (rng.unit() - 0.5) * 110, y: b.p.y + (rng.unit() - 0.5) * 80)
                pop(at, [arcade.snake, arcade.border, arcade.star][Int(rng.next() % 3)], big: true)
            }
            if clock - dying > 1.5 {
                for dx in [-24.0, 24.0] {
                    pows.append(Pow(p: CGPoint(x: b.p.x + dx, y: b.p.y), kind: ArcadePower.random(&rng), born: clock))
                }
                boss = nil
                return
            }
            boss = b
            return
        }
        // Drifts in from the top, then sways across on a slow figure.
        let home = CGPoint(
            x: size.width / 2 + (size.width / 2 - 70) * CGFloat(sin(t * 0.45)),
            y: formationTop + 70 + 22 * CGFloat(sin(t * 0.8)),
        )
        let enter = min(1, t / 2.5)
        b.p = CGPoint(x: home.x, y: -80 + (home.y + 80) * enter)
        if t > 2.5 {
            // Past half its health it presses harder: denser rings, faster shots.
            let enraged = b.hp * 2 < b.maxHP
            let origin = CGPoint(x: b.p.x, y: b.p.y + 10)
            func orb(_ from: CGPoint, angle a: Double, speed v: Double) {
                bombs.append(Bomb(p: from, v: CGVector(dx: cos(a) * v, dy: sin(a) * v), orb: true))
            }
            // A ring on every contraction, rotated a little each time.
            let beat = Int(t / Self.bossBeat)
            if beat != b.beat {
                b.beat = beat
                let n = enraged ? 22 : 16
                for k in 0 ..< n {
                    orb(origin, angle: Double(k) / Double(n) * 2 * .pi + Double(beat) * 0.26, speed: enraged ? 135 : 115)
                }
            }
            // Between rings, a two-armed spiral turning under the bell.
            if clock - b.spiralAt > (enraged ? 0.16 : 0.24) {
                b.spiralAt = clock
                let a = t * 2.1
                for arm in 0 ..< 2 {
                    orb(origin, angle: .pi / 2 + sin(a) * 1.1 + Double(arm) * .pi, speed: 150)
                }
            }
            // An aimed fan of three.
            if clock - b.aimedAt > (enraged ? 0.8 : 1.1) {
                b.aimedAt = clock
                let from = CGPoint(x: b.p.x, y: b.p.y + 30)
                let aim = atan2(ship.y - from.y, ship.x - from.x)
                for spread in [-0.22, 0.0, 0.22] {
                    orb(from, angle: aim + spread, speed: enraged ? 240 : 200)
                }
            }
            // It calls its brood out of its bell, a different pack each time,
            // and a saucer whenever none is flying.
            if clock >= b.summonAt {
                b.summonAt = clock + (enraged ? 3.5 : 5)
                summon(from: CGPoint(x: b.p.x, y: b.p.y + 36), enraged: enraged)
            }
        }
        boss = b
    }

    private func summon(from at: CGPoint, enraged: Bool) {
        let packs: [[BroodKind]] = [[.pip, .pip, .pip], [.bitling, .bitling], [.lantern, .bitling]]
        let pack = packs[summons % packs.count] + (enraged && summons % 2 == 0 ? [.pip] : [])
        for (i, kind) in pack.enumerated() {
            let off = CGFloat(i) - CGFloat(pack.count - 1) / 2
            var jelly = BroodJelly(kind, at: CGPoint(x: at.x + off * 22, y: at.y), v: CGVector(dx: off * 60, dy: 20), phase: rng.unit())
            jelly.dodges = (kind == .bitling || kind == .pip) && rng.unit() < 0.5
            brood.append(jelly)
        }
        if summons % 2 == 1 || enraged, !brood.contains(where: { $0.kind == .saucer }) {
            brood.append(BroodJelly(.saucer, at: at, phase: rng.unit()))
        }
        summons += 1
    }

    /// Bitjelly's bell, for hits: its sprite is 14 cells by 9 at 3.9 units.
    private func bossHit(_ p: CGPoint, pad: CGFloat = 0) -> Bool {
        guard let b = boss, b.dyingAt == nil else { return false }
        return near(p, CGPoint(x: b.p.x, y: b.p.y - 2), 27 * Self.bossScale + pad, 18 * Self.bossScale + pad)
    }

    private func spawn() {
        if boss != nil { return }
        if clock >= nextDiveAt {
            // An invader peels off the formation and dives at you.
            let present = formation.presentIndices
            if !present.isEmpty, divers.count(where: { $0.col >= 0 }) < 2 + wave / 2 {
                let slot = present[Int(rng.next() % UInt64(present.count))]
                let m = formation.members[slot]
                formation.members[slot].away = true
                let at = formation.center(slot)
                divers.append(Diver(p: at, v: .zero, col: slot, row: m.tint, age: 0, side: at.x < ship.x ? -1 : 1, alien: m.alien, hp: m.hp, dodges: rng.unit() < 0.45))
            }
            // The swarm: after the fruit, more pour in over the top as well.
            if hunting {
                let x = 20 + rng.unit() * (size.width - 40)
                divers.append(Diver(p: CGPoint(x: x, y: -12), v: .zero, col: -1, row: Int(rng.next() % 3), age: 0.7, side: 1))
            }
            nextDiveAt = clock + (hunting ? max(0.45, 1.2 - Double(wave) * 0.08) : max(1.2, 3.2 - Double(wave) * 0.25))
        }
        if raid == nil, clock >= nextRaidAt {
            raid = Raid(start: clock, fromLeft: rng.unit() < 0.5)
        }
        if wave >= 2, mothership == nil, clock >= nextMothershipAt {
            let fromLeft = rng.unit() < 0.5
            mothership = Mothership(p: CGPoint(x: fromLeft ? -24 : size.width + 24, y: formationTop - 18), vx: fromLeft ? 80 : -80)
        }
    }

    private func raiderPosition(_ raid: Raid, _ i: Int) -> (CGPoint, Double) {
        let t = clock - raid.start - Double(i) * 0.3
        let x = raid.fromLeft ? -20 + 110 * t : size.width + 20 - 110 * t
        let y = formationTop + 40 + 50 * sin(t * 2.4)
        return (CGPoint(x: x, y: y), t)
    }

    private func moveEnemies(_ dt: Double) {
        let head = center(of: snake[0])
        divers = divers.compactMap { d in
            var d = d
            let slot = d.col >= 0 ? formation.center(d.col) : .zero
            // It comes in on a flank, beside the ship on the side it is already
            // on, and cuts in only once it is low — so holding still under
            // your own fire does not line the dive up in front of the gun.
            let committed = d.p.y > ship.y - 100
            let flank = committed ? ship : CGPoint(x: ship.x + (d.p.x < ship.x ? -20 : 20), y: ship.y)
            let flying = InvaderTape.steer(&d, toward: flank, slot: slot, bottom: size.height + 20, dt: dt, speed: hunting ? 1.25 : 1.1)
            if flying, d.dodges, !d.returning, d.age > 0.7, !committed {
                dodge(&d.p, agility: d.alien.agility, dt: dt)
            }
            if !flying {
                formation.members[d.col].away = false
                formation.members[d.col].hp = d.hp
                return nil
            }
            // Once the snake is hunting, the aliens give it a wide berth, so it
            // has to come for you through the swarm instead of eating it.
            if hunting {
                let dx = d.p.x - head.x, dy = d.p.y - head.y
                let dist = hypot(dx, dy)
                if dist < 56, dist > 0.1 {
                    let push = 160 * (1 - dist / 56) * dt
                    d.p.x += dx / dist * push
                    d.p.y += dy / dist * push
                }
            }
            return d.returning && d.col < 0 ? nil : d
        }
        let hover = size.height * 0.46
        var lifted = false
        for i in brood.indices {
            if let orb = brood[i].swim(toward: ship, hover: hover, t: clock, dt: dt) {
                bombs.append(Bomb(p: orb, v: CGVector(dx: 0, dy: 150), orb: true))
            }
            // The quick ones sidestep your fire too; Lantern and Saucer are
            // the slow, tough ones and take it.
            if brood[i].dodges, brood[i].p.y < ship.y - 100 {
                dodge(&brood[i].p, agility: brood[i].kind == .pip ? 0.7 : 0.5, dt: dt)
            }
            guard brood[i].kind == .saucer, brood[i].beaming(at: clock) else { continue }
            // The tractor beam: lifts the ship while it stays in the cone; a
            // wingman caught in it is taken.
            if !rolling, brood[i].inBeam(ship, bottom: size.height) {
                tractor += 70 * dt
                lifted = true
                if near(ship, brood[i].p, 16, 16) {
                    hurt()
                    brood[i].beamUntil = clock
                    tractor = 0
                }
            }
            if !brood[i].tookWingman, let w = wingmanSpots.firstIndex(where: { brood[i].inBeam($0, bottom: size.height) }) {
                brood[i].tookWingman = true
                loseWingman(at: w)
            }
        }
        if !lifted { tractor = max(0, tractor - 140 * dt) }
        brood.removeAll { $0.p.y > size.height + 24 || $0.p.x < -40 || $0.p.x > size.width + 40 }
        if var m = mothership {
            m.p.x += m.vx * dt
            m.flash = max(0, m.flash - dt)
            mothership = m.p.x < -40 || m.p.x > size.width + 40 ? nil : m
            if mothership == nil { nextMothershipAt = clock + 16 + rng.unit() * 8 }
        }
        guard var r = raid else { return }
        var gone = true
        for i in 0 ..< 5 {
            let (p, t) = raiderPosition(r, i)
            if t < 0 || (p.x > -30 && p.x < size.width + 30) { gone = false }
            // Each raider throws one bomb at the ship as it crosses.
            if r.alive[i], !r.fired[i], t > 1.2, p.x > 0, p.x < size.width {
                r.fired[i] = true
                let dx = ship.x - p.x, dy = ship.y - p.y
                let d = max(1, hypot(dx, dy))
                bombs.append(Bomb(p: p, v: CGVector(dx: dx / d * 170, dy: dy / d * 170)))
            }
        }
        raid = r
        if gone {
            raid = nil
            nextRaidAt = clock + (hunting ? 10 : 15)
        }
    }

    private func moveProjectiles(_ dt: Double) {
        for i in shots.indices {
            shots[i].p.x += shots[i].vx * dt
            shots[i].p.y -= 520 * dt
        }
        shots.removeAll { $0.p.y < -10 || $0.p.x < -10 || $0.p.x > size.width + 10 }
        for i in bombs.indices {
            bombs[i].p.x += bombs[i].v.dx * dt
            bombs[i].p.y += bombs[i].v.dy * dt
        }
        bombs.removeAll { $0.p.y > size.height + 10 || $0.p.y < -10 || $0.p.x < -10 || $0.p.x > size.width + 10 }
        for i in pows.indices { pows[i].p.y += 55 * dt }
        pows.removeAll { $0.p.y > size.height + 20 }
    }

    // MARK: Snake

    private func stepSnake(_ dt: Double) {
        snakeClock += dt
        let interval = hunting ? 0.11 : 0.16
        while snakeClock >= interval {
            snakeClock -= interval
            snakeStep()
        }
    }

    private func snakeStep() {
        let rows = hunting || charmed ? allRows : skyRows
        let goal: (Int, Int) = if charmed, let prey = nearestPrey(to: center(of: snake[0])) {
            (Int(prey.x / cell), Int(prey.y / cell))
        } else if hunting {
            (Int(ship.x / cell), Int(ship.y / cell))
        } else {
            food ?? (cols / 2, rows / 2)
        }
        let head = snake[0]
        let candidates = [snakeDir, (-snakeDir.1, snakeDir.0), (snakeDir.1, -snakeDir.0)]
        var best: ((Int, Int), Int)?
        for d in candidates {
            let next = (head.0 + d.0, head.1 + d.1)
            guard next.0 >= 0, next.0 < cols, next.1 >= 0, next.1 < rows else { continue }
            let eats = food.map { next == $0 } ?? false
            let keepsTail = eats || growth > 0
            if snake.dropLast(keepsTail ? 0 : 1).contains(where: { $0 == next }) { continue }
            let score = abs(next.0 - goal.0) + abs(next.1 - goal.1) + (rng.unit() < 0.1 ? 2 : 0)
            if best == nil || score < best!.1 { best = (d, score) }
        }
        guard let move = best?.0 else {
            // Trapped: a new snake drops in at the top.
            snake = (0 ..< 6).map { (cols / 2 - $0, 1) }
            snakeDir = (1, 0)
            return
        }
        snakeDir = move
        let next = (head.0 + move.0, head.1 + move.1)
        snake.insert(next, at: 0)
        if let f = food, next == f {
            growth += 1
            food = placeFood()
        }
        if growth > 0, snake.count <= 48 {
            growth -= 1
        } else {
            snake.removeLast()
        }
    }

    /// Sidesteps the nearest bullet coming up underneath, away from its line.
    /// `agility` scales how hard. Only about half of them try (`dodges`, rolled
    /// when each one sets off), they see a bullet late, and nothing dodges a
    /// whole spread — a player holding still should still win most dives.
    private func dodge(_ p: inout CGPoint, agility: CGFloat, dt: Double) {
        let threat = shots
            .filter { $0.p.y > p.y && $0.p.y - p.y < 70 && abs($0.p.x - p.x) < 14 }
            .min { $0.p.y < $1.p.y }
        guard let threat else { return }
        let away: CGFloat = threat.p.x == p.x ? (p.x < size.width / 2 ? 1 : -1) : (p.x > threat.p.x ? 1 : -1)
        p.x = max(10, min(size.width - 10, p.x + away * 110 * agility * CGFloat(dt)))
    }

    /// Charmed, the snake goes for the nearest alien or jelly instead.
    private func nearestPrey(to head: CGPoint) -> CGPoint? {
        let candidates = formation.presentIndices.map { formation.center($0) } + divers.map(\.p) + brood.filter { $0.kind != .saucer }.map(\.p)
        return candidates.min { hypot($0.x - head.x, $0.y - head.y) < hypot($1.x - head.x, $1.y - head.y) }
    }

    private func placeFood() -> (Int, Int) {
        for _ in 0 ..< 64 {
            let c = (Int(rng.next() % UInt64(max(cols, 1))), Int(rng.next() % UInt64(max(skyRows, 1))))
            if !snake.contains(where: { $0 == c }) { return c }
        }
        return (0, 0)
    }

    private func center(of c: (Int, Int)) -> CGPoint {
        CGPoint(x: (CGFloat(c.0) + 0.5) * cell, y: (CGFloat(c.1) + 0.5) * cell)
    }

    // MARK: Collisions

    private func near(_ a: CGPoint, _ b: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> Bool {
        abs(a.x - b.x) < dx && abs(a.y - b.y) < dy
    }

    private func pop(_ p: CGPoint, _ color: Color, big: Bool = false) {
        bursts.append(Burst(p: p, age: 0, life: big ? 0.7 : 0.4, color: color, reach: big ? 30 : 14))
    }

    /// An alien shot down: its points, its burst, and a splitter's two halves
    /// going on without it.
    private func kill(_ alien: ArcadeAlien, at p: CGPoint, tint: Int) {
        score += alien.points - (alien == .plain ? tint * 5 : 0)
        pop(p, alien == .shielded ? arcade.star : ArcadeDraw.invaderTint(arcade, row: tint))
        guard alien == .splitter else { return }
        for (k, side) in [CGFloat(-1), 1].enumerated() {
            var mini = Diver(p: CGPoint(x: p.x + side * 5, y: p.y), v: CGVector(dx: side * 140, dy: -40), col: -1, row: k == 0 ? 0 : 2, age: 0.7, side: side, alien: .mini)
            mini.hp = 1
            mini.dodges = rng.unit() < 0.55
            divers.append(mini)
        }
    }

    // MARK: Damage

    // One function per kind of target, shared by the guns and the laser.

    private func damageBoss(at p: CGPoint) {
        guard var b = boss, b.dyingAt == nil else { return }
        b.hp -= 1
        b.flash = 0.06
        score += 10
        pop(p, arcade.star)
        if let next = b.drops.first, Double(b.hp) / Double(b.maxHP) <= next {
            b.drops.removeFirst()
            pows.append(Pow(p: b.p, kind: ArcadePower.random(&rng), born: clock))
        }
        if b.hp <= 0 {
            b.dyingAt = clock
            score += 5_000
            bombs.removeAll { $0.orb }
            PlatformHaptics.success()
        }
        boss = b
    }

    private func damageMember(_ m: Int, at p: CGPoint) {
        formation.members[m].hp -= 1
        if formation.members[m].hp > 0 {
            pop(p, arcade.star)
        } else {
            formation.members[m].alive = false
            kill(formation.members[m].alien, at: formation.center(m), tint: formation.members[m].tint)
        }
    }

    private func damageDiver(_ d: Int, at p: CGPoint) {
        divers[d].hp -= 1
        guard divers[d].hp <= 0 else { pop(p, arcade.star); return }
        let gone = divers.remove(at: d)
        if gone.col >= 0 { formation.members[gone.col].alive = false }
        // Diving is worth more than sitting still.
        score += 20
        kill(gone.alien, at: gone.p, tint: gone.row)
        if boss != nil, rng.unit() < 0.25 {
            pows.append(Pow(p: gone.p, kind: ArcadePower.random(&rng), born: clock))
        }
    }

    private func damageJelly(_ j: Int, at p: CGPoint) {
        brood[j].hp -= 1
        brood[j].flash = 0.06
        pop(p, arcade.star)
        guard brood[j].hp <= 0 else { return }
        let gone = brood.remove(at: j)
        score += gone.kind.points
        bursts.append(Burst(p: gone.p, age: 0, life: 0.5, color: gone.kind == .pip ? BroodPalette.pink : BroodPalette.rim, reach: 20))
        // The two-hit ones pay: a lantern often, a saucer always.
        if gone.kind == .saucer || (gone.kind == .lantern && rng.unit() < 0.5) {
            pows.append(Pow(p: gone.p, kind: ArcadePower.random(&rng), born: clock))
        }
    }

    private func damageMothership(at p: CGPoint) {
        guard var m = mothership else { return }
        m.hp -= 1
        m.flash = 0.08
        pop(p, arcade.star)
        guard m.hp <= 0 else { mothership = m; return }
        score += 300
        for (color, reach, life) in [(arcade.pow, 22.0, 0.5), (arcade.star, 40.0, 0.7)] {
            bursts.append(Burst(p: m.p, age: 0, life: life, color: color, reach: reach))
        }
        pows.append(Pow(p: m.p, kind: ArcadePower.random(&rng), born: clock))
        mothership = nil
        nextMothershipAt = clock + 16 + rng.unit() * 8
    }

    private func damageRaider(_ k: Int) {
        guard var r = raid, r.alive[k] else { return }
        let (p, _) = raiderPosition(r, k)
        r.alive[k] = false
        r.lastKill = p
        score += 100
        pop(p, arcade.raider)
        // The whole raid down: a POW where the last one fell.
        if !r.alive.contains(true) {
            score += 500
            pows.append(Pow(p: p, kind: ArcadePower.random(&rng), born: clock))
            r.lastKill = nil
        }
        raid = r
    }

    /// The egg: the fruit is shot, and the snake turns on you.
    private func burstFruit(_ f: (Int, Int)) {
        hunting = true
        food = nil
        score += 200
        let at = center(of: f)
        egg = (clock, at)
        // Four rings of pixels on staggered reaches and lives, so it reads as
        // one blast opening outward rather than a pop.
        for (color, reach, life) in [(arcade.food, 26.0, 0.5), (arcade.star, 48.0, 0.7), (arcade.raider, 72.0, 0.9), (arcade.food, 100.0, 1.1)] {
            bursts.append(Burst(p: at, age: 0, life: life, color: color, reach: reach))
        }
        nextDiveAt = clock + 0.5
        PlatformHaptics.success()
    }

    /// One bullet, one target: the first thing it touches.
    private func strike(_ p: CGPoint) -> Bool {
        if bossHit(p) { damageBoss(at: p); return true }
        if let m = formation.presentIndices.first(where: { near(p, formation.center($0), 9, 8) }) { damageMember(m, at: p); return true }
        if let d = divers.firstIndex(where: { near(p, $0.p, 10, 9) }) { damageDiver(d, at: p); return true }
        if let j = brood.firstIndex(where: { near(p, $0.p, $0.kind.reach.width, $0.kind.reach.height) }) { damageJelly(j, at: p); return true }
        if let m = mothership, near(p, m.p, 17, 8) { damageMothership(at: p); return true }
        if let r = raid, let k = (0 ..< 5).first(where: { r.alive[$0] && near(p, raiderPosition(r, $0).0, 10, 8) }) { damageRaider(k); return true }
        // A shot turns a capsule into the next power-up — one step per quarter
        // second, so a stream of fire does not spin it past what you wanted.
        if let i = pows.firstIndex(where: { $0.kind != .charm && near(p, $0.p, 11, 8) }) {
            if clock - pows[i].changedAt > 0.25 {
                pows[i].kind = pows[i].kind.next
                pows[i].changedAt = clock
                pop(pows[i].p, arcade.pow)
            }
            return true
        }
        if !hunting, let f = food, near(p, center(of: f), 7, 7) { burstFruit(f); return true }
        return false
    }

    /// The laser's tick: everything in the ship's column, all at once.
    private func burnColumn() {
        let x = ship.x, top = ship.y - 10
        func inColumn(_ p: CGPoint, _ half: CGFloat) -> Bool { abs(p.x - x) < half && p.y < top }
        if let b = boss, abs(b.p.x - x) < 27 * Self.bossScale, b.p.y < top { damageBoss(at: CGPoint(x: x, y: b.p.y + 30)) }
        for m in formation.presentIndices where inColumn(formation.center(m), 9) { damageMember(m, at: formation.center(m)) }
        for d in divers.indices.reversed() where inColumn(divers[d].p, 10) { damageDiver(d, at: divers[d].p) }
        for j in brood.indices.reversed() where inColumn(brood[j].p, brood[j].kind.reach.width) { damageJelly(j, at: brood[j].p) }
        if let m = mothership, inColumn(m.p, 17) { damageMothership(at: m.p) }
        if let r = raid { for k in 0 ..< 5 where r.alive[k] && inColumn(raiderPosition(r, k).0, 10) { damageRaider(k) } }
        if !hunting, let f = food, inColumn(center(of: f), 7) { burstFruit(f) }
    }

    private func collide(_ dt: Double) {
        var spent = IndexSet()
        for (i, s) in shots.enumerated() where strike(s.p) {
            spent.insert(i)
        }
        shots.remove(atOffsets: spent)
        if laserOn, !rolling {
            laserTick -= dt
            if laserTick <= 0 {
                laserTick = 0.06
                burnColumn()
            }
        }

        // The snake eats whatever invader its head runs into, and grows.
        let head = center(of: snake[0])
        for m in formation.presentIndices where near(head, formation.center(m), 12, 10) {
            formation.members[m].alive = false
            if charmed { score += formation.members[m].alien.points }
            growth += 2
            pop(formation.center(m), arcade.snake)
        }
        if let d = divers.firstIndex(where: { near(head, $0.p, 12, 10) }) {
            if charmed { score += divers[d].alien.points }
            growth += 2
            pop(divers[d].p, arcade.snake)
            let gone = divers.remove(at: d)
            if gone.col >= 0 { formation.members[gone.col].alive = false }
        }

        // Wingmen take a hit each before the ship does.
        var dead = IndexSet()
        for (i, b) in bombs.enumerated() {
            if let w = wingmanSpots.firstIndex(where: { near(b.p, $0, 8, 7) }), !rolling {
                loseWingman(at: w)
                dead.insert(i)
            } else if near(b.p, ship, 8, 8) {
                dead.insert(i)
                hurt()
            }
        }
        bombs.remove(atOffsets: dead)
        if let d = divers.firstIndex(where: { near($0.p, ship, 13, 12) }) {
            pop(divers[d].p, ArcadeDraw.invaderTint(arcade, row: divers[d].row))
            let gone = divers.remove(at: d)
            if gone.col >= 0 { formation.members[gone.col].alive = false }
            hurt()
        }
        for (w, spot) in wingmanSpots.enumerated().reversed() where !rolling {
            if let d = divers.firstIndex(where: { near($0.p, spot, 11, 10) }) {
                pop(divers[d].p, ArcadeDraw.invaderTint(arcade, row: divers[d].row))
                let gone = divers.remove(at: d)
                if gone.col >= 0 { formation.members[gone.col].alive = false }
                loseWingman(at: w)
            }
        }
        if let j = brood.firstIndex(where: { $0.kind != .saucer && near($0.p, ship, $0.kind.reach.width + 4, $0.kind.reach.height + 4) }) {
            pop(brood[j].p, BroodPalette.rim)
            brood.remove(at: j)
            hurt()
        }
        for (w, spot) in wingmanSpots.enumerated().reversed() where !rolling {
            if let j = brood.firstIndex(where: { $0.kind != .saucer && near($0.p, spot, $0.kind.reach.width + 2, $0.kind.reach.height + 2) }) {
                pop(brood[j].p, BroodPalette.rim)
                brood.remove(at: j)
                loseWingman(at: w)
            }
        }
        if let j = brood.firstIndex(where: { $0.kind != .saucer && near(head, $0.p, 12, 10) }) {
            if charmed { score += brood[j].kind.points }
            growth += 2
            pop(brood[j].p, arcade.snake)
            brood.remove(at: j)
        }
        if let r = raid, (0 ..< 5).contains(where: { r.alive[$0] && near(raiderPosition(r, $0).0, ship, 13, 11) }) {
            hurt()
        }
        if hunting, !charmed, near(head, ship, 12, 12) {
            hurt()
        }
        if bossHit(ship, pad: -10) {
            hurt()
        }

        if let i = pows.firstIndex(where: { near($0.p, ship, 22, 22) }) {
            apply(pows[i].kind)
            // Every POW is also a life: the rounds get frantic, and the
            // pickup is the breather. Nine fit the HUD's row.
            lives = min(9, lives + 1)
            pop(pows[i].p, arcade.pow, big: true)
            pop(ship, arcade.star, big: true)
            pows.remove(at: i)
            score += 1_000
            PlatformHaptics.success()
        }
    }

    private func loseWingman(at index: Int) {
        pop(wingmanSpots[index], arcade.star)
        if shields > 0 {
            shields -= 1
            return
        }
        wingmen -= 1
        PlatformHaptics.impact()
    }

    private func apply(_ power: ArcadePower) {
        switch power {
        case .wide:
            wideLevel = min(2, wideLevel + 1)
            callout = (wideLevel == 2 ? "Wider!" : "Wide!", clock)
        case .wingmen:
            // A second pickup shields the pair already flying.
            if wingmen == 2 {
                shields = 2
                callout = ("Shields!", clock)
            } else {
                wingmen = 2
                callout = ("Wingmen!", clock)
            }
        case .loop:
            loops = min(5, loops + 1)
            callout = ("Extra roll!", clock)
        case .laser:
            laserUntil = max(laserUntil, clock) + 6
            callout = ("Laser!", clock)
        case .charm:
            charmedUntil = max(charmedUntil, clock) + 10
            callout = ("Snake charmed!", clock)
        case .bomb:
            callout = ("Bomb!", clock)
            for m in formation.presentIndices {
                score += formation.members[m].alien.points
                pop(formation.center(m), ArcadeDraw.invaderTint(arcade, row: formation.members[m].tint), big: true)
            }
            for i in formation.members.indices { formation.members[i].alive = false }
            for d in divers { score += 50; pop(d.p, ArcadeDraw.invaderTint(arcade, row: d.row), big: true) }
            divers.removeAll()
            for j in brood {
                score += j.kind.points
                pop(j.p, BroodPalette.rim, big: true)
            }
            brood.removeAll()
            bombs.removeAll()
            if var b = boss, b.dyingAt == nil {
                b.hp = max(1, b.hp - 25)
                b.flash = 0.2
                boss = b
            }
        }
    }

    private func hurt() {
        guard !isOver, clock >= invulnerableUntil, !rolling else { return }
        lives -= 1
        pop(ship, arcade.star, big: true)
        PlatformHaptics.impact()
        // 1942's rule: a life lost takes the power-ups with it.
        wideLevel = 0
        wingmen = 0
        shields = 0
        laserUntil = -1
        loops = 3
        invulnerableUntil = clock + 2
        if lives <= 0 { overAt = clock }
    }

    // MARK: Drawing

    private func drawBoss(_ b: Boss, in context: inout GraphicsContext, dark: Bool) {
        let t = clock - b.start
        context.drawLayer { layer in
            layer.translateBy(x: b.p.x, y: b.p.y)
            layer.scaleBy(x: Self.bossScale, y: Self.bossScale)
            if let dying = b.dyingAt { layer.opacity = max(0, 1 - (clock - dying) / 1.5) }
            JellySpecies.bitjelly.draw(in: &layer, time: t, motion: Self.bossMotion, bell: arcade.snake, dark: dark, showFace: true)
        }
        // A hit flashes the bell white for a frame or two.
        if b.flash > 0 {
            let bell = CGRect(x: b.p.x - 27 * Self.bossScale, y: b.p.y - 20 * Self.bossScale, width: 54 * Self.bossScale, height: 36 * Self.bossScale)
            context.fill(Path(roundedRect: bell, cornerRadius: 12), with: .color(arcade.star.opacity(0.18)))
        }
        guard b.dyingAt == nil else { return }
        // Its health, across the whole field, in tenths.
        let bar = CGRect(x: 20, y: formationTop - 26, width: size.width - 40, height: 9)
        let left = CGFloat(b.hp) / CGFloat(b.maxHP)
        context.fill(Path(bar), with: .color(arcade.star.opacity(0.12)))
        context.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * left, height: bar.height)), with: .color(b.hp * 2 < b.maxHP ? arcade.raider : arcade.border))
        var ticks = Path()
        for k in 1 ..< 10 {
            let x = bar.minX + bar.width * CGFloat(k) / 10
            ticks.move(to: CGPoint(x: x, y: bar.minY))
            ticks.addLine(to: CGPoint(x: x, y: bar.maxY))
        }
        context.stroke(ticks, with: .color(.black.opacity(0.45)), lineWidth: 1)
        context.stroke(Path(bar.insetBy(dx: -1.5, dy: -1.5)), with: .color(arcade.star.opacity(0.7)), lineWidth: 1.5)
    }

    private func drawAlien(_ alien: ArcadeAlien, hp: Int, tint: Int, frame: Int, at p: CGPoint, in context: inout GraphicsContext) {
        switch alien {
        case .plain:
            ArcadeDraw.sprite(ArcadeSprite.invaders[tint % 3][frame], at: p, color: ArcadeDraw.invaderTint(arcade, row: tint), glow: false, in: &context)
        case .shielded:
            ArcadeDraw.sprite(ArcadeSprite.shielded[frame], at: p, color: arcade.star, glow: false, in: &context)
            if hp < alien.hp {
                ArcadeDraw.sprite(ArcadeSprite.crack, at: p, color: .black.opacity(0.75), glow: false, in: &context)
            }
        case .splitter:
            let halves = ArcadeSprite.splitter[frame]
            ArcadeDraw.sprite(halves.left, at: p, color: arcade.invader, glow: false, in: &context)
            ArcadeDraw.sprite(halves.right, at: p, color: arcade.border, glow: false, in: &context)
        case .mini:
            ArcadeDraw.sprite(ArcadeSprite.mini[frame], at: p, color: tint == 0 ? arcade.invader : arcade.border, glow: false, in: &context)
        }
    }

    /// What you are carrying, in the bottom-left corner: a capsule per power,
    /// pips for the spread's level, a draining bar for the timed ones.
    private func drawPowers(in context: inout GraphicsContext, t: Double) {
        var held: [(ArcadePower, Double?, Int)] = []
        if wideLevel > 0 { held.append((.wide, nil, wideLevel)) }
        if wingmen > 0 { held.append((.wingmen, nil, shields)) }
        if laserOn { held.append((.laser, (laserUntil - t) / 6, 0)) }
        if charmed { held.append((.charm, (charmedUntil - t) / 10, 0)) }
        for (i, (power, left, pips)) in held.enumerated() {
            let at = CGPoint(x: 26 + CGFloat(i) * 30, y: size.height - 46)
            let capsule = CGRect(x: at.x - 11, y: at.y - 8, width: 22, height: 16)
            context.fill(Path(roundedRect: capsule, cornerRadius: 4), with: .color((power == .charm ? arcade.food : arcade.pow).opacity(0.85)))
            context.fill(ArcadeSprite.pows[power]!.applying(CGAffineTransform(translationX: at.x, y: at.y)), with: .color(.black.opacity(0.8)))
            if let left {
                let bar = CGRect(x: capsule.minX, y: capsule.maxY + 3, width: capsule.width, height: 2)
                context.fill(Path(bar), with: .color(arcade.star.opacity(0.2)))
                context.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(max(0, min(1, left))), height: bar.height)), with: .color(arcade.star))
            }
            for k in 0 ..< pips {
                context.fill(Path(CGRect(x: capsule.minX + 2 + CGFloat(k) * 5, y: capsule.maxY + 3, width: 3, height: 3)), with: .color(arcade.snake))
            }
        }
    }

    /// `clock` is the frame being drawn, passed in so the canvas captures it.
    func draw(in context: inout GraphicsContext, dark: Bool, clock t: Double) {
        // The fruit's blast shakes the whole field for half a second.
        // Negative until the fruit is shot, so nothing below fires early.
        let sinceEgg = egg.map { t - $0.at } ?? -1
        if sinceEgg >= 0, sinceEgg < 0.5 {
            let a = 6 * (1 - sinceEgg / 0.5)
            context.translateBy(x: a * sin(t * 90), y: a * cos(t * 73))
        }
        // The snake. Once the fruit is shot it is your enemy, and it turns red
        // from the head back, one segment every 30 ms.
        for (k, c) in snake.enumerated() {
            let rect = CGRect(x: CGFloat(c.0) * cell + 1, y: CGFloat(c.1) * cell + 1, width: cell - 2, height: cell - 2)
            let isHead = k == 0
            let red = sinceEgg >= 0 && sinceEgg > Double(k) * 0.03
            // Charmed it wears the invaders' green, flickering as it wears off.
            let charm = charmed && (charmedUntil - t > 2 || Int(t * 8) % 2 == 0)
            let color = switch (isHead, charm, red) {
            case (true, true, _): arcade.invader
            case (false, true, _): arcade.invader.mix(with: .black, by: 0.3)
            case (true, false, true): arcade.raider
            case (false, false, true): arcade.raider.mix(with: .black, by: 0.25)
            case (true, false, false): arcade.snake
            case (false, false, false): arcade.snakeBody
            }
            let fade = max(0.45, 0.95 - Double(k) * 0.025)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(isHead ? 1 : fade)))
            if isHead {
                for ex in [0.3, 0.7] {
                    context.fill(Path(CGRect(x: rect.minX + rect.width * ex - 1, y: rect.minY + 3, width: 2, height: 2)), with: .color(red ? arcade.pow : .black.opacity(0.8)))
                }
            }
        }
        if let f = food {
            let r = CGRect(x: CGFloat(f.0) * cell + 2, y: CGFloat(f.1) * cell + 2, width: cell - 4, height: cell - 4)
            let blink = 0.6 + 0.4 * (sin(t * 2 * 6.28) > 0 ? 1 : 0)
            context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(arcade.food.opacity(blink)))
        }
        for m in formation.presentIndices {
            let member = formation.members[m]
            drawAlien(member.alien, hp: member.hp, tint: member.tint, frame: formation.march, at: formation.center(m), in: &context)
        }
        for d in divers {
            drawAlien(d.alien, hp: d.hp, tint: d.row, frame: Int(d.age * 6) % 2, at: d.p, in: &context)
        }
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
        if let r = raid {
            for i in 0 ..< 5 where r.alive[i] {
                ArcadeDraw.sprite(ArcadeSprite.raider, at: raiderPosition(r, i).0, color: arcade.raider, glow: false, in: &context)
            }
        }
        for p in pows {
            let at = CGPoint(x: p.p.x + 6 * sin((t - p.born) * 3), y: p.p.y)
            // A shot that turns it swells it for a beat, so the change reads.
            let swell: CGFloat = t - p.changedAt < 0.15 ? 1.25 : 1
            let capsule = CGRect(x: at.x - 11 * swell, y: at.y - 8 * swell, width: 22 * swell, height: 16 * swell)
            // Charm is the rare one: the fruit's magenta, not the POW yellow.
            context.fill(Path(roundedRect: capsule, cornerRadius: 4), with: .color((p.kind == .charm ? arcade.food : arcade.pow).opacity(0.9)))
            context.fill(ArcadeSprite.pows[p.kind]!.applying(CGAffineTransform(translationX: at.x, y: at.y)), with: .color(.black.opacity(0.8)))
        }
        for s in shots { ArcadeDraw.shot(at: s.p, color: arcade.star, in: &context) }
        if let b = boss { drawBoss(b, in: &context, dark: dark) }
        for b in bombs {
            if b.orb {
                context.fill(Path(ellipseIn: CGRect(x: b.p.x - 3, y: b.p.y - 3, width: 6, height: 6)), with: .color(arcade.border))
                context.fill(Path(CGRect(x: b.p.x - 1, y: b.p.y - 1, width: 2, height: 2)), with: .color(arcade.star))
            } else {
                ArcadeDraw.bomb(at: b.p, color: arcade.raider, time: t, in: &context)
            }
        }
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
        drawPowers(in: &context, t: t)
        guard !isOver else { return }
        // The laser, from the nose to the top of the field.
        if laserOn, !rolling {
            let flick = 0.8 + 0.2 * sin(t * 50)
            let beam = CGRect(x: ship.x - 4, y: 0, width: 8, height: ship.y - 10)
            context.fill(Path(beam), with: .color(arcade.border.opacity(0.35 * flick)))
            context.fill(Path(beam.insetBy(dx: 2.5, dy: 0)), with: .color(arcade.star.opacity(flick)))
        }
        // Blinks while it cannot be hit; a roll turns it over and lifts it.
        let blinking = t < invulnerableUntil && Int(t * 10) % 2 == 1
        guard !blinking else { return }
        let u = min(1, (t - rollStart) / 1.0)
        let lift: CGFloat = rolling ? 1 + 0.5 * CGFloat(sin(u * .pi)) : 1
        let spin: Angle = rolling ? .radians(u * 2 * .pi) : .zero
        for (i, w) in wingmanSpots.enumerated() {
            ArcadeDraw.sprite(ArcadeSprite.wingman, at: w, color: arcade.snake, glow: false, rotation: spin, scale: lift, in: &context)
            if i < shields {
                context.stroke(Path(ellipseIn: CGRect(x: w.x - 9, y: w.y - 9, width: 18, height: 18)), with: .color(arcade.snake.opacity(0.5 + 0.3 * sin(t * 6))), lineWidth: 1.2)
            }
        }
        ArcadeDraw.ship(at: ship, arcade: arcade, time: t, glow: dark, rotation: spin, scale: lift, in: &context)
    }
}
