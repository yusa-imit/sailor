//! Performance benchmarking utilities for sailor library
//!
//! This module provides benchmarking functions to measure performance
//! of critical operations across sailor TUI framework.

const std = @import("std");

/// Benchmark result for a single operation
pub const BenchResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    avg_ns: u64,
    ops_per_sec: f64,

    pub fn format(
        self: BenchResult,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print(
            "{s:50} | {d:>10} iters | {d:>12.2} ns/op | {d:>15.0} ops/sec",
            .{ self.name, self.iterations, @as(f64, @floatFromInt(self.avg_ns)), self.ops_per_sec },
        );
    }
};

/// Run all benchmarks
pub fn runAll(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("\n");
    try writer.writeAll("=======================================================================\n");
    try writer.writeAll("                  SAILOR PERFORMANCE BENCHMARKS\n");
    try writer.writeAll("=======================================================================\n");

    try benchBuffer(allocator, writer);

    try writer.writeAll("\n");
    try writer.writeAll("=======================================================================\n");
    try writer.writeAll("                       BENCHMARKS COMPLETE\n");
    try writer.writeAll("=======================================================================\n");
    try writer.writeAll("\n");
}

/// Benchmark buffer operations
pub fn benchBuffer(allocator: std.mem.Allocator, writer: anytype) !void {
    const buffer = @import("tui/buffer.zig");
    const Buffer = buffer.Buffer;
    const Style = @import("tui/style.zig").Style;

    try writer.writeAll("\n=== Buffer Operations ===\n");

    // Benchmark: Create and destroy buffer
    {
        const iterations = 10000;
        var timer = std.time.Timer.start() catch unreachable;
        const start = timer.read();

        for (0..iterations) |_| {
            var buf = try Buffer.init(allocator, 80, 24);
            buf.deinit();
        }

        const end = timer.read();
        const total_ns = end - start;
        const avg_ns = total_ns / iterations;
        const ops_per_sec = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));

        const result = BenchResult{
            .name = "Buffer init+deinit (80x24 cells)",
            .iterations = iterations,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .ops_per_sec = ops_per_sec,
        };
        try writer.print("{s:50} | {d:>10} iters | {d:>12.2} ns/op | {d:>15.0} ops/sec\n", .{
            result.name,
            result.iterations,
            @as(f64, @floatFromInt(result.avg_ns)),
            result.ops_per_sec,
        });
    }

    // Benchmark: Set single character
    {
        var buf = try Buffer.init(allocator, 80, 24);
        defer buf.deinit();

        const iterations = 100000;
        var timer = std.time.Timer.start() catch unreachable;
        const start = timer.read();

        for (0..iterations) |i| {
            const x: u16 = @intCast(i % 80);
            const y: u16 = @intCast((i / 80) % 24);
            buf.setChar(x, y, 'X', Style{});
        }

        const end = timer.read();
        const total_ns = end - start;
        const avg_ns = total_ns / iterations;
        const ops_per_sec = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));

        const result = BenchResult{
            .name = "Buffer setChar (single character)",
            .iterations = iterations,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .ops_per_sec = ops_per_sec,
        };
        try writer.print("{s:50} | {d:>10} iters | {d:>12.2} ns/op | {d:>15.0} ops/sec\n", .{
            result.name,
            result.iterations,
            @as(f64, @floatFromInt(result.avg_ns)),
            result.ops_per_sec,
        });
    }

    // Benchmark: Set string
    {
        var buf = try Buffer.init(allocator, 80, 24);
        defer buf.deinit();

        const iterations = 50000;
        var timer = std.time.Timer.start() catch unreachable;
        const start = timer.read();

        for (0..iterations) |i| {
            const y: u16 = @intCast(i % 24);
            buf.setString(10, y, "Hello Sailor!", Style{});
        }

        const end = timer.read();
        const total_ns = end - start;
        const avg_ns = total_ns / iterations;
        const ops_per_sec = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));

        const result = BenchResult{
            .name = "Buffer setString (13 characters)",
            .iterations = iterations,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .ops_per_sec = ops_per_sec,
        };
        try writer.print("{s:50} | {d:>10} iters | {d:>12.2} ns/op | {d:>15.0} ops/sec\n", .{
            result.name,
            result.iterations,
            @as(f64, @floatFromInt(result.avg_ns)),
            result.ops_per_sec,
        });
    }

    // Benchmark: Clear buffer
    {
        var buf = try Buffer.init(allocator, 80, 24);
        defer buf.deinit();

        const iterations = 10000;
        var timer = std.time.Timer.start() catch unreachable;
        const start = timer.read();

        for (0..iterations) |_| {
            buf.clear();
        }

        const end = timer.read();
        const total_ns = end - start;
        const avg_ns = total_ns / iterations;
        const ops_per_sec = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));

        const result = BenchResult{
            .name = "Buffer clear (80x24 cells)",
            .iterations = iterations,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .ops_per_sec = ops_per_sec,
        };
        try writer.print("{s:50} | {d:>10} iters | {d:>12.2} ns/op | {d:>15.0} ops/sec\n", .{
            result.name,
            result.iterations,
            @as(f64, @floatFromInt(result.avg_ns)),
            result.ops_per_sec,
        });
    }

    // Benchmark: Diff computation
    {
        var buf1 = try Buffer.init(allocator, 80, 24);
        defer buf1.deinit();
        var buf2 = try Buffer.init(allocator, 80, 24);
        defer buf2.deinit();

        buf2.setString(10, 10, "Changed text!", Style{});

        const iterations = 1000;
        var timer = std.time.Timer.start() catch unreachable;
        const start = timer.read();

        for (0..iterations) |_| {
            const diff_ops = try buffer.diff(allocator, buf1, buf2);
            defer allocator.free(diff_ops);
        }

        const end = timer.read();
        const total_ns = end - start;
        const avg_ns = total_ns / iterations;
        const ops_per_sec = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));

        const result = BenchResult{
            .name = "Buffer diff (80x24 cells, with changes)",
            .iterations = iterations,
            .total_ns = total_ns,
            .avg_ns = avg_ns,
            .ops_per_sec = ops_per_sec,
        };
        try writer.print("{s:50} | {d:>10} iters | {d:>12.2} ns/op | {d:>15.0} ops/sec\n", .{
            result.name,
            result.iterations,
            @as(f64, @floatFromInt(result.avg_ns)),
            result.ops_per_sec,
        });
    }
}

test "bench result creation" {
    const result = BenchResult{
        .name = "Test Operation",
        .iterations = 10000,
        .total_ns = 1_000_000,
        .avg_ns = 100,
        .ops_per_sec = 10_000_000.0,
    };

    try std.testing.expectEqual(@as(usize, 10000), result.iterations);
    try std.testing.expectEqual(@as(u64, 100), result.avg_ns);
}

test "benchBuffer runs without error" {
    const allocator = std.testing.allocator;
    var buffer: [8192]u8 = undefined;
    var buf = std.io.fixedBufferStream(&buffer);

    try benchBuffer(allocator, buf.writer());

    // Verify benchmark completed (no crash)
}

test "runAll runs without error" {
    const allocator = std.testing.allocator;
    var buffer: [8192]u8 = undefined;
    var buf = std.io.fixedBufferStream(&buffer);

    try runAll(allocator, buf.writer());

    // Verify benchmark suite completed (no crash)
}
