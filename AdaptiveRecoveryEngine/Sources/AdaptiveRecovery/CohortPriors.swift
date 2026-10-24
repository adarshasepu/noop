import Foundation

/// Hook for the cohort layer (spec §13, in progress): partial-pooling priors from similar users.
/// This package does NO networking or data sharing; a provider is whatever the app injects
/// (e.g. a table shipped in the app bundle). The default provider returns nil for everything.
public struct CohortPrior: Codable, Equatable, Sendable {
    public var lnRmssdMean: Double?
    public var lnRmssdSD: Double?
    /// Per session family: expected next-day Δ ln rMSSD.
    public var recoveryCostByFamily: [String: Double]
    public init(lnRmssdMean: Double? = nil, lnRmssdSD: Double? = nil, recoveryCostByFamily: [String: Double] = [:]) {
        self.lnRmssdMean = lnRmssdMean; self.lnRmssdSD = lnRmssdSD; self.recoveryCostByFamily = recoveryCostByFamily
    }
}

public protocol CohortPriorProvider: Sendable {
    /// Prior for this user (profile + resolved family). Return nil for "no cohort information".
    func prior(for profile: UserProfile, family: String) -> CohortPrior?
}

public struct NoCohortPriors: CohortPriorProvider {
    public init() {}
    public func prior(for profile: UserProfile, family: String) -> CohortPrior? { nil }
}

public enum CohortBlend {
    /// Individual weight w = n / (n + k); value = w·individual + (1 − w)·prior.
    public static func blend(individual: Double, prior: Double?, n: Int, k: Double) -> Double {
        guard let prior, k > 0 else { return individual }
        let w = Double(n) / (Double(n) + k)
        return w * individual + (1 - w) * prior
    }
}
