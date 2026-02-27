# Sailor Project Context

## Overview
- Zig TUI framework & CLI toolkit library
- Library consumed via `build.zig.zon`
- Zero dependencies (Zig stdlib only)
- Cross-platform: Linux, macOS, Windows
- Current version: v0.2.0

## Current Phase
- **Phase 2 — Interactive (v0.2.0)**: ✅ COMPLETE & RELEASED
- **Phase 3 — TUI Core (v0.3.0)**: 🚀 NEXT TARGET

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

## Phase 3 Implementation Plan

**Dependency Graph** (must implement in this order):
```
tui/style.zig   → standalone (Color, Style, Span, Line types)
tui/symbols.zig → standalone (box-drawing character sets)
tui/buffer.zig  → depends on style.zig (Cell grid, diff)
tui/layout.zig  → standalone (Rect, constraint solver)
tui/tui.zig     → depends on all above (Terminal, Frame, event loop)
```

**Next Implementation Steps**:
1. Create `src/tui/` directory
2. Implement `tui/style.zig` first (no dependencies)
3. Implement `tui/symbols.zig` (no dependencies)
4. Implement `tui/layout.zig` (standalone)
5. Implement `tui/buffer.zig` (depends on style.zig)
6. Implement `tui/tui.zig` (depends on all above)
7. Uncomment `pub const tui = @import("tui/tui.zig");` in `src/sailor.zig`
8. Write comprehensive tests for each module
9. Release v0.3.0

## Consumer Projects
| Project | Path | Current sailor Usage | Next Migration |
|---------|------|---------------------|----------------|
| zr | ../zr | v0.2.0 arg, color, progress | v0.4.0 TUI widgets |
| zoltraak | ../zoltraak | v0.2.0 arg, color, repl | v0.4.0 TUI (redis-cli) |
| silica | ../silica | v0.2.0 arg, color, repl, fmt | v0.4.0 TUI (SQL shell) |

## Test Status
- **Total Tests**: 121 passing
  - Module tests: 53 (term: 5, color: 16, arg: 13, repl: 5, progress: 7, fmt: 7)
  - Infrastructure tests: 68 (smoke, cross-platform, memory safety, build verification)
- **Cross-platform**: All 5 targets build successfully
  - x86_64-linux-gnu ✓
  - aarch64-linux-gnu ✓
  - x86_64-windows-msvc ✓
  - x86_64-macos ✓
  - aarch64-macos ✓
- **CI Status**: GREEN ✓
- **Compiler Warnings**: 0
- **Known Issues**: 0 open bugs

## Recent Stabilization Work (Current Session)
- Verified all 121 tests passing
- Confirmed zero compiler warnings
- Validated all 5 cross-platform targets
- CI pipeline green with no issues
- Library standards enforced:
  - No `@panic` in library code ✓
  - No stdout/stderr direct usage ✓
  - Writer-based APIs only ✓
  - No global state ✓
  - Memory safety verified ✓

## Architecture Notes
- All modules are independently usable
- Each module accepts `std.mem.Allocator` parameter
- Output via user-provided `std.io.Writer`
- Comptime platform branching for cross-platform code
- Test coverage requirement: every public function has tests
