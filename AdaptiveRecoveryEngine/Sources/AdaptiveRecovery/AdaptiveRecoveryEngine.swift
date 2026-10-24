import Foundation

public enum Decision: String, Codable, Sendable {
    case coldStart = "COLD_START"
    case trainAsPlanned = "TRAIN_AS_PLANNED"
    case reduceIntensity = "REDUCE_INTENSITY"
    case recover = "RECOVER"
    case medicalRefer = "MEDICAL_REFER"
    case stopAndDescend = "STOP_DESCEND_MEDICAL_REFER"
    /// Clinical / beta-blocker / supervised meds: data shown, advice off, "ask your doctor".
    case adviceOff = "ADVICE_OFF"
    /// Pregnancy: descriptive data only, refer to doctor or midwife.
    case dataOnly = "DATA_ONLY"
}

public enum RangeStatus: String, Codable, Sendable { case below, inside, above, noBaseline }
public enum RhrState: String, Codable, Sendable { case high, normal, low, noBaseline }
public enum Confidence: String, Codable, Sendable { case normal, low }

public struct Metrics: Codable, Equatable, Sendable {
    public var lnRmssd: Double?
    public var roll7: Double?
    public var baselineMean: Double?
    public var baselineSD: Double?
    public var baselineDays = 0
    public var band: Double?
    public var normalLow: Double?
    public var normalHigh: Double?
    public var statusDaily: RangeStatus = .noBaseline
    public var status7: RangeStatus = .noBaseline
    public var cv7: Double?
    public var cvBaseline: Double?
    public var rhr7: Double?
    public var rhrBaseline: Double?
    public var rhrState: RhrState = .noBaseline
    public var ratio: Double?
    public var ratio7: Double?
    public var wellnessZ: Double?
    public var trendRoll7PerDay: Double?
    public var trendCvPerDay: Double?
    public var votes: [String] = []
}

public struct Assessment: Codable, Equatable, Sendable {
    public var day: Int
    public var decision: Decision
    public var reasons: [String] = []
    /// Source tags (sources.md) / "EC" for every rule that fired — explainability.
    public var tags: [String] = []
    public var annotations: [String] = []
    public var coachFlags: [String] = []
    public var prompts: [String] = []
    public var infoCards: [String] = []
    public var confidence: Confidence = .normal
    public var metrics = Metrics()
    public var load: LoadSnapshot?
    public var profile: ResolvedProfile?
    /// Research-only output (learning flag). Never read by `decision` unless learningAffectsDecisions.
    public var research: [String: Double] = [:]
}

/// The adaptive recovery engine: hrv-algorithm-spec.md §1-12. Pure and deterministic.
public struct AdaptiveRecoveryEngine: Sendable {
    public var config: AdaptiveConfig
    public var cohort: any CohortPriorProvider
    public init(config: AdaptiveConfig = .bundled(), cohort: any CohortPriorProvider = NoCohortPriors()) {
        self.config = config; self.cohort = cohort
    }

    /// Assess every day in `history` (any order; one record per day).
    public func evaluate(history raw: [DayRecord], profile: UserProfile) -> [Assessment] {
        let history = raw.sorted { $0.day < $1.day }
        guard let first = history.first?.day else { return [] }
        var byDay: [Int: DayRecord] = [:]
        for r in history { byDay[r.day] = r }
        var st = RunState()
        var out: [Assessment] = []
        for r in history { out.append(assess(r, byDay: byDay, firstDay: first, profile: profile, state: &st)) }
        if config.learningEnabled {
            let fam = out.last?.profile?.primaryFamily ?? "GENERAL"
            ResponseLearner.attach(to: &out, byDay: byDay, profile: profile, config: config,
                                   cohort: config.cohortPriorsEnabled ? cohort.prior(for: profile, family: fam) : nil)
        }
        return out
    }

    /// Convenience: the assessment for the last day in `history`.
    public func today(history: [DayRecord], profile: UserProfile) -> Assessment? { evaluate(history: history, profile: profile).last }

    // MARK: - internals

    struct RunState {
        var gated: Set<Int> = []                 // quality-gate rejects (excluded from baselines)
        var roll7: [Int: Double] = [:]
        var cv7: [Int: Double] = [:]
        var lowStreak = 0
        var allBadStreak = 0
    }

    func ln(_ r: DayRecord?) -> Double? { r?.rmssdMs.flatMap { $0 > 0 ? Foundation.log($0) : nil } }

