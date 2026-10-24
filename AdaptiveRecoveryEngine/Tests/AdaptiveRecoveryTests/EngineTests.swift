import XCTest
@testable import AdaptiveRecovery

final class EngineTests: XCTestCase {
    let eng = AdaptiveRecoveryEngine(config: AdaptiveConfig.bundled())

    func last(_ h: [DayRecord], _ p: UserProfile = UserProfile(), _ e: AdaptiveRecoveryEngine? = nil) -> Assessment { (e ?? eng).today(history: h, profile: p)! }

    // MARK: core calculations
    func testLnAndRollingNeedThreeReadings() {
        var h = Fx.baseline(days: 30)
        for i in 23..<29 { h[i].rmssdMs = nil }    // only 2 readings in the last 7 days
        let a = last(h)
        XCTAssertNil(a.metrics.roll7); XCTAssertEqual(a.decision, .coldStart)
        XCTAssertEqual(a.metrics.lnRmssd!, log(h[29].rmssdMs!), accuracy: 1e-12)
    }
    func testColdStartUntil14BaselineDays() {
        let out = eng.evaluate(history: Fx.baseline(days: 16), profile: UserProfile())
        XCTAssertEqual(out[13].decision, .coldStart)
        XCTAssertTrue(out[13].reasons[0].contains("Building your baseline"))
        XCTAssertEqual(out[14].metrics.baselineDays, 14); XCTAssertNotEqual(out[14].decision, .coldStart)
    }
    func testBaselineExcludesTodayAndUses60Days() {
        let a = last(Fx.baseline(days: 90))
        XCTAssertEqual(a.metrics.baselineDays, 60)
    }
    func testDeviceErrorFloorOnBand() {
        let a = last(Fx.baseline(days: 40))   // 0.5·CV band of this fixture is below the 6 % device floor
        XCTAssertEqual(a.metrics.band!, log(1.06), accuracy: 1e-12)
    }
    func testSickAndAlcoholDaysExcludedFromBaseline() {
        var h = Fx.baseline(days: 40); h[30].sick = true; h[31].alcoholPreviousEvening = true
        XCTAssertEqual(last(h).metrics.baselineDays, 37)
    }

    // MARK: decision logic (2-of-3)
    func testSingleLowDayIsReduceNotRecover() {
        var h = Fx.baseline(days: 40); h[39].rmssdMs = 40
        let a = last(h)
        XCTAssertEqual(a.metrics.statusDaily, .below); XCTAssertEqual(a.decision, .reduceIntensity)
    }
    func testTwoSignalsRecover() {
        var h = Fx.baseline(days: 40)
        h[39].rmssdMs = 40; h[39].wellness = Wellness(sleepQuality: 2, fatigue: 2, soreness: 2, stress: 2, mood: 2)
        let a = last(h)
        XCTAssertEqual(a.decision, .recover); XCTAssertEqual(Set(a.metrics.votes).isSuperset(of: ["hrv_low", "feeling_bad"]), true)
    }
    func testRhrHighPlusLowSevenDayRecovers() {
        var h = Fx.baseline(days: 45)
        for i in 39..<45 { h[i].rmssdMs = 42; h[i].restingHr = 62 }
        let a = last(h)
        XCTAssertEqual(a.metrics.status7, .below); XCTAssertEqual(a.metrics.rhrState, .high); XCTAssertEqual(a.decision, .recover)
    }
    func testAboveRangeIsNeutralNotPush() {
        var h = Fx.baseline(days: 40); h[39].rmssdMs = 80
        let a = last(h)
        XCTAssertEqual(a.decision, .trainAsPlanned, dbg(a))
        XCTAssertTrue(a.reasons.contains { $0.contains("not a signal to push") })
    }
    func testAboveRangeWithLowRhrIsBusyRecovering() {
        var h = Fx.baseline(days: 40); for i in 34..<40 { h[i].rmssdMs = 80; h[i].restingHr = 50 }
        XCTAssertEqual(last(h).decision, .reduceIntensity)
    }
    func testWellnessZScores() {
        var h = Fx.baseline(days: 40); h[39].wellness = Wellness(sleepQuality: 5, fatigue: 5, soreness: 5, stress: 5, mood: 5)
        XCTAssertGreaterThan(last(h).metrics.wellnessZ!, 0.5)
    }
    func testCvScatterAnnotates() {
        var h = Fx.baseline(days: 50)
        for (k, i) in (43..<50).enumerated() { h[i].rmssdMs = k % 2 == 0 ? 85 : 45 }
        XCTAssertTrue(last(h).annotations.contains { $0.contains("unsettled") })
    }
    func testPersistentLowRefers() {
        var h = Fx.baseline(days: 40)
        h += (0..<25).map { i in DayRecord(day: 20040 + i, rmssdMs: 40, restingHr: 55) }
        let out = eng.evaluate(history: h, profile: UserProfile())
        XCTAssertEqual(out.last!.decision, .medicalRefer)
    }
    func testRedFlagsRefer() {
        for f in [\DayRecord.headImpact, \.irregularRhythm, \.illnessSymptoms] {
            var h = Fx.baseline(days: 30); h[29][keyPath: f] = true
            XCTAssertEqual(last(h).decision, .medicalRefer)
        }
    }
    func testAcwrIsContextOnly() {
        var h = Fx.baseline(days: 40)
        for i in 33..<40 { h[i].sessions = [Session(type: "Running", minutes: 120, sRPE: 9)] }   // big spike
        h[39].rmssdMs = 60
        let a = last(h)
        XCTAssertNotNil(a.load?.loadChangeVsUsual); XCTAssertEqual(a.decision, .trainAsPlanned, dbg(a))
    }

