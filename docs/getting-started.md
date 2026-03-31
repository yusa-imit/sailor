# Getting Started with sailor

sailor is a Zig TUI framework and CLI toolkit designed for building terminal user interfaces and command-line applications. This guide will help you get started with each major module.

## Installation

Add sailor to your `build.zig.zon`:

```zig
.dependencies = .{
    .sailor = .{
        .url = "https://github.com/yusa-imit/sailor/archive/refs/tags/v1.26.0.tar.gz",
        .hash = "<hash>",
    },
},
```

Then in your `build.zig`:

```zig
const sailor = b.dependency("sailor", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sailor", sailor.module("sailor"));
```

## Quick Start: Terminal & CLI

### term.zig — Terminal Control

The `term` module provides low-level terminal control: TTY detection, raw mode, terminal size, and advanced protocols.

```zig
const sailor = @import("sailor");
const std = @import("std");

pub fn main() !void {
    // Detect if stdout is a terminal
    const is_tty = try sailor.term.isatty(std.io.getStdOut().handle);
    std.debug.print("Running in a TTY: {}\n", .{is_tty});

    // Get terminal size
    const size = try sailor.term.getSize(std.io.getStdOut().handle);
    std.debug.print("Terminal: {}x{} characters\n", .{ size.cols, size.rows });

    // Enter raw mode for key-by-key input
    var raw = try sailor.term.RawMode.init(std.io.getStdIn().handle);
    defer raw.deinit();

    // Read single key press
    const key = try sailor.term.readKey(std.io.getStdIn().reader());
    std.debug.print("You pressed: {}\n", .{key});
}
```

**Key features**:
- TTY detection (`isatty`)
- Terminal size (`getSize`)
- Raw mode for character-by-character input (`RawMode`)
- Key reading with escape sequence parsing (`readKey`)
- Advanced protocols: bracketed paste, synchronized output, hyperlinks

### color.zig — ANSI Color Output

The `color` module provides ANSI color codes with automatic color depth detection.

```zig
const sailor = @import("sailor");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    // Auto-detect color support
    const depth = try sailor.color.detectColorSupport(allocator);
    std.debug.print("Color depth: {}\n", .{depth});

    // Basic colors
    try sailor.color.fg(.red, stdout);
    try stdout.writeAll("Red text\n");
    try sailor.color.reset(stdout);

    // RGB colors (if terminal supports it)
    const style = sailor.color.Style{
        .fg = .{ .rgb = .{ .r = 100, .g = 200, .b = 255 } },
        .bg = .{ .basic = .black },
        .bold = true,
    };
    try style.apply(stdout);
    try stdout.writeAll("Styled text\n");
    try sailor.color.reset(stdout);

    // Semantic helpers
    try sailor.color.err("Error message", stdout);
    try sailor.color.ok("Success message", stdout);
    try sailor.color.warn("Warning message", stdout);
    try sailor.color.info("Info message", stdout);
}
```

**Key features**:
- Auto color depth detection (`detectColorSupport`)
- Basic 16 colors, 256-color palette, RGB truecolor
- Style composition (fg, bg, bold, italic, underline)
- Semantic helpers (err, ok, warn, info)
- NO_COLOR environment variable support

### arg.zig — Argument Parsing

The `arg` module provides type-safe, comptime-validated command-line argument parsing.

```zig
const sailor = @import("sailor");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define flags at compile time
    const flags = comptime &[_]sailor.arg.Flag{
        .{ .name = "verbose", .short = 'v', .type = .bool, .help = "Enable verbose output" },
        .{ .name = "output", .short = 'o', .type = .string, .help = "Output file path" },
        .{ .name = "count", .short = 'n', .type = .int, .help = "Number of iterations" },
    };

    // Parse arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const result = try sailor.arg.parse(flags, args, allocator);
    defer result.deinit();

    // Access parsed values
    const verbose = try result.get("verbose", bool) orelse false;
    const output = try result.get("output", []const u8) orelse "output.txt";
    const count = try result.get("count", i32) orelse 10;

    std.debug.print("verbose={}, output={s}, count={}\n", .{ verbose, output, count });

    // Remaining positional arguments
    for (result.positional) |pos| {
        std.debug.print("Positional: {s}\n", .{pos});
    }
}
```

