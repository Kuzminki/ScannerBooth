import AppKit
import OSLog
import SwiftUI

struct ScannerEditorView: View {
    private static let pdfExportLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.guilhem.ScannerBooth",
        category: "PDFExport"
    )

    let photo: PhotoEntry
    let onBack: () -> Void

    @State private var sourceImage: CGImage?
    @State private var automaticQuad: DocumentQuad?
    @State private var quad: DocumentQuad = .imageBounds
    @State private var processedImage: CGImage?
    @State private var selectedFilter: ScanFilter = .doc
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var isDirty = false
    @State private var errorMessage: String?
    @State private var alertTitle = "ScannerBooth"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Photothèque", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Text(photo.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    Self.pdfExportLogger.info("PDF export button action received")
                    beginPDFExport()
                } label: {
                    Label("Enregistrer le PDF…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(processedImage == nil || isProcessing || isLoading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Détection et redressement du document…")
                Spacer()
            } else if let sourceImage {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Cadrage", systemImage: "crop.rotate")
                            .font(.headline)
                        Text(automaticQuad == nil
                             ? "Aucun document détecté automatiquement. Déplacez les quatre poignées pour cadrer la page."
                             : "Ajustez les quatre poignées si nécessaire, puis actualisez l’aperçu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        CropCanvas(image: sourceImage, quad: $quad) {
                            isDirty = true
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Aperçu du scan", systemImage: "doc.text.viewfinder")
                            .font(.headline)
                        Text(selectedFilter.previewDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .underPageBackgroundColor))
                            if let processedImage {
                                Image(nsImage: nsImage(for: processedImage))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(12)
                                if isDirty {
                                    Text("Mettez à jour l’aperçu après le cadrage")
                                        .font(.callout.weight(.medium))
                                        .padding(10)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                            } else {
                                ContentUnavailableView("Aucun aperçu", systemImage: "doc.viewfinder")
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Picker("Filtre", selection: $selectedFilter) {
                            ForEach(ScanFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(isLoading || isProcessing)
                    }
                }
                .padding(16)

                Divider()

                HStack {
                    Button("Réinitialiser le cadrage") {
                        quad = automaticQuad ?? .imageBounds
                        isDirty = true
                    }
                    .disabled(isProcessing)
                    Spacer()
                    if isProcessing {
                        ProgressView().controlSize(.small)
                        Text("Traitement…").foregroundStyle(.secondary)
                    }
                    Button {
                        updatePreview()
                    } label: {
                        Label("Actualiser l’aperçu", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isDirty || isProcessing)
                }
                .padding(14)
            } else {
                ContentUnavailableView {
                    Label("Impossible d’ouvrir la photo", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage ?? "Choisissez une autre image de la photothèque.")
                } actions: {
                    Button("Retour à la photothèque", action: onBack)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: photo.id) { await loadAndProcess() }
        .onChange(of: selectedFilter) { _, filter in
            guard !isLoading else { return }
            updatePreview(using: filter)
        }
        .onChange(of: isLoading) { _, _ in
            logExportAvailability(after: "loading state changed")
        }
        .onChange(of: isProcessing) { _, _ in
            logExportAvailability(after: "processing state changed")
        }
        .onChange(of: processedImage != nil) { _, _ in
            logExportAvailability(after: "preview availability changed")
        }
        .alert(alertTitle, isPresented: errorAlertPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Une erreur inconnue est survenue.")
        }
    }

    private func loadAndProcess() async {
        isLoading = true
        do {
            let url = photo.url
            let filter = selectedFilter
            let result = try await Task.detached(priority: .userInitiated) {
                let image = try ScanImageProcessor.loadImage(at: url)
                let detected = try ScanImageProcessor.detectDocument(in: image)
                let initialQuad = detected ?? .imageBounds
                let processed = try ScanImageProcessor.process(image, using: initialQuad, filter: filter)
                return (image, detected, processed)
            }.value
            sourceImage = result.0
            automaticQuad = result.1
            quad = result.1 ?? .imageBounds
            processedImage = result.2
            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func updatePreview(using filter: ScanFilter? = nil) {
        guard let sourceImage else { return }
        let source = sourceImage
        let selectedQuad = quad
        let filter = filter ?? selectedFilter
        isProcessing = true
        isDirty = true
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ScanImageProcessor.process(source, using: selectedQuad, filter: filter)
                }.value
                processedImage = output
                isDirty = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private func beginPDFExport() {
        Self.pdfExportLogger.info(
            "Preparing PDF save panel; isLoading=\(isLoading, privacy: .public), isProcessing=\(isProcessing, privacy: .public), hasPreview=\(processedImage != nil, privacy: .public)"
        )

        guard let sourceImage else {
            Self.pdfExportLogger.error("Cannot export PDF because the source image is unavailable")
            alertTitle = "Aucun aperçu à exporter"
            errorMessage = "La photo source n’est pas disponible pour préparer le PDF."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Enregistrer le scan en PDF"
        panel.prompt = "Enregistrer"
        panel.nameFieldStringValue = "\(photo.title)_scan.pdf"
        panel.allowedContentTypes = [.pdf]
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        Self.pdfExportLogger.info("NSSavePanel configured for PDF with an editable default filename")

        let selectedQuad = quad
        let chosenFilter = selectedFilter
        let save: (NSApplication.ModalResponse) -> Void = { response in
            Self.pdfExportLogger.info("NSSavePanel completed with response rawValue=\(response.rawValue, privacy: .public)")
            guard response == .OK else {
                Self.pdfExportLogger.info("PDF save panel cancelled")
                return
            }
            guard let destination = panel.url else {
                Self.pdfExportLogger.error("Save panel returned OK without a destination URL")
                alertTitle = "Échec de l’enregistrement"
                errorMessage = "Aucun emplacement de destination n’a été retourné par la fenêtre d’enregistrement."
                return
            }

            let destinationFolder = destination.deletingLastPathComponent()
            let didStartAccess = destinationFolder.startAccessingSecurityScopedResource()
            Self.pdfExportLogger.info(
                "PDF destination selected; directory security scope started=\(didStartAccess, privacy: .public)"
            )
            exportPDF(
                to: destination,
                from: sourceImage,
                using: selectedQuad,
                filter: chosenFilter,
                securityScopedDirectory: didStartAccess ? destinationFolder : nil
            )
        }

        let keyWindowAvailable = NSApp.keyWindow != nil
        let mainWindowAvailable = NSApp.mainWindow != nil
        let visibleWindowCount = NSApp.windows.filter { $0.isVisible }.count
        Self.pdfExportLogger.info(
            "Window state before presentation; keyWindow=\(keyWindowAvailable, privacy: .public), mainWindow=\(mainWindowAvailable, privacy: .public), visibleWindowCount=\(visibleWindowCount, privacy: .public)"
        )

        NSApp.activate(ignoringOtherApps: true)
        Self.pdfExportLogger.info("Presenting NSSavePanel with begin(completionHandler:)")
        panel.begin { response in
            save(response)
        }
        Self.pdfExportLogger.info("NSSavePanel.begin returned")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            Self.pdfExportLogger.info("NSSavePanel visibility after presentation delay; visible=\(panel.isVisible, privacy: .public)")
        }
    }

    private func exportPDF(
        to destination: URL,
        from sourceImage: CGImage,
        using quad: DocumentQuad,
        filter: ScanFilter,
        securityScopedDirectory: URL?
    ) {
        Self.pdfExportLogger.info("PDF processing and writing started; filter=\(filter.rawValue, privacy: .public)")
        isProcessing = true
        Task {
            defer { securityScopedDirectory?.stopAccessingSecurityScopedResource() }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let corrected = try ScanImageProcessor.process(sourceImage, using: quad, filter: filter)
                    try PDFExporter.write(image: corrected, to: destination)
                }.value
                Self.pdfExportLogger.info("PDF processing and writing completed successfully")
                alertTitle = "PDF enregistré"
                errorMessage = "Le document a été enregistré dans \(destination.lastPathComponent)."
            } catch {
                let nsError = error as NSError
                Self.pdfExportLogger.error(
                    "PDF processing or writing failed; domain=\(nsError.domain, privacy: .public), code=\(nsError.code, privacy: .public)"
                )
                alertTitle = "Échec de l’enregistrement"
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private func logExportAvailability(after event: String) {
        let isEnabled = processedImage != nil && !isProcessing && !isLoading
        Self.pdfExportLogger.info(
            "Export control state after \(event, privacy: .public); enabled=\(isEnabled, privacy: .public), hasPreview=\(processedImage != nil, privacy: .public), isLoading=\(isLoading, privacy: .public), isProcessing=\(isProcessing, privacy: .public)"
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct CropCanvas: View {
    let image: CGImage
    @Binding var quad: DocumentQuad
    let onChange: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let fitted = fittedRect(imageSize: CGSize(width: image.width, height: image.height), in: geometry.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: nsImage(for: image))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                    .allowsHitTesting(false)

                CropHandleOverlay(quad: $quad, imageRect: fitted, onChange: onChange)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fittedRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

}

private struct CropHandleOverlay: NSViewRepresentable {
    @Binding var quad: DocumentQuad
    let imageRect: CGRect
    let onChange: () -> Void

    func makeNSView(context: Context) -> CropInteractionView {
        let view = CropInteractionView()
        configure(view)
        return view
    }

    func updateNSView(_ view: CropInteractionView, context: Context) {
        configure(view)
        view.needsDisplay = true
    }

    private func configure(_ view: CropInteractionView) {
        let binding = $quad
        view.quad = quad
        view.imageRect = imageRect
        view.setQuad = { binding.wrappedValue = $0 }
        view.onChange = onChange
    }
}

private final class CropInteractionView: NSView {
    var quad: DocumentQuad = .imageBounds
    var imageRect: CGRect = .zero
    var setQuad: ((DocumentQuad) -> Void)?
    var onChange: (() -> Void)?

    private let handleRadius: CGFloat = 11
    private let hitRadius: CGFloat = 22
    private var activeIndex: Int?
    private var dragStartQuad: DocumentQuad?
    private var dragStartLocation: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        let points = quad.points.map(viewPoint)
        let outline = NSBezierPath()
        guard let first = points.first else { return }
        outline.move(to: first)
        for point in points.dropFirst() { outline.line(to: point) }
        outline.close()
        outline.lineWidth = 2.5
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        for point in points {
            let circle = NSBezierPath(ovalIn: CGRect(
                x: point.x - handleRadius,
                y: point.y - handleRadius,
                width: handleRadius * 2,
                height: handleRadius * 2
            ))
            NSColor.white.setFill()
            circle.fill()
            circle.lineWidth = 3
            NSColor.controlAccentColor.setStroke()
            circle.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let points = quad.points.map(viewPoint)
        guard let nearestIndex = points.indices.min(by: {
            squaredDistance(points[$0], location) < squaredDistance(points[$1], location)
        }), squaredDistance(points[nearestIndex], location) <= hitRadius * hitRadius else {
            activeIndex = nil
            return
        }

        activeIndex = nearestIndex
        dragStartQuad = quad
        dragStartLocation = location
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeIndex, let dragStartQuad, let dragStartLocation,
              imageRect.width > 0, imageRect.height > 0 else { return }

        let location = convert(event.locationInWindow, from: nil)
        let origin = dragStartQuad.point(at: activeIndex)
        let proposed = NormalizedPoint(
            x: origin.x + (location.x - dragStartLocation.x) / imageRect.width,
            y: origin.y + (location.y - dragStartLocation.y) / imageRect.height
        ).clamped()
        let candidate = dragStartQuad.replacing(pointAt: activeIndex, with: proposed)
        guard candidate.isValid, candidate != quad else { return }

        quad = candidate
        setQuad?(candidate)
        onChange?()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        activeIndex = nil
        dragStartQuad = nil
        dragStartLocation = nil
    }

    private func viewPoint(_ point: NormalizedPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + point.x * imageRect.width, y: imageRect.minY + point.y * imageRect.height)
    }

    private func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }
}

private func nsImage(for image: CGImage) -> NSImage {
    NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}
