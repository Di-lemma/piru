import Testing
@testable import Piru

@Suite("Hebi's snake")
struct ArcadeSnakeTests {
    @Test
    func `At a wall with nothing of its own in the way, it turns rather than crashing`() {
        var snake = ArcadeSnake(cols: 10, rows: 10, skyRows: 5)
        snake.body = [(9, 0), (8, 0), (7, 0), (6, 0)]
        snake.dir = (1, 0)
        var rng = SeededRNG(seed: 1)
        let outcome = snake.step(toward: (9, 0), rng: &rng)
        guard case .moved = outcome else {
            Issue.record("expected a move, got \(outcome)")
            return
        }
        #expect(snake.body[0] == (9, 1))
    }

    @Test
    func `Boxed in by its own body, it crashes into itself and starts again at the top`() {
        var snake = ArcadeSnake(cols: 12, rows: 12, skyRows: 6)
        // Head at (5,5) heading right; ahead, below and above are all its own body.
        snake.body = [(5, 5), (4, 5), (4, 4), (5, 4), (6, 4), (6, 5), (6, 6), (5, 6), (4, 6)]
        snake.dir = (1, 0)
        var rng = SeededRNG(seed: 1)
        let outcome = snake.step(toward: (11, 5), rng: &rng)
        guard case let .crashed(at) = outcome else {
            Issue.record("expected a crash, got \(outcome)")
            return
        }
        #expect(at == ArcadeSnake.center((5, 5)))
        #expect(snake.body.count == ArcadeSnake.startLength)
        #expect(snake.body[0] == (6, 1))
    }

    @Test
    func `Over a long run it only ever crashes when its own body has closed every way out`() {
        var snake = ArcadeSnake(cols: 32, rows: 64, skyRows: 30)
        var rng = SeededRNG(seed: 0x5AAE)
        snake.placeFood(&rng)
        var crashes = 0
        for _ in 0 ..< 4_000 {
            let h = snake.body[0], d = snake.dir
            let turns: [ArcadeSnake.Cell] = [d, (-d.y, d.x), (d.y, -d.x)].map { (h.x + $0.x, h.y + $0.y) }
            let open = turns.contains { snake.inside($0) && !snake.blocked($0) }
            let ownBody = turns.contains { snake.inside($0) && snake.blocked($0) }
            switch snake.step(toward: snake.food ?? (16, 15), rng: &rng) {
            case .moved: #expect(open)
            case .ate:
                #expect(open)
                snake.placeFood(&rng)
            case .crashed:
                crashes += 1
                #expect(!open)
                #expect(ownBody, "walls alone never box it in")
            }
            #expect(snake.inside(snake.body[0]))
        }
        #expect(crashes < 40)
    }
}