**Key features**:
- Comptime flag definitions with type safety
- Auto-generated `--help` output
- Short and long flag forms (`-v`, `--verbose`)
- Type coercion (bool, string, int)
- Positional argument collection
- Subcommand support
- "Did you mean?" suggestions for typos (Levenshtein distance)

## Interactive Modules

### repl.zig — Read-Eval-Print Loop

The `repl` module provides a line editor with history and completion.

```zig
const sailor = @import("sailor");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var repl = try sailor.repl.Repl.init(allocator, .{
        .prompt = ">> ",
        .history_file = ".myapp_history",
    });
    defer repl.deinit();

    while (true) {
        const line = repl.readline() catch |err| {
            if (err == error.EndOfStream) break; // Ctrl+D
            return err;
        };
        defer allocator.free(line);

        if (std.mem.eql(u8, line, "exit")) break;

        // Process command
        std.debug.print("You entered: {s}\n", .{line});
    }
}
```

**Key features**:
- Line editing with cursor movement
- Command history (up/down arrows)
- History persistence to file
- Tab completion callback support
- Ctrl+C/Ctrl+D handling
- Pipe mode fallback for non-TTY input

### progress.zig — Progress Indicators

The `progress` module provides progress bars and spinners.

```zig
const sailor = @import("sailor");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    // Progress bar
    var bar = try sailor.progress.Bar.init(allocator, .{
        .total = 100,
        .width = 40,
        .show_percentage = true,
        .show_eta = true,
    });
    defer bar.deinit();

    var i: usize = 0;
    while (i <= 100) : (i += 1) {
        try bar.update(i, stdout);
        std.time.sleep(50 * std.time.ns_per_ms);
    }

    // Spinner
    var spinner = try sailor.progress.Spinner.init(allocator, .{
        .frames = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        .message = "Loading...",
    });
    defer spinner.deinit();

    i = 0;
    while (i < 50) : (i += 1) {
        try spinner.update(stdout);
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}
```

**Key features**:
- Progress bars with percentage and ETA
- Spinners with Braille animation frames
- Multi-progress for concurrent tasks (thread-safe)
- Customizable width, style, messages

### fmt.zig — Output Formatting

The `fmt` module provides table, JSON, and CSV formatting.

```zig
const sailor = @import("sailor");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    // Table formatting
    var table = try sailor.fmt.Table.init(allocator);
    defer table.deinit();

    try table.addRow(&.{ "Name", "Age", "City" });
    try table.addRow(&.{ "Alice", "30", "NYC" });
    try table.addRow(&.{ "Bob", "25", "SF" });
    try table.render(stdout);

    // JSON streaming
    var json = sailor.fmt.JsonWriter.init(stdout);
    try json.beginObject();
    try json.field("status");
    try json.string("success");
    try json.field("count");
    try json.number(42);
    try json.endObject();

    // CSV output
    var csv = sailor.fmt.CsvWriter.init(stdout, .{ .delimiter = ',' });
    try csv.writeRow(&.{ "name", "value" });
    try csv.writeRow(&.{ "foo", "123" });
    try csv.writeRow(&.{ "bar", "456" });
}
```

**Key features**:
- Auto-width table columns
- JSON streaming writer
- CSV with configurable delimiter
- Mode switching for different output formats

## TUI Framework

### Building a TUI Application

The TUI framework consists of multiple modules that work together:

```zig
const sailor = @import("sailor");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var term = try sailor.tui.Terminal.init(allocator);
    defer term.deinit();

    // Enter alternate screen
    try term.enterAlternateScreen();
    defer term.leaveAlternateScreen() catch {};

    // Enable raw mode
    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    // Main render loop
    while (true) {
        // Draw frame
        try term.draw(drawUI);

        // Poll for events (100ms timeout)
        if (try term.pollEvent(100)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.code == .char and key.c == 'q') break;
                },
                .resize => |size| {
                    // Terminal was resized
                    std.debug.print("Resized to {}x{}\n", .{ size.cols, size.rows });
                },
                else => {},
            }
        }
    }
}

fn drawUI(frame: *sailor.tui.Frame) !void {
    const area = frame.size();

    // Create a block widget
    const block = sailor.tui.widgets.Block{
        .title = "My App",
        .borders = .all,
        .border_style = .{ .fg = .{ .basic = .cyan } },
    };

    // Render block
    try block.render(frame.buffer, area);

    // Add text inside
    const text = "Press 'q' to quit";
    const inner = block.inner(area);
    try frame.buffer.setString(
        inner.x + 1,
        inner.y + 1,
        text,
        .{},
    );
}
```

### Widget System

sailor includes 30+ built-in widgets:

**Core Widgets**:
- `Block` — Container with borders and title
- `Paragraph` — Multi-line text with wrapping
- `List` — Scrollable item list with selection
- `Table` — Multi-column data grid
- `Input` — Single-line text input
- `Tabs` — Tab navigation
- `StatusBar` — Bottom status line
- `Gauge` — Progress indicator

**Advanced Widgets**:
- `Tree` — Hierarchical tree view
- `TextArea` — Multi-line editor
- `Sparkline` — Inline chart
- `BarChart`, `LineChart` — Data visualization
- `Canvas` — Custom drawing surface
- `Dialog`, `Popup` — Modal overlays
- `Notification` — Toast messages

**Interactive Widgets**:
- `Menu` — Keyboard-navigable menu
- `Calendar` — Date picker
- `FileBrowser` — File system navigator
- `Select`, `Checkbox`, `Radio` — Form inputs
- `Autocomplete` — Type-ahead completion

**Editor Widgets**:
- `Editor` — Syntax-highlighted code editor
- `RichText` — Rich text input with formatting

See `examples/` directory for complete working examples.

## Layout System

sailor uses a constraint-based layout system:

```zig
const layout = sailor.tui.Layout.init(.horizontal)
    .constraints(&.{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    });

const chunks = layout.split(area);
// chunks[0] = left half
// chunks[1] = right half
```

**Constraint types**:
- `.length` — Fixed size in characters
- `.percentage` — Percentage of available space
- `.min` — Minimum size
- `.max` — Maximum size
- `.ratio` — Ratio (e.g., 1:2)

**Layout directions**:
- `.horizontal` — Left to right
- `.vertical` — Top to bottom

## Advanced Features

### Theming

sailor supports runtime theme switching:

```zig
const theme = sailor.tui.Theme{
    .primary = .{ .rgb = .{ .r = 100, .g = 150, .b = 255 } },
    .secondary = .{ .basic = .cyan },
    .success = .{ .basic = .green },
    .error = .{ .basic = .red },
    .warning = .{ .basic = .yellow },
    .info = .{ .basic = .blue },
};

term.setTheme(theme);
```

### Accessibility

- Screen reader hints via `ScreenReaderOutput`
- Focus management with `FocusManager`
- Keyboard navigation with `KeyboardNavigator`
- High-contrast themes for WCAG AAA compliance

### Graphics

- Sixel graphics protocol support
- Kitty graphics protocol support
- Image rendering in supported terminals

### Internationalization

- Unicode width calculation (CJK, emoji)
- RTL text support (Arabic, Hebrew)
- BiDi text rendering (Unicode UAX #9)

## Next Steps

1. **Examples**: Check `examples/` directory for complete applications
2. **API Reference**: See generated docs in `docs/api/`
3. **Troubleshooting**: Read `docs/troubleshooting.md` for common issues
4. **Performance**: Read `docs/performance.md` for optimization tips

## Getting Help

- GitHub Issues: https://github.com/yusa-imit/sailor/issues
- Documentation: https://github.com/yusa-imit/sailor/tree/main/docs
- Examples: https://github.com/yusa-imit/sailor/tree/main/examples
