import DesignSystem
import LongbookCore
import SwiftUI

/// Everyone the vault pays for, shown as People: their relationship, how many commitments
/// and charges are theirs, listed and opened whole. The screen is shared with Accounts.
struct MembersView: View {
    let model: DashboardModel

    var body: some View {
        EntityListView(model: model, kind: .familyMember)
    }
}
