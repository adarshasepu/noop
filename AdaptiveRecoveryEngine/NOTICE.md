# AdaptiveRecovery engine — ownership and licence notice

This folder (`AdaptiveRecoveryEngine/`) is **Adarsh's original work**, written from scratch from:

- his own HRV algorithm spec (`hrv-algorithm-spec.md` v0.6, §1–13) and parameter file (`params.json`),
- his own spreadsheet formulas (`noop_vision_scoring_v2.xlsx`),
- public research (citation tags such as `[P2012]`, `[A-G2]`, `[F2019C]` refer to the sources list in the spec).

It copies **no NOOP source code**, imports no NOOP module and has no dependency besides Foundation.

**Licence: still to be decided by the author.** It sits in this fork only for convenience. The NOOP repository's
PolyForm Noncommercial 1.0.0 licence covers NOOP's own code. Whether files committed in this fork are treated as
covered by it has not been settled here. Before any commercial use, move this folder to its own repository with an
explicit licence and get legal advice.

The only NOOP-specific glue is `Packages/StrandAnalytics/Sources/StrandAnalytics/AdaptiveRecoveryBridge.swift`
(and its test), which is part of NOOP and follows NOOP's licence.
