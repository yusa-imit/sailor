# Sailor Common Patterns & Examples

This guide provides examples for common use cases and patterns when using the Sailor library.

## Table of Contents

- [Terminal Setup](#terminal-setup)
- [Color & Styling](#color--styling)
- [Argument Parsing](#argument-parsing)
- [Progress Indicators](#progress-indicators)
- [REPL (Interactive Shells)](#repl-interactive-shells)
- [Formatted Output](#formatted-output)
- [TUI Applications](#tui-applications)
- [Event Handling](#event-handling)
- [Layout Management](#layout-management)
- [Widget Composition](#widget-composition)

---

## Terminal Setup

### Basic Terminal Detection

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    // Check if running in a TTY
    if (sailor.term.isatty(std.posix.STDOUT_FILENO)) {
        std.debug.print("Running in a terminal\n", .{});
    } else {
        std.debug.print("Output is redirected\n", .{});
    }

    // Get terminal size
    const size = sailor.term.getSize() catch {
        std.debug.print("Could not determine terminal size\n", .{});
        return;
    };

    std.debug.print("Terminal: {d}x{d}\n", .{ size.cols, size.rows });
}
```

### Entering Raw Mode

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    // Enter raw mode (disable line buffering, echo)
    var raw_mode = try sailor.term.RawMode.enter(std.posix.STDIN_FILENO);
    defer raw_mode.deinit();

    std.debug.print("Raw mode enabled. Press 'q' to quit.\n", .{});

    const stdin = std.io.getStdIn();
    var buf: [1]u8 = undefined;

    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) break;

        if (buf[0] == 'q') break;
        std.debug.print("Got: {c}\n", .{buf[0]});
    }
}
```

---

## Color & Styling

### Basic Colors

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Create a style with red foreground
    const red_style = sailor.color.Style{
        .fg = .{ .basic = .red },
    };

    try red_style.apply(writer);
    try writer.writeAll("Red text");
    try sailor.color.reset(writer);
    try writer.writeAll("\n");

    std.debug.print("{s}", .{fbs.getWritten()});
}
```

### Truecolor RGB

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Custom RGB color
    const custom_style = sailor.color.Style{
        .fg = .{ .rgb = .{ .r = 255, .g = 128, .b = 64 } },
        .bg = .{ .rgb = .{ .r = 32, .g = 64, .b = 128 } },
        .bold = true,
    };

    try custom_style.apply(writer);
    try writer.writeAll("Custom RGB colors");
    try sailor.color.reset(writer);

    std.debug.print("{s}\n", .{fbs.getWritten()});
}
```

### Semantic Colors

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    // Use semantic helpers
    try sailor.color.err(writer, "Error: something went wrong\n");
    try sailor.color.ok(writer, "Success: operation completed\n");
    try sailor.color.warn(writer, "Warning: check this\n");
    try sailor.color.info(writer, "Info: just so you know\n");

    std.debug.print("{s}", .{fbs.getWritten()});
}
```

---

## Argument Parsing

### Basic Flags

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Flags = struct {
        verbose: bool = false,
        output: ?[]const u8 = null,
        count: u32 = 10,
    };

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parser = sailor.arg.Parser(Flags).init(allocator);
    defer parser.deinit();

    try parser.addFlag("verbose", .{ .short = 'v' });
    try parser.addFlag("output", .{ .short = 'o', .takes_value = true });
    try parser.addFlag("count", .{ .short = 'n', .takes_value = true });

    const flags = try parser.parse(args);

    std.debug.print("Verbose: {}\n", .{flags.verbose});
    std.debug.print("Output: {?s}\n", .{flags.output});
    std.debug.print("Count: {d}\n", .{flags.count});
}
```

### Subcommands

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: app <command>\n", .{});
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "init")) {
        try runInit(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "build")) {
        try runBuild(allocator, args[2..]);
    } else {
        std.debug.print("Unknown command: {s}\n", .{cmd});
        std.debug.print("Did you mean: init, build?\n", .{});
    }
}

fn runInit(allocator: std.mem.Allocator, args: [][]const u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("Running init...\n", .{});
}

fn runBuild(allocator: std.mem.Allocator, args: [][]const u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("Running build...\n", .{});
}
```

---

## Progress Indicators

### Progress Bar

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    const stdout = std.io.getStdOut();
    const writer = stdout.writer().any();

    var progress = sailor.progress.Bar.init(writer, 100);

    var i: u32 = 0;
    while (i <= 100) : (i += 1) {
        try progress.update(i);
        std.time.sleep(50 * std.time.ns_per_ms);
    }

    try progress.finish();
}
```

### Spinner

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    const stdout = std.io.getStdOut();
    const writer = stdout.writer().any();

    var spinner = sailor.progress.Spinner.init(writer, "Loading");

    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        try spinner.tick();
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    try spinner.finish("Done!");
}
```

---

## REPL (Interactive Shells)

### Basic REPL

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const writer = stdout.writer().any();

    var repl = try sailor.repl.Repl.init(allocator, stdin, writer);
    defer repl.deinit();

    try writer.writeAll("Welcome! Type 'exit' to quit.\n");

    while (true) {
        const line = try repl.readline("> ");
        if (line == null) break;

        const trimmed = std.mem.trim(u8, line.?, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "exit")) break;

        try writer.print("You typed: {s}\n", .{trimmed});
    }
}
```

### REPL with Completion

```zig
const std = @import("std");
const sailor = @import("sailor");

const commands = [_][]const u8{ "help", "list", "create", "delete", "exit" };

fn completer(allocator: std.mem.Allocator, line: []const u8) ![][]const u8 {
    var results = std.ArrayList([]const u8).init(allocator);

    for (commands) |cmd| {
        if (std.mem.startsWith(u8, cmd, line)) {
            try results.append(try allocator.dupe(u8, cmd));
        }
    }

    return results.toOwnedSlice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const writer = stdout.writer().any();

    var repl = try sailor.repl.Repl.init(allocator, stdin, writer);
    defer repl.deinit();

    repl.setCompleter(completer);

    while (true) {
        const line = try repl.readline("> ");
        if (line == null) break;

        const trimmed = std.mem.trim(u8, line.?, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, "exit")) break;

        try writer.print("Executing: {s}\n", .{trimmed});
    }
}
```

---

## Formatted Output

### Table

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut();
    const writer = stdout.writer().any();

    var table = try sailor.fmt.Table.init(allocator, writer);
    defer table.deinit();

    try table.addHeader(&[_][]const u8{ "Name", "Age", "City" });
    try table.addRow(&[_][]const u8{ "Alice", "30", "New York" });
    try table.addRow(&[_][]const u8{ "Bob", "25", "San Francisco" });
    try table.addRow(&[_][]const u8{ "Charlie", "35", "Seattle" });

    try table.render();
}
```

### JSON Output

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    const stdout = std.io.getStdOut();
    const writer = stdout.writer().any();

    var json = sailor.fmt.Json.init(writer);

    try json.beginObject();
    try json.field("name", "sailor");
    try json.field("version", "1.0.0");
    try json.beginArray("features");
    try json.arrayItem("terminal");
    try json.arrayItem("color");
    try json.arrayItem("tui");
    try json.endArray();
    try json.endObject();
}
```

---

## TUI Applications

### Minimal TUI

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tui = try sailor.tui.Terminal.init(allocator);
    defer tui.deinit();

    try tui.enterAlternateScreen();
    defer tui.exitAlternateScreen() catch {};

    var raw_mode = try sailor.term.RawMode.enter(std.posix.STDIN_FILENO);
    defer raw_mode.deinit();

    while (true) {
        try tui.draw(drawFrame);

        const event = try tui.pollEvent(100);
        if (event) |ev| {
            if (ev == .key and ev.key.char == 'q') break;
        }
    }
}

fn drawFrame(frame: *sailor.tui.Frame) !void {
    const area = frame.size;

    const text = sailor.tui.style.Line.init(&[_]sailor.tui.style.Span{
        .{ .content = "Press 'q' to quit" },
    });

    var para = sailor.tui.widgets.Paragraph{
        .lines = &[_]sailor.tui.style.Line{text},
    };

    try para.render(frame.buffer, area);
}
```

### Widget Example

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tui = try sailor.tui.Terminal.init(allocator);
    defer tui.deinit();

    try tui.enterAlternateScreen();
    defer tui.exitAlternateScreen() catch {};

    var raw_mode = try sailor.term.RawMode.enter(std.posix.STDIN_FILENO);
    defer raw_mode.deinit();

    var selected: usize = 0;
    const items = [_][]const u8{ "Option 1", "Option 2", "Option 3" };

    while (true) {
        try tui.draw(struct {
            selected: usize,
            items: []const []const u8,

            pub fn draw(self: @This(), frame: *sailor.tui.Frame) !void {
                const area = frame.size;

                var list = sailor.tui.widgets.List{
                    .items = self.items,
                    .selected = self.selected,
                };

                try list.render(frame.buffer, area);
            }
        }{ .selected = selected, .items = &items }.draw);

        const event = try tui.pollEvent(100);
        if (event) |ev| {
            if (ev == .key) {
                if (ev.key.char == 'q') break;
                if (ev.key.char == 'j' and selected < items.len - 1) selected += 1;
                if (ev.key.char == 'k' and selected > 0) selected -= 1;
            }
        }
    }
}
```

---

## Event Handling

### Keyboard Events

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn handleKeyEvent(event: sailor.tui.Event) !void {
    switch (event) {
        .key => |key| {
            if (key.ctrl) {
                std.debug.print("Ctrl+{c}\n", .{key.char});
            } else if (key.alt) {
                std.debug.print("Alt+{c}\n", .{key.char});
            } else {
                std.debug.print("Key: {c}\n", .{key.char});
            }
        },
        .resize => |size| {
            std.debug.print("Resize: {d}x{d}\n", .{ size.cols, size.rows });
        },
        else => {},
    }
}
```

### Mouse Events

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn handleMouseEvent(event: sailor.tui.Event) !void {
    switch (event) {
        .mouse => |mouse| {
            switch (mouse.kind) {
                .press => std.debug.print("Mouse press at ({d}, {d})\n", .{ mouse.x, mouse.y }),
                .release => std.debug.print("Mouse release\n", .{}),
                .scroll_up => std.debug.print("Scroll up\n", .{}),
                .scroll_down => std.debug.print("Scroll down\n", .{}),
            }
        },
        else => {},
    }
}
```

---

## Layout Management

### Split Layout

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn splitLayout(area: sailor.tui.layout.Rect) [2]sailor.tui.layout.Rect {
    const chunks = sailor.tui.layout.split(
        .vertical,
        &[_]sailor.tui.layout.Constraint{
            .{ .percentage = 50 },
            .{ .percentage = 50 },
        },
        area,
    );
    return chunks;
}
```

### Complex Layout

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn complexLayout(area: sailor.tui.layout.Rect) [3]sailor.tui.layout.Rect {
    // Split vertically: header, body, footer
    const vertical_chunks = sailor.tui.layout.split(
        .vertical,
        &[_]sailor.tui.layout.Constraint{
            .{ .length = 3 },  // Header: 3 rows
            .{ .min = 0 },     // Body: remaining
            .{ .length = 1 },  // Footer: 1 row
        },
        area,
    );

    return vertical_chunks;
}
```

---

## Widget Composition

### Custom Widget

```zig
const std = @import("std");
const sailor = @import("sailor");

const MyWidget = struct {
    title: []const u8,
    content: []const u8,

    pub fn render(self: @This(), buffer: *sailor.tui.buffer.Buffer, area: sailor.tui.layout.Rect) !void {
        // Draw block with title
        var block = sailor.tui.widgets.Block{
            .title = self.title,
            .borders = .all,
        };
        try block.render(buffer, area);

        // Draw content inside block
        const inner = block.inner(area);

        const text_line = sailor.tui.style.Line.init(&[_]sailor.tui.style.Span{
            .{ .content = self.content },
        });

        var para = sailor.tui.widgets.Paragraph{
            .lines = &[_]sailor.tui.style.Line{text_line},
        };

        try para.render(buffer, inner);
    }
};
```

### Composing Widgets

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn renderDashboard(frame: *sailor.tui.Frame) !void {
    const area = frame.size;

    // Split into left and right panels
    const chunks = sailor.tui.layout.split(
        .horizontal,
        &[_]sailor.tui.layout.Constraint{
            .{ .percentage = 50 },
            .{ .percentage = 50 },
        },
        area,
    );

    // Left panel: status
    var status = MyWidget{
        .title = "Status",
        .content = "All systems operational",
    };
    try status.render(frame.buffer, chunks[0]);

    // Right panel: logs
    var logs = MyWidget{
        .title = "Logs",
        .content = "No errors",
    };
    try logs.render(frame.buffer, chunks[1]);
}
```

---

## Best Practices

### Memory Management

Always use allocators provided by the caller:

```zig
pub fn myFunction(allocator: std.mem.Allocator) !void {
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);

    // Use data...
}
```

### Error Handling

Propagate errors, don't panic:

```zig
// ✅ Good: propagate error
pub fn safeFunction() !void {
    try riskyOperation();
}

// ❌ Bad: panic in library code
pub fn unsafeFunction() void {
    riskyOperation() catch unreachable;
}
```

### Writer-Based Output

Never write directly to stdout in library code:

```zig
// ✅ Good: use writer
pub fn output(writer: std.io.AnyWriter, msg: []const u8) !void {
    try writer.writeAll(msg);
}

// ❌ Bad: hardcoded stdout
pub fn badOutput(msg: []const u8) !void {
    try std.io.getStdOut().writeAll(msg);
}
```

### Platform Independence

Use `comptime` for platform-specific code:

```zig
pub fn platformSpecific() !void {
    if (comptime builtin.os.tag == .windows) {
        // Windows implementation
    } else {
        // Unix implementation
    }
}
```

---

## Further Reading

- [Examples directory](../examples/) - Full working examples
- [API Reference](../README.md) - Complete API documentation
- [PRD](./PRD.md) - Product requirements and design decisions
