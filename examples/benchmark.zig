//! Benchmark runner for sailor library performance tests
//!
//! Usage: zig build benchmark

const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Table = sailor.tui.widgets.Table;
const Column = sailor.tui.widgets.Column;
const Row = sailor.tui.widgets.Row;
const Gauge = sailor.tui.widgets.Gauge;
const Sparkline = sailor.tui.widgets.Sparkline;
const List = sailor.tui.widgets.List;
const Input = sailor.tui.widgets.Input;
const Tabs = sailor.tui.widgets.Tabs;
const StatusBar = sailor.tui.widgets.StatusBar;
// const Tree = sailor.tui.widgets.Tree; // Skipped: BoundedArray error
// const TreeNode = sailor.tui.widgets.TreeNode;
// const TextArea = sailor.tui.widgets.TextArea; // Skipped: error set discard issue
// const BarChart = sailor.tui.widgets.BarChart; // Skipped: setCell error
// const LineChart = sailor.tui.widgets.LineChart; // Skipped: setCell error
// const Calendar = sailor.tui.widgets.Calendar; // Skipped: API mismatch
// const Menu = sailor.tui.widgets.Menu; // Skipped for now
// const Dialog = sailor.tui.widgets.Dialog; // Skipped for now
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Line = sailor.tui.Line;
const Span = sailor.tui.Span;

const ITERATIONS = 10000;

fn benchmark(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime func: fn (std.mem.Allocator) anyerror!void,
) !void {
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < ITERATIONS) : (i += 1) {
        try func(allocator);
    }

    const end = std.time.nanoTimestamp();
    const elapsed = @as(f64, @floatFromInt(end - start)) / 1_000_000.0; // Convert to ms
    const per_op = elapsed / @as(f64, @floatFromInt(ITERATIONS));

    std.debug.print("{s}: {d:.2}ms total, {d:.4}ms per op ({d:.0} ops/sec)\n", .{
        name,
        elapsed,
        per_op,
        1000.0 / per_op,
    });
}

fn benchBufferCreate(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();
}

fn benchBufferFill(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    buffer.fill(area, 'x', .{ .fg = .red });
}

fn benchBufferDiff(allocator: std.mem.Allocator) !void {
    var buf1 = try Buffer.init(allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 80, 24);
    defer buf2.deinit();

    buf1.setString(10, 5, "Hello World", .{ .fg = .blue });
    buf2.setString(10, 5, "Hello Sailor!", .{ .fg = .green });

    const diff_ops = try sailor.tui.buffer.diff(allocator, buf1, buf2);
    defer allocator.free(diff_ops);
}

fn benchBlockRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const block = Block{
        .title = "Test Block",
        .borders = .all,
        .border_style = .{ .fg = .cyan },
    };

    block.render(&buffer, Rect{ .x = 0, .y = 0, .width = 40, .height = 10 });
}

fn benchParagraphRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const spans = [_]Span{
        Span.raw("This is a "),
        Span.styled("test", .{ .fg = .red, .bold = true }),
        Span.raw(" paragraph with "),
        Span.styled("multiple", .{ .fg = .blue }),
        Span.raw(" styled spans."),
    };
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line} ** 5;

    const para = Paragraph{
        .lines = &lines,
        .block = Block{
            .title = "Paragraph",
            .borders = .all,
        },
    };

    para.render(&buffer, Rect{ .x = 0, .y = 0, .width = 60, .height = 10 });
}

fn benchTableRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const columns = [_]Column{
        .{ .title = "Column 1", .width = .{ .fixed = 20 } },
        .{ .title = "Column 2", .width = .{ .fixed = 20 } },
    };

    const row1 = [_][]const u8{ "Row 1", "Data 1" };
    const row2 = [_][]const u8{ "Row 2", "Data 2" };
    const row3 = [_][]const u8{ "Row 3", "Data 3" };

    const rows = [_]Row{ &row1, &row2, &row3 };

    const table = Table{
        .columns = &columns,
        .rows = &rows,
        .block = Block{
            .title = "Table",
            .borders = .all,
        },
    };

    table.render(&buffer, Rect{ .x = 0, .y = 0, .width = 50, .height = 10 });
}

fn benchGaugeRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const gauge = Gauge{
        .ratio = 0.65,
        .filled_style = .{ .fg = .green },
        .block = Block{
            .title = "Progress",
            .borders = .all,
        },
    };

    gauge.render(&buffer, Rect{ .x = 0, .y = 0, .width = 40, .height = 3 });
}

