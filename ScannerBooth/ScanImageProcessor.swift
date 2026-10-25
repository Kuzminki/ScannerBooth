import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

enum ScanFilter: String, CaseIterable, Identifiable, Sendable {
    case doc = "Doc"
    case gray = "Gray"
    case blackAndWhite = "N&B"

    var id: String { rawValue }

    var previewDescription: String {
        switch self {
        case .doc: return "Couleur · fond éclairci · perspective corrigée"
        case .gray: return "Niveaux de gris · fond éclairci · perspective corrigée"
        case .blackAndWhite: return "Noir et blanc · contraste renforcé"
        }
    }
}

enum ScanProcessingFailure: LocalizedError {
    case unreadableImage
    case noPerspectiveCorrection
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "Cette image n’a pas pu être ouverte."
        case .noPerspectiveCorrection: return "Le cadrage ne peut pas être redressé. Ajustez les quatre coins."
        case .processingFailed: return "Le traitement de l’image a échoué."
        }
    }
}

enum ScanImageProcessor {
    private static let context = CIContext()

    static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScanProcessingFailure.unreadableImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let oriented = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientationValue))
        return try renderNormalized(oriented)
    }

    static func detectDocument(in image: CGImage) throws -> DocumentQuad? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 20
        request.minimumConfidence = 0.35
        request.minimumSize = 0.15
        request.quadratureTolerance = 45
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        let candidates = (request.results ?? []).compactMap { observation -> (DocumentQuad, CGFloat)? in
            let quad = DocumentQuad(
                topLeft: imagePoint(fromVision: observation.topLeft),
                topRight: imagePoint(fromVision: observation.topRight),
                bottomRight: imagePoint(fromVision: observation.bottomRight),
                bottomLeft: imagePoint(fromVision: observation.bottomLeft)
            )
            guard quad.isValid else { return nil }
            return (quad, CGFloat(observation.confidence) * sqrt(quad.area))
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    static func process(
        _ image: CGImage,
        using quad: DocumentQuad,
        filter: ScanFilter = .doc
    ) throws -> CGImage {
        guard quad.isValid else { throw ScanProcessingFailure.noPerspectiveCorrection }
        let input = CIImage(cgImage: image)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        func ciPoint(_ point: NormalizedPoint) -> CGPoint {
            CGPoint(x: point.x * width, y: (1 - point.y) * height)
        }

        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = input
        correction.topLeft = ciPoint(quad.topLeft)
        correction.topRight = ciPoint(quad.topRight)
        correction.bottomLeft = ciPoint(quad.bottomLeft)
        correction.bottomRight = ciPoint(quad.bottomRight)
        guard let corrected = correction.outputImage else {
            throw ScanProcessingFailure.noPerspectiveCorrection
        }

        let output: CIImage
        switch filter {
        case .doc:
            let controls = CIFilter.colorControls()
            controls.inputImage = corrected
            controls.contrast = 1.10
            controls.saturation = 1.02
            controls.brightness = 0
            guard let contrasted = controls.outputImage else { throw ScanProcessingFailure.processingFailed }
            output = try correctPaperWhite(in: contrasted, preserveColor: true)

        case .gray:
            let grayscale = try grayscaleImage(corrected, contrast: 1.10)
            output = try correctPaperWhite(in: grayscale, preserveColor: false)

        case .blackAndWhite:
            let grayscale = try grayscaleImage(corrected, contrast: 1.10)
            let paperCorrected = try correctPaperWhite(in: grayscale, preserveColor: false)
            guard let threshold = CIFilter(name: "CIColorThresholdOtsu") else {
                throw ScanProcessingFailure.processingFailed
            }
            threshold.setValue(paperCorrected, forKey: kCIInputImageKey)
            guard let binary = threshold.outputImage else { throw ScanProcessingFailure.processingFailed }
            output = binary
        }

        return try renderNormalized(output)
    }

    private static func grayscaleImage(_ image: CIImage, contrast: Float) throws -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.contrast = contrast
        controls.saturation = 0
        controls.brightness = 0
        guard let grayscale = controls.outputImage else { throw ScanProcessingFailure.processingFailed }
        return grayscale
    }

    private static func correctPaperWhite(in image: CIImage, preserveColor: Bool) throws -> CIImage {
        // The four corners are usually paper. Their average provides a restrained
        // per-channel white point correction without removing document color.
        let whitePoint = try averageCornerColor(of: image)
        let redGain: CGFloat
        let greenGain: CGFloat
        let blueGain: CGFloat
        if preserveColor {
            redGain = min(1.20, max(0.92, 1 / max(whitePoint.0, 0.82)))
            greenGain = min(1.20, max(0.92, 1 / max(whitePoint.1, 0.82)))
            blueGain = min(1.20, max(0.92, 1 / max(whitePoint.2, 0.82)))
        } else {
            let luminance = 0.2126 * whitePoint.0 + 0.7152 * whitePoint.1 + 0.0722 * whitePoint.2
            let gain = min(1.20, max(0.92, 1 / max(luminance, 0.82)))
            redGain = gain
            greenGain = gain
            blueGain = gain
        }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: redGain, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: greenGain, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: blueGain, w: 0)
        guard let gained = matrix.outputImage else { throw ScanProcessingFailure.processingFailed }

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = gained
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let output = clamp.outputImage else { throw ScanProcessingFailure.processingFailed }
        return output
    }

    private static func averageCornerColor(of image: CIImage) throws -> (CGFloat, CGFloat, CGFloat) {
        let extent = image.extent.integral
        let patchWidth = max(2, extent.width * 0.035)
        let patchHeight = max(2, extent.height * 0.035)
        let patches = [
            CGRect(x: extent.minX, y: extent.minY, width: patchWidth, height: patchHeight),
            CGRect(x: extent.maxX - patchWidth, y: extent.minY, width: patchWidth, height: patchHeight),
            CGRect(x: extent.minX, y: extent.maxY - patchHeight, width: patchWidth, height: patchHeight),
            CGRect(x: extent.maxX - patchWidth, y: extent.maxY - patchHeight, width: patchWidth, height: patchHeight)
        ]

        var totals = [CGFloat](repeating: 0, count: 3)
        for patch in patches {
            let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: patch)])
            var rgba = [UInt8](repeating: 0, count: 4)
            rgba.withUnsafeMutableBytes { buffer in
                guard let address = buffer.baseAddress else { return }
                context.render(
                    average,
                    toBitmap: address,
                    rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                )
            }
            totals[0] += CGFloat(rgba[0]) / 255
            totals[1] += CGFloat(rgba[1]) / 255
            totals[2] += CGFloat(rgba[2]) / 255
        }
        return (totals[0] / 4, totals[1] / 4, totals[2] / 4)
    }

    private static func renderNormalized(_ image: CIImage) throws -> CGImage {
        let extent = image.extent.integral
        guard !extent.isNull, extent.width > 0, extent.height > 0 else {
            throw ScanProcessingFailure.processingFailed
        }
        let normalized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        guard let output = context.createCGImage(
            normalized,
            from: CGRect(origin: .zero, size: extent.size),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else {
            throw ScanProcessingFailure.processingFailed
        }
        return output
    }
}
