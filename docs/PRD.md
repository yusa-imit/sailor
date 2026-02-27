# Sailor — Product Requirements Document

> **sailor**: Zig TUI framework & CLI toolkit
> Version: 0.1.0 | Language: Zig 0.15.x | License: MIT

---

## 1. Overview

Sailor is a full-featured TUI framework and CLI toolkit for Zig. It provides everything needed to build interactive terminal applications — from argument parsing and colored output to full-screen layouts with composable widgets.

Inspired by Rust's [ratatui](https://github.com/ratatui/ratatui) architecture, adapted for Zig's comptime capabilities and zero-cost abstractions.

### 1.1 Motivation

Three Zig projects share overlapping CLI and TUI needs but each implements them from scratch:

| Project | Type | CLI/TUI Status |
|---------|------|---------------|
| **zr** | Task runner (43K LOC) | Hand-rolled arg parsing, basic color/progress, custom TUI (900 LOC) |
| **zoltraak** | Redis server (39K LOC) | Minimal flags, needs redis-cli REPL + monitoring TUI |
| **silica** | Embedded DB (5K LOC) | No CLI yet, needs sqlite3-style shell + schema browser |

Beyond these three projects, Zig lacks a mature TUI framework comparable to ratatui (Rust), bubbletea (Go), or blessed (Node).

### 1.2 Design Principles

1. **Immediate mode rendering** — No persistent widget tree. Every frame: build layout, render widgets, diff output. Simple, predictable, no hidden state.
2. **Composable** — Each layer is independent. Use `sailor.arg` without importing `sailor.tui`. Use `sailor.tui` without `sailor.repl`.
3. **Comptime-first** — Flag definitions, layout constraints, and widget types resolved at compile time where possible.
4. **Cross-platform** — Linux, macOS, Windows. POSIX termios / Windows Console API. Graceful degradation.
5. **Zero dependencies** — Zig stdlib only.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Application Layer                    │
│         (zr, zoltraak-cli, silica shell)             │
├──────────┬──────────┬───────────┬───────────────────┤
│ sailor   │ sailor   │ sailor    │ sailor            │
│ .arg     │ .repl    │ .fmt      │ .tui              │
│          │          │           │ ┌───────────────┐ │
│ ArgParser│ REPL     │ Table     │ │   Widgets     │ │
│ Help gen │ History  │ JSON      │ │ List, Table,  │ │
│ Subcmds  │ Complete │ CSV       │ │ Input, Tabs,  │ │
│          │ Highlight│ Plain     │ │ Chart, Dialog │ │
│          │          │           │ ├───────────────┤ │
│          │          │           │ │   Layout      │ │
│          │          │           │ │ Flex, Grid,   │ │
│          │          │           │ │ Constraint    │ │
│          │          │           │ ├───────────────┤ │
│          │          │           │ │   Rendering   │ │
│          │          │           │ │ Buffer, Diff, │ │
│          │          │           │ │ Cell, Style   │ │
├──────────┴──────────┴───────────┼───────────────────┤
│         sailor.color            │  sailor.term      │
│  ANSI, Styles, Semantic output  │  Raw mode, Keys,  │
│  NO_COLOR, 256/Truecolor        │  Size, TTY detect │
├─────────────────────────────────┼───────────────────┤
│         sailor.progress         │                   │
│  Bar, Spinner, Multi-bar        │                   │
└─────────────────────────────────┴───────────────────┘
```

---

## 3. Module Specification

### 3.1 `sailor.term` — Terminal Backend

Cross-platform terminal primitives. Foundation for all other modules.

```zig
// Terminal size
const size = try sailor.term.getSize(); // .{ .cols = 120, .rows = 40 }

// Raw mode (RAII)
var raw = try sailor.term.enableRawMode();
defer raw.restore();

// Key events
const key = try sailor.term.readKey();
switch (key) {
    .char => |c| { ... },
    .enter, .tab, .backspace => { ... },
    .up, .down, .left, .right => { ... },
    .ctrl => |c| { ... },     // Ctrl+C, Ctrl+D, etc.
    .alt => |c| { ... },
    .f => |n| { ... },        // F1-F12
    .mouse => |m| { ... },    // mouse events
    .resize => |s| { ... },   // SIGWINCH
    .escape => { ... },
}