    // MARK: profiles and modifiers
    func testExpectedDipAfterHardSessionDoesNotVote() {
        var h = Fx.baseline(days: 40); h[38].sessions = [Session(type: "Running", minutes: 90, sRPE: 8)]; h[39].rmssdMs = 45
        let a = last(h)
        XCTAssertEqual(a.decision, .trainAsPlanned); XCTAssertTrue(a.annotations.contains { $0.contains("fits your recent session") })
    }
    func testStrengthYesterdayPromptsNeuromuscularCheck() {
        var h = Fx.baseline(days: 40); h[38].sessions = [Session(type: "Olympic lifting", minutes: 75, sRPE: 7)]
        var p = UserProfile(); p.primaryActivity = "Olympic lifting"
        XCTAssertTrue(last(h, p).prompts.contains { $0.contains("bar speed") })
    }
    func testQuizPriorThenTwentySessionTakeover() {
        var p = UserProfile(); p.primaryActivity = "Running"; p.secondaryActivities = ["Powerlifting"]
        let c = AdaptiveConfig.bundled()
        XCTAssertEqual(ProfileClassifier.quizPrior(p, c), ["ENDURANCE": 0.6, "STRENGTH": 0.4])
        var h = Fx.baseline(days: 28)
        for i in stride(from: 0, to: 28, by: 1) where i % 7 != 6 { h[i].sessions = [Session(type: "CrossFit/metcon", minutes: 45, sRPE: 8)] }
        let r = ProfileClassifier.resolve(profile: p, history: h, asOf: h.last!.day, config: c)
        XCTAssertGreaterThanOrEqual(r.observedSessions, 20); XCTAssertEqual(r.quizWeight, 0); XCTAssertEqual(r.primaryFamily, "METCON")
        let r0 = ProfileClassifier.resolve(profile: p, history: Array(h.prefix(7)), asOf: h[6].day, config: c)
        XCTAssertEqual(r0.quizWeight, 0.7, accuracy: 1e-9)   // 6 sessions -> w_obs 0.3
    }
    func testHybridBlendOrsBooleans() {
        var p = UserProfile(); p.primaryActivity = "Running"; p.secondaryActivities = ["Powerlifting"]
        var hc = AdaptiveConfig.bundled(); hc.singleProfileShare = 0.7
        let r = ProfileClassifier.resolve(profile: p, history: [], asOf: 0, config: hc)
        XCTAssertTrue(r.isHybrid); XCTAssertTrue(r.nmCheck)
        XCTAssertEqual(r.expectedDipDays, 0.6 * 2 + 0.4 * 1, accuracy: 1e-9)
    }
    func testModifiersFromQuiz() {
        var p = UserProfile(); p.ageYears = 45; p.trainingYears = 0.2; p.mostlyWeekends = true; p.shiftWorker = true; p.tracksCycle = true
        let r = ProfileClassifier.resolve(profile: p, history: [], asOf: 0, config: .bundled())
        XCTAssertEqual(r.modifiers, [.masters, .beginner, .weekendWarrior, .shiftWorker, .femaleCycle])
        XCTAssertEqual(r.baselineWindowDays, 28)
        var y = UserProfile(); y.ageYears = 16
        XCTAssertTrue(ProfileClassifier.resolve(profile: y, history: [], asOf: 0, config: .bundled()).modifiers.contains(.youth))
    }
    func testPregnancyIsDataOnly() {
        var p = UserProfile(); p.pregnantOrPostpartum = true
        XCTAssertEqual(last(Fx.baseline(days: 40), p).decision, .dataOnly)
    }
    func testClinicalTurnsAdviceOff() {
        var p = UserProfile(); p.clinicalCondition = true
        XCTAssertEqual(last(Fx.baseline(days: 40), p).decision, .adviceOff)
    }
    func testLutealLowHrvAloneDoesNotVote() {
        var h = Fx.baseline(days: 40); h[39].rmssdMs = 42; h[39].lutealPhase = true
        var p = UserProfile(); p.tracksCycle = true
        XCTAssertEqual(last(h, p).decision, .trainAsPlanned)
    }

