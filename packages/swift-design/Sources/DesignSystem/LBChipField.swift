import SwiftUI

/// A name typed where it will sit: a pill on the row rather than a box beneath it, so a
/// rack or a flow keeps its shape while the word is typed. The caller holds the focus and
/// the field takes the cursor when it appears.
public struct LBChipField: View {
    /// How the pill gets its height: padding around the line, or a floor under it.
    public enum Height: Equatable {
        case padded(CGFloat)
        case floor(CGFloat)
    }

    private let prompt: String
    private let text: Binding<String>
    private let width: CGFloat
    private let height: Height
    private let fillOpacity: Double
    private let focus: FocusState<Bool>.Binding
    private let onSubmit: () -> Void

    public init(
        _ prompt: String,
        text: Binding<String>,
        width: CGFloat,
        height: Height = .padded(LBSpacing.s2),
        fillOpacity: Double = 0.12,
        focus: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.text = text
        self.width = width
        self.height = height
        self.fillOpacity = fillOpacity
        self.focus = focus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        sized
            .background(LBColor.brand.color.opacity(fillOpacity), in: Capsule())
            .overlay(Capsule().strokeBorder(LBColor.brand.color, lineWidth: 1))
    }

    @ViewBuilder
    private var sized: some View {
        switch height {
        case .padded(let amount): line.padding(.vertical, amount)
        case .floor(let minimum): line.frame(minHeight: minimum)
        }
    }

    private var line: some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(LBColor.textTertiary.color))
            .textFieldStyle(.plain)
            .lbText(.bodySM)
            .foregroundStyle(LBColor.brandText.color)
            .focused(focus)
            // The field takes the cursor once it exists; before that there is nothing to focus.
            .onAppear { focus.wrappedValue = true }
            .onSubmit(onSubmit)
            .submitLabel(.done)
            .accessibilityLabel(prompt)
            .frame(width: width)
            .padding(.horizontal, LBSpacing.s3)
    }
}
