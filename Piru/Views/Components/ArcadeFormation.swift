import SwiftUI

/// Play mode's formation. The backdrop's is a fixed 6 × 3 block on a bit
/// mask; this one grows with the waves, takes a new shape each wave, and
/// carries an alien and its health in every slot.
nonisolated struct ArcadeFormation {
    struct Member {
        /// Where the slot sits from the formation's origin.
        let offset: CGPoint
        /// -1 or 1 in the two-squad shape, which opens and closes; else 0.
        let squad: CGFloat
        let tint: Int
        var alien: ArcadeAlien
        var hp: Int
        var alive = true
        /// Out on a dive; the slot waits for it.
        var away = false

        var present: Bool { alive && !away }
    }

    enum Shape: CaseIterable {
        case block
        case chevron
        case diamond
        case squads
    }

    var origin: CGPoint
    var dir: CGFloat = 1
    var members: [Member]
    var march = 0
    private var marchClock = 0.0
    private var age = 0.0
    let total: Int

    init(origin: CGPoint, members: [Member]) {
        self.origin = origin
        self.members = members
        total = max(1, members.count)
    }

    /// The backdrop's block, exactly as the tap found it.
    static func handoff(origin: CGPoint, alive: UInt32) -> ArcadeFormation {
        var members: [Member] = []
        for row in 0 ..< InvaderTape.rows {
            for col in 0 ..< InvaderTape.cols {
                let at = InvaderTape.invaderCenter(origin: .zero, col: col, row: row)
                let live = alive & (1 << UInt32(row * InvaderTape.cols + col)) != 0
                members.append(Member(offset: at, squad: 0, tint: row, alien: .plain, hp: 1, alive: live))
            }
        }
        return ArcadeFormation(origin: origin, members: members)
    }

    /// Slot index for a backdrop diver's grid position.
    static func handoffIndex(col: Int, row: Int) -> Int {
        row * InvaderTape.cols + col
    }

    /// Wave `wave`'s formation: wider and deeper as the waves go on, a new
    /// shape each wave, armor on the front row from the third, and splitters
    /// scattered through it from the second.
    static func wave(_ wave: Int, width: CGFloat, top: CGFloat, rng: inout SeededRNG) -> ArcadeFormation {
        let spacing = InvaderTape.spacing
        let cols = min(8, 6 + (wave - 1) / 2)
        let rows = wave >= 4 ? 4 : 3
        let shape = Shape.allCases[(wave - 1) % Shape.allCases.count]
        var slots: [(col: Double, row: Int, squad: CGFloat)] = []
        let mid = Double(cols - 1) / 2
        switch shape {
        case .block:
            for r in 0 ..< rows {
                for c in 0 ..< cols { slots.append((Double(c), r, 0)) }
            }
        case .chevron:
            // A V pointing down at the ship, two or three thick.
            let n = rows + 1
            for r in 0 ..< n {
                let arm = mid * (1 - Double(r) / Double(n - 1))
                for c in 0 ..< cols where abs(abs(Double(c) - mid) - arm) <= 1 {
                    slots.append((Double(c), r, 0))
                }
            }
        case .diamond:
            let n = rows + 2
            let rmid = Double(n - 1) / 2
            for r in 0 ..< n {
                for c in 0 ..< cols where abs(Double(c) - mid) / max(mid, 1) + abs(Double(r) - rmid) / max(rmid, 1) <= 1.05 {
                    slots.append((Double(c), r, 0))
                }
            }
        case .squads:
            // Two blocks a column apart; they open and close as they march.
            let half = cols / 2
            for r in 0 ..< rows {
                for c in 0 ..< half {
                    slots.append((Double(c) - 0.5, r, -1))
                    slots.append((Double(cols - half + c) + 0.5, r, 1))
                }
            }
        }
        let firstRow = slots.map(\.row).min() ?? 0
        let members = slots.map { slot in
            var alien = ArcadeAlien.plain
            let front = slot.row == firstRow
            if wave >= 3, front || (wave >= 6 && slot.row == firstRow + 1 && rng.unit() < 0.5) {
                alien = .shielded
            } else if wave >= 2, rng.unit() < 0.2 {
                alien = .splitter
            }
            let at = CGPoint(x: CGFloat(slot.col) * spacing.width + ArcadeSprite.invaderSize.width / 2, y: CGFloat(slot.row) * spacing.height)
            return Member(offset: at, squad: slot.squad, tint: slot.row % 3, alien: alien, hp: alien.hp)
        }
        let lo = members.map(\.offset.x).min() ?? 0, hi = members.map(\.offset.x).max() ?? 0
        return ArcadeFormation(origin: CGPoint(x: (width - (hi - lo)) / 2 - lo, y: top), members: members)
    }

    /// How far each squad stands off its slots right now.
    private var spread: CGFloat { 22 * CGFloat(sin(age * 0.8)) }

    func center(_ i: Int) -> CGPoint {
        let m = members[i]
        return CGPoint(x: origin.x + m.offset.x + m.squad * spread, y: origin.y + m.offset.y)
    }

    var liveCount: Int { members.count(where: \.alive) }
    var isCleared: Bool { !members.contains(where: \.alive) }
    var presentIndices: [Int] { members.indices.filter { members[$0].present } }

    /// The lowest alien still in formation, for landing.
    var lowestY: CGFloat? {
        presentIndices.map { center($0).y }.max()
    }

    /// One step of the march: across, down at a wall, quicker as it thins.
    /// The walls are found from the aliens still in it, the arcade's way —
    /// clear a flank and the rest marches further out.
    mutating func step(_ dt: Double, wave: Int, width: CGFloat, hurry: CGFloat) {
        age += dt
        let lost = 1 - CGFloat(liveCount) / CGFloat(total)
        let speed = (20 + 4 * CGFloat(wave) + 40 * lost) * hurry
        origin.x += dir * speed * dt
        let xs = presentIndices.map { center($0).x }
        if let lo = xs.min(), let hi = xs.max(), lo < 16 || hi > width - 16 {
            dir = lo < 16 ? 1 : -1
            origin.x += dir * speed * dt
            origin.y += 10
        }
        marchClock += dt
        if marchClock > max(0.18, 0.5 - Double(wave) * 0.03 - Double(lost) * 0.2) {
            marchClock = 0
            march ^= 1
        }
    }
}
