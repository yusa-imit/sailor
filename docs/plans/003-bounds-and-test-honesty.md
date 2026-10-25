# Plan 003 — Tiger Style bounds and test honesty

## Goal

Make every loop in `src/` provably bounded, make tests assert what they claim, fix the one known
multi-cursor bug, and make `Paragraph` do what its doc comment promises (word/char wrap, RTL).
Ships as **v3.2.0**.

## Why now

Plan 002 left four kinds of untruth in the tree. Code: `MultiCursorEditor.deleteCharAll`
(`multicursor.zig:495`) moves every cursor left by exactly 1, so two cursors on one line end up
on the wrong columns; the sibling `insertCharAll` was fixed in plan 002 item 1. Loops: 13
`while (true)` in `src/` that nothing bounds, and tidy does not track them. Tests: a heuristic
scan finds ~1,050 of ~13,860 test blocks with no `expect`/`assert` (344 of them named "does not
crash"), which `testing.md` forbids. Docs: `paragraph.zig` advertises word/char wrapping and
RTL, but `render()` writes one cell per byte, never wraps, and never reads `direction`;
consumers porting their shells to `tui` will reach for `Paragraph` first.

## Scope

All items are `blocked_by: none`. Each item is one cycle and one PR. Bug first, then bounds,
then tests, then the paragraph work, which needs its ADR merged before code.

- [x] **`deleteCharAll` cursor shift.** Each cursor moves left by the number of deletions at or
      before it on its line (not a flat 1); col 0 stays. Assert col <= line length: `addCursor`
      clamps on entry, so that is an invariant, not user data.
      *Verify:* RED tests for two cursors on one line (cols 3, 5 -> 2, 3), col 0, cursors on
      different lines, undo restores; a seeded model test applies the same random cursor sets
      to a single-cursor reference and compares text and cursors after each step.
- [x] **One bounded line rasterizer.** Six Bresenham loops (`canvas` 126, `linechart` 303,
      `radar_chart` 251, `parallel_coordinates` 350, `slope_chart` 400, `chord_diagram` 251)
      stop only on hitting the endpoint exactly; correct today, enforced by nothing. Add one
      helper (`src/tui/line_iter.zig`) that yields at most `max(|dx|,|dy|) + 1` points and
      asserts it reached the endpoint, and route all six through it (one construction path).
      *Verify:* helper tests for length 0, horizontal, vertical, 45°, steep, reversed, far
      off-screen endpoints; the six widgets' existing tests stay green unchanged;
      `grep -n 'while (true)'` on the six files is empty.
- [x] **Remaining seven `while (true)` and a tidy guard.** `focus.zig:336` and
      `workspace.zig:194,211` walk an array: rewrite as `for (0..len)`. `term.zig:482` (Windows
      pipe poll) and `validation.zig:517` are bounded only by the wall clock: add a poll cap of
      `timeout_ms / poll_ms + 2` so a clock that never advances cannot hang them.
      `repl.zig:240` (key read loop) and `validation.zig:453` (worker ended by cancel) are
      top-level loops: keep them with a `// top-level loop:` proof comment. Add a tidy check
      `unbounded_while` (bare `while (true)` without that comment), baseline 0. May split into
      two PRs (sites, then check). *Verify:* tidy unit tests (bare vs commented); a frozen-clock
      `Io` double (`VirtualClock` pattern, `error_recovery_test.zig`) makes
      `getResultWithTimeout` return `error.ValidationTimeout`; Windows CI green for `term.zig`.
- [ ] **Tidy `assertion_free_test` ratchet.** Extend the tidy walk to `tests/` for this one
      check: count `test` blocks whose body has no `expect`, `assert`, or listed helper
      (`expectCell`-style names, documented in `tidy.zig`), recorded per file in the baseline.
      Why: the debt is too large for one plan, so first stop it growing. *Verify:* tidy tests
      on fixtures (asserting, assertion-free, braces inside strings); a scratch test file with
      an assertion-free test fails `zig build tidy`.
- [ ] **Honest tests, round 1: `area_chart_test`, `bullet_chart_test`.** Each assertion-free
      test gains the assertion its guard exists for (NaN/Inf: finite points still plotted, no
      cell written outside the area; tiny area: border corners present or area left blank per
      the doc comment); exact duplicates are deleted. *Verify:* both files reach 0 in the
      `assertion_free_test` baseline; one guard per file reverted locally makes a test fail.
- [ ] **ADR 0001: paragraph wrap and bidi** (`docs/adr/0001-paragraph-wrap-and-bidi.md`,
      architect pass, opus). Decide: no allocation in `render()` while `Bidi.reorder`
      allocates (bounded stack scratch and its overflow fallback vs caller scratch); code
      points and display width via `unicode.zig` instead of bytes; whether `scroll` counts
      visual rows or logical lines (pager chose logical); interaction with justify,
      `first_line_indent`, alignment; whether the `.word` default stays, since wrapping changes
      output for every current caller. A `render` signature change is forbidden (MAJOR).
      *Verify:* ADR merged with Context · Decision · Consequences and a test list for items 7-8.
- [ ] **Paragraph word/char wrap per ADR.** Wrap logic in `paragraph_wrap.zig` so
      `paragraph.zig` (700 lines) stays under 800. *Verify:* RED tests for widths 0, 1, exact
      fit, fit + 1; a word longer than the width falls back to char split; multi-byte and
      width-2 (CJK) text; scroll with wrap; `.none` still truncates.
- [ ] **Paragraph RTL per ADR.** `direction` reaches rendering through `Bidi` without
      allocating in `render()`. *Verify:* RED tests for an RTL line, `.auto` detection, mixed
      RTL with LTR digits, a line over the scratch bound taking the ADR's fallback; if the ADR
      drops RTL instead, the doc comment says so and `withDirection` is documented as a no-op.
- [ ] **Release v3.2.0** once the items above are checked (see Version impact); comment the
      release notes on the consumers' open migration issues (zr#178, silica#163, zoltraak#141)
      or open new ones if those are closed, naming the `Paragraph` behavior change.

## Out of scope

- Splitting the 53 files over 800 lines (worst: `layout.zig` 3631, `term.zig` 2183, `style.zig`
  2172); its own plan (004), since each split is a per-file design judgment.
- The ~1,000 assertion-free tests outside item 5; the ratchet holds them, later plans shrink it.
- Shrinking other tidy categories (`function_length`, `line_length`, ...) beyond incidental wins.
- Public API changes in `arg`, `color`, `repl`, `fmt`, `progress` (item 3 only adds a comment to
  `repl.zig` and an internal cap in `term.zig`); anything in zr, silica, zoltraak; new widgets.

## Risks

- The six Bresenham variants may differ (endpoint included or not, signed vs unsigned steps);
  a shared helper can shift a pixel. Existing render tests catch it; a deliberate visual change
  is named in the PR body, or that widget keeps a local bounded loop.
- The heuristic misses tests asserting through helpers; the helper list is explicit in
  `tidy.zig`; other false positives get a real assertion, not a wider list.
- Wrapping changes `Paragraph` output for every caller using the `.word` default; consumers
  porting shells to `tui` see it, so the release note and migration comments spell it out.
- The ADR may find bounded-scratch RTL unworkable; item 8 then corrects the doc comment.
- `term.zig:482` is Windows-only, so only Windows CI exercises it; on a flake rerun once.

## Done when

- `grep -rn 'while (true)' src` shows only the two `// top-level loop:` sites, and
  `zig build tidy` fails on a bare one.
- `zig build test` green with the `deleteCharAll` regression and model tests on `main`.
- `zig build tidy` enforces `assertion_free_test`; `area_chart_test` and `bullet_chart_test`
  have no entry.
- `docs/adr/0001-paragraph-wrap-and-bidi.md` is on `main`; every feature listed in the
  `paragraph.zig` `//!` comment has a test, or is no longer listed.
- Excluding the new `unbounded_while` and `assertion_free_test` lines, `tidy_baseline.txt` has
  at most 329 entries (today's `grep -v '^#' tidy_baseline.txt | grep -c .`).
- CI green on all targets; tag `v3.2.0` and its GitHub release exist; milestone issue closed.

## Version impact

MINOR (v3.2.0): `Paragraph` gains wrapping and RTL (additive behavior; output changes for the
`.word` default, documented, no signature change) and `deleteCharAll` is fixed. No public
signature in `arg`, `color`, `repl`, `fmt`, or `progress` changes. If the ADR concludes that a
public signature must change, item 7 stops and the question goes to the owner as an issue,
because that would be MAJOR.
