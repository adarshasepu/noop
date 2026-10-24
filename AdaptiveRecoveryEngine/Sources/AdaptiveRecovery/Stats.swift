import Foundation

enum Stats {
    static func mean(_ x: [Double]) -> Double? { x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }
    /// Sample SD (n-1), matching Excel STDEV.
    static func sd(_ x: [Double]) -> Double? {
        guard x.count >= 2, let m = mean(x) else { return nil }
        return (x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)).squareRoot()
    }
    /// OLS slope of y over x.
    static func slope(_ pts: [(Double, Double)]) -> Double? {
        guard pts.count >= 3 else { return nil }
        let mx = pts.map(\.0).reduce(0, +) / Double(pts.count), my = pts.map(\.1).reduce(0, +) / Double(pts.count)
        let num = pts.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = pts.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
        return den > 0 ? num / den : nil
    }
}
