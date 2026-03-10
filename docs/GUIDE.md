# sailor Getting Started Guide

This guide will help you build CLI tools and TUI applications with sailor.

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [CLI Applications](#cli-applications)
4. [TUI Applications](#tui-applications)
5. [Widget Gallery](#widget-gallery)
6. [Best Practices](#best-practices)

---

## Installation

### Requirements

- Zig 0.15.x or later
- No other dependencies

### Setup

Add sailor to your `build.zig.zon`:

```zig
.{
    .name = "myapp",
    .version = "0.1.0",
    .paths = .{""},
    .dependencies = .{
        .sailor = .{
            // For local development:
            .path = "../sailor",

            // Or use git URL (when published):
            // .url = "https://github.com/yourusername/sailor/archive/v0.5.0.tar.gz",
            // .hash = "...",
        },
    },
}
```

Update your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add sailor dependency
    const sailor = b.dependency("sailor", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("sailor", sailor.module("sailor"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

---

## Quick Start

### Hello, World!

Create `src/main.zig`:

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const style = sailor.color.Style{
        .fg = .green,
        .bold = true,
    };

    try style.write(stdout, "Hello, sailor!\n");
}
```

Build and run:

```bash
zig build run
```

---

## CLI Applications

### Argument Parsing

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = sailor.arg.Parser.init(allocator);
    defer parser.deinit();

    // Define flags
    parser.addFlag(.{
        .long = "input",
        .short = 'i',
        .type = .string,
        .description = "Input file path",
        .required = true,
    });

    parser.addFlag(.{
        .long = "output",
        .short = 'o',
        .type = .string,
        .description = "Output file path",
    });

    parser.addFlag(.{
        .long = "verbose",
        .short = 'v',
        .description = "Enable verbose logging",
    });

    // Parse arguments
    const args = parser.parse() catch {
        try parser.printHelp(std.io.getStdErr().writer());
        return error.InvalidArgs;
    };

    // Access parsed values
    const input = args.flag("input").?;
    const output = args.flag("output") orelse "output.txt";
    const verbose = args.flagBool("verbose");

    if (verbose) {
        std.debug.print("Input: {s}\n", .{input});
        std.debug.print("Output: {s}\n", .{output});
    }
}
```

### Styled Output

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Semantic helpers
    try sailor.color.ok(stdout, "✓ Build successful\n");
    try sailor.color.err(stdout, "✗ Build failed\n");
    try sailor.color.warn(stdout, "⚠ Deprecated API\n");
    try sailor.color.info(stdout, "ℹ Using cache\n");

    // Custom styles
    const header_style = sailor.color.Style{
        .fg = .cyan,
        .bold = true,
        .underline = true,
    };
    try header_style.write(stdout, "\nProject Status\n");

    // RGB colors
    const custom = sailor.color.Style{
        .fg = .{ .rgb = .{ .r = 255, .g = 100, .b = 200 } },
        .bg = .{ .indexed = 234 },
    };
    try custom.write(stdout, "Custom RGB color\n");
}
```

### Progress Indicators

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    // Progress bar
    var bar = try sailor.progress.Bar.init(allocator, 100);
    defer bar.deinit();

    for (0..101) |i| {
        bar.set(i);
        try stdout.writeAll("\r");
        try bar.render(stdout);
        std.time.sleep(20 * std.time.ns_per_ms);
    }
    try stdout.writeAll("\n");
    bar.finish();

    // Spinner
    var spinner = try sailor.progress.Spinner.init(allocator, .braille);
    defer spinner.deinit();

    for (0..50) |_| {
        spinner.tick();
        try stdout.writeAll("\r");
        try spinner.render(stdout);
        try stdout.writeAll(" Processing...");
        std.time.sleep(50 * std.time.ns_per_ms);
    }
    try stdout.writeAll("\n");
    spinner.finish();
}
```

### Table Formatting

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var table = sailor.fmt.Table.init(allocator);
    defer table.deinit();

    try table.setHeaders(&.{ "Name", "Age", "City", "Status" });
    try table.addRow(&.{ "Alice", "30", "NYC", "Active" });
    try table.addRow(&.{ "Bob", "25", "LA", "Active" });
    try table.addRow(&.{ "Charlie", "35", "SF", "Inactive" });

    try table.render(std.io.getStdOut().writer());
}
```

### REPL

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var repl = try sailor.repl.Repl.init(allocator);
    defer repl.deinit();

    repl.setPrompt("myapp> ");

    // Optional: tab completion
    repl.setCompleter(completer);

    while (try repl.readline()) |line| {
        defer allocator.free(line);

        if (std.mem.eql(u8, line, "exit")) break;

        try repl.addHistory(line);

        // Process command
        if (std.mem.startsWith(u8, line, "echo ")) {
            const msg = line[5..];
            try std.io.getStdOut().writer().print("{s}\n", .{msg});
        } else if (line.len > 0) {
            try sailor.color.err(
                std.io.getStdOut().writer(),
                "Unknown command\n",
            );
        }
    }
}

fn completer(
    allocator: std.mem.Allocator,
    line: []const u8,
    pos: usize,
) ![]const []const u8 {
    _ = pos;
    const commands = [_][]const u8{ "echo", "exit", "help" };

    var matches = std.ArrayList([]const u8).init(allocator);
    for (commands) |cmd| {
        if (std.mem.startsWith(u8, cmd, line)) {
            try matches.append(cmd);
        }
    }
    return matches.toOwnedSlice();
}
```

---

## TUI Applications

### Basic TUI

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try sailor.tui.Terminal.init(allocator);
    defer terminal.deinit();

    try terminal.run(render);
}

fn render(frame: *sailor.tui.Frame) !void {
    const area = frame.size();

    const block = sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("My App"))
        .setBorders(sailor.tui.Borders.all);

    const para = sailor.tui.widgets.Paragraph.init(
        sailor.tui.Line.fromString("Hello, TUI!")
    ).setBlock(block);

    frame.renderWidget(para, area);
}
```

### Event Handling

```zig
const std = @import("std");
const sailor = @import("sailor");

const App = struct {
    counter: u32 = 0,
    running: bool = true,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try sailor.tui.Terminal.init(allocator);
    defer terminal.deinit();

    var app = App{};

    while (app.running) {
        try terminal.draw(app, render);

        if (try terminal.pollEvent(100)) |event| {
            switch (event) {
                .key => |key| switch (key) {
                    .char => |c| switch (c) {
                        'q' => app.running = false,
                        '+' => app.counter += 1,
                        '-' => if (app.counter > 0) app.counter -= 1,
                        else => {},
                    },
                    .ctrl_c => app.running = false,
                    else => {},
                },
                .resize => {},
            }
        }
    }
}

fn render(app: *App, frame: *sailor.tui.Frame) !void {
    const area = frame.size();

    const block = sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Counter"))
        .setBorders(sailor.tui.Borders.all);

    var buf: [64]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "Count: {}\nPress +/- to change, q to quit", .{app.counter});

    const para = sailor.tui.widgets.Paragraph.init(
        sailor.tui.Line.fromString(text)
    ).setBlock(block);

    frame.renderWidget(para, area);
}
```

### Layout System

```zig
fn render(frame: *sailor.tui.Frame) !void {
    const area = frame.size();

    // Vertical split: 20% top, 60% middle, 20% bottom
    const vertical = sailor.tui.Layout.init(
        frame.allocator,
        .vertical,
        &.{
            .{ .percentage = 20 },
            .{ .percentage = 60 },
            .{ .percentage = 20 },
        },
    );
    defer vertical.deinit();
    const v_chunks = vertical.split(area);

    // Horizontal split of middle section
    const horizontal = sailor.tui.Layout.init(
        frame.allocator,
        .horizontal,
        &.{
            .{ .percentage = 50 },
            .{ .percentage = 50 },
        },
    );
    defer horizontal.deinit();
    const h_chunks = horizontal.split(v_chunks[1]);

    // Render widgets in each area
    const top_block = sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Header"))
        .setBorders(sailor.tui.Borders.all);
    frame.renderWidget(top_block, v_chunks[0]);

    const left_block = sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Left"))
        .setBorders(sailor.tui.Borders.all);
    frame.renderWidget(left_block, h_chunks[0]);

    const right_block = sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Right"))
        .setBorders(sailor.tui.Borders.all);
    frame.renderWidget(right_block, h_chunks[1]);

    const bottom_status = sailor.tui.widgets.StatusBar.init()
        .setLeft(sailor.tui.Line.fromString("Ready"))
        .setRight(sailor.tui.Line.fromString("Ctrl+C to quit"));
    frame.renderWidget(bottom_status, v_chunks[2]);
}
```

---

## Widget Gallery

### List Widget

```zig
const items = &[_]sailor.tui.Line{
    sailor.tui.Line.fromString("Item 1"),
    sailor.tui.Line.fromString("Item 2"),
    sailor.tui.Line.fromString("Item 3"),
};

const list = sailor.tui.widgets.List.init(items)
    .setSelected(0)
    .setHighlightStyle(sailor.tui.Style{ .fg = .cyan, .bold = true })
    .setBlock(sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Menu"))
        .setBorders(sailor.tui.Borders.all));

frame.renderWidget(list, area);
```

### Table Widget

```zig
const table = sailor.tui.widgets.Table.init(
    frame.allocator,
    &.{ "Name", "Status", "Progress" },
) catch return;
defer table.deinit();

table.setRows(&.{
    &.{ "Task 1", "Done", "100%" },
    &.{ "Task 2", "Running", "45%" },
    &.{ "Task 3", "Pending", "0%" },
}).setWidths(&.{ 20, 10, 10 })
  .setBlock(sailor.tui.widgets.Block.init()
      .setBorders(sailor.tui.Borders.all));

frame.renderWidget(table, area);
```

### Tabs Widget

```zig
const tabs = sailor.tui.widgets.Tabs.init(&.{ "Home", "Settings", "About" })
    .setSelected(app.selected_tab)
    .setBlock(sailor.tui.widgets.Block.init()
        .setBorders(sailor.tui.Borders.all));

frame.renderWidget(tabs, area);
```

### Gauge Widget

```zig
const gauge = sailor.tui.widgets.Gauge.init(app.progress / 100.0)
    .setLabel("Downloading...")
    .setBlock(sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Progress"))
        .setBorders(sailor.tui.Borders.all));

frame.renderWidget(gauge, area);
```

### BarChart Widget

```zig
const data = &[_]u64{ 8, 12, 5, 15, 10 };
const labels = &[_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri" };

const chart = sailor.tui.widgets.BarChart.init(data, labels)
    .setBlock(sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Weekly Stats"))
        .setBorders(sailor.tui.Borders.all));

frame.renderWidget(chart, area);
```

### LineChart Widget

```zig
const dataset = sailor.tui.widgets.LineChart.Dataset{
    .label = "Revenue",
    .data = &.{ 10.0, 20.0, 15.0, 30.0, 25.0 },
    .style = .{ .fg = .green },
};

const chart = sailor.tui.widgets.LineChart.init(&.{dataset})
    .setXLabels(&.{ "Q1", "Q2", "Q3", "Q4", "Q5" })
    .setYRange(0, 40)
    .setBlock(sailor.tui.widgets.Block.init()
        .setTitle(sailor.tui.Line.fromString("Quarterly Revenue"))
        .setBorders(sailor.tui.Borders.all));

frame.renderWidget(chart, area);
```

### Dialog Widget

```zig
const dialog = try sailor.tui.widgets.Dialog.init(
    frame.allocator,
    "Confirm",
    "Are you sure you want to delete this item?",
);
defer dialog.deinit();

dialog.setButtons(&.{ "Yes", "No" })
      .setSelected(app.dialog_selected);

frame.renderWidget(dialog, area);
```

### Notification Widget

```zig
const notif = sailor.tui.widgets.Notification.init("Task completed!")
    .setLevel(.success);

frame.renderWidget(notif, area);
```

### HttpClient Widget (v1.8.0)

```zig
var client = sailor.tui.widgets.HttpClient.init(frame.allocator);
defer client.deinit();

// Update progress from your HTTP client
client.updateProgress(downloaded_bytes, total_bytes, elapsed_ms);

// Or mark as completed/failed
client.complete(response_body);
// client.fail("Connection timeout");

client.setBlock(sailor.tui.widgets.Block.init()
    .setTitle(sailor.tui.Line.fromString("Download"))
    .setBorders(sailor.tui.Borders.all));

frame.renderWidget(client, area);
```

### WebSocket Widget (v1.8.0)

```zig
var ws = try sailor.tui.widgets.WebSocket.init(frame.allocator);
defer ws.deinit();

// Push messages to the widget
try ws.pushMessage("Server connected", .incoming);
try ws.pushMessage("Hello, server!", .outgoing);

ws.setTimestampFormat(.datetime)
  .setBlock(sailor.tui.widgets.Block.init()
      .setTitle(sailor.tui.Line.fromString("WebSocket Feed"))
      .setBorders(sailor.tui.Borders.all));

// Handle scrolling
if (scroll_up_event) ws.scrollUp(1);
if (scroll_down_event) ws.scrollDown(1);

frame.renderWidget(ws, area);
```

### TaskRunner Widget (v1.8.0)

```zig
var runner = try sailor.tui.widgets.TaskRunner.init(frame.allocator);
defer runner.deinit();

// Add tasks
try runner.addTask(task_handle, "Build project");
try runner.addTask(task_handle2, "Run tests");

// Update task states
runner.updateTaskState(task_handle, .running, 0.45); // 45% progress
runner.updateTaskState(task_handle2, .completed, 1.0);

runner.setDisplayFormat(.detailed)
      .setBlock(sailor.tui.widgets.Block.init()
          .setTitle(sailor.tui.Line.fromString("Background Tasks"))
          .setBorders(sailor.tui.Borders.all));

frame.renderWidget(runner, area);
```

### LogViewer Widget (v1.8.0)

```zig
var viewer = try sailor.tui.widgets.LogViewer.init(frame.allocator);
defer viewer.deinit();

// Push log entries
try viewer.pushLog(.info, "Application started", "main");
try viewer.pushLog(.warn, "Config file missing", "config");
try viewer.pushLog(.err, "Connection failed", "network");

// Enable auto-scroll and filtering
viewer.setAutoScroll(true)
      .setMinLevel(.info)
      .setSourceFilter("network")
      .setBlock(sailor.tui.widgets.Block.init()
          .setTitle(sailor.tui.Line.fromString("Logs"))
          .setBorders(sailor.tui.Borders.all));

// Handle scrolling
if (scroll_up_event) viewer.scrollUp(1);

frame.renderWidget(viewer, area);
```

---

## Best Practices

### Memory Management

sailor is a library, so **you control all allocations**:

```zig
// ✓ Good: Pass allocator explicitly
var table = sailor.fmt.Table.init(allocator);
defer table.deinit();

// ✓ Good: Use arena for request-scoped allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const arena_alloc = arena.allocator();
```

### Error Handling

sailor returns errors instead of panicking:

```zig
// ✓ Good: Handle errors
const size = sailor.term.getSize(stdout) catch |err| {
    std.debug.print("Failed to get terminal size: {}\n", .{err});
    return err;
};

// ✗ Bad: Don't use unreachable in library usage
const size = sailor.term.getSize(stdout) catch unreachable;
```

### Writer-Based Output

Never write to stdout/stderr directly in library code. sailor APIs accept writers:

```zig
// ✓ Good: Write to provided writer
const stdout = std.io.getStdOut().writer();
try sailor.color.ok(stdout, "Success\n");

// ✓ Good: Use buffer for testing
var buf = std.ArrayList(u8).init(allocator);
defer buf.deinit();
try sailor.color.ok(buf.writer(), "Success\n");
```

### Cross-Platform Code

sailor handles platform differences internally:

```zig
// ✓ This works on Linux, macOS, and Windows
const size = try sailor.term.getSize(std.io.getStdOut());
try sailor.term.enableRawMode(std.io.getStdIn());
defer sailor.term.disableRawMode(std.io.getStdIn()) catch {};
```

### TUI Event Loops

Always use timeout with `pollEvent` to allow rendering:

```zig
// ✓ Good: Timeout allows periodic rendering
while (app.running) {
    try terminal.draw(app, render);
    if (try terminal.pollEvent(100)) |event| {
        handleEvent(&app, event);
    }
}

// ✗ Bad: Blocks forever, UI freezes
while (app.running) {
    const event = try terminal.pollEvent(std.math.maxInt(u64));
    handleEvent(&app, event);
    try terminal.draw(app, render);
}
```

### Widget Composition

Build complex UIs by composing simple widgets:

```zig
// Create reusable widget functions
fn renderHeader(frame: *Frame, area: Rect, title: []const u8) void {
    const block = Block.init()
        .setTitle(Line.fromString(title))
        .setBorders(Borders.all);
    frame.renderWidget(block, area);
}

fn renderBody(frame: *Frame, area: Rect, app: *App) !void {
    const list = List.init(&app.items)
        .setSelected(app.selected);
    frame.renderWidget(list, area);
}
```

---

## Examples

Check the `examples/` directory for complete applications:

- **`hello.zig`** - Minimal TUI with a single block
- **`counter.zig`** - Interactive counter with event handling
- **`dashboard.zig`** - Multi-widget dashboard with layout

Run examples:

```bash
zig build example -- hello
zig build example -- counter
zig build example -- dashboard
```

---

## Next Steps

- Read [API.md](API.md) for complete API reference
- Check [PRD.md](PRD.md) for design rationale
- Browse `src/` for implementation details
- Join discussions on GitHub

Happy building! 🚢
