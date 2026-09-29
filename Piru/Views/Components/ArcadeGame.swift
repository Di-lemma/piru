import SwiftUI

// MARK: - The round

/// One round, stepped by whoever draws it. The backdrop runs one with the
/// pilot flying (`idle`), and tapping the ship hands that same round over:
/// `takeOver()` gives it you from exactly where it was. Not observed: its
/// views read it every frame anyway, so observation would only add
/// bookkeeping. What they draw is a value, `scene`.
@MainActor
final class ArcadeGame {
    typealias Shot = ArcadeShot
    typealias Bomb = ArcadeBomb
    typealias Pow = ArcadePow
    typealias Burst = ArcadeBurst
    typealias Diver = ArcadeRules.Diver

    let size: CGSize
    let arcade: SkinArcade

    /// The pilot is flying: the round cannot be lost, the fruit cannot be
    /// burst, waves loop through the first four, and rolls are free.
    private(set) var idle: Bool
    private var clock = 0.0
    private var lastDate: Double
    /// When you took the ship, on the round's clock.
    private(set) var startedAt = 0.0
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var loops = 3
    private var overAt: Double?
    var isOver: Bool { overAt != nil }
    var finished: Bool { overAt.map { clock - $0 > 2.6 } ?? false }

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
    /// The ship's own bubble, in layers: each takes a hit that would have
    /// cost a life, and the power-ups with it.
    private var shield = 0
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

    private var mothership: ArcadeMothership?
    private var nextMothershipAt = 16.0
    private var boss: ArcadeBoss?
    private var shots: [Shot] = []
    private var bombs: [Bomb] = []
    private var divers: [Diver] = []
    /// Bitjelly's summons.
    private var brood: [BroodJelly] = []
    private var summons = 0
    /// How far a saucer's beam has lifted the ship off where you are steering it.
    private var tractor: CGFloat = 0
    private var raid: ArcadeRaid?
    private var nextRaidAt = 7.0
    private var nextDiveAt = 3.0
    private var pows: [Pow] = []
    private var bursts: [Burst] = []

    private var snake: ArcadeSnake
    /// The fruit was shot: the snake hunts the ship and the invaders swarm.
    private(set) var hunting = false
    /// When and where the fruit went up: the blast, the flash, the shake,
    /// and the red running down the snake all time from it.
    private var egg: (at: Double, p: CGPoint)?
    private var snakeClock = 0.0
    /// When the fruit on the board was served; it ripens from then.
    private var foodAt = 0.0

    // The pilot.
    private var velocity = CGVector.zero
    private var goal: CGPoint
    private var decideAt = 0.0
    private var focus: (() -> (x: CGFloat, y: CGFloat, vx: CGFloat)?)?
    private var focusUntil = 0.0

    private var rng: SeededRNG

    init(size: CGSize, arcade: SkinArcade, time: Double, idle: Bool) {
        self.size = size
        self.arcade = arcade
        self.idle = idle
        lastDate = time
        rng = SeededRNG(seed: UInt64(bitPattern: Int64(time * 1_000)))
        let start = CGPoint(x: size.width / 2, y: ArcadeRules.home(in: size))
        ship = start
        aim = start
        goal = start
        formation = .wave(1, width: size.width, top: max(110, size.height * 0.14), rng: &rng)
        let cell = ArcadeSnake.cell
        snake = ArcadeSnake(cols: Int(size.width / cell), rows: Int(size.height / cell), skyRows: Int(size.height * 0.52 * 0.9 / cell))
        snake.placeFood(&rng)
    }

    private func serveFood() {
        snake.placeFood(&rng)
        foodAt = clock
    }