    struct AltitudeState { var tripDay: Int?; var acclimatized = false; var daysSinceReturn: Int?; var isTrip: Bool { tripDay != nil } }

    func isTripDay(_ r: DayRecord?, home: Double) -> Bool {
        guard let e = r?.elevationM else { return false }
        let c = config
        return e - home >= c.altitudeTripDeltaM || (home < c.altitudeLowHomeM && e >= c.altitudeVisitorAbsoluteM)
    }

    func altitude(_ day: Int, byDay: [Int: DayRecord], home: Double) -> AltitudeState {
        var s = AltitudeState()
        if isTripDay(byDay[day], home: home) {
            var n = 1, d = day - 1
            while isTripDay(byDay[d], home: home) { n += 1; d -= 1 }
            s.tripDay = n
            // spec §10: resident after `resident_days`; after the acclimatization window a separate altitude baseline is used.
            s.acclimatized = n > config.altitudeAcclimatizationDays
        } else {
            for k in 1...max(config.altitudeReturnAnnotateDays, 1) where isTripDay(byDay[day - k], home: home) { s.daysSinceReturn = k; break }
        }
        return s
    }

    struct SubstanceState { var disabled: [String] = []; var cpDay: Int?; var inWindow = false; var active: Set<String> = [] }

    func substances(_ day: Int, _ p: UserProfile) -> SubstanceState {
        var s = SubstanceState()
        let rules = Dictionary(config.substances.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var latest: [String: SubstanceEvent] = [:]
        for e in p.substanceEvents where e.day <= day { if (latest[e.id]?.day ?? Int.min) <= e.day { latest[e.id] = e } }
        for (id, e) in latest {
            if e.kind != .stop { s.active.insert(id) }
            guard let r = rules[id] else { continue }
            if r.action == .disableRefer && e.kind != .stop { s.disabled.append(id) }
        }
        for e in p.substanceEvents where e.day <= day {
            guard let r = rules[e.id], r.chronic, r.action != .disableRefer else { continue }
            if (s.cpDay ?? Int.min) < e.day { s.cpDay = e.day }
        }
        if let cp = s.cpDay { s.inWindow = day - cp < config.changePointWindowDays }
        s.disabled.sort()
        return s
    }

    func assess(_ r: DayRecord, byDay: [Int: DayRecord], firstDay: Int, profile p: UserProfile, state st: inout RunState) -> Assessment {
        let c = config, t = r.day
        let prof = ProfileClassifier.resolve(profile: p, history: Array(byDay.values), asOf: t, config: c)
        var a = Assessment(day: t, decision: .coldStart)
        a.profile = prof
        a.load = TrainingLoad.snapshot(day: t, byDay: byDay, firstDay: firstDay, config: c)
        a.infoCards = AgeAncestry.infoCards(p, c)
        var m = Metrics()
        let home = p.homeElevationM ?? 0
        let alt = altitude(t, byDay: byDay, home: home)
        let sub = substances(t, p)

        // ---- baseline day set ----
        var lo = t - prof.baselineWindowDays, hi = t - 1
        if let cp = sub.cpDay {
            if sub.inWindow { hi = min(hi, cp - 1) } else { lo = max(lo, cp) }   // freeze old / use new [§9]
        }
        func excluded(_ d: Int) -> Bool {
            guard let rr = byDay[d] else { return true }
            if rr.sick || rr.artifact || st.gated.contains(d) { return true }
            if c.alcoholExcludeNextDay && rr.alcoholPreviousEvening { return true }
            let trip = isTripDay(rr, home: home)
            if alt.isTrip && alt.acclimatized { return !trip }    // separate altitude baseline
            return trip                                           // home baseline excludes trip days
        }
        let baseDays = lo <= hi ? (lo...hi).filter { !excluded($0) } : []
        let baseX = baseDays.compactMap { ln(byDay[$0]) }
        m.lnRmssd = ln(r)
        m.baselineDays = baseX.count
        if baseX.count >= c.minBaselineDays { m.baselineMean = Stats.mean(baseX); m.baselineSD = Stats.sd(baseX) }
        if c.cohortPriorsEnabled, let mu = m.baselineMean, let sd = m.baselineSD,
           let pr = cohort.prior(for: p, family: prof.primaryFamily) {   // spec §13 partial pooling
            m.baselineMean = CohortBlend.blend(individual: mu, prior: pr.lnRmssdMean, n: baseX.count, k: c.cohortShrinkageK)
            m.baselineSD = CohortBlend.blend(individual: sd, prior: pr.lnRmssdSD, n: baseX.count, k: c.cohortShrinkageK)
            a.tags.append("COHORT-PRIOR")
        }

        // ---- 7-day rolling (today included) ----
        let w7 = (t - c.rollingDays + 1)...t
        let x7 = w7.filter { $0 == t || !(byDay[$0]?.artifact ?? true) }.compactMap { ln(byDay[$0]) }
        if x7.count >= c.minReadingsInRolling, let mu = Stats.mean(x7) {
            m.roll7 = mu; st.roll7[t] = mu
            if let sd = Stats.sd(x7) { m.cv7 = sd / mu * 100; st.cv7[t] = m.cv7 }
        }
        let rhr7v = w7.compactMap { byDay[$0]?.restingHr }
        if rhr7v.count >= c.minReadingsInRolling { m.rhr7 = Stats.mean(rhr7v) }
        if let h = r.rmssdMs, let rh = r.restingHr, rh > 0 { m.ratio = h / rh }
        let ratios = w7.compactMap { d -> Double? in guard let h = byDay[d]?.rmssdMs, let rh = byDay[d]?.restingHr, rh > 0 else { return nil }; return h / rh }
        m.ratio7 = Stats.mean(ratios)

        // ---- range (with device floor and widening) ----
        var widen = 1.0
        if sub.inWindow { widen = max(widen, c.changePointRangeMultiplier) }
        if alt.isTrip && !alt.acclimatized && (alt.tripDay ?? 0) <= c.altitudeAcclimatizationDays { widen = max(widen, c.altitudeRangeMultiplier) }
        let floor = Foundation.log(1 + c.deviceErrorHrvPct / 100)
        if let mu = m.baselineMean, let sd = m.baselineSD {
            let cvBase = sd / mu * 100
            var band: Double
            switch c.rangeMethod {
            case .cvSWC: band = mu * c.cvMultiplier * cvBase / 100
            case .fixedSWC: band = Foundation.log(1 + c.swcHrvPct / 100)
            case .sdBand: band = c.sdMultiplierM * sd
            }
            band = max(band, floor) * widen
            m.band = band; m.normalLow = mu - band; m.normalHigh = mu + band
            func cls(_ v: Double?) -> RangeStatus { guard let v else { return .noBaseline }; return v < mu - band ? .below : v > mu + band ? .above : .inside }
            m.statusDaily = cls(m.lnRmssd); m.status7 = cls(m.roll7)
            let cvs = baseDays.compactMap { st.cv7[$0] }
            if cvs.count >= c.minReadingsInRolling { m.cvBaseline = Stats.mean(cvs) }
        }
        let rhrBase = baseDays.compactMap { byDay[$0]?.restingHr }
        if rhrBase.count >= c.minBaselineDays, let rb = Stats.mean(rhrBase) {
            m.rhrBaseline = rb
            if let r7 = m.rhr7 {
                let b = max(c.rhrBandPct, c.deviceErrorRhrPct) / 100
                m.rhrState = r7 > rb * (1 + b) ? .high : r7 < rb * (1 - b) ? .low : .normal
            }
        }

        // ---- wellness (G2) ----
        var subjBad = false
        if let w = r.wellness {
            var zs: [Double] = []
            for i in 0..<5 {
                guard let v = w.items[i] else { continue }
                let hist = ((t - c.wellnessWindowDays)...(t - 1)).compactMap { byDay[$0]?.wellness?.items[i] }
                if hist.count >= c.wellnessMinDays, let mu = Stats.mean(hist), let sd = Stats.sd(hist), sd > 0 { zs.append((v - mu) / sd) }
            }
            if let z = Stats.mean(zs) { m.wellnessZ = z; subjBad = z < c.wellnessBadZ }
        } else if let s = r.subjective { subjBad = s <= c.subjectiveSingleBadAtOrBelow }

        // ---- trends (14 d) ----
        let tw = (t - c.trendWindowDays + 1)...t
        m.trendRoll7PerDay = Stats.slope(tw.compactMap { d in st.roll7[d].map { (Double(d), $0) } })
        m.trendCvPerDay = Stats.slope(tw.compactMap { d in st.cv7[d].map { (Double(d), $0) } })

        // ---- quality gate ----
        if c.qualityGateEnabled, let x = m.lnRmssd, let hiR = m.normalHigh, let sd = m.baselineSD, x > hiR + prof.artifactK * sd {
            st.gated.insert(t); a.prompts.append("This reading is unusually high; please re-measure (artifacts inflate HRV) [A-ARR]"); a.confidence = .low
        }
        if r.artifact { a.prompts.append("Reading flagged as noisy; re-measure if you can"); a.confidence = .low }
        let timing = r.takenBeforeReading.filter { id in c.substances.first { $0.id == id }?.timing ?? false }
        if !timing.isEmpty { a.confidence = .low; a.prompts.append("Next time take your reading before: \(timing.joined(separator: ", "))") }
        if r.alcoholPreviousEvening { a.annotations.append("Alcohol last night: HRV is often ~12% lower; this day is kept out of your baseline [A-P2021]") }
        if sub.inWindow { a.confidence = .low; a.annotations.append("Baseline rebuilding after a supplement/medication change (\(c.changePointWindowDays) days, range widened) [EC]") }

        a.metrics = m
        decide(&a, r: r, m: m, prof: prof, p: p, alt: alt, sub: sub, subjBad: subjBad, byDay: byDay, st: &st)
        return a
    }

    func decide(_ a: inout Assessment, r: DayRecord, m: Metrics, prof: ResolvedProfile, p: UserProfile, alt: AltitudeState,
                sub: SubstanceState, subjBad: Bool, byDay: [Int: DayRecord], st: inout RunState) {
        let c = config, t = r.day
        // streak bookkeeping (always, so later days see it)
        st.lowStreak = m.status7 == .below ? st.lowStreak + 1 : 0
        let rhrHigh = m.rhrState == .high
        let hrvLowAny = m.status7 == .below || m.statusDaily == .below
        st.allBadStreak = ((hrvLowAny || m.status7 == .above) && rhrHigh && subjBad) ? st.allBadStreak + 1 : 0

        // ---- gates that switch advice off ----
        if prof.modifiers.contains(.clinical) || !sub.disabled.isEmpty {
            a.decision = .adviceOff
            a.reasons.append("Your medication or condition changes heart rate and HRV, so recovery advice is off. Please ask your doctor.")
            a.tags += ["DEH2009", "TAN2018", "A-ARR"]; if !sub.disabled.isEmpty { a.reasons.append("Active: \(sub.disabled.joined(separator: ", "))") }
            return
        }
        if r.amsSymptoms && alt.isTrip {
            a.decision = .stopAndDescend; a.reasons.append("Altitude sickness symptoms: stop, go down, get medical help"); a.tags += ["KAR2012", "TSA2025"]; return
        }
        if r.illnessSymptoms || r.headImpact || r.irregularRhythm {
            a.decision = .medicalRefer
            a.reasons.append(r.headImpact ? "Head impact: see a doctor before training" : r.irregularRhythm ? "Possible irregular heart rhythm: see a doctor" : "Illness symptoms: rest and check with a doctor")
            a.tags += ["F2019C", "A-ARR"]; return
        }
        if prof.modifiers.contains(.pregnant) {
            a.decision = .dataOnly; a.reasons.append("We'll show your data but won't give training advice. Please follow your doctor or midwife."); a.tags += ["A-MENS", "BOS2023"]; return
        }

        // ---- cold start (G14) ----
        if m.baselineMean == nil || m.statusDaily == .noBaseline && m.status7 == .noBaseline {
            a.decision = .coldStart; a.reasons.append(AgeAncestry.coldStartNote(p)); a.tags += ["SEI-X2025", "MAN2021", "EC"]; return
        }
        if c.decisionRule == .coreV01 { return coreV01(&a, m: m, subjBad: subjBad) }
        if m.status7 == .noBaseline {
            a.decision = .coldStart; a.reasons.append("Need at least \(c.minReadingsInRolling) readings in the last \(c.rollingDays) days [P2014]"); return
        }

        // ---- red flags ----
        if st.lowStreak >= c.persistentLowReferDays {
            a.decision = .medicalRefer; a.reasons.append("7-day HRV below your normal range for \(st.lowStreak) days: rest and see a doctor"); a.tags += ["F2021FB", "EC"]; return
        }
        if st.allBadStreak >= c.persistentReferDays && r.performanceDown {
            a.decision = .medicalRefer; a.reasons.append("HRV, resting HR and how you feel have all been off for two weeks while performance drops: see a sports-medicine doctor"); a.tags += ["CAR2022", "SCW2016", "EC"]; return
        }

        // ---- votes (G3) ----
        var hrvVote = hrvLowAny
        var hrvDaily = m.statusDaily == .below
        let deficit = r.caloricDeficit || sub.active.contains("glp1")
        if deficit {   // [A-NORM]: weight loss lowers RHR, use HRV:HR
            a.annotations.append("Calorie deficit / weight loss: HRV judged together with resting HR [A-NORM]")
            if m.rhrState == .low { hrvVote = m.status7 == .below; hrvDaily = false }
        }
        // expected dip after yesterday's session family / weekend warrior Monday-Tuesday
        if hrvDaily && m.status7 != .below {
            var expected = false
            for k in 1...max(1, Int(prof.expectedDipDays.rounded(.up))) {
                if let s = byDay[t - k]?.sessions, s.contains(where: { $0.load > 0 }) && Double(k) <= max(prof.expectedDipDays, 1) {
                    let fam = ProfileClassifier.family(of: s.max { $0.load < $1.load }!.type, c)
                    if (c.families[fam]?.expectedDipDays ?? 1) + (prof.modifiers.contains(.masters) ? c.mastersExtraDipDays : 0) >= Double(k) { expected = true; break }
                }
            }
            let wd = DayIndex.weekday(t)
            if prof.modifiers.contains(.weekendWarrior) && (wd == 0 || wd == 1) { expected = true; a.annotations.append("A dip after a big weekend is expected; we judge your full week [EC, HYN2010]") }
            if expected {
                hrvVote = false
                a.annotations.append("Today's dip fits your recent session; only the 7-day trend counts [A-YT4]")
            }
        }
        if r.lutealPhase && hrvVote && !rhrHigh && !subjBad {
            hrvVote = false; a.annotations.append("Luteal phase: a lower HRV alone does not count [SCM2020][DEJ2026]")
        }
        if prof.modifiers.contains(.femaleCycle) && r.lutealPhase { a.tags.append("A-MENS") }
        if prof.modifiers.contains(.eliteSaturationWatch) && hrvVote && m.rhrState == .low {
            hrvVote = false; a.annotations.append("HRV down with resting HR down: often saturation in very fit athletes, not fatigue [P2017R][P2013]")
        }
        var rhrVote = rhrHigh
        if r.taper && rhrHigh { rhrVote = false; a.annotations.append("Taper: higher resting HR is not counted [A-G2]") }
        var votes: [String] = []
        if hrvVote { votes.append("hrv_low") }
        if rhrVote { votes.append("rhr_high") }
        if subjBad { votes.append("feeling_bad") }
        // G7 scatter
        if let cv = m.cv7, let cb = m.cvBaseline, prof.cvRule, cv > c.cvScatterMultiplier * cb {
            a.annotations.append("Readings unsettled this week (day-to-day HRV swings are bigger than usual) [SCH2013]")
            if hrvVote && m.status7 == .below { votes.append("hrv_scatter") }   // trend-level low only, so one odd day is not double-counted (EC)
        }
        votes = Array(votes.prefix(3))

        var d: Decision = votes.count >= c.votesRequiredForRecover ? .recover : votes.isEmpty ? .trainAsPlanned : .reduceIntensity
        a.tags += ["NUU2024", "BUC2014"]
        if d == .recover { a.reasons.append("Two or more signals are off (\(votes.joined(separator: ", "))): rest or easy only") }
        else if d == .reduceIntensity { a.reasons.append("One signal is off (\(votes.joined(separator: ", "))): keep it easier today [A-HGT][MR2021]") }

        // G12 illness
        let respHist = ((t - c.illnessRespWindowDays)...(t - 1)).compactMap { byDay[$0]?.respRate }
        if let rr = r.respRate, respHist.count >= c.minBaselineDays, let mu = Stats.mean(respHist), let sd = Stats.sd(respHist),
           rr > mu + c.illnessRespSD * sd && rhrHigh {
            d = .recover; a.reasons.append("Possible illness (breathing rate and resting HR up): rest and check symptoms"); a.tags += ["MIL2020", "SCW2016"]
        }

        // above range: neutral, never a push signal
        if d == .trainAsPlanned && (m.statusDaily == .above || m.status7 == .above) {
            if m.rhrState == .low || r.recentMajorStressor {
                d = .reduceIntensity; a.reasons.append("HRV above range with low resting HR or a recent big stressor: your body may be busy recovering [A-HIGH]")
            } else { a.reasons.append("Above your normal range: neutral, not a signal to push harder [MR2021][A-PUSH]") }
            if let age = p.ageYears, age >= 60, m.rhrState != .low {
                a.annotations.append("Unusually high HRV: mention it to your doctor if it persists [GEO2020][A-HIGH]")
            }
        }
        // trends (P2012): only when the move over the window exceeds the band
        if d == .trainAsPlanned, let tx = m.trendRoll7PerDay, let tc = m.trendCvPerDay, let band = m.band,
           tx < 0, abs(tx) * Double(c.trendWindowDays - 1) > c.trendMinChangeFractionOfBand * band {
            if tc < 0 { d = .reduceIntensity; a.coachFlags.append("NFOR risk: HRV trending down with shrinking variation [P2012][A-G2]") }
            else if tc > 0 { d = .reduceIntensity; a.coachFlags.append("Poor adaptation: HRV trending down with growing variation [A-G2][F2017S]") }
        }
        // altitude soft rule (§10)
        if alt.isTrip && !alt.acclimatized {
            a.confidence = .low
            let res = Self.altitudeSoftRule(core: d, corroborated: rhrHigh || subjBad, tripDay: alt.tripDay ?? 1, config: c)
            d = res.decision; a.reasons += res.reasons; a.annotations += res.annotations
        }
        if let back = alt.daysSinceReturn { a.annotations.append("Back home day \(back): altitude days are kept out of your baseline; HRV may still be settling (EC)") }
        // during a change-point window RECOVER needs RHR or feeling bad as well (§9)
        if sub.inWindow && d == .recover && !(rhrVote || subjBad) { d = .reduceIntensity }
        // strength/oly yesterday: HRV inside != cleared for max [F2019RT]
        if prof.nmCheck, d == .trainAsPlanned, let y = byDay[t - 1]?.sessions,
           y.contains(where: { ["OLY", "STRENGTH", "HYPERTROPHY"].contains(ProfileClassifier.family(of: $0.type, c)) }) {
            a.prompts.append("Check bar speed, top-single RPE or soreness before max efforts [F2019RT]")
        }
        if prof.modifiers.contains(.weightCut) { a.annotations.append("A normal HRV never means a weight cut is safe [YIL2026]") }
        if prof.modifiers.contains(.youth) { a.annotations.append("Under 18: a guardian should see this advice; no weight-cut advice") }
        if prof.modifiers.contains(.shiftWorker) { a.prompts.append("Measure when you wake from your main sleep, whatever the time [A-MORN]") }
        if let s = r.sleepHours, s < c.shortSleepHours { a.annotations.append("Short sleep (\(String(format: "%.1f", s)) h) [MIL2022]") }
        if r.lowPsychResources { a.annotations.append("High life stress this week: expect smaller gains [RUU2012][COY2018]") }
        if let l = a.load?.loadChangeVsUsual { a.annotations.append(String(format: "Load change vs usual: %.2f (context only)", l)) }
        a.decision = d
        a.metrics.votes = votes
    }

    /// Spec §10 soft rule for a visitor at altitude (pure; mirrors the 'Supplements & Meds' sheet B62/B63).
    /// `corroborated` = resting HR high OR feeling bad.
    public static func altitudeSoftRule(core: Decision, corroborated: Bool, tripDay: Int, config c: AdaptiveConfig)
        -> (decision: Decision, reasons: [String], annotations: [String]) {
        var d = core, reasons: [String] = []
        if c.altitudeNoRedAlone {
            if core == .recover && !corroborated { d = .reduceIntensity; reasons.append("Altitude: no red day from altitude alone (EC)") }
            else if core == .reduceIntensity && !corroborated { d = .trainAsPlanned; reasons.append("Altitude: train as planned, go by feel (EC)") }
        }
        let note = tripDay <= 3 ? "Days 1-3 at altitude: HRV usually lower, sleep may be worse [LI2025][PIR2025]"
                                : "Acclimatizing: HRV can stay lower for 10+ days [PIR2025]"
        return (d, reasons, [note])
    }

    /// v0.1 §3 core rule, identical to the spreadsheet's 'Adaptive HRV' DECISION column.
    func coreV01(_ a: inout Assessment, m: Metrics, subjBad: Bool) {
        if m.statusDaily == .noBaseline { a.decision = .coldStart; return }
        var d: Decision
        if m.status7 == .below || (m.statusDaily == .below && (m.rhrState == .high || subjBad)) { d = .recover }
        else if m.statusDaily == .below { d = .reduceIntensity }
        else if m.statusDaily == .above || m.status7 == .above { d = (m.rhrState == .low || subjBad) ? .reduceIntensity : .trainAsPlanned }
        else { d = .trainAsPlanned }
        if d == .trainAsPlanned && subjBad { d = .reduceIntensity }
        a.decision = d; a.tags += ["P2012", "A-G2", "MR2021"]
    }
}