// TTY check
const is_tty = sailor.term.isTty(std.io.getStdOut());
```

**Features**:
- Raw mode: POSIX `termios` / Windows `SetConsoleMode`
- Key reading: printable chars, arrows, Ctrl/Alt modifiers, function keys
- Mouse input: click, scroll, drag (xterm mouse protocol)
- Terminal size: `ioctl TIOCGWINSZ` / `GetConsoleScreenBufferInfo`
- Resize events: `SIGWINCH` handler / Windows console events
- TTY detection for stdout/stderr
- Windows ANSI: enable Virtual Terminal Processing
- Alternate screen buffer: enter/leave (`\x1b[?1049h/l`)
- Cursor: show/hide, position get/set

---

### 3.2 `sailor.color` — Styled Output

ANSI escape codes with full color depth support.

```zig
const c = sailor.color.init(.{
    .mode = .auto, // .auto | .always | .never
    .writer = stderr,
});

// Semantic helpers
c.err("connection refused: {s}\n", .{addr});       // red "✗ ..."
c.ok("connected to {s}\n", .{addr});                // green "✓ ..."
c.warn("deprecation: {s}\n", .{msg});               // yellow "⚠ ..."
c.info("listening on :{d}\n", .{port});              // cyan "→ ..."

// Style builder
const style = sailor.color.Style{
    .fg = .{ .rgb = .{ 0xFF, 0xA5, 0x00 } },  // orange
    .bg = .blue,
    .bold = true,
    .italic = true,
};
c.styled(style, "highlighted text\n", .{});
```

**Color Depth**:
- Basic 16 colors (always)
- 256-color palette (`\x1b[38;5;Nm`)
- Truecolor RGB (`\x1b[38;2;R;G;Bm`)
- Auto-detection: `COLORTERM=truecolor`, `TERM=*-256color`, fallback to 16

**Features**:
- `NO_COLOR` environment variable support (https://no-color.org/)
- Force mode: auto/always/never (for `--color` / `--no-color` flags)
- Semantic helpers: `err`, `ok`, `warn`, `info`, `dim`, `bold`
- Style struct: fg, bg, bold, dim, italic, underline, strikethrough, reverse
- Writer-based API (works with any `std.io.Writer`)

---

### 3.3 `sailor.arg` — Argument Parser

Comptime-declarative flag and command definitions.

```zig
const cli = sailor.arg.parse(&.{
    .name = "zoltraak",
    .version = "0.5.0",
    .description = "Redis-compatible in-memory data store",
    .flags = &.{
        .{ .long = "host", .short = 'h', .type = []const u8, .default = "127.0.0.1",
           .desc = "Bind address" },
        .{ .long = "port", .short = 'p', .type = u16, .default = 6379,
           .desc = "Listen port" },
        .{ .long = "verbose", .short = 'v', .type = bool,
           .desc = "Enable verbose logging" },
    },
    .commands = &.{
        .{ .name = "cli", .desc = "Start interactive client",
           .flags = &.{
               .{ .long = "raw", .type = bool, .desc = "Raw output mode" },
           },
        },
        .{ .name = "benchmark", .desc = "Run performance benchmark",
           .flags = &.{
               .{ .long = "clients", .short = 'c', .type = u32, .default = 50 },
               .{ .long = "requests", .short = 'n', .type = u32, .default = 100000 },
           },
        },
    },
}, args) catch |err| {
    // Auto-prints error + usage on failure
};

const host = cli.flag("host");       // []const u8
const port = cli.flag("port");       // u16
if (cli.command()) |cmd| {
    switch (cmd) {
        .cli => |sub| { const raw = sub.flag("raw"); },
        .benchmark => |sub| { ... },
    }
}
```

**Features**:
- Comptime flag definition — type-safe access
- Auto-generated `--help` and `--version`
- Short (`-p`) and long (`--port`) flag forms
- Grouped short flags (`-vvv` for verbosity count)
- Value types: `bool`, integers, `[]const u8`, enums
- Subcommand support (nested definitions, each with own flags)
- Positional arguments with optional/required/variadic
- `--` separator for passthrough arguments
- Unknown flag detection with Levenshtein "Did you mean?" suggestions
- Bash/Zsh/Fish completion script generation from definitions

---

### 3.4 `sailor.repl` — Interactive REPL

Read-eval-print loop with line editing, history, and completion.

```zig
var repl = try sailor.repl.init(allocator, .{
    .prompt = "127.0.0.1:6379> ",
    .history_file = "~/.zoltraak_history",
    .history_size = 10000,
    .completer = struct {
        fn complete(buf: []const u8, allocator: Allocator) ![]const []const u8 {
            // return matching Redis commands
        }
    }.complete,
    .highlighter = struct {
        fn highlight(buf: []const u8, out: *Style.Buffer) void {
            // colorize keywords, strings, numbers
        }
    }.highlight,
    .validator = struct {
        fn validate(buf: []const u8) Validation {
            // .complete, .incomplete (multi-line), .invalid
        }
    }.validate,
});
defer repl.deinit();

while (try repl.readLine()) |line| {
    const result = processCommand(line);
    repl.print("{s}\n", .{result});
}
```

**Features**:
- Line editing: cursor movement, word jump (Ctrl+Left/Right), home/end, kill line
- History: up/down navigation, reverse search (Ctrl+R), persistent file
- Tab completion: user callback, popup menu for multiple matches
- Syntax highlighting: real-time as-you-type via user callback
- Multi-line input: validator callback returns `.incomplete` → continuation prompt
- Hints: inline suggestion text (dimmed, right of cursor)
- Signal handling: Ctrl+C clears line, Ctrl+D exits on empty line
- Pipe mode: graceful degradation (no raw mode, no completion, no color)

---

### 3.5 `sailor.tui` — Full-Screen TUI Framework

Immediate-mode TUI with layout system and composable widgets. Inspired by ratatui.

#### 3.5.1 Core Loop

```zig
var term = try sailor.tui.Terminal.init(allocator, .{});
defer term.deinit();

var state = AppState{};

while (state.running) {
    // 1. Render
    try term.draw(struct {
        fn render(frame: *Frame) !void {
            const chunks = frame.layout(.{
                .direction = .vertical,
                .constraints = &.{
                    .{ .length = 3 },     // header: fixed 3 rows
                    .{ .min = 1 },        // body: fill remaining
                    .{ .length = 1 },     // footer: fixed 1 row
                },
            }, frame.area());

            frame.render(Header{}, chunks[0]);
            frame.render(MainContent{ .state = &state }, chunks[1]);
            frame.render(StatusBar{ .state = &state }, chunks[2]);
        }
    }.render);

    // 2. Handle events
    if (try term.pollEvent(100)) |event| {
        switch (event) {
            .key => |k| state.handleKey(k),
            .mouse => |m| state.handleMouse(m),
            .resize => |s| {},  // auto-handled by terminal
        }
    }
}
```

#### 3.5.2 Layout System

Constraint-based layout inspired by CSS Flexbox.

```zig
// Vertical split
const chunks = frame.layout(.{
    .direction = .vertical,
    .constraints = &.{
        .{ .length = 3 },          // exact 3 rows
        .{ .percentage = 60 },     // 60% of remaining
        .{ .min = 5 },             // at least 5, fill rest
        .{ .max = 10 },            // at most 10
        .{ .ratio = .{ 1, 3 } },  // 1/3 of space
    },
    .margin = 1,
    .spacing = 0,
}, area);

// Nested horizontal split within a chunk
const cols = frame.layout(.{
    .direction = .horizontal,
    .constraints = &.{
        .{ .percentage = 30 },
        .{ .min = 1 },
    },
}, chunks[1]);
```

**Constraint Types**:
- `length(n)` — exact n cells
- `percentage(p)` — p% of available space
- `min(n)` — at least n, expands to fill
- `max(n)` — at most n
- `ratio(num, den)` — fraction of available space

#### 3.5.3 Rendering Backend

Double-buffered cell grid with diff-based output.

```zig
// Cell: single terminal character
const Cell = struct {
    char: u21,           // Unicode codepoint
    style: Style,        // fg, bg, modifiers
};

// Buffer: 2D grid of cells
const Buffer = struct {
    area: Rect,
    cells: []Cell,

    fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void;
    fn setString(self: *Buffer, x: u16, y: u16, str: []const u8, style: Style) void;
    fn setLine(self: *Buffer, x: u16, y: u16, line: Line) void;
    fn diff(self: Buffer, other: Buffer) []Update;  // minimal diff for output
};
```

**Features**:
- Double buffering: only emit changed cells each frame
- Unicode-aware: wide characters, combining marks
- Alternate screen: auto enter/leave on init/deinit
- Cursor management: hide during render, restore on exit

#### 3.5.4 Built-in Widgets

All widgets implement a common pattern:

```zig
fn render(self: MyWidget, buf: *Buffer, area: Rect) void;
```

**Layout Widgets**:

| Widget | Description |
|--------|------------|
| `Block` | Borders, title, padding. Wraps any other widget. |
| `Tabs` | Tab bar with selectable items. |
| `Popup` | Centered overlay with configurable size. |

**Display Widgets**:

| Widget | Description |
|--------|------------|
| `Paragraph` | Text display with wrapping. Supports styled spans. |
| `List` | Scrollable item list with selection highlight. |
| `Table` | Column-aligned data table with header, row selection, column resize. |
| `Tree` | Hierarchical tree view with expand/collapse. |
| `Canvas` | Freeform drawing with Braille/block/half-block characters. |

**Input Widgets**:

| Widget | Description |
|--------|------------|
| `Input` | Single-line text input with cursor. |
| `TextArea` | Multi-line text editor with scroll. |

**Data Visualization**:

| Widget | Description |
|--------|------------|
| `Gauge` | Progress bar (horizontal). |
| `Sparkline` | Inline mini-chart from data series. |
| `BarChart` | Vertical bar chart with labels. |
| `LineChart` | Line chart with axis labels and multiple series. |

**Feedback Widgets**:

| Widget | Description |
|--------|------------|
| `Dialog` | Modal dialog with message and button choices. |
| `Notification` | Toast-style temporary message. |
| `StatusBar` | Bottom bar with key hints and status info. |

#### 3.5.5 Styling

```zig
const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,
};

const Color = union(enum) {
    reset,
    black, red, green, yellow, blue, magenta, cyan, white,
    bright_black, bright_red, // ... bright variants
    indexed: u8,              // 256-color
    rgb: struct { r: u8, g: u8, b: u8 },  // truecolor
};

// Styled text span
const Span = struct {
    content: []const u8,
    style: Style,
};

// Line of styled spans
const Line = struct {
    spans: []const Span,
};
```

#### 3.5.6 Concrete Use Cases

**zr — Task Runner TUI**:
```
┌─ Tasks ──────────────────┬─ Output ─────────────────┐
│ > build                  │ $ echo "building..."     │
│   test                   │ building...              │
│   lint                   │ ✓ build completed (1.2s) │
│   deploy                 │                          │
├──────────────────────────┴──────────────────────────┤
│ [Enter] Run  [/] Filter  [q] Quit    CPU: 23% 1.2MB│
└─────────────────────────────────────────────────────┘
```
Widgets: `Block`, `List`, `Paragraph`, `StatusBar`

**zoltraak-cli — Redis Monitor**:
```
┌─ Keys ──────────────────┬─ Value ──────────────────┐
│ user:1001        string │ {"name":"Kim","age":28}  │
│ user:1002        string │                          │
│ > session:abc    hash   │ ┌─ Fields ─────────────┐ │
│ scores           zset   │ │ token   eyJhbGci...  │ │
│ queue:emails     list   │ │ expiry  1709312400   │ │
│                         │ │ ip      10.0.0.1     │ │
├─────────────────────────┴─┴───────────────────────┤
│ 4 keys | 1.2 MB | connected 127.0.0.1:6379       │
└───────────────────────────────────────────────────┘
```
Widgets: `Block`, `List`, `Table`, `Paragraph`, `StatusBar`

**silica — SQL Shell**:
```
┌─ Schema ────────────────┬─ Results ────────────────┐
│ ▼ users                 │ id │ name    │ email     │
│   id (INTEGER PK)       │  1 │ Kim     │ k@ex.com  │
│   name (TEXT)            │  2 │ Lee     │ l@ex.com  │
│   email (TEXT)           │  3 │ Park    │ p@ex.com  │
│ ▶ orders                │────┼─────────┼───────────│
│ ▶ products              │ 3 rows (0.2ms)           │
├─────────────────────────┴──────────────────────────┤
│ silica> SELECT * FROM users;                       │
└────────────────────────────────────────────────────┘
```
Widgets: `Block`, `Tree`, `Table`, `Input`, `StatusBar`

---

### 3.6 `sailor.progress` — Progress Indicators

Progress bar, spinner, and multi-progress for non-TUI contexts.

```zig
// Simple progress bar
var bar = sailor.progress.bar(writer, .{
    .total = file_size,
    .width = 40,
    .label = "Loading RDB",
    .style = .{ .fill = '█', .empty = '░' },
});
while (readChunk()) |chunk| {
    process(chunk);
    bar.update(bytes_read);
}
bar.finish();

// Multi-progress (concurrent downloads, etc.)
var multi = sailor.progress.multi(writer, allocator);
var bar1 = try multi.add(.{ .label = "dump.rdb", .total = rdb_size });
var bar2 = try multi.add(.{ .label = "appendonly.aof", .total = aof_size });
// update bar1, bar2 from separate threads
multi.finish();

// Spinner
var spin = sailor.progress.spinner(writer, .{ .label = "Connecting..." });
defer spin.finish("Connected!");
```

**Features**:
- Progress bar: percentage, count (N/M), throughput (MB/s), ETA
- Spinner: Braille animation or ASCII fallback
- Multi-progress: multiple concurrent bars, thread-safe updates
- Color-aware
- Pipe/redirect: degrades to periodic line output

---

### 3.7 `sailor.fmt` — Result Formatting

Structured data output for CLI applications.

```zig
// Table
var table = sailor.fmt.table(writer, &.{
    .{ .header = "KEY", .width = .auto },
    .{ .header = "TYPE", .width = .fixed(10) },
    .{ .header = "SIZE", .width = .fixed(8), .align = .right },
});
try table.row(.{ "user:1", "string", "128" });
try table.row(.{ "scores", "zset", "1,024" });
try table.separator();
try table.row(.{ "", "Total", "1,152" });
table.finish();

// JSON (streaming, no allocation)
var json = sailor.fmt.json(writer);
try json.beginArray();
try json.object(.{ .key = "user:1", .type = "string", .size = 128 });
try json.endArray();

// CSV
var csv = sailor.fmt.csv(writer, .{ .delimiter = ',', .header = true });
try csv.row(.{ "user:1", "string", "128" });
```

**Output Modes** (inspired by sqlite3):
- `table` — Unicode box-drawing borders, aligned columns
- `plain` — Tab-separated, no decoration
- `csv` — RFC 4180 compliant
- `json` — Streaming JSON array of objects
- `jsonl` — One JSON object per line

---

## 4. Package Structure

```
sailor/
├── build.zig
├── build.zig.zon
├── docs/
│   └── PRD.md
├── src/
│   ├── sailor.zig           # Root — pub exports all modules
│   ├── term.zig             # Terminal backend
│   ├── color.zig            # Styled output
│   ├── arg.zig              # Argument parser
│   ├── repl.zig             # Interactive REPL
│   ├── progress.zig         # Progress indicators
│   ├── fmt.zig              # Result formatting
│   └── tui/
│       ├── tui.zig          # TUI root — Terminal, Frame
│       ├── buffer.zig       # Cell buffer, diff engine
│       ├── layout.zig       # Constraint solver, Rect
│       ├── style.zig        # Style, Color, Span, Line
│       ├── symbols.zig      # Box-drawing character sets
│       └── widgets/
│           ├── block.zig    # Block (borders, title, padding)
│           ├── paragraph.zig
│           ├── list.zig
│           ├── table.zig
│           ├── tree.zig
│           ├── input.zig
│           ├── textarea.zig
│           ├── tabs.zig
│           ├── gauge.zig
│           ├── sparkline.zig
│           ├── barchart.zig
│           ├── linechart.zig
│           ├── canvas.zig
│           ├── dialog.zig
│           ├── notification.zig
│           ├── popup.zig
│           └── statusbar.zig
└── tests/
    ├── term_test.zig
    ├── color_test.zig
    ├── arg_test.zig
    ├── repl_test.zig
    ├── progress_test.zig
    ├── fmt_test.zig
    ├── buffer_test.zig
    ├── layout_test.zig
    └── widget_test.zig
```

---

## 5. Integration Plan

### Phase 1 — Terminal + CLI Foundation (v0.1.0)

Bootstrap the package with terminal primitives, colored output, and argument parsing.

| Module | Migrates from |
|--------|---------------|
| `term` | zr `util/platform.zig` + `output/color.zig` (TTY/raw mode) |
| `color` | zr `output/color.zig` (extended to 256/truecolor) |
| `arg` | New (zr/zoltraak hand-rolled parsers as reference) |

**Deliverable**: Installable via `zig fetch`. zoltraak replaces `parseArgs()`, zr starts migration.

### Phase 2 — Interactive (v0.2.0)

REPL and progress for interactive CLI applications.

| Module | Migrates from |
|--------|---------------|
| `repl` | zr `cli/tui.zig` (raw mode, key reading) + new features |
| `progress` | zr `output/progress.zig` (extended to multi-bar) |
| `fmt` | New (inspired by zr JSON output, sqlite3 output modes) |

**Deliverable**: zoltraak-cli prototype with REPL, silica shell skeleton.

### Phase 3 — TUI Core (v0.3.0)

Full-screen rendering with layout system.

| Module | Description |
|--------|-------------|
| `tui.Terminal` | Alternate screen, event loop, frame rendering |
| `tui.Buffer` | Cell grid, double buffering, diff |
| `tui.Layout` | Constraint solver (length, percentage, min, max, ratio) |
| `tui.Style` | Style, Color, Span, Line |

**Deliverable**: Minimal TUI apps possible (manual cell rendering).

### Phase 4 — Core Widgets (v0.4.0)

Essential widgets for all three projects.

| Widget | Primary consumer |
|--------|-----------------|
| `Block` | All (borders, titles) |
| `List` | zr (task picker), zoltraak (key browser) |
| `Table` | silica (query results), zoltraak (data view) |
| `Input` | silica (SQL input), zoltraak (command input) |
| `Paragraph` | zr (log viewer), all (text display) |
| `StatusBar` | All (key hints, status info) |
| `Tabs` | All (view switching) |

**Deliverable**: All three project TUIs buildable.

### Phase 5 — Advanced Widgets (v0.5.0)

Data visualization and advanced interaction.

| Widget | Use case |
|--------|----------|
| `Tree` | silica (schema browser), zr (dependency tree) |
| `TextArea` | silica (multi-line SQL), zoltraak (Lua script editor) |
| `Gauge` | zr (task progress), silica (import progress) |
| `Sparkline` | zoltraak (ops/sec), zr (build time trends) |
| `BarChart` | zoltraak (memory by type), zr (task duration) |
| `LineChart` | zoltraak (connections over time), silica (query latency) |
| `Canvas` | Custom visualizations (Braille dots, block chars) |
| `Dialog` | All (confirmation prompts) |
| `Popup` | All (detail views, help overlay) |
| `Notification` | All (toast messages) |

### Phase 6 — Polish (v1.0.0)

- Theming system (named themes, runtime switching)
- Animation support (transitions, smooth scrolling)
- Accessibility (screen reader hints)
- Comprehensive documentation and examples
- Performance benchmarks

### Migration Schedule

| Project | Phase 1 | Phase 2 | Phase 3-4 | Phase 5 |
|---------|---------|---------|-----------|---------|
| **zr** | Arg + color migration | Progress migration | Task picker TUI, live runner | Dependency tree, charts |
| **zoltraak** | Replace `parseArgs()` | Build REPL `zoltraak-cli` | Key browser, data viewer | Monitoring dashboard |
| **silica** | Add CLI flags | SQL shell with REPL | Schema browser, results table | Query plan visualizer |

---

## 6. Consumer Usage

### 6.1 `build.zig.zon`

```zig
.dependencies = .{
    .sailor = .{
        .url = "https://github.com/<org>/sailor/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

### 6.2 `build.zig`

```zig
const sailor_dep = b.dependency("sailor", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sailor", sailor_dep.module("sailor"));
```

### 6.3 Application Code

```zig
const sailor = @import("sailor");

pub fn main() !void {
    // Parse args
    const cli = sailor.arg.parse(&.{ ... }, args);

    // Full-screen TUI
    var term = try sailor.tui.Terminal.init(allocator, .{});
    defer term.deinit();

    while (running) {
        try term.draw(struct {
            fn render(f: *sailor.tui.Frame) !void {
                const areas = f.layout(.vertical, &.{
                    .{ .min = 1 },
                    .{ .length = 1 },
                }, f.area());

                f.render(sailor.tui.widgets.List{ ... }, areas[0]);
                f.render(sailor.tui.widgets.StatusBar{ ... }, areas[1]);
            }
        }.render);

        if (try term.pollEvent(16)) |ev| handleEvent(ev);
    }
}
```

---

## 7. Compatibility

| Target | Support |
|--------|---------|
| Zig 0.15.x | Required |
| x86_64-linux-gnu | Full |
| aarch64-linux-gnu | Full |
| x86_64-macos | Full |
| aarch64-macos | Full |
| x86_64-windows-msvc | Full (Windows Console API + VT Processing) |
| aarch64-windows-msvc | Full |

**Dependencies**: None. Zig stdlib only.

---

## 8. Prior Art

| Library | Language | Relevance |
|---------|----------|-----------|
| [ratatui](https://github.com/ratatui/ratatui) | Rust | Primary inspiration for TUI architecture (immediate mode, layout, widgets) |
| [bubbletea](https://github.com/charmbracelet/bubbletea) | Go | Elm-architecture TUI. Reference for event model. |
| [blessed](https://github.com/chjj/blessed) | Node | Widget-rich TUI. Reference for widget catalog. |
| [crossterm](https://github.com/crossterm-rs/crossterm) | Rust | Terminal backend. Reference for cross-platform handling. |
| [clap](https://github.com/Hejsil/zig-clap) | Zig | Zig arg parser. Reference for comptime patterns. |
| [readline](https://tiswww.case.edu/php/chet/readline/rltop.html) | C | Line editing standard. Reference for REPL features. |

---

## 9. Non-Goals

- **Not a window manager** — No floating windows, z-ordering, or window decorators.
- **Not a shell** — No command execution, piping, or job control.
- **Not a logging library** — Color module formats output, doesn't manage log levels or rotation.
- **Not async** — Synchronous API. Caller manages concurrency.
- **Not a terminal emulator** — Writes to existing terminal, doesn't emulate one.

---

## 10. Success Criteria

| Metric | Target |
|--------|--------|
| Dependencies | 0 (stdlib only) |
| Test coverage | Every public function tested |
| Cross-compile | All 6 targets build cleanly |
| Render performance | 60 fps on 200x50 terminal |
| Input latency | < 1ms key-to-screen |
| Migration | zoltraak-cli using sailor.repl + sailor.tui by v0.4.0 |
| Migration | silica SQL shell using sailor by v0.4.0 |
| Migration | zr TUI migrated to sailor by v0.4.0 |
