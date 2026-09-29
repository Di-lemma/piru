// Swift Charts for Android: the marks, axes and chart modifiers the shared code uses, drawn
// through the Canvas stand-in. Marks record their plotted values and style; `Chart` fits
// them to a plot area with light gridlines and leading/bottom labels. Axis customization
// (AxisMarks contents, value formats) is accepted and drawn in the default style, and chart
// selection is not interactive.
//
// Inside a `Chart { }` body, stage.py renames `ForEach` to `ChartForEach`: SwiftUI's ForEach
// builds chart content there, and SkipFuseUI's builds only views.

import SwiftUI

// MARK: - Values

protocol Plottable {
    var androidPlotted: PlottedValue { get }
}

enum PlottedValue: Hashable {
    case number(Double)
    case date(Date)
    case category(String)
}

extension Double: Plottable { var androidPlotted: PlottedValue { .number(self) } }
extension Float: Plottable { var androidPlotted: PlottedValue { .number(Double(self)) } }
extension Int: Plottable { var androidPlotted: PlottedValue { .number(Double(self)) } }
extension Date: Plottable { var androidPlotted: PlottedValue { .date(self) } }
extension String: Plottable { var androidPlotted: PlottedValue { .category(self) } }

struct PlottableValue<Value: Plottable> {
    let label: String
    let value: Value

    static func value(_ label: LocalizedStringKey, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: "", value: value)
    }

    static func value<S: StringProtocol>(_ label: S, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: String(label), value: value)
    }

    static func value(_ label: Text, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: "", value: value)
    }
}

extension PlottableValue where Value == Date {
    /// A date binned to `unit`: plotted at the unit's start, as Swift Charts groups it.
    static func value<S: StringProtocol>(_ label: S, _ value: Date, unit: Calendar.Component, calendar: Calendar = .current) -> PlottableValue<Date> {
        PlottableValue(label: String(label), value: calendar.dateInterval(of: unit, for: value)?.start ?? value)
    }

    static func value(_ label: LocalizedStringKey, _ value: Date, unit: Calendar.Component, calendar: Calendar = .current) -> PlottableValue<Date> {
        PlottableValue(label: "", value: calendar.dateInterval(of: unit, for: value)?.start ?? value)
    }
}

enum InterpolationMethod {
    case linear, monotone, catmullRom, cardinal, stepStart, stepCenter, stepEnd
}

enum MarkStackingMethod {
    case standard, normalized, center, unstacked
}

// MARK: - Marks

struct ChartMark {
    enum Kind { case line, area, rule, point, bar, rectangle }

    var kind: Kind
    var x: PlottedValue?
    var y: PlottedValue?
    var xStart: PlottedValue?
    var xEnd: PlottedValue?
    var yStart: PlottedValue?
    var yEnd: PlottedValue?
    var series: String?
    var color: Color?
    var strokeStyle = StrokeStyle(lineWidth: 2)
    var interpolation = InterpolationMethod.linear
    var symbolSize: CGFloat = 30
    var opacity: Double = 1
}

protocol ChartContent {
    var androidMarks: [ChartMark] { get }
}

extension Array: ChartContent where Element == ChartMark {
    var androidMarks: [ChartMark] { self }
}

/// The modifiers every mark takes, each returning the mark so chains keep their type.
protocol AndroidMark: ChartContent {
    var mark: ChartMark { get set }
}

extension AndroidMark {
    var androidMarks: [ChartMark] { [mark] }

    private func with(_ change: (inout ChartMark) -> Void) -> Self {
        var copy = self
        change(&copy.mark)
        return copy
    }

    func foregroundStyle<S: ShapeStyle>(_ style: S) -> Self {
        with { if let color = style as? Color { $0.color = color } }
    }

    func foregroundStyle<V: Plottable>(by value: PlottableValue<V>) -> Self {
        with { $0.series = value.value.androidPlotted.seriesName }
    }

