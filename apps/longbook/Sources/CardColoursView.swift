import DesignSystem
import SwiftUI

/// One row per kind of card, each with the colour it wears, and the way back to the defaults.
/// A kind's colour comes from a grid of twenty; one colour belongs to one kind.
struct CardColoursList: View {
    private let colours = LBCardColours.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CardColourKinds.all, id: \.kind) { row in
                CardColourRow(kind: row.kind, title: row.title)
                Rectangle()
                    .fill(LBColor.hairline.color)
                    .frame(height: 1)
                    .padding(.leading, LBSpacing.s3)
                    .accessibilityHidden(true)
            }
            Button {
                Measure.used("reset_card_colours")
                colours.reset()
            } label: {
                Text("Reset to Defaults")
                    .lbText(.body)
                    .foregroundStyle((colours.isDefault ? LBColor.textTertiary : LBColor.brandText).color)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .disabled(colours.isDefault)
        }
    }
}

/// The kinds a person can colour, in the order the app lists them.
enum CardColourKinds {
    static let all: [(kind: LBCardKind, title: String)] = [
        (.commitment, "Commitment"), (.charge, "Charge"), (.earning, "Earning"), (.transfer, "Transfer"),
        (.account, "Account"), (.people, "Person"), (.report, "Report"),
    ]

    static func title(_ kind: LBCardKind) -> String {
        all.first { $0.kind == kind }?.title ?? ""
    }
}

private struct CardColourRow: View {
    let kind: LBCardKind
    let title: String
    @State private var picking = false
    private let colours = LBCardColours.shared

    var body: some View {
        Button {
            Measure.used("card_colour_row")
            picking = true
        } label: {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer(minLength: LBSpacing.s2)
                Text(colours.swatch(for: kind).name)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textSecondary.color)
                Circle()
                    .fill(kind.ink.color)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LBSpacing.s3)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .help("Choose the \(title.lowercased()) colour")
        .accessibilityLabel("\(title), \(colours.swatch(for: kind).name)")
        #if os(macOS)
        .measured("card_colour_picking", .popover, when: picking)
        .popover(isPresented: $picking, arrowEdge: .trailing) {
            CardColourGrid(kind: kind) { picking = false }
                .padding(LBSpacing.s4)
                .frame(width: 340)
                .lbKeyboardFocusEffects()
        }
        #else
        .measured("card_colour_picking", .sheet, when: picking)
        .sheet(isPresented: $picking) {
            CardColourGrid(kind: kind) { picking = false }
                .padding(LBSpacing.s4)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(LBColor.canvas.color)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .lbKeyboardFocusEffects()
        }
        #endif
    }
}

/// The twenty colours. One another kind wears is disabled and says which kind.
struct CardColourGrid: View {
    let kind: LBCardKind
    let onDone: () -> Void
    private let colours = LBCardColours.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: LBSpacing.s1, alignment: .top), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text(CardColourKinds.title(kind))
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: LBSpacing.s2) {
                ForEach(LBCardSwatch.all) { swatch in
                    cell(swatch)
                }
            }
        }
    }

    private func cell(_ swatch: LBCardSwatch) -> some View {
        let holder = colours.holder(of: swatch)
        let mine = holder == kind
        let taken = holder.map(CardColourKinds.title).flatMap { mine ? nil : $0 }
        return Button {
            Measure.used("card_colour")
            if colours.assign(swatch, to: kind) {
                LBHaptics.tap()
                onDone()
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(swatch.dark.color)
                        .frame(width: 32, height: 32)
                        .opacity(taken == nil ? 1 : 0.35)
                    if mine {
                        Circle()
                            .strokeBorder(LBColor.textPrimary.color, lineWidth: 2)
                            .frame(width: 38, height: 38)
                    }
                }
                .frame(width: 40, height: 40)
                Text(taken ?? swatch.name)
                    .lbText(.footnote)
                    .foregroundStyle((taken == nil ? LBColor.textSecondary : LBColor.textTertiary).color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(taken != nil)
        .help(taken.map { "Used by \($0)" } ?? swatch.name)
        .accessibilityLabel(taken.map { "\(swatch.name), used by \($0)" } ?? swatch.name)
        .accessibilityAddTraits(mine ? .isSelected : [])
    }
}

/// The picker as a phone's sheet: its title, the way out, the list.
struct CardColoursSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            HStack {
                Text("Card colours")
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: LBSpacing.s2)
                Button("Done") { Measure.used("done"); onClose() }
                    .lbButtonStyle()
            }
            ScrollView {
                LBCard { CardColoursList() }
            }
        }
        .padding(LBSpacing.s4)
        .background(LBColor.canvas.color)
    }
}
