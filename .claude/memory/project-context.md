✅ **Session 374** — FEATURE MODE (2026-07-16)
  - **Mode**: NORMAL (session 374, 374 % 5 == 4)
  - **Achievement**: Found a prior session's fully-implemented-and-passing-but-uncommitted ToggleSwitch widget, verified independently, committed, and released v2.92.0.

  **Completed Work**:
    - ✅ Found uncommitted working tree at session start: `src/tui/widgets/toggle_switch.zig` (360 lines) + `tests/toggle_switch_test.zig` (66 tests) already wired into `build.zig`/`src/sailor.zig`/`src/tui/tui.zig`. Unlike session 372's IcicleChart find, this one was fully green (`zig build test` exit 0, no `@panic`/stdout/global state) — closer to sessions 363/369's "just never committed" pattern than 372's "looked done but wasn't."
    - ✅ Confirmed CI green (latest 3 runs success/cancelled) and 0 open bug issues before treating this as ready. Note: ToggleSwitch was not on the prior future-candidate list (which was empty after v2.91.0/IcicleChart) — it's a form-control widget (slider-style boolean toggle, distinct from Checkbox's tick-mark convention) rather than the recent run of dataviz/chart widgets, but fully justified as its own widget with no overlap.
    - ✅ Committed the widget (b83360f). Ran all 6 cross-compile targets sequentially (linux/macos/windows × x86_64/aarch64, ReleaseSafe) after confirming no concurrent `zig build` process — all exit 0.
    - ✅ Released v2.92.0: bumped build.zig.zon, added milestone entry to docs/milestones.md (retroactive — widget was already built, so documented after the fact rather than before), tagged, pushed, GitHub release created.
    - ✅ Consumer migration issues filed: zr#139, zoltraak#105, silica#117.

  **Current State**:
    - **Latest release**: v2.92.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **Widget count**: 136 widgets in src/tui/widgets/ (toggle_switch added)
    - **Active milestones**: 0 — needs replenishment next session (future-candidate list empty; check `gh issue list --label feature-request` across sailor/zr/zoltraak/silica first)

  **Next Priority**:
    - Establish next milestone from feature-request issues, PRD gaps, or consumer feedback — no widget currently queued.

✅ **Session 372** — FEATURE MODE (2026-07-16). Found a prior session's uncommitted IcicleChart widget (v2.91.0) with 4 genuinely failing tests — root-caused the focused-path bug (was comparing path length vs depth instead of validating the actual index chain) and a second unshipped bug (`show_values` had a hardcoded TODO placeholder behind weak `countNonEmptyCells > 0` tests). **Process insight**: `zig build test` exit code is the only trustworthy "done" signal — never infer completeness from file size or doc-comment polish; when fixing one bug, grep the same file for other TODO/placeholder markers. Released v2.91.0.

✅ **Session 370** — STABILIZATION (2026-07-15). CI green, 0 issues — continued session 360's weak-disjunction-assertion audit (`or countNonEmptyCells(...) > N`) across mindmap/radar_chart/bracket_viewer/wordcloud, fixed 9 instances (bracket_viewer audited clean). Full 6-target cross-compile verified. No release (test-only changes).

✅ **Sessions 363–369** (compressed) — Released v2.86.0–v2.91.0: ParetoChart, SlopeChart, RidgelinePlot, BumpChart, MosaicPlot, IcicleChart. Recurring pattern: several of these were found as prior-session fully-implemented-but-uncommitted work (363/369) — always independently verify via `zig build test` + grep the claimed wiring edits (`src/sailor.zig`/`src/tui/tui.zig`/`build.zig`) before trusting an agent's self-report of test count or wiring completeness (gaps found in sessions 361/364). Session 364 fixed a red Windows CI flake (exact-boundary timing assertion in `profiler.zig` needed ~10% tolerance) before feature work, per protocol (CI-red overrides mode).

✅ **Session 361** — Released v2.84.0 (BulletChart). Process insight: agent claimed `sailor.zig` exports were wired but grep showed they were missing — always verify independently.

✅ **Session 360** — STABILIZATION: found the `countNonEmptyCells(...) > 0` disjunction anti-pattern (masks real bugs, e.g. session 354's BoxPlot) in 26 test files; fixed flowchart this cycle, remainder completed session 370. Released patch v2.83.1.

✅ **Session 357** — Released v2.83.0 (CandlestickChart). Fixed a shipped panic: unclamped OHLC values overflowed `@intCast` on row mapping — clamp both the normalized ratio AND the final row index, not just the lower bound.

✅ **Session 354** — Completed a stalled v2.81.0 release (checklist was `[x]` but version/tag never bumped — a checked box isn't proof, verify against `build.zig.zon` + `git tag -l`) + released v2.82.0 (BoxPlot). Caught a real bug pre-commit: box-drawing `row_q1 <= row_q3` comparison was backwards, masked by weak `countNonEmptyCells > 0` tests.

✅ **Session 352** — Released v2.80.0 (ViolinPlot: mirrored density silhouette, global min/max binning).

✅ **Sessions 346–351** (compressed) — Released v2.75.0–v2.79.0: WaterfallChart, FunnelChart, DotPlot, RadialBar, StreamGraph. Recurring gotchas: `@floatFromInt` in struct literals needs explicit `@as(f32, ...)` in Zig 0.15.x; symmetry assertions must exclude the label column; pin macOS ARM64 CI runner to macos-15 (macos-latest→26 broke Zig 0.15.2 linking).
