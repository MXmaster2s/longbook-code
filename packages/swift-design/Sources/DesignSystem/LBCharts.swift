import SwiftUI

/// One bar in the month chart: a calendar day, with the words it answers to. The title
/// names the day ("14 Sep"), the detail what it held ("₹4,200 · 2 charges"); the axis
/// label is the month's name where one starts, nil elsewhere.
public struct LBDayBarValue: Equatable {
    public let scoped: Double
    public let foreignOnly: Bool
    public let isPast: Bool
    public let title: String
    public let detail: String
    public let axisLabel: String?

    public init(scoped: Double, foreignOnly: Bool, isPast: Bool,
                title: String = "", detail: String = "", axisLabel: String? = nil) {
        self.scoped = scoped
        self.foreignOnly = foreignOnly
        self.isPast = isPast
        self.title = title
        self.detail = detail
        self.axisLabel = axisLabel
    }
}

/// The months, day by day: a bar's height is its day's scoped sum against the busiest day,
/// log scale. A day charged only in another currency gets a marker, never a bar. A pointer
/// or a tap captions a day; with `onOpen`, a click or second tap opens it.
public struct LBDayBars: View {
    private let days: [LBDayBarValue]
    /// The widest a bar may be. Nil shares the width out, as a month of days does; a few
    /// days stay bar-shaped, the first and last at the chart's two edges.
    private let widest: CGFloat?
    /// What a day's bar opens, by index. Nil leaves the chart caption-only.
    private let onOpen: ((Int) -> Void)?
    /// The bar under the pointer, or the last one tapped.
    @State private var picked: Int?
    @State private var captionWidth: CGFloat = 0

    /// Points between shared bars.
    static let sharedGap: CGFloat = 2
    /// The room an axis label needs: a closer one is not drawn, and one this near the
    /// right edge ends at its bar instead of starting there.
    static let axisLabelRoom: CGFloat = 30
    private static let axisHeight: CGFloat = 14

    public init(_ days: [LBDayBarValue], widest: CGFloat? = nil, onOpen: ((Int) -> Void)? = nil) {
        self.days = days
        self.widest = widest
        self.onOpen = onOpen
    }

    /// Whether a bar is a door: something was charged that day, and a caller is listening.
    private func opens(_ i: Int) -> Bool {
        onOpen != nil && (days[i].scoped > 0 || days[i].foreignOnly)
    }

    private func open(_ i: Int?) {
        guard let i, opens(i) else { return }
        onOpen?(i)
    }

    /// Said once per bar that opens: a tooltip on the Mac, a button to VoiceOver. An
    /// assistive activation opens the day in one step; a sighted tap keeps its caption first.
    @ViewBuilder
    private func doorHints<V: View>(_ view: V, at i: Int) -> some View {
        if opens(i) {
            view
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the charges on this day")
                .accessibilityAction { open(i) }
                #if os(macOS)
                .help("Open the charges on this day")
                #endif
        } else {
            view
        }
    }

