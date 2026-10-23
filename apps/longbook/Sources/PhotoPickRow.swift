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

    /// Writes the picture at most 512 px a side and says what the row should name; nil
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
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(sink) ? out as Data : nil
    }
}

#if os(macOS)
/// The picture and its two verbs in an editor: Choose (or Change) opens the file panel,
/// Remove takes the picture away. Both land with the editor's Save.
struct PhotoPickRow: View {
    let current: URL?
    @Binding var picked: Data?
    @Binding var removing: Bool
    var shape: Shape = .circle
    @State private var choosing = false

    enum Shape { case circle, rounded }

    private var has: Bool { picked != nil || (current != nil && !removing) }

    var body: some View {
        HStack(spacing: LBSpacing.s3) {
            preview
            Button(has ? "Change Photo…" : "Choose Photo…") { choosing = true }
                .buttonStyle(.plain)
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
                    guard case .success(let url) = result else { return }
                    let open = url.startAccessingSecurityScopedResource()
                    defer { if open { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) { picked = data; removing = false }
                }
            if has {
                Button("Remove") { picked = nil; removing = true }
                    .buttonStyle(.plain)
                    .lbText(.label)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let data = picked ?? (removing ? nil : current.flatMap { try? Data(contentsOf: $0) })
        let image = data.flatMap(NSImage.init(data:)).map(Image.init(nsImage:))
        Group {
            if let image {
                image.resizable().scaledToFill()
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
#endif
