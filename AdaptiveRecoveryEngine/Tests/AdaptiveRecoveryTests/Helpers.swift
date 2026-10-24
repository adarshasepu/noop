import Foundation
import XCTest
@testable import AdaptiveRecovery

enum Fx {
    static func json(_ name: String) throws -> Any {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }
    /// Deterministic pseudo-noise in [-1, 1].
    static func noise(_ i: Int) -> Double { sin(Double(i) * 12.9898) * 0.5 + cos(Double(i) * 4.1414) * 0.5 }

    /// `days` stable baseline days. HRV ≈ hrv ms (±10%, realistic day-to-day noise), RHR ≈ rhr.
    static func baseline(days: Int, start: Int = 20000, hrv: Double = 60, rhr: Double = 55, wellness: Bool = true) -> [DayRecord] {
        (0..<days).map { i in
            var r = DayRecord(day: start + i, rmssdMs: hrv * exp(0.10 * noise(i)), restingHr: rhr + 0.6 * noise(i + 99))
            r.respRate = 14.5 + 0.2 * noise(i + 7)
            if wellness { let v = 4 + 0.5 * noise(i + 3); r.wellness = Wellness(sleepQuality: v, fatigue: v, soreness: v, stress: v, mood: v) }
            return r
        }.enumerated().map { i, r in
            var r = r   // the last ("today") day is neutral: wellness at its mean, HRV/RHR at the centre
            if i == days - 1 { r.rmssdMs = hrv; r.restingHr = rhr; if wellness { r.wellness = Wellness(sleepQuality: 4, fatigue: 4, soreness: 4, stress: 4, mood: 4) } }
            return r
        }
    }
    static func cfg(_ f: (inout AdaptiveConfig) -> Void = { _ in }) -> AdaptiveConfig { var c = AdaptiveConfig.bundled(); f(&c); return c }
}
func dbg(_ a: Assessment) -> String { "\(a.decision) votes=\(a.metrics.votes) s=\(a.metrics.statusDaily)/\(a.metrics.status7) rhr=\(a.metrics.rhrState) band=\(a.metrics.band ?? -1) \(a.reasons) \(a.coachFlags) \(a.annotations)" }
