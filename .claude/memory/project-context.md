✅ **Session 364** — FEATURE MODE (2026-07-14)
  - **Mode**: NORMAL (session 364, 364 % 5 == 4)
  - **Achievement**: Fixed red CI (Windows timing flake) before feature work, then implemented and released v2.87.0 (SlopeChart widget)

  **Completed Work**:
    - ✅ CI check found latest run RED on main (Windows x86_64 only) — per protocol, fixed this before any feature work regardless of NORMAL mode.
    - ✅ Root cause: `src/profiler.zig` test "flame graph self time excludes children" asserted `total_time_ns >= 2_000_000` after sleeping for an accumulated *exactly* 2ms via 3x `std.Thread.sleep` calls — zero tolerance margin for OS timer imprecision. Windows CI occasionally undershoots `Thread.sleep` by a small amount, causing the exact-boundary assertion to fail intermittently (other platforms/most runs have enough call overhead to clear the boundary). Loosened this and a similarly-tight assertion in the "nested scopes" test to ~10% tolerance (`>= 1_800_000` / `>= 900_000` instead of exact `2_000_000` / `1_000_000`). Verified locally, pushed (609e0c7), watched CI go green on the new commit before proceeding.
    - ✅ TDD Red: test-writer wrote 86 tests in `tests/slope_chart_test.zig` (self-reported 131 — same bookkeeping-drift pattern as session 361/363, harmless, caught by independent grep). Locked in API up front via scratchpad spec before dispatching: `SlopeChart` + `SlopeItem` (label/left_value/right_value/style), two shared-scale value columns, direction-based line char ('/' increase, '\' decrease, '─' flat), style precedence focused > per-item > direction > line default, MAX_ITEMS=16.
    - ✅ TDD Green: zig-developer implemented `src/tui/widgets/slope_chart.zig` (569 lines) reusing ParallelCoordinates' normalizeValue/axisY/Bresenham-line patterns adapted to a fixed 2-column layout, DotPlot's label-column-width computation, and the established focused_style-is-set precedence check.
    - ✅ **Verified agent self-report independently before trusting it** (per session 361 lesson): grepped `src/sailor.zig`, `src/tui/tui.zig`, `build.zig` directly for all 3 claimed wiring edits — all present and correct. Ran `zig build test` myself (exit 0) rather than trusting the agent's "131 tests pass" claim; actual test count is 86 via `grep -c '^test "'`.
    - ✅ All 6 cross-compile targets built successfully (sequential, ReleaseSafe), 0 open `bug` issues — all release conditions met.
    - ✅ Released v2.87.0: bumped build.zig.zon, updated milestones.md (checked off v2.87.0, established v2.88.0 RidgelinePlot milestone from the backlog, queued BumpChart as new future candidate to keep backlog stocked), tagged, pushed, GitHub release created. Filed consumer migration issues: zr#134, zoltraak#100, silica#112.

  **Current State**:
    - **Latest release**: v2.87.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **Widget count**: 130 widgets in src/tui/widgets/ (slope_chart added)

  **Next Priority**:
    - Implement v2.88.0 milestone: RidgelinePlot widget (see docs/milestones.md for scope)

✅ **Session 363** — FEATURE MODE (2026-07-14)
  - **Mode**: NORMAL (session 363, 363 % 5 == 3)
  - **Achievement**: Completed uncommitted v2.85.0 (ParallelCoordinates) fix + release, then implemented and released v2.86.0 (ParetoChart widget)

  **Completed Work**:
    - ✅ CI: latest 3 runs green/cancelled; 0 open issues
    - ✅ Found prior session's uncommitted work: a fix to `parallel_coordinates.zig`'s `axisX()` off-by-one (divided by `inner.width` instead of `inner.width - 1`, dropping/mispositioning the last axis) plus strengthened previously-trivial `>= 0` assertions in `tests/parallel_coordinates_test.zig`. Verified `zig build test` passed, committed (e3680b3).
    - ✅ Discovered the ParallelCoordinates widget itself was already fully implemented, exported (tui.zig/sailor.zig), and wired into build.zig (83 tests) — milestone checklist just hadn't been marked complete. Ran all 6 cross-compile targets (all exit 0), released v2.85.0: bumped build.zig.zon, updated milestones.md, tagged, pushed, GitHub release created. Filed consumer migration issues: zr#132, zoltraak#98, silica#110.
    - ✅ Milestone backlog was empty after v2.85.0 — established v2.86.0 (ParetoChart: descending bars + cumulative % line + 80% threshold marker, MAX_ITEMS=32) from the future-candidate list.
    - ✅ TDD Red: test-writer wrote 86 tests in `tests/pareto_chart_test.zig`. Locked in API: `ParetoChart` + `ParetoItem` (label/value/style), `sorted` bool toggle (descending sort vs. preserve input order), `show_values`/`show_cumulative_line`/`show_threshold` toggles, `threshold: f32 = 0.8`, focused_style precedence pattern matching recent widgets.
    - ✅ TDD Green: zig-developer implemented `src/tui/widgets/pareto_chart.zig` (509 lines incl. bottom test block) — on-stack insertion sort over index array (no heap allocation) for descending order, cumulative-percentage line mapped to an implicit 0–100% scale, safe division-by-zero/negative-value clamping matching BulletChart/CandlestickChart conventions.
    - ✅ **Verified agent self-report against actual files before trusting it** (per session 361's lesson): grepped `src/sailor.zig`, `src/tui/tui.zig`, `build.zig` directly for the 3 claimed wiring edits — all present and correct this time, no gap found.
    - ✅ Full suite passes (`zig build test` 100%), all 6 cross-compile targets exit 0, no `@panic`/`std.debug.print`/global state in the new widget. Committed (2236e1c), pushed.
    - ✅ Released v2.86.0: bumped build.zig.zon, updated milestones.md, tagged, pushed, GitHub release created. Filed consumer migration issues: zr#133, zoltraak#99, silica#111.
    - ✅ Established v2.87.0 milestone: SlopeChart (before/after two-point comparison lines per category, complements DotPlot, MAX_ITEMS=16). Queued RidgelinePlot as the remaining future candidate.

  **Current State**:
    - **Latest release**: v2.86.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **Widget count**: 129 widgets in src/tui/widgets/ (parallel_coordinates already existed; pareto_chart added this session)

  **Next Priority**:
    - Implement v2.87.0 milestone: SlopeChart widget (see docs/milestones.md for scope)

✅ **Session 361** — FEATURE MODE (2026-07-13)
  - **Mode**: NORMAL (session 361, 361 % 5 == 1)
  - **Achievement**: Implemented and released v2.84.0 — BulletChart widget

  **Completed Work**:
    - ✅ CI: latest 3 runs green/cancelled (not RED); 0 open issues
    - ✅ TDD Red: test-writer wrote 88 tests in tests/bullet_chart_test.zig, wired bullet_chart_tests into build.zig, added exports to src/tui/tui.zig. Locked in API: `BulletChart` + `Bullet` (label/value/target/ranges/style), MAX_BULLETS=32, range bands cycling '░'→'▒'→'▓', value bar '█', target tick '│' drawn after the bar so always visible, focused_style "only override if explicitly set" precedence (same pattern as CandlestickChart/BoxPlot).
    - ✅ TDD Green: zig-developer implemented src/tui/widgets/bullet_chart.zig (~400 lines) — all normalized value/target/range-boundary inputs clamped to [0,1] via `std.math.clamp` before column math, `max_value <= 0` guarded with a safe 1.0 fallback denominator. Verified no @panic/stdout/global state.
    - ✅ **Orchestrator caught a gap in the agent's self-report before committing**: zig-developer's completion summary claimed `src/sailor.zig` top-level exports (`BulletChart`, `Bullet`) were already wired, but grepping the file directly showed they were absent — only `tui.zig`'s widgets struct had them. Added the missing 3 `pub const` lines (matching the `CandlestickChart`/`Candle`/`candlestick_chart` pattern) before proceeding. Also noted test-writer's summary claimed 99 tests but the file actually contains 88 (`grep -c '^test "'`) — harmless bookkeeping drift, not a functional issue, but reinforces: verify agent-claimed file changes independently rather than trusting the summary.
    - ✅ All 88 bullet_chart tests + full suite pass (`Build Summary: 306/306 steps succeeded; 10857/10913 tests passed; 56 skipped`)
    - ✅ Committed widget (69c30cd), verified 6/6 cross-compile targets sequentially (linux/macos/windows × x86_64/aarch64, ReleaseSafe) — all exit 0, followed the established FEATURE-mode-release precedent of running cross-compile locally as a release gate even outside a Stabilization session
    - ✅ Released v2.84.0: bumped build.zig.zon, updated docs/milestones.md (checked off v2.84.0, logged the export-gap Known Issue), tagged, pushed, GitHub release created
    - ✅ Consumer migration issues filed: zr#131, zoltraak#97, silica#109
    - ✅ Established v2.85.0 milestone: ParallelCoordinates widget (multi-dimensional data as parallel vertical axes connected by per-item polylines, MAX_AXES=8, MAX_ITEMS=16)
    - ✅ Discord notification sent

  **Current State**:
    - **Latest release**: v2.84.0 (tagged + GitHub release)
    - **Open issues**: 0 (sailor)
    - **Widget count**: 127 widgets in src/tui/widgets/ (bullet_chart.zig added)

  **BulletChart Widget Summary**:
    - Bullet: label/value/target/ranges([]const f32)/style
    - BulletChart: bullets/focused/max_value/show_labels/show_values/style/range_style/bar_style/target_style/focused_style/label_style/block
    - One row per bullet; label column width = max(longest label, 10) when show_labels
    - Range bands cycle '░'/'▒'/'▓' across ranges boundaries; value bar '█' from 0 to value; target tick '│' drawn last so always visible over the bar
    - All normalized ratios clamped to [0,1]; max_value<=0 falls back to 1.0 denominator — no panics on malformed input
    - MAX_BULLETS=32, no heap allocations
    - 88 tests

  **Process Insight — verify agent self-reports against the actual files**:
    - Both subagents in this cycle self-reported slightly inaccurate completion states (zig-developer: claimed sailor.zig exports done, were missing; test-writer: claimed 99 tests, actual 88). Neither was caught by `zig build test` passing, since the missing export only breaks *external* consumers of the top-level `sailor` module, not the widget's own test file (which imports via `sailor.tui.widgets.bullet_chart` directly). Lesson: after any agent claims "exports wired" or a specific count, grep the actual file before trusting the number — this cycle caught it before commit/release, but a less careful pass could have shipped a widget invisible to `sailor.BulletChart` consumers.

  **Next Priority**:
    - Implement v2.85.0 milestone: ParallelCoordinates widget (see docs/milestones.md for scope)

✅ **Session 360** — STABILIZATION MODE (2026-07-13)
  - **Mode**: STABILIZATION (session 360, 360 % 5 == 0)
  - **Achievement**: Test-quality audit — strengthened 4 weak assertions in flowchart_test.zig; verified all 6 cross-compile targets

  **Completed Work**:
    - ✅ CI: latest run on main green; 0 open issues (both sailor and no `bug`/`from:*` labels pending)
    - ✅ `zig build test` — 100% pass before and after changes
    - ✅ Scanned all `tests/*.zig` for the `countNonEmptyCells(...) > 0` weak-assertion anti-pattern (the same shape that hid the v2.82.0 BoxPlot bug — see that milestone entry). Found it in 26 files; most uses are legitimate ("does not crash" tests), but flagged files with a high ratio of the *disjunction* variant (`specific_claim or countNonEmptyCells > 0`), which is strictly worse since it defeats a more specific check: flowchart_test.zig (20/32), mindmap_test.zig (22/43), radar_chart_test.zig (19/31), bracket_viewer_test.zig (12/20), wordcloud_test.zig (13/20)
    - ✅ Delegated to test-writer: audited and fixed the 4 disjunction-pattern tests in tests/flowchart_test.zig. All 4 specific claims verified true against current flowchart.zig — no latent bug found this time; tightened assertions to remove the always-true fallback. Committed 241fc20, pushed.
    - ✅ Ran all 6 CI cross-compile targets locally sequentially — all exit 0
    - ✅ Noticed 2 unreleased `fix:` commits since v2.83.0 (Windows clipboard/env, Windows pipe-stdin readByte hang) — met patch-release conditions, so released **v2.83.1** (tag + GitHub release, no build.zig.zon bump per patch protocol)
    - ✅ Consumer migration issues filed for v2.83.1: zr#130, zoltraak#96, silica#108

  **Next Priority (carried forward, still open)**:
    - Continue the weak-assertion audit on remaining flagged files: mindmap_test.zig, radar_chart_test.zig, bracket_viewer_test.zig, wordcloud_test.zig (same `or countNonEmptyCells > 0` disjunction pattern, not yet audited — could hide a real bug like BoxPlot did)

✅ **Session 357** — Released v2.83.0 (CandlestickChart: OHLC wick+body per period, global min/max scale from high/low only, 79 tests). Fixed a shipped panic: unclamped `open`/`close` outside candle's own high/low overflowed `@intCast` on row mapping — clamp `normalized` to [0,1] AND clamp final row to [0,height-1], not just the lower bound. **Process insight**: found a prior session's fully-implemented-but-uncommitted widget with a crashing edge-case test — always run `zig build test` on found uncommitted work before assuming it's ship-ready.

✅ **Session 354** — Completed a stalled v2.81.0 release (checklist was `[x]` but version/tag never actually bumped — verify claimed-complete releases against `build.zig.zon` + `git tag -l`, a checked box isn't proof) + released v2.82.0 (BoxPlot: five-number-summary via linear interpolation/R-7, MAX_SERIES=8, MAX_SAMPLES=64, 95 tests). Orchestrator review caught a real bug pre-commit: box-drawing loop's `row_q1 <= row_q3` was backwards (row 0 = max value), masked by `countNonEmptyCells > 0` tests — same anti-pattern lesson repeated in sessions 360/361.

✅ **Session 352** — Released v2.80.0 (ViolinPlot: mirrored density silhouette per series, GLOBAL min/max binning across all series, MAX_SERIES=8, MAX_BINS=64, 88 tests, dedicated zero-range fallback path).

✅ **Session 351** — Released v2.79.0 (StreamGraph: whole-stack-centered-on-middle-row silhouette, not per-layer alternating — rewrote after catching a non-genuine single-layer-centering test artifact, MAX_LAYERS=8, 70 tests). Known test-pattern: symmetry assertions must exclude the label column or they can pass on a stray label char alone.

✅ **Session 349** — Released v2.78.0 (RadialBar: concentric-ring arcs, clockwise fill from 12 o'clock, aspect-ratio x*0.5 compensation, MAX_ARCS=8, 88 tests). Known issue: `@floatFromInt` in struct literals needs explicit `@as(f32, ...)` in Zig 0.15.x.

✅ **Session 348** — Released v2.77.0 (DotPlot: label+dashed-line+dot per item, auto-sized label column, MAX_ITEMS=64, 94 tests).

✅ **Session 347** — Released v2.76.0 (FunnelChart: centered proportional bars narrowing top-to-bottom, MAX_STAGES=16, 89 tests).

✅ **Session 346** — Fixed CI red (macos-latest→macOS 26 broke Zig 0.15.2 linking; pinned ARM64 runner to macos-15) + released v2.75.0 (WaterfallChart: relative/absolute/total bar kinds, MAX_BARS=32, 90 tests).
