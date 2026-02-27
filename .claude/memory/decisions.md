# Sailor Decision Log

## Decision: Project Name
- **Date**: 2026-02-27
- **Context**: Need a name for the Zig CLI/TUI library shared by zr, zoltraak, silica
- **Decision**: "sailor" (만년필 브랜드)
- **Rationale**: Short, memorable, no namespace conflicts in Zig ecosystem

## Decision: Library Architecture (ratatui-inspired)
- **Date**: 2026-02-27
- **Context**: Need to choose between retained mode (bubbletea/Elm style) vs immediate mode (ratatui style) for TUI
- **Decision**: Immediate mode rendering with double-buffered diff
- **Rationale**: Simpler mental model, no hidden state management, better fit for Zig's explicit style. Widget = plain struct with render method, no vtable overhead.

## Decision: Module Independence
- **Date**: 2026-02-27
- **Context**: Should all modules be tightly integrated or independently usable?
- **Decision**: Each module is independently importable. `sailor.arg` works without `sailor.tui`.
- **Rationale**: Consumer projects have different needs. zoltraak server only needs arg+color. silica shell needs arg+repl+fmt+tui.
