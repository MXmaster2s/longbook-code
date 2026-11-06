import DesignSystem
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import PhotosUI
import UIKit
#endif

/// The shape a photo sits in: a person's circle, or a card icon's rounded square.
enum PhotoShape {
    case circle, rounded

    /// The outline at this side, for the Move and Scale hole.
    func outline(side: CGFloat) -> AnyShape {
        switch self {
        case .circle: AnyShape(Circle())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: side / 4, style: .continuous))
        }
    }
}

/// Bytes just chosen or pasted, on their way through Move and Scale.
struct PhotoInHand: Identifiable {
    let id = UUID()
    let data: Data
}

/// The pasteboard's picture, if it holds one.
enum PhotoPasteboard {
    /// Whether a picture is there, asked without reading it, so no paste prompt shows.
    static var holdsImage: Bool {
        #if os(macOS)
        let board = NSPasteboard.general
        if board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return imageFile(board) != nil }
        return (board.types ?? []).contains { UTType($0.rawValue)?.conforms(to: .image) == true }
        #else
        UIPasteboard.general.hasImages
        #endif
    }

    /// The picture's bytes as the pasteboard holds them; nil when there is none.
    static func imageData() -> Data? {
        #if os(macOS)
        let board = NSPasteboard.general
        if let file = imageFile(board) { return try? Data(contentsOf: file) }
        for type in [UTType.png, .tiff, .jpeg, .heic] {
            if let data = board.data(forType: NSPasteboard.PasteboardType(type.identifier)) { return data }
        }
        return (board.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first?.tiffRepresentation
        #else
        let board = UIPasteboard.general
        for type in [UTType.png, .jpeg, .heic] {
            if let data = board.data(forPasteboardType: type.identifier) { return data }
        }
        return board.image?.jpegData(compressionQuality: 0.95)
        #endif
    }

    #if os(macOS)
    /// A copied file that is a picture.
    private static func imageFile(_ board: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        return (board.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }
    #endif
}

/// The photo's verbs as one menu opened where it is pressed: Choose Photo… opens the file
/// panel on the Mac and Photos on the phone, Paste Photo takes the pasteboard's picture, and
/// both pass through Move and Scale first. Remove Photo takes it away. All land with Save.
struct PhotoMenu<Label: View>: View {
    let has: Bool
    let shape: PhotoShape
    @Binding var picked: Data?
    @Binding var removing: Bool
    @ViewBuilder let label: () -> Label
    @State private var choosing = false
    @State private var canPaste = false
    @State private var moving: PhotoInHand?
    #if os(iOS)
    @State private var item: PhotosPickerItem?
    #endif

    var body: some View {
        Menu {
            Button("Choose Photo…") { Measure.used("choose_photo", .menuItem); choosing = true }
            Button("Paste Photo") { Measure.used("paste_photo", .menuItem); paste() }
                .disabled(!canPaste)
            if has {
                Divider()
                Button("Remove Photo", role: .destructive) { Measure.used("remove_photo", .menuItem); picked = nil; removing = true }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .lbButtonStyle()
        .menuIndicator(.hidden)
        .accessibilityLabel("Photo")
        .onAppear { canPaste = PhotoPasteboard.holdsImage }
        #if os(macOS)
        .onHover { inside in if inside { canPaste = PhotoPasteboard.holdsImage } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in canPaste = PhotoPasteboard.holdsImage }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let open = url.startAccessingSecurityScopedResource()
            defer { if open { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { moving = PhotoInHand(data: data) }
        }
        .measured("move_and_scale", .sheet, when: moving != nil)
        .sheet(item: $moving) { hand in
            PhotoMoveScaleView(data: hand.data, shape: shape, onChoose: keep, onCancel: { moving = nil })
                .lbKeyboardFocusEffects()
        }
        #else
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in canPaste = PhotoPasteboard.holdsImage }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in canPaste = PhotoPasteboard.holdsImage }
        .photosPicker(isPresented: $choosing, selection: $item, matching: .images)
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            item = nil
            Task {
                if let data = try? await chosen.loadTransferable(type: Data.self) { moving = PhotoInHand(data: data) }
            }
        }
        .measured("move_and_scale", .sheet, when: moving != nil)
        .fullScreenCover(item: $moving) { hand in
            PhotoMoveScaleView(data: hand.data, shape: shape, onChoose: keep, onCancel: { moving = nil })
        }
        #endif
    }

    private func paste() {
        guard let data = PhotoPasteboard.imageData() else { canPaste = false; return }
        moving = PhotoInHand(data: data)
    }

    private func keep(_ square: Data) {
        picked = square
        removing = false
        moving = nil
    }
}

/// Move and Scale: the photo behind the shape it will sit in, dragged and zoomed until the
/// shape holds the part wanted. Choose hands back only that square, at the folder's size;
/// Cancel leaves the editor's photo as it was.
struct PhotoMoveScaleView: View {
    let data: Data
    let shape: PhotoShape
    let onChoose: (Data) -> Void
    let onCancel: () -> Void

    @State private var photo: Loaded?
    /// The photo's place, in units of the hole's side, so a resized screen keeps it.
    @State private var crop = LBPhotoCrop(image: CGSize(width: 1, height: 1))
    @State private var dragged: CGSize = .zero
    @State private var pinched: CGFloat = 1

    private struct Loaded {
        let source: CGImageSource
        let image: CGImage
    }

    #if os(macOS)
    private static let well = CGSize(width: 372, height: 300)
    private static let hole: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            Text("Move and Scale")
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Text("Drag the photo to place it. Zoom with the slider or a pinch.")
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            stage(hole: Self.hole)
                .frame(width: Self.well.width, height: Self.well.height)
                .clipShape(RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { crop.zoom }, set: { crop = crop.zoomed(to: $0) }), in: 1...LBPhotoCrop.maxZoom)
                    .tint(LBColor.brand.color)
                    .accessibilityLabel("Zoom")
                Image(systemName: "circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(LBColor.textTertiary.color)
                    .accessibilityHidden(true)
            }
            HStack(spacing: LBSpacing.s2) {
                Spacer(minLength: 0)
                Button(action: { Measure.used("cancel"); onCancel() }) {
                    Text("Cancel")
                        .lbText(.label)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize()
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .lbButtonStyle()
                .keyboardShortcut(.cancelAction)
                Button(action: { Measure.used("choose"); choose() }) {
                    Text("Choose")
                        .lbText(.label)
                        .foregroundStyle(LBColor.onBrand.color)
                        .fixedSize()
                        .padding(.horizontal, LBSpacing.s3)
                        .frame(minHeight: 32)
                        .background(LBColor.brand.color, in: Capsule())
                        .contentShape(Capsule())
                }
                .lbButtonStyle(.capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(photo == nil)
            }
        }
        .padding(LBSpacing.s6)
        .frame(width: Self.well.width + 2 * LBSpacing.s6)
        .background(LBColor.canvas.color)
        .task { load() }
    }
    #else
    /// The window's own top inset: a cover raised from a sheet reports none, which put the
    /// title under the clock.
    private static var clockClearance: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        VStack(spacing: LBSpacing.s4) {
            Text("Move and Scale")
                .lbText(.headline)
                .foregroundStyle(Color.white)
                .padding(.top, LBSpacing.s3 + Self.clockClearance)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Text("Pinch to zoom, drag to move.")
                .lbText(.footnote)
                .foregroundStyle(Color.white.opacity(0.75))
            HStack {
                Button(action: { Measure.used("cancel"); onCancel() }) { barWord("Cancel") }
                    .lbButtonStyle()
                Spacer(minLength: LBSpacing.s4)
                Button(action: { Measure.used("choose"); choose() }) { barWord("Choose") }
                    .lbButtonStyle()
                    .disabled(photo == nil)
            }
            .padding(.horizontal, LBSpacing.s4)
        }
        .padding(.bottom, LBSpacing.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        // Behind the words, so the stage runs edge to edge while the title keeps clear of the clock.
        .background {
            GeometryReader { space in
                stage(hole: max(1, min(space.size.width, space.size.height) - 2 * LBSpacing.s4))
            }
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { load() }
    }

    private func barWord(_ word: String) -> some View {
        Text(word)
            .lbText(.body)
            .foregroundStyle(Color.white)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
    #endif

    /// The photo at its place on black, everything outside the hole dimmed, the hole outlined.
    private func stage(hole: CGFloat) -> some View {
        Color.black
            .overlay {
                if let photo {
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: crop.shown.width * hole, height: crop.shown.height * hole)
                        .offset(x: crop.offset.width * hole, y: crop.offset.height * hole)
                }
            }
            .overlay {
                PhotoHoleMask(side: hole, shape: shape)
                    .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
            }
            .overlay {
                shape.outline(side: hole)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    .frame(width: hole, height: hole)
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { withAnimation(.snappy) { crop = crop.reset } }
            .gesture(drag(hole: hole).simultaneously(with: pinch))
            .accessibilityElement()
            .accessibilityLabel("Photo")
            .accessibilityValue("\(Int((crop.zoom * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: crop = crop.zoomed(to: crop.zoom + 0.5)
                case .decrement: crop = crop.zoomed(to: crop.zoom - 0.5)
                @unknown default: break
                }
            }
    }

    /// Each step of a drag moves the photo by what the finger moved since the last, so a drag
    /// past an edge picks up at once on the way back.
    private func drag(hole: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let step = CGSize(width: value.translation.width - dragged.width, height: value.translation.height - dragged.height)
                dragged = value.translation
                crop = crop.moved(by: CGSize(width: step.width / hole, height: step.height / hole))
            }
            .onEnded { _ in dragged = .zero }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                crop = crop.zoomed(to: crop.zoom * value.magnification / pinched)
                pinched = value.magnification
            }
            .onEnded { _ in pinched = 1 }
    }

    /// Reads the photo once, upright and no larger than the screen can use at the most zoom.
    private func load() {
        guard photo == nil else { return }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let size = LBPhotoCrop.size(of: source),
              let image = LBPhotoCrop.upright(source, longest: 2400) else { return onCancel() }
        crop = LBPhotoCrop(image: size)
        photo = Loaded(source: source, image: image)
    }

    private func choose() {
        guard let photo, let square = crop.render(photo.source, pixels: VaultImages.side), let png = Self.png(square) else { return onCancel() }
        onChoose(png)
    }

    /// Lossless, so the folder's JPEG is the photo's only compression.
    private static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, image, nil)
        return CGImageDestinationFinalize(sink) ? out as Data : nil
    }
}

/// The dim around the hole: the whole frame with the hole cut out, filled even-odd.
private struct PhotoHoleMask: Shape {
    let side: CGFloat
    let shape: PhotoShape

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let hole = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        path.addPath(shape.outline(side: side).path(in: hole))
        return path
    }
}
