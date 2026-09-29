// SwiftUI API that SkipFuseUI does not provide, each with its nearest Compose behavior.
// Modifiers that only tune an Apple-specific affordance (hit shapes, border shapes, scroll
// edge effects, layout priority) apply nothing: Compose lays the view out the same way
// without them. Views are rebuilt from the primitives Skip does bridge.

import SwiftUI

// MARK: - Modifiers with no Compose counterpart

struct ContentShapeKinds: OptionSet {
    let rawValue: Int
    static let interaction = ContentShapeKinds(rawValue: 1)
    static let dragPreview = ContentShapeKinds(rawValue: 2)
    static let contextMenuPreview = ContentShapeKinds(rawValue: 4)
    static let hoverEffect = ContentShapeKinds(rawValue: 8)
    static let focusEffect = ContentShapeKinds(rawValue: 16)
    static let accessibility = ContentShapeKinds(rawValue: 32)
}

struct ButtonBorderShape {
    static let automatic = ButtonBorderShape()
    static let capsule = ButtonBorderShape()
    static let circle = ButtonBorderShape()
    static let roundedRectangle = ButtonBorderShape()
    static func roundedRectangle(radius: CGFloat) -> ButtonBorderShape { ButtonBorderShape() }
}

extension View {
    /// Compose hit-tests a view by its bounds, which is what most of these shapes describe.
    func contentShape(_ shape: some Shape, eoFill: Bool = false) -> some View { self }
    func contentShape(_ kind: ContentShapeKinds, _ shape: some Shape, eoFill: Bool = false) -> some View { self }

