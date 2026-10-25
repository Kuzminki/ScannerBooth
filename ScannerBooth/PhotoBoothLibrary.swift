import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct PhotoEntry: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let title: String
    let modifiedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
}

enum PhotoLibraryFailure: LocalizedError {
    case invalidLibrary
    case permissionDenied
    case noImages

    var errorDescription: String? {
        switch self {
        case .invalidLibrary:
            return "Choisissez le paquet ou le dossier « Photo Booth Library »."
        case .permissionDenied:
            return "L’accès à cette photothèque n’a pas pu être ouvert. Sélectionnez-la de nouveau."
        case .noImages:
            return "Aucune photo compatible n’a été trouvée dans cette photothèque."
        }
    }
}

@MainActor
final class PhotoBoothLibraryStore: ObservableObject {
    @Published private(set) var photos: [PhotoEntry] = []
    @Published private(set) var libraryName: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let bookmarkKey = "PhotoBoothLibraryBookmark"
    private var activeLibraryURL: URL?
    private var refreshRequestID = UUID()

    func restoreSavedLibrary() async {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                throw PhotoLibraryFailure.permissionDenied
            }
            activeLibraryURL = url
            libraryName = url.deletingPathExtension().lastPathComponent
            if isStale { try storeBookmark(for: url) }
            await refresh(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Choisir la photothèque Photo Booth"
        panel.message = "Sélectionnez le paquet ou le dossier Photo Booth Library."
        panel.prompt = "Utiliser cette photothèque"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard values.isDirectory == true || values.isPackage == true else {
                throw PhotoLibraryFailure.invalidLibrary
            }
            guard url.startAccessingSecurityScopedResource() else {
                throw PhotoLibraryFailure.permissionDenied
            }
            if let activeLibraryURL { activeLibraryURL.stopAccessingSecurityScopedResource() }
            activeLibraryURL = url
            try storeBookmark(for: url)
            libraryName = url.deletingPathExtension().lastPathComponent
            errorMessage = nil
            refreshRequestID = UUID()
            Task { await refresh(from: url) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func storeBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    private func refresh(from url: URL) async {
        let requestID = UUID()
        refreshRequestID = requestID
        isLoading = true
        errorMessage = nil
        do {
            let found = try await Task.detached(priority: .userInitiated) {
                try PhotoBoothLibraryScanner.enumerateImages(in: url)
            }.value
            guard refreshRequestID == requestID else { return }
            photos = found
            if found.isEmpty { errorMessage = PhotoLibraryFailure.noImages.localizedDescription }
        } catch {
            guard refreshRequestID == requestID else { return }
            photos = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

enum PhotoBoothLibraryScanner {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif"]

    static func enumerateImages(in libraryURL: URL) throws -> [PhotoEntry] {
        let values = try libraryURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values.isDirectory == true || values.isPackage == true else {
            throw PhotoLibraryFailure.invalidLibrary
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw PhotoLibraryFailure.invalidLibrary
        }

        var results: [PhotoEntry] = []
        for case let fileURL as URL in enumerator {
            guard imageExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  min(width, height) >= 320 else { continue }

            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let modifiedAt = attributes?[.modificationDate] as? Date ?? .distantPast
            results.append(PhotoEntry(
                id: fileURL.absoluteString,
                url: fileURL,
                title: fileURL.deletingPathExtension().lastPathComponent,
                modifiedAt: modifiedAt,
                pixelWidth: width,
                pixelHeight: height
            ))
        }
        return results.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func thumbnail(for url: URL, maximumPixelSize: Int = 520) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary)
    }
}
