import SwiftUI

struct PostDetailView: View {
    let post: Post

    // ⬇️ Add these two lines
    private let historyAPI = FirebaseFeedAPI()
    @State private var didLogView = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FeedCard(post: post)

                Text(post.text).font(.body).padding(.horizontal, 4)
                if !post.tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(post.tags, id: \.self) {
                            Text("#\($0)")
                                .font(.caption).padding(.horizontal,10).padding(.vertical,6)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        // ⬇️ Log exactly once per appearance
        .task {
            if !didLogView {
                didLogView = true
                await historyAPI.recordHistoryView(postId: post.id)
            }
        }
    }
}
