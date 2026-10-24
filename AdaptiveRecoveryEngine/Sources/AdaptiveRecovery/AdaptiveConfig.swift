import Foundation

// AdaptiveConfig — EVERY tunable number of the adaptive engine lives here, nowhere else.
//
// Three ways to change behaviour without touching engine code:
//   1. `AdaptiveConfig.bundled()` reads the bundled `Resources/params.json` (the research
//      `params.json`, `{value, ec, sources}` format) and maps every key it knows onto this struct.
//   2. `AdaptiveConfig.load(paramsJSON:)` does the same for any params.json the app ships or downloads.
//   3. `AdaptiveConfig.merging(overrideJSON:)` deep-merges a JSON object in THIS struct's own
//      (camelCase) shape over the current values; keys you omit keep their defaults.
// Swift defaults below mirror hrv-algorithm-spec.md v0.6. `EC` = engineering choice (no source).

public struct AdaptiveConfig: Codable, Equatable, Sendable {

    public enum RangeMethod: String, Codable, Sendable {
        /// METHOD_A [F2019C]: band = cvMultiplier * CV_base% of base_mu, floored at device error. DEFAULT.
        case cvSWC
        /// METHOD_B [A-P2021]: band = ln(1 + swcHrvPct/100).
        case fixedSWC
        /// METHOD_C (HRV4Training-style): band = m * SD_base (m EC). The spreadsheet tab uses this.
        case sdBand
    }
    public enum DecisionRule: String, Codable, Sendable {
        /// v0.5 §11 multi-marker vote: RECOVER needs >= votesRequiredForRecover of {HRV low, RHR high, wellness bad}. DEFAULT.
        case multiMarkerVote
        /// v0.1 §3 core rule, exactly as the 'Adaptive HRV' spreadsheet tab computes it (parity/testing).
        case coreV01
    }

    // MARK: feature flag
    /// Master switch. OFF by default: the legacy RecoveryScorer stays the shipped score.
    public var engineEnabled: Bool = false

    // MARK: baseline / range
    public var rollingDays: Int = 7                    // [P2012][A-G2]
    public var minReadingsInRolling: Int = 3           // [P2014]
    public var baselineWindowDays: Int = 60            // EC
    public var minBaselineDays: Int = 14               // EC [SEI-X2025][MAN2021]
    public var rangeMethod: RangeMethod = .cvSWC
    public var cvMultiplier: Double = 0.5              // [F2019C][FLA2018]
    public var swcHrvPct: Double = 3                   // [A-P2021]
    public var sdMultiplierM: Double = 0.5             // EC (METHOD_C)
    public var deviceErrorHrvPct: Double = 6           // [BEL2021] PPG LOA; floor of the HRV band
    public var rhrBandPct: Double = 2                  // [A-P2021]
    public var deviceErrorRhrPct: Double = 0           // EC; rhr band = max(rhrBandPct, this)
    public var cvScatterMultiplier: Double = 1.25      // EC [SCH2013]
    public var trendWindowDays: Int = 14               // EC
    /// A trend counts only if roll7 moved more than this fraction of the HRV band over the trend window. EC.
    public var trendMinChangeFractionOfBand: Double = 1.0
    /// Readings above upper_normal + k·SD prompt a re-measure and are kept out of the baseline (EC [A-ARR]).
    public var qualityGateEnabled: Bool = true
    public var artifactK: Double = 1.5                 // EC [A-ARR]
    public var artifactKMasters: Double = 1.0          // EC stricter for masters [A-ARR]

    // MARK: decision
    public var decisionRule: DecisionRule = .multiMarkerVote
    public var votesRequiredForRecover: Int = 2        // EC [NUU2024][BUC2014]
    public var aboveRangeIsGreen: Bool = false         // never auto-escalate [MR2021][A-PUSH]
    public var wellnessWindowDays: Int = 28            // EC
    public var wellnessMinDays: Int = 7                // EC
    public var wellnessBadZ: Double = -0.5             // [FLA2018]
    public var wellnessGoodZ: Double = 0.5
    /// Legacy single 1-5 subjective score: "bad" at or below this (spreadsheet parity). EC.
    public var subjectiveSingleBadAtOrBelow: Double = 2
    public var persistentLowReferDays: Int = 21        // EC [F2021FB]
    public var persistentReferDays: Int = 14           // EC [CAR2022][SCW2016]
    public var illnessRespSD: Double = 1.0             // EC [MIL2020]
    public var illnessRespWindowDays: Int = 28         // EC
    public var shortSleepHours: Double = 6.0           // EC context only [MIL2022]
    public var acwrIsDecisionInput: Bool = false       // NEVER true [DIN2026][IMP2023]