    func lineStyle(_ style: StrokeStyle) -> Self { with { $0.strokeStyle = style } }
    func interpolationMethod(_ method: InterpolationMethod) -> Self { with { $0.interpolation = method } }
    func symbolSize(_ size: CGFloat) -> Self { with { $0.symbolSize = size } }
    func symbolSize(_ size: CGSize) -> Self { with { $0.symbolSize = size.width * size.height } }
    func symbol<S>(_ symbol: S) -> Self { self }
    func symbol<V: Plottable>(by value: PlottableValue<V>) -> Self { self }
    func opacity(_ value: Double) -> Self { with { $0.opacity = value } }
    func cornerRadius(_ radius: CGFloat, style: RoundedCornerStyle = .continuous) -> Self { self }
    func position<V: Plottable>(by value: PlottableValue<V>, axis: Axis? = nil) -> Self {
        with { $0.series = value.value.androidPlotted.seriesName }
    }
    func offset(x: CGFloat = 0, y: CGFloat = 0) -> Self { self }
    func zIndex(_ value: Double) -> Self { self }
    func alignsMarkStylesWithPlotArea(_ aligns: Bool = true) -> Self { self }
    func accessibilityLabel(_ label: Text) -> Self { self }
    func accessibilityLabel(_ label: String) -> Self { self }
    func accessibilityValue(_ value: Text) -> Self { self }
    func accessibilityValue(_ value: String) -> Self { self }
    func accessibilityHidden(_ hidden: Bool) -> Self { self }
    func clipShape(_ shape: some Shape) -> Self { self }
    func mask<M>(_ mask: () -> M) -> Self { self }
    func annotation<C: View>(
        position: AnnotationPosition = .automatic, alignment: Alignment = .center, spacing: CGFloat? = nil,
        overflowResolution: AnnotationOverflowResolution = .automatic,
        @ViewBuilder content: () -> C
    ) -> Self { self }
}

enum AnnotationPosition { case automatic, top, bottom, leading, trailing, overlay, topLeading, topTrailing, bottomLeading, bottomTrailing }

struct AnnotationOverflowResolution {
    static let automatic = AnnotationOverflowResolution()
    init() {}
    init(x: AnnotationOverflowStrategy = .automatic, y: AnnotationOverflowStrategy = .automatic) {}
}

struct AnnotationOverflowStrategy {
    static let automatic = AnnotationOverflowStrategy()
    static let fit = AnnotationOverflowStrategy()
    static let disabled = AnnotationOverflowStrategy()
    static func fit(to: AnnotationBoundary) -> AnnotationOverflowStrategy { AnnotationOverflowStrategy() }
}

enum AnnotationBoundary { case automatic, chart, plot }

private extension PlottedValue {
    var seriesName: String {
        switch self {
        case let .category(name): name
        case let .number(value): String(value)
        case let .date(date): String(date.timeIntervalSince1970)
        }
    }
}

struct LineMark: AndroidMark {
    var mark: ChartMark

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
        mark = ChartMark(kind: .line, x: x.value.androidPlotted, y: y.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable, S: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, series: PlottableValue<S>) {
        mark = ChartMark(kind: .line, x: x.value.androidPlotted, y: y.value.androidPlotted, series: series.value.androidPlotted.seriesName)
    }
}

