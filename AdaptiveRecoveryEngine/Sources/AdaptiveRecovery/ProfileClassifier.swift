import Foundation

public enum Modifier: String, Codable, Sendable, CaseIterable {
    case masters, youth, beginner, weekendWarrior, femaleCycle, pregnant, shiftWorker, clinical, weightCut, eliteSaturationWatch
}

public struct ResolvedProfile: Codable, Equatable, Sendable {
    /// Final family shares after quiz-prior/observed blend (spec §8).
    public var shares: [String: Double]
    public var primaryFamily: String
    public var isHybrid: Bool
    public var observedSessions: Int
    public var quizWeight: Double
    public var modifiers: Set<Modifier>
    // blended parameters (§7.4)
    public var expectedDipDays: Double
    public var nmCheck: Bool
    public var sorenessCheck: Bool
    public var cvRule: Bool
    public var baselineWindowDays: Int
    public var artifactK: Double
}

public enum ProfileClassifier {

    public static func family(of activity: String, _ c: AdaptiveConfig) -> String {
        c.sessionComponents[activity]?.family ?? c.activityFamily[activity] ?? "GENERAL"
    }
    /// (family, sRPE×min) pairs for a session, split by component when components are given.
    public static func familyLoads(_ s: Session, _ c: AdaptiveConfig) -> [(String, Double)] {
        s.components.isEmpty ? [(family(of: s.type, c), s.load)] : s.components.map { (family(of: $0.type, c), $0.minutes * $0.sRPE) }
    }

    /// Quiz prior: primary 0.6, secondaries split 0.4; no secondaries -> primary 1.0 (EC, §8).
    public static func quizPrior(_ p: UserProfile, _ c: AdaptiveConfig) -> [String: Double] {
        guard let q1 = p.primaryActivity else { return [:] }
        var prior: [String: Double] = [:]
        let secondaries = Array(p.secondaryActivities.prefix(3))
        if secondaries.isEmpty { prior[family(of: q1, c)] = 1.0; return prior }
        prior[family(of: q1, c), default: 0] += c.quizPrimaryPrior
        for a in secondaries { prior[family(of: a, c), default: 0] += (1 - c.quizPrimaryPrior) / Double(secondaries.count) }
        return prior
    }

    public static func resolve(profile p: UserProfile, history: [DayRecord], asOf day: Int, config c: AdaptiveConfig) -> ResolvedProfile {
        let lo = day - c.classifierWindowDays + 1
        let window = history.filter { $0.day >= lo && $0.day <= day }
        var famLoad: [String: Double] = [:]; var wkendLoad = 0.0, total = 0.0, n = 0, weekdaySessions = 0
        for r in window {
            for s in r.sessions {
                n += 1
                for (f, l) in familyLoads(s, c) { famLoad[f, default: 0] += l }
                total += s.load
                if DayIndex.weekday(r.day) >= 5 { wkendLoad += s.load } else { weekdaySessions += 1 }
            }
        }
        var observed: [String: Double] = [:]
        if total > 0 { for (f, l) in famLoad { observed[f] = l / total } }
        let prior = quizPrior(p, c)
        // §8: w_obs = min(1, n / 20); with no quiz, observed only (after minSessions), else GENERAL.
        var wObs = min(1.0, Double(n) / Double(max(c.quizTakeoverSessions, 1)))
        if prior.isEmpty { wObs = n >= c.minSessionsToClassify ? 1 : 0 }
        if observed.isEmpty { wObs = 0 }
        var shares: [String: Double] = [:]
        for f in Set(prior.keys).union(observed.keys) {
            shares[f] = (1 - wObs) * (prior[f] ?? 0) + wObs * (observed[f] ?? 0)
        }
        if shares.isEmpty { shares = ["GENERAL": 1] }
        let primary = shares.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }!.key
        let isHybrid = (shares[primary] ?? 0) < c.singleProfileShare
        // §7.4 blend: numeric = share-weighted over included families; booleans = OR (most conservative)
        let included = isHybrid ? shares.filter { $0.value >= c.hybridInclusionShare } : [primary: 1.0]
        let wsum = included.values.reduce(0, +)
        var dip = 0.0; var nm = false, sore = false, cv = false
        for (f, w) in included {
            let fp = c.families[f] ?? c.families["GENERAL"] ?? FamilyParams(expectedDipDays: 1)
            dip += fp.expectedDipDays * w / max(wsum, 1e-9)
            nm = nm || fp.nmCheck; sore = sore || fp.sorenessCheck; cv = cv || fp.cvRule
        }
        if let q1 = p.primaryActivity, let sub = FamilyParams.subtypeDipDays[q1], family(of: q1, c) == primary { dip = max(dip, sub) }

        var mods = Set<Modifier>()
        if let a = p.ageYears { if a >= c.mastersAge { mods.insert(.masters) }; if a < 18 { mods.insert(.youth) } }
        if (p.trainingYears ?? 99) < c.beginnerMaxTrainingYears || (p.sessionsPerWeek ?? 99) < 2 { mods.insert(.beginner) }
        let weeks = Double(c.classifierWindowDays) / 7
        if p.mostlyWeekends || (total > 0 && wkendLoad / total >= c.weekendWarriorShare && Double(weekdaySessions) / weeks <= c.weekendWarriorMaxWeekdaySessionsPerWeek) {
            mods.insert(.weekendWarrior)
        }
        if p.tracksCycle { mods.insert(.femaleCycle) }
        if p.pregnantOrPostpartum { mods.insert(.pregnant) }
        if p.clinicalCondition { mods.insert(.clinical) }
        if p.shiftWorker { mods.insert(.shiftWorker) }
        if p.cutsWeight { mods.insert(.weightCut) }
        if p.primaryActivity == "Rowing" || (primary == "ENDURANCE" && (p.sessionsPerWeek ?? 0) >= 6) { mods.insert(.eliteSaturationWatch) }
        if mods.contains(.masters) { dip += c.mastersExtraDipDays }

        return ResolvedProfile(shares: shares, primaryFamily: primary, isHybrid: isHybrid, observedSessions: n, quizWeight: 1 - wObs,
                               modifiers: mods, expectedDipDays: dip, nmCheck: nm, sorenessCheck: sore, cvRule: cv,
                               baselineWindowDays: mods.contains(.beginner) ? c.beginnerBaselineDays : c.baselineWindowDays,
                               artifactK: mods.contains(.masters) ? c.artifactKMasters : c.artifactK)
    }

    /// §7.5 shrinkage: c_user = n/(n+k)·personal + k/(n+k)·profile.
    public static func shrink(personal: Double, profile: Double, nObs: Int, k: Double) -> Double {
        let n = Double(nObs); return (n / (n + k)) * personal + (k / (n + k)) * profile
    }
}
