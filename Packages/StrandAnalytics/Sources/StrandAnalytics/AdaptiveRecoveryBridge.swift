import Foundation
import WhoopStore
import AdaptiveRecovery

// AdaptiveRecoveryBridge — thin noop glue for the standalone AdaptiveRecovery engine
// (AdaptiveRecoveryEngine/ at the repo root, a separate package that shares no noop code).
//
// Feature flag: OFF by default. The engine never replaces Charge (RecoveryScorer); when the flag is on
// the app can show its assessment ALONGSIDE Charge. This file stays pure: the app reads the flag
// (UserDefaults key `flagKey`) and passes `enabled` in, like the other Experimental switches.
public enum AdaptiveRecoveryBridge {

    /// UserDefaults key the app layer reads for the Experimental toggle.
    public static let flagKey = "experimental.adaptiveRecovery"

    /// noop daily rows -> engine records. Only avgHrv (rMSSD), restingHr, resp rate and sleep duration are used.
    public static func records(from daily: [DailyMetric]) -> [DayRecord] {
        daily.compactMap { m in
            guard let d = DayIndex.from(m.day) else { return nil }
            var r = DayRecord(day: d, rmssdMs: m.avgHrv, restingHr: m.restingHr.map(Double.init))
            r.respRate = m.respRateBpm
            r.sleepHours = m.totalSleepMin.map { $0 / 60 }
            return r
        }
    }

    /// The adaptive assessment for the latest day, or nil when the flag is off (the default).
    /// `extra` lets the caller merge sessions / check-ins / context it already holds, keyed by day ordinal.
    public static func assessToday(daily: [DailyMetric], profile: AdaptiveRecovery.UserProfile = AdaptiveRecovery.UserProfile(),
                                   enabled: Bool, config: AdaptiveConfig = .bundled(),
                                   extra: (inout DayRecord) -> Void = { _ in }) -> Assessment? {
        guard enabled || config.engineEnabled else { return nil }
        let recs = records(from: daily).map { r -> DayRecord in var r = r; extra(&r); return r }
        return AdaptiveRecoveryEngine(config: config).today(history: recs, profile: profile)
    }
}

/// Lets any noop store act as an engine data source (device-agnostic seam).
public struct NoopDailyMetricSource: RecoveryDataSource {
    public let daily: [DailyMetric]
    public let userProfile: AdaptiveRecovery.UserProfile
    public init(daily: [DailyMetric], profile: AdaptiveRecovery.UserProfile = AdaptiveRecovery.UserProfile()) { self.daily = daily; self.userProfile = profile }
    public func measurements(from: Int, to: Int) -> [RawMeasurement] {
        AdaptiveRecoveryBridge.records(from: daily).filter { $0.day >= from && $0.day <= to }.map {
            RawMeasurement(day: $0.day, rmssdMs: $0.rmssdMs, restingHr: $0.restingHr, respRate: $0.respRate, sleepHours: $0.sleepHours, source: "noop")
        }
    }
    public func sessions(from: Int, to: Int) -> [Int: [Session]] { [:] }
    public func checkIns(from: Int, to: Int) -> [Int: Wellness] { [:] }
    public func profile() -> AdaptiveRecovery.UserProfile { userProfile }
}