struct AreaMark: AndroidMark {
    var mark: ChartMark

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, stacking: MarkStackingMethod = .standard) {
        mark = ChartMark(kind: .area, x: x.value.androidPlotted, y: y.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(kind: .area, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable, S: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, series: PlottableValue<S>, stacking: MarkStackingMethod = .standard) {
        mark = ChartMark(kind: .area, x: x.value.androidPlotted, y: y.value.androidPlotted, series: series.value.androidPlotted.seriesName)
    }
}

struct RuleMark: AndroidMark {
    var mark: ChartMark

    init<X: Plottable>(x: PlottableValue<X>) {
        mark = ChartMark(kind: .rule, x: x.value.androidPlotted)
    }

    init<Y: Plottable>(y: PlottableValue<Y>) {
        mark = ChartMark(kind: .rule, y: y.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<Y>) {
        mark = ChartMark(kind: .rule, y: y.value.androidPlotted, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(kind: .rule, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }
}

struct PointMark: AndroidMark {
    var mark: ChartMark

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
        mark = ChartMark(kind: .point, x: x.value.androidPlotted, y: y.value.androidPlotted)
    }
}

struct BarMark: AndroidMark {
    var mark: ChartMark

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, width: MarkDimension = .automatic, stacking: MarkStackingMethod = .standard) {
        mark = ChartMark(kind: .bar, x: x.value.androidPlotted, y: y.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>, width: MarkDimension = .automatic) {
        mark = ChartMark(kind: .bar, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<Y>, height: MarkDimension = .automatic) {
        mark = ChartMark(kind: .bar, y: y.value.androidPlotted, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }
}

struct RectangleMark: AndroidMark {
    var mark: ChartMark

    init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(
            kind: .rectangle,
            xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted,
            yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted
        )
    }

    init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>, width: MarkDimension = .automatic) {
        mark = ChartMark(kind: .rectangle, x: x.value.androidPlotted, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<Y>, height: MarkDimension = .automatic) {
        mark = ChartMark(kind: .rectangle, y: y.value.androidPlotted, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }

    /// A band across the whole plot width.
    init<Y: Plottable>(yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        mark = ChartMark(kind: .rectangle, yStart: yStart.value.androidPlotted, yEnd: yEnd.value.androidPlotted)
    }

    /// A band across the whole plot height.
    init<X: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>) {
        mark = ChartMark(kind: .rectangle, xStart: xStart.value.androidPlotted, xEnd: xEnd.value.androidPlotted)
    }
}

struct MarkDimension: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    static let automatic = MarkDimension()
    static func fixed(_ value: CGFloat) -> MarkDimension { MarkDimension() }
    static func ratio(_ value: CGFloat) -> MarkDimension { MarkDimension() }
    init() {}
    init(floatLiteral value: Double) {}
    init(integerLiteral value: Int) {}
}

@resultBuilder
enum ChartContentBuilder {
    static func buildExpression(_ content: some ChartContent) -> [ChartMark] { content.androidMarks }
    static func buildBlock(_ parts: [ChartMark]...) -> [ChartMark] { parts.flatMap { $0 } }
    static func buildOptional(_ part: [ChartMark]?) -> [ChartMark] { part ?? [] }
    static func buildEither(first: [ChartMark]) -> [ChartMark] { first }
    static func buildEither(second: [ChartMark]) -> [ChartMark] { second }
    static func buildArray(_ parts: [[ChartMark]]) -> [ChartMark] { parts.flatMap { $0 } }
    static func buildLimitedAvailability(_ part: [ChartMark]) -> [ChartMark] { part }
}

/// `ForEach` inside a chart body (stage.py renames it there).
struct ChartForEach: ChartContent {
    let androidMarks: [ChartMark]

    init<Data: RandomAccessCollection>(_ data: Data, @ChartContentBuilder content: (Data.Element) -> [ChartMark]) {
        androidMarks = data.flatMap(content)
    }

    init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data, id: KeyPath<Data.Element, ID>, @ChartContentBuilder content: (Data.Element) -> [ChartMark]
    ) {
        androidMarks = data.flatMap(content)
    }
}

protocol ChartSymbolShape: Shape {}

/// The built-in point symbols; drawn as circles, the one symbol the renderer draws.
struct BasicChartSymbolShape: ChartSymbolShape {
    static let circle = BasicChartSymbolShape()
    static let square = BasicChartSymbolShape()
    static let triangle = BasicChartSymbolShape()
    static let diamond = BasicChartSymbolShape()
    static let pentagon = BasicChartSymbolShape()
    static let plus = BasicChartSymbolShape()
    static let cross = BasicChartSymbolShape()
    static let asterisk = BasicChartSymbolShape()

    nonisolated func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }

    func strokeBorder(lineWidth: CGFloat = 1) -> BasicChartSymbolShape { self }
}

// MARK: - Axes

protocol AxisContent {}

@resultBuilder
enum AxisContentBuilder {
    static func buildExpression(_ content: some AxisContent) -> AxisGroup { AxisGroup() }
    static func buildBlock(_ parts: AxisGroup...) -> AxisGroup { AxisGroup() }
    static func buildOptional(_ part: AxisGroup?) -> AxisGroup { AxisGroup() }
    static func buildEither(first: AxisGroup) -> AxisGroup { first }
    static func buildEither(second: AxisGroup) -> AxisGroup { second }
    static func buildArray(_ parts: [AxisGroup]) -> AxisGroup { AxisGroup() }
}

struct AxisGroup: AxisContent {}

struct AxisValue {
    let index: Int
    let count: Int
    private let plotted: PlottedValue

    init(index: Int = 0, count: Int = 0, plotted: PlottedValue = .number(0)) {
        self.index = index
        self.count = count
        self.plotted = plotted
    }

    func `as`<V>(_ type: V.Type) -> V? {
        switch plotted {
        case let .number(value): (value as? V) ?? (Int(value) as? V)
        case let .date(date): date as? V
        case let .category(name): name as? V
        }
    }
}

struct AxisMarkValues: ExpressibleByArrayLiteral {
    static let automatic = AxisMarkValues()
    static func automatic(desiredCount: Int? = nil, roundLowerBound: Bool? = nil, roundUpperBound: Bool? = nil) -> AxisMarkValues { AxisMarkValues() }
    static func stride(by component: Calendar.Component, count: Int = 1) -> AxisMarkValues { AxisMarkValues() }
    static func stride(by step: Double) -> AxisMarkValues { AxisMarkValues() }
    init() {}
    init(arrayLiteral elements: Double...) {}
    init(_ values: [some Plottable]) {}
}

enum AxisMarkPosition { case automatic, leading, trailing, top, bottom }
enum AxisMarkPreset { case automatic, extended, aligned, inset }

struct AxisMarks: AxisContent {
    init(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: AxisMarkValues = .automatic) {}

    init(
        preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: AxisMarkValues = .automatic,
        @AxisContentBuilder content: @escaping (AxisValue) -> AxisGroup
    ) {}

    init(
        preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: [some Plottable],
        @AxisContentBuilder content: @escaping (AxisValue) -> AxisGroup
    ) {}

    init(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: [some Plottable]) {}
}

struct AxisGridLine: AxisContent {
    init(centered: Bool? = nil, stroke: StrokeStyle? = nil) {}
    func foregroundStyle(_ style: some ShapeStyle) -> AxisGridLine { self }
}

struct AxisTick: AxisContent {
    init(centered: Bool? = nil, length: CGFloat? = nil, stroke: StrokeStyle? = nil) {}
    func foregroundStyle(_ style: some ShapeStyle) -> AxisTick { self }
}

struct AxisValueLabel: AxisContent {
    init() {}
    init(centered: Bool? = nil, anchor: UnitPoint? = nil, multiLabelAlignment: Alignment? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic, offsetsMarks: Bool? = nil, orientation: AxisValueLabelOrientation = .automatic, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil) {}
    init(format: Date.FormatStyle, centered: Bool? = nil, anchor: UnitPoint? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic) {}
    init(format: FloatingPointFormatStyle<Double>, centered: Bool? = nil, anchor: UnitPoint? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic) {}
    init(format: FloatingPointFormatStyle<Double>.Percent, centered: Bool? = nil, anchor: UnitPoint? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic) {}
    init(format: IntegerFormatStyle<Int>, centered: Bool? = nil, anchor: UnitPoint? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic) {}
    init<C: View>(@ViewBuilder content: () -> C) {}
    init<C: View>(centered: Bool?, anchor: UnitPoint? = nil, @ViewBuilder content: () -> C) {}
    func font(_ font: Font?) -> AxisValueLabel { self }
    func foregroundStyle(_ style: some ShapeStyle) -> AxisValueLabel { self }
}

struct AxisValueLabelCollisionResolution {
    static let automatic = AxisValueLabelCollisionResolution()
    static let greedy = AxisValueLabelCollisionResolution()
    static let disabled = AxisValueLabelCollisionResolution()
    static func greedy(priority: Double = 0, minimumSpacing: CGFloat = 0) -> AxisValueLabelCollisionResolution { .greedy }
}

enum AxisValueLabelOrientation { case automatic, horizontal, vertical, verticalReversed }

// MARK: - Chart modifiers

struct ChartAxisConfiguration: Equatable {
    var xHidden = false
    var yHidden = false
    var xDomain: ClosedRange<Double>?
    var yDomain: ClosedRange<Double>?
    var seriesColors: [String: Color] = [:]
}

private struct ChartAxisConfigurationKey: EnvironmentKey {
    static let defaultValue = ChartAxisConfiguration()
}

extension EnvironmentValues {
    var androidChartConfiguration: ChartAxisConfiguration {
        get { self[ChartAxisConfigurationKey.self] }
        set { self[ChartAxisConfigurationKey.self] = newValue }
    }
}

private extension ClosedRange where Bound: Plottable {
    var androidDomain: ClosedRange<Double>? {
        guard case let .number(low) = lowerBound.androidPlotted.normalized,
              case let .number(high) = upperBound.androidPlotted.normalized, low <= high else { return nil }
        return low ... high
    }
}

private extension PlottedValue {
    var normalized: PlottedValue {
        if case let .date(date) = self { return .number(date.timeIntervalSinceReferenceDate) }
        return self
    }
}

/// Applies one chart modifier to the configuration the enclosing ones already set.
struct ChartConfigured<Content: View>: View {
    let content: Content
    let change: (inout ChartAxisConfiguration) -> Void
    @Environment(\.androidChartConfiguration) var configuration

    var body: some View {
        var changed = configuration
        change(&changed)
        return content.environment(\.androidChartConfiguration, changed)
    }
}

extension View {
    fileprivate func configureChart(_ change: @escaping (inout ChartAxisConfiguration) -> Void) -> some View {
        ChartConfigured(content: self, change: change)
    }

    func chartXAxis(_ visibility: Visibility) -> some View {
        configureChart { $0.xHidden = visibility == .hidden }
    }

    func chartYAxis(_ visibility: Visibility) -> some View {
        configureChart { $0.yHidden = visibility == .hidden }
    }

    func chartXAxis(@AxisContentBuilder content: () -> AxisGroup) -> some View { self }
    func chartYAxis(@AxisContentBuilder content: () -> AxisGroup) -> some View { self }

    func chartYScale<B: Plottable>(domain: ClosedRange<B>, type: ScaleType? = nil) -> some View {
        let domain = domain.androidDomain
        return configureChart { $0.yDomain = domain }
    }

    func chartXScale<B: Plottable>(domain: ClosedRange<B>, type: ScaleType? = nil) -> some View {
        let domain = domain.androidDomain
        return configureChart { $0.xDomain = domain }
    }

    func chartYScale(range: ClosedRange<CGFloat>) -> some View { self }
    /// A categorical domain: the renderer orders categories as the data first lists them.
    func chartXScale(domain: [String]) -> some View { self }
    func chartYScale(domain: [String]) -> some View { self }
    func chartXScale(range: ClosedRange<CGFloat>) -> some View { self }

    func chartForegroundStyleScale(_ mapping: KeyValuePairs<String, Color>) -> some View {
        let colors = Dictionary(mapping.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        return configureChart { $0.seriesColors = colors }
    }

    /// A style range the renderer can use only where its entries are plain colors.
    func chartForegroundStyleScale<D: Plottable, S: ShapeStyle>(domain: [D], range: [S]) -> some View {
        let names = domain.map { value -> String in
            if case let .category(name) = value.androidPlotted { return name }
            return String(describing: value)
        }
        let colors = Dictionary(zip(names, range).compactMap { name, style in (style as? Color).map { (name, $0) } }, uniquingKeysWith: { first, _ in first })
        return configureChart { $0.seriesColors = colors }
    }

    func chartForegroundStyleScale(domain: [String], range: [Color]) -> some View {
        let colors = Dictionary(zip(domain, range).map { ($0, $1) }, uniquingKeysWith: { first, _ in first })
        return configureChart { $0.seriesColors = colors }
    }

    func chartForegroundStyleScale<V>(_ mapping: @escaping (V) -> Color) -> some View { self }

    func chartLegend(_ visibility: Visibility) -> some View { self }
    func chartLegend(position: AnnotationPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View { self }
    func chartYAxisLabel(_ label: String, position: AnnotationPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View { self }
    func chartYAxisLabel(_ label: Text, position: AnnotationPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View { self }
    func chartXAxisLabel(_ label: String, position: AnnotationPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View { self }
    func chartXSelection<V>(value: Binding<V?>) -> some View { self }
    func chartXSelection<V>(range: Binding<ClosedRange<V>?>) -> some View { self }
    func chartOverlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: @escaping (ChartProxy) -> V) -> some View { self }
    func chartBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: @escaping (ChartProxy) -> V) -> some View { self }
    func chartPlotStyle<V: View>(@ViewBuilder content: @escaping (ChartPlotContent) -> V) -> some View { self }
    func chartScrollableAxes(_ axes: Axis.Set) -> some View { self }
    func chartXVisibleDomain(length: some Numeric) -> some View { self }
    func chartScrollPosition<V>(x: Binding<V>) -> some View { self }
    func chartScrollPosition<V>(initialX: V) -> some View { self }
    func chartXScrollWindow<L, W, I>(fullLength: L, window: W, initialX: I) -> some View { self }
    func chartGesture(_ gesture: @escaping (ChartProxy) -> Void) -> some View { self }
}

enum ScaleType { case linear, log, squareRoot, date, category, symmetricLog }

/// Where the plot sits inside the chart's geometry; the stand-in renderer does not report it.
struct ChartPlotAnchor {}

extension GeometryProxy {
    subscript(_ anchor: ChartPlotAnchor) -> CGRect { .zero }
}

struct ChartProxy {
    var plotSize: CGSize { .zero }
    var plotFrame: ChartPlotAnchor? { nil }
    func value<V>(atX x: CGFloat, as type: V.Type) -> V? { nil }
    func position<V>(forX value: V) -> CGFloat? { nil }
    func position<V>(forY value: V) -> CGFloat? { nil }
}

struct ChartPlotContent: View {
    var body: some View { EmptyView() }
}

// MARK: - Chart

struct Chart: View {
    private let marks: [ChartMark]
    @Environment(\.androidChartConfiguration) var configuration

    init(@ChartContentBuilder content: () -> [ChartMark]) {
        marks = content()
    }

    init<Data: RandomAccessCollection>(_ data: Data, @ChartContentBuilder content: (Data.Element) -> [ChartMark]) {
        marks = data.flatMap(content)
    }

    var body: some View {
        let marks = marks
        let configuration = configuration
        Canvas { context, size in
            ChartRenderer(marks: marks, configuration: configuration, size: size).draw(in: &context)
        }
    }
}

private struct ChartRenderer {
    let marks: [ChartMark]
    let configuration: ChartAxisConfiguration
    let size: CGSize

    private static let palette: [Color] = [.accentColor, .blue, .orange, .green, .purple, .pink, .teal, .red]

    private var categories: [String] {
        var seen: [String] = []
        for mark in marks {
            for value in [mark.x, mark.xStart, mark.xEnd] {
                if case let .category(name)? = value, !seen.contains(name) { seen.append(name) }
            }
        }
        return seen
    }

    private func number(_ value: PlottedValue?, categories: [String]) -> Double? {
        switch value {
        case let .number(n)?: n
        case let .date(d)?: d.timeIntervalSinceReferenceDate
        case let .category(c)?: categories.firstIndex(of: c).map { Double($0) + 0.5 }
        case nil: nil
        }
    }

    func draw(in context: inout GraphicsContext) {
        let categories = categories
        let xs = marks.flatMap { [$0.x, $0.xStart, $0.xEnd] }.compactMap { number($0, categories: categories) }
        let ys = marks.flatMap { [$0.y, $0.yStart, $0.yEnd] }.compactMap { number($0, categories: []) }
        guard !xs.isEmpty || !ys.isEmpty else { return }

        var xDomain = configuration.xDomain ?? ((xs.min() ?? 0) ... (xs.max() ?? 1))
        if !categories.isEmpty, configuration.xDomain == nil { xDomain = 0 ... Double(categories.count) }
        let hasBars = marks.contains { $0.kind == .bar }
        var yDomain = configuration.yDomain ?? (min(hasBars ? 0 : (ys.min() ?? 0), ys.min() ?? 0) ... (ys.max() ?? 1))
        if xDomain.lowerBound == xDomain.upperBound { xDomain = (xDomain.lowerBound - 1) ... (xDomain.upperBound + 1) }
        if yDomain.lowerBound == yDomain.upperBound { yDomain = (yDomain.lowerBound - 1) ... (yDomain.upperBound + 1) }

        let leading: CGFloat = configuration.yHidden ? 0 : 34
        let bottom: CGFloat = configuration.xHidden ? 0 : 18
        let plot = CGRect(x: leading, y: 4, width: max(1, size.width - leading - 4), height: max(1, size.height - bottom - 8))

        func px(_ value: Double) -> CGFloat {
            plot.minX + CGFloat((value - xDomain.lowerBound) / (xDomain.upperBound - xDomain.lowerBound)) * plot.width
        }
        func py(_ value: Double) -> CGFloat {
            plot.maxY - CGFloat((value - yDomain.lowerBound) / (yDomain.upperBound - yDomain.lowerBound)) * plot.height
        }

        drawGrid(&context, plot: plot, yDomain: yDomain, xDomain: xDomain, categories: categories, py: py, px: px)

        let grouped = Dictionary(grouping: marks.enumerated(), by: { "\($0.element.kind)|\($0.element.series ?? "")" })
        for (_, group) in grouped.sorted(by: { $0.value.first!.offset < $1.value.first!.offset }) {
            let series = group.map(\.element)
            guard let first = series.first else { continue }
            let color = first.color ?? first.series.flatMap { configuration.seriesColors[$0] } ?? seriesColor(first.series)
            context.opacity = first.opacity
            switch first.kind {
            case .line:
                let points = series.compactMap { mark -> CGPoint? in
                    guard let x = number(mark.x, categories: categories), let y = number(mark.y, categories: []) else { return nil }
                    return CGPoint(x: px(x), y: py(y))
                }.sorted { $0.x < $1.x }
                context.stroke(Self.path(through: points, smooth: first.interpolation != .linear), with: .color(color), style: first.strokeStyle)
            case .area:
                let points = series.compactMap { mark -> (CGPoint, CGFloat)? in
                    guard let x = number(mark.x, categories: categories) else { return nil }
                    let top = number(mark.yEnd ?? mark.y, categories: []) ?? 0
                    let base = number(mark.yStart, categories: []) ?? max(yDomain.lowerBound, 0)
                    return (CGPoint(x: px(x), y: py(top)), py(base))
                }.sorted { $0.0.x < $1.0.x }
                guard let firstPoint = points.first, let lastPoint = points.last else { continue }
                var path = Self.path(through: points.map(\.0), smooth: first.interpolation != .linear)
                path.addLine(to: CGPoint(x: lastPoint.0.x, y: lastPoint.1))
                for point in points.reversed() { path.addLine(to: CGPoint(x: point.0.x, y: point.1)) }
                path.addLine(to: firstPoint.0)
                path.closeSubpath()
                context.opacity = first.opacity * (first.color == nil ? 0.3 : 1)
                context.fill(path, with: .color(color))
            case .point:
                for mark in series {
                    guard let x = number(mark.x, categories: categories), let y = number(mark.y, categories: []) else { continue }
                    let radius = max(2, sqrt(mark.symbolSize) / 2)
                    context.fill(Path(ellipseIn: CGRect(x: px(x) - radius, y: py(y) - radius, width: radius * 2, height: radius * 2)), with: .color(mark.color ?? color))
                }
            case .rule:
                for mark in series {
                    var path = Path()
                    if let x = number(mark.x, categories: categories) {
                        let top = number(mark.yEnd, categories: []).map(py) ?? plot.minY
                        let base = number(mark.yStart, categories: []).map(py) ?? plot.maxY
                        path.move(to: CGPoint(x: px(x), y: base))
                        path.addLine(to: CGPoint(x: px(x), y: top))
                    } else if let y = number(mark.y, categories: []) {
                        let start = number(mark.xStart, categories: categories).map(px) ?? plot.minX
                        let end = number(mark.xEnd, categories: categories).map(px) ?? plot.maxX
                        path.move(to: CGPoint(x: start, y: py(y)))
                        path.addLine(to: CGPoint(x: end, y: py(y)))
                    }
                    context.stroke(path, with: .color(mark.color ?? color), style: mark.strokeStyle.lineWidth == 2 ? StrokeStyle(lineWidth: 1) : mark.strokeStyle)
                }
            case .bar, .rectangle:
                let slot = categories.isEmpty ? max(2, plot.width / CGFloat(max(series.count, 1)) * 0.7) : plot.width / CGFloat(categories.count) * 0.7
                for mark in series {
                    let rect: CGRect
                    if let xStart = number(mark.xStart, categories: categories), let xEnd = number(mark.xEnd, categories: categories) {
                        let y = number(mark.y, categories: []) ?? 0
                        let height: CGFloat = mark.kind == .bar ? 10 : plot.height / 8
                        let top = number(mark.yEnd, categories: []).map(py)
                        let base = number(mark.yStart, categories: []).map(py)
                        if let top, let base {
                            rect = CGRect(x: px(xStart), y: top, width: px(xEnd) - px(xStart), height: base - top)
                        } else {
                            rect = CGRect(x: px(xStart), y: py(y) - height / 2, width: px(xEnd) - px(xStart), height: height)
                        }
                    } else if mark.kind == .rectangle, mark.x == nil, mark.y == nil,
                              let yStart = number(mark.yStart, categories: []), let yEnd = number(mark.yEnd, categories: []) {
                        rect = CGRect(x: plot.minX, y: py(yEnd), width: plot.width, height: py(yStart) - py(yEnd))
                    } else if let x = number(mark.x, categories: categories) {
                        let top = py(number(mark.yEnd ?? mark.y, categories: []) ?? 0)
                        let base = py(number(mark.yStart, categories: []) ?? max(yDomain.lowerBound, 0))
                        rect = CGRect(x: px(x) - slot / 2, y: min(top, base), width: slot, height: abs(base - top))
                    } else {
                        continue
                    }
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(mark.color ?? color))
                }
            }
        }
        context.opacity = 1
    }

    private func seriesColor(_ series: String?) -> Color {
        guard let series else { return Self.palette[0] }
        let names = Array(Set(marks.compactMap(\.series))).sorted()
        return Self.palette[(names.firstIndex(of: series) ?? 0) % Self.palette.count]
    }

    private func drawGrid(
        _ context: inout GraphicsContext, plot: CGRect, yDomain: ClosedRange<Double>, xDomain: ClosedRange<Double>,
        categories: [String], py: (Double) -> CGFloat, px: (Double) -> CGFloat
    ) {
        let grid = Color.secondary.opacity(0.25)
        if !configuration.yHidden {
            for value in Self.ticks(yDomain, count: 4) {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: py(value)))
                line.addLine(to: CGPoint(x: plot.maxX, y: py(value)))
                context.stroke(line, with: .color(grid), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                context.draw(
                    Text(Self.format(value, span: yDomain.upperBound - yDomain.lowerBound)).font(.caption2).foregroundStyle(Color.secondary),
                    at: CGPoint(x: plot.minX - 4, y: py(value)), anchor: .trailing
                )
            }
        }
        guard !configuration.xHidden else { return }
        if !categories.isEmpty {
            for (index, name) in categories.enumerated() where categories.count <= 12 {
                context.draw(Text(name).font(.caption2).foregroundStyle(Color.secondary), at: CGPoint(x: px(Double(index) + 0.5), y: plot.maxY + 9))
            }
        } else if marks.contains(where: { if case .date = $0.x { true } else { false } }) {
            let span = xDomain.upperBound - xDomain.lowerBound
            for value in Self.ticks(xDomain, count: 4) {
                let date = Date(timeIntervalSinceReferenceDate: value)
                let label = span > 3 * 86400 ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.hour())
                context.draw(Text(label).font(.caption2).foregroundStyle(Color.secondary), at: CGPoint(x: px(value), y: plot.maxY + 9))
            }
        } else {
            for value in Self.ticks(xDomain, count: 4) {
                context.draw(
                    Text(Self.format(value, span: xDomain.upperBound - xDomain.lowerBound)).font(.caption2).foregroundStyle(Color.secondary),
                    at: CGPoint(x: px(value), y: plot.maxY + 9)
                )
            }
        }
    }

    private static func ticks(_ domain: ClosedRange<Double>, count: Int) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [domain.lowerBound] }
        let rough = span / Double(count)
        let magnitude = pow(10, floor(log10(rough)))
        let step = [1, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= rough } ?? rough
        var value = ceil(domain.lowerBound / step) * step
        var out: [Double] = []
        while value <= domain.upperBound + step * 1e-9, out.count < 12 {
            out.append(value)
            value += step
        }
        return out
    }

    private static func format(_ value: Double, span: Double) -> String {
        span < 10 ? value.formatted(.number.precision(.fractionLength(0 ... 1))) : value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func path(through points: [CGPoint], smooth: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard smooth, points.count > 2 else {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        for index in 1 ..< points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = (current.x - previous.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x + mid, y: previous.y),
                control2: CGPoint(x: current.x - mid, y: current.y)
            )
        }
        return path
    }
}