fn benchSparklineRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const data = [_]u64{ 10, 20, 15, 30, 25, 40, 35, 50, 45, 55 };
    const sparkline = Sparkline{
        .data = &data,
        .style = .{ .fg = .cyan },
        .block = Block{
            .title = "Sparkline",
            .borders = .all,
        },
    };

    sparkline.render(&buffer, Rect{ .x = 0, .y = 0, .width = 40, .height = 5 });
}

fn benchListRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const items = [_][]const u8{ "Item 1", "Item 2", "Item 3", "Item 4", "Item 5" };
    const list = List{
        .items = &items,
        .selected = 2,
        .block = Block{
            .title = "List",
            .borders = .all,
        },
    };

    list.render(&buffer, Rect{ .x = 0, .y = 0, .width = 30, .height = 10 });
}

fn benchInputRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    var input = Input{
        .value = "Test input value",
        .cursor = 5,
        .block = Block{
            .title = "Input",
            .borders = .all,
        },
    };

    input.render(&buffer, Rect{ .x = 0, .y = 0, .width = 40, .height = 3 });
}

fn benchTabsRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const titles = [_][]const u8{ "Tab 1", "Tab 2", "Tab 3" };
    const tabs = Tabs{
        .titles = &titles,
        .selected = 1,
        .block = Block{
            .title = "Tabs",
            .borders = .all,
        },
    };

    tabs.render(&buffer, Rect{ .x = 0, .y = 0, .width = 50, .height = 3 });
}

fn benchStatusBarRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const left_spans = [_]Span{Span.raw("Ready")};
    const center_spans = [_]Span{Span.raw("file.txt")};
    const right_spans = [_]Span{Span.raw("Ln 10, Col 5")};
    const statusbar = StatusBar{
        .left = &left_spans,
        .center = &center_spans,
        .right = &right_spans,
        .style = .{ .bg = .blue },
    };

    statusbar.render(&buffer, Rect{ .x = 0, .y = 0, .width = 80, .height = 1 });
}

// fn benchTreeRender(allocator: std.mem.Allocator) !void {
//     var buffer = try Buffer.init(allocator, 80, 24);
//     defer buffer.deinit();
//     // Skipped: BoundedArray compilation error in tree.zig
// }

// fn benchTextAreaRender - Skipped: error set discard issue

// Skipped: BarChart, LineChart, Calendar, Menu, Dialog (setCell error or API mismatches)

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\nSailor TUI Framework - Performance Benchmarks\n", .{});
    std.debug.print("============================================\n\n", .{});
    std.debug.print("Running {d} iterations per benchmark...\n\n", .{ITERATIONS});

    // Core Infrastructure
    std.debug.print("=== Core Infrastructure ===\n", .{});
    try benchmark(allocator, "Buffer.init (80x24)", benchBufferCreate);
    try benchmark(allocator, "Buffer.fill", benchBufferFill);
    try benchmark(allocator, "Buffer.diff", benchBufferDiff);

    // Basic Widgets
    std.debug.print("\n=== Basic Widgets ===\n", .{});
    try benchmark(allocator, "Block.render", benchBlockRender);
    try benchmark(allocator, "Paragraph.render", benchParagraphRender);
    try benchmark(allocator, "List.render", benchListRender);
    try benchmark(allocator, "Input.render", benchInputRender);
    try benchmark(allocator, "Tabs.render", benchTabsRender);
    try benchmark(allocator, "StatusBar.render", benchStatusBarRender);
    try benchmark(allocator, "Gauge.render", benchGaugeRender);

    // Advanced Widgets
    std.debug.print("\n=== Advanced Widgets ===\n", .{});
    try benchmark(allocator, "Table.render", benchTableRender);
    // Skipped: Tree, TextArea, Menu, Dialog (source file issues)

    // Chart Widgets
    std.debug.print("\n=== Chart Widgets ===\n", .{});
    try benchmark(allocator, "Sparkline.render", benchSparklineRender);
    // try benchmark(allocator, "BarChart.render", benchBarChartRender); // Skipped: setCell
    // try benchmark(allocator, "LineChart.render", benchLineChartRender); // Skipped: setCell

    std.debug.print("\n✅ Core widget benchmarks complete!\n", .{});
    std.debug.print("📊 Total widgets benchmarked: 12 core widgets\n", .{});
    std.debug.print("⚠️  Note: Advanced widgets skipped due to source file compilation issues\n", .{});
    std.debug.print("         (Tree/TextArea/BarChart/LineChart/Calendar - to be fixed in separate session)\n", .{});
}
