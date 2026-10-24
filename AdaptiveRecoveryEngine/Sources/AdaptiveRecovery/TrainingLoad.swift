import Foundation

/// Training-load context (tonnage, sRPE x min, acute/chronic, monotony, strain, ACWR).
/// ACWR is CONTEXT ONLY ("load change vs usual") — never a decision input, never coloured as injury risk [DIN2026][IMP2023].
public struct LoadSnapshot: Codable, Equatable, Sendable {
    public var tonnageKg: Double
    public var effectiveSets: Double     // Σ sets × f(RIR) [HEL2016][REF2023]
    public var sRPELoad: Double
    public var acuteMean: Double?
    public var chronicMean: Double?
    public var loadChangeVsUsual: Double?   // ACWR, display only
    public var monotony: Double?
    public var strain: Double?
}

public enum TrainingLoad {
    /// Daily loads for days lo...hi (missing days = 0, as in the spreadsheet's SUMIF).
    static func dailyLoads(_ byDay: [Int: DayRecord], from lo: Int, to hi: Int) -> [Double] {
        guard hi >= lo else { return [] }
        return (lo...hi).map { d in byDay[d]?.sessions.reduce(0) { $0 + $1.load } ?? 0 }
    }

    public static func snapshot(day: Int, byDay: [Int: DayRecord], firstDay: Int, config c: AdaptiveConfig) -> LoadSnapshot {
        let today = byDay[day]
        let ton = today?.sessions.reduce(0) { $0 + $1.tonnage } ?? 0
        let eff = today?.sessions.reduce(0.0) { acc, s in
            acc + s.sets.reduce(0.0) { a, e in
                let f = e.rir.map { c.rirFactors[min(max($0, 0), c.rirFactors.count - 1)] } ?? 1.0
                return a + Double(e.sets) * f
            }
        } ?? 0
        let load = today?.sessions.reduce(0) { $0 + $1.load } ?? 0
        var s = LoadSnapshot(tonnageKg: ton, effectiveSets: eff, sRPELoad: load)
        if day - firstDay + 1 >= c.acuteDays {
            let a = dailyLoads(byDay, from: day - c.acuteDays + 1, to: day)
            s.acuteMean = Stats.mean(a)
            if let sd = Stats.sd(a), sd > 0, let m = s.acuteMean { s.monotony = m / sd; s.strain = a.reduce(0, +) * m / sd }
        }
        if day - firstDay + 1 >= c.chronicDays {
            s.chronicMean = Stats.mean(dailyLoads(byDay, from: day - c.chronicDays + 1, to: day))
            if let a = s.acuteMean, let ch = s.chronicMean, ch > 0 { s.loadChangeVsUsual = a / ch }
        }
        return s
    }
}
