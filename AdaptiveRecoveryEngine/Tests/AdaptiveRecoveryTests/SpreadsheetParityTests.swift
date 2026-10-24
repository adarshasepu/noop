import XCTest
@testable import AdaptiveRecovery

/// Mirrors noop_vision_scoring_v2.xlsx 'Adaptive HRV' (70 example days, LibreOffice-recalculated values)
/// and 'Training Load' (130 set rows, 70 daily rows). Fixtures were exported from the sheet's cached values.
final class SpreadsheetParityTests: XCTestCase {

    /// The sheet uses METHOD_C (mean ± 0.5·SD), no device floor, the v0.1 core rule and a single 1-5 score.
    static let sheetConfig = Fx.cfg {
        $0.rangeMethod = .sdBand; $0.sdMultiplierM = 0.5; $0.deviceErrorHrvPct = 0
        $0.decisionRule = .coreV01; $0.subjectiveSingleBadAtOrBelow = 2
        $0.baselineWindowDays = 60; $0.minBaselineDays = 14; $0.alcoholExcludeNextDay = false; $0.qualityGateEnabled = false
    }

    func loadSheet() throws -> ([DayRecord], [[String: Any]]) {
        let rows = try XCTUnwrap(Fx.json("adaptive_hrv_sheet") as? [[String: Any]])
        let recs: [DayRecord] = rows.map { r in
            var d = DayRecord(day: DayIndex.from(r["date"] as! String)!, rmssdMs: (r["rmssd"] as! NSNumber).doubleValue,
                              restingHr: (r["rhr"] as! NSNumber).doubleValue)
            d.subjective = (r["subj"] as! NSNumber).doubleValue
            return d
        }
        return (recs, rows)
    }

    func testAdaptiveHrvTabNumbersMatch() throws {
        let (recs, rows) = try loadSheet()
        let out = AdaptiveRecoveryEngine(config: Self.sheetConfig).evaluate(history: recs, profile: UserProfile())
        XCTAssertEqual(out.count, 70)
        func chk(_ got: Double?, _ want: Any?, _ what: String, _ i: Int) {
            let w = (want as? NSNumber)?.doubleValue
            if let w { XCTAssertEqual(got ?? .nan, w, accuracy: 1e-9, "\(what) day \(i)") } else { XCTAssertNil(got, "\(what) day \(i)") }
        }
        for (i, (a, r)) in zip(out, rows).enumerated() {
            chk(a.metrics.lnRmssd, r["ln"], "ln", i)
            chk(a.metrics.roll7, r["roll7"], "roll7", i)
            chk(a.metrics.baselineMean, r["baseMean"], "baseMean", i)
            chk(a.metrics.baselineSD, r["baseSD"], "baseSD", i)
            chk(a.metrics.normalLow, r["low"], "low", i)
            chk(a.metrics.normalHigh, r["high"], "high", i)
            chk(a.metrics.cv7, r["cv7"], "cv7", i)
            chk(a.metrics.rhr7, r["rhr7"], "rhr7", i)
            chk(a.metrics.rhrBaseline, r["rhrBase"], "rhrBase", i)
            chk(a.metrics.ratio, r["ratio"], "ratio", i)
            chk(a.metrics.ratio7, r["ratio7"], "ratio7", i)
            let sd = r["statusDaily"] as! String, s7 = r["status7"] as! String, rs = r["rhrState"] as! String
            XCTAssertEqual(a.metrics.statusDaily.rawValue, sd == "no baseline" ? "noBaseline" : sd, "status day \(i)")
            XCTAssertEqual(a.metrics.status7.rawValue, s7 == "no baseline" ? "noBaseline" : s7, "status7 day \(i)")
            XCTAssertEqual(a.metrics.rhrState.rawValue, rs == "no baseline" ? "noBaseline" : rs, "rhr state day \(i)")
        }
    }

    func testAdaptiveHrvTabDecisionsMatch() throws {
        let (recs, rows) = try loadSheet()
        let out = AdaptiveRecoveryEngine(config: Self.sheetConfig).evaluate(history: recs, profile: UserProfile())
        let map = ["TRAIN AS PLANNED": Decision.trainAsPlanned, "REDUCE INTENSITY": .reduceIntensity, "RECOVER": .recover]
        var counts: [Decision: Int] = [:]
        for (i, (a, r)) in zip(out, rows).enumerated() {
            let want = map[r["decision"] as! String] ?? .coldStart
            XCTAssertEqual(a.decision, want, "decision day \(i)")
            counts[a.decision, default: 0] += 1
        }
        XCTAssertEqual(counts, [.trainAsPlanned: 33, .coldStart: 14, .recover: 12, .reduceIntensity: 11])
    }

    func testTrainingLoadTabMatches() throws {
        let fx = try XCTUnwrap(Fx.json("training_load_sheet") as? [String: Any])
        let sets = fx["sets"] as! [[String: Any]], daily = fx["daily"] as! [[String: Any]]
        var byDay: [Int: DayRecord] = [:]
        for d in daily { let k = DayIndex.from(d["date"] as! String)!; byDay[k] = DayRecord(day: k) }
        var cur: (Int, Int)? = nil
        for s in sets {
            let k = DayIndex.from(s["date"] as! String)!
            let e = SetEntry(sets: (s["sets"] as! NSNumber).intValue, reps: (s["reps"] as! NSNumber).intValue, loadKg: (s["kg"] as! NSNumber).doubleValue)
            if let m = s["minutes"] as? NSNumber {
                byDay[k]!.sessions.append(Session(type: s["type"] as! String, minutes: m.doubleValue, sRPE: (s["srpe"] as! NSNumber).doubleValue, sets: [e]))
                cur = (k, byDay[k]!.sessions.count - 1)
            } else if let c = cur, c.0 == k { byDay[k]!.sessions[c.1].sets.append(e) }
        }
        let first = byDay.keys.min()!
        let c = AdaptiveConfig()
        for d in daily {
            let k = DayIndex.from(d["date"] as! String)!
            let s = TrainingLoad.snapshot(day: k, byDay: byDay, firstDay: first, config: c)
            XCTAssertEqual(s.tonnageKg, (d["tonnage"] as! NSNumber).doubleValue, accuracy: 1e-6, "tonnage \(k)")
            XCTAssertEqual(s.sRPELoad, (d["load"] as! NSNumber).doubleValue, accuracy: 1e-9)
            for (got, key) in [(s.acuteMean, "acute"), (s.chronicMean, "chronic"), (s.loadChangeVsUsual, "acwr"), (s.monotony, "monotony"), (s.strain, "strain")] {
                if let w = d[key] as? NSNumber { XCTAssertEqual(got ?? .nan, w.doubleValue, accuracy: 1e-6, "\(key) \(k)") } else { XCTAssertNil(got, "\(key) \(k)") }
            }
        }
    }
}