    /// The idle round becomes yours, from exactly where it was.
    func takeOver() {
        idle = false
        startedAt = clock
        score = 0
        lives = 3
        loops = 3
        callout = nil
        aim = ship
        invulnerableUntil = clock + 1.5
        #if DEBUG
            // `-piruArcadeWave <n>` starts the round at wave n, and
            // `-piruArcadeBoss` at the tenth, Bitjelly's, for recording a wave
            // without playing up to it.
            let args = ProcessInfo.processInfo.arguments
            let startWave = args.contains("-piruArcadeBoss") ? 10 : args.firstIndex(of: "-piruArcadeWave").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
            if let startWave, startWave > 1 {
                wave = startWave - 1
                for i in formation.members.indices { formation.members[i].alive = false }
                divers = []
                nextFormationAt = nil
            }
        #endif
    }

    // MARK: Controls

    /// 1942's loop: a second or so of flying through everything. The pilot's
    /// are free; yours are counted.
    func roll() {
        guard !isOver, clock - rollStart > 1.0 else { return }
        if !idle {
            guard loops > 0 else { return }
            loops -= 1
            PlatformHaptics.impact()
        }
        rollStart = clock
        // Rolling inside a bubble thickens it.
        if shield > 0 { shield = min(3, shield + 1) }
    }

    private var rolling: Bool { clock - rollStart < 1.0 }

    // MARK: Step

    /// Steps the round up to `date` in slices of at most 1/30 s, so a slow
    /// frame rate (Low Power Mode draws at 15) plays at the right speed, and
    /// returns its clock. A gap after the app was away is capped, not replayed.
    func advance(to date: Double) -> Double {
        var left = min(0.25, max(0, date - lastDate))
        lastDate = date
        while left > 0 {
            let dt = min(left, 1 / 30)
            left -= dt
            step(dt)
        }
        return clock
    }

    private func step(_ dt: Double) {
        clock += dt
        bursts = bursts.compactMap { var b = $0; b.age += dt; return b.age < b.life ? b : nil }
        guard !isOver else { return }
        if idle { pilot(dt) } else { moveShip(dt) }
        fire(dt)
        moveFormation(dt)
        spawn()
        moveEnemies(dt)
        moveProjectiles(dt)
        stepSnake(dt)
        collide(dt)
    }

    private func moveShip(_ dt: Double) {
        let k = min(1, dt * 18)
        ship = CGPoint(x: ship.x + (aim.x - ship.x) * k, y: ship.y + (aim.y - tractor - ship.y) * k)
    }

    private var wingmanSpots: [CGPoint] {
        Array([CGPoint(x: ship.x - 26, y: ship.y + 8), CGPoint(x: ship.x + 26, y: ship.y + 8)].prefix(wingmen))
    }

    /// Every muzzle in the flight: the nose, then each wingman's. Wingmen fly
    /// your gun, so whatever the ship fires, they fire too.
    private var guns: [CGPoint] {
        [CGPoint(x: ship.x, y: ship.y - 10)] + wingmanSpots.map { CGPoint(x: $0.x, y: $0.y - 6) }
    }

    /// How much wider Wide makes the laser, on each side.
    private var beamReach: CGFloat { CGFloat(wideLevel) * 8 }

    private func fire(_ dt: Double) {
        cooldown -= dt
        // Five-way from three guns is fifteen a volley: room for eight in the air.
        guard cooldown <= 0, !rolling, shots.count < 160 else { return }
        cooldown = idle ? 0.32 : 0.2
        // The laser replaces the guns while it lasts.
        guard !laserOn else { return }
        let spread: [CGFloat] = switch wideLevel {
        case 0: [0]
        case 1: [-120, 0, 120]
        default: [-200, -100, 0, 100, 200]
        }
        for gun in guns {
            for vx in spread { shots.append(Shot(p: gun, vx: vx)) }
        }
    }

