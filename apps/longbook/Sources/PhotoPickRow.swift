import DesignSystem
import ImageIO
import LongbookCore
import SwiftUI
import UniformTypeIdentifiers

/// Pictures the owner gives things: kept as small files under the longbook folder's
/// images/, named by what they picture, and never anywhere else. The Mac writes them;
/// the phone only shows them.
enum VaultImages {
    static func name(kind: String, id: String) -> String { "images/\(kind)-\(id).jpg" }

    /// The pixels a side a picture is kept at: enough for the largest place one shows, a
    /// 48 pt preview or an avatar at the largest text size, on a 3x screen.
    static let side = 512

    /// Writes the picture at most `side` px a side and says what the row should name; nil
    /// when the bytes are not an image or the file could not be written.
    static func store(_ data: Data, kind: String, id: String, in folder: URL) -> String? {
        guard let small = smallJPEG(data) else { return nil }
        let relative = name(kind: kind, id: id)
        let file = folder.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? small.write(to: file, options: .atomic)) == nil ? nil : relative
    }

    /// Removes a picture file by its URL, only when it sits inside the folder.
    static func remove(file: URL, in folder: URL) {
        guard file.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else { return }
        try? FileManager.default.removeItem(at: file)
    }

    static func remove(_ relative: String?, in folder: URL) {
        guard let relative, !relative.isEmpty, !relative.contains("..") else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(relative))
    }

    private static func smallJPEG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(sink) ? out as Data : nil
    }
}

#if os(macOS)
/// The picture and its menu in an editor: Choose Photo…, Paste Photo and Remove Photo, the
/// first two through Move and Scale. All land with the editor's Save.
struct PhotoPickRow: View {
    let current: URL?
    @Binding var picked: Data?
    @Binding var removing: Bool
    var shape: PhotoShape = .circle
    @Environment(\.displayScale) private var displayScale

    private var has: Bool { picked != nil || (current != nil && !removing) }

    var body: some View {
        HStack(spacing: LBSpacing.s3) {
            preview
            PhotoMenu(has: has, shape: shape, picked: $picked, removing: $removing) {
                HStack(spacing: LBSpacing.s1) {
                    Text(has ? "Change Photo" : "Add Photo")
                        .lbText(.label)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(LBColor.brandText.color)
                .fixedSize()
                .contentShape(Rectangle())
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private var preview: some View {
        let image = picked.flatMap { LBPhoto.image(data: $0, side: 48, scale: displayScale) }
            ?? (removing ? nil : LBPhoto.image(file: current, side: 48, scale: displayScale))
        Group {
            if let image {
                image
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LBColor.textTertiary.color)
            }
        }
        .frame(width: 48, height: 48)
        .background(LBColor.chrome.color)
        .clipShape(AnyShape(shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))))
        .accessibilityHidden(true)
    }
}

/// The picture and its menu in an editor, as one field: Choose Photo…, Paste Photo and Remove
/// Photo, the first two through Move and Scale. All land with the editor's Save.
struct PhotoMenuField: View {
    let current: URL?
    @Binding var picked: Data?
    @Binding var removing: Bool
    var shape: PhotoShape = .circle
    @Environment(\.displayScale) private var displayScale

    private var has: Bool { picked != nil || (current != nil && !removing) }

    var body: some View {
        PhotoMenu(has: has, shape: shape, picked: $picked, removing: $removing) {
            FormField {
                HStack(spacing: LBSpacing.s2) {
                    preview
                    Text(has ? "Change" : "Add")
                        .lbText(.body)
                        .foregroundStyle((has ? LBColor.textPrimary : LBColor.textTertiary).color)
                    Spacer(minLength: LBSpacing.s2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LBColor.textTertiary.color)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = picked.flatMap({ LBPhoto.image(data: $0, side: 18, scale: displayScale) })
            ?? (removing ? nil : LBPhoto.image(file: current, side: 18, scale: displayScale)) {
            image
                .frame(width: 18, height: 18)
                .clipShape(AnyShape(shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))))
                .accessibilityHidden(true)
        }
    }
}
#endif
