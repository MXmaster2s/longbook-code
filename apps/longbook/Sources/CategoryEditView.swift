import DesignSystem
import LongbookCore
import SwiftUI

/// Rename a category, or drop it. Rows store the category's word rather than an id, so a
/// rename carries every commitment wearing it — the engine does that in one reviewed
/// write, and this screen only has to ask for the new word and show whose it is.
struct CategoryEditView: View {
    let model: DashboardModel
    let name: String
    let onDone: () -> Void
    /// What happened, for a caller holding the old word — a form mid-edit, a tile.
    var onRenamed: ((String) -> Void)?
    var onDeleted: (() -> Void)?

    @State private var typed = ""
    @State private var error: String?
    /// The category's picture, staged on the Mac and landed with Save.
    @State private var photoData: Data?
    @State private var removingPhoto = false
    @State private var viewingCommitment: Row?

    /// A sheet's subject. A bare id cannot present a sheet — SwiftUI wants something
    /// identifiable, and this is the smallest honest thing that is.
    struct Row: Identifiable, Equatable {
        let id: String
    }

    private var wearers: [Subscription] { model.commitmentsWearing(kind: "commitment", name: name) }
    private var trimmed: String { typed.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var renamed: Bool { !trimmed.isEmpty && trimmed != name }
    private var photoChanged: Bool { photoData != nil || removingPhoto }
    private var changed: Bool { renamed || photoChanged }

    var body: some View {
        // The two decisions sit at the bottom of the screen, under everything they act
        // on, and stay there however long the list of commitments runs.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s4) {
                    header
                    nameField
                    #if os(macOS)
                    VStack(alignment: .leading, spacing: LBSpacing.s2) {
                        Text("Photo")
                            .lbText(.label)
                            .foregroundStyle(LBColor.textSecondary.color)
                        PhotoPickRow(current: model.tagPhotoURL(kind: "commitment", name: name), picked: $photoData, removing: $removingPhoto, shape: .rounded)
                        Text("Shown on the category's tile and its commitments. Kept in your longbook folder.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                    #endif
                    commitments
                    if let error {
                        Text(error)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.urgent.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(LBSpacing.s4)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        // The floor its sibling editors have. Without one this sheet opened smaller than
        // the account editor beside it and resized with the commitment count.
        .frame(minWidth: 480, minHeight: 480)
        .focusEffectDisabled()
        #endif
        .background(LBColor.canvas.color)
        .lbClosesOnOutsideClick(onDone)
        // A commitment opens whole, the same screen a push shows; Edit lives on it.
        .measured("category_edit_viewing_commitment", .sheet, when: viewingCommitment != nil)
        .sheet(item: $viewingCommitment) { row in
            CommitmentDetailView(model: model, id: row.id) { viewingCommitment = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Category")
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(categoryWord(name))
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            Spacer()
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 30, height: 30)
                    .background(LBColor.chrome.color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close without saving")
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text("Category Name")
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
            TextField("", text: $typed, prompt: Text(name).foregroundStyle(LBColor.textTertiary.color))
                .textFieldStyle(.plain)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .padding(LBSpacing.s3)
                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                .autocorrectionDisabled()
            Text("Renaming updates the commitments below.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    /// Whose category this is. Each row keeps two doors: the label comes off here, and
    /// the commitment itself is edited where every other list edits it.
    @ViewBuilder
    private var commitments: some View {
        let rows = wearers
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text(rows.count == 1 ? "1 COMMITMENT" : "\(rows.count) COMMITMENTS")
                .lbText(.eyebrow)
                .foregroundStyle(LBColor.textTertiary.color)
            if rows.isEmpty {
                Text("Nothing wears this category.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            ForEach(rows) { sub in
                Button {
                    viewingCommitment = Row(id: sub.id)
                } label: {
                    HStack(spacing: LBSpacing.s2) {
                        Text(sub.name)
                            .lbText(.bodySM)
                            .foregroundStyle(LBColor.textPrimary.color)
                            .lineLimit(1)
                        Spacer(minLength: LBSpacing.s2)
                        Text(fmtMoney(sub.amount, sub.currency))
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        iconButton("xmark", label: "Take \(name) off \(sub.name)", tone: LBColor.textSecondary) {
                            model.untag(commitmentId: sub.id)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(LBColor.textQuaternary.color)
                    }
                    .frame(minHeight: 36)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, LBSpacing.s1)
                    .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(sub.name)")
            }
        }
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        tone: LBColorValue,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 26, height: 26)
                .background(LBColor.chrome.color, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var actions: some View {
        VStack(spacing: LBSpacing.s3) {
            Button(action: save) {
                Text("Save")
                    .lbText(.label)
                    .foregroundStyle(changed ? LBColor.onBrand.color : LBColor.textTertiary.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LBSpacing.s3)
                    .background(
                        changed ? LBColor.brand.color : LBColor.chrome.color,
                        in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!changed)
            // The other door to delete. Gating only the context menu left this one telling
            // the same lie: a seeded tag has no registry entry to remove, so it returns.
            if model.customTags(kind: "commitment").contains(name) {
            DangerButton(
                title: "Delete Category",
                question: "Delete \"\(name)\"?",
                detail: wearers.count == 1
                    ? "1 commitment keeps its money and loses this label."
                    : "\(wearers.count) commitments keep their money and lose this label.",
                fullWidth: true
            ) {
                model.deleteTag(kind: "commitment", name: name)
                onDeleted?()
                onDone()
            }
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(LBColor.canvas.color)
        .overlay(alignment: .top) {
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
        }
    }

    private func save() {
        guard changed else { return }
        error = nil
        if renamed, !model.renameTag(kind: "commitment", from: name, to: trimmed) {
            error = model.saveError ?? "That didn’t save."
            return
        }
        let finalName = renamed ? trimmed : name
        if photoChanged, let folder = model.vaultFolderURL {
            let key = finalName.lowercased().replacingOccurrences(of: " ", with: "-")
            if let photoData, let named = VaultImages.store(photoData, kind: "tag", id: key, in: folder) {
                model.setTagPhoto(kind: "commitment", name: finalName, photo: named)
            } else if removingPhoto {
                if let old = model.tagPhotoURL(kind: "commitment", name: finalName) { VaultImages.remove(file: old, in: folder) }
                model.setTagPhoto(kind: "commitment", name: finalName, photo: nil)
            }
        }
        if renamed { onRenamed?(trimmed) }
        onDone()
    }
}