    // MARK: training load
    public var acuteDays: Int = 7
    public var chronicDays: Int = 28
    public var rirFactors: [Double] = [1.0, 0.8, 0.7, 0.6]   // index = RIR (3+ uses last). EC [HEL2016][REF2023]

    // MARK: profiles
    public var classifierWindowDays: Int = 28          // EC
    public var singleProfileShare: Double = 0.6        // EC
    public var hybridInclusionShare: Double = 0.15     // EC
    public var minSessionsToClassify: Int = 8          // EC
    public var quizPrimaryPrior: Double = 0.6          // EC
    public var quizTakeoverSessions: Int = 20          // EC
    public var weekendWarriorShare: Double = 0.6       // EC
    public var weekendWarriorMaxWeekdaySessionsPerWeek: Double = 1
    public var beginnerMaxTrainingYears: Double = 0.5
    public var beginnerBaselineDays: Int = 28          // EC [NAV2022]
    public var mastersAge: Int = 40                    // EC
    public var mastersExtraDipDays: Double = 1         // EC [LI2024][BOR2025]
    public var shrinkageK: Double = 20                 // EC
    public var families: [String: FamilyParams] = FamilyParams.defaults
    /// Activity / subtype (quiz Q1 or logged session type) -> family.
    public var activityFamily: [String: String] = FamilyParams.defaultActivityFamily

    /// Session component kinds (spec §14 hook): component type -> family + its native load metric.
    /// Add rows here (or via params.json `engine_overrides`) to support new component kinds.
    public var sessionComponents: [String: ComponentSpec] = ComponentSpec.defaults

    // MARK: substances
    public var changePointWindowDays: Int = 14         // EC
    public var changePointRangeMultiplier: Double = 1.5 // EC
    public var alcoholExcludeNextDay: Bool = true      // EC [A-P2021]
    public var substances: [SubstanceRule] = SubstanceRule.defaults

    // MARK: altitude
    public var altitudeTripDeltaM: Double = 1000
    public var altitudeVisitorAbsoluteM: Double = 2000
    public var altitudeLowHomeM: Double = 500
    public var altitudeResidentDays: Int = 14
    public var altitudeAcclimatizationDays: Int = 14   // [PIR2025]
    public var altitudeRangeMultiplier: Double = 1.5
    public var altitudeNoRedAlone: Bool = true
    public var altitudeReturnAnnotateDays: Int = 7

    // MARK: age / ancestry (spec §12) — display, cold start, zones, caveats only
    public var hrmaxIntercept: Double = 208            // Tanaka [ROY2015][NIK2018]
    public var hrmaxSlope: Double = 0.7
    public var hrmaxUncertaintyBpm: Double = 10        // [KAS2023]
    public var zoneTopsPctHrmax: [Double] = [70, 80, 87, 93]   // EC
    public var olderNoiseCaveatAge: Int = 60           // EC [COS2025]
    /// Hard lock: ancestry is never a decision input. The engine asserts this; flipping it has no effect.
    public var ancestryChangesSeverity: Bool = false
    public var displayNorms: [DisplayNorm] = DisplayNorm.defaults

    // MARK: cohort layer (spec §13 hook) — off by default, no data sharing
    public var cohortPriorsEnabled: Bool = false
    public var cohortShrinkageK: Double = 20           // EC: individual weight n/(n+k)

    // MARK: per-user learning (research flag)
    public var learningEnabled: Bool = false           // research flag G15, OFF
    public var learningAffectsDecisions: Bool = false  // even when learning runs, log only
    public var learningEwmaAlpha: Double = 0.2         // EC