    private func moveFormation(_ dt: Double) {
        // Cleared only once the divers are down too; one still out comes home.
        if formation.isCleared, boss == nil {
            if nextFormationAt == nil {
                nextFormationAt = clock + 1.2
                wave += 1
                // The idle round loops the first four waves; Bitjelly waits for a player.
                if idle, wave > 4 { wave = 1 }
            }
            if let at = nextFormationAt, clock >= at {
                nextFormationAt = nil
                if wave % 10 == 0 {
                    let hp = 260 + wave * 10
                    boss = ArcadeBoss(p: CGPoint(x: size.width / 2, y: -80), hp: hp, maxHP: hp, start: clock, summonAt: clock + 4)
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
            bombs.append(Bomb(p: formation.center(i), v: CGVector(dx: 0, dy: ArcadeRules.bombSpeed)))
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
        // Come at it with everything and it takes it personally.
        let furious = !idle && wideLevel == 2 && wingmen == 2
        if furious, !b.furious {
            bursts.append(Burst(p: b.p, age: 0, life: 0.8, color: arcade.raider, reach: 90))
            buzz()
        }
        b.furious = furious
        if t > 2.5, b.furious {
            danmaku(&b, t: t)
            if clock >= b.summonAt {
                b.summonAt = clock + 3.5
                summon(from: CGPoint(x: b.p.x, y: b.p.y + 36), enraged: true)
            }
        } else if t > 2.5 {
            // Past half its health it presses harder: denser rings, faster shots.
            let enraged = b.hp * 2 < b.maxHP
            let origin = CGPoint(x: b.p.x, y: b.p.y + 10)
            func orb(_ from: CGPoint, angle a: Double, speed v: Double) {
                bombs.append(Bomb(p: from, v: CGVector(dx: cos(a) * v, dy: sin(a) * v), orb: true))
            }
            // A ring on every contraction, rotated a little each time.
            let beat = Int(t / ArcadeBoss.beatPeriod)
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

    /// Furious: Touhou-thick. Two rings a beat curling opposite ways, two
    /// five-armed flowers turning against each other, and a seven-way fan at
    /// the ship. The ship is hit only at its core meanwhile (see `collide`).
    private func danmaku(_ b: inout ArcadeBoss, t: Double) {
        guard bombs.count < 700 else { return }
        let enraged = b.hp * 2 < b.maxHP
        let origin = CGPoint(x: b.p.x, y: b.p.y + 10)
        func orb(_ from: CGPoint, angle a: Double, speed v: Double, curl: Double = 0) {
            bombs.append(Bomb(p: from, v: CGVector(dx: cos(a) * v, dy: sin(a) * v), orb: true, curl: curl))
        }
        let beat = Int(t / ArcadeBoss.beatPeriod)
        if beat != b.beat {
            b.beat = beat
            let n = enraged ? 48 : 36
            for k in 0 ..< n {
                let a = Double(k) / Double(n) * 2 * .pi + Double(beat) * 0.26
                orb(origin, angle: a, speed: 125, curl: 0.35)
                orb(origin, angle: a + .pi / Double(n), speed: 90, curl: -0.35)
            }
        }
        if clock - b.spiralAt > (enraged ? 0.07 : 0.09) {
            b.spiralAt = clock
            for arm in 0 ..< 5 {
                let step = Double(arm) / 5 * 2 * .pi
                orb(origin, angle: t * 1.9 + step, speed: 145, curl: 0.5)
                orb(origin, angle: -t * 1.3 + step, speed: 115, curl: -0.5)
            }
        }
        if clock - b.aimedAt > 0.7 {
            b.aimedAt = clock
            let from = CGPoint(x: b.p.x, y: b.p.y + 30)
            let aim = atan2(ship.y - from.y, ship.x - from.x)
            for k in -3 ... 3 {
                orb(from, angle: aim + Double(k) * 0.14, speed: 230)
            }
        }
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
        return near(p, CGPoint(x: b.p.x, y: b.p.y - 2), 27 * ArcadeBoss.scale + pad, 18 * ArcadeBoss.scale + pad)
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
            raid = ArcadeRaid(start: clock, fromLeft: rng.unit() < 0.5)
        }
        if wave >= 2, mothership == nil, clock >= nextMothershipAt {
            let fromLeft = rng.unit() < 0.5
            mothership = ArcadeMothership(p: CGPoint(x: fromLeft ? -24 : size.width + 24, y: formationTop - 18), vx: fromLeft ? 80 : -80)
        }
    }

    private func raiderPosition(_ raid: ArcadeRaid, _ i: Int) -> (CGPoint, Double) {
        raid.position(i, at: clock, top: formationTop, width: size.width)
    }

    private func moveEnemies(_ dt: Double) {
        let head = snake.head
        divers = divers.compactMap { d in
            var d = d
            let slot = d.col >= 0 ? formation.center(d.col) : .zero
            // It comes in on a flank, beside the ship on the side it is already
            // on, and cuts in only once it is low, so holding still under your
            // own fire does not line the dive up in front of the gun.
            let committed = d.p.y > ship.y - 100
            let flank = committed ? ship : CGPoint(x: ship.x + (d.p.x < ship.x ? -20 : 20), y: ship.y)
            let flying = ArcadeRules.steer(&d, toward: flank, slot: slot, bottom: size.height + 20, dt: dt, speed: hunting ? 1.25 : 1.1)
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
                bombs.append(Bomb(p: orb, v: CGVector(dx: 0, dy: ArcadeRules.bombSpeed), orb: true))
            }
            // The quick ones sidestep your fire too; Lantern and Saucer are
            // the slow, tough ones and take it.
            if brood[i].dodges, brood[i].p.y < ship.y - 100 {
                dodge(&brood[i].p, agility: brood[i].kind == .pip ? 0.7 : 0.5, dt: dt)
            }
            guard brood[i].kind == .saucer, brood[i].beaming(at: clock) else { continue }
            // The tractor beam: lifts the ship while it stays in the cone; a
            // wingman caught in it is taken.
            if !rolling, !idle, brood[i].inBeam(ship, bottom: size.height) {
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
            shots[i].p.y -= ArcadeRules.shotSpeed * dt
        }
        shots.removeAll { $0.p.y < -10 || $0.p.x < -10 || $0.p.x > size.width + 10 }
        for i in bombs.indices {
            if bombs[i].curl != 0 {
                let a = bombs[i].curl * dt, v = bombs[i].v
                bombs[i].v = CGVector(dx: v.dx * cos(a) - v.dy * sin(a), dy: v.dx * sin(a) + v.dy * cos(a))
            }
            bombs[i].p.x += bombs[i].v.dx * dt
            bombs[i].p.y += bombs[i].v.dy * dt
        }
        bombs.removeAll { $0.p.y > size.height + 10 || $0.p.y < -10 || $0.p.x < -10 || $0.p.x > size.width + 10 }
        for i in pows.indices { pows[i].p.y += 55 * dt }
        pows.removeAll { $0.p.y > size.height + 20 }
    }

    // MARK: Pilot

    /// What the pilot is shooting at, re-picked every couple of seconds.
    private func pickFocus() {
        focusUntil = clock + 1.4 + rng.unit() * 1.6
        let present = formation.presentIndices
        if let d = divers.first(where: { !$0.returning && $0.age > 0.7 && $0.p.y < ship.y - 40 }), rng.unit() < 0.6 {
            let key = (d.col, d.row, d.side)
            focus = { [unowned self] in
                guard let d = divers.first(where: { ($0.col, $0.row, $0.side) == key && !$0.returning }) else { return nil }
                return (d.p.x, d.p.y, d.v.dx)
            }
        } else if let m = mothership, rng.unit() < 0.5 {
            let vx = m.vx
            focus = { [unowned self] in mothership.map { ($0.p.x, $0.p.y, vx) } }
        } else if !brood.isEmpty, rng.unit() < 0.6 {
            let phase = brood[Int(rng.next() % UInt64(brood.count))].phase
            focus = { [unowned self] in brood.first { $0.phase == phase }.map { ($0.p.x, $0.p.y, $0.v.dx) } }
        } else if !present.isEmpty {
            // The column nearest where the ship is headed, now and then another.
            let offsets = Array(Set(present.map { formation.members[$0].offset.x }))
            let nearest = offsets.min { abs(formation.origin.x + $0 - goal.x) < abs(formation.origin.x + $1 - goal.x) }!
            let col = rng.unit() < 0.7 ? nearest : offsets[Int(rng.next() % UInt64(offsets.count))]
            focus = { [unowned self] in
                let live = formation.presentIndices.filter { formation.members[$0].offset.x == col }
                guard let low = live.map({ formation.center($0) }).max(by: { $0.y < $1.y }) else { return nil }
                let lost = 1 - CGFloat(formation.liveCount) / CGFloat(formation.total)
                return (low.x, low.y, formation.dir * (20 + 4 * CGFloat(wave) + 40 * lost))
            }
        } else {
            focus = nil
        }
    }

    /// How bad it would be to be at `c`, arriving in `reach` seconds and
    /// staying a moment.
    private func danger(at c: CGPoint, reach: Double) -> CGFloat {
        var d: CGFloat = 0
        for t in [reach, reach + 0.12, reach + 0.3, reach + 0.5] {
            let t = CGFloat(t)
            for b in bombs where near(CGPoint(x: b.p.x + b.v.dx * t, y: b.p.y + b.v.dy * t), c, 13, 15) { d += 60 }
            for q in divers where !q.returning && near(CGPoint(x: q.p.x + q.v.dx * t, y: q.p.y + q.v.dy * t), c, 22, 22) { d += 45 }
            for j in brood where near(CGPoint(x: j.p.x + j.v.dx * t, y: j.p.y + j.v.dy * t), c, 20, 20) { d += 45 }
            if let r = raid {
                for k in 0 ..< 5 where r.alive[k] {
                    let p = raiderPosition(r, k).0
                    if near(CGPoint(x: p.x + (r.fromLeft ? 110 : -110) * t, y: p.y), c, 18, 16) { d += 45 }
                }
            }
        }
        if bossHit(c, pad: 20) { d += 200 }
        return d
    }

    private func pilot(_ dt: Double) {
        if focus == nil || clock >= focusUntil || focus?() == nil { pickFocus() }
        if clock >= decideAt {
            decideAt = clock + 0.08
            let aimAt = focus?(), rest = ArcadeRules.Pilot.home(ArcadeRules.home(in: size), at: clock)
            let yMin = ArcadeRules.home(in: size) - 114, yMax = min(size.height - 70, ArcadeRules.home(in: size) + 290)
            var best = goal, bestCost = CGFloat.infinity
            for ox in ArcadeRules.Pilot.offsets {
                for oy in ArcadeRules.Pilot.lifts {
                    let c = CGPoint(x: max(16, min(size.width - 16, ship.x + ox)), y: max(yMin, min(yMax, ship.y + oy)))
                    let dist = hypot(c.x - ship.x, c.y - ship.y), reach = Double(dist / 200)
                    var cost = danger(at: c, reach: reach)
                    // A led shot: aim where the target will be when a shot from c gets there.
                    if let aimAt {
                        let lead = aimAt.x + aimAt.vx * max(0, c.y - 10 - aimAt.y) / ArcadeRules.shotSpeed
                        cost += min(abs(c.x - lead), 100)
                    }
                    cost += abs(c.y - rest) * 0.05
                    cost += hypot(c.x - goal.x, c.y - goal.y) * 0.06 + dist * 0.03
                    if c.x < 34 || c.x > size.width - 34 { cost += 12 }
                    // And a falling POW is worth a detour.
                    for p in pows where hypot(p.p.x - c.x, p.p.y + 55 * CGFloat(reach) - c.y) < 24 { cost -= 45 }
                    if cost < bestCost { bestCost = cost; best = c }
                }
            }
            goal = best
        }
        // Steering: a capped speed and a capped change in it, so it curves.
        let a = ArcadeRules.Pilot.accel * CGFloat(dt), cap = ArcadeRules.Pilot.speed
        let want = CGVector(dx: max(-cap, min(cap, (goal.x - ship.x) * 5)), dy: max(-cap, min(cap, (goal.y - ship.y) * 5)))
        velocity.dx += max(-a, min(a, want.dx - velocity.dx))
        velocity.dy += max(-a, min(a, want.dy - velocity.dy))
        ship = CGPoint(x: max(16, min(size.width - 16, ship.x + velocity.dx * CGFloat(dt))), y: max(80, min(size.height - 50, ship.y + velocity.dy * CGFloat(dt))))
        aim = ship
        // Something about to land where it is going: roll through it.
        guard !rolling else { return }
        let soon = [0.06, 0.12, 0.18].contains { t in
            let t = CGFloat(t)
            let at = CGPoint(x: ship.x + velocity.dx * t, y: ship.y + velocity.dy * t)
            return bombs.contains { near(CGPoint(x: $0.p.x + $0.v.dx * t, y: $0.p.y + $0.v.dy * t), at, 9, 10) }
                || divers.contains { !$0.returning && near(CGPoint(x: $0.p.x + $0.v.dx * t, y: $0.p.y + $0.v.dy * t), at, 14, 13) }
        }
        if soon { roll() }
    }

    // MARK: Snake

    private func stepSnake(_ dt: Double) {
        snakeClock += dt
        // Set on you, it winds up to its hunting pace over three seconds
        // rather than lunging from the first step.
        let windUp = egg.map { min(1, (clock - $0.at) / 3) } ?? 1
        let interval = hunting ? 0.19 - 0.05 * windUp : 0.19
        while snakeClock >= interval {
            snakeClock -= interval
            let cell = ArcadeSnake.cell
            let goal: ArcadeSnake.Cell = if charmed, let prey = nearestPrey(to: snake.head) {
                (Int(prey.x / cell), Int(prey.y / cell))
            } else if hunting {
                (Int(ship.x / cell), Int(ship.y / cell))
            } else {
                snake.food ?? (snake.cols / 2, snake.skyRows / 2)
            }
            switch snake.step(toward: goal, rng: &rng) {
            case .moved: break
            case .ate: serveFood()
            case let .crashed(at):
                // It ran into itself: a burst where the head was, and a new
                // snake drops in at the top.
                for (color, reach, life) in [(arcade.snake, 18.0, 0.5), (arcade.star, 32.0, 0.7)] {
                    bursts.append(Burst(p: at, age: 0, life: life, color: color, reach: reach))
                }
            }
        }
    }

    /// Sidesteps the nearest bullet coming up underneath, away from its line.
    /// `agility` scales how hard. Only about half of them try (`dodges`, rolled
    /// when each one sets off), they see a bullet late, and nothing dodges a
    /// whole spread, so a player holding still still wins most dives.
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

    // MARK: Collisions

    private func near(_ a: CGPoint, _ b: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> Bool {
        abs(a.x - b.x) < dx && abs(a.y - b.y) < dy
    }

    private func pop(_ p: CGPoint, _ color: Color, big: Bool = false) {
        bursts.append(Burst(p: p, age: 0, life: big ? 0.7 : 0.4, color: color, reach: big ? 30 : 14))
    }

    /// Haptics are for the player; the idle round behind your journal is quiet.
    private func buzz(_ success: Bool = false) {
        guard !idle else { return }
        if success { PlatformHaptics.success() } else { PlatformHaptics.impact() }
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
            // Beating it furious pays double.
            score += b.furious ? 10_000 : 5_000
            bombs.removeAll { $0.orb }
            buzz(true)
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
        score += 100
        pop(p, arcade.raider)
        // The whole raid down: a POW where the last one fell.
        if !r.alive.contains(true) {
            score += 500
            pows.append(Pow(p: p, kind: ArcadePower.random(&rng), born: clock))
        }
        raid = r
    }

    /// The egg: the fruit is shot, and the snake turns on you.
    private func burstFruit(_ f: ArcadeSnake.Cell) {
        hunting = true
        snake.food = nil
        score += 200
        let at = ArcadeSnake.center(f)
        egg = (clock, at)
        // Four rings of pixels on staggered reaches and lives, so it reads as
        // one blast opening outward rather than a pop.
        for (color, reach, life) in [(arcade.food, 26.0, 0.5), (arcade.star, 48.0, 0.7), (arcade.raider, 72.0, 0.9), (arcade.food, 100.0, 1.1)] {
            bursts.append(Burst(p: at, age: 0, life: life, color: color, reach: reach))
        }
        nextDiveAt = clock + 0.5
        buzz(true)
    }

    /// The fruit is the player's egg: in the idle round, shots pass it by,
    /// and so they do while a new one ripens.
    private var fruitTarget: ArcadeSnake.Cell? {
        idle || hunting || clock - foodAt < ArcadeRules.ripen ? nil : snake.food
    }

    /// One bullet, one target: the first thing it touches.
    private func strike(_ p: CGPoint) -> Bool {
        if bossHit(p) { damageBoss(at: p); return true }
        if let m = formation.presentIndices.first(where: { near(p, formation.center($0), 9, 8) }) { damageMember(m, at: p); return true }
        if let d = divers.firstIndex(where: { near(p, $0.p, 10, 9) }) { damageDiver(d, at: p); return true }
        if let j = brood.firstIndex(where: { near(p, $0.p, $0.kind.reach.width, $0.kind.reach.height) }) { damageJelly(j, at: p); return true }
        if let m = mothership, near(p, m.p, 17, 8) { damageMothership(at: p); return true }
        if let r = raid, let k = (0 ..< 5).first(where: { r.alive[$0] && near(p, raiderPosition(r, $0).0, 10, 8) }) { damageRaider(k); return true }
        // A shot turns a capsule into the next power-up, one step per quarter
        // second, so a stream of fire does not spin it past what you wanted.
        if let i = pows.firstIndex(where: { $0.kind != .charm && near(p, $0.p, 11, 8) }) {
            if clock - pows[i].changedAt > 0.25 {
                pows[i].kind = pows[i].kind.next
                pows[i].changedAt = clock
                pop(pows[i].p, arcade.pow)
            }
            return true
        }
        if let f = fruitTarget, near(p, ArcadeSnake.center(f), 7, 7) { burstFruit(f); return true }
        return false
    }

    /// The laser's tick: everything under any beam, all at once. A target
    /// under two beams still takes one hit a tick, so the wingmen's beams
    /// cover ground rather than melting Bitjelly three times as fast.
    private func burnColumn() {
        let beams = guns, reach = beamReach
        func beam(over p: CGPoint, _ half: CGFloat) -> CGPoint? {
            beams.first { abs(p.x - $0.x) < half + reach && p.y < $0.y }
        }
        func inColumn(_ p: CGPoint, _ half: CGFloat) -> Bool { beam(over: p, half) != nil }
        if let b = boss, let x = beam(over: b.p, 27 * ArcadeBoss.scale)?.x { damageBoss(at: CGPoint(x: x, y: b.p.y + 30)) }
        for m in formation.presentIndices where inColumn(formation.center(m), 9) { damageMember(m, at: formation.center(m)) }
        for d in divers.indices.reversed() where inColumn(divers[d].p, 10) { damageDiver(d, at: divers[d].p) }
        for j in brood.indices.reversed() where inColumn(brood[j].p, brood[j].kind.reach.width) { damageJelly(j, at: brood[j].p) }
        if let m = mothership, inColumn(m.p, 17) { damageMothership(at: m.p) }
        if let r = raid { for k in 0 ..< 5 where r.alive[k] && inColumn(raiderPosition(r, k).0, 10) { damageRaider(k) } }
        if let f = fruitTarget, inColumn(ArcadeSnake.center(f), 7) { burstFruit(f) }
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
        let head = snake.head
        for m in formation.presentIndices where near(head, formation.center(m), 12, 10) {
            formation.members[m].alive = false
            if charmed { score += formation.members[m].alien.points }
            snake.growth += 2
            pop(formation.center(m), arcade.snake)
        }
        if let d = divers.firstIndex(where: { near(head, $0.p, 12, 10) }) {
            if charmed { score += divers[d].alien.points }
            snake.growth += 2
            pop(divers[d].p, arcade.snake)
            let gone = divers.remove(at: d)
            if gone.col >= 0 { formation.members[gone.col].alive = false }
        }

        // Wingmen take a hit each before the ship does. Against a furious
        // Bitjelly its orbs play by Touhou's rules instead: the wingmen are
        // untouchable, and the ship is hit only at its core.
        let furious = boss?.furious == true
        var dead = IndexSet()
        for (i, b) in bombs.enumerated() {
            let core = furious && b.orb
            if !core, !rolling, let w = wingmanSpots.firstIndex(where: { near(b.p, $0, 8, 7) }) {
                loseWingman(at: w)
                dead.insert(i)
            } else if near(b.p, ship, core ? 3.5 : 8, core ? 3.5 : 8) {
                dead.insert(i)
                hurt()
            }
        }
        // Charmed, the snake is on your side all the way down: it swallows
        // the fire it passes through.
        if charmed {
            let cell = ArcadeSnake.cell
            let body = Set(snake.body.map { $0.x * 10_000 + $0.y })
            for (i, b) in bombs.enumerated() where body.contains(Int(b.p.x / cell) * 10_000 + Int(b.p.y / cell)) {
                dead.insert(i)
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
            snake.growth += 2
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
            buzz(true)
        }
    }

    private func loseWingman(at index: Int) {
        pop(wingmanSpots[index], arcade.star)
        if shields > 0 {
            shields -= 1
            return
        }
        wingmen -= 1
        buzz()
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
                // Arriving inside your bubble, they are in it too.
                if shield > 0 { shields = 2 }
                callout = ("Wingmen!", clock)
            }
        case .shield:
            shield = min(3, shield + 1)
            // The bubble takes in whoever is flying with you.
            shields = max(shields, wingmen)
            callout = ("Shields!", clock)
        case .loop:
            loops = min(5, loops + 1)
            callout = ("Extra roll!", clock)
        case .laser:
            laserUntil = max(laserUntil, clock) + 6
            callout = ("Laser!", clock)
        case .charm:
            charmedUntil = max(charmedUntil, clock) + 10
            // A heart makes peace: the snake stops hunting you and gets a new
            // fruit, and only another burst fruit sets it on you again.
            hunting = false
            egg = nil
            if snake.food == nil { serveFood() }
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
        // The bubble takes it: a layer gone, and a beat to get clear.
        if shield > 0 {
            shield -= 1
            invulnerableUntil = clock + 1
            bursts.append(Burst(p: ship, age: 0, life: 0.5, color: arcade.snake, reach: 24))
            buzz()
            return
        }
        invulnerableUntil = clock + 2
        pop(ship, arcade.star, big: true)
        // The idle round cannot lose; it only blinks.
        guard !idle else { return }
        lives -= 1
        buzz()
        // 1942's rule: a life lost takes the power-ups with it.
        wideLevel = 0
        wingmen = 0
        shields = 0
        laserUntil = -1
        loops = 3
        if lives <= 0 { overAt = clock }
    }

    // MARK: Drawing

    /// This frame, as a value the canvas can take off the main actor.
    var scene: ArcadeScene {
        ArcadeScene(
            arcade: arcade, size: size, clock: clock, top: formationTop, idle: idle, isOver: isOver,
            snake: snake.body, food: snake.food, nextFood: snake.nextFood, foodAt: foodAt, egg: egg, charmedUntil: charmedUntil,
            aliens: formation.presentIndices.map { i in
                let m = formation.members[i]
                return .init(alien: m.alien, hp: m.hp, tint: m.tint, frame: formation.march, p: formation.center(i))
            } + divers.map { .init(alien: $0.alien, hp: $0.hp, tint: $0.row, frame: Int($0.age * 6) % 2, p: $0.p) },
            brood: brood, mothership: mothership,
            raiders: raid.map { r in (0 ..< 5).filter { r.alive[$0] }.map { raiderPosition(r, $0).0 } } ?? [],
            pows: pows, shots: shots, bombs: bombs, bursts: bursts, boss: boss,
            ship: ship, wingmen: wingmanSpots, shields: shields, shield: shield, rollStart: rollStart,
            invulnerableUntil: invulnerableUntil, laserUntil: laserUntil, wideLevel: wideLevel, beams: guns, beamReach: beamReach,
        )
    }
}
