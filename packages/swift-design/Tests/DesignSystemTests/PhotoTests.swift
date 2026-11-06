import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DesignSystem

final class PhotoTests: XCTestCase {
    private func source(width: Int, height: Int) throws -> CGImageSource {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(sink, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return try XCTUnwrap(CGImageSourceCreateWithData(data, nil))
    }

    func testALargeSquareComesToTheExactPixelsOfItsPlace() throws {
        let made = try XCTUnwrap(LBPhoto.square(source(width: 512, height: 512), pixels: 80))
        XCTAssertEqual([made.width, made.height], [80, 80])
    }

    func testAWidePictureKeepsItsMiddleSquareAtFullPixels() throws {
        let made = try XCTUnwrap(LBPhoto.square(source(width: 1024, height: 512), pixels: 80))
        XCTAssertEqual([made.width, made.height], [80, 80])
    }

    func testAPictureSmallerThanItsPlaceIsNotBlownUp() throws {
        let made = try XCTUnwrap(LBPhoto.square(source(width: 40, height: 60), pixels: 80))
        XCTAssertEqual([made.width, made.height], [40, 40])
    }
}
