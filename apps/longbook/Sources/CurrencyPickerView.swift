import DesignSystem
import LongbookCore
import SwiftUI

/// The world's codes, to put one on the quick selector. Typing three letters into a box
/// asked the reader to already know the answer; this states the list and lets it be found.
struct CurrencyPickerView: View {
    let already: [String]
    let onPick: (String) -> Void
    let onDone: () -> Void

    @State private var typed = ""

    /// One column, not two. Localized names run from "Euro" to "United Arab Emirates
    /// Dirham"; halved, a quarter of them lost their tails, USD's among them.
    private static let columns = [GridItem(.flexible(), spacing: LBSpacing.s2)]

    /// Every code the system knows, named. The ones already on the selector are shown as
    /// taken rather than hidden, so a code that is missing is missing for a reason.
    private var codes: [(code: String, name: String)] {
        let locale = Locale.current
        let all = Locale.commonISOCurrencyCodes.map {
            (code: $0, name: locale.localizedString(forCurrencyCode: $0) ?? $0)
        }
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.code.lowercased().contains(needle) || $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            header
            search
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: LBSpacing.s2) {
                    ForEach(codes, id: \.code) { entry in
                        tile(entry)
                    }
                }
                .padding(.bottom, LBSpacing.s4)
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
        .background(LBColor.canvas.color)
        .lbClosesOnOutsideClick(onDone)
    }

    private var header: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: LBGlyph.currency)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LBColor.textSecondary.color)
            Text("Currency")
                .lbText(.label)
                .foregroundStyle(LBColor.textPrimary.color)
            Spacer()
            Button(action: { Measure.used("close"); onDone() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 30, height: 30)
                    .background(LBColor.chrome.color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var search: some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
            TextField("", text: $typed,
                      prompt: Text("Code or name").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
        }
        .padding(LBSpacing.s3)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    private func tile(_ entry: (code: String, name: String)) -> some View {
        let taken = already.contains(entry.code)
        return Button {
            Measure.used("guard")
            guard !taken else { return }
            LBHaptics.tap()
            onPick(entry.code)
            onDone()
        } label: {
            HStack(spacing: LBSpacing.s2) {
                Text(entry.code)
                    .lbText(.label)
                    .foregroundStyle(taken ? LBColor.textQuaternary.color : LBColor.textPrimary.color)
                    .frame(width: 42, alignment: .leading)
                Text(entry.name)
                    .lbText(.footnote)
                    .foregroundStyle(taken ? LBColor.textQuaternary.color : LBColor.textTertiary.color)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(LBSpacing.s3)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(taken)
        .accessibilityLabel("\(entry.code), \(entry.name)\(taken ? ", already listed" : "")")
    }
}
