// CircleYa/Services/Embeddings/EmbeddingProvider.swift
import Foundation

// MARK: - Public selection
enum EmbeddingBackend: String, CaseIterable {
    case openAI, cohere, vertexAI, localFallback
}

// MARK: - Protocol
protocol EmbeddingProvider {
    /// Returns one vector per input text. All vectors are L2-normalized.
    func embed(texts: [String]) async throws -> [[Double]]
}

// MARK: - Factory
struct Embeddings {
    static func make() -> EmbeddingProvider {
        let choice = UserDefaults.standard.string(forKey: "embeddings.backend")
            .flatMap(EmbeddingBackend.init(rawValue:)) ?? .localFallback

        switch choice {
        case .openAI:      return OpenAIEmbeddingProvider()
        case .cohere:      return CohereEmbeddingProvider()
        case .vertexAI:    return VertexEmbeddingProvider()
        case .localFallback: return LocalEmbeddingProvider()
        }
    }
}

// MARK: - OpenAI
struct OpenAIEmbeddingProvider: EmbeddingProvider {
    private let apiKey: String = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        ?? (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? "")

    // text-embedding-3-small keeps payload light; swap if you prefer -large
    private let model = "text-embedding-3-small"

    func embed(texts: [String]) async throws -> [[Double]] {
        guard !apiKey.isEmpty else { return try await LocalEmbeddingProvider().embed(texts: texts) }

        struct Req: Encodable { let input: [String]; let model: String }
        struct Resp: Decodable {
            struct Datum: Decodable { let embedding: [Double] }
            let data: [Datum]
        }

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/embeddings")!)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(Req(input: texts, model: model))

        let (data, _) = try await URLSession.shared.data(for: req)
        let parsed = try JSONDecoder().decode(Resp.self, from: data)
        return parsed.data.map { VectorMath.normalize($0.embedding) }
    }
}

// MARK: - Cohere
struct CohereEmbeddingProvider: EmbeddingProvider {
    private let apiKey: String = ProcessInfo.processInfo.environment["COHERE_API_KEY"]
        ?? (Bundle.main.object(forInfoDictionaryKey: "COHERE_API_KEY") as? String ?? "")
    private let model = "embed-english-v3.0"

    func embed(texts: [String]) async throws -> [[Double]] {
        guard !apiKey.isEmpty else { return try await LocalEmbeddingProvider().embed(texts: texts) }

        struct Req: Encodable { let texts: [String]; let model: String }
        struct Resp: Decodable { let embeddings: [[Double]] }

        var req = URLRequest(url: URL(string: "https://api.cohere.ai/v1/embed")!)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(Req(texts: texts, model: model))

        let (data, _) = try await URLSession.shared.data(for: req)
        let parsed = try JSONDecoder().decode(Resp.self, from: data)
        return parsed.embeddings.map { VectorMath.normalize($0) }
    }
}

// MARK: - Vertex AI (expects an access token in env/Info.plist)
struct VertexEmbeddingProvider: EmbeddingProvider {
    private let project = Bundle.main.object(forInfoDictionaryKey: "VERTEX_PROJECT_ID") as? String ?? ""
    private let location = Bundle.main.object(forInfoDictionaryKey: "VERTEX_LOCATION") as? String ?? "us-central1"
    private let model = Bundle.main.object(forInfoDictionaryKey: "VERTEX_EMBED_MODEL") as? String ?? "text-embedding-004"
    private let accessToken = ProcessInfo.processInfo.environment["VERTEX_ACCESS_TOKEN"]
        ?? (Bundle.main.object(forInfoDictionaryKey: "VERTEX_ACCESS_TOKEN") as? String ?? "")

    func embed(texts: [String]) async throws -> [[Double]] {
        guard !project.isEmpty, !accessToken.isEmpty else { return try await LocalEmbeddingProvider().embed(texts: texts) }

        struct Part: Encodable { let text: String }
        struct Instance: Encodable { let content: [Part] }
        struct Req: Encodable { let instances: [Instance]; let model: String }
        struct Resp: Decodable {
            struct Pred: Decodable { let embeddings: Emb; struct Emb: Decodable { let values: [Double] } }
            let predictions: [Pred]
        }

        let url = URL(string:
          "https://\(location)-aiplatform.googleapis.com/v1/projects/\(project)/locations/\(location)/publishers/google/models/\(model):predict"
        )!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let instances = texts.map { Instance(content: [Part(text: $0)]) }
        req.httpBody = try JSONEncoder().encode(Req(instances: instances, model: model))

        let (data, _) = try await URLSession.shared.data(for: req)
        let parsed = try JSONDecoder().decode(Resp.self, from: data)
        return parsed.predictions.map { VectorMath.normalize($0.embeddings.values) }
    }
}

// MARK: - Local fallback (deterministic, lightweight)
struct LocalEmbeddingProvider: EmbeddingProvider {
    func embed(texts: [String]) async throws -> [[Double]] {
        return texts.map { LocalEmbeddingProvider.hashingEmbedding($0, dim: 256) }
    }

    private static func hashingEmbedding(_ s: String, dim: Int) -> [Double] {
        var vec = Array(repeating: 0.0, count: dim)
        let tokens = s.lowercased().split { !$0.isLetter && !$0.isNumber }
        for t in tokens {
            let h = t.hashValue
            let i = abs(h) % dim
            vec[i] += 1.0
        }
        return VectorMath.normalize(vec)
    }
}
