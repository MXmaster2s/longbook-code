import DesignSystem
import LongbookCore
import SwiftUI

/// Sharing, under the report it shares. One live share per report: a password-protected
/// link that expires in days, revocable, whose viewer comments come back into the vault.
/// The card says what is known about the share; the password is shown once, in a sheet,
/// the moment the link is made.
struct ReportSharingCard: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let reportId: String
    /// Counts links made and ended. The share itself lives in the sidecar, which nothing
    /// observes, so a screen reading the state is told when to read it again.
    var revision: Binding<Int> = .constant(0)

    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var pulled: Int?
    @State private var copied = false
    @State private var with = ""
    /// The link just made, with its password: on screen only while the sheet is up.
    @State private var fresh: FreshShare?
    /// The Cloud door, opened when a link is asked for without Cloud. Viewing and
    /// commenting on a link already made stay open; ending one does too.
    @State private var paywall = false

    var body: some View {
        LBPanel {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                if !auth.isSignedIn {
                    Text("Sign in to share this report.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                } else if let share = model.shareDetails(forReport: reportId) {
                    liveShare(share)
                } else {
                    notShared
                }
                if let notice {
                    Text(notice)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.urgent.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { with = model.shareDetails(forReport: reportId)?.with ?? "" }
        .onChange(of: with) { _, _ in saveWith() }
        .sheet(item: $fresh) { made in
            ShareCreatedSheet(share: made)
        }
        .cloudPaywall(isPresented: $paywall, auth: auth)
    }

    // MARK: states

    private var notShared: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text("Not shared.")
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
            Text("A link and a password open the report for 3 days, without a longbook account. It can be ended sooner.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            if !model.hasCloud {
                Text("Sharing a report is part of longbook Cloud.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionButton(busy ? "Sharing…" : "Share report", filled: true) {
                await createShare()
            }
        }
    }

    /// Everything known about the share, in facts. The password is not among them: the
    /// server keeps only its hash, and the sheet showed it once.
    private func liveShare(_ share: DashboardModel.ShareDetails) -> some View {
        let ended = share.expiresAt.map { $0 <= Date() } ?? false
        return VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text(status(share, ended: ended))
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                fact("Link", share.url, copyable: true)
                withField
            }
            if let pulled {
                Text("\(pulled) new comment\(pulled == 1 ? "" : "s") added to the report.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            HStack(spacing: LBSpacing.s3) {
                if ended {
                    actionButton(busy ? "Sharing…" : "Share again", filled: true) {
                        await createShare()
                    }
                    actionButton("Remove", filled: false) {
                        await revoke()
                    }
                } else {
                    actionButton(busy ? "Checking…" : "Pull comments", filled: true) {
                        await pullComments()
                    }
                    actionButton("Stop sharing", filled: false) {
                        await revoke()
                    }
                }
            }
        }
    }

    /// "Shared 30 Sep 2026 · expires 3 Oct, 15:45", or that the link has ended.
    private func status(_ share: DashboardModel.ShareDetails, ended: Bool) -> String {
        if ended { return "The link has ended. It no longer opens." }
        let parts = [
            share.sharedOn.map { "Shared \(LB.shortDate($0))" },
            share.expiresAt.map { "expires \(whenWord($0))" },
        ].compactMap { $0 }
        return parts.isEmpty ? "Shared." : parts.joined(separator: " · ")
    }

    // MARK: pieces

    private func fact(_ label: String, _ value: String, copyable: Bool) -> some View {
        HStack(spacing: LBSpacing.s2) {
            factLabel(label)
            Text(value)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: LBSpacing.s2)
            if copyable {
                Button {
                    copyToClipboard(value)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(label)")
            }
        }
        .frame(minHeight: 32)
    }

    /// Who was given the link — the owner's own note, kept beside the share.
    private var withField: some View {
        HStack(spacing: LBSpacing.s2) {
            factLabel("Shared with")
            TextField("", text: $with, prompt: Text("Nobody noted yet").foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textPrimary.color)
        }
        .frame(minHeight: 32)
    }

    private func factLabel(_ label: String) -> some View {
        Text(label)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .frame(width: 84, alignment: .leading)
    }

    /// "10 Sep 2026, 15:45" — an instant, in the device's own zone and clock.
    private func whenWord(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .lbText(.label)
                .foregroundStyle(filled ? LBColor.onBrand.color : LBColor.textSecondary.color)
                .padding(.horizontal, LBSpacing.s4)
                .padding(.vertical, LBSpacing.s2)
                .background(filled ? LBColor.brand.color : LBColor.chrome.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// Every keystroke lands, so a note survives the view going away mid-word.
    private func saveWith() {
        let note = with.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note != (model.shareDetails(forReport: reportId)?.with ?? "") else { return }
        model.noteShare(forReport: reportId, "with", note)
    }

    // MARK: actions

    private func createShare() async {
        // Making a link is Cloud's; the server refuses one without it.
        guard model.hasCloud else {
            paywall = true
            return
        }
        guard let file = model.reportFile(id: reportId) else {
            error = "The report file could not be found in the folder."
            return
        }
        guard let token = await auth.accessToken() else {
            error = "Sign in again to share this report."
            return
        }
        busy = true
        error = nil
        notice = nil
        do {
            // A link being replaced is taken down first; the server may have dropped it already.
            if let old = model.shareId(forReport: reportId) {
                try? await ShareReportClient.revoke(id: old, token: token)
            }
            let share = try await ShareReportClient.create(reportJSON: Self.forViewers(file.bytes), hours: 72, token: token)
            Telemetry.shared.send("app.report_shared")
            var details = ["url": share.url, "expires_at": share.expiresAt, "shared_on": VaultPatch.iso8601(Date())]
            let note = with.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { details["with"] = note }
            model.rememberShare(share.id, forReport: reportId, details: details)
            fresh = FreshShare(id: share.id, url: share.url, password: share.password)
            pulled = nil
            revision.wrappedValue += 1
        } catch {
            Telemetry.shared.failed(.reportShare, error)
            self.error = error.friendlyDescription
        }
        busy = false
    }

    /// The report as a viewer may read it: no charge ids and no list of charges dropped for
    /// good, which would say what the owner left out. Comments are keyed by module, never by row.
    static func forViewers(_ bytes: Data) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return bytes }
        object.removeValue(forKey: "hidden_ids")
        if let modules = object["modules"] as? [[String: Any]] {
            object["modules"] = modules.map { module -> [String: Any] in
                guard var rows = module["rows"] as? [[String: Any]] else { return module }
                rows = rows.map { row in var copy = row; copy.removeValue(forKey: "id"); return copy }
                var copy = module
                copy["rows"] = rows
                return copy
            }
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? bytes
    }

    private func pullComments() async {
        guard let token = await auth.accessToken(),
              let shareId = model.shareId(forReport: reportId) else { return }
        busy = true
        error = nil
        notice = nil
        do {
            let reply = try await ShareReportClient.comments(id: shareId, token: token)
            if let expiresAt = reply.expiresAt {
                model.noteShare(forReport: reportId, "expires_at", expiresAt)
            }
            let notes = reply.comments.map { comment in
                let author = comment.author?.trimmingCharacters(in: .whitespaces)
                return (module: comment.moduleId, line: "\(author?.isEmpty == false ? author! : "Someone") — \(comment.body)")
            }
            pulled = model.mergeComments(notes, intoReport: reportId) ?? 0
        } catch let failure as ShareReportClient.ShareError where failure.shareIsGone {
            endShare()
        } catch {
            Telemetry.shared.failed(.reportShare, error)
            self.error = error.friendlyDescription
        }
        busy = false
    }

    private func revoke() async {
        guard let token = await auth.accessToken(),
              let shareId = model.shareId(forReport: reportId) else { return }
        busy = true
        error = nil
        notice = nil
        do {
            try await ShareReportClient.revoke(id: shareId, token: token)
            Telemetry.shared.send("app.report_revoked")
            endShare(notice: nil)
        } catch let failure as ShareReportClient.ShareError where failure.shareIsGone {
            endShare()
        } catch {
            Telemetry.shared.failed(.reportShare, error)
            self.error = error.friendlyDescription
        }
        busy = false
    }

    /// The share is over — by the owner's hand, or because the server no longer has it.
    private func endShare(notice: String? = "The link has ended.") {
        model.rememberShare(nil, forReport: reportId)
        pulled = nil
        with = ""
        self.notice = notice
        revision.wrappedValue += 1
    }
}

/// A link just made, carried to the sheet that shows it once.
private struct FreshShare: Identifiable {
    let id: String
    let url: String
    let password: String
}

/// The one time the password is on screen: the link and the password side by side, each
/// with a copy button, and the word to send them apart.
private struct ShareCreatedSheet: View {
    let share: FreshShare
    @Environment(\.dismiss) private var dismiss
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text("Report shared")
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("Send the link and the password separately. The password is shown only now; longbook keeps no copy.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LBPanel {
                VStack(spacing: 0) {
                    row("Link", share.url, key: "url")
                    Rectangle().fill(LBColor.hairline.color).frame(height: 1)
                    row("Password", share.password, key: "password")
                }
            }
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .lbText(.body)
                    .foregroundStyle(LBColor.onBrand.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LBSpacing.s3)
                    .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LBColor.canvas.color)
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    private func row(_ label: String, _ value: String, key: String) -> some View {
        HStack(spacing: LBSpacing.s2) {
            Text(label)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .lbText(key == "password" ? .numberSM : .footnote)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: LBSpacing.s2)
            Button {
                copyToClipboard(value)
                copied = key
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if copied == key { copied = nil }
                }
            } label: {
                Image(systemName: copied == key ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(label)")
        }
        .frame(minHeight: 36)
    }
}

private func copyToClipboard(_ value: String) {
    #if os(iOS)
    UIPasteboard.general.string = value
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    #endif
}
