import SwiftUI

/// One action a list row offers. A destructive one with a `confirm` question asks before
/// it runs; everything else runs on the tap.
public struct LBRowAction: Identifiable {
    public let id: String
    let title: String
    let systemImage: String
    let destructive: Bool
    let tint: LBColorValue?
    let confirm: Confirmation?
    let run: () -> Void

    /// The question a destructive action asks, and the words on its button.
    public struct Confirmation {
        let question: String
        let message: String?
        let button: String

        public init(_ question: String, message: String? = nil, button: String) {
            self.question = question
            self.message = message
            self.button = button
        }
    }

    public init(
        _ title: String, systemImage: String, tint: LBColorValue? = nil, run: @escaping () -> Void
    ) {
        self.id = title
        self.title = title
        self.systemImage = systemImage
        self.destructive = false
        self.tint = tint
        self.confirm = nil
        self.run = run
    }

    /// A destructive action: red, last in its edge, and asking first when `confirm` is set.
    public static func destructive(
        _ title: String, systemImage: String = "trash", confirm: Confirmation? = nil, run: @escaping () -> Void
    ) -> LBRowAction {
        LBRowAction(id: title, title: title, systemImage: systemImage, destructive: true, tint: nil, confirm: confirm, run: run)
    }

    private init(
        id: String, title: String, systemImage: String, destructive: Bool, tint: LBColorValue?,
        confirm: Confirmation?, run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.destructive = destructive
        self.tint = tint
        self.confirm = confirm
        self.run = run
    }
}

public extension View {
    /// A row's actions as the platform offers them: swipe actions on each edge, and the
    /// same actions in the context menu, so a click on the Mac reaches what a swipe does.
    /// Swipes need the row to sit inside a `List`.
    func lbRowActions(leading: [LBRowAction] = [], trailing: [LBRowAction] = []) -> some View {
        modifier(LBRowActionsModifier(leading: leading, trailing: trailing))
    }
}

private struct LBRowActionsModifier: ViewModifier {
    let leading: [LBRowAction]
    let trailing: [LBRowAction]
    @State private var asking: LBRowAction?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                ForEach(leading) { button($0) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: trailing.first?.confirm == nil) {
                ForEach(trailing) { button($0) }
            }
            .contextMenu {
                ForEach(leading + trailing.filter { !$0.destructive }) { button($0) }
                let destructive = trailing.filter(\.destructive)
                if !destructive.isEmpty {
                    Divider()
                    ForEach(destructive) { button($0) }
                }
            }
            .confirmationDialog(
                asking?.confirm?.question ?? "",
                isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                titleVisibility: .visible,
                presenting: asking
            ) { action in
                Button(action.confirm?.button ?? action.title, role: .destructive) { action.run() }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                if let message = action.confirm?.message { Text(message) }
            }
    }

    @ViewBuilder
    private func button(_ action: LBRowAction) -> some View {
        let tap = {
            if action.confirm != nil { asking = action } else { action.run() }
        }
        if action.destructive {
            Button(role: .destructive, action: tap) {
                Label(action.title, systemImage: action.systemImage)
            }
        } else {
            Button(action: tap) {
                Label(action.title, systemImage: action.systemImage)
            }
            .tint(action.tint?.color ?? LBColor.brand.color)
        }
    }
}
