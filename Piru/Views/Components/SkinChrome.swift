import SwiftUI

// The form layer of the skin system: how buttons and chips are drawn under
// each `SkinSurface`. Color comes from `Theme` / `Skin`; this file
// only decides shape, stroke and shadow. Graphs never come through here.

/// Prominence of a standalone action.
enum SkinButtonProminence {
    /// The accent-tinted primary (the system "Allow" pill).
    case prominent
    /// The plain counterpart for skip / not-now escape hatches.
    case neutral
}

extension View {
    /// The skin's button treatment. A glass skin keeps the system Liquid Glass
    /// styles; an edged skin draws a solid sticker with a stroke and a hard
    /// shadow the press sinks onto. Replaces `.buttonStyle(.glassProminent)` /
    /// `.buttonStyle(.glass)` at every standalone action.
    @ViewBuilder
    func skinButtonStyle(_ prominence: SkinButtonProminence) -> some View {
        let skin = SkinStore.shared.current
        if let gilding = skin.gilding {
            buttonStyle(GildedButtonStyle(prominence: prominence, gilding: gilding))
        } else {
            surfaceButtonStyle(prominence, surface: skin.surface)
        }
    }

    @ViewBuilder
    private func surfaceButtonStyle(_ prominence: SkinButtonProminence, surface: SkinSurface) -> some View {
        switch surface {
        case .glass:
            switch prominence {
            case .prominent: buttonStyle(.glassProminent)
            case .neutral: buttonStyle(.glass)
            }
        case let .edged(stroke, strokeWidth, shadow, shadowOffset):
            buttonStyle(EdgedButtonStyle(
                prominence: prominence,
                stroke: stroke,
                strokeWidth: strokeWidth,
                shadow: shadow,
                shadowOffset: shadowOffset,
            ))
        case let .soft(stroke, glow, glowRadius):
            buttonStyle(SoftButtonStyle(prominence: prominence, stroke: stroke, glow: glow, glowRadius: glowRadius))
        case let .frosted(stroke, highlight):
            buttonStyle(SoftButtonStyle(prominence: prominence, stroke: stroke, glow: highlight, glowRadius: 10))
        case let .paper(stroke, _):
            buttonStyle(PaperButtonStyle(prominence: prominence, stroke: stroke))
        case let .neon(stroke, glow):
            buttonStyle(NeonButtonStyle(prominence: prominence, stroke: stroke, glow: glow))
        }
    }
}

/// A gilded button: a ``GildedPlate`` under the ink, or, for the neutral
/// twin, a dark plate inside the same gold rim. Pressing takes the light off
/// the metal.
struct GildedButtonStyle: ButtonStyle {
    let prominence: SkinButtonProminence
    let gilding: SkinGilding

