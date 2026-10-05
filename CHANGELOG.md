# Changelog

All notable changes to sailor. Versions follow semantic versioning; a MAJOR bump means a
consumer has to change code. History before v3.0.0 is summarised in
[`docs/plans/000-inherited.md`](docs/plans/000-inherited.md) and in the git tags.

## [3.0.0] - 2026-10-05

Zig 0.16.0 migration and Tiger Style baseline (plan 001, milestone #19). The before/after table
for every changed public signature is in [`docs/API.md`](docs/API.md#migrating-to-v300-zig-0160).

### Breaking

- Requires Zig 0.16.0 (`minimum_zig_version`); 0.15.x no longer builds.
- `io: std.Io` convention: functions that touch the clock, sleep, the filesystem, mutexes or the
  terminal take `io` first after the receiver; long-lived owning structs take it in `init` and
  cache it. Affects, among others, `Debouncer`, `Throttler`, `RenderBudget`, `EventBatcher`,
  `ThemeWatcher`, `ThemeLoader.fromFile`, the clipboard functions and the gamepad event
  constructors.
- No global environment access. Code that reads environment variables takes
  `environ_map: *const std.process.Environ.Map`; `debug_log.init(environ_map)` must be called
  at startup, and logging stays off until then.
- Cancelable operations include `error.Canceled` in their error sets; callers must propagate it.
- `sailor.layout.split`: a lone `.min` constraint larger than the span is honored in full and
  the other constraints are squeezed to zero; `split` asserts that area edges are at most 65536.
- `fmt` Table and JSON writers can return the new errors `InvalidConfig`, `CellTooLong` and
  `NonFiniteNumber` (NaN and infinity are not valid JSON); table width math is capped
  (2^20 for configuration, 2^30 for a cell).
- `term.getSize` on Windows returns `TerminalSizeUnavailable` for out-of-range console
  dimensions instead of passing them through, matching the Unix path.

### Added

- `zig build tidy`, run by `zig build test`: line and function length, `//!` module headers,
  proof comments for `catch unreachable` and `@panic`, no `std.debug.print`, `std.time.*` or
  `std.crypto.random` in library code. Existing offenders live in `tidy_baseline.txt`, which
  may only shrink.
- Assertion baseline (positive and negative space, `check_invariants()`, seeded model tests) for
  `term`, `arg`, `tui/buffer`, `tui/layout` and `fmt`, about 175 assertions in total.
- `src/stdx.zig` with the shared `maybe` helper.
- `src/term/win32.zig`, the console externs that Zig 0.16 std dropped.
- `//!` module headers on every file under `src/`.

### Fixed

- `Buffer.fill` and `Rect` edge math overflowed `u16`; `Buffer.renderDiff` emitted an
  uninitialised byte.
- `layout.split` overflowed `u32`, over-committed space and overflowed its offsets.
- `fmt.Table.render` crashed on allocation failure (it freed uninitialised lists); a
  `max_width` of 0 looped forever; short `alignments` slices read out of bounds; CSV fields
  containing `\r` were written unquoted.
- `ErrorInjector` delay tests failed on Windows because they compared wall-clock time; they now
  run against a virtual-clock `Io` double.
- `TimelineEvent.description` is now rendered under each event title.

### Known gaps

- Eight widgets that no test references still use the removed `ArrayList(T).init`
  (`websocket`, `theme_editor`, `metricspanel`, `debugger`, `richtext`, `multicursor`,
  `virtuallist`, `streaming_table`), so `bench-large-data` and `examples/clipboard_demo.zig`
  do not build yet.
- About 78 files, mostly under `tests/`, are not `zig fmt` clean; CI does not run
  `zig fmt --check` over them.