    public var body: some View {
        let peak = max(days.map(\.scoped).max() ?? 1, 1)
        VStack(spacing: LBSpacing.s1) {
            GeometryReader { geo in
                let layout = Self.layout(width: geo.size.width, count: days.count, widest: widest)
                ZStack(alignment: .topLeading) {
                    if let i = picked, i < days.count {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(LBColor.chrome.color)
                            .frame(width: layout.slot + 2, height: geo.size.height)
                            .offset(x: CGFloat(i) * layout.step - 1)
                    }
                    HStack(alignment: .bottom, spacing: layout.gap) {
                        ForEach(days.indices, id: \.self) { i in
                            doorHints(
                                bar(days[i], peak: peak, height: geo.size.height, lifted: picked == i)
                                    .frame(maxWidth: widest ?? .infinity)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(days[i].title + ", " + days[i].detail)
                                    .accessibilityHidden(days[i].scoped == 0 && !days[i].foreignOnly),
                                at: i
                            )
                        }
                    }
                    .frame(height: geo.size.height, alignment: .bottom)
                    if let i = picked, i < days.count {
                        caption(days[i])
                            .offset(x: captionX(bar: i, layout: layout, width: geo.size.width))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                #if os(macOS)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let hit = Self.index(atX: location.x, width: geo.size.width, count: days.count, widest: widest)
                        if picked != hit { picked = hit }
                    case .ended:
                        picked = nil
                    }
                }
                // The same surface and the same hit test as the hover, so the day the
                // caption names is the day the click opens.
                .onTapGesture { location in
                    open(Self.index(atX: location.x, width: geo.size.width, count: days.count, widest: widest))
                }
                #else
                // The first tap names the day; a second on the same bar opens it. Without a
                // listener the second tap clears the caption, as it always did.
                .onTapGesture { location in
                    let hit = Self.index(atX: location.x, width: geo.size.width, count: days.count, widest: widest)
                    if picked == hit, let hit, opens(hit) {
                        open(hit)
                    } else {
                        picked = picked == hit ? nil : hit
                    }
                }
                #endif
            }
            if days.contains(where: { $0.axisLabel != nil }) {
                axis
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: days) { picked = nil }
    }

    @ViewBuilder
    private func bar(_ day: LBDayBarValue, peak: Double, height: CGFloat, lifted: Bool) -> some View {
        if day.scoped > 0 {
            Capsule(style: .continuous)
                .fill(LBColor.chartBar.color.opacity(day.isPast && !lifted ? 0.45 : 1))
                .frame(height: max(height * Self.share(day.scoped, peak: peak), 4))
        } else if day.foreignOnly {
            Capsule(style: .continuous)
                .fill(LBColor.textTertiary.color)
                .frame(height: 6)
        } else {
            Capsule(style: .continuous)
                .fill(LBColor.textQuaternary.color.opacity(0.35))
                .frame(height: 2)
        }
    }

    /// The picked day's words, on chrome so they read over the bars beneath.
    private func caption(_ day: LBDayBarValue) -> some View {
        HStack(spacing: LBSpacing.s2) {
            Text(day.title)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textPrimary.color)
            Text(day.detail)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, LBSpacing.s2)
        .padding(.vertical, LBSpacing.s1)
        .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
        .background(GeometryReader { g in
            Color.clear.preference(key: CaptionWidthKey.self, value: g.size.width)
        })
        .onPreferenceChange(CaptionWidthKey.self) { captionWidth = $0 }
        .accessibilityHidden(true)
    }

    /// Centred on its bar, held inside the chart at either edge.
    private func captionX(bar: Int, layout: Layout, width: CGFloat) -> CGFloat {
        let centre = CGFloat(bar) * layout.step + layout.slot / 2
        return min(max(centre - captionWidth / 2, 0), max(width - captionWidth, 0))
    }

    /// The month names under the bars that start one, each at its bar's left edge.
    private var axis: some View {
        GeometryReader { geo in
            let layout = Self.layout(width: geo.size.width, count: days.count, widest: widest)
            ZStack(alignment: .topLeading) {
                ForEach(Self.axisMarks(days, layout: layout, width: geo.size.width), id: \.index) { mark in
                    Text(mark.label)
                        .lbText(.tabLabel)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: mark.endsAtBar ? mark.x + layout.slot : geo.size.width,
                               alignment: mark.endsAtBar ? .trailing : .leading)
                        .offset(x: mark.endsAtBar ? 0 : mark.x)
                }
            }
        }
        .frame(height: Self.axisHeight)
        .accessibilityHidden(true)
    }

    struct Layout: Equatable {
        /// A bar's width.
        let slot: CGFloat
        /// The space after it.
        let gap: CGFloat
        var step: CGFloat { slot + gap }
    }

    struct AxisMark: Equatable {
        let index: Int
        let label: String
        let x: CGFloat
        /// True near the right edge, where the label ends at its bar rather than starting there.
        let endsAtBar: Bool
    }

    /// How wide a bar is and how far apart they sit. Shared bars split the width with two
    /// points between them; capped bars take whatever gap sets the first and last at the
    /// edges, never less than two points, and shrink to the shared width when it is smaller.
    static func layout(width: CGFloat, count: Int, widest: CGFloat?) -> Layout {
        guard count > 0 else { return Layout(slot: 0, gap: sharedGap) }
        let n = CGFloat(count)
        let shared = max((width - sharedGap * (n - 1)) / n, 0)
        guard let widest else { return Layout(slot: shared, gap: sharedGap) }
        guard count > 1 else { return Layout(slot: min(widest, max(width, 0)), gap: sharedGap) }
        let slot = min(widest, shared)
        return Layout(slot: slot, gap: max((width - n * slot) / (n - 1), sharedGap))
    }

    /// A bar's share of the height: log1p against the busiest day, so a day a tenth of the
    /// peak draws well above a tenth of the height. Nothing is nothing; the peak is all of it.
    static func share(_ value: Double, peak: Double) -> Double {
        guard value > 0, peak > 0 else { return 0 }
        return min(log1p(value) / log1p(peak), 1)
    }

    /// The bar nearest a point across the chart, so a finger between two thin bars still
    /// lands on one. Nil only when there are no bars.
    static func index(atX x: CGFloat, width: CGFloat, count: Int, widest: CGFloat?) -> Int? {
        guard count > 0 else { return nil }
        let layout = layout(width: width, count: count, widest: widest)
        guard layout.step > 0 else { return 0 }
        let i = Int(((x + layout.gap / 2) / layout.step).rounded(.down))
        return min(max(i, 0), count - 1)
    }

    /// Which labels are drawn and where. A label closer than `axisLabelRoom` to the one
    /// before it is left out rather than drawn over it.
    static func axisMarks(_ days: [LBDayBarValue], layout: Layout, width: CGFloat) -> [AxisMark] {
        var marks: [AxisMark] = []
        var lastX = -CGFloat.infinity
        for (i, day) in days.enumerated() {
            guard let label = day.axisLabel else { continue }
            let x = CGFloat(i) * layout.step
            guard x - lastX >= axisLabelRoom else { continue }
            lastX = x
            marks.append(AxisMark(index: i, label: label, x: x, endsAtBar: x + axisLabelRoom > width))
        }
        return marks
    }
}