    func buttonBorderShape(_ shape: ButtonBorderShape) -> some View { self }
    func layoutPriority(_ value: Double) -> some View { self }
    func alignmentGuide(_ guide: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View { self }
    func alignmentGuide(_ guide: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View { self }
    func gridColumnAlignment(_ alignment: HorizontalAlignment) -> some View { self }
    func gridCellColumns(_ count: Int) -> some View { self }
    func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View { self }
    func gridCellAnchor(_ anchor: UnitPoint) -> some View { self }
    func accessibilitySortPriority(_ priority: Double) -> some View { self }
    func persistentSystemOverlays(_ visibility: Visibility) -> some View { self }
    func matchedGeometryEffect<ID: Hashable>(
        id: ID, in namespace: AndroidNamespaceID, properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center, isSource: Bool = true
    ) -> some View { self }

    func onScrollPhaseChange(_ action: @escaping (ScrollPhase, ScrollPhase) -> Void) -> some View { self }

    /// The bar stacked at the edge it names. SkipFuseUI has no safe-area inset, so the bar takes
    /// its own space instead of floating over the content's edge.
    func safeAreaBar<V: View>(
        edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
        @ViewBuilder content: () -> V
    ) -> some View {
        let bar = content()
        return VStack(alignment: alignment, spacing: spacing ?? 0) {
            if edge == .top { bar }
            self
            if edge == .bottom { bar }
        }
    }

    /// Shows the first phase: the cycle is an iOS flourish, and the resting frame reads the same.
    func phaseAnimator<Phase: Equatable, V: View>(
        _ phases: some Sequence<Phase>, trigger: some Equatable = 0,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> V,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        Group {
            if let first = Array(phases).first {
                content(PlaceholderContentView(content: self), first)
            } else {
                self
            }
        }
    }
}

struct AndroidNamespaceID: Hashable, Sendable {}

struct MatchedGeometryProperties: OptionSet {
    let rawValue: Int
    static let position = MatchedGeometryProperties(rawValue: 1)
    static let size = MatchedGeometryProperties(rawValue: 2)
    static let frame: MatchedGeometryProperties = [.position, .size]
}

struct PlaceholderContentView<Content: View>: View {
    let content: Content
    var body: some View { content }
}

struct ViewDimensions {
    let width: CGFloat
    let height: CGFloat

    subscript(guide: HorizontalAlignment) -> CGFloat { 0 }
    subscript(guide: VerticalAlignment) -> CGFloat { 0 }
}

// MARK: - Modifiers SkipFuseUI declares unavailable

// substitutions.txt renames each call to its `android` twin here: redeclaring the unavailable
// signature would be ambiguous with SkipFuseUI's.

enum AndroidAccessibilityChildBehavior {
    case ignore, combine, contain
}

enum AndroidImageScale {
    case small, medium, large
}

extension View {
    /// TalkBack groups by Compose semantics; there is no per-view grouping to request.
    func androidAccessibilityElement(children: AndroidAccessibilityChildBehavior = .ignore) -> some View { self }
    func androidAccessibilityHint(_ hint: Text, isEnabled: Bool = true) -> some View { self }
    func androidAccessibilityHint(_ hint: LocalizedStringKey, isEnabled: Bool = true) -> some View { self }
    func androidAccessibilityHint(_ hint: String, isEnabled: Bool = true) -> some View { self }
    func androidAccessibilityInputLabels(_ labels: [Text], isEnabled: Bool = true) -> some View { self }
    func androidAccessibilityInputLabels(_ labels: [LocalizedStringKey], isEnabled: Bool = true) -> some View { self }
    func androidAccessibilityInputLabels(_ labels: [String], isEnabled: Bool = true) -> some View { self }
    func androidMonospacedDigit() -> some View { self }
    func androidKerning(_ kerning: CGFloat) -> some View { self }
    func androidListRowInsets(_ insets: EdgeInsets?) -> some View { self }
    func androidImageScale(_ scale: AndroidImageScale) -> some View { self }
    func androidScrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View { self }
}

enum AndroidControlSize {
    case mini, small, regular, large, extraLarge
}

extension View {
    func androidControlSize(_ size: AndroidControlSize) -> some View { self }
    func androidTruncationMode(_ mode: Text.TruncationMode) -> some View { self }

    /// Liquid Glass is Apple's; on Android the same surface is a quiet translucent fill.
    func androidGlassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S, isEnabled: Bool = true) -> some View {
        background(shape.fill(Color.platformSecondarySystemBackground))
    }

    func androidGlassEffect(_ glass: Glass = .regular, isEnabled: Bool = true) -> some View {
        background(Capsule().fill(Color.platformSecondarySystemBackground))
    }
}

/// Groups glass shapes on iOS so they blend; with no glass to blend, it only holds them.
struct AndroidGlassEffectContainer<Content: View>: View {
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View { content }
}

extension ShapeStyle where Self == Color {
    /// The hierarchical levels SkipFuseUI marks unavailable, as the system draws them.
    static var androidTertiary: Color { Color.secondary.opacity(0.6) }
    static var androidQuaternary: Color { Color.secondary.opacity(0.35) }
    static var androidFillTertiary: Color { Color.platformTertiarySystemFill }
    static var androidFillSecondary: Color { Color.platformSecondarySystemFill }
    static var androidFillPrimary: Color { Color.platformSecondarySystemFill.opacity(1.3) }
    static var androidFillQuaternary: Color { Color.platformTertiarySystemFill.opacity(0.7) }
    static var separator: Color { Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.29) }
}

extension Text {
    func androidMonospacedDigit() -> Text { self }
    func androidKerning(_ kerning: CGFloat) -> Text { self }
}

extension Font {
    func androidMonospacedDigit() -> Font { self }
}

extension Image {
    func androidImageScale(_ scale: AndroidImageScale) -> some View { self }
}

// MARK: - Popover

extension View {
    /// A popover is a sheet on a phone-sized screen, which is what iOS shows there too.
    func popover<Content: View>(
        isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, content: content)
    }
}

enum AndroidPresentationAdaptation {
    case automatic, none, popover, sheet, fullScreenCover
}

