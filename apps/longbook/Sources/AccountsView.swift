import DesignSystem
import LongbookCore
import SwiftUI

/// A card the owner can actually edit — the synthetic "no account" bucket is not one.
struct EntityTarget: Identifiable {
    let id: String
    let name: String
}

/// Every account: its type, what it holds, whose it is and what hangs on it, listed and
/// opened whole. The screen is shared with People; this names the kind.
struct AccountsView: View {
    let model: DashboardModel

    var body: some View {
        EntityListView(model: model, kind: .paymentMethod)
    }
}
