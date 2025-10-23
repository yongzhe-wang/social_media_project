import FirebaseAuth
import SwiftUI

struct CreatePostView: View {
    @State private var text = ""
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var showPicker = false
    let api = FirebaseFeedAPI()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextEditor(text: $text)
                    .frame(height: 150)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                }

                Button { showPicker = true } label: {
                    Label("Add Photo", systemImage: "photo.on.rectangle")
                }

                Spacer()

                Button {
                    Task {
                        isUploading = true
                        do {
                            try await api.uploadPost(text: text, image: selectedImage)
                            text = ""
                            selectedImage = nil
                        } catch {
                            print("Upload failed:", error)
                        }
                        isUploading = false
                    }
                } label: {
                    if isUploading {
                        ProgressView()
                    } else {
                        Text("Post")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                PhotoPicker(image: $selectedImage)
            }
            .padding()
            .navigationTitle("Create Post")
        }
    }
}
