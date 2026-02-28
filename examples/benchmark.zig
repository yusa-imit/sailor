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

    const area = Rect.new(0, 0, 80, 24);
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

    block.render(&buffer, Rect.new(0, 0, 40, 10));
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

    para.render(&buffer, Rect.new(0, 0, 60, 10));
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

    table.render(&buffer, Rect.new(0, 0, 50, 10));
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

    gauge.render(&buffer, Rect.new(0, 0, 40, 3));
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

    sparkline.render(&buffer, Rect.new(0, 0, 40, 5));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\nSailor TUI Framework - Performance Benchmarks\n", .{});
    std.debug.print("============================================\n\n", .{});
    std.debug.print("Running {d} iterations per benchmark...\n\n", .{ITERATIONS});

    try benchmark(allocator, "Buffer.init (80x24)", benchBufferCreate);
    try benchmark(allocator, "Buffer.fill", benchBufferFill);
    try benchmark(allocator, "Buffer.diff", benchBufferDiff);
    try benchmark(allocator, "Block.render", benchBlockRender);
    try benchmark(allocator, "Paragraph.render", benchParagraphRender);
    try benchmark(allocator, "Table.render", benchTableRender);
    try benchmark(allocator, "Gauge.render", benchGaugeRender);
    try benchmark(allocator, "Sparkline.render", benchSparklineRender);

    std.debug.print("\n✅ Benchmarks complete!\n", .{});
}
