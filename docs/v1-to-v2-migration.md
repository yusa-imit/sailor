# sailor v1.x to v2.0.0 Migration Guide

This guide helps you migrate your code from sailor v1.x APIs to the new v2.0.0 APIs. All v2.0.0 changes are **opt-in** — v1.x APIs remain available with deprecation warnings to enable gradual migration.

## Table of Contents

- [Overview](#overview)
- [Breaking Changes](#breaking-changes)
- [API Deprecations](#api-deprecations)
  - [Buffer API](#buffer-api)
  - [Style API](#style-api)
  - [Widget Lifecycle](#widget-lifecycle)
- [Migration Strategies](#migration-strategies)
- [Example Migrations](#example-migrations)
- [Deprecation Timeline](#deprecation-timeline)

---

## Overview

**Philosophy**: v2.0.0 prioritizes:
1. **Clarity**: Shorter, clearer method names (`set()` vs `setChar()`)
2. **Consistency**: All widgets follow 3 lifecycle patterns (stateless, allocating, data-driven)
3. **Ergonomics**: Fluent style inference helpers reduce boilerplate
4. **Safety**: Compile-time deprecation warnings guide migration

**Migration approach**: Fix warnings one module at a time, run tests frequently.

---

## Breaking Changes

### None (Yet)

v2.0.0 is currently in **bridge phase** — all v1.x APIs work with deprecation warnings. Breaking removals will occur in a future version (v3.0.0+) with advance notice.

---

## API Deprecations

### Buffer API

#### `setChar()` → `set()`

**Deprecated**: `buffer.setChar(x, y, cell)`
**Replacement**: `buffer.set(x, y, cell)`

**Rationale**: The method accepts a `Cell` (not just a `char`), so the name was misleading. `set()` is clearer and shorter.

**Before (v1.x)**:
```zig
const cell = Cell{ .char = 'A', .style = .{} };
buffer.setChar(0, 0, cell);
```

**After (v2.0.0)**:
```zig
const cell = Cell{ .char = 'A', .style = .{} };
buffer.set(0, 0, cell); // Clearer: sets the entire cell
```

**Deprecation warning**:
```
warning: setChar() is deprecated, use set() instead
  → setChar() will be removed in v3.0.0
  → Replacement: buffer.set(x, y, cell)
```

**Migration script** (sed one-liner):
```bash
# macOS/BSD
sed -i '' 's/\.setChar(/\.set(/g' src/**/*.zig

# GNU/Linux
sed -i 's/\.setChar(/\.set(/g' src/**/*.zig
```

---

### Style API

#### Manual style construction → Fluent inference helpers

**Deprecated**: Manual `Style{}` construction with all fields
**Replacement**: Fluent builder methods (`.withForeground()`, `.makeBold()`, etc.)

**Rationale**: Reduces boilerplate, enables method chaining, clearer intent.

**Before (v1.x)**:
```zig
const style = Style{
    .fg = Color.rgb(255, 0, 0),
    .bg = Color.rgb(0, 0, 0),
    .bold = true,
    .italic = false,
    .underline = false,
    .dim = false,
};
```

**After (v2.0.0)**:
```zig
const style = Style{}
    .withForeground(.rgb(255, 0, 0))
    .withBackground(.rgb(0, 0, 0))
    .makeBold();
```

**Chaining examples**:
```zig
// Error style: red + bold
const err_style = Style{}.withForeground(.red).makeBold();

// Warning style: yellow + italic
const warn_style = Style{}.withForeground(.yellow).makeItalic();

// Success style: green
const ok_style = Style{}.withForeground(.green);

// Both fg+bg at once
const highlight = Style{}.withColors(.white, .blue);
```

**Available helpers** (v2.0.0):
- `.withForeground(color: Color) Style`
- `.withBackground(color: Color) Style`
- `.withColors(fg: Color, bg: Color) Style`
- `.makeBold() Style`
- `.makeItalic() Style`
- `.makeUnderline() Style`
- `.makeDim() Style`

**Deprecation warning**: None (additive change — old syntax still works)

---

### Widget Lifecycle

#### Unnecessary `init()` removed from stateless widgets

**Deprecated**: Calling `Widget.init()` for stateless widgets (Block, Paragraph, Gauge, etc.)
**Replacement**: Direct struct construction `Widget{}`

**Rationale**: Stateless widgets don't need initialization — `init()` created confusion about ownership.

**Three lifecycle patterns**:

| Pattern | Example Widgets | Construction | Cleanup |
|---------|-----------------|--------------|---------|
| **Stateless** | Block, Paragraph, Gauge, List, Table, Tabs | `Widget{}` | None (no `deinit()`) |
| **Allocating** | Tree, LogViewer, ConfigEditor, MetricsPanel | `Widget.init(allocator)` | `widget.deinit()` |
| **Data-driven** | Input, TextArea, Sparkline | `Widget.init(data)` | None (caller owns data) |

**Before (v1.x)**:
```zig
// Stateless widgets (Block, Paragraph, Gauge)
var block = Block.init(); // Unnecessary!
var para = Paragraph.init(); // Unnecessary!
```

**After (v2.0.0)**:
```zig
// Stateless widgets (Block, Paragraph, Gauge)
const block = Block{}; // Direct construction
const para = Paragraph{}; // Direct construction
```

**Allocating widgets (unchanged)**:
```zig
// Allocating widgets (Tree, LogViewer, etc.)
var tree = try Tree.init(allocator); // Still correct
defer tree.deinit();
```

**Method chaining syntax fix**:
```zig
// v1.x: Worked due to init() returning instance
block.withBorder(...).withTitle(...)

// v2.0.0: Wrap in parentheses for direct construction
(Block{}).withBorder(...).withTitle(...)

// Or assign first
const block = Block{};
block.withBorder(...).withTitle(...)
```

**Deprecation warning**: None (old `init()` methods were removed, not deprecated)

---

## Migration Strategies

### 1. Module-by-module migration

Migrate one source file at a time, run tests after each:

```bash
# Fix buffer.setChar() in one file
sed -i 's/\.setChar(/\.set(/g' src/ui/dashboard.zig
zig build test

# Fix style construction
# (manual edit — no regex for this)
zig build test
```

### 2. Deprecation warning triage

Compile with warnings enabled:
```bash
zig build 2>&1 | grep "deprecated"
```

Fix highest-impact warnings first (most frequent call sites).

### 3. Test-driven migration

1. Migrate tests first (smallest scope)
2. Run tests to verify behavior unchanged
3. Migrate application code using passing tests as reference

### 4. Gradual rollout (consumer projects)

For zr, zoltraak, silica:
1. Update `build.zig.zon` to sailor v2.0.0
2. Run `zig build` — collect all deprecation warnings
3. Fix warnings in one module (e.g., `src/ui/`)
4. Run tests: `zig build test`
5. Repeat for other modules

---

## Example Migrations

### Example 1: Buffer operations

**Before (v1.x)**:
```zig
const Buffer = @import("sailor").tui.Buffer;

pub fn drawGrid(buf: *Buffer) void {
    const cell = .{ .char = '+', .style = .{} };
    buf.setChar(0, 0, cell);
    buf.setChar(10, 0, cell);
    buf.setChar(0, 5, cell);
    buf.setChar(10, 5, cell);
}
```

**After (v2.0.0)**:
```zig
const Buffer = @import("sailor").tui.Buffer;

pub fn drawGrid(buf: *Buffer) void {
    const cell = .{ .char = '+', .style = .{} };
    buf.set(0, 0, cell); // Clearer: sets entire cell
    buf.set(10, 0, cell);
    buf.set(0, 5, cell);
    buf.set(10, 5, cell);
}
```

---

### Example 2: Styled text rendering

**Before (v1.x)**:
```zig
const Style = @import("sailor").tui.Style;
const Color = @import("sailor").tui.Color;

pub fn renderError(writer: anytype, msg: []const u8) !void {
    const err_style = Style{
        .fg = Color.rgb(255, 0, 0),
        .bg = null,
        .bold = true,
        .italic = false,
        .underline = false,
        .dim = false,
    };
    try writer.print("Error: {s}\n", .{msg});
}
```

**After (v2.0.0)**:
```zig
const Style = @import("sailor").tui.Style;

pub fn renderError(writer: anytype, msg: []const u8) !void {
    const err_style = Style{}
        .withForeground(.rgb(255, 0, 0))
        .makeBold();
    try writer.print("Error: {s}\n", .{msg});
}
```

---

### Example 3: Widget construction

**Before (v1.x)**:
```zig
const Block = @import("sailor").tui.widgets.Block;
const Paragraph = @import("sailor").tui.widgets.Paragraph;

pub fn buildUI(allocator: std.mem.Allocator) !void {
    var block = Block.init(); // Unnecessary init()
    var para = Paragraph.init(); // Unnecessary init()

    block = block.withTitle("Dashboard");
    para = para.withText("Hello, world!");
}
```

**After (v2.0.0)**:
```zig
const Block = @import("sailor").tui.widgets.Block;
const Paragraph = @import("sailor").tui.widgets.Paragraph;

pub fn buildUI(allocator: std.mem.Allocator) !void {
    // Direct construction for stateless widgets
    const block = (Block{}).withTitle("Dashboard");
    const para = (Paragraph{}).withText("Hello, world!");

    // Or assign first, then chain
    const block2 = Block{};
    const configured = block2.withTitle("Dashboard").withBorder(.single);
}
```

---

### Example 4: Full dashboard migration

**Before (v1.x)**:
```zig
const sailor = @import("sailor");
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Buffer = sailor.tui.Buffer;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

pub fn renderDashboard(buf: *Buffer, allocator: std.mem.Allocator) !void {
    // Title with manual style
    const title_style = Style{
        .fg = Color.rgb(100, 200, 255),
        .bg = null,
        .bold = true,
        .italic = false,
        .underline = true,
        .dim = false,
    };

    // Widgets with init()
    var block = Block.init();
    block = block.withTitle("Status").withBorder(.double);

    var para = Paragraph.init();
    para = para.withText("System: OK");

    // Render with setChar()
    const cell = .{ .char = '─', .style = title_style };
    buf.setChar(0, 0, cell);
}
```

**After (v2.0.0)**:
```zig
const sailor = @import("sailor");
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Buffer = sailor.tui.Buffer;
const Style = sailor.tui.Style;

pub fn renderDashboard(buf: *Buffer, allocator: std.mem.Allocator) !void {
    // Title with fluent style
    const title_style = Style{}
        .withForeground(.rgb(100, 200, 255))
        .makeBold()
        .makeUnderline();

    // Widgets with direct construction
    const block = (Block{})
        .withTitle("Status")
        .withBorder(.double);

    const para = (Paragraph{})
        .withText("System: OK");

    // Render with set()
    const cell = .{ .char = '─', .style = title_style };
    buf.set(0, 0, cell); // Clearer API
}
```

---

## Deprecation Timeline

### Current (v1.37.0 - Bridge Phase)

- ✅ v2.0.0 APIs available alongside v1.x APIs
- ✅ Compile-time deprecation warnings for old APIs
- ✅ All consumer projects (zr, zoltraak, silica) can migrate gradually

### v1.38.0 - v1.40.0 (Migration Window)

- All v1.x APIs remain functional with warnings
- Consumer projects encouraged to migrate
- New features use v2.0.0 APIs exclusively

### v2.0.0 (Target: 2026-05)

- **No breaking changes yet** — v1.x APIs still present
- Deprecation warnings become **errors** (opt-in via `-Werror`)
- Documentation updated to v2.0.0 examples

### v3.0.0 (Future)

- Deprecated v1.x APIs **removed**
- Only v2.0.0 APIs remain
- Minimum 6-month notice before v3.0.0 release

---

## Summary Checklist

Use this checklist to track your migration:

- [ ] Update `build.zig.zon` to sailor v1.37.0+
- [ ] Run `zig build` and collect deprecation warnings
- [ ] Replace `buffer.setChar()` → `buffer.set()` (sed script or manual)
- [ ] Replace manual `Style{}` construction with fluent helpers (`.withForeground()`, `.makeBold()`, etc.)
- [ ] Remove unnecessary `Widget.init()` calls for stateless widgets (Block, Paragraph, Gauge, etc.)
- [ ] Fix method chaining syntax: `Widget{}` → `(Widget{})` when chaining immediately
- [ ] Run `zig build test` to verify behavior unchanged
- [ ] Commit migration changes incrementally (one module at a time)

---

## Getting Help

- **Example code**: See `examples/migration_demo.zig` for side-by-side v1.x vs v2.0.0 comparisons
- **Issues**: Report migration problems at https://github.com/yusa-imit/sailor/issues
- **Questions**: Ask in consumer project discussions (zr, zoltraak, silica)

---

**Last updated**: 2026-04-06 (sailor v1.37.0)
