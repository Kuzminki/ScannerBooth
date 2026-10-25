import AppKit
import CoreGraphics
import PDFKit
import XCTest
@testable import ScannerBooth

final class ScannerBoothTests: XCTestCase {
    func testVisionCoordinatesConvertToTopLeftImageCoordinates() {
        XCTAssertEqual(imagePoint(fromVision: CGPoint(x: 0.2, y: 0.8)), NormalizedPoint(x: 0.2, y: 0.2))
    }

    func testQuadRejectsCrossedCorners() {
        let crossed = DocumentQuad(
            topLeft: .init(x: 0.1, y: 0.1),
            topRight: .init(x: 0.9, y: 0.9),
            bottomRight: .init(x: 0.9, y: 0.1),
            bottomLeft: .init(x: 0.1, y: 0.9)
        )
        XCTAssertFalse(crossed.isValid)
        XCTAssertTrue(DocumentQuad.imageBounds.isValid)
    }

    func testWhitePointCorrectionBrightensPaperAndKeepsColor() throws {
        let source = try makeTestImage(width: 400, height: 500)
        let result = try ScanImageProcessor.process(source, using: .imageBounds)
        let bitmap = NSBitmapImageRep(cgImage: result)
        let paper = try XCTUnwrap(bitmap.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
        let coloredMark = try XCTUnwrap(bitmap.colorAt(x: 200, y: 250)?.usingColorSpace(.deviceRGB))

        XCTAssertGreaterThan(paper.redComponent, 0.97)
        XCTAssertGreaterThan(paper.greenComponent, 0.97)
        XCTAssertGreaterThan(paper.blueComponent, 0.97)
        XCTAssertGreaterThan(coloredMark.redComponent, coloredMark.greenComponent * 1.8)
    }

    func testPDFExportCreatesOnePageWithImageAspectRatio() throws {
        let image = try makeTestImage(width: 400, height: 500)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerBooth-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: destination) }

        try PDFExporter.write(image: image, to: destination)
        let document = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width / page.bounds(for: .mediaBox).height, 0.8, accuracy: 0.01)
    }

    func testUnreadableImageReportsAnError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerBooth-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)

        XCTAssertThrowsError(try ScanImageProcessor.loadImage(at: url))
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        var data = Data(count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let image = data.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let address = buffer.baseAddress else { return nil }
            guard let context = CGContext(
                data: address,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }
            context.setFillColor(CGColor(srgbRed: 0.90, green: 0.90, blue: 0.90, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(srgbRed: 0.82, green: 0.20, blue: 0.12, alpha: 1))
            context.fill(CGRect(x: 160, y: 200, width: 80, height: 100))
            return context.makeImage()
        }
        return try XCTUnwrap(image)
    }
}
