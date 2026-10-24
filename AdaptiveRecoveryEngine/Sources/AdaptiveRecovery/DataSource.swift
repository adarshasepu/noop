import Foundation

// Device-agnostic input layer. The engine only ever sees `DayRecord` / `UserProfile` plain structs.
// Adapters for Apple HealthKit, Android Health Connect, Garmin, Oura, WHOOP, Polar, BLE chest straps,
// or a host app (e.g. the noop glue) implement `RecoveryDataSource` and live OUTSIDE this package.

/// One raw night or morning measurement. Supply either RR intervals (preferred) or a device rMSSD.
public struct RawMeasurement: Codable, Equatable, Sendable {
    public var day: Int
    public var rrIntervalsMs: [Double]?
    public var rmssdMs: Double?
    public var restingHr: Double?
    public var respRate: Double?
    public var sleepHours: Double?
    public var elevationM: Double?
    public var source: String          // free text, e.g. "healthkit", "polar-h10", "noop"
    public init(day: Int, rrIntervalsMs: [Double]? = nil, rmssdMs: Double? = nil, restingHr: Double? = nil,
                respRate: Double? = nil, sleepHours: Double? = nil, elevationM: Double? = nil, source: String = "") {
        self.day = day; self.rrIntervalsMs = rrIntervalsMs; self.rmssdMs = rmssdMs; self.restingHr = restingHr
        self.respRate = respRate; self.sleepHours = sleepHours; self.elevationM = elevationM; self.source = source
    }
}

public protocol RecoveryDataSource {
    func measurements(from: Int, to: Int) -> [RawMeasurement]
    func sessions(from: Int, to: Int) -> [Int: [Session]]
    func checkIns(from: Int, to: Int) -> [Int: Wellness]
    func profile() -> UserProfile
}

public enum RRProcessing {
    /// rMSSD (ms) from RR intervals: drop beats outside 300-2000 ms and successive changes > 20 %
    /// (a common simple artifact filter, EC), then sqrt(mean(ΔRR²)). Nil if fewer than `minBeats` remain.
    public static func rmssd(_ rr: [Double], minBeats: Int = 30) -> Double? {
        var clean: [Double] = []
        for v in rr where v >= 300 && v <= 2000 {
            if let last = clean.last, abs(v - last) / last > 0.2 { continue }
            clean.append(v)
        }
        guard clean.count >= minBeats else { return nil }
        var s = 0.0
        for i in 1..<clean.count { let d = clean[i] - clean[i - 1]; s += d * d }
        return (s / Double(clean.count - 1)).squareRoot()
    }
    /// Mean heart rate (bpm) from RR intervals.
    public static func meanHr(_ rr: [Double]) -> Double? {
        let v = rr.filter { $0 >= 300 && $0 <= 2000 }
        guard !v.isEmpty else { return nil }
        return 60000 / (v.reduce(0, +) / Double(v.count))
    }
}

extension AdaptiveRecoveryEngine {
    /// Pull `from...to` from any data source and assess every day.
    public func evaluate(source: RecoveryDataSource, from: Int, to: Int) -> [Assessment] {
        let ses = source.sessions(from: from, to: to), chk = source.checkIns(from: from, to: to)
        var byDay: [Int: DayRecord] = [:]
        for m in source.measurements(from: from, to: to) {
            var r = byDay[m.day] ?? DayRecord(day: m.day)
            r.rmssdMs = m.rrIntervalsMs.flatMap { RRProcessing.rmssd($0) } ?? m.rmssdMs ?? r.rmssdMs
            r.restingHr = m.restingHr ?? r.restingHr
            r.respRate = m.respRate ?? r.respRate; r.sleepHours = m.sleepHours ?? r.sleepHours; r.elevationM = m.elevationM ?? r.elevationM
            byDay[m.day] = r
        }
        for (d, s) in ses { var r = byDay[d] ?? DayRecord(day: d); r.sessions = s; byDay[d] = r }
        for (d, w) in chk { var r = byDay[d] ?? DayRecord(day: d); r.wellness = w; byDay[d] = r }
        return evaluate(history: Array(byDay.values), profile: source.profile())
    }
}
