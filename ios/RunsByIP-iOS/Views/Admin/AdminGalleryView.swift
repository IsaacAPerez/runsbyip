import SwiftUI
import PhotosUI

struct AdminGalleryView: View {
    @EnvironmentObject var chatService: ChatService

    @State private var photos: [GalleryPhoto] = []
    @State private var isLoading = true
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var toastMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if isLoading {
                LoadingView(message: "Loading gallery...")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Upload button
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            HStack {
                                if isUploading {
                                    AppSpinner(color: .appBackground, size: .sm)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Photo")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appAccentOrange)
                            .foregroundColor(.appBackground)
                            .cornerRadius(AppStyle.buttonCornerRadius)
                        }
                        .disabled(isUploading)
                        .padding(.horizontal)

                        if photos.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 40))
                                    .foregroundColor(.appTextTertiary)
                                Text("No gallery photos yet")
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                            }
                            .padding(.top, 60)
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(photos) { photo in
                                    GalleryTile(photo: photo) {
                                        deletePhoto(photo)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }

            if let toast = toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: toast, type: .success)
                        .padding(.bottom, 20)
                }
            }
        }
        .condensedNavTitle("Gallery")
        .task { await loadPhotos() }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            uploadPhoto(item: item)
        }
    }

    private func loadPhotos() async {
        do {
            let urls = try await chatService.fetchGalleryPhotos()
            photos = urls.map { GalleryPhoto(url: $0) }
        } catch {
            // degrade gracefully
        }
        isLoading = false
    }

    private func uploadPhoto(item: PhotosPickerItem) {
        isUploading = true
        Task {
            defer { isUploading = false; selectedItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.75) else {
                showToast("Could not load image")
                return
            }
            do {
                try await chatService.uploadGalleryPhoto(data: jpeg)
                await loadPhotos()
                showToast("Photo added")
            } catch {
                showToast("Upload failed")
            }
        }
    }

    private func deletePhoto(_ photo: GalleryPhoto) {
        let filename = photo.url.lastPathComponent
        Task {
            do {
                try await chatService.deleteGalleryPhoto(path: filename)
                photos.removeAll { $0.id == photo.id }
                showToast("Photo removed")
            } catch {
                showToast("Delete failed")
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            toastMessage = nil
        }
    }
}

struct GalleryPhoto: Identifiable {
    let id = UUID()
    let url: URL
}

/// Square thumbnail with overlaid delete control. Constraining each tile to
/// 1:1 prevents `scaledToFill()` from overflowing the grid cell and stacking
/// onto the next row's tile (which was hiding the x button for that row).
private struct GalleryTile: View {
    let photo: GalleryPhoto
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.appSurface

            AsyncImage(url: photo.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.appTextTertiary)
                case .empty:
                    AppSpinner(color: .appTextSecondary, size: .md)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.65), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .confirmationDialog("Remove this photo?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}
