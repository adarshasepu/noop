import Foundation

/// Spec §12: age and ancestry change DISPLAY, cold-start text, HR zones and caveats only.
/// They are never inputs to `Decision`; the engine has a test that proves it.
public struct HrMaxEstimate: Codable, Equatable, Sendable {
    public var bpm: Double
    public var uncertaintyBpm: Double
    public var measured: Bool
    public var lowConfidence: Bool
    /// Zone upper bounds Z1..Z4 in bpm (Z5 is above the last).
    public var zoneTopsBpm: [Double]
}

public enum AgeAncestry {
    public static func hrMax(_ p: UserProfile, _ c: AdaptiveConfig) -> HrMaxEstimate? {
        let bpm: Double, measured: Bool
        if let m = p.measuredHrMax { bpm = m; measured = true }
        else if let a = p.ageYears { bpm = c.hrmaxIntercept - c.hrmaxSlope * Double(a); measured = false }   // Tanaka [ROY2015][NIK2018]
        else { return nil }
        return HrMaxEstimate(bpm: bpm, uncertaintyBpm: measured ? 0 : c.hrmaxUncertaintyBpm, measured: measured,
                             lowConfidence: !measured && (p.ageYears ?? 30) < 18,
                             zoneTopsBpm: c.zoneTopsPctHrmax.map { bpm * $0 / 100 })
    }

    public static func displayNorm(_ p: UserProfile, _ c: AdaptiveConfig) -> (rmssdMs: Double, caveat: String)? {
        guard let anc = p.ancestry, let age = p.ageYears,
              let n = c.displayNorms.first(where: { $0.ancestry == anc && age >= $0.minAge && age <= $0.maxAge }) else { return nil }
        let v: Double? = p.sex == "male" ? n.rmssdMale : p.sex == "female" ? n.rmssdFemale : n.rmssdAll
        return v.map { ($0, n.caveat) }
    }

    static func coldStartNote(_ p: UserProfile) -> String {
        var s = "Building your baseline: we compare you only with yourself, so we need about 2 weeks of morning readings first."
        if p.ageYears != nil { s += " HRV is usually lower with age; that is normal and only your own changes count." }
        return s
    }

    static func infoCards(_ p: UserProfile, _ c: AdaptiveConfig) -> [String] {
        var cards: [String] = []
        if p.ancestry == "South Asian" {   // [HUS2013][AGA2023], opt-in, severity unchanged
            cards.append("People of South Asian ancestry can develop heart and metabolic risk earlier. Consider asking your doctor about early screening (blood pressure, lipids, glucose). This does not change your recovery advice.")
        }
        if let a = p.ageYears, a >= c.olderNoiseCaveatAge {
            cards.append("Wrist readings may be noisier with age; we use quality checks and may ask you to re-measure.")   // [COS2025]
        }
        return cards
    }
}
