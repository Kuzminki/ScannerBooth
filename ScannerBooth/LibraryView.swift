import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: PhotoBoothLibraryStore
    @State private var selectedPhoto: PhotoEntry?

    var body: some View {
        Group {
            if let selectedPhoto {
                ScannerEditorView(photo: selectedPhoto) {
                    self.selectedPhoto = nil
                }
            } else {
                browser
            }
        }
        .task { await library.restoreSavedLibrary() }
        .alert("Photothèque Photo Booth", isPresented: errorAlertPresented) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "Une erreur inconnue est survenue.")
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ScannerBooth")
                        .font(.title2.weight(.semibold))
                    Text(library.libraryName ?? "Choisissez votre photothèque Photo Booth")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(library.libraryName == nil ? "Choisir la photothèque…" : "Changer de photothèque…") {
                    library.chooseLibrary()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            if library.isLoading {
                Spacer()
                ProgressView("Lecture de la photothèque…")
                Spacer()
            } else if library.photos.isEmpty {
                ContentUnavailableView {
                    Label("Aucune photo à afficher", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text(library.libraryName == nil
                         ? "Sélectionnez le paquet ou le dossier Photo Booth Library pour parcourir ses photos."
                         : "Choisissez une autre photothèque ou vérifiez qu’elle contient des photos."
                    )
                } actions: {
                    Button("Choisir une photothèque") { library.chooseLibrary() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 270), spacing: 18)], spacing: 18) {
                        ForEach(library.photos) { photo in
                            PhotoCard(photo: photo) { selectedPhoto = photo }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )
    }
}

private struct PhotoCard: View {
    let photo: PhotoEntry
    let action: () -> Void
    @State private var thumbnail: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(nsColor: .underPageBackgroundColor))
                    if let thumbnail {
                        Image(nsImage: NSImage(
                            cgImage: thumbnail,
                            size: NSSize(width: thumbnail.width, height: thumbnail.height)
                        ))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(7)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(photo.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .help(photo.title)
                Text("\(photo.pixelWidth) × \(photo.pixelHeight) · \(photo.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .task(id: photo.url) {
            let url = photo.url
            thumbnail = await Task.detached(priority: .utility) {
                PhotoBoothLibraryScanner.thumbnail(for: url)
            }.value
        }
    }
}
