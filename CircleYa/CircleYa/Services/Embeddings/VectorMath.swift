// CircleYa/Services/Embeddings/VectorMath.swift
import Foundation

enum VectorMath {
    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        var s = 0.0
        for i in 0..<n { s += a[i] * b[i] }
        return s
    }
    static func norm(_ a: [Double]) -> Double {
        sqrt(max(1e-12, a.reduce(0.0) { $0 + $1*$1 }))
    }
    static func normalize(_ a: [Double]) -> [Double] {
        let n = norm(a)
        return a.map { $0 / n }
    }
    static func cos(_ a: [Double], _ b: [Double]) -> Double {
        let d = dot(a, b)
        let na = norm(a), nb = norm(b)
        return d / max(1e-12, na*nb)
    }
}