    func makeBody(configuration: Configuration) -> some View {
        let skin = SkinStore.shared.current
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(prominence == .prominent ? gilding.ink : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                switch prominence {
                case .prominent:
                    GildedPlate(gilding: gilding, shape: shape, pressed: pressed)
                case .neutral:
                    shape.fill(skin.cardBackground.opacity(0.85))
                    shape.strokeBorder(gilding.rim, lineWidth: 1.25)
                }
            }
            .brightness(pressed ? -0.07 : 0)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

/// Gold leaf in any shape: the foil ramp bright along the top as if lit from
/// above, a diagonal sheen across the face, a bright bevel inside the top
/// edge, the skin's pinstripe along the foot, and a rim that darkens toward it.
struct GildedPlate<S: Shape>: View {
    let gilding: SkinGilding
    let shape: S
    var pressed = false

    var body: some View {
        ZStack {
            shape.fill(foil)
                .shadow(color: gilding.deep.opacity(pressed ? 0.2 : 0.45), radius: pressed ? 3 : 8, y: pressed ? 1 : 4)
            shape.fill(sheen)
            if !gilding.stripe.isEmpty {
                pinstripe.clipShape(shape)
            }
            shape.stroke(gilding.shine.opacity(0.7), lineWidth: 0.75)
                .padding(1.5)
                .mask { LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center) }
            shape.stroke(gilding.rim, lineWidth: 1)
        }
    }

    private var foil: LinearGradient {
        LinearGradient(stops: [
            .init(color: gilding.mid, location: 0),
            .init(color: gilding.bright, location: 0.2),
            .init(color: gilding.shine, location: 0.32),
            .init(color: gilding.mid, location: 0.55),
            .init(color: gilding.deep, location: 0.85),
            .init(color: gilding.mid, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var sheen: LinearGradient {
        LinearGradient(stops: [
            .init(color: gilding.shine.opacity(0), location: 0.3),
            .init(color: gilding.shine.opacity(0.5), location: 0.46),
            .init(color: gilding.shine.opacity(0), location: 0.6),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The stripe's bands side by side along the foot.
    private var pinstripe: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(gilding.stripe.indices, id: \.self) { i in
                    Rectangle().fill(gilding.stripe[i])
                }
            }
            .frame(height: 3)
        }
    }
}

extension SkinGilding {
    /// Bright at the top edge, dark at the foot.
    var rim: LinearGradient {
        LinearGradient(colors: [shine, mid, deep], startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// The fill and label color of a hand-built call to action — one that
    /// lays its own label out and so cannot take ``skinButtonStyle(_:)``.
    /// Gold leaf with its ink under a gilded skin, the accent with the
    /// skin's `onAccent` everywhere else.
    @ViewBuilder
    func skinProminentFill(in shape: some Shape) -> some View {
        let skin = SkinStore.shared.current
        if let gilding = skin.gilding {
            foregroundStyle(gilding.ink)
                .background { GildedPlate(gilding: gilding, shape: shape) }
        } else {
            foregroundStyle(skin.onAccent)
                .background(skin.accent, in: shape)
        }
    }
}

/// A paper button: the ink stroke, a flat fill, and a press that darkens the
/// fill the way pressed paper does. No shadow anywhere on paper.
struct PaperButtonStyle: ButtonStyle {
    let prominence: SkinButtonProminence
    let stroke: Color

    func makeBody(configuration: Configuration) -> some View {
        let skin = SkinStore.shared.current
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(prominence == .prominent ? skin.onAccent : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                shape.fill(prominence == .prominent ? skin.accent : skin.cardBackground)
                    .brightness(pressed ? -0.08 : 0)
                shape.stroke(stroke.opacity(prominence == .prominent ? 0.5 : 0.35), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

/// A neon button: a phosphor stroke with its glow, text in the accent, and a
/// press that fills the tube.
struct NeonButtonStyle: ButtonStyle {
    let prominence: SkinButtonProminence
    let stroke: Color
    let glow: Color

    func makeBody(configuration: Configuration) -> some View {
        let skin = SkinStore.shared.current
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let pressed = configuration.isPressed
        let filled = prominence == .prominent || pressed
        configuration.label
            .foregroundStyle(filled ? skin.onAccent : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                shape.fill(filled ? skin.accent : skin.cardBackground.opacity(0.85))
                    .shadow(color: glow.opacity(pressed ? 0.9 : 0.55), radius: pressed ? 12 : 8)
                shape.stroke(stroke, lineWidth: 1.5)
            }
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

/// A glowing button: solid fill, hairline, a colored bloom beneath that
/// brightens on press — the way Tsuki signals selection.
struct SoftButtonStyle: ButtonStyle {
    let prominence: SkinButtonProminence
    let stroke: Color
    let glow: Color
    let glowRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let skin = SkinStore.shared.current
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(prominence == .prominent ? skin.onAccent : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                shape.fill(prominence == .prominent ? skin.accent : skin.cardBackground)
                    .shadow(color: glow.opacity(pressed ? 0.7 : 0.4), radius: pressed ? glowRadius * 0.6 : glowRadius, y: 3)
                shape.stroke(stroke.opacity(prominence == .prominent ? 0.0 : 0.4), lineWidth: 1)
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// A sticker button: solid fill, stroke, hard offset shadow. Pressing moves the
/// face onto its shadow instead of dimming it — the site's buttons do the same.
struct EdgedButtonStyle: ButtonStyle {
    let prominence: SkinButtonProminence
    let stroke: Color
    let strokeWidth: CGFloat
    let shadow: Color
    let shadowOffset: CGSize

    func makeBody(configuration: Configuration) -> some View {
        let skin = SkinStore.shared.current
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let pressed = configuration.isPressed
        // Fill is the text-safe accent, not the vivid mark: `onAccent` is gated
        // against it (6.4:1 night, 4.8:1 pink), and a label is small copy.
        configuration.label
            .foregroundStyle(prominence == .prominent ? skin.onAccent : skin.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                shape.fill(shadow).offset(pressed ? .zero : shadowOffset)
                shape.fill(prominence == .prominent ? skin.accent : skin.cardBackground)
                shape.stroke(stroke, lineWidth: strokeWidth)
            }
            .offset(pressed ? shadowOffset : .zero)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension Text {
    /// The skin's chip: the badge grammar every categorical label shares
    /// (route, strength, severity, tags). `text` is the gated label color,
    /// `fill` the mark color. A glass skin tints a capsule from `fill` at
    /// 0.10 — never higher, a color on a tint of itself asymptotes around
    /// 4.5:1 in dark mode. An edged skin draws the site's blinky: a square
    /// chip with a stroke in the mark color on the input surface.
    @ViewBuilder
    func skinChip(text: Color, fill: Color, style: Font.TextStyle, weight: Font.Weight, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let base = self.font(.piruLabel(style, weight: weight))
            .lineLimit(1)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
        switch SkinStore.shared.current.surface {
        case .glass, .soft, .frosted:
            base
                .background(fill.opacity(Theme.Opacity.tint), in: Capsule())
                .foregroundStyle(text)
        case .paper:
            let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
            base
                .background(fill.opacity(Theme.Opacity.tint), in: shape)
                .overlay(shape.strokeBorder(text.opacity(0.35), lineWidth: 1))
                .foregroundStyle(text)
        case .neon:
            let shape = RoundedRectangle(cornerRadius: 1, style: .continuous)
            base
                .textCase(.uppercase)
                .background(Theme.inputBackground, in: shape)
                .overlay(shape.strokeBorder(fill, lineWidth: 1))
                .shadow(color: fill.opacity(0.45), radius: 4)
                .foregroundStyle(text)
        case .edged:
            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
            base
                .background(Theme.inputBackground, in: shape)
                .overlay(shape.strokeBorder(fill, lineWidth: 1.5))
                .foregroundStyle(text)
        }
    }

    /// The outline grammar — an **unfilled** chip whose stroke may carry an
    /// identity color (a per-substance color is a non-text mark at the 3:1
    /// floor, never the label). Capsule under glass, square under an edge.
    @ViewBuilder
    func skinOutlineChip(stroke: Color, style: Font.TextStyle, weight: Font.Weight, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let base = self.font(.piruLabel(style, weight: weight))
            .lineLimit(1)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .foregroundStyle(Theme.secondaryLabel)
        switch SkinStore.shared.current.surface {
        case .glass, .soft, .frosted:
            base.overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        case .paper:
            base.overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(stroke, lineWidth: 1))
        case .neon:
            base.overlay(RoundedRectangle(cornerRadius: 1, style: .continuous).strokeBorder(stroke, lineWidth: 1))
        case .edged:
            base.overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(stroke, lineWidth: 1.5))
        }
    }
}

/// The shape of a small filled chip drawn outside the chip primitives — the
/// white-on-gradient chips on the Library cards. A capsule, or the skin's
/// squared chip corner.
func skinChipShape() -> AnyShape {
    if let radius = SkinStore.shared.current.chipCornerRadius {
        AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    } else {
        AnyShape(Capsule())
    }
}