    // MARK: substances
    func testBetaBlockerDisablesAndStopReenables() {
        var p = UserProfile(); p.substanceEvents = [SubstanceEvent(id: "beta_blocker", day: 20030, kind: .start)]
        XCTAssertEqual(last(Fx.baseline(days: 40), p).decision, .adviceOff)
        p.substanceEvents.append(SubstanceEvent(id: "beta_blocker", day: 20035, kind: .stop))
        XCTAssertNotEqual(last(Fx.baseline(days: 40), p).decision, .adviceOff)
    }
    func testChangePointFreezesWidensThenRebuilds() {
        var p = UserProfile(); p.substanceEvents = [SubstanceEvent(id: "ssri_snri", day: 20040, kind: .start)]
        let out = eng.evaluate(history: Fx.baseline(days: 70), profile: p)
        let inWin = out[45], after = out[60]
        XCTAssertEqual(inWin.confidence, .low)
        XCTAssertEqual(inWin.metrics.baselineDays, 40)   // frozen: days before the change point
        XCTAssertEqual(inWin.metrics.band!, log(1.06) * 1.5, accuracy: 1e-12)
        XCTAssertEqual(after.metrics.baselineDays, 20)   // new baseline from day 20040
        XCTAssertEqual(after.metrics.band!, log(1.06), accuracy: 1e-12)
    }
    func testTimingSubstanceLowersConfidence() {
        var h = Fx.baseline(days: 40); h[39].takenBeforeReading = ["caffeine"]
        let a = last(h)
        XCTAssertEqual(a.confidence, .low); XCTAssertTrue(a.prompts.contains { $0.contains("caffeine") })
    }