    public init() {}
}

public struct FamilyParams: Codable, Equatable, Sendable {
    public var expectedDipDays: Double
    public var nmCheck: Bool
    public var sorenessCheck: Bool
    public var cvRule: Bool
    public var wRatio: Double
    public var multiDayTrigger: Int     // swimmers: consecutive high-volume days before a dip is meaningful [KAM2020]
    public init(expectedDipDays: Double, nmCheck: Bool = false, sorenessCheck: Bool = false,
                cvRule: Bool = true, wRatio: Double = 0, multiDayTrigger: Int = 0) {
        self.expectedDipDays = expectedDipDays; self.nmCheck = nmCheck; self.sorenessCheck = sorenessCheck
        self.cvRule = cvRule; self.wRatio = wRatio; self.multiDayTrigger = multiDayTrigger
    }
    public static let defaults: [String: FamilyParams] = [
        "GENERAL": .init(expectedDipDays: 1),
        "ENDURANCE": .init(expectedDipDays: 2),                       // EC from dose [HYN2010]
        "METCON": .init(expectedDipDays: 1, sorenessCheck: true),     // [DEB2021][F2019RT]
        "OLY": .init(expectedDipDays: 1, nmCheck: true, sorenessCheck: true),        // [F2019RT]
        "STRENGTH": .init(expectedDipDays: 1, nmCheck: true, sorenessCheck: true),   // [F2019RT][WIL2020]
        "HYPERTROPHY": .init(expectedDipDays: 1, nmCheck: true, sorenessCheck: true),
        "TEAM": .init(expectedDipDays: 1.5),                          // [F2017S][EDM2018]
        "LOW_LOAD": .init(expectedDipDays: 0),
    ]
    public static let defaultActivityFamily: [String: String] = [
        "Running": "ENDURANCE", "Road/indoor cycling": "ENDURANCE", "Spin/Peloton class": "METCON",
        "Swimming (pool)": "ENDURANCE", "Open-water swim": "ENDURANCE", "Triathlon/multisport": "ENDURANCE",
        "Rowing": "ENDURANCE", "Hiking/mountaineering": "ENDURANCE", "Ultra/trail running": "ENDURANCE",
        "Skiing/snowboarding": "ENDURANCE", "Zone 2": "ENDURANCE",
        "Team sport": "TEAM", "Rec league (basketball/soccer)": "TEAM", "Racquet sports": "TEAM", "Dance": "TEAM",
        "Golf": "LOW_LOAD", "Yoga/Pilates": "LOW_LOAD",
        "CrossFit/HIFT": "METCON", "CrossFit/metcon": "METCON", "HIIT": "METCON",
        "HR-zone class (Orangetheory/F45/boot camp)": "METCON", "Hyrox/kettlebell/calisthenics": "METCON",
        "Combat sport (boxing/kickboxing/Muay Thai/MMA/BJJ/wrestling)": "METCON",
        "Olympic lifting": "OLY", "Powerlifting": "STRENGTH", "Strongman": "STRENGTH", "Strength": "STRENGTH",
        "Climbing/bouldering": "STRENGTH", "Bodybuilding/hypertrophy": "HYPERTROPHY", "Hypertrophy": "HYPERTROPHY",
        "General fitness": "GENERAL", "Not active yet": "GENERAL",
    ]
    /// Subtype-specific expected dip (days), overriding the family value (athlete-profiles.md).
    public static let subtypeDipDays: [String: Double] = [
        "Ultra/trail running": 7,   // [PAE2021]
        "Dance": 1.5,               // [EDM2018]
    ]
}

public enum LoadMethod: String, Codable, Sendable { case sRPEMinutes, tonnage, effectiveSets }

