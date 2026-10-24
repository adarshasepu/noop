import XCTest
import WhoopStore
import AdaptiveRecovery
@testable import StrandAnalytics

final class AdaptiveRecoveryBridgeTests: XCTestCase {

    /// The 5 example rows of noop_scoring_examples.xlsx ('Current Recovery'): the legacy RecoveryScorer
    /// must still produce the sheet's scores (the new engine must not change Charge).
    func testLegacyRecoveryScorerUnchangedOnFiveExampleDays() {
        typealias B = RecoveryScorer.DriverBaseline
        // (hrv, hrvMean, hrvSpread, rhr, rhrMean, rhrSpread, resp, respMean, respSpread, sleep, skin, slope, effort, effMean, effSpread, score, band)
        let rows: [(Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, String)] = [
            (72, 60, 8, 52, 55, 3, 14.2, 14.5, 0.5, 0.92, 0.1, -2.5, 40, 45, 10, 85.627, "Green"),
            (60, 60, 8, 55, 55, 3, 14.5, 14.5, 0.5, 0.85, 0.0, -1.0, 45, 45, 10, 58.816, "Yellow"),
            (50, 60, 8, 59, 55, 3, 15.0, 14.5, 0.5, 0.78, 0.2, 0.0, 70, 45, 10, 24.368, "Red"),
            (54, 60, 8, 57, 55, 3, 14.8, 14.5, 0.5, 0.65, 0.1, 0.5, 50, 45, 10, 31.722, "Red"),
            (42, 60, 8, 63, 55, 3, 16.0, 14.5, 0.5, 0.70, 0.8, 1.5, 30, 45, 10, 9.902, "Red"),
        ]
        for r in rows {
            let s = RecoveryScorer.recovery(hrv: r.0, rhr: r.3, resp: r.6, hrvBaseline: B(mean: r.1, spread: r.2),
                                            rhrBaseline: B(mean: r.4, spread: r.5), respBaseline: B(mean: r.7, spread: r.8),
                                            sleepPerf: r.9, skinTempDev: r.10, recoveryIndexSlope: r.11,
                                            effortBaseline: B(mean: r.13, spread: r.14), priorDayEffort: r.12)
            XCTAssertEqual(s ?? -1, r.15, accuracy: 0.01)
            XCTAssertEqual(RecoveryScorer.band(s!).lowercased(), r.16.lowercased())
        }
    }

    func daily(_ n: Int) -> [DailyMetric] {
        (0..<n).map { i in
            let d = String(format: "2026-08-%02d", i + 1)
            return DailyMetric(day: d, totalSleepMin: 450, efficiency: 0.9, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                               restingHr: 55, avgHrv: 60 * exp(0.08 * sin(Double(i))), recovery: nil, strain: nil, exerciseCount: nil)
        }
    }

    func testFlagOffReturnsNil() {
        XCTAssertNil(AdaptiveRecoveryBridge.assessToday(daily: daily(30), enabled: false))
    }
    func testFlagOnAssessesAndMapsFields() {
        let a = AdaptiveRecoveryBridge.assessToday(daily: daily(30), enabled: true)
        XCTAssertNotNil(a); XCTAssertNotEqual(a?.decision, .coldStart)
        let r = AdaptiveRecoveryBridge.records(from: daily(1))[0]
        XCTAssertEqual(r.restingHr, 55); XCTAssertEqual(r.sleepHours, 7.5)
        XCTAssertEqual(r.day, DayIndex.from("2026-08-01"))
    }
    func testNoopDataSource() {
        let src = NoopDailyMetricSource(daily: daily(30))
        let lo = DayIndex.from("2026-08-01")!, hi = DayIndex.from("2026-08-30")!
        XCTAssertEqual(AdaptiveRecoveryEngine(config: .bundled()).evaluate(source: src, from: lo, to: hi).count, 30)
    }
}
