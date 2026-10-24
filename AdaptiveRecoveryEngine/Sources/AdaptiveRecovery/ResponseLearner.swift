import Foundation

/// Per-user learning hooks (spec §5, research flag G15). OFF by default; output goes to
/// `Assessment.research` and is never read by the decision unless `learningAffectsDecisions`.
public enum ResponseLearner {
    /// Per-family recovery cost: EWMA of Δx = ln rMSSD(t+1) − roll7(t) after a session of that family,
    /// shrunk towards the profile prior (0) with k = shrinkageK.
    public static func costs(history: [DayRecord], assessments: [Assessment], config c: AdaptiveConfig, cohort: CohortPrior? = nil) -> [String: (cost: Double, n: Int)] {
        var byDay: [Int: Assessment] = [:]; for a in assessments { byDay[a.day] = a }
        var lnBy: [Int: Double] = [:]; for r in history { if let v = r.rmssdMs, v > 0 { lnBy[r.day] = log(v) } }
        var ewma: [String: Double] = [:], n: [String: Int] = [:]
        for r in history.sorted(by: { $0.day < $1.day }) {
            guard let s = r.sessions.max(by: { $0.load < $1.load }), let roll = byDay[r.day]?.metrics.roll7, let next = lnBy[r.day + 1] else { continue }
            let f = ProfileClassifier.family(of: s.type, c), dx = next - roll
            ewma[f] = ewma[f].map { (1 - c.learningEwmaAlpha) * $0 + c.learningEwmaAlpha * dx } ?? dx
            n[f, default: 0] += 1
        }
        var out: [String: (Double, Int)] = [:]
        for (f, v) in ewma { let prior = cohort?.recoveryCostByFamily[f] ?? 0   // cohort prior (§13) else profile prior 0
            out[f] = (ProfileClassifier.shrink(personal: v, profile: prior, nObs: n[f]!, k: cohort == nil ? c.shrinkageK : c.cohortShrinkageK), n[f]!) }
        return out
    }

    static func attach(to out: inout [Assessment], byDay: [Int: DayRecord], profile: UserProfile, config c: AdaptiveConfig, cohort: CohortPrior?) {
        let hist = Array(byDay.values)
        for i in out.indices {
            let upTo = hist.filter { $0.day <= out[i].day }
            for (f, v) in costs(history: upTo, assessments: Array(out[...i]), config: c, cohort: cohort) {
                out[i].research["cost.\(f)"] = v.cost; out[i].research["n.\(f)"] = Double(v.n)
            }
        }
    }
}
