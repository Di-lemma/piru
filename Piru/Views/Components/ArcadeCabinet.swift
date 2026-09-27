import SwiftUI

// MARK: - Cabinet

/// Hebi's round. Behind every screen the backdrop plays one with the pilot
/// flying (`idle`); tap its ship and that same round is yours: the app dims,
/// the ship follows your finger and fires on its own, and everything goes on
/// from exactly where it was. Shoot the snake's fruit and it stops chasing
/// fruit and starts hunting you, and the invaders come down in a swarm.
///
/// One round at a time: the idle one is stepped by whichever backdrop is on
/// screen, so it carries on across screens, and while you play it is the
/// overlay's and the backdrop draws only its sky.
@Observable @MainActor
final class ArcadeCabinet {
    static let shared = ArcadeCabinet(defaults: .standard)

    private(set) var isPlaying = false
    private(set) var best: Int
    /// The round in play; set and cleared with `isPlaying`.
    @ObservationIgnored private(set) var game: ArcadeGame?
    /// The round the backdrop plays, made on first sight of the arcade skin.
    @ObservationIgnored private var idle: ArcadeGame?
    /// The window the backdrops fill, measured at the root.
    @ObservationIgnored var windowSize: CGSize = .zero

    private let defaults: UserDefaults
    /// Backed up with the other settings (`ExportedSettings`).
    nonisolated static let bestKey = "arcadeBestScore"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        best = defaults.integer(forKey: Self.bestKey)
    }

    /// Every touch-down in the window. One on the backdrop's ship starts a
    /// round; anywhere else, nothing.
    func touched(at point: CGPoint, reduceMotion: Bool) {
        let skins = SkinStore.shared
        guard !isPlaying, !reduceMotion, windowSize.width > 0, skins.decorationsEnabled,
              case .arcade? = skins.current.decorations?.scene,
              // Not under a sheet: the round draws beneath it, and a sheet's
              // backdrop is inset, so its ship is not where this one looks.
              !Self.sheetIsUp
        else { return }
        guard let round = idle, round.size == windowSize,
              hypot(point.x - round.ship.x, point.y - round.ship.y) < 30 else { return }
        round.takeOver()
        game = round
        idle = nil
        isPlaying = true
        PlatformHaptics.impact()
    }

    /// Anything presented over the app — the navigator's sheets, the launch
    /// notices, the system's — as UIKit sees it, which is the one place all
    /// of them show up.
    private static var sheetIsUp: Bool {
        #if canImport(UIKit)
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            return windows.contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
        #else
            return !AppNavigator.shared.sheetStack.isEmpty
        #endif
    }

    /// The idle round, stepped to `date`, as a frame to draw: nil while a
    /// round is in play, before the window is measured, or off the arcade skin.
    /// Stepping it twice for one date is a no-op, so two backdrops on screen
    /// at once do not play it at double speed.
    func idleScene(at date: Double) -> ArcadeScene? {
        guard !isPlaying, windowSize.width > 0,
              case let .arcade(arcade)? = SkinStore.shared.current.decorations?.scene
        else { return nil }
        if idle?.size != windowSize {
            idle = ArcadeGame(size: windowSize, arcade: arcade, time: date, idle: true)
        }
        guard let idle else { return nil }
        _ = idle.advance(to: date)
        return idle.scene
    }

    func end() {
        if let game, game.score > best {
            best = game.score
            defaults.set(best, forKey: Self.bestKey)
        }
        game = nil
        isPlaying = false
    }
}

extension View {
    /// The arcade cabinet over the whole app. Attached once at the root, after
    /// ``tapTrail()``, which reports the touches that start a round.
    func arcadeCabinet() -> some View {
        modifier(ArcadeCabinetLayer())
    }
}

private struct ArcadeCabinetLayer: ViewModifier {
    @State private var cabinet = ArcadeCabinet.shared

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .ignoresSafeArea()
                    // A proxy's size leaves out the safe area even here; the
                    // backdrops it must match do not.
                    .onGeometryChange(for: CGSize.self) { proxy in
                        let inset = proxy.safeAreaInsets
                        return CGSize(width: proxy.size.width + inset.leading + inset.trailing, height: proxy.size.height + inset.top + inset.bottom)
                    } action: { cabinet.windowSize = $0 }
            }
            .overlay {
                if cabinet.isPlaying, let game = cabinet.game {
                    ArcadePlayView(game: game, best: cabinet.best) { cabinet.end() }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: cabinet.isPlaying)
    }
}