public struct ComponentSpec: Codable, Equatable, Sendable {
    public var family: String
    /// Native metric shown for this component; blending/comparison always uses sRPE × min [HAD2017].
    public var loadMethod: LoadMethod
    public init(family: String, loadMethod: LoadMethod) { self.family = family; self.loadMethod = loadMethod }
    public static let defaults: [String: ComponentSpec] = [   // EC placeholders until spec §14 lands
        "heavy_strength": .init(family: "STRENGTH", loadMethod: .tonnage),
        "olympic": .init(family: "OLY", loadMethod: .tonnage),
        "gymnastics_skill": .init(family: "METCON", loadMethod: .sRPEMinutes),
        "metcon_short": .init(family: "METCON", loadMethod: .sRPEMinutes),
        "metcon_medium": .init(family: "METCON", loadMethod: .sRPEMinutes),
        "metcon_long": .init(family: "METCON", loadMethod: .sRPEMinutes),
        "aerobic": .init(family: "ENDURANCE", loadMethod: .sRPEMinutes),
        "test_day": .init(family: "METCON", loadMethod: .sRPEMinutes),
    ]
}

public enum SubstanceAction: String, Codable, Sendable { case annotate, timing, changePoint, disableRefer }

public struct SubstanceRule: Codable, Equatable, Sendable {
    public var id: String
    public var chronic: Bool
    public var timing: Bool
    public var action: SubstanceAction
    public var note: String
    public init(_ id: String, chronic: Bool, timing: Bool, _ action: SubstanceAction, _ note: String) {
        self.id = id; self.chronic = chronic; self.timing = timing; self.action = action; self.note = note
    }
    // supplements-medications.md table. Grades/tags are in that file.
    public static let defaults: [SubstanceRule] = [
        .init("nitrate_beetroot", chronic: false, timing: false, .annotate, "mixed results [BON2014][CAR2021b]"),
        .init("arginine", chronic: false, timing: false, .annotate, "no post-exercise change [POR2024]"),
        .init("citrulline", chronic: false, timing: false, .annotate, "no HRV study (gap)"),
        .init("caffeine", chronic: false, timing: true, .timing, "measure before caffeine [GON2017]"),
        .init("pre_workout", chronic: false, timing: true, .timing, "measure before; palpitations -> doctor [ALS2015]"),
        .init("creatine", chronic: false, timing: false, .annotate, "no clear HRV effect"),
        .init("beta_alanine", chronic: false, timing: false, .annotate, "no HRV study (gap)"),
        .init("electrolytes", chronic: false, timing: false, .annotate, "hypohydration lowers HRV [YOU2019]"),
        .init("magnesium", chronic: false, timing: false, .annotate, "no oral HRV study (gap)"),
        .init("omega3", chronic: true, timing: false, .changePoint, "may raise HRV [CHR2011]"),
        .init("adaptogens", chronic: false, timing: false, .annotate, "no HRV study (gap)"),
        .init("melatonin", chronic: true, timing: false, .changePoint, "[CAM2020]"),
        .init("cbd", chronic: false, timing: false, .annotate, "[WIL2021]"),
        .init("cannabis", chronic: false, timing: false, .annotate, "no study found"),
        .init("alcohol", chronic: false, timing: false, .annotate, "HRV -12% next morning [A-P2021]"),
        .init("nicotine", chronic: true, timing: false, .changePoint, "RMSSD -8.9%/10 g/day [MUR2019]"),
        .init("fat_burner", chronic: false, timing: true, .timing, "stimulant; palpitations -> doctor"),
        .init("adhd_stimulant", chronic: true, timing: true, .changePoint, "[DOL2018]"),
        .init("ssri_snri", chronic: true, timing: false, .changePoint, "[VAN2008]"),
        .init("antihistamine", chronic: false, timing: false, .annotate, "no study found"),
        .init("decongestant", chronic: false, timing: true, .timing, "illness context"),
        .init("thyroid_med", chronic: true, timing: false, .changePoint, "[BRU2022]"),
        .init("untreated_thyroid", chronic: true, timing: false, .disableRefer, "[BRU2022] safety EC"),
        .init("beta_blocker", chronic: true, timing: false, .disableRefer, "HR rules meaningless [TAN2018][DEH2009]"),
        .init("bp_med", chronic: true, timing: false, .changePoint, "[MAC2020]"),
        .init("bp_unstable", chronic: true, timing: false, .disableRefer, "safety EC"),
        .init("inhaler", chronic: false, timing: true, .timing, "[BOK2020]"),
        .init("testosterone_aas_sarms", chronic: true, timing: false, .disableRefer, "medical supervision flag"),
        .init("glp1", chronic: true, timing: false, .changePoint, "use HRV:HR [A-NORM][BAG2017]"),
    ]
}