extension View {
    /// Presentations already adapt to the one size class a phone has.
    func androidPresentationCompactAdaptation(_ adaptation: AndroidPresentationAdaptation) -> some View { self }
    func androidPresentationBackground<S: ShapeStyle>(_ style: S) -> some View { self }
    func androidPresentationBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }
    func androidListSectionSpacing(_ spacing: CGFloat) -> some View { self }
    func androidListSectionSpacing(_ spacing: AndroidListSectionSpacing) -> some View { self }
    func androidScrollBounceBehavior(_ behavior: AndroidScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View { self }
    func androidContentTransition(_ transition: AndroidContentTransition) -> some View { self }
    func androidTextSelection(_ selectability: AndroidTextSelectability) -> some View { self }
    func androidAccessibilityAction(named name: Text, _ handler: @escaping () -> Void) -> some View { self }
    func androidAccessibilityAction(named name: LocalizedStringKey, _ handler: @escaping () -> Void) -> some View { self }
    func androidAccessibilityAction(_ kind: AndroidAccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> some View { self }
    func androidScrollClipDisabled(_ disabled: Bool = true) -> some View { self }
    func androidSymbolEffect(_ effect: AndroidSymbolEffect, options: Any? = nil, value: some Equatable) -> some View { self }
    func androidSymbolEffect(_ effect: AndroidSymbolEffect, options: Any? = nil, isActive: Bool = true) -> some View { self }
    func androidTransaction<V: Equatable>(value: V, _ transform: @escaping (inout Transaction) -> Void) -> some View { self }

    /// The sheet's detents without a selection binding, which SkipFuseUI's sheet does not take.
    func androidPresentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View {
        presentationDetents(detents)
    }

    func androidPresentationBackgroundInteraction(_ interaction: AndroidPresentationBackgroundInteraction) -> some View { self }
    func androidPresentationContentInteraction(_ interaction: AndroidPresentationContentInteraction) -> some View { self }
    func androidTransaction(_ transform: @escaping (inout Transaction) -> Void) -> some View { self }
    func androidDynamicTypeSize<R>(_ range: R) -> some View { self }
    func androidAccessibilityRepresentation<V: View>(@ViewBuilder representation: () -> V) -> some View { self }
    /// Gesture locations are already in the view's own space on Compose.
    func androidCoordinateSpace(_ name: NamedCoordinateSpace) -> some View { self }
    func androidScrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> some View { self }

    func onScrollGeometryChange<T: Equatable>(
        for type: T.Type, of transform: @escaping (ScrollGeometry) -> T, action: @escaping (T, T) -> Void
    ) -> some View { self }

    func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View {
        accessibilityLabel(Text(String(label)))
    }

    func accessibilityValue<S: StringProtocol>(_ value: S) -> some View {
        accessibilityValue(Text(String(value)))
    }

    func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        lineLimit(limit.upperBound)
    }

    func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        lineLimit(nil)
    }
}

enum AndroidSymbolEffect {
    case replace, bounce, pulse, variableColor, scale, appear, disappear, wiggle, rotate, breathe
}

struct AndroidPresentationBackgroundInteraction {
    static let automatic = AndroidPresentationBackgroundInteraction()
    static let disabled = AndroidPresentationBackgroundInteraction()
    static let enabled = AndroidPresentationBackgroundInteraction()
    static func enabled(upThrough detent: PresentationDetent) -> AndroidPresentationBackgroundInteraction { .enabled }
}

enum AndroidPresentationContentInteraction { case automatic, resizes, scrolls }

enum AndroidListSectionSpacing { case `default`, compact, custom(CGFloat) }
enum AndroidScrollBounceBehavior { case automatic, always, basedOnSize }
enum AndroidTextSelectability { case enabled, disabled }
enum AndroidAccessibilityActionKind { case `default`, escape, magicTap, delete, showMenu }

/// Content transitions are an iOS animation between two renders; Compose recomposes directly.
struct AndroidContentTransition {
    static let identity = AndroidContentTransition()
    static let opacity = AndroidContentTransition()
    static let interpolate = AndroidContentTransition()
    static func numericText(countsDown: Bool = false) -> AndroidContentTransition { AndroidContentTransition() }
    static func numericText(value: Double) -> AndroidContentTransition { AndroidContentTransition() }
    static func androidSymbolEffect(_ effect: AndroidSymbolEffect, options: Any? = nil) -> AndroidContentTransition { AndroidContentTransition() }
    static var androidSymbolEffect: AndroidContentTransition { AndroidContentTransition() }
}

enum PopoverAttachmentAnchor {
    case rect(Anchor)
    case point(UnitPoint)

    enum Anchor { case bounds }
}

// MARK: - Formatters

