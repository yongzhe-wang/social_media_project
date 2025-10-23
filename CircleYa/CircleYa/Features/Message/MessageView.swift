import SwiftUI

struct MessagesView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Top buttons row
                HStack(spacing: 20) {
                    NavigationLink(destination: LikesDetailView()) {
                        VStack {
                            Image(systemName: "heart.fill")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text("Likes")
                                .font(.caption)
                        }
                    }
                    Spacer()
                    NavigationLink(destination: CommentsDetailView()) {
                        VStack {
                            Image(systemName: "text.bubble.fill")
                                .font(.largeTitle)
                                .foregroundColor(.blue)
                            Text("Comments")
                                .font(.caption)
                        }
                    }
                    Spacer()
                    NavigationLink(destination: FollowersDetailView()) {
                        VStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.largeTitle)
                                .foregroundColor(.green)
                            Text("Followers")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Divider()

                // Conversations list
                List {
                    Section(header: Text("Conversations")) {
                        ForEach(0..<10, id: \.self) { i in
                            NavigationLink(destination: ChatView(username: "User \(i)")) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                        .overlay(Text("\(i)").font(.caption))
                                    VStack(alignment: .leading) {
                                        Text("User \(i)")
                                            .font(.headline)
                                        Text("Last message preview...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Messages")
        }
    }
}
