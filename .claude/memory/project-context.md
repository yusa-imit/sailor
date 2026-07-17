✅ **Session 377** — FEATURE MODE (2026-07-17). CI green, 0 issues at session start. Found a prior session's fully-implemented-and-passing-but-uncommitted **CalendarHeatmap** widget (467-line widget + 898-line/54-test suite, already wired into `build.zig`/`src/sailor.zig`/`src/tui/tui.zig`, plus a `Calendar.setRange()` helper) — the `.claude/logs/agent-activity.jsonl` diff showed the full TDD cycle (test-writer → zig-developer → code-reviewer) had already run at 2026-07-17T00:28–00:52Z but was never committed. Independently verified via `zig build test` (0 failures) and `zig build` before trusting it, per the recurring session pattern (372/374/376-ish) of "uncommitted-but-green work from a prior cycle." Committed, ran all 6 cross-compile targets sequentially (all green), released **v2.93.0**. Filed consumer migration issues: zr#141, zoltraak#107, silica#119. No feature-request issues open anywhere (sailor/zr/zoltraak/silica) — milestone list is empty again, carried to next session same as 374/375.
  - **Current state**: latest release v2.93.0, 0 open issues, 137 widget files. No active milestones — needs replenishment (2nd consecutive session with nothing to replenish from; may need to proactively propose a widget from PRD gaps rather than waiting on issues).

✅ **Session 375** — STABILIZATION (2026-07-17). CI green, 0 issues at session start. Continued the session 360/370 weak-disjunction-assertion audit and found 5 files the earlier sweep had missed (`bubble_chart`, `flowchart`, `gantt`, `gantt_chart`, `matrix_view` test suites — 15 instances of `<claim> or countNonEmptyCells(...) > N`). Strengthening these to strict assertions uncovered a **real bug**: FlowChart rendered edges (arrows/labels) before nodes, so node borders overwrote them — fixed render order (nodes first, then edges on top). Released **v2.92.1** (patch).
  - Then found 6 meaningless `expect(true)` placeholder assertions in `toggle_switch_test.zig` (added uncommitted/unverified in session 374's ToggleSwitch find — codebase convention elsewhere always pairs "does not panic" with a real state check, toggle_switch was the outlier). Fixing the "applies base style to items" placeholder uncovered a **second real bug**: `ToggleSwitchGroup.render()` never applied `self.style` (group base style) to items at all — silently dropped since v2.92.0. Fixed with `applyGroupStyle`/`mergeStyles` helpers (group style as base, item's own sub-styles override). Released **v2.92.2** (patch, supersedes v2.92.1).
  - **Process insight**: both bugs were shipped in v2.92.0 and only surfaced because a test-quality audit forced weak assertions into strict ones — reinforces that "meaningful tests only" (CLAUDE.md rule 15) isn't cosmetic, it's the actual bug-detection mechanism. When a newly-added widget/file is found "uncommitted but green" (session 374 pattern), its tests deserve the same weak-assertion scrutiny as older files, not a pass because `zig build test` was green.
  - Full 6-target cross-compile verified for both patch releases. Consumer migration issues filed for v2.92.1 (zr#140, zoltraak#106, silica#118) then updated in-place with a comment pointing to v2.92.2 rather than filing 3 more duplicate issues.
  - **Current state**: latest release v2.92.2, 0 open issues, 135 widget files. No active milestones (still needs replenishment — carried over from session 374, not addressed this cycle since stabilization work took priority).

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
