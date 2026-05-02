//! Benchmark stability tests — verify variance < 5%
//!
//! These tests ensure that our performance benchmarks produce consistent results,
//! which is critical for CI regression detection (scripts/check_benchmarks.zig).
//! If variance is too high, small regressions become indistinguishable from noise.

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Gauge = sailor.tui.widgets.Gauge;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Span = sailor.tui.Span;
const Line = sailor.tui.Line;

const RUNS = 5; // Run each benchmark 5 times
const ITERATIONS_PER_RUN = 1000; // 1000 iterations per run (lower than production for test speed)
const MAX_VARIANCE = 0.05; // 5% coefficient of variation (CV = stddev / mean)

/// Statistics for benchmark runs
const Stats = struct {
    mean: f64,
    stddev: f64,
    cv: f64, // Coefficient of variation (stddev / mean)
    min: f64,
    max: f64,

    fn fromSamples(samples: []const f64) Stats {
        var sum: f64 = 0.0;
        var min_val = samples[0];
        var max_val = samples[0];

        for (samples) |sample| {
            sum += sample;
            if (sample < min_val) min_val = sample;
            if (sample > max_val) max_val = sample;
        }

        const mean = sum / @as(f64, @floatFromInt(samples.len));

        var variance_sum: f64 = 0.0;
        for (samples) |sample| {
            const diff = sample - mean;
            variance_sum += diff * diff;
        }

        const variance = variance_sum / @as(f64, @floatFromInt(samples.len));
        const stddev = @sqrt(variance);
        const cv = if (mean != 0.0) stddev / mean else 0.0;

        return .{
            .mean = mean,
            .stddev = stddev,
            .cv = cv,
            .min = min_val,
            .max = max_val,
        };
    }
};

/// Run a benchmark function multiple times and collect timing samples
fn benchmarkStability(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime func: fn (std.mem.Allocator) anyerror!void,
) !Stats {
    var samples: [RUNS]f64 = undefined;

    for (&samples) |*sample| {
        const start = std.time.nanoTimestamp();

        var i: usize = 0;
        while (i < ITERATIONS_PER_RUN) : (i += 1) {
            try func(allocator);
        }

        const end = std.time.nanoTimestamp();
        const elapsed_ns = @as(f64, @floatFromInt(end - start));
        const per_op_ns = elapsed_ns / @as(f64, @floatFromInt(ITERATIONS_PER_RUN));
        sample.* = per_op_ns;
    }

    const stats = Stats.fromSamples(&samples);

    // Debug output (only shown when test fails)
    std.debug.print("\n{s}:\n", .{name});
    std.debug.print("  Mean: {d:.2} ns/op\n", .{stats.mean});
    std.debug.print("  StdDev: {d:.2} ns\n", .{stats.stddev});
    std.debug.print("  CV: {d:.2}% (max {d:.0}%)\n", .{ stats.cv * 100.0, MAX_VARIANCE * 100.0 });
    std.debug.print("  Range: {d:.2} - {d:.2} ns/op\n", .{ stats.min, stats.max });

    return stats;
}

// Benchmark functions (same as examples/benchmark.zig but simplified for testing)

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
        Span.raw(" paragraph."),
    };
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};

    const para = Paragraph{
        .lines = &lines,
        .block = Block{
            .title = "Paragraph",
            .borders = .all,
        },
    };

    para.render(&buffer, Rect{ .x = 0, .y = 0, .width = 60, .height = 10 });
}

fn benchListRender(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const items = [_][]const u8{ "Item 1", "Item 2", "Item 3" };
    const list = List{
        .items = &items,
        .selected = 1,
        .block = Block{
            .title = "List",
            .borders = .all,
        },
    };

    list.render(&buffer, Rect{ .x = 0, .y = 0, .width = 30, .height = 10 });
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

// Tests

test "benchmark stability: Buffer.init variance < 5%" {
    const stats = try benchmarkStability(testing.allocator, "Buffer.init", benchBufferCreate);
    try testing.expect(stats.cv < MAX_VARIANCE);
}

test "benchmark stability: Buffer.fill variance < 5%" {
    const stats = try benchmarkStability(testing.allocator, "Buffer.fill", benchBufferFill);
    try testing.expect(stats.cv < MAX_VARIANCE);
}

test "benchmark stability: Buffer.diff variance < 5%" {
    const stats = try benchmarkStability(testing.allocator, "Buffer.diff", benchBufferDiff);
    try testing.expect(stats.cv < MAX_VARIANCE);
}

test "benchmark stability: Block.render variance < 5%" {
    const stats = try benchmarkStability(testing.allocator, "Block.render", benchBlockRender);
    try testing.expect(stats.cv < MAX_VARIANCE);
}

test "benchmark stability: Paragraph.render variance < 5%" {
    const stats = try benchmarkStability(testing.allocator, "Paragraph.render", benchParagraphRender);
    try testing.expect(stats.cv < MAX_VARIANCE);
}

test "benchmark stability: List.render variance < 5%" {
    const stats = try benchmarkStability(testing.allocator, "List.render", benchListRender);
    try testing.expect(stats.cv < MAX_VARIANCE);
}

test "benchmark stability: Gauge.render variance < 5%" {
    const stats = try benchmarkStability(testing.allocator, "Gauge.render", benchGaugeRender);
    try testing.expect(stats.cv < MAX_VARIANCE);
}

test "Stats.fromSamples calculates correct statistics" {
    const samples = [_]f64{ 10.0, 12.0, 11.0, 13.0, 9.0 };
    const stats = Stats.fromSamples(&samples);

    // Mean = (10 + 12 + 11 + 13 + 9) / 5 = 55 / 5 = 11.0
    try testing.expectApproxEqAbs(11.0, stats.mean, 0.01);

    // Variance = [(10-11)^2 + (12-11)^2 + (11-11)^2 + (13-11)^2 + (9-11)^2] / 5
    //          = [1 + 1 + 0 + 4 + 4] / 5 = 10 / 5 = 2.0
    // StdDev = sqrt(2.0) ≈ 1.414
    try testing.expectApproxEqAbs(1.414, stats.stddev, 0.01);

    // CV = stddev / mean ≈ 1.414 / 11.0 ≈ 0.1286 (12.86%)
    try testing.expectApproxEqAbs(0.1286, stats.cv, 0.01);

    // Min/Max
    try testing.expectApproxEqAbs(9.0, stats.min, 0.01);
    try testing.expectApproxEqAbs(13.0, stats.max, 0.01);
}
