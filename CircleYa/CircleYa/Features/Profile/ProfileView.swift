import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @State private var username: String = "First Last"
    @State private var location: String = "Philadelphia, USA" // TODO: replace with real IP logic
    @State private var bio: String = "Tell something about yourself"
    @State private var profileImage: UIImage?
    @State private var selectedTab: ProfileTab = .notes
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var followerCount = 0
    @State private var followingCount = 0

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Avatar + Name + Location + Bio
                    VStack(spacing: 8) {
                        if let profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .foregroundColor(.secondary)
                        }

                        Text(username)
                            .font(.title2).bold()

                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !bio.isEmpty {
                            Text(bio)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 20)

                    // Profile Buttons (QR + Edit)
                    HStack(spacing: 20) {
                        NavigationLink(destination: QRScannerView()) {
                            VStack {
                                Image(systemName: "qrcode.viewfinder").font(.title2)
                                Text("Scan QR").font(.caption)
                            }
                        }
                        NavigationLink(
                            destination: EditProfileView(
                                username: $username,
                                bio: $bio,
                                profileImage: $profileImage
                            )
                        ) {
                            VStack {
                                Image(systemName: "pencil.circle").font(.title2)
                                Text("Edit Profile").font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    // Counts
                    HStack(spacing: 24) {
                        VStack {
                            Text("\(followerCount)").bold()
                            Text("Followers").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack {
                            Text("\(followingCount)").bold()
                            Text("Following").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    // Sign Out
                    Button { signOut() } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .padding(.bottom, 5)
                    }

                    Divider().padding(.horizontal)

                    // Tabs
                    HStack {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(.subheadline).bold()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedTab == tab ? Color.blue.opacity(0.15) : Color.clear)
                                    )
                            }
                            .foregroundColor(selectedTab == tab ? .blue : .primary)
                        }
                    }
                    .padding(.horizontal)

                    Divider().padding(.horizontal)

                    // Content
                    VStack(spacing: 12) {
                        switch selectedTab {
                        case .notes:   NotesListView()
                        case .history: HistoryListView()
                        case .saved:   SavedListView()
                        }
                    }
                    .padding(.horizontal)
                }
                .overlay {
                    if isLoading { ProgressView("Loading…") }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadCurrentUser() }               // ← fetch on open
            .refreshable { await loadCurrentUser() }        // ← pull to refresh
            .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
                Task { await loadCurrentUser() }            // ← update after edits
            }
        }
    }

    // MARK: - Firestore fetch
    private func loadCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            await MainActor.run { errorMessage = "Not signed in." }
            return
        }

        await MainActor.run { isLoading = true; errorMessage = nil }
        defer { Task { await MainActor.run { isLoading = false } } }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else { throw NSError(domain: "Profile", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not found"]) }

            let displayName: String = {
                let raw = data["displayName"] as? String ?? ""
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "First Last" : trimmed
            }()

            let bio = (data["bio"] as? String) ?? ""
            let avatarURLString = data["avatarURL"] as? String

            await MainActor.run {
                self.username = displayName
                self.bio = bio
            }

            if let s = avatarURLString, let url = URL(string: s) {
                do {
                    let (d, _) = try await URLSession.shared.data(from: url)
                    if let img = UIImage(data: d) {
                        await MainActor.run { self.profileImage = img }
                    }
                } catch {
                    // don’t fail the screen if avatar download fails
                    print("⚠️ Avatar download failed:", error.localizedDescription)
                }
            } else {
                await MainActor.run { self.profileImage = nil }
            }
            async let followersSnap = db.collection("users")
                .document(uid)
                .collection("followers")
                .getDocuments()

            async let followingSnap = db.collection("users")
                .document(uid)
                .collection("following")
                .getDocuments()

            let (fSnap, gSnap) = try await (followersSnap, followingSnap)

            await MainActor.run {
                self.followerCount = fSnap.documents.count
                self.followingCount = gSnap.documents.count
            }
        } catch {
            await MainActor.run { self.errorMessage = "Failed to load profile: \(error.localizedDescription)" }
        }
    }

    // MARK: - Sign Out
    private func signOut() {
        do {
            try Auth.auth().signOut()
            print("🧹 Signed out from Firebase")
            NotificationCenter.default.post(name: .userDidSignOut, object: nil)
        } catch {
            errorMessage = "Sign-out failed: \(error.localizedDescription)"
        }
    }
}

extension Notification.Name {
    static let userDidSignOut = Notification.Name("userDidSignOut")
    static let profileDidChange = Notification.Name("profileDidChange") // post this after saving in EditProfileView
}

enum ProfileTab: String, CaseIterable {
    case notes = "Notes"
    case history = "History"
    case saved = "Saved"
}
