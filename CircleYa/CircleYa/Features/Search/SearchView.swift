import SwiftUI
import FirebaseFirestore

@MainActor
struct SearchView: View {
    enum Segment: String, CaseIterable { case posts = "Posts", users = "Users" }

    let api: FeedAPI

    @State private var query = ""
    @State private var segment: Segment = .posts

    @State private var isLoading = false
    @State private var postResults: [Post] = []
    @State private var userResults: [User] = []

    var body: some View {
        List {
            // Search field
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search tags, users, posts", text: $query)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await runSearch() } }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            postResults = []
                            userResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Segmented control
            Section {
                Picker("Type", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Results
            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    if segment == .posts {
                        ForEach(postResults, id: \.id) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                HStack(spacing: 12) {
                                    if let m = post.media.first {
                                        AsyncImage(url: m.thumbURL ?? m.url) { phase in
                                            switch phase {
                                            case .success(let img): img.resizable().scaledToFill()
                                            default: Color.gray.opacity(0.12)
                                            }
                                        }
                                        .frame(width: 64, height: 64)
                                        .clipped()
                                        .cornerRadius(8)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(post.text).lineLimit(2)
                                        Text("@\(post.author.idForUsers) • \(post.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else { // users
                        ForEach(userResults, id: \.id) { user in
                            NavigationLink(
                                destination: OtherUserProfileView(userId: user.id) // <-- your profile screen
                            ) {
                                HStack(spacing: 12) {
                                    AvatarView(user: user, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName).font(.headline)
                                        Text("@\(user.idForUsers)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack { Spacer(); Button("Search") { Task { await runSearch() } } }
            }
        }
    }

    // MARK: - Search
    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { postResults = []; userResults = []; return }
        isLoading = true; defer { isLoading = false }

        // Posts: reuse your current feed then filter locally
        if let page = try? await api.fetchFeed(cursor: nil) {
            postResults = page.items.filter {
                $0.text.lowercased().contains(q) ||
                $0.tags.contains { $0.lowercased().contains(q) } ||
                $0.author.displayName.lowercased().contains(q) ||
                $0.author.idForUsers.lowercased().contains(q)
            }
        } else {
            postResults = []
        }

        // Users: simple fetch+filter (good enough for demo; can be replaced with indexed prefix query later)
        do {
            let snap = try await Firestore.firestore()
                .collection("users")
                .limit(to: 100)
                .getDocuments()

            userResults = snap.documents.compactMap { doc in
                let d = doc.data()
                let display = (d["displayName"] as? String) ?? ""
                let handle  = (d["idForUsers"] as? String)
                    ?? (d["handle"] as? String) ?? ""
                let email   = (d["email"] as? String) ?? ""
                let avatar  = (d["avatarURL"] as? String).flatMap(URL.init(string:))
                return User(id: doc.documentID,
                            idForUsers: handle,
                            displayName: display,
                            email: email,
                            avatarURL: avatar,
                            bio: d["bio"] as? String)
            }
            .filter {
                $0.displayName.lowercased().contains(q) ||
                $0.idForUsers.lowercased().contains(q)
            }
        } catch {
            userResults = []
            print("User search failed:", error.localizedDescription)
        }
    }
}