public struct DisplayNorm: Codable, Equatable, Sendable {
    public var ancestry: String
    public var minAge: Int
    public var maxAge: Int
    public var method: String
    public var rmssdMale: Double?
    public var rmssdFemale: Double?
    public var rmssdAll: Double?
    public var caveat: String
    public static let defaults: [DisplayNorm] = [
        .init(ancestry: "South Asian", minAge: 18, maxAge: 30, method: "short_supine",
              rmssdMale: 57.4, rmssdFemale: 64.9, rmssdAll: 61.6,
              caveat: "One study of young South Indian adults, short lying-down recordings [KUN2021]; a different method from your wearable. For context only.")
    ]
}

// MARK: - Loading

public enum AdaptiveConfigError: Error { case notAnObject }

extension AdaptiveConfig {

    /// Defaults + the bundled params.json.
    public static func bundled() -> AdaptiveConfig {
        guard let url = Bundle.module.url(forResource: "params", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cfg = try? AdaptiveConfig().applyingParams(data) else { return AdaptiveConfig() }
        return cfg
    }

    public static func load(paramsJSON data: Data) throws -> AdaptiveConfig {
        try AdaptiveConfig().applyingParams(data)
    }

    /// Deep-merge a JSON object in this struct's own shape over the current values.
    public func merging(overrideJSON data: Data) throws -> AdaptiveConfig {
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        guard var b = base as? [String: Any],
              let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdaptiveConfigError.notAnObject }
        b = Self.deepMerge(b, o)
        return try JSONDecoder().decode(AdaptiveConfig.self, from: JSONSerialization.data(withJSONObject: b))
    }

    static func deepMerge(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
        var r = a
        for (k, v) in b {
            if let av = r[k] as? [String: Any], let bv = v as? [String: Any] { r[k] = deepMerge(av, bv) } else { r[k] = v }
        }
        return r
    }

