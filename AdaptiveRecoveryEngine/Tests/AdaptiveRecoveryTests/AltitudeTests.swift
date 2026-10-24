import XCTest
@testable import AdaptiveRecovery

/// The 4 altitude tests run against the spreadsheet (T1-T4 in the v0.4 delivery), plus end-to-end trips.
final class AltitudeTests: XCTestCase {
    let c = AdaptiveConfig.bundled()

    // T1 visitor day 2 at +1500 m, core RECOVER, RHR normal & feeling ok -> REDUCE_INTENSITY
    func testT1VisitorNoRedFromAltitudeAlone() {
        let r = AdaptiveRecoveryEngine.altitudeSoftRule(core: .recover, corroborated: false, tripDay: 2, config: c)
        XCTAssertEqual(r.decision, .reduceIntensity)
        XCTAssertTrue(r.annotations[0].contains("Days 1-3"))
    }
    // T2 same, RHR high -> RECOVER stays
    func testT2VisitorWithHighRhrStillRecovers() {
        XCTAssertEqual(AdaptiveRecoveryEngine.altitudeSoftRule(core: .recover, corroborated: true, tripDay: 2, config: c).decision, .recover)
    }
    // T3 resident at 2200 m (home 2200): no adjustment, end-to-end
    func testT3ResidentGetsNoAdjustment() {
        var h = Fx.baseline(days: 40); for i in h.indices { h[i].elevationM = 2200 }
        var p = UserProfile(); p.homeElevationM = 2200
        let a = AdaptiveRecoveryEngine(config: c).today(history: h, profile: p)!
        XCTAssertEqual(a.decision, .trainAsPlanned, dbg(a))
        XCTAssertFalse(a.annotations.contains { $0.contains("altitude") || $0.contains("Altitude") })
        XCTAssertEqual(a.confidence, .normal)
    }
    // T4 back home day 3 -> annotation, trip days excluded from home baseline
    func testT4BackHomeAnnotatedAndTripExcluded() {
        var h = Fx.baseline(days: 40)
        for i in 30..<37 { h[i].elevationM = 2500; h[i].rmssdMs = 35 }   // 7 trip days, very low HRV
        let a = AdaptiveRecoveryEngine(config: c).evaluate(history: h, profile: UserProfile())
        let back3 = a[39]
        XCTAssertTrue(back3.annotations.contains { $0.contains("Back home day 3") })
        XCTAssertEqual(back3.metrics.baselineDays, 32, "the 7 trip days are not in the home baseline")
    }
    func testReduceBecomesGoByFeel() {
        let r = AdaptiveRecoveryEngine.altitudeSoftRule(core: .reduceIntensity, corroborated: false, tripDay: 5, config: c)
        XCTAssertEqual(r.decision, .trainAsPlanned); XCTAssertTrue(r.annotations[0].contains("10+"))
    }
    func testEndToEndTripWidensRangeAndNeverRedAlone() {
        var h = Fx.baseline(days: 40)
        for i in 36..<40 { h[i].elevationM = 2600; h[i].rmssdMs = 40; h[i].restingHr = 55
            h[i].wellness = Wellness(sleepQuality: 4, fatigue: 4, soreness: 4, stress: 4, mood: 4) }   // HRV low only
        let out = AdaptiveRecoveryEngine(config: c).evaluate(history: h, profile: UserProfile())
        for a in out[36...] { XCTAssertNotEqual(a.decision, .recover); XCTAssertEqual(a.confidence, .low) }
        XCTAssertEqual(out[39].metrics.band! / out[35].metrics.band!, 1.5, accuracy: 0.2)
    }
    func testAmsSymptomsStop() {
        var h = Fx.baseline(days: 30); h[29].elevationM = 3000; h[29].amsSymptoms = true
        XCTAssertEqual(AdaptiveRecoveryEngine(config: c).today(history: h, profile: UserProfile())!.decision, .stopAndDescend)
    }
}
