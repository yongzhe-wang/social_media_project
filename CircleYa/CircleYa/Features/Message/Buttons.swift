import SwiftUI

struct LikesDetailView: View {
    var body: some View {
        List(0..<20, id: \.self) { i in
            HStack {
                Image(systemName: "heart.fill").foregroundColor(.red)
                Text("User \(i) liked your post")
            }
        }
        .navigationTitle("Likes")
    }
}

struct CommentsDetailView: View {
    var body: some View {
        List(0..<15, id: \.self) { i in
            HStack {
                Image(systemName: "text.bubble.fill").foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text("User \(i) commented:")
                    Text("This is a comment preview…").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Comments")
    }
}

struct FollowersDetailView: View {
    var body: some View {
        List(0..<10, id: \.self) { i in
            HStack {
                Image(systemName: "person.crop.circle.badge.plus").foregroundColor(.green)
                Text("User \(i) followed you")
            }
        }
        .navigationTitle("Followers")
    }
}
