import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct OtherUserProfileView: View {
    let userId: String

    @State private var user: User?
    @State private var posts: [Post] = []

    @State private var isLoading = false
    @State private var error: String?

    // Follow state
    @State private var isFollowing = false
    @State private var isTogglingFollow = false
    @State private var followerCount: Int = 0
    @State private var followingCount: Int = 0

    private let db = Firestore.firestore()
    private let api = FirebaseFeedAPI()

    private var currentUid: String? { Auth.auth().currentUser?.uid }
    private var isViewingSelf: Bool { currentUid == userId }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if !isViewingSelf {
                    Button(action: { Task { await toggleFollow() } }) {
                        HStack {
                            if isTogglingFollow { ProgressView() }
                            Text(isFollowing ? "Unfollow" : "Follow")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isFollowing ? Color.secondary.opacity(0.15) : Color.accentColor)
                        .foregroundStyle(isFollowing ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isTogglingFollow || currentUid == nil)
                    .padding(.horizontal)
                }

                HStack(spacing: 24) {
                    VStack { Text("\(followerCount)").bold(); Text("Followers").font(.caption).foregroundStyle(.secondary) }
                    VStack { Text("\(followingCount)").bold(); Text("Following").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.bottom, 4)

                Divider().padding(.horizontal)

                if isLoading {
                    ProgressView("Loading…").padding()
                } else if let error {
                    Text(error).foregroundStyle(.red).padding()
                } else {
                    MasonryLayout(columns: 2, spacing: 8) {
                        ForEach(posts) { p in
                            NavigationLink(destination: PostDetailView(post: p)) {
                                FeedCard(post: p)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle(user?.displayName.isEmpty == false ? user!.displayName : "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header
    @ViewBuilder private var header: some View {
        VStack(spacing: 10) {
            if let u = user, let url = u.avatarURL {
                AsyncImage(url: url) { ph in
                    switch ph {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .shadow(radius: 4)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(.secondary)
            }

            Text(user?.displayName ?? " ").font(.title3).bold()
            if let bio = user?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Load profile, posts, and follow state
    private func load() async {
        await MainActor.run { isLoading = true; error = nil }
        defer { Task { await MainActor.run { isLoading = false } } }

        do {
            // Profile
            let doc = try await db.collection("users").document(userId).getDocument()
            let data = doc.data() ?? [:]
            let avatar = (data["avatarURL"] as? String).flatMap(URL.init(string:))
            let u = User(
                id: userId,
                idForUsers: (data["idForUsers"] as? String) ?? (data["handle"] as? String) ?? "user",
                displayName: (data["displayName"] as? String) ?? "Unknown",
                email: (data["email"] as? String) ?? "",
                avatarURL: avatar,
                bio: data["bio"] as? String
            )
            await MainActor.run { self.user = u }

            // Posts
            let snap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            var decoded: [Post] = []
            for d in snap.documents {
                if let p = try? await api.decodePost(from: d.data(), id: d.documentID) {
                    decoded.append(p)
                }
            }
            await MainActor.run { self.posts = decoded }

            // Follow state + counts
            await loadFollowStateAndCounts()
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func loadFollowStateAndCounts() async {
        guard let me = currentUid else { return }

        async let isFollowingDoc = db.collection("users").document(me)
            .collection("following").document(userId).getDocument()

        async let followersCountAgg = db.collection("users").document(userId)
            .collection("followers").count.getAggregation(source: .server)

        async let followingCountAgg = db.collection("users").document(userId)
            .collection("following").count.getAggregation(source: .server)

        do {
            let (followDoc, followersAgg, followingAgg) = try await (isFollowingDoc, followersCountAgg, followingCountAgg)

            await MainActor.run {
                self.isFollowing = followDoc.exists
                self.followerCount = Int(truncating: followersAgg.count)
                self.followingCount = Int(truncating: followingAgg.count)
            }
        } catch {
            print("⚠️ follow state/counts load failed:", error.localizedDescription)
        }
    }

    // MARK: - Follow / Unfollow
    private func toggleFollow() async {
        guard let me = currentUid, me != userId else { return }
        if isTogglingFollow { return }
        await MainActor.run { isTogglingFollow = true }
        defer { Task { await MainActor.run { isTogglingFollow = false } } }

        let myFollowing = db.collection("users").document(me).collection("following").document(userId)
        let theirFollowers = db.collection("users").document(userId).collection("followers").document(me)

        do {
            let currentlyFollowing = try await myFollowing.getDocument().exists
            let batch = db.batch()

            if currentlyFollowing {
                // UNFOLLOW: remove both pointers
                batch.deleteDocument(myFollowing)
                batch.deleteDocument(theirFollowers)
                await MainActor.run {
                    self.isFollowing = false
                    self.followerCount = max(0, self.followerCount - 1)
                }
            } else {
                // FOLLOW: create both pointers
                let now: [String: Any] = ["createdAt": FieldValue.serverTimestamp()]
                batch.setData(now, forDocument: myFollowing)
                batch.setData(now, forDocument: theirFollowers)
                await MainActor.run {
                    self.isFollowing = true
                    self.followerCount += 1
                }
            }

            try await batch.commit()
        } catch {
            print("❌ toggleFollow failed:", error.localizedDescription)
        }
    }
}
