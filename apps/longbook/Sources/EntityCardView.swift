import DesignSystem
import LongbookCore
import SwiftUI

/// The words the account and people screens share, so the list, the editor and the
/// delete question never drift apart.
enum EntityCopy {
    static func word(_ kind: VaultPatch.EntityKind) -> String {
        kind == .paymentMethod ? "account" : "person"
    }

    /// The vault's own word for the kind, which insight keys are filed under.
    static func insightWord(_ kind: VaultPatch.EntityKind) -> String {
        kind == .paymentMethod ? "account" : "member"
    }

    /// A card's name as it reads: the bucket of commitments naming nobody is Unassigned.
    static func name(_ card: DashboardModel.EntityCard) -> String {
        card.isReal ? card.name : "Unassigned"
    }

    /// The counts first: the numbers are the whole reason to hesitate. Commitments are
    /// counted as the card counts them; settled one-time charges and, for a person, their
    /// accounts are named beside them, since deleting unhooks those too.
    static func removalNote(
        _ kind: VaultPatch.EntityKind, use: (commitments: Int, oneTime: Int, accounts: Int)
    ) -> String {
        let isAccount = kind == .paymentMethod
        let parts = [
            use.commitments > 0 ? counted(use.commitments, "commitment") : nil,
            use.oneTime > 0 ? counted(use.oneTime, "one-time charge") : nil,
            use.accounts > 0 ? counted(use.accounts, "account") : nil,
        ].compactMap { $0 }
        guard let last = parts.last else {
            return isAccount
                ? "No commitment uses this account. Deleting it changes nothing else."
                : "Nothing names this person. Deleting them changes nothing else."
        }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + last : last
        let single = use.commitments + use.oneTime + use.accounts == 1
        let verb = isAccount ? (single ? "uses this account" : "use this account")
            : (single ? "names this person" : "name this person")
        return "\(list) \(verb). \(single ? "It stays" : "They stay"), without \(isAccount ? "an account" : "a person")."
    }

    /// The same note for many: the use added up, and "these" in place of "this".
    static func removalNote(
        _ kind: VaultPatch.EntityKind, many use: (commitments: Int, oneTime: Int, accounts: Int)
    ) -> String {
        let isAccount = kind == .paymentMethod
        let parts = [
            use.commitments > 0 ? counted(use.commitments, "commitment") : nil,
            use.oneTime > 0 ? counted(use.oneTime, "one-time charge") : nil,
            use.accounts > 0 ? counted(use.accounts, "account") : nil,
        ].compactMap { $0 }
        guard let last = parts.last else {
            return isAccount
                ? "No commitment uses these accounts. Deleting them changes nothing else."
                : "Nothing names these people. Deleting them changes nothing else."
        }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + last : last
        let single = use.commitments + use.oneTime + use.accounts == 1
        let verb = isAccount ? (single ? "uses these accounts" : "use these accounts")
            : (single ? "names these people" : "name these people")
        return "\(list) \(verb). \(single ? "It stays" : "They stay"), without \(isAccount ? "an account" : "a person")."
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// A tag as it reads: its first letter raised, and the few that are initials in full.
    static func tagWord(_ tag: String) -> String { categoryWord(tag) }
}

/// The add form as an account or a person opens it, with that account or person already
/// chosen. The one place the cards and the editor open it from.
@MainActor
func entityAddForm(
    model: DashboardModel, kind: VaultPatch.EntityKind, id: String, onDone: @escaping () -> Void
) -> some View {
    RenewalFormView(
        model: model, editingId: nil,
        seedMethodId: kind == .paymentMethod ? id : nil,
        seedMemberId: kind == .familyMember ? id : nil,
        onDone: onDone
    )
}

/// The initial in a tinted circle: the colour an account or a person wears everywhere. A
/// person with a picture in the folder shows it instead, in the same circle.
struct EntityAvatar: View {
    let name: String
    let ink: Int?
    var size: CGFloat = 36
    var photo: URL? = nil
    var photoData: Data? = nil
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Circle()
            .fill(LBColor.dataInk(rank: ink).color.opacity(0.22))
            .frame(width: size * scale, height: size * scale)
            .overlay {
                if let image = picture {
                    image
                        .frame(width: size * scale, height: size * scale)
                        .clipShape(Circle())
                } else {
                    Text(name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                        .lbText(size >= 30 ? .body : .tabLabel)
                        .foregroundStyle(LBColor.textPrimary.color)
                }
            }
            .accessibilityHidden(true)
    }

    /// The picked bytes first, then the file in the folder; a file that will not open draws the initial.
    private var picture: Image? {
        if let photoData { return LBPhoto.image(data: photoData, side: size * scale, scale: displayScale) }
        return LBPhoto.image(file: photo, side: size * scale, scale: displayScale)
    }
}

/// A commitment's glyph on its tile, tinted with its category's ink.
struct EntityGlyphTile: View {
    let symbol: String
    var ink: Int?
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(LBColor.dataInk(rank: ink).color)
            .frame(width: size, height: size)
            .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A card's action, drawn one way whether a button or a link carries it.
struct EntityActionLabel: View {
    let title: String
    let symbol: String
    let prominent: Bool
    var fills = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .lbText(.bodySM)
                .lineLimit(1)
        }
        .foregroundStyle((prominent ? LBColor.onBrandTint : LBColor.textPrimary).color)
        .padding(.horizontal, LBSpacing.s4)
        .frame(maxWidth: fills ? .infinity : nil, minHeight: Self.height)
        .background(
            prominent ? LBColor.brand.color.opacity(0.12) : LBColor.chrome.color,
            in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                .strokeBorder(prominent ? LBColor.brand.color.opacity(0.45) : LBColor.hairline.color, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    /// A finger's target on the phone; the pointer needs less.
    static var height: CGFloat {
        #if os(iOS)
        44
        #else
        36
        #endif
    }
}
