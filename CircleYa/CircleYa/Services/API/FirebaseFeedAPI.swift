//
//  FirebaseFeedAPI.swift
//  CircleYa
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import UIKit

// MARK: - Errors
enum AuthError: Error {
    case noUser
    case noAuthor
}

// MARK: - User Cache (actor-safe)
actor UserCache {
    static let shared = UserCache()
    private var cache: [String: User] = [:]

    func get(_ uid: String) -> User? { cache[uid] }
    func set(_ uid: String, user: User) { cache[uid] = user }
}

// MARK: - Centralized Firestore Paths (schema aligned with your design)
private enum FSPath {
    static let db = Firestore.firestore()

    // Collections
    static var posts: CollectionReference { db.collection("posts") }
    static func user(_ uid: String) -> DocumentReference { db.collection("users").document(uid) }

    // Subcollections under /users/{uid}
    static func userHistory(_ uid: String) -> CollectionReference {
        user(uid).collection("history")
    }
    static func userSaves(_ uid: String) -> CollectionReference {
        user(uid).collection("saves")
    }
    static func userFollowers(_ uid: String) -> CollectionReference {
        user(uid).collection("followers")
    }
    static func userFollowing(_ uid: String) -> CollectionReference {
        user(uid).collection("following")
    }
    static func userSettingPreferences(_ uid: String) -> CollectionReference {
        user(uid).collection("settingPreferences")
    }
    static func userCreator(_ uid: String) -> CollectionReference {
        user(uid).collection("creator")
    }
    static func userPostsICreate(_ uid: String) -> CollectionReference {
        user(uid).collection("postsICreate")
    }
    // (Optional) separate likes subcollection for fast membership checks
    static func userLikes(_ uid: String) -> CollectionReference {
        user(uid).collection("likes")
    }
}

// MARK: - API
struct FirebaseFeedAPI: FeedAPI {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: Feed (Discover)
    func fetchFeed(cursor: String?) async throws -> FeedPage {
        let snapshot = try await FSPath.posts
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        let posts = try await decodePosts(snapshot.documents)
        return FeedPage(items: posts, nextCursor: nil)
    }

    // MARK: Nearby (currently same query; location filter can be added later)
    func fetchNearby(cursor: String?) async throws -> FeedPage {
        try await fetchFeed(cursor: cursor)
    }

    // MARK: Upload Post (Global + /users/{uid}/postsICreate)
    func uploadPost(text: String, image: UIImage?) async throws {
        guard let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }

        Log.info("🚀 uploadPost start uid=\(user.uid.prefix(6)) text=\(text.prefix(20))")

        // 1) Upload media if provided
        var mediaItems: [[String: Any]] = []
        if let image = image {
            let imageURL = try await uploadImage(image)
            mediaItems = [[
                "id": UUID().uuidString,
                "type": "image",
                "url": imageURL.absoluteString,
                "width": 600,
                "height": 600,
                "thumbURL": imageURL.absoluteString
            ]]
        }

        // 2) Prepare post object
        let postId = UUID().uuidString
        let postData: [String: Any] = [
            "id": postId,
            "authorId": user.uid,
            "text": text,
            "media": mediaItems,
            "tags": [],
            "createdAt": FieldValue.serverTimestamp(),
            "likeCount": 0,
            "saveCount": 0,
            "commentCount": 0
        ]

        // 3) Write global post
        try await FSPath.posts.document(postId).setData(postData)

        // 4) Write duplicate ref under user subcollection per design: /users/{uid}/postsICreate/{postId}
        try await FSPath.userPostsICreate(user.uid).document(postId).setData([
            "postRef": FSPath.posts.document(postId).path,
            "createdAt": FieldValue.serverTimestamp()
        ])