/// Foundation's ListFormatter, for the English-shaped lists the app joins: "a, b and c".
enum ListFormatter {
    static func localizedString(byJoining strings: [String]) -> String {
        guard strings.count > 1, let last = strings.last else { return strings.first ?? "" }
        return strings.dropLast().joined(separator: ", ") + " " + String(localized: "and") + " " + last
    }
}

extension Shape {
    /// A concrete-Color overload, so `strokeBorder(color.opacity(x))` has one reading.
    func strokeBorder(_ color: Color, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        stroke(color, lineWidth: lineWidth)
    }
}

extension Text {
    /// `Text(date, style: .relative)`, which Compose text cannot keep updating: the offset at render.
    init(androidRelative date: Date) {
        let seconds = Int(Date().timeIntervalSince(date))
        let magnitude = abs(seconds)
        let amount: String
        switch magnitude {
        case ..<60: amount = String(localized: "\(magnitude) sec")
        case ..<3600: amount = String(localized: "\(magnitude / 60) min")
        case ..<86400: amount = String(localized: "\(magnitude / 3600) hr")
        default: amount = String(localized: "\(magnitude / 86400) days")
        }
        self.init(verbatim: amount)
    }
}

// MARK: - ContentUnavailableView

struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    private let label: Label
    private let description: Description
    private let actions: Actions

    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() }, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            description
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description })
    }

    init<S: StringProtocol>(_ title: S, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(String(title), systemImage: name) }, description: { description })
    }

    static var search: ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass")
    }

    static func search(text: String) -> ContentUnavailableView {
        ContentUnavailableView(
            "No Results", systemImage: "magnifyingglass",
            description: Text("Check the spelling or try a new search.")
        )
    }
}

// MARK: - Grid

/// Rows of cells: columns align as far as each row's cells share widths, which holds for the
/// app's label-value grids.
struct Grid<Content: View>: View {
    private let alignment: Alignment
    private let verticalSpacing: CGFloat?
    private let content: Content

    init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment.horizontal, spacing: verticalSpacing) { content }
    }
}

struct GridRow<Content: View>: View {
    private let alignment: VerticalAlignment
    private let content: Content

    init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment ?? .center
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment) { content }
    }
}

// MARK: - AnyLayout

protocol AndroidStackLayout {
    var anyLayout: AnyLayout { get }
}

struct HStackLayout: AndroidStackLayout {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat?
    var anyLayout: AnyLayout { AnyLayout(axis: .horizontal, horizontal: .center, vertical: alignment, spacing: spacing) }
}

struct VStackLayout: AndroidStackLayout {
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat?
    var anyLayout: AnyLayout { AnyLayout(axis: .vertical, horizontal: alignment, vertical: .center, spacing: spacing) }
}

struct ZStackLayout: AndroidStackLayout {
    var alignment: Alignment = .center
    var anyLayout: AnyLayout { AnyLayout(axis: nil, horizontal: alignment.horizontal, vertical: alignment.vertical, spacing: nil) }
}

/// A stack whose axis is a value, which is all the app switches between.
struct AnyLayout {
    fileprivate let axis: Axis?
    fileprivate let horizontal: HorizontalAlignment
    fileprivate let vertical: VerticalAlignment
    fileprivate let spacing: CGFloat?

    fileprivate init(axis: Axis?, horizontal: HorizontalAlignment, vertical: VerticalAlignment, spacing: CGFloat?) {
        self.axis = axis
        self.horizontal = horizontal
        self.vertical = vertical
        self.spacing = spacing
    }

    init(_ layout: some AndroidStackLayout) {
        self = layout.anyLayout
    }

    @ViewBuilder
    func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        switch axis {
        case .horizontal: HStack(alignment: vertical, spacing: spacing) { content() }
        case .vertical: VStack(alignment: horizontal, spacing: spacing) { content() }
        case nil: ZStack { content() }
        }
    }
}

// MARK: - TimelineView

protocol TimelineSchedule {
    /// Seconds between redraws.
    var androidInterval: TimeInterval { get }
}

struct PeriodicTimelineSchedule: TimelineSchedule {
    let androidInterval: TimeInterval
}

struct EveryMinuteTimelineSchedule: TimelineSchedule {
    var androidInterval: TimeInterval { 60 }
}

