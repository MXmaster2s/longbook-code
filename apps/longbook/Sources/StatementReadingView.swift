import DesignSystem
import LongbookCore
import SwiftUI

/// The brand button the import's screens share: full width on the phone, and on the Mac
/// either filling a module or sized to its word in a footer.
struct ImportPrimaryButton: View {
    let title: String
    let measure: StaticString
    var fills = true
    let action: () -> Void

    var body: some View {
        Button {
            Measure.used(measure)
            action()
        } label: {
            Text(title)
                #if os(iOS)
                .lbText(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                #else
                .lbText(.label)
                .padding(.horizontal, LBSpacing.s6)
                .frame(maxWidth: fills ? .infinity : nil, minHeight: 32)
                #endif
                .foregroundStyle(LBColor.onBrand.color)
                .background(LBColor.brand.color, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle(.capsule)
    }
}

/// The reading: its title, one bar that keeps rising, one line at a time, and the game in the
/// space below. It names no file and offers no tips.
struct StatementReadingView: View {
    /// The share of answers back, as far as the device can know it.
    let done: Double
    /// The seconds this batch should take.
    let expected: Double
    /// The reading is over and its save landed: only now is the bar full.
    let full: Bool
    /// Full, with a game that was played to come back from.
    let isPrepared: Bool
    /// The save was refused, in words.
    let notSaved: String?
    @Binding var played: Bool
    let onClose: () -> Void
    let onContinue: () -> Void
    let onTryAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The bar's own state, advanced as the timeline draws, so a frame of the bar never
    /// redraws the screen around it.
    @State private var clock = ReadingBarClock()

    private var title: String {
        if notSaved != nil { return "Your longbook is not saved" }
        return isPrepared ? "Your longbook is prepared" : "Preparing your longbook…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            #if os(iOS)
            HStack {
                Spacer()
                closeButton
            }
            titleText
            #else
            HStack(spacing: LBSpacing.s2) {
                titleText
                Spacer()
                closeButton
            }
            #endif
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 30, paused: full)) { context in
                let bar = clock.bar(at: context.date, expected: expected, done: done, full: full)
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    barView(bar.share)
                    statusLine(bar)
                }
            }
            WaitingGame(reading: isPrepared ? .prepared : notSaved.map { .notSaved($0) } ?? .underWay,
                        played: $played, onContinue: onContinue, onTryAgain: onTryAgain)
                .padding(.top, LBSpacing.s2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .padding(LBSpacing.s6)
        #else
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, LBSpacing.s2)
        .padding(.bottom, LBSpacing.s4)
        #endif
    }

    private var titleText: some View {
        Text(title)
            .lbText(.screenTitle)
            .foregroundStyle(LBColor.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
    }

    private var closeButton: some View {
        Button {
            Measure.used("close")
            onClose()
        } label: {
            Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .frame(width: 30, height: 30)
                .background(LBColor.chrome.color, in: Circle())
                .contentShape(Circle())
        }
        .lbButtonStyle(.capsule)
        .help("Close")
    }

    private func barView(_ share: Double) -> some View {
        GeometryReader { space in
            ZStack(alignment: .leading) {
                Capsule().fill(LBColor.chrome.color)
                Capsule().fill(LBColor.brand.color)
                    .frame(width: max(6, space.size.width * share))
            }
        }
        .frame(height: 6)
        .animation(LBMotion.rise(reduceMotion: reduceMotion), value: full)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(share * 100)) percent")
    }

    /// The line the bar has reached, its symbol breathing and its words shimmering. Once
    /// prepared, what became of the game.
    @ViewBuilder
    private func statusLine(_ bar: ReadingBar) -> some View {
        if isPrepared {
            Label {
                Text("Your game is paused")
                    .foregroundStyle(LBColor.textSecondary.color)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(LBColor.brandText.color)
            }
            .labelStyle(.titleAndIcon)
            .lbText(.bodySM)
        } else {
            let line = ReadingBar.lines[bar.line]
            Label {
                LBShimmerText(line.words, style: .bodySM)
            } icon: {
                Image(systemName: line.kind.symbol)
                    .foregroundStyle(LBColor.brandText.color)
                    .lbBreathing(!reduceMotion)
            }
            .labelStyle(.titleAndIcon)
            .lbText(.bodySM)
            .id(bar.line)
            .transition(.opacity)
            .animation(LBMotion.resolve(reduceMotion: reduceMotion), value: bar.line)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The bar as time passes: a plain box, not state a view watches.
@MainActor
final class ReadingBarClock {
    private var bar = ReadingBar()
    private var started: Date?

    func bar(at now: Date, expected: Double, done: Double, full: Bool) -> ReadingBar {
        let start = started ?? now
        started = start
        if full {
            bar.finish()
        } else {
            bar.advance(to: now.timeIntervalSince(start), expected: expected, done: done)
        }
        return bar
    }
}

extension StatementTour.Kind {
    var symbol: String { cardKind.symbol }

    var cardKind: LBCardKind {
        switch self {
        case .charge: .charge
        case .people: .people
        case .account: .account
        case .commitment: .commitment
        case .transfer: .transfer
        case .earning: .earning
        }
    }
}

private extension View {
    /// A symbol breathing while work is under way: the system's breathe where it exists, its
    /// pulse before that.
    @ViewBuilder
    func lbBreathing(_ active: Bool) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            symbolEffect(.breathe, isActive: active)
        } else {
            symbolEffect(.pulse, isActive: active)
        }
    }
}
