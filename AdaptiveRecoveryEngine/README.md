# AdaptiveRecovery

A device-agnostic, per-user adaptive HRV recovery engine in pure Swift (Foundation only; builds and tests on Linux,
macOS, iOS, watchOS). See NOTICE.md for ownership and licence status. **Training guidance, not a medical device.**

## What it does (spec section → file)
| Spec | What | File |
|---|---|---|
| §1–2 | ln rMSSD, 7-day rolling mean (min 3), 60-day baseline excluding today (min 14), normal range (METHOD_A CV-based / B fixed SWC / C SD band) with 6 % device-error floor, CV7, RHR state, HRV:RHR ratio | `AdaptiveRecoveryEngine.swift` |
| §3, §11 | Decisions: TRAIN_AS_PLANNED / REDUCE_INTENSITY / RECOVER by 2-of-3 vote (HRV low, RHR high, wellness z < −0.5); above range is neutral; CV scatter; trends; red flags → MEDICAL_REFER | `AdaptiveRecoveryEngine.swift` |
| §4, G4, G10 | Training load: tonnage, effective sets × f(RIR), sRPE × min, acute/chronic, monotony, strain, ACWR **context only** | `TrainingLoad.swift` |
| §7–8 | Profile families, classifier, hybrid blend, quiz prior with 20-session takeover, modifiers | `ProfileClassifier.swift` |
| §9 | Supplements/meds: annotate, timing, 14-day change point (×1.5 range), disable + refer | `AdaptiveConfig.swift` (registry), engine |
| §10 | Altitude soft rule: resident / visitor (no red from altitude alone) / back home | engine `altitudeSoftRule` |
| §12 | Age & ancestry: Tanaka HRmax (208 − 0.7·age) with measured override, zones, cold-start text, 60+ notes, optional display norm, South Asian info card. **Ancestry is never a decision input** (tested). | `AgeAncestry.swift` |
| §13 hook | `CohortPriorProvider` (default no-op) for partial pooling, blended n/(n+k) | `CohortPriors.swift` |
| §5, G15 | Per-user recovery cost per session family (EWMA + shrinkage). Research flag, off, log-only | `ResponseLearner.swift` |
| inputs | `RecoveryDataSource` protocol + `RawMeasurement` (RR intervals or rMSSD); `RRProcessing.rmssd` | `DataSource.swift` |

## Tuning without code changes
All numbers live in `AdaptiveConfig`. `AdaptiveConfig.bundled()` = Swift defaults + `Resources/params.json`
(the research params file, `{value, ec, sources}` format; unknown keys are ignored). Override with
`AdaptiveConfig.load(paramsJSON:)` or `config.merging(overrideJSON:)` (camelCase keys of `AdaptiveConfig`), or put an
`engine_overrides` object inside params.json. Most future fixes should be a params.json edit plus a test.

## Tests
`swift test` — 46 XCTest cases, including exact parity with the spreadsheet's 'Adaptive HRV' tab (70 days: every
ln/rolling/baseline/range/CV/RHR/ratio value and all 70 decisions) and 'Training Load' tab, the 4 altitude cases and
the 5 noop example days.

## What is evidence vs engineering choice
Every rule carries source tags in its reason/tag output; `EC` marks engineering choices (thresholds such as the
60-day window, 2-of-3 vote, 14-day change point, 1.5× widening, 1000 m trip delta, 0.6/0.15 profile shares, k = 20).
