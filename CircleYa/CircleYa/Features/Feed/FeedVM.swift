import Foundation
import FirebaseFirestore

enum FeedKind {
    case discover
    case nearby
}

@MainActor
final class FeedVM: ObservableObject {
    @Published var items: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdated: Date?

    private let api: FeedAPI
    private let kind: FeedKind
    private var listener: ListenerRegistration?

    init(api: FeedAPI, kind: FeedKind = .discover) {
        self.api = api
        self.kind = kind
    }

    // MARK: - Load feed (initial or refresh)
    func loadInitial(forceRefresh: Bool = false) async {
        // Avoid duplicate loads unless forced by refresh
        if isLoading && !forceRefresh { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let page: FeedPage
            switch kind {
            case .discover:
                page = try await api.fetchFeed(cursor: nil)
            case .nearby:
                page = try await api.fetchNearby(cursor: nil)
            }

            // Set items and timestamp
            self.items = page.items
            self.lastUpdated = Date()

            // Attach realtime listener only once
            if listener == nil {
                await attachLiveListener()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Manual refresh
    func refresh() async {
        await loadInitial(forceRefresh: true)
    }

    // MARK: - Realtime listener for Firestore updates
    private func attachLiveListener() async {
        listener?.remove()

        listener = Firestore.firestore()
            .collection("posts")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, err in
                guard let self else { return }

                if let err {
                    Task { @MainActor in
                        self.error = err.localizedDescription
                    }
                    return
                }

                guard let docs = snapshot?.documents else { return }

                Task {
                    let decoder = FirebaseFeedAPI()
                    var decoded: [Post] = []

                    for doc in docs {
                        do {
                            let post = try await decoder.decodePost(from: doc.data(), id: doc.documentID)
                            decoded.append(post)
                        } catch {
                            Log.warn("⚠️ Failed to decode post \(doc.documentID): \(error.localizedDescription)")
                        }
                    }

                    await MainActor.run {
                        self.items = decoded
                        self.lastUpdated = Date()
                    }
                }
            }
    }

    deinit {
        listener?.remove()
    }
}