        Log.info("✅ uploadPost done id=\(postId)")
    }

    // MARK: Upload Image helper
    func uploadImage(_ image: UIImage) async throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotCreateFile)
        }
        let name = "posts/\(UUID().uuidString).jpg"
        let ref = storage.reference().child(name)
        _ = try await ref.putDataAsync(data)
        return try await ref.downloadURL()
    }

    // MARK: Decode a batch of posts
    private func decodePosts(_ docs: [QueryDocumentSnapshot]) async throws -> [Post] {
        var posts: [Post] = []
        posts.reserveCapacity(docs.count)

        for doc in docs {
            do {
                let post = try await decodePost(from: doc.data(), id: doc.documentID)
                posts.append(post)
            } catch {
                Log.warn("⚠️ decodePosts skip \(doc.documentID): \(error.localizedDescription)")
            }
        }
        return posts
    }

    // MARK: Decode a single post (with live author lookup)
    func decodePost(from data: [String: Any], id: String) async throws -> Post {
        let authorId = data["authorId"] as? String ?? ""
        guard !authorId.isEmpty else { throw AuthError.noAuthor }

        // Fetch author from /users/{uid} (cached)
        let author = try await fetchAuthor(for: authorId)

        // Decode media
        let mediaArray: [Media] = (data["media"] as? [[String: Any]] ?? []).compactMap { m in
            guard let urlStr = m["url"] as? String, let url = URL(string: urlStr) else { return nil }
            let thumbStr = (m["thumbURL"] as? String) ?? urlStr
            return Media(
                id: (m["id"] as? String) ?? UUID().uuidString,
                type: .image,
                url: url,
                width: (m["width"] as? Int) ?? 600,
                height: (m["height"] as? Int) ?? 600,
                thumbURL: URL(string: thumbStr)
            )
        }

        // Timestamp
        let timestamp = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

        return Post(
            id: id,
            author: author,
            text: (data["text"] as? String) ?? "",
            media: mediaArray,
            tags: (data["tags"] as? [String]) ?? [],
            createdAt: timestamp,
            likeCount: (data["likeCount"] as? Int) ?? 0,
            saveCount: (data["saveCount"] as? Int) ?? 0,
            commentCount: (data["commentCount"] as? Int) ?? 0
        )
    }

    // MARK: Fetch Author (Firestore + actor cache) — matches new User design
    private func fetchAuthor(for uid: String) async throws -> User {
        if let cached = await UserCache.shared.get(uid) {
            return cached
        }

        let doc = try await FSPath.user(uid).getDocument()
        let data = doc.data() ?? [:]

        let displayName = (data["displayName"] as? String) ?? "Unknown"
        let idForUsers = (data["idForUsers"] as? String)
            ?? (data["handle"] as? String)               // fallback if old field is still present
            ?? (data["email"] as? String)?.components(separatedBy: "@").first
            ?? "user"

        let avatarURLStr = (data["avatarURL"] as? String)
        let author = User(
            id: uid,
            idForUsers: idForUsers,
            displayName: displayName,
            email: (data["email"] as? String) ?? (Auth.auth().currentUser?.email ?? ""),
            avatarURL: avatarURLStr.flatMap(URL.init(string:)),
            bio: data["bio"] as? String,
            numTotalLikes: data["numTotalLikes"] as? Int,
            numTotalSaves: data["numTotalSaves"] as? Int
        )

        await UserCache.shared.set(uid, user: author)
        return author
    }
}

// MARK: - Like / Save operations (aligned with subcollections in your design)
extension FirebaseFeedAPI {

    /// Toggle like membership in /users/{uid}/likes and update post.likeCount.
    /// (If you also want to maintain author's numTotalLikes, you can add an update to the author's user doc.)
    func toggleLike(for postId: String) async throws -> Bool {
        guard
            let uid = Auth.auth().currentUser?.uid
        else { throw URLError(.userAuthenticationRequired) }

        let likeRef = FSPath.userLikes(uid).document(postId)
        let postRef = FSPath.posts.document(postId)

        let exists = try await likeRef.getDocument().exists
        if exists {
            try await likeRef.delete()
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(-1))])
            return false
        } else {
            try await likeRef.setData(["createdAt": FieldValue.serverTimestamp()])
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(1))])
            return true
        }
    }

    /// Toggle save membership in /users/{uid}/saves and update post.saveCount + user's savedPostIds array.
    func toggleSave(for postId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { throw AuthError.noUser }

        let userRef = FSPath.user(uid)
        let saveRef = FSPath.userSaves(uid).document(postId)
        let postRef = FSPath.posts.document(postId)

        let doc = try await saveRef.getDocument()
        if doc.exists {
            // UNSAVE
            try await saveRef.delete()
            try await userRef.updateData([
                "savedPostIds": FieldValue.arrayRemove([postId])
            ])
            try await postRef.updateData(["saveCount": FieldValue.increment(Int64(-1))])
            return false
        } else {
            // SAVE
            try await saveRef.setData([
                "createdAt": FieldValue.serverTimestamp()
            ])
            try await userRef.updateData([
                "savedPostIds": FieldValue.arrayUnion([postId])
            ])
            try await postRef.updateData(["saveCount": FieldValue.increment(Int64(1))])
            return true
        }
    }

    // Convenience checks used by UI
    func isPostLiked(_ postId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return (try? await FSPath.userLikes(uid).document(postId).getDocument().exists) ?? false
    }

    func isPostSaved(_ postId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return (try? await FSPath.userSaves(uid).document(postId).getDocument().exists) ?? false
    }
}

// MARK: - History (viewed posts)
extension FirebaseFeedAPI {
    /// Log that the current user viewed a post.
    func recordHistoryView(postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FSPath.userHistory(uid)
                .document(postId)
                .setData(["viewedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            print("⚠️ recordHistoryView failed:", error.localizedDescription)
        }
    }

    /// Fetch recently viewed posts for current user, newest first.
    func fetchHistory(limit: Int = 50) async throws -> [Post] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }

        let historySnap = try await FSPath.userHistory(uid)
            .order(by: "viewedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        var posts: [Post] = []
        for doc in historySnap.documents {
            let postId = doc.documentID
            do {
                let postDoc = try await FSPath.posts.document(postId).getDocument()
                if let data = postDoc.data() {
                    let post = try await decodePost(from: data, id: postId)
                    posts.append(post)
                }
            } catch {
                print("⚠️ history decode failed for \(postId):", error.localizedDescription)
            }
        }
        return posts
    }

    /// Remove one item from history (for swipe-to-delete).
    func removeFromHistory(postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FSPath.userHistory(uid).document(postId).delete()
        } catch {
            print("⚠️ removeFromHistory failed:", error.localizedDescription)
        }
    }

    /// Clear all history.
    func clearHistory() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await FSPath.userHistory(uid).getDocuments()
            let batch = Firestore.firestore().batch()
            for d in snap.documents {
                batch.deleteDocument(d.reference)
            }
            try await batch.commit()
        } catch {
            print("⚠️ clearHistory failed:", error.localizedDescription)
        }
    }
}





