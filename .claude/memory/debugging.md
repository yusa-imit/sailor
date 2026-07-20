# Sailor Debugging Notes

> Compressed 2026-07-17 (session 375) — kept patterns with ongoing/future relevance, dropped
> narrative detail on one-off fixes now fully resolved. Full history in git log if needed.

## Known Zig 0.15.x Gotchas (from zr experience)
- `std.ArrayList(T){}` not `.init(allocator)` — unmanaged API
- ArrayList methods need allocator: `list.deinit(allocator)`, `list.append(allocator, item)`
- `std.Thread.sleep(ns)` not `std.time.sleep`
- `child.wait()` closes stdout — read stdout BEFORE wait()
- `callconv(.c)` lowercase in 0.15
- Buffered writers: flush before `std.process.exit()`
- File-scope: `const X = expr;` (no `comptime` keyword — redundant error)
- `zig build test` uses `--listen=-` protocol — NEVER use `stdout()` in test code
- Ambiguous type references: Use module-level references (`const mod = @This()`) when re-exporting types
- On Windows, `posix.fd_t` is `*anyopaque` (HANDLE), not `i32` — don't treat handles as integers
- `std.posix.getenv()` doesn't exist on Windows (env vars are UTF-16) — guard with
  `if (windows) return false; else { getenv() }`, NOT an early-return before the call (compiler
  still analyzes the "unreachable" branch and fails to compile it on Windows targets)
- `@floatFromInt` in struct literals needs explicit `@as(f32, ...)` wrapping
- Pin macOS ARM64 CI runner to macos-15 — macos-latest→26 broke Zig 0.15.2 linking
- `value * bar_count / (max + 1)` style scaling math on `u64` inputs can genuinely overflow
  (integer-overflow panic, not just UB) when `value` is near `u64::max` — widen to `u128` for the
  multiply/divide rather than clamping `value` first (session 388, `sparkline.zig getBarChar`);
  `u128` safely holds the product since the other operand — an on-screen glyph count — is always
  small in practice
- `std.math.clamp(val, lo, hi)` does NOT sanitize `NaN` — `NaN < lo` and `NaN > hi` are both false,
  so `NaN` passes through unclamped and can later panic an `@intFromFloat` cast downstream. Flagged
  (not yet fixed) in session 388 for widgets that clamp a public `ratio`/`value` field via
  `std.math.clamp` before casting (`gauge.zig`, `reactive.zig`, `splitpane.zig`, likely others) —
  only reachable if a caller constructs the struct literal directly with `NaN` rather than going
  through the clamping builder method.

## Test-Quality Anti-Patterns (recurring — audit for these every STABILIZATION session)

### 1. Weak disjunction: `<specific_claim> or countNonEmptyCells(...) > N`
Lets a test pass even when the specific claimed behavior (a marker char, border, label text) never
renders, as long as SOME unrelated content occupies the area. Masked a real backwards-comparison
bug in BoxPlot (session 354) and a real FlowChart render-order bug (session 375, see below).
**Fix**: assert the specific claim directly; drop the `countNonEmptyCells` fallback unless the test
name itself is genuinely generic ("produces content") with no specific claim to check.
Swept clean as of session 375 (26+ instances across sessions 360/370, plus 15 more in
bubble_chart/flowchart/gantt/gantt_chart/matrix_view found in session 375).

### 2. Placeholder `expect(true)` — literal no-op assertions
Comment says "Placeholder; implementation will set style" or similar — the test always passes
regardless of implementation. Found in toggle_switch_test.zig (session 375, widget added session
374): fixing "applies base style to items" uncovered that `ToggleSwitchGroup.style` was never
applied to items at all. **Detection**: `grep -rn "expect(true)\|expect(1 == 1)" tests/*.zig`.
The project convention (confirmed across 12 "does not panic" tests elsewhere) is that even
panic-safety tests pair the check with a real assertion of resulting buffer/cell state.

### 3. Whole-area scans hide asymmetric/positional bugs (session 351, StreamGraph)
Geometric/symmetry assertions that scan the entire `area` (including label/border columns) can be
satisfied by unrelated content (labels, borders, focus markers) landing in the checked region by
coincidence, rather than the property actually being verified. **Fix**: restrict scans to the
data-plot sub-rect excluding label/border columns, or render with `show_labels=false`/no block when
asserting a geometric property of plotted data itself.

**Process insight (session 375)**: a widget being "uncommitted but `zig build test` green" (the
session 363/369/374 pattern) is NOT evidence its tests are meaningful — apply the same
weak-assertion scrutiny to newly-found work as to old files. Two real bugs shipped in v2.92.0
(FlowChart render order predates v2.92.0; ToggleSwitchGroup.style bug was net-new) and only
surfaced when stabilization forced weak assertions into strict ones.

## Resolved Compilation/API Migration Issues (compressed)
- **Zig 0.15 ArrayList/Thread API migration** (sessions 20, 45-75): unmanaged ArrayList, explicit
  allocator params, `std.Thread.sleep` — see gotchas list above, all call sites fixed.
- **Windows fd_t/getenv compilation failures** (sessions 45-75, commits fb40a43/26f507e/b30ff59):
  fully resolved, all 6 cross-compile targets green since session 75.
- **UTF-8 byte-vs-codepoint bugs** (Buffer.setString session ~feb, Menu submenu indicator session
  18): iterating `for (str) |c|` treats UTF-8 multi-byte sequences as individual bytes — always
  decode via `std.unicode.Utf8View`/`utf8Decode()` for user-facing text.
- **"Test suite hangs" (session 90)**: was never root-caused but has not recurred in 280+ sessions
  since — `zig build test` completes reliably (debug prints from stack_trace.zig tests are expected
  stderr output, not a hang symptom). Considered stale; re-open only if the hang actually recurs.