private struct CaptionWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The next thirty days as an axis: a dot on every day that owes something, a larger dot
/// where several land together.
public struct LBTimelineStrip: View {
    public struct Dot {
        public let fraction: Double
        public let heavy: Bool

        public init(fraction: Double, heavy: Bool) {
            self.fraction = fraction
            self.heavy = heavy
        }
    }

    private let dots: [Dot]
    private let progress: Double

    /// `progress` is how far along the strip the rail beside it has been carried, 0 to 1.
    public init(_ dots: [Dot], progress: Double = 0) {
        self.dots = dots
        self.progress = progress
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LBColor.chrome.color).frame(height: 2)
                // Where the rail has been carried to, stated as quietly as a border.
                Capsule()
                    .fill(LBColor.brand.color.opacity(0.5))
                    .frame(width: geo.size.width * min(max(progress, 0), 1), height: 2)
                ForEach(dots.indices, id: \.self) { i in
                    let dot = dots[i]
                    // One size for every day. A heavier day says so in ink rather than in
                    // shape — a strip of different-sized circles reads as a mistake.
                    Circle()
                        .fill(LBColor.chartBar.color)
                        .opacity(dot.heavy ? 1 : 0.5)
                        .frame(width: 7, height: 7)
                        .position(
                            x: geo.size.width * dot.fraction,
                            y: geo.size.height / 2
                        )
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// A donut of shares. Values are same-currency by contract — mixing currencies into one
/// ring is the blending this product refuses, so the caller passes one currency's slices.
public struct LBDonut: View {
    public struct Slice {
        public let value: Double
        public let ink: LBColorValue

        public init(value: Double, ink: LBColorValue) {
            self.value = value
            self.ink = ink
        }
    }

    private let slices: [Slice]
    private let centerTitle: String
    private let centerNote: String

    public init(slices: [Slice], centerTitle: String, centerNote: String) {
        self.slices = slices
        self.centerTitle = centerTitle
        self.centerNote = centerNote
    }

    public var body: some View {
        ZStack {
            ring
            VStack(spacing: 2) {
                // A ring's hole is narrower than the ring; a long total must shrink to
                // fit rather than break across lines mid-number.
                Text(centerTitle)
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, LBSpacing.s4)
                Text(centerNote)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(LBSpacing.s8)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(centerTitle + ", " + centerNote)
    }

    private var ring: some View {
        let total = max(slices.map(\.value).reduce(0, +), 0.0001)
        var start = -0.25
        let arcs: [(from: Double, to: Double, ink: LBColorValue)] = slices.map { slice in
            let span = slice.value / total
            defer { start += span }
            return (start, start + span, slice.ink)
        }
        return ZStack {
            ForEach(arcs.indices, id: \.self) { i in
                Circle()
                    .trim(from: 0, to: max(arcs[i].to - arcs[i].from - 0.004, 0))
                    .stroke(arcs[i].ink.color, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                    .rotationEffect(.degrees((arcs[i].from + 0.002) * 360))
            }
        }
        .padding(11)
    }
}
