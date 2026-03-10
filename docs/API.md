# sailor API Reference

Complete API documentation for all sailor modules.

## Table of Contents

- [term](#term) - Terminal backend
- [color](#color) - Styled output
- [arg](#arg) - Argument parser
- [repl](#repl) - Interactive REPL
- [progress](#progress) - Progress indicators
- [fmt](#fmt) - Result formatting
- [tui](#tui) - Full-screen TUI framework
  - [Core](#tui-core)
  - [Layout](#layout)
  - [Widgets](#widgets)

---

## term

Terminal backend for raw mode, key reading, TTY detection, and terminal size.

### Types

```zig
pub const Key = union(enum) {
    char: u21,
    escape,
    backspace,
    delete,
    enter,
    tab,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    ctrl_c,
    unknown,
};

pub const Size = struct {
    width: u16,
    height: u16,
};
```

### Functions

#### `isTTY`
```zig
pub fn isTTY(file: std.fs.File) bool
```
Check if a file descriptor is a TTY.

**Example:**
```zig
const is_tty = sailor.term.isTTY(std.io.getStdOut());
if (!is_tty) {
    return error.NotATTY;
}
```

#### `getSize`
```zig
pub fn getSize(file: std.fs.File) !Size
```
Get terminal size in columns and rows.

**Errors:**
- `error.NotATTY` - File is not a terminal
- `error.Unexpected` - System call failed

**Example:**
```zig
const size = try sailor.term.getSize(std.io.getStdOut());
std.debug.print("Terminal: {}x{}\n", .{ size.width, size.height });
```

#### `enableRawMode`
```zig
pub fn enableRawMode(file: std.fs.File) !void
```
Enable raw mode (no echo, no buffering, no signals).

**Platform:** Linux, macOS (termios), Windows (console mode)

**Example:**
```zig
try sailor.term.enableRawMode(std.io.getStdIn());
defer sailor.term.disableRawMode(std.io.getStdIn()) catch {};
```

#### `disableRawMode`
```zig
pub fn disableRawMode(file: std.fs.File) !void
```
Restore terminal to normal mode.

#### `readKey`
```zig
pub fn readKey(reader: anytype) !Key
```
Read a single keypress. Blocks until a key is available.

**Example:**
```zig
while (true) {
    const key = try sailor.term.readKey(std.io.getStdIn().reader());
    switch (key) {
        .ctrl_c => break,
        .char => |c| std.debug.print("Pressed: {u}\n", .{c}),
        else => {},
    }
}
```

---

## color

Styled output with ANSI escape codes, 256-color, and truecolor support.

### Types

```zig
pub const Color = union(enum) {
    default,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    indexed: u8,
    rgb: struct { r: u8, g: u8, b: u8 },
};

pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,

    pub fn write(self: Style, writer: anytype, text: []const u8) !void
    pub fn format(self: Style, comptime fmt: []const u8, args: anytype, writer: anytype) !void
};

pub const ColorLevel = enum {
    none,
    basic,      // 16 colors
    extended,   // 256 colors
    truecolor,  // 24-bit RGB

    pub fn detect() ColorLevel
};
```

### Semantic Helpers

```zig
pub fn ok(writer: anytype, text: []const u8) !void    // Green, bold
pub fn err(writer: anytype, text: []const u8) !void   // Red, bold
pub fn warn(writer: anytype, text: []const u8) !void  // Yellow
pub fn info(writer: anytype, text: []const u8) !void  // Cyan
```

**Example:**
```zig
const stdout = std.io.getStdOut().writer();
try sailor.color.ok(stdout, "Success!\n");
try sailor.color.err(stdout, "Error!\n");

const style = sailor.color.Style{
    .fg = .{ .rgb = .{ .r = 255, .g = 100, .b = 50 } },
    .bold = true,
};
try style.write(stdout, "Custom color\n");
```

### Environment Variables

- `NO_COLOR` - Disable all colors if set
- `COLORTERM=truecolor` - Enable 24-bit color
- `TERM=xterm-256color` - Enable 256-color mode

---

## arg

Type-safe command-line argument parser with subcommand support.

### Types

```zig
pub const FlagType = enum {
    bool,
    string,
    int,
    float,
};

pub const FlagDef = struct {
    long: []const u8,
    short: ?u8 = null,
    description: []const u8 = "",
    type: FlagType = .bool,
    required: bool = false,
    default: ?[]const u8 = null,
};

pub const Parser = struct {
    pub fn init(allocator: std.mem.Allocator) Parser
    pub fn deinit(self: *Parser) void
    pub fn addFlag(self: *Parser, flag: FlagDef) void
    pub fn parse(self: *Parser) !ParseResult
    pub fn printHelp(self: Parser, writer: anytype) !void
};

pub const ParseResult = struct {
    pub fn flag(self: ParseResult, name: []const u8) ?[]const u8
    pub fn flagBool(self: ParseResult, name: []const u8) bool
    pub fn flagInt(self: ParseResult, name: []const u8) ?i64
    pub fn flagFloat(self: ParseResult, name: []const u8) ?f64
    pub fn args(self: ParseResult) []const []const u8
};
```

**Example:**
```zig
var parser = sailor.arg.Parser.init(allocator);
defer parser.deinit();

parser.addFlag(.{
    .long = "output",
    .short = 'o',
    .type = .string,
    .description = "Output file",
    .required = true,
});
parser.addFlag(.{
    .long = "verbose",
    .short = 'v',
    .description = "Enable verbose output",
});

const result = try parser.parse();
const output = result.flag("output") orelse return error.MissingOutput;
const verbose = result.flagBool("verbose");
```

---

## repl

Interactive REPL with line editing, history, and tab completion.

### Types

```zig
pub const Repl = struct {
    pub fn init(allocator: std.mem.Allocator) !Repl
    pub fn deinit(self: *Repl) void
    pub fn setPrompt(self: *Repl, prompt: []const u8) void
    pub fn setCompleter(self: *Repl, completer: CompleterFn) void
    pub fn readline(self: *Repl) !?[]const u8
    pub fn addHistory(self: *Repl, line: []const u8) !void
};

pub const CompleterFn = *const fn (
    allocator: std.mem.Allocator,
    line: []const u8,
    pos: usize,
) std.mem.Allocator.Error![]const []const u8;
```

**Example:**
```zig
var repl = try sailor.repl.Repl.init(allocator);
defer repl.deinit();

repl.setPrompt("> ");
repl.setCompleter(myCompleter);

while (try repl.readline()) |line| {
    defer allocator.free(line);
    if (std.mem.eql(u8, line, "exit")) break;
    try repl.addHistory(line);
    // Process command
}
```

### Key Bindings

- `Ctrl+C` - Cancel input
- `Ctrl+D` - EOF (exit REPL)
- `Up/Down` - Navigate history
- `Left/Right` - Move cursor
- `Home/End` - Jump to start/end
- `Backspace/Delete` - Delete characters
- `Tab` - Trigger completion

---

## progress

Progress indicators with bars, spinners, and multi-progress support.

### Types

```zig
pub const Bar = struct {
    pub fn init(allocator: std.mem.Allocator, total: u64) !Bar
    pub fn deinit(self: *Bar) void
    pub fn set(self: *Bar, current: u64) void
    pub fn inc(self: *Bar, delta: u64) void
    pub fn finish(self: *Bar) void
    pub fn render(self: Bar, writer: anytype) !void
};

pub const Spinner = struct {
    pub const Style = enum { dots, line, braille };

    pub fn init(allocator: std.mem.Allocator, style: Style) !Spinner
    pub fn deinit(self: *Spinner) void
    pub fn tick(self: *Spinner) void
    pub fn finish(self: *Spinner) void
    pub fn render(self: Spinner, writer: anytype) !void
};

pub const Multi = struct {
    pub fn init(allocator: std.mem.Allocator) !Multi
    pub fn deinit(self: *Multi) void
    pub fn addBar(self: *Multi, label: []const u8, total: u64) !*Bar
    pub fn render(self: Multi, writer: anytype) !void
};
```

**Example:**
```zig
var bar = try sailor.progress.Bar.init(allocator, 100);
defer bar.deinit();

for (0..100) |i| {
    bar.set(i);
    try bar.render(std.io.getStdOut().writer());
    std.time.sleep(10 * std.time.ns_per_ms);
}
bar.finish();
```

---

## fmt

Result formatting for tables, JSON, CSV, and plain text.

### Types

```zig
pub const Mode = enum { table, json, csv, plain };

pub const Table = struct {
    pub fn init(allocator: std.mem.Allocator) Table
    pub fn deinit(self: *Table) void
    pub fn setHeaders(self: *Table, headers: []const []const u8) !void
    pub fn addRow(self: *Table, row: []const []const u8) !void
    pub fn render(self: Table, writer: anytype) !void
};

pub const Json = struct {
    pub fn init(allocator: std.mem.Allocator, writer: anytype) Json
    pub fn deinit(self: *Json) void
    pub fn beginArray(self: *Json) !void
    pub fn endArray(self: *Json) !void
    pub fn beginObject(self: *Json) !void
    pub fn endObject(self: *Json) !void
    pub fn writeKey(self: *Json, key: []const u8) !void
    pub fn writeString(self: *Json, value: []const u8) !void
    pub fn writeInt(self: *Json, value: i64) !void
};
```

**Example:**
```zig
var table = sailor.fmt.Table.init(allocator);
defer table.deinit();

try table.setHeaders(&.{ "Name", "Age", "City" });
try table.addRow(&.{ "Alice", "30", "NYC" });
try table.addRow(&.{ "Bob", "25", "LA" });
try table.render(std.io.getStdOut().writer());
```

---

## tui

Full-screen TUI framework with layout engine and widgets.

### Core

#### Terminal

```zig
pub const Terminal = struct {
    pub fn init(allocator: std.mem.Allocator) !Terminal
    pub fn deinit(self: *Terminal) void
    pub fn run(self: *Terminal, render_fn: RenderFn) !void
    pub fn pollEvent(self: *Terminal, timeout_ms: u64) !?Event
    pub fn size(self: Terminal) Rect
};

pub const RenderFn = *const fn (frame: *Frame) anyerror!void;

pub const Event = union(enum) {
    key: term.Key,
    resize: Size,
};
```

#### Frame

```zig
pub const Frame = struct {
    pub fn size(self: Frame) Rect
    pub fn renderWidget(self: *Frame, widget: anytype, area: Rect) void
    pub fn setCursor(self: *Frame, x: u16, y: u16) void
};
```

#### Buffer

```zig
pub const Cell = struct {
    char: u21 = ' ',
    style: Style = .{},
};

pub const Buffer = struct {
    pub fn init(allocator: std.mem.Allocator, area: Rect) !Buffer
    pub fn deinit(self: *Buffer) void
    pub fn setChar(self: *Buffer, x: u16, y: u16, cell: Cell) void
    pub fn setString(self: *Buffer, x: u16, y: u16, str: []const u8, style: Style) void
    pub fn setSpan(self: *Buffer, x: u16, y: u16, span: Span) void
    pub fn fill(self: *Buffer, area: Rect, cell: Cell) void
    pub fn diff(old: Buffer, new: Buffer) ![]const u8
};
```

---

### Layout

```zig
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn area(self: Rect) u32
    pub fn inner(self: Rect, margin: u16) Rect
};

pub const Direction = enum { horizontal, vertical };

pub const Constraint = union(enum) {
    length: u16,
    percentage: u16,
    min: u16,
    max: u16,
    ratio: struct { num: u32, den: u32 },
};

pub const Layout = struct {
    pub fn init(allocator: std.mem.Allocator, direction: Direction, constraints: []const Constraint) Layout
    pub fn deinit(self: *Layout) void
    pub fn split(self: Layout, area: Rect) []Rect
};
```

**Example:**
```zig
const layout = Layout.init(allocator, .vertical, &.{
    .{ .percentage = 20 },  // Top 20%
    .{ .min = 3 },          // Middle (at least 3 rows)
    .{ .percentage = 20 },  // Bottom 20%
});
defer layout.deinit();

const chunks = layout.split(frame.size());
// chunks[0] = top area, chunks[1] = middle, chunks[2] = bottom
```

---

### Widgets

All widgets follow the same interface:

```zig
pub const Widget = struct {
    // Widget-specific fields

    pub fn render(self: @This(), buf: *Buffer, area: Rect) void
};
```

#### Block

Border and title container.

```zig
pub const Block = struct {
    title: ?Line = null,
    borders: Borders = .{},
    border_style: Style = .{},

    pub fn init() Block
    pub fn setTitle(self: *Block, title: Line) *Block
    pub fn setBorders(self: *Block, borders: Borders) *Block
    pub fn inner(self: Block, area: Rect) Rect
    pub fn render(self: Block, buf: *Buffer, area: Rect) void
};

pub const Borders = struct {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,

    pub const all = Borders{ .top = true, .bottom = true, .left = true, .right = true };
    pub const none = Borders{};
};
```

#### Paragraph

Text rendering with wrapping.

```zig
pub const Paragraph = struct {
    text: Line,
    block: ?Block = null,
    wrap: bool = true,

    pub fn init(text: Line) Paragraph
    pub fn setBlock(self: *Paragraph, block: Block) *Paragraph
    pub fn setWrap(self: *Paragraph, wrap: bool) *Paragraph
    pub fn render(self: Paragraph, buf: *Buffer, area: Rect) void
};
```

#### List

Scrollable item list.

```zig
pub const List = struct {
    items: []const Line,
    selected: ?usize = null,
    block: ?Block = null,
    highlight_style: Style = .{},

    pub fn init(items: []const Line) List
    pub fn setSelected(self: *List, idx: ?usize) *List
    pub fn render(self: List, buf: *Buffer, area: Rect) void
};
```

#### Table

Tabular data with headers.

```zig
pub const Table = struct {
    headers: []const []const u8,
    rows: []const []const []const u8,
    widths: []const u16,
    block: ?Block = null,

    pub fn init(allocator: std.mem.Allocator, headers: []const []const u8) !Table
    pub fn deinit(self: *Table) void
    pub fn setRows(self: *Table, rows: []const []const []const u8) *Table
    pub fn render(self: Table, buf: *Buffer, area: Rect) void
};
```

#### Input

Single-line text input.

```zig
pub const Input = struct {
    value: []const u8,
    cursor: usize = 0,
    block: ?Block = null,

    pub fn init(value: []const u8) Input
    pub fn render(self: Input, buf: *Buffer, area: Rect) void
};
```

#### Tabs

Tab navigation bar.

```zig
pub const Tabs = struct {
    titles: []const []const u8,
    selected: usize = 0,
    block: ?Block = null,

    pub fn init(titles: []const []const u8) Tabs
    pub fn render(self: Tabs, buf: *Buffer, area: Rect) void
};
```

#### StatusBar

Bottom status bar with sections.

```zig
pub const StatusBar = struct {
    left: ?Line = null,
    center: ?Line = null,
    right: ?Line = null,
    style: Style = .{},

    pub fn init() StatusBar
    pub fn render(self: StatusBar, buf: *Buffer, area: Rect) void
};
```

#### Gauge

Progress indicator.

```zig
pub const Gauge = struct {
    ratio: f64,
    label: ?[]const u8 = null,
    block: ?Block = null,

    pub fn init(ratio: f64) Gauge
    pub fn render(self: Gauge, buf: *Buffer, area: Rect) void
};
```

---

### Advanced Widgets

#### Tree

Hierarchical tree view.

```zig
pub const Tree = struct {
    pub const Node = struct {
        label: []const u8,
        children: []Node,
        expanded: bool = true,
    };

    root: []const Node,
    selected: ?usize = null,
    block: ?Block = null,

    pub fn init(root: []const Node) Tree
    pub fn render(self: Tree, buf: *Buffer, area: Rect) void
};
```

#### TextArea

Multi-line text editor.

```zig
pub const TextArea = struct {
    lines: []const []const u8,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    scroll: usize = 0,
    block: ?Block = null,
    show_line_numbers: bool = false,

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !TextArea
    pub fn deinit(self: *TextArea) void
    pub fn render(self: TextArea, buf: *Buffer, area: Rect) void
};
```

#### Charts

```zig
pub const Sparkline = struct {
    data: []const u64,
    block: ?Block = null,

    pub fn init(data: []const u64) Sparkline
    pub fn render(self: Sparkline, buf: *Buffer, area: Rect) void
};

pub const BarChart = struct {
    data: []const u64,
    labels: []const []const u8,
    max_value: ?u64 = null,
    block: ?Block = null,

    pub fn init(data: []const u64, labels: []const []const u8) BarChart
    pub fn render(self: BarChart, buf: *Buffer, area: Rect) void
};

pub const LineChart = struct {
    pub const Dataset = struct {
        label: []const u8,
        data: []const f64,
        style: Style,
    };

    datasets: []const Dataset,
    x_labels: []const []const u8,
    y_min: f64,
    y_max: f64,
    block: ?Block = null,

    pub fn init(datasets: []const Dataset) LineChart
    pub fn render(self: LineChart, buf: *Buffer, area: Rect) void
};
```

#### Overlays

```zig
pub const Dialog = struct {
    title: []const u8,
    message: []const u8,
    buttons: []const []const u8,
    selected: usize = 0,

    pub fn init(allocator: std.mem.Allocator, title: []const u8, message: []const u8) !Dialog
    pub fn deinit(self: *Dialog) void
    pub fn render(self: Dialog, buf: *Buffer, area: Rect) void
};

pub const Popup = struct {
    content: Line,
    border_style: Style = .{},

    pub fn init(content: Line) Popup
    pub fn render(self: Popup, buf: *Buffer, area: Rect) void
};

pub const Notification = struct {
    pub const Level = enum { info, success, warning, error };

    message: []const u8,
    level: Level = .info,
    duration_ms: u64 = 3000,

    pub fn init(message: []const u8) Notification
    pub fn render(self: Notification, buf: *Buffer, area: Rect) void
};
```

#### Network & Async Widgets (v1.8.0)

```zig
pub const HttpClient = struct {
    pub const RequestState = enum { idle, connecting, sending, receiving, completed, failed };

    allocator: std.mem.Allocator,
    state: RequestState = .idle,
    url: ?[]const u8 = null,
    progress: DownloadProgress = .{},
    response_preview: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    block: ?Block = null,

    pub fn init(allocator: std.mem.Allocator) HttpClient
    pub fn deinit(self: *HttpClient) void
    pub fn updateProgress(self: *HttpClient, bytes_downloaded: u64, total_bytes: u64, elapsed_ms: u64) void
    pub fn complete(self: *HttpClient, response: []const u8) !void
    pub fn fail(self: *HttpClient, error_msg: []const u8) !void
    pub fn render(self: HttpClient, buf: *Buffer, area: Rect) void
};

pub const WebSocket = struct {
    pub const ConnectionState = enum { disconnected, connecting, connected, reconnecting, failed };
    pub const MessageDirection = enum { incoming, outgoing };
    pub const TimestampFormat = enum { time_only, datetime, unix_ms, relative };

    allocator: std.mem.Allocator,
    state: ConnectionState = .disconnected,
    messages: std.ArrayListUnmanaged(Message) = .{},
    max_messages: usize = 1000,
    scroll_offset: usize = 0,
    auto_scroll: bool = true,
    timestamp_format: TimestampFormat = .time_only,
    block: ?Block = null,

    pub fn init(allocator: std.mem.Allocator) !WebSocket
    pub fn deinit(self: *WebSocket) void
    pub fn pushMessage(self: *WebSocket, content: []const u8, direction: MessageDirection) !void
    pub fn scrollUp(self: *WebSocket, lines: usize) void
    pub fn scrollDown(self: *WebSocket, lines: usize) void
    pub fn scrollToBottom(self: *WebSocket) void
    pub fn render(self: WebSocket, buf: *Buffer, area: Rect) void
};

pub const TaskRunner = struct {
    pub const DisplayFormat = enum { compact, normal, detailed };

    allocator: std.mem.Allocator,
    tasks: std.ArrayListUnmanaged(TaskInfo) = .{},
    selected_index: ?usize = null,
    display_format: DisplayFormat = .normal,
    use_unicode: bool = true,
    block: ?Block = null,

    pub fn init(allocator: std.mem.Allocator) !TaskRunner
    pub fn deinit(self: *TaskRunner) void
    pub fn addTask(self: *TaskRunner, handle: TaskHandle, name: []const u8) !void
    pub fn updateTaskState(self: *TaskRunner, handle: TaskHandle, state: TaskState, progress: f32) void
    pub fn updateTaskError(self: *TaskRunner, handle: TaskHandle, error_msg: []const u8) !void
    pub fn selectNext(self: *TaskRunner) void
    pub fn selectPrevious(self: *TaskRunner) void
    pub fn render(self: TaskRunner, buf: *Buffer, area: Rect) void
};

pub const LogViewer = struct {
    pub const LogLevel = enum { trace, debug, info, warn, err, fatal };

    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(LogEntry) = .{},
    max_entries: usize = 10000,
    scroll_offset: usize = 0,
    auto_scroll: bool = true,
    min_level: LogLevel = .trace,
    source_filter: ?[]const u8 = null,
    search_term: ?[]const u8 = null,
    block: ?Block = null,

    pub fn init(allocator: std.mem.Allocator) !LogViewer
    pub fn deinit(self: *LogViewer) void
    pub fn pushLog(self: *LogViewer, level: LogLevel, message: []const u8, source: []const u8) !void
    pub fn pushLogRaw(self: *LogViewer, raw_line: []const u8) !void
    pub fn clear(self: *LogViewer) void
    pub fn scrollUp(self: *LogViewer, lines: usize) void
    pub fn scrollDown(self: *LogViewer, lines: usize) void
    pub fn setMinLevel(self: *LogViewer, level: LogLevel) *LogViewer
    pub fn setSourceFilter(self: *LogViewer, source: ?[]const u8) *LogViewer
    pub fn setSearchTerm(self: *LogViewer, term: ?[]const u8) *LogViewer
    pub fn render(self: LogViewer, buf: *Buffer, area: Rect) void
};
```

---

## Complete Example

```zig
const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments
    var parser = sailor.arg.Parser.init(allocator);
    defer parser.deinit();
    parser.addFlag(.{ .long = "name", .type = .string, .default = "World" });
    const args = try parser.parse();

    // Run TUI
    var terminal = try sailor.tui.Terminal.init(allocator);
    defer terminal.deinit();

    const ctx = struct {
        name: []const u8,

        pub fn render(self: @This(), frame: *sailor.tui.Frame) !void {
            const area = frame.size();

            const block = sailor.tui.widgets.Block.init()
                .setTitle(sailor.tui.Line.fromString("Hello"))
                .setBorders(sailor.tui.Borders.all);

            var text = try std.fmt.allocPrint(
                frame.allocator,
                "Hello, {s}!",
                .{self.name},
            );
            defer frame.allocator.free(text);

            const para = sailor.tui.widgets.Paragraph.init(
                sailor.tui.Line.fromString(text)
            ).setBlock(block);

            frame.renderWidget(para, area);
        }
    }{ .name = args.flag("name") orelse "World" };

    try terminal.run(ctx.render);
}
```
