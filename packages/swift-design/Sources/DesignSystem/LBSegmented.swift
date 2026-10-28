import SwiftUI

/// Two or three choices in one control. On the Mac it is the system's segmented control, with
/// hover, pressed, focus and the arrow keys, its chosen segment drawn plain, never in the accent
/// colour. The phone draws its own: a chrome track, the chosen one raised on a card.
public struct LBSegmented<Value: Hashable>: View {
    @Binding private var selection: Value
    private let choices: [(value: Value, label: String)]

    public init(selection: Binding<Value>, choices: [(value: Value, label: String)]) {
        _selection = selection
        self.choices = choices
    }

    public var body: some View {
        #if os(macOS)
        Picker("", selection: $selection) {
            ForEach(choices, id: \.value) { choice in
                Text(choice.label).tag(choice.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #else
        HStack(spacing: 2) {
            ForEach(choices, id: \.value) { choice in
                let chosen = choice.value == selection
                Button {
                    guard !chosen else { return }
                    withAnimation(.snappy(duration: 0.2)) { selection = choice.value }
                } label: {
                    Text(choice.label)
                        .lbText(.label)
                        .foregroundStyle(chosen ? LBColor.textPrimary.color : LBColor.textSecondary.color)
                        .lineLimit(1)
                        // At the largest sizes a half-width word shrinks before it would truncate.
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, LBSpacing.s3)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(chosen ? LBColor.card.color : .clear, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                                .strokeBorder(chosen ? LBColor.hairline.color : .clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .lbButtonStyle(.rounded(LBRadius.xs), hovers: false)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .accessibilityElement(children: .contain)
        #endif
    }
}
