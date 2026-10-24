import Foundation

/// Days are plain integer ordinals (e.g. days since 1970-01-01, local calendar) so the engine is
/// timezone-free and deterministic. `DayIndex.from("2026-08-01")` helps tests and importers.
public enum DayIndex {
    public static func from(_ iso: String) -> Int? {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        // days-from-civil (Howard Hinnant), proleptic Gregorian, 1970-01-01 = 0
        let y = p[1] <= 2 ? p[0] - 1 : p[0]
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (p[1] + 9) % 12
        let doy = (153 * mp + 2) / 5 + p[2] - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    /// 0 = Monday ... 6 = Sunday (1970-01-01 was a Thursday).
    public static func weekday(_ day: Int) -> Int { ((day % 7) + 7 + 3) % 7 }
}

public struct Wellness: Codable, Equatable, Sendable {
    /// 1-5, higher = better for every item (fatigue 5 = fresh, soreness 5 = none, stress 5 = calm).
    public var sleepQuality: Double?, fatigue: Double?, soreness: Double?, stress: Double?, mood: Double?
    public init(sleepQuality: Double? = nil, fatigue: Double? = nil, soreness: Double? = nil, stress: Double? = nil, mood: Double? = nil) {
        self.sleepQuality = sleepQuality; self.fatigue = fatigue; self.soreness = soreness; self.stress = stress; self.mood = mood
    }
    var items: [Double?] { [sleepQuality, fatigue, soreness, stress, mood] }
}

public struct SetEntry: Codable, Equatable, Sendable {
    public var sets: Int, reps: Int, loadKg: Double, rir: Int?
    public init(sets: Int, reps: Int, loadKg: Double, rir: Int? = nil) { self.sets = sets; self.reps = reps; self.loadKg = loadKg; self.rir = rir }
}

/// One part of a mixed session (e.g. CrossFit: heavy strength, gymnastics skill, short metcon, aerobic, test day).
/// `type` is a free string looked up in `AdaptiveConfig.sessionComponents` / `activityFamily`, so new
/// component kinds (spec §14) are config rows, not code changes.
public struct SessionComponent: Codable, Equatable, Sendable {
    public var type: String
    public var minutes: Double
    public var sRPE: Double
    public var sets: [SetEntry]
    public init(type: String, minutes: Double, sRPE: Double, sets: [SetEntry] = []) {
        self.type = type; self.minutes = minutes; self.sRPE = sRPE; self.sets = sets
    }
}

public struct Session: Codable, Equatable, Sendable {
    /// Activity / session type (free string), mapped to a family by `AdaptiveConfig.activityFamily`.
    public var type: String
    public var minutes: Double
    /// Session RPE, CR-10.
    public var sRPE: Double
    public var sets: [SetEntry]
    /// Optional parts of a mixed session. When present, load is the sum of the parts (each sRPE × min).
    public var components: [SessionComponent]
    /// Free-form tags (e.g. "competitor", "masters", "double_day_am") for future rules (§14).
    public var tags: [String]
    public init(type: String, minutes: Double, sRPE: Double, sets: [SetEntry] = [],
                components: [SessionComponent] = [], tags: [String] = []) {
        self.type = type; self.minutes = minutes; self.sRPE = sRPE; self.sets = sets; self.components = components; self.tags = tags
    }
    /// Common load unit across sports: sRPE × minutes [HAD2017]; summed over components when given.
    public var load: Double { components.isEmpty ? minutes * sRPE : components.reduce(0) { $0 + $1.minutes * $1.sRPE } }
    public var tonnage: Double { (sets + components.flatMap(\.sets)).reduce(0) { $0 + Double($1.sets * $1.reps) * $1.loadKg } }
}

public struct DayRecord: Codable, Equatable, Sendable {
    public var day: Int
    public var rmssdMs: Double?
    public var restingHr: Double?
    public var respRate: Double?
    public var sleepHours: Double?
    public var wellness: Wellness?
    /// Legacy single 1-5 subjective score (spreadsheet). Used only when `wellness` is nil.
    public var subjective: Double?
    public var sessions: [Session] = []
    // context
    public var artifact = false
    public var sick = false
    public var illnessSymptoms = false
    public var headImpact = false
    public var irregularRhythm = false
    public var amsSymptoms = false
    public var alcoholPreviousEvening = false
    public var lutealPhase = false
    public var caloricDeficit = false
    public var taper = false
    public var recentMajorStressor = false
    public var performanceDown = false
    public var lowPsychResources = false
    public var elevationM: Double?
    /// Substance ids (SubstanceRule.id) taken BEFORE this morning's reading.
    public var takenBeforeReading: [String] = []
    public init(day: Int, rmssdMs: Double? = nil, restingHr: Double? = nil) { self.day = day; self.rmssdMs = rmssdMs; self.restingHr = restingHr }
}

public struct SubstanceEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case start, stop, doseChange }
    public var id: String, day: Int, kind: Kind
    public init(id: String, day: Int, kind: Kind) { self.id = id; self.day = day; self.kind = kind }
}

/// Onboarding quiz answers + demographics. Every field optional.
public struct UserProfile: Codable, Equatable, Sendable {
    public var ageYears: Int?
    public var sex: String?            // "male" | "female" | other / nil
    /// Self-identified ancestry (spec §12 options). Used ONLY for an optional info card and display norms; never decisions.
    public var ancestry: String?
    /// Free text, stored only. Not used by any rule.
    public var nationality: String?
    public var measuredHrMax: Double?
    public var primaryActivity: String?          // Q1
    public var secondaryActivities: [String] = [] // Q2
    public var trainingYears: Double?            // Q6
    public var sessionsPerWeek: Double?          // Q3
    public var mostlyWeekends = false            // Q5
    public var tracksCycle = false               // Q8
    public var pregnantOrPostpartum = false      // Q9
    public var clinicalCondition = false         // Q10 yes/unsure
    public var shiftWorker = false               // Q11
    public var cutsWeight = false                // Q13
    public var homeElevationM: Double?           // Q12b
    public var substanceEvents: [SubstanceEvent] = [] // Q15/Q16 + later logs
    public init() {}
}
