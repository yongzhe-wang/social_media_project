import FirebaseFirestore
import FirebaseAuth

struct FirebaseMessageAPI {
    private let db = Firestore.firestore()

    struct ChatMessage: Codable {
        var id: String
        var senderId: String
        var text: String
        var createdAt: Date
    }

    // Create or fetch a conversation
    func getOrCreateConversation(with otherUserId: String) async throws -> String {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }

        let participants = [currentUserId, otherUserId].sorted()
        let conversationId = participants.joined(separator: "_")

        let docRef = db.collection("messages").document(conversationId)
        let doc = try await docRef.getDocument()

        if !doc.exists {
            try await docRef.setData([
                "participants": participants,
                "lastMessage": "",
                "updatedAt": FieldValue.serverTimestamp()
            ])
        }

        return conversationId
    }

    // Send a message
    func sendMessage(to otherUserId: String, text: String) async throws {
        let conversationId = try await getOrCreateConversation(with: otherUserId)
        guard let senderId = Auth.auth().currentUser?.uid else { return }

        let messageId = UUID().uuidString
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": senderId,
            "text": text,
            "createdAt": FieldValue.serverTimestamp()
        ]

        let conversationRef = db.collection("messages").document(conversationId)
        try await conversationRef.collection("messages").document(messageId).setData(messageData)

        try await conversationRef.updateData([
            "lastMessage": text,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // Fetch messages in a conversation
    // Fetch messages in a conversation
    func fetchMessages(with otherUserId: String) async throws -> [ChatMessage] {
        let conversationId = try await getOrCreateConversation(with: otherUserId)
        let snapshot = try await db.collection("messages")
            .document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()

            guard
                let senderId = data["senderId"] as? String,
                let text = data["text"] as? String
            else {
                return nil
            }

            // Firestore serverTimestamp() can be nil right after write; be defensive.
            let createdAt: Date
            if let ts = data["createdAt"] as? Timestamp {
                createdAt = ts.dateValue()
            } else {
                createdAt = Date()
            }

            return ChatMessage(
                id: doc.documentID,
                senderId: senderId,
                text: text,
                createdAt: createdAt
            )
        }
    }

}
