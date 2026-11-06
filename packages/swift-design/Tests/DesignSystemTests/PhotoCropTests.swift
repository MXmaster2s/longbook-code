import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DesignSystem

final class PhotoCropTests: XCTestCase {
    func testAtTheStartAWidePhotoFillsTheHoleCentred() {
        let crop = LBPhotoCrop(image: CGSize(width: 4000, height: 3000), hole: 240)
        XCTAssertEqual(crop.zoom, 1)
        XCTAssertEqual(crop.shown.height, 240, accuracy: 0.001)
        XCTAssertEqual(crop.rect, CGRect(x: 500, y: 0, width: 3000, height: 3000))
    }

    func testZoomStaysBetweenFillingTheHoleAndFourTimes() {
        let crop = LBPhotoCrop(image: CGSize(width: 1000, height: 1000), hole: 200)
        XCTAssertEqual(crop.zoomed(to: 0.3).zoom, 1)
        XCTAssertEqual(crop.zoomed(to: 9).zoom, LBPhotoCrop.maxZoom)
        XCTAssertEqual(crop.zoomed(to: 2).rect, CGRect(x: 250, y: 250, width: 500, height: 500))
        XCTAssertEqual(crop.zoomed(to: 4).rect.width, 250)
    }

    func testThePhotoNeverMovesSoTheHoleShowsEmptySpace() {
        let crop = LBPhotoCrop(image: CGSize(width: 4000, height: 3000), hole: 240)
        // At zoom 1 the tall way has no room, the wide way 40 points each side.
        let far = crop.moved(by: CGSize(width: 1000, height: -1000))
        XCTAssertEqual(far.offset, CGSize(width: 40, height: 0))
        XCTAssertEqual(far.rect, CGRect(x: 0, y: 0, width: 3000, height: 3000))
        XCTAssertEqual(crop.moved(by: CGSize(width: -1000, height: 0)).rect.maxX, 4000)
    }

    func testMovingThePhotoDownShowsItsTop() {
        let crop = LBPhotoCrop(image: CGSize(width: 1000, height: 2000), hole: 100).zoomed(to: 2)
        let rect = crop.moved(by: CGSize(width: 0, height: 10_000)).rect
        XCTAssertEqual(rect, CGRect(x: 250, y: 0, width: 500, height: 500))
    }

    func testZoomingOutPullsTheOffsetBackInsideTheEdges() {
        let crop = LBPhotoCrop(image: CGSize(width: 1000, height: 1000), hole: 100).zoomed(to: 4).moved(by: CGSize(width: 150, height: 150))
        XCTAssertEqual(crop.offset, CGSize(width: 150, height: 150))
        let back = crop.zoomed(to: 2)
        XCTAssertEqual(back.offset, CGSize(width: 50, height: 50))
        XCTAssertEqual(back.rect, CGRect(x: 0, y: 0, width: 500, height: 500))
        XCTAssertEqual(back.reset, LBPhotoCrop(image: CGSize(width: 1000, height: 1000), hole: 100))
    }

    func testTheRectDoesNotDependOnTheHolesSize() {
        let small = LBPhotoCrop(image: CGSize(width: 3000, height: 2000), hole: 1).zoomed(to: 1.5).moved(by: CGSize(width: 0.2, height: -0.1))
        let large = LBPhotoCrop(image: CGSize(width: 3000, height: 2000), hole: 300).zoomed(to: 1.5).moved(by: CGSize(width: 60, height: -30))
        XCTAssertEqual(small.rect, large.rect)
    }

    func testTheRenderedSquareIsThePartTheHoleShowsAtThePixelsAsked() throws {
        // Red on top, blue below; moved down, the hole shows the red top.
        let source = try photo(width: 100, height: 200)
        XCTAssertEqual(LBPhotoCrop.size(of: source), CGSize(width: 100, height: 200))
        let top = LBPhotoCrop(image: CGSize(width: 100, height: 200), hole: 1).moved(by: CGSize(width: 0, height: 1))
        let made = try XCTUnwrap(top.render(source, pixels: 40))
        XCTAssertEqual([made.width, made.height], [40, 40])
        XCTAssertGreaterThan(try red(of: made), 0.9)
        let bottom = top.moved(by: CGSize(width: 0, height: -2))
        XCTAssertLessThan(try red(of: XCTUnwrap(bottom.render(source, pixels: 40))), 0.1)
    }

    func testASmallPhotoIsNotBlownUp() throws {
        let made = try XCTUnwrap(LBPhotoCrop(image: CGSize(width: 100, height: 200)).render(photo(width: 100, height: 200), pixels: 512))
        XCTAssertEqual([made.width, made.height], [100, 100])
    }

    private func photo(width: Int, height: Int) throws -> CGImageSource {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // A context's origin is its bottom-left, so the top half is the upper rectangle.
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        let data = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(sink, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return try XCTUnwrap(CGImageSourceCreateWithData(data, nil))
    }

    /// The red share of the picture's middle pixel.
    private func red(of image: CGImage) throws -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGFloat(pixel[0]) / 255
    }
}