    // MARK: age / ancestry (§12)
    func testHrMaxTanakaAndMeasuredOverride() {
        var p = UserProfile(); p.ageYears = 40
        let e = AgeAncestry.hrMax(p, .bundled())!
        XCTAssertEqual(e.bpm, 180, accuracy: 1e-9); XCTAssertEqual(e.uncertaintyBpm, 10); XCTAssertEqual(e.zoneTopsBpm[0], 126, accuracy: 1e-9)
        p.measuredHrMax = 191
        XCTAssertEqual(AgeAncestry.hrMax(p, .bundled())!.bpm, 191)
    }
    func testAncestryNeverChangesDecisions() {
        var h = Fx.baseline(days: 50); h[49].rmssdMs = 41
        var base = UserProfile(); base.ageYears = 25
        let ref = eng.evaluate(history: h, profile: base).map(\.decision)
        for anc in ["South Asian", "East Asian", "Black/African/Caribbean", "White/European", "Hispanic/Latino", "Prefer not to say"] {
            var p = base; p.ancestry = anc; p.nationality = "Indian"
            XCTAssertEqual(eng.evaluate(history: h, profile: p).map(\.decision), ref, anc)
        }
        var p = base; p.ancestry = "South Asian"; p.sex = "male"
        XCTAssertEqual(AgeAncestry.displayNorm(p, .bundled())!.rmssdMs, 57.4)
        XCTAssertTrue(eng.evaluate(history: h, profile: p).last!.infoCards.contains { $0.contains("South Asian") })
    }
    func testOlderHighHrvNote() {
        var h = Fx.baseline(days: 40); h[39].rmssdMs = 85
        var p = UserProfile(); p.ageYears = 65
        XCTAssertTrue(last(h, p).annotations.contains { $0.contains("mention it to your doctor") })
    }

    // MARK: config, learning, cohort hook
    func testBundledParamsLoadAndOverrideMerge() throws {
        let c = AdaptiveConfig.bundled()
        XCTAssertEqual(c.deviceErrorHrvPct, 6); XCTAssertEqual(c.baselineWindowDays, 60); XCTAssertFalse(c.engineEnabled)
        let o = try c.merging(overrideJSON: Data(#"{"baselineWindowDays": 42, "engineEnabled": true}"#.utf8))
        XCTAssertEqual(o.baselineWindowDays, 42); XCTAssertTrue(o.engineEnabled); XCTAssertEqual(o.rollingDays, 7)
        let p = try AdaptiveConfig.load(paramsJSON: Data(#"{"altitude":{"trip_delta_m":{"value":800}},"age_ancestry":{"ancestry_changes_severity":true}}"#.utf8))
        XCTAssertEqual(p.altitudeTripDeltaM, 800); XCTAssertFalse(p.ancestryChangesSeverity)
    }
    func testLearningOffByDefaultAndLogOnly() {
        var h = Fx.baseline(days: 50); for i in stride(from: 20, to: 49, by: 3) { h[i].sessions = [Session(type: "HIIT", minutes: 30, sRPE: 9)] }
        XCTAssertTrue(eng.evaluate(history: h, profile: UserProfile()).last!.research.isEmpty)
        var c = AdaptiveConfig.bundled(); c.learningEnabled = true
        let on = AdaptiveRecoveryEngine(config: c).evaluate(history: h, profile: UserProfile())
        XCTAssertNotNil(on.last!.research["cost.METCON"])
        XCTAssertEqual(on.map(\.decision), eng.evaluate(history: h, profile: UserProfile()).map(\.decision))
    }
    struct FixedCohort: CohortPriorProvider {
        func prior(for profile: UserProfile, family: String) -> CohortPrior? { CohortPrior(lnRmssdMean: log(50), lnRmssdSD: 0.1) }
    }
    func testCohortHookDefaultNoOpAndPartialPooling() {
        let h = Fx.baseline(days: 40)
        var c = AdaptiveConfig.bundled(); c.qualityGateEnabled = false   // keep the baseline day set identical
        let off = AdaptiveRecoveryEngine(config: c, cohort: FixedCohort()).today(history: h, profile: UserProfile())!
        XCTAssertEqual(off.metrics.baselineMean, AdaptiveRecoveryEngine(config: c).today(history: h, profile: UserProfile())!.metrics.baselineMean)   // disabled by config
        c.cohortPriorsEnabled = true
        let on = AdaptiveRecoveryEngine(config: c, cohort: FixedCohort()).today(history: h, profile: UserProfile())!
        let n = Double(on.metrics.baselineDays); let w = n / (n + 20.0)
        XCTAssertEqual(on.metrics.baselineMean!, w * off.metrics.baselineMean! + (1 - w) * log(50), accuracy: 1e-12)
    }
}
