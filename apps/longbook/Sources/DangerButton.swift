import DesignSystem
import SwiftUI

/// Every destructive control in one manner: quiet red at rest, filled red under the
/// pointer, and always a confirmation before it acts.
struct DangerButton: View {
    let title: String
    let question: String
    let detail: String
    var confirmLabel: String?
    var fullWidth = false
    let action: () -> Void

    @State private var hovering = false
    @State private var confirming = false

    var body: some View {
        Button {
            Measure.used("confirming")
            confirming = true
        } label: {
            Text(title)
                .lbText(.label)
                .foregroundStyle(hovering ? LBColor.onBrand.color : LBColor.danger.color)
                .padding(.horizontal, LBSpacing.s3)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 34)
                .background(hovering ? LBColor.dangerFill.color : LBColor.chrome.color, in: Capsule())
                .contentShape(Capsule())
        }
        // The red fill is this control's hover; the shared style adds the press.
        .lbButtonStyle(hovers: false)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .measured("danger_button_confirming", .dialog, when: confirming)
        .confirmationDialog(question, isPresented: $confirming, titleVisibility: .visible) {
            Button(confirmLabel ?? title, role: .destructive, action: { Measure.used("danger_confirm"); action() })
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: {
            Text(detail)
        }
    }
}

/// The same danger-styled control, for a way out that opens a screen which does the asking
/// itself instead of a confirmation.
struct DangerLink: View {
    let title: String
    let destination: Destination
    var fullWidth = false

    @State private var hovering = false

    var body: some View {
        NavigationLink(value: destination) {
            Text(title)
                .lbText(.label)
                .foregroundStyle(hovering ? LBColor.onBrand.color : LBColor.danger.color)
                .padding(.horizontal, LBSpacing.s3)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 34)
                .background(hovering ? LBColor.dangerFill.color : LBColor.chrome.color, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle(hovers: false)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
