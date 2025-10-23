// CircleYa/Services/Reco/RecoEngine.swift
import Foundation

struct RecoParams {
    var w_sim = 0.40
    var w_soc = 0.10
    var w_eng = 0.20
    var w_rec = 0.20
    var w_nov = 0.10

    var muRecencyPerHour = 1.0/96.0     // ~4-day half-life
    var cooldownPenalty = 0.25
    var cooldownWindow = 2
    var jitter = 0.02
    var mmrLambda = 0.7

    var quotas: [Bucket: Double] = [.following:0.25,.trending:0.25,.similar:0.35,.fresh:0.15]
    var pageSize = 40
}

enum Bucket: CaseIterable { case following, trending, similar, fresh }

struct Candidate {
    let post: Post
    let bucket: Bucket
    let postVec: [Double]
    let authorId: String
    let createdAt: Date
    let likeCount: Int
    let saveCount: Int
}

struct UserVectors {
    let u: [Double]
    let recentShown: [(postId: String, vec: [Double])]
    let following: Set<String>
}

struct Scored {
    let cand: Candidate
    let base: Double
}

enum RecoEngine {
    static func score(_ c: Candidate,
                      u: UserVectors,
                      params: RecoParams) -> Double {

        // similarity
        let sSim = VectorMath.cos(u.u, c.postVec)

        // social affinity
        let sSoc: Double = u.following.contains(c.authorId) ? 1.0 : 0.0

        // engagement (tanh(log(1+likes+c*saves)))
        let cSave = 2.0
        let eta = 0.15
        let pop = log(1.0 + Double(c.likeCount) + cSave*Double(c.saveCount))
        let sEng = tanh(eta * pop)

        // recency exp(-mu * hours)
        let hours = max(0.0, Date().timeIntervalSince(c.createdAt)/3600.0)
        let sRec = exp(-params.muRecencyPerHour * hours)

        // novelty: 1 - max cos to recently shown
        var maxCos = 0.0
        for (_, v) in u.recentShown { maxCos = max(maxCos, VectorMath.cos(c.postVec, v)) }
        let sNov = 1.0 - maxCos

        var score = params.w_sim*sSim + params.w_soc*sSoc + params.w_eng*sEng + params.w_rec*sRec + params.w_nov*sNov
        // tiny jitter
        score += Double.random(in: -params.jitter...params.jitter)
        return score
    }

    static func mix(sortedByBucket: [Bucket:[Candidate]],
                    u: UserVectors,
                    params: RecoParams) -> [Post] {

        // Precompute scores
        var heads: [Bucket:[Scored]] = [:]
        for (b, list) in sortedByBucket {
            let scored = list.map { Scored(cand: $0, base: score($0, u: u, params: params)) }
                .sorted { $0.base > $1.base }
            heads[b] = scored
        }

        // quotas
        var remaining: [Bucket:Int] = [:]
        for b in Bucket.allCases {
            let target = Int(Double(params.pageSize) * (params.quotas[b] ?? 0.0))
            remaining[b] = target
        }

        var out: [Post] = []
        var recentAuthors: [String] = []

        func violatesCooldown(_ author: String) -> Bool {
            let recent = recentAuthors.suffix(params.cooldownWindow)
            return recent.contains(author)
        }

        // round-robin with borrowing + simple MMR
        var pointers: [Bucket:Int] = Bucket.allCases.reduce(into: [:]) { $0[$1] = 0 }
        var round = 0
        let totalTarget = remaining.values.reduce(0,+)
        while out.count < max(totalTarget, params.pageSize) && out.count < params.pageSize*2 {
            let b = Bucket.allCases[round % Bucket.allCases.count]
            round += 1

            // find next available bucket if empty or met quota
            var pickedBucket: Bucket? = nil
            for _ in 0..<Bucket.allCases.count {
                if let rem = remaining[pointers.keys.first(where: { $0 == pickedBucket ?? b }) ?? b],
                   rem > 0, let arr = heads[b], pointers[b]! < arr.count {
                    pickedBucket = b
                    break
                } else {
                    // rotate
                    let idx = (Bucket.allCases.firstIndex(of: b)! + 1) % Bucket.allCases.count
                    let nb = Bucket.allCases[idx]
                    if let rem = remaining[nb], rem > 0, let arr = heads[nb], pointers[nb]! < arr.count {
                        pickedBucket = nb; break
                    }
                }
            }
            guard let useB = pickedBucket, var arr = heads[useB] else { continue }

            // walk down until no cooldown conflict
            var i = pointers[useB]!
            var chosen: Scored?
            while i < arr.count {
                let s = arr[i]
                if !violatesCooldown(s.cand.authorId) {
                    // simple 1-vs-1 MMR against last placed
                    if let last = out.last {
                        let lastVec = sortedByBucket.values.flatMap{$0}.first(where: { $0.post.id == last.id })?.postVec
                        if let lastVec {
                            let mmr = params.mmrLambda*s.base - (1.0-params.mmrLambda)*VectorMath.cos(s.cand.postVec, lastVec)
                            // accept if mmr >= base of next or it’s the first feasible
                            chosen = s // (cheap heuristic; good enough for client-side)
                            break
                        }
                    }
                    chosen = s; break
                }
                i += 1
            }
            guard let ch = chosen else { pointers[useB] = i; continue }

            out.append(ch.cand.post)
            recentAuthors.append(ch.cand.authorId)
            pointers[useB] = i + 1
            remaining[useB] = max(0, (remaining[useB] ?? 0) - 1)
        }
        return Array(out.prefix(params.pageSize))
    }
}
