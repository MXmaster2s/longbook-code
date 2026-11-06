import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// A picture made for the place it shows: its middle square, resampled by ImageIO to exactly the
/// pixels that place holds. A large picture squeezed by the screen at draw time drops pixels and
/// its edges turn hard; this one keeps them soft. Made once per file, size and change.
public enum LBPhoto {
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 400
        return cache
    }()

    /// A view for a file in the folder, sized `side` points; nil when it will not open.
    public static func image(file: URL?, side: CGFloat, scale: CGFloat) -> Image? {
        guard let file else { return nil }
        let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(file.path)|\(changed)|\(pixels(side, scale))" as NSString
        if let made = cache.object(forKey: key) { return view(made, side: side, scale: scale) }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil), let made = square(source, pixels: pixels(side, scale)) else { return nil }
        cache.setObject(made, forKey: key)
        return view(made, side: side, scale: scale)
    }

    /// A view for bytes just picked, not yet in the folder.
    public static func image(data: Data, side: CGFloat, scale: CGFloat) -> Image? {
        let key = "\(fingerprint(data))|\(pixels(side, scale))" as NSString
        if let made = cache.object(forKey: key) { return view(made, side: side, scale: scale) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let made = square(source, pixels: pixels(side, scale)) else { return nil }
        cache.setObject(made, forKey: key)
        return view(made, side: side, scale: scale)
    }

    /// The picture's middle square at these pixels, or at its own when it holds fewer.
    public static func square(_ source: CGImageSource, pixels: Int) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat, let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        // The long side is what ImageIO limits, so the short side lands on the pixels wanted.
        let long = ceil(CGFloat(pixels) * max(width, height) / min(width, height))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: long, kCGImageSourceShouldCacheImmediately: true]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(scaled.width, scaled.height)
        return scaled.cropping(to: CGRect(x: (scaled.width - side) / 2, y: (scaled.height - side) / 2, width: side, height: side))
    }

    /// Enough of the bytes to tell two pictures of one size apart, without reading them all each draw.
    private static func fingerprint(_ data: Data) -> String {
        var hasher = Hasher()
        hasher.combine(data.count)
        for at in stride(from: data.startIndex, to: data.endIndex, by: max(1, data.count / 512)) { hasher.combine(data[at]) }
        return String(hasher.finalize())
    }

    private static func pixels(_ side: CGFloat, _ scale: CGFloat) -> Int { max(1, Int(ceil(side * max(scale, 1)))) }

    /// Drawn pixel for pixel at its size. A photo smaller than its place is smoothed up.
    private static func view(_ made: CGImage, side: CGFloat, scale: CGFloat) -> Image {
        Image(decorative: made, scale: CGFloat(made.width) / max(side, 1)).interpolation(.high)
    }
}
