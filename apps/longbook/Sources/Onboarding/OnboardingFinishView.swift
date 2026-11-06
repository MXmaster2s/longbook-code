import DesignSystem
import LongbookCore
import SwiftUI

/// Step 3 of the way in: the first statement. Upload asks the consent and opens the picker
/// here, so the reading is the next screen. The owner's own AI waits until the book is open.
/// A kept statement opens the dashboard; Skip opens it as it is.
struct OnboardingFinishView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let clock: OnboardingClock
    let onDone: () -> Void
    let onNotNow: () -> Void
    let onBack: () -> Void
    /// Setup reopened from Settings: the way out.
    var onClose: (() -> Void)? = nil
    /// The demo longbook, for a reader who wants to see one before filling theirs.
    var onDemo: (() -> Void)? = nil

    @State private var importing = false
    @AppStorage(AIConsent.statements.key) private var consented = false
    @State private var askingConsent = false
    @State private var picking = false
    /// The files chosen here, read by the importer as soon as it rises.
    @State private var picked: [URL] = []
    /// Charges in the book when the importer opened: more after it closes means one was kept.
    @State private var chargesBefore = 0

    /// Said beside every statement upload: who reads it, and that nothing is kept.
    static let privacyLine = "No one at longbook sees your statement. It travels encrypted, is read once by an AI model, and longbook keeps none of it. The charges it finds are written to your longbook, in your own folder."

    var body: some View {
        OnboardingStep(dot: 2, mark: .symbol("doc.text.fill")) {
            OnboardingWords(title: "Import a statement",
                            line: "Start with your bank or card statement, and longbook finds the payments you make every month.",
                            note: "Recommended: most recent 6-month statement")
        } actions: {
            OnboardingPrimaryButton(title: "Securely Upload Statement") {
                chargesBefore = model.chargeCount
                if consented { picking = true } else { askingConsent = true }
            }
            HStack(spacing: LBSpacing.s2) {
                if let onDemo { OnboardingTextButton(title: "See Demo", action: onDemo).frame(maxWidth: .infinity) }
                OnboardingTextButton(title: "Skip", action: onNotNow).frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onClose { OnboardingCloseButton(action: onClose).padding(LBSpacing.s2) }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { onBack(); return .handled }
        .onKeyPress(.leftArrow) { onBack(); return .handled }
        // A statement kept opens the book: the reader never comes back to this step.
        // The sheet takes the import's own size: no frame here may hold it to another.
        .measured("onboarding_finish_asking_consent", .sheet, when: askingConsent)
        .sheet(isPresented: $askingConsent) {
            ConsentSheet(consent: .statements, onAccept: {
                consented = true
                askingConsent = false
                // The picker cannot open while this sheet is still leaving.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { picking = true }
            }, onDecline: { askingConsent = false })
                .lbKeyboardFocusEffects()
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: StatementImportView.pickable, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            picked = Array(urls.prefix(StatementImportView.filesAtOnce))
            importing = true
        }
        .measured("onboarding_finish_importing", .sheet, when: importing)
        .sheet(isPresented: $importing, onDismiss: { if model.chargeCount > chargesBefore { onDone() } }) {
            StatementImportView(model: model, auth: auth, context: .setup, dropped: picked, onDone: { importing = false })
                .lbKeyboardFocusEffects()
        }
    }
}
