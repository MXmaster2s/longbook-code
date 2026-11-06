import CoreGraphics
import Foundation
import ImageIO

/// A photo behind a square hole while it is moved and scaled, and the part the hole shows in
/// its own pixels. At zoom 1 its short side fills the hole; it never moves so far that the
/// hole shows past its edge. Offsets are in hole units, y downward.
public struct LBPhotoCrop: Equatable, Sendable {
    public static let maxZoom: CGFloat = 4

    /// The photo's pixels, upright.
    public let image: CGSize
    /// The hole's side, in the units the offset is in.
    public let hole: CGFloat
    public private(set) var zoom: CGFloat = 1
    /// Where the photo's centre sits from the hole's.
    public private(set) var offset: CGSize = .zero

    public init(image: CGSize, hole: CGFloat = 1, zoom: CGFloat = 1, offset: CGSize = .zero) {
        self.image = CGSize(width: max(image.width.rounded(), 1), height: max(image.height.rounded(), 1))
        self.hole = hole > 0 && hole.isFinite ? hole : 1
        place(zoom: zoom, offset: offset)
    }

    /// Hole units for one photo pixel.
    public var scale: CGFloat { hole / min(image.width, image.height) * zoom }

    /// The photo's drawn size, in hole units.
    public var shown: CGSize { CGSize(width: image.width * scale, height: image.height * scale) }

    /// The same photo moved by this much, stopping at its edges.
    public func moved(by delta: CGSize) -> LBPhotoCrop {
        var next = self
        next.place(zoom: zoom, offset: CGSize(width: offset.width + delta.width, height: offset.height + delta.height))
        return next
    }

    /// The same photo at another zoom, about the hole's centre: the point there stays there
    /// while the edges allow it.
    public func zoomed(to wanted: CGFloat) -> LBPhotoCrop {
        let kept = Self.limit(wanted) / zoom
        var next = self
        next.place(zoom: wanted, offset: CGSize(width: offset.width * kept, height: offset.height * kept))
        return next
    }

    /// The starting place: the photo filling the hole, centred.
    public var reset: LBPhotoCrop { LBPhotoCrop(image: image, hole: hole) }

    /// The square the hole shows, in whole photo pixels from the top-left, inside the photo.
    public var rect: CGRect {
        let side = max(1, min((hole / scale).rounded(), min(image.width, image.height)))
        let midX = image.width / 2 - offset.width / scale
        let midY = image.height / 2 - offset.height / scale
        let x = min(max((midX - side / 2).rounded(), 0), image.width - side)
        let y = min(max((midY - side / 2).rounded(), 0), image.height - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private mutating func place(zoom wanted: CGFloat, offset wantedOffset: CGSize) {
        zoom = Self.limit(wanted)
        let reach = CGSize(width: max(0, (shown.width - hole) / 2), height: max(0, (shown.height - hole) / 2))
        offset = CGSize(width: Self.clamp(wantedOffset.width, reach.width), height: Self.clamp(wantedOffset.height, reach.height))
    }

    private static func limit(_ zoom: CGFloat) -> CGFloat { zoom.isFinite ? min(max(zoom, 1), maxZoom) : 1 }

    private static func clamp(_ value: CGFloat, _ reach: CGFloat) -> CGFloat { value.isFinite ? min(max(value, -reach), reach) : 0 }
}

public extension LBPhotoCrop {
    /// The photo's upright pixel size, its orientation read; nil when the bytes are not a photo.
    static func size(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat, let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        // Orientations 5 to 8 turn the photo a quarter, so its sides trade places.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// The upright photo at most `longest` pixels on its long side, for drawing behind the hole.
    static func upright(_ source: CGImageSource, longest: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, longest), kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The square the hole shows at `pixels` a side, or at its own when it holds fewer. The
    /// photo is read only as large as that square needs.
    func render(_ source: CGImageSource, pixels: Int) -> CGImage? {
        let crop = rect
        let shrink = min(1, CGFloat(max(1, pixels)) / crop.width)
        guard let photo = Self.upright(source, longest: Int(ceil(max(image.width, image.height) * shrink))) else { return nil }
        let read = CGFloat(photo.width) / image.width
        let bounds = CGRect(x: 0, y: 0, width: photo.width, height: photo.height)
        let part = CGRect(x: crop.minX * read, y: crop.minY * read, width: crop.width * read, height: crop.width * read)
            .integral.intersection(bounds)
        guard !part.isEmpty, let cut = photo.cropping(to: part) else { return nil }
        let side = min(max(1, pixels), cut.width, cut.height)
        if cut.width == side, cut.height == side { return cut }
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cut, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}
