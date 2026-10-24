import DesignSystem
import LongbookCore
import SwiftUI

/// What Sign out opens: the two ways to leave, each asking once more, and every place the
/// account is signed in, so a person sees what "all sessions" would end before choosing.
struct SignOutScreenView: View {
    @ObservedObject var auth: AuthViewModel
    @State private var answer: ActiveSessionList?
    @State private var loading = true
    @State private var reading = false
    @State private var signingOutAll = false
    @State private var failure: String?

    var body: some View {
        SettingsScreen(title: "Sign out", note: "Your folder stays where it is either way. Signing back in picks up the same memory.") {
            buttons
            list
        }
        .task { await load() }
    }

    private func load() async {
        // One read at a time: a second tap on Try again waits for the first.
        guard !reading else { return }
        reading = true
        loading = true
        defer {
            reading = false
            loading = false
        }
        #if DEBUG
        // Development only: the offscreen harness has no account to ask about.
        if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] == "signout" {
            answer = ActiveSessionList(sessions: Self.sample, total: Self.sample.count)
            return
        }
        #endif
        answer = await auth.activeSessions()
    }

    // MARK: the two ways out

    private var buttons: some View {
        VStack(spacing: LBSpacing.s3) {
            DangerButton(
                title: "Sign Out This Session",
                question: "Sign out of this device?",
                detail: "Your other devices and connected AI apps stay signed in.",
                fullWidth: true
            ) {
                Task { await auth.signOut() }
            }
            DangerButton(
                title: "Sign Out All Sessions",
                question: "Sign out everywhere?",
                detail: "Every device and every connected AI app is signed out, this one too. Sign in again on each to use it.",
                confirmLabel: "Sign Out All Sessions",
                fullWidth: true
            ) {
                guard !signingOutAll else { return }
                signingOutAll = true
                failure = nil
                Task {
                    failure = await auth.signOutEverywhere()
                    signingOutAll = false
                }
            }
            .disabled(signingOutAll)
            if let failure {
                Text(failure)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.danger.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: where the account is signed in

    @ViewBuilder
    private var list: some View {
        LBSectionHeader("Active sessions")
        if let answer {
            if answer.sessions.isEmpty {
                Text("No active sessions to show.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(answer.sessions.enumerated()), id: \.element.id) { index, session in
                        SessionRow(session: session, separated: index < answer.sessions.count - 1)
                    }
                }
                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                        .strokeBorder(LBColor.hairline.color, lineWidth: 1)
                )
                if answer.total > answer.sessions.count {
                    Text("And \(answer.total - answer.sessions.count) more. Sign Out All Sessions ends them too.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                if answer.sessions.contains(where: { $0.kind == .connector }) {
                    Text("A session named for an AI is a connector you set up. Signing out of all sessions ends it, and you connect it again.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if loading {
            HStack(spacing: LBSpacing.s2) {
                ProgressView().controlSize(.small)
                Text("Reading your sessions…")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        } else {
            Text("Your sessions could not be listed. Signing out still works.")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Measure.used("try_again")
                Task { await load() }
            } label: {
                Text("Try Again")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    #if DEBUG
    private static let sample: [ActiveSession] = {
        let now = Date()
        return [
            ActiveSession(id: "1", kind: .app, label: "iPhone", detail: "longbook 18 · iOS 27.0",
                          signedInAt: now.addingTimeInterval(-9 * 86400), lastActiveAt: now, isThisDevice: true),
            ActiveSession(id: "2", kind: .app, label: "Mac", detail: "longbook 18 · macOS 27.2",
                          signedInAt: now.addingTimeInterval(-20 * 86400), lastActiveAt: now.addingTimeInterval(-3 * 3600), isThisDevice: false),
            ActiveSession(id: "3", kind: .connector, label: "Claude", detail: "AI connector",
                          signedInAt: now.addingTimeInterval(-5 * 3600), lastActiveAt: now.addingTimeInterval(-600), isThisDevice: false),
            ActiveSession(id: "4", kind: .app, label: "longbook app", detail: "longbook 15",
                          signedInAt: now.addingTimeInterval(-40 * 86400), lastActiveAt: now.addingTimeInterval(-6 * 86400), isThisDevice: false),
        ]
    }()
    #endif
}

/// One session: its device or connector, what is known about it, when it began and was last
/// used, and a mark on the one this screen is open on.
private struct SessionRow: View {
    let session: ActiveSession
    let separated: Bool

    private var symbol: String {
        switch session.kind {
        case .connector: "sparkles"
        case .browser: "globe"
        case .other: "questionmark.circle"
        case .app:
            switch session.label {
            case "Mac": "laptopcomputer"
            case "iPad": "ipad"
            case "iPhone": "iphone"
            default: "app.dashed"
            }
        }
    }

    private var when: String {
        var parts: [String] = []
        if let began = session.signedInAt { parts.append("Signed in \(LB.longDate(began))") }
        if let used = session.lastUsedWords() { parts.append("used \(used)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: LBSpacing.s3) {
            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                .fill(LBColor.neutralFold.color.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LBColor.neutralFold.color)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: LBSpacing.s2) {
                    Text(session.label)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                    if session.isThisDevice {
                        Text("This device")
                            .lbText(.tabLabel)
                            .foregroundStyle(LBColor.brandText.color)
                            .padding(.horizontal, LBSpacing.s2)
                            .padding(.vertical, 2)
                            .background(LBColor.brand.color.opacity(0.14), in: Capsule())
                    }
                }
                if !session.detail.isEmpty {
                    Text(session.detail)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                if !when.isEmpty {
                    Text(when)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(LBSpacing.s3)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottom) {
            if separated {
                Rectangle().fill(LBColor.hairline.color).frame(height: 1)
                    .padding(.leading, 34 + LBSpacing.s3 * 2)
            }
        }
    }
}
