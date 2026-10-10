# Plan 002 — Post-v3 cleanup: unbuilt widgets, fmt, doc-comment audit round 3

## Goal

Close the loose ends v3.0.0 left behind so that every file in the repo compiles under 0.16 and
is `zig fmt` clean, then finish the doc-comment-vs-implementation audit that plan 001 displaced
(inherited milestone v2.100.0 round 3). Ships as **v3.1.0**.

## Why now

The 0.16 migration (plan 001, PR #40) only touched code reachable from a test root. Eight widget
files and one Windows helper still call the removed `ArrayList(T).init(allocator)`
(`debugger`, `streaming_table`, `virtuallist`, `richtext`, `multicursor`, `theme_editor`,
`websocket`, `metricspanel`, plus `src/term/windows.zig:554`), so `zig build bench-large-data`
and `examples/clipboard_demo.zig` do not build, and nothing in CI notices. `zig fmt --check`
passes on `src` and `build.zig` but flags 69 files under `tests/`; CI does not run it, though
the kingdom rule says every commit passes it. The consumers (zr, silica, zoltraak) are migrating
onto v3.0.0 now, so a clean tree is cheapest to land before they start filing issues.

## Scope

All items are `blocked_by: none`. Each item is one cycle and one PR. Order is the order of
risk, lowest first.

- [x] **Unbuilt-code sweep.** Replace the removed `ArrayList(T).init(allocator)` form with
      `.empty` plus per-call allocator in the nine files above. Add each widget to a test root
      so it is analysed (the orphan bug seen three times before), and fix whatever else 0.16
      breaks in them. *Verify:* `zig build`, `zig build bench-large-data` and
      `examples/clipboard_demo.zig` compile; each newly analysed widget has a test that fails
      before the fix; `grep -rn 'ArrayList([^)]*)\.init(' src examples benchmarks` is empty.
- [x] **CI builds everything.** Add a CI step that compiles all examples and benchmark targets
      (compile only, not run) so the orphan class cannot return; add `zig fmt --check src
      build.zig tests examples benchmarks` to the Linux job. *Verify:* the step fails on a
      deliberately reverted file in the PR branch before it is fixed. (`tests` joins the fmt
      check when item 3 makes it clean.)
- [ ] **`zig fmt` on `tests/`, `examples/`, `benchmarks/`.** One mechanical PR, no logic
      changes; confirm the diff is whitespace only by comparing `zig ast-check` output or test
      counts before and after. *Verify:* `zig fmt --check` over the whole repo is empty.
- [ ] **`terminal.zig` `AnsiParseState` wiring.** The doc comment promises that the widget
      interprets ANSI sequences; `ansi_state` is a field that `render()` never consults.
      Wire parsing into the write path, with invalid and truncated sequences handled as
      returned data errors, never asserted. *Verify:* RED tests render colored output through
      the widget and read the cell styles back.
- [ ] **`pager.zig` soft-wrap.** Implement the documented soft-wrap or correct the doc comment
      if the architect pass in the PR concludes wrapping belongs to `paragraph`. *Verify:*
      wrapped and unwrapped renders differ in a test for a line wider than the area; width
      boundaries 0, 1, exact fit, fit + 1.
- [ ] **`metrics_dashboard.zig` and `richtext.zig` scope decision.** Per widget, list each
      behavior the doc comment promises, then either wire it up or edit the doc comment, and
      record which in the PR body. The two widgets may split into two PRs if the first
      consumes the cycle. *Verify:* each promised behavior is covered by a test or no longer
      promised.
- [ ] **Typed errors for the four non-provable `catch unreachable` sites**
      (`event_metrics` 181, 248; `render_metrics` 186, 255; `smart_autocomplete` 41, 43;
      `editor` 97). The caller-supplied allocator can fail, so the functions return
      `error{OutOfMemory}` instead of claiming a proof. *Verify:* failing-allocator tests
      provoke each error; the tidy baseline shrinks accordingly.
- [ ] **Release v3.1.0** once the items above are checked (see Version impact).

## Out of scope

- `paragraph.zig` word/char wrap and RTL/bidi (needs an architect pass and an ADR; plan 003).
- Splitting the 53 files over 800 lines, and the 13 `while (true)` loops (per-site judgment;
  plan 003).
- Anything in zr, silica, or zoltraak; they receive changes only through
  `migration,from:sailor` issues.
- New widgets or new public API beyond what items above require.

## Risks

- Newly analysed widgets may carry more 0.16 breakage than the `ArrayList` call shown by grep;
  an item that outgrows one cycle splits by file, and the leftover files stay listed in the
  PR body so the checklist stays honest.
- A whitespace-only `zig fmt` PR on `tests/` conflicts with any other open test PR; land it
  while no other PR is open.
- Windows CI flakes (mindmap runner timeout seen 2026-10-06) can delay merges; rerun the job
  once, and treat a second failure as real.
- Wiring `terminal.zig` and `pager.zig` changes rendered output; consumers using these
  widgets see a behavior change, so the release note names them.

## Done when

- `zig build`, `zig build test`, every example and every benchmark target compile on 0.16.0.
- `zig fmt --check` over `src build.zig tests examples benchmarks` is empty and CI enforces it.
- CI compiles examples and benchmarks.
- Each doc comment audited in this plan matches its implementation, or states what is not done.
- The `tidy` baseline has shrunk and never grown.

## Version impact

MINOR (v3.1.0): behavior is added to `terminal` and `pager`, and four functions gain an
`OutOfMemory` error variant, which is source-compatible for callers that already use `try`.
If the typed-error item changes a signature a consumer pattern-matches exhaustively, the PR
escalates to the owner before the release.
