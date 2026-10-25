import CoreGraphics
import Foundation

enum PDFExporter {
    static func makePDFData(image: CGImage) throws -> Data {
        let longestEdge: CGFloat = 842
        let scale = longestEdge / CGFloat(max(image.width, image.height))
        let pageSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
        context.interpolationQuality = .high
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    static func write(image: CGImage, to url: URL) throws {
        try makePDFData(image: image).write(to: url, options: .atomic)
    }
}
