# Sailor Architecture

## Module Dependency Graph

```
sailor.tui ─────┬──→ sailor.color ──→ sailor.term
                │
sailor.repl ────┤
                │
sailor.progress ┘

sailor.arg  (standalone)
sailor.fmt  (standalone)
```

Lower layers must never import higher layers.

## Key Decisions

### Immediate Mode Rendering (TUI)
- No persistent widget tree
- Every frame: caller builds layout → renders widgets → framework diffs output
- Inspired by ratatui (Rust)
- Rationale: simpler mental model, no hidden state, easier testing

### Widget = Plain Struct
- No vtable, no interface trait
- Widget struct has `render(self, buf: *Buffer, area: Rect)` method
- Caller passes widget to `Frame.render()`
- Rationale: zero-cost, no runtime dispatch, comptime type checking

### Writer-Based Output
- All output goes through user-provided `std.io.Writer`
- Library never touches stdout/stderr directly
- Rationale: testability (fixedBufferStream), composability, no global state
