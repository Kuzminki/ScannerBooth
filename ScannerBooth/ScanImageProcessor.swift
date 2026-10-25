import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import OSLog
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
    private static let paperWhiteningKernel = CIColorKernel(source: """
    kernel vec4 whitenPaper(__sample pixel, float strength) {
        float luminance = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722));
        float level = clamp((luminance - 0.48) / 0.42, 0.0, 1.0);
        float mask = level * level * (3.0 - 2.0 * level);
        float lift = strength * mask;
        vec3 whitened = pixel.rgb + (vec3(1.0) - pixel.rgb) * lift;
        return vec4(whitened, pixel.a);
    }
    """)
    private static let detectionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.guilhem.ScannerBooth",
        category: "DocumentDetection"
    )

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
        request.maximumObservations = 100
        request.minimumConfidence = 0.15
        request.minimumSize = 0.08
        request.quadratureTolerance = 45
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        let observations = request.results ?? []
        let minimumPageArea: CGFloat = 0.07
        let maximumPageArea: CGFloat = 0.90
        var largestObservedArea: CGFloat = 0
        let candidates = observations.compactMap { observation -> (quad: DocumentQuad, confidence: CGFloat, area: CGFloat, score: CGFloat)? in
            let quad = DocumentQuad(
                topLeft: imagePoint(fromVision: observation.topLeft),
                topRight: imagePoint(fromVision: observation.topRight),
                bottomRight: imagePoint(fromVision: observation.bottomRight),
                bottomLeft: imagePoint(fromVision: observation.bottomLeft)
            )
            let area = quad.area
            guard quad.isValid else { return nil }
            largestObservedArea = max(largestObservedArea, area)
            guard area >= minimumPageArea, area <= maximumPageArea else { return nil }

            func pixelDistance(_ first: NormalizedPoint, _ second: NormalizedPoint) -> CGFloat {
                hypot(
                    (first.x - second.x) * CGFloat(image.width),
                    (first.y - second.y) * CGFloat(image.height)
                )
            }

            let width = (pixelDistance(quad.topLeft, quad.topRight) + pixelDistance(quad.bottomLeft, quad.bottomRight)) / 2
            let height = (pixelDistance(quad.topLeft, quad.bottomLeft) + pixelDistance(quad.topRight, quad.bottomRight)) / 2
            let aspectRatio = min(width, height) / max(width, height)
            guard aspectRatio >= 0.25 else { return nil }

            let centerX = quad.points.map(\.x).reduce(0, +) / 4
            let centerY = quad.points.map(\.y).reduce(0, +) / 4
            let centerOffset = hypot(centerX - 0.5, centerY - 0.5)
            let centrality = max(0.75, 1 - centerOffset * 0.35)
            let confidence = CGFloat(observation.confidence)
            let confidenceWeight = 0.70 + confidence * 0.30
            let score = area * confidenceWeight * centrality
            return (quad, confidence, area, score)
        }

        detectionLogger.info(
            "Vision rectangle results=\(observations.count, privacy: .public), plausible page candidates=\(candidates.count, privacy: .public), largest rectangle areaFraction=\(Double(largestObservedArea), privacy: .public)"
        )
        guard let selected = candidates.max(by: { $0.score < $1.score }) else {
            detectionLogger.warning("No rectangle met the minimum page size and shape constraints; using manual crop")
            return nil
        }
        detectionLogger.info(
            "Selected document candidate; areaFraction=\(Double(selected.area), privacy: .public), confidence=\(Double(selected.confidence), privacy: .public)"
        )
        return selected.quad
    }

    static func process(
        _ image: CGImage,
        using quad: DocumentQuad,
        filter: ScanFilter = .doc,
        sharpness: Float = 0.5,
        paperWhitening: Float = 0.5
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
            let paperCorrected = try correctPaperWhite(
                in: contrasted,
                preserveColor: true,
                whitening: paperWhitening
            )
            output = try sharpen(paperCorrected, amount: sharpness)

        case .gray:
            let grayscale = try grayscaleImage(corrected, contrast: 1.10)
            let paperCorrected = try correctPaperWhite(
                in: grayscale,
                preserveColor: false,
                whitening: paperWhitening
            )
            output = try sharpen(paperCorrected, amount: sharpness)

        case .blackAndWhite:
            let grayscale = try grayscaleImage(corrected, contrast: 1.10)
            let paperCorrected = try correctPaperWhite(
                in: grayscale,
                preserveColor: false,
                whitening: paperWhitening
            )
            let sharpened = try sharpen(paperCorrected, amount: sharpness)
            guard let threshold = CIFilter(name: "CIColorThresholdOtsu") else {
                throw ScanProcessingFailure.processingFailed
            }
            threshold.setValue(sharpened, forKey: kCIInputImageKey)
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

    private static func correctPaperWhite(
        in image: CIImage,
        preserveColor: Bool,
        whitening: Float
    ) throws -> CIImage {
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

        let strength = min(1, max(0, whitening))
        guard strength > 0 else { return output }
        guard let paperWhiteningKernel else { throw ScanProcessingFailure.processingFailed }
        guard let whitened = paperWhiteningKernel.apply(
            extent: output.extent,
            arguments: [output, NSNumber(value: strength)]
        ) else {
            throw ScanProcessingFailure.processingFailed
        }
        return whitened
    }

    private static func sharpen(_ image: CIImage, amount: Float) throws -> CIImage {
        let strength = min(2, max(0, amount))
        guard strength > 0 else { return image }
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = strength
        guard let output = filter.outputImage else { throw ScanProcessingFailure.processingFailed }
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
