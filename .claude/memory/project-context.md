# Sailor Project Context

## Overview
- Zig TUI framework & CLI toolkit library
- Library consumed via `build.zig.zon`
- Zero dependencies (Zig stdlib only)
- Cross-platform: Linux, macOS, Windows
- Current version: v0.3.0

## Current Phase
- **Phase 3 — TUI Core (v0.3.0)**: ✅ COMPLETE & RELEASED
- **Phase 4 — Core Widgets (v0.4.0)**: 🚀 IN PROGRESS (4/8 widgets complete)

## Completed Phases

### Phase 1 — Terminal + CLI Foundation (v0.1.0) ✅
- [x] src/term.zig — TTY detection, terminal size, raw mode, key reading
- [x] src/color.zig — ANSI codes, styles, 256/truecolor, NO_COLOR support
- [x] src/arg.zig — Flag parsing, subcommands, help generation
- [x] All tests passing (53 module tests + 68 infrastructure tests = 121 total)
- [x] CI pipeline green
- [x] Released v0.1.0

### Phase 2 — Interactive (v0.2.0) ✅
- [x] src/repl.zig — Line editing, history, completion, highlighting
- [x] src/progress.zig — Bar, spinner, multi-progress
- [x] src/fmt.zig — Table, JSON, CSV output
- [x] All tests passing
- [x] Released v0.2.0

### Phase 3 — TUI Core (v0.3.0) ✅
- [x] src/tui/style.zig — Style, Color, Span, Line (19 tests)
- [x] src/tui/symbols.zig — Box-drawing character sets (19 tests)
- [x] src/tui/layout.zig — Constraint solver, Rect (21 tests)
- [x] src/tui/buffer.zig — Cell grid, double buffering, diff (19 tests)
- [x] src/tui/tui.zig — Terminal, Frame, event loop (6 tests)
- [x] All 96 TUI core tests passing
- [x] Released v0.3.0

## Phase 4 Implementation Plan

**Widgets Status**:
- [x] widgets/block.zig — Borders, title, padding (14 tests)
- [x] widgets/paragraph.zig — Text rendering, wrapping (14 tests)
- [x] widgets/list.zig — Item lists, selection (21 tests)
- [x] widgets/table.zig — Tabular data (27 tests)
- [x] widgets/input.zig — Single-line text input (16 tests)
- [ ] widgets/tabs.zig — Tab navigation
- [ ] widgets/statusbar.zig — Bottom status bar
- [ ] widgets/gauge.zig — Progress gauge

**Next Steps**:
1. Implement remaining 3 widgets (tabs, statusbar, gauge)
2. Ensure each widget has comprehensive tests
3. Release v0.4.0

## Consumer Projects
| Project | Path | Current sailor Usage | Next Migration |
|---------|------|---------------------|----------------|
| zr | ../zr | v0.2.0 arg, color, progress | v0.4.0 TUI widgets |
| zoltraak | ../zoltraak | v0.2.0 arg, color, repl | v0.4.0 TUI (redis-cli) |
| silica | ../silica | v0.2.0 arg, color, repl, fmt | v0.4.0 TUI (SQL shell) |

## Test Status
- **Total Tests**: 206 passing (updated 2026-02-28)
  - Phase 1-2 modules: 68 (term: 5, color: 16, arg: 13, repl: 5, progress: 7, fmt: 13)
  - Phase 3 TUI core: 107 (style: 19, symbols: 19, layout: 26, buffer: 25, tui: 6, widget integration: 12)
  - Phase 4 widgets: 92 (block: 14, paragraph: 14, list: 21, table: 27, input: 16)
- **Cross-platform**: All 6 targets build successfully
  - x86_64-linux-gnu ✓
  - aarch64-linux-gnu ✓
  - x86_64-windows-msvc ✓
  - aarch64-windows-msvc ✓
  - x86_64-macos ✓
  - aarch64-macos ✓
- **CI Status**: GREEN ✓
- **Compiler Warnings**: 0
- **Known Issues**: 0 open bugs

## Recent Work
- **2026-02-28 10:00 (Hour 10 - Feature Cycle)**:
  - FEATURE MODE: Phase 4 widget implementation
  - **CRITICAL BUG FIX #1**: Fixed repl.zig Zig 0.15.x compatibility (issue #1 from silica)
    - Replaced std.io.getStdIn() with std.fs.File.stdin()
    - Issue closed, consumer projects unblocked
  - **FEATURE**: Implemented Input widget (widgets/input.zig)
    - Single-line text input with cursor positioning
    - Horizontal scroll for long text
    - Placeholder support
    - Unicode/UTF-8 handling (CJK, emoji)
    - 16 comprehensive tests
  - Progress: 5/8 Phase 4 widgets complete
  - All 206 tests passing
  - Cross-platform builds verified (6/6 targets)

## Architecture Notes
- All modules are independently usable
- Each module accepts `std.mem.Allocator` parameter
- Output via user-provided `std.io.Writer`
- Comptime platform branching for cross-platform code
- Test coverage requirement: every public function has tests
