import XCTest
@testable import AdaptiveRecovery

final class DataSourceTests: XCTestCase {
    func testRmssdFromRR() {
        let rr = (0..<60).map { 1000.0 + ($0 % 2 == 0 ? 20 : -20) }   // alternating ±20 -> successive diff 40
        XCTAssertEqual(RRProcessing.rmssd(rr)!, 40, accuracy: 1e-9)
        XCTAssertEqual(RRProcessing.meanHr(rr)!, 60, accuracy: 1e-9)
        XCTAssertNil(RRProcessing.rmssd([1000, 1010]))
    }
    struct Mem: RecoveryDataSource {
        let days: [DayRecord]
        func measurements(from: Int, to: Int) -> [RawMeasurement] {
            days.map { RawMeasurement(day: $0.day, rmssdMs: $0.rmssdMs, restingHr: $0.restingHr, source: "test") }
        }
        func sessions(from: Int, to: Int) -> [Int: [Session]] { [:] }
        func checkIns(from: Int, to: Int) -> [Int: Wellness] { [:] }
        func profile() -> UserProfile { UserProfile() }
    }
    func testEvaluateFromDataSourceMatchesDirect() {
        var h = Fx.baseline(days: 40, wellness: false)
        for i in h.indices { h[i].respRate = nil }
        let e = AdaptiveRecoveryEngine(config: .bundled())
        let a = e.evaluate(source: Mem(days: h), from: h.first!.day, to: h.last!.day)
        XCTAssertEqual(a.map(\.decision), e.evaluate(history: h, profile: UserProfile()).map(\.decision))
    }
}

final class SessionComponentTests: XCTestCase {
    func testMixedSessionSplitsLoadByComponent() {
        let s = Session(type: "CrossFit/HIFT", minutes: 60, sRPE: 7, components: [
            SessionComponent(type: "heavy_strength", minutes: 20, sRPE: 8, sets: [SetEntry(sets: 5, reps: 3, loadKg: 100)]),
            SessionComponent(type: "metcon_short", minutes: 12, sRPE: 9),
        ])
        XCTAssertEqual(s.load, 20 * 8 + 12 * 9); XCTAssertEqual(s.tonnage, 1500)
        let c = AdaptiveConfig.bundled()
        let fl = Dictionary(ProfileClassifier.familyLoads(s, c), uniquingKeysWith: +)
        XCTAssertEqual(fl, ["STRENGTH": 160, "METCON": 108])
        var c2 = c; c2.sessionComponents["sled_push"] = ComponentSpec(family: "STRENGTH", loadMethod: .sRPEMinutes)
        XCTAssertEqual(ProfileClassifier.family(of: "sled_push", c2), "STRENGTH")
    }
}