    /// Map the research `params.json` ({value, ec, sources}) onto this struct. Unknown keys are ignored,
    /// so the research file can grow without breaking the app. An optional top-level `engine_overrides`
    /// object (this struct's own shape) is merged last.
    public func applyingParams(_ data: Data) throws -> AdaptiveConfig {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdaptiveConfigError.notAnObject }
        func node(_ path: String) -> Any? {
            var cur: Any? = root
            for p in path.split(separator: ".") { cur = (cur as? [String: Any])?[String(p)] }
            if let d = cur as? [String: Any], d.keys.contains("value") { return d["value"] }
            return cur
        }
        func num(_ p: String) -> Double? { (node(p) as? NSNumber)?.doubleValue }
        func bool(_ p: String) -> Bool? { (node(p) as? NSNumber)?.boolValue }
        var c = self
        if let v = num("baseline.rolling_mean_days") { c.rollingDays = Int(v) }
        if let v = num("baseline.baseline_window_days") { c.baselineWindowDays = Int(v) }
        if let v = num("baseline.min_readings_per_week") { c.minReadingsInRolling = Int(v) }
        if let v = num("baseline.min_history_days_before_decisions") { c.minBaselineDays = Int(v) }
        if let v = num("baseline.normal_range.METHOD_A_cv_multiplier") { c.cvMultiplier = v }
        if let v = num("baseline.normal_range.METHOD_B_swc_hrv_pct") { c.swcHrvPct = v }
        if let v = num("baseline.normal_range.METHOD_B_swc_rhr_pct") { c.rhrBandPct = v }
        if let v = num("baseline.device_loa_hrv_ppg_pct") { c.deviceErrorHrvPct = v }
        if let v = num("baseline.cv_scatter_multiplier") { c.cvScatterMultiplier = v }
        if let v = bool("decision.above_range_is_green") { c.aboveRangeIsGreen = v }
        if let v = num("decision.votes_required_for_recover") { c.votesRequiredForRecover = Int(v) }
        if let v = num("decision.wellness_window_days") { c.wellnessWindowDays = Int(v) }
        if let v = num("decision.wellness_bad_z") { c.wellnessBadZ = v }
        if let v = num("decision.persistent_refer_days") { c.persistentReferDays = Int(v) }
        if let v = num("decision.illness_rr_sd") { c.illnessRespSD = v }
        if let v = bool("decision.acwr_decision_input") { c.acwrIsDecisionInput = v }
        if let v = num("profiles.single_profile_share") { c.singleProfileShare = v }
        if let v = num("profiles.hybrid_inclusion_share") { c.hybridInclusionShare = v }
        if let v = num("profiles.weekend_warrior_share") { c.weekendWarriorShare = v }
        if let v = num("profiles.shrinkage_k") { c.shrinkageK = v }
        if let v = num("profiles.quiz_prior_n_full") { c.quizTakeoverSessions = Int(v) }
        if let v = num("profiles.quiz_prior_primary_share") { c.quizPrimaryPrior = v }
        if let v = num("profiles.masters_age") { c.mastersAge = Int(v) }
        if let v = num("profiles.masters_extra_dip_days") { c.mastersExtraDipDays = v }
        if let r = node("profiles.strength_rir_factor") as? [String: Any] {
            let keys = ["0", "1", "2", "3+"]
            let vals = keys.compactMap { (r[$0] as? NSNumber)?.doubleValue }
            if vals.count == 4 { c.rirFactors = vals }
        }
        if let v = num("substances.change_point_window_days") { c.changePointWindowDays = Int(v) }
        if let v = num("substances.change_point_range_multiplier") { c.changePointRangeMultiplier = v }
        if let v = bool("substances.alcohol_exclude_next_day") { c.alcoholExcludeNextDay = v }
        if let ids = node("substances.disable_refer") as? [String] {
            for id in ids {
                if let i = c.substances.firstIndex(where: { $0.id == id }) { c.substances[i].action = .disableRefer }
                else { c.substances.append(.init(id, chronic: true, timing: false, .disableRefer, "from params.json")) }
            }
        }
        if let v = num("altitude.trip_delta_m") { c.altitudeTripDeltaM = v }
        if let v = num("altitude.visitor_absolute_m") { c.altitudeVisitorAbsoluteM = v }
        if let v = num("altitude.low_home_m") { c.altitudeLowHomeM = v }
        if let v = num("altitude.resident_days") { c.altitudeResidentDays = Int(v) }
        if let v = num("altitude.acclimatization_window_days") { c.altitudeAcclimatizationDays = Int(v) }
        if let v = num("altitude.range_multiplier") { c.altitudeRangeMultiplier = v }
        if let v = bool("altitude.no_red_from_altitude_alone") { c.altitudeNoRedAlone = v }
        if let v = num("altitude.return_home_annotate_days") { c.altitudeReturnAnnotateDays = Int(v) }
        if let v = num("age_ancestry.hrmax_uncertainty_bpm") { c.hrmaxUncertaintyBpm = v }
        if let z = node("age_ancestry.zone_tops_pct_hrmax") as? [NSNumber], z.count == 4 { c.zoneTopsPctHrmax = z.map(\.doubleValue) }
        if let v = num("age_ancestry.older_noise_caveat_age") { c.olderNoiseCaveatAge = Int(v) }
        if let n = node("age_ancestry.display_norms.south_indian_18_30_short_supine_rmssd_ms") as? [String: Any],
           let i = c.displayNorms.firstIndex(where: { $0.ancestry == "South Asian" }) {
            if let m = (n["M"] as? NSNumber)?.doubleValue { c.displayNorms[i].rmssdMale = m }
            if let f = (n["F"] as? NSNumber)?.doubleValue { c.displayNorms[i].rmssdFemale = f }
            if let a = (n["all"] as? NSNumber)?.doubleValue { c.displayNorms[i].rmssdAll = a }
        }
        c.ancestryChangesSeverity = false   // hard lock regardless of file [QUE2020]
        if let o = root["engine_overrides"] as? [String: Any] {
            c = try c.merging(overrideJSON: JSONSerialization.data(withJSONObject: o))
            c.ancestryChangesSeverity = false
        }
        return c
    }
}
