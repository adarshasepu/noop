import XCTest
@testable import AdaptiveRecovery

/// The 5 example days from noop_scoring_examples.xlsx ('Current Recovery'), fed to the ADAPTIVE engine as
/// "today" after a 30-day baseline with mean HRV 60 ms / RHR 55 bpm. Legacy noop scores for the same rows
/// (85.6 Green, 58.8 Yellow, 24.4 Red, 31.7 Red, 9.9 Red) are asserted against RecoveryScorer in
/// StrandAnalyticsTests/AdaptiveRecoveryBridgeTests. Key difference by design: one hard day is not red.
final class NoopExampleDaysTests: XCTestCase {
    struct Ex { let name: String; let hrv: Double; let rhr: Double; let resp: Double; let feel: Double?; let want: Decision }
    let rows = [
        Ex(name: "Good day", hrv: 72, rhr: 52, resp: 14.2, feel: nil, want: .trainAsPlanned),
        Ex(name: "Normal day", hrv: 60, rhr: 55, resp: 14.5, feel: nil, want: .trainAsPlanned),
        Ex(name: "Hard training day after", hrv: 50, rhr: 59, resp: 15, feel: nil, want: .reduceIntensity),
        Ex(name: "Poor sleep", hrv: 54, rhr: 57, resp: 14.8, feel: 2, want: .recover),
        Ex(name: "Getting sick", hrv: 42, rhr: 63, resp: 16, feel: 2, want: .recover),
    ]
    func testFiveExampleDays() {
        let eng = AdaptiveRecoveryEngine(config: .bundled())
        for e in rows {
            var h = Fx.baseline(days: 30)
            for i in 24..<30 { h[i].rmssdMs = 60; h[i].restingHr = 55 }   // a settled week before the example day
            var d = DayRecord(day: 20030, rmssdMs: e.hrv, restingHr: e.rhr); d.respRate = e.resp
            if let f = e.feel { d.wellness = Wellness(sleepQuality: f, fatigue: f, soreness: f, stress: f, mood: f) }
            h.append(d)
            let a = eng.today(history: h, profile: UserProfile())!
            XCTAssertEqual(a.decision, e.want, "\(e.name): \(a.reasons)")
        }
    }
}
