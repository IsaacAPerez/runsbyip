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
                                    ProgressView().tint(.appBackground).scaleEffect(0.8)
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
                                    ZStack(alignment: .topTrailing) {
                                        AsyncImage(url: photo.url) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            } else if phase.error != nil {
                                                Color.appSurfaceElevated
                                                    .overlay(
                                                        Image(systemName: "exclamationmark.triangle")
                                                            .foregroundColor(.appTextTertiary)
                                                    )
                                            } else {
                                                Color.appSurface
                                                    .overlay(ProgressView().tint(.appTextSecondary))
                                            }
                                        }
                                        .frame(minHeight: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                        Button {
                                            deletePhoto(photo)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundColor(.white)
                                                .shadow(color: .black.opacity(0.6), radius: 3)
                                        }
                                        .padding(6)
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
