# Sailor Project Context

## Overview
- Zig TUI framework & CLI toolkit
- Library consumed via `build.zig.zon`
- Zero dependencies (Zig stdlib only)
- Cross-platform: Linux, macOS, Windows

## Current Phase
- **Phase 1 — Terminal + CLI Foundation (v0.1.0)**: IN PROGRESS
- Modules: term.zig, color.zig, arg.zig
- Next: Implement term.zig (no dependencies)

## Consumer Projects
| Project | Path | Status |
|---------|------|--------|
| zr | ../zr | 43K LOC, will migrate arg/color/progress |
| zoltraak | ../zoltraak | 39K LOC, will replace parseArgs(), build redis-cli |
| silica | ../silica | 5K LOC, will build SQL shell |

## Checklist — Phase 1
- [x] build.zig + build.zig.zon bootstrap
- [x] src/sailor.zig root module
- [x] Test infrastructure (tests/smoke_test.zig, 12 tests passing)
- [x] Cross-platform build verification (Linux, Windows, macOS ARM)
- [x] Comprehensive test suites (73 tests passing: smoke, cross-platform, memory safety, build verification)
- [x] Zig 0.15.x API compatibility (ArrayList, builtin fields, alignedAlloc)
- [x] All test files integrated into build.zig
- [ ] src/term.zig — raw mode, key reading, TTY detection, terminal size
- [ ] src/color.zig — ANSI codes, styles, 256/truecolor, NO_COLOR
- [ ] src/arg.zig — flag parsing, subcommands, help generation
- [ ] Tests for all Phase 1 modules
- [ ] CI pipeline green
- [ ] First consumer integration test (zoltraak parseArgs replacement)