struct AnimationTimelineSchedule: TimelineSchedule {
    let androidInterval: TimeInterval
    let paused: Bool
}

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(androidInterval: max(interval, 1.0 / 30))
    }
}

extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule(androidInterval: 1.0 / 30, paused: false) }

    static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule {
        AnimationTimelineSchedule(androidInterval: minimumInterval ?? 1.0 / 30, paused: paused)
    }
}

struct TimelineViewDefaultContext {
    let date: Date
    let cadence: Cadence = .live

    enum Cadence: Comparable { case live, seconds, minutes }
}

/// Redraws its content on the schedule's interval from a task, which is what the schedule
/// asks of SwiftUI.
struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    private let schedule: Schedule
    private let content: (TimelineViewDefaultContext) -> Content
    @State private var date = Date()

    init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    var body: some View {
        content(TimelineViewDefaultContext(date: date))
            .task {
                if let animation = schedule as? AnimationTimelineSchedule, animation.paused { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(schedule.androidInterval))
                    date = Date()
                }
            }
    }
}

// MARK: - Shapes

/// A rounded rectangle; Android has no display corners to be concentric with, so the
/// minimum radius the shape asks for is its radius.
nonisolated struct ConcentricRectangle: Shape {
    var cornerRadius: CGFloat = 20

    init() {}

    init(corners: ConcentricCorners, isUniform: Bool = false) {
        cornerRadius = corners.radius
    }

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius)
    }
}

struct ConcentricCorners {
    let radius: CGFloat

    static func concentric(minimum: ConcentricMinimum = .fixed(20)) -> ConcentricCorners {
        ConcentricCorners(radius: minimum.radius)
    }

    static func fixed(_ radius: CGFloat) -> ConcentricCorners {
        ConcentricCorners(radius: radius)
    }
}

struct ConcentricMinimum: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    let radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
    }

    init(integerLiteral value: Int) {
        radius = CGFloat(value)
    }

    init(floatLiteral value: Double) {
        radius = CGFloat(value)
    }

    static func fixed(_ radius: CGFloat) -> ConcentricMinimum {
        ConcentricMinimum(radius: radius)
    }
}

/// An image tiled as a fill. SkipFuseUI bridges only its own shape styles, so the texture is
/// dropped and the fill is clear, leaving the surface's own color.
typealias ImagePaint = Color

extension Color {
    init(image: Image, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) {
        self = .clear
    }
}

// MARK: - ImageRenderer

/// Android has no offscreen SwiftUI rendering here, so an image is never produced and the
/// share paths that need one fall back to sharing text.
@Observable
final class ImageRenderer<Content: View> {
    var content: Content
    var scale: CGFloat = 1
    var proposedSize: ProposedViewSize = .unspecified
    var isOpaque = false

    init(content: Content) {
        self.content = content
    }
}

struct ProposedViewSize {
    var width: CGFloat?
    var height: CGFloat?

    static let unspecified = ProposedViewSize(width: nil, height: nil)
    static let zero = ProposedViewSize(width: 0, height: 0)
    static let infinity = ProposedViewSize(width: .infinity, height: .infinity)

    init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}

enum SearchScopeActivation {
    case automatic, onTextEntry, onSearchPresentation
}

extension View {
    /// Compose's search bar has no scope row; the Search tab's scope stays where it was seeded.
    func searchScopes<V: Hashable, S: View>(
        _ scope: Binding<V>, activation: SearchScopeActivation = .automatic, @ViewBuilder scopes: () -> S
    ) -> some View { self }
}

extension View {
    /// SkipFuseUI has no safeAreaInset: the inset content is stacked against the view's edge,
    /// which shrinks the view by the content's height as the inset would. The flexible frame
    /// becomes a Compose weight, so a view that fills (a NavigationStack) leaves the inset room.
    func androidSafeAreaInset<V: View>(
        edge: VerticalEdge, spacing: CGFloat? = nil, @ViewBuilder content: () -> V
    ) -> some View {
        VStack(spacing: spacing ?? 0) {
            if edge == .top {
                content()
                frame(maxHeight: .infinity)
            } else {
                frame(maxHeight: .infinity)
                content()
            }
        }
    }
}