// MARK: - Play view

private struct ArcadePlayView: View {
    let game: ArcadeGame
    let best: Int
    let leave: () -> Void

    @State private var skins = SkinStore.shared
    /// Where the finger went down and where the ship was aiming then: the ship
    /// moves by the finger's travel, so it never hides under the finger.
    @State private var grab: (touch: CGPoint, target: CGPoint)?
    @State private var lastDown = 0.0
    /// Resolved once: the face lookup goes through UIKit and the HUD is
    /// rebuilt every frame.
    @State private var hudFont = ArcadePlayView.makeHUDFont()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 60 Hz is the arcade's own rate; ProMotion's 120 doubles the work
        // and the round looks no different.
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let clock = game.advance(to: timeline.date.timeIntervalSinceReferenceDate)
            let scene = game.scene
            let dark = colorScheme == .dark
            ZStack {
                skins.current.background.opacity(0.82)
                    .ignoresSafeArea()
                // The frame goes in as a value: a canvas that captured only the
                // round, one reference that never changes, would look unchanged
                // to SwiftUI and keep its last frame.
                Canvas { context, _ in scene.draw(in: &context, dark: dark) }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(steering)
                    .accessibilityHidden(true)
                hud(clock: clock)
                if game.finished {
                    Color.clear.task { leave() }
                }
            }
        }
    }

    private var steering: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if grab == nil {
                    let now = Date.now.timeIntervalSinceReferenceDate
                    if now - lastDown < 0.3 { game.roll() }
                    lastDown = now
                    grab = (value.startLocation, game.target)
                }
                if let grab {
                    game.target = CGPoint(x: grab.target.x + value.translation.width * 1.2, y: grab.target.y + value.translation.height * 1.2)
                }
            }
            .onEnded { _ in grab = nil }
    }

    private func hud(clock: Double) -> some View {
        let arcade = game.arcade
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Button(action: leave) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(arcade.star)
                        .frame(width: 36, height: 36)
                        .background(arcade.star.opacity(0.12), in: Circle())
                }
                .accessibilityLabel(Text("Leave the game"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Score").textCase(.uppercase).foregroundStyle(arcade.border)
                    Text(verbatim: String(format: "%06d", game.score)).foregroundStyle(arcade.star)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best").textCase(.uppercase).foregroundStyle(arcade.border)
                    Text(verbatim: String(format: "%06d", max(best, game.score))).foregroundStyle(arcade.star)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: String(repeating: "▲", count: max(0, game.lives))).foregroundStyle(arcade.star)
                    Text(verbatim: String(repeating: "◎", count: game.loops)).foregroundStyle(arcade.pow)
                }
                .accessibilityHidden(true)
            }
            .font(hudFont)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            Spacer()
            // A pickup's word: pops in large, settles, fades.
            if let callout = game.callout, clock - callout.at < 1.3, !game.isOver {
                let u = (clock - callout.at) / 1.3
                Text(callout.text)
                    .textCase(.uppercase)
                    .font(hudFont)
                    .foregroundStyle(arcade.pow)
                    .scaleEffect(1.9 - 0.5 * min(1, u * 4))
                    .opacity(u < 0.75 ? 1 : (1 - u) * 4)
                    .accessibilityHidden(true)
                Spacer()
            }
            if game.isOver {
                Text("Game over")
                    .textCase(.uppercase)
                    .font(hudFont)
                    .foregroundStyle(arcade.raider)
                    .scaleEffect(1.8)
                Spacer()
            } else if clock - game.startedAt < 3.5 {
                let since = clock - game.startedAt
                Text("Drag to fly, double-tap to roll")
                    .font(hudFont)
                    .foregroundStyle(arcade.star.opacity(since < 2.5 ? 0.9 : (3.5 - since) * 0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    private static func makeHUDFont() -> Font {
        #if canImport(UIKit)
            SkinFace.label(weight: .regular, size: 10, relativeTo: .caption) ?? .system(size: 11, weight: .bold, design: .monospaced)
        #else
            .system(size: 11, weight: .bold, design: .monospaced)
        #endif
    }
}
