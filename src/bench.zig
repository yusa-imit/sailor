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

test "bench result creation and field validation" {
    const result = BenchResult{
        .name = "Test Operation",
        .iterations = 10000,
        .total_ns = 1_000_000,
        .avg_ns = 100,
        .ops_per_sec = 10_000_000.0,
    };

    try std.testing.expectEqual(@as(usize, 10000), result.iterations);
    try std.testing.expectEqual(@as(u64, 100), result.avg_ns);
    try std.testing.expectEqual(@as(u64, 1_000_000), result.total_ns);
    try std.testing.expectEqualStrings("Test Operation", result.name);
}

test "bench result avg_ns calculation is correct" {
    const iterations: usize = 5000;
    const total_ns: u64 = 500_000;
    const avg_ns = total_ns / iterations;

    try std.testing.expectEqual(@as(u64, 100), avg_ns);
}

test "bench result ops_per_sec calculation is correct" {
    const avg_ns: u64 = 100;
    const ops_per_sec = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns));

    try std.testing.expectApproxEqRel(@as(f64, 10_000_000.0), ops_per_sec, 0.001);
}

test "bench result format includes all fields" {
    const result = BenchResult{
        .name = "Test Bench",
        .iterations = 5000,
        .total_ns = 500_000,
        .avg_ns = 100,
        .ops_per_sec = 10_000_000.0,
    };

    var output: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try result.format("", .{}, stream.writer());
    const formatted = stream.getWritten();

    try expectStringContains(formatted, "Test Bench");
    try expectStringContains(formatted, "5000");
    try expectStringContains(formatted, "100.00");
    try expectStringContains(formatted, "10000000");
}

test "bench result format has proper column spacing" {
    const result = BenchResult{
        .name = "MyBench",
        .iterations = 1000,
        .total_ns = 100_000,
        .avg_ns = 100,
        .ops_per_sec = 10_000_000.0,
    };

    var output: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try result.format("", .{}, stream.writer());
    const formatted = stream.getWritten();

    // Verify columns are present: name | iters | ns/op | ops/sec
    try std.testing.expect(std.mem.indexOf(u8, formatted, "iters") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "ns/op") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "ops/sec") != null);
}

test "benchBuffer output contains all benchmark names" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try benchBuffer(allocator, stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "Buffer init+deinit (80x24 cells)");
    try expectStringContains(output, "Buffer setChar (single character)");
    try expectStringContains(output, "Buffer setString (13 characters)");
    try expectStringContains(output, "Buffer clear (80x24 cells)");
    try expectStringContains(output, "Buffer diff (80x24 cells, with changes)");
}

test "benchBuffer output contains numeric values and columns" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try benchBuffer(allocator, stream.writer());
    const output = stream.getWritten();

    // Verify output has iteration counts
    try std.testing.expect(std.mem.indexOf(u8, output, "iters") != null);

    // Verify output has ns/op column
    try std.testing.expect(std.mem.indexOf(u8, output, "ns/op") != null);

    // Verify output has ops/sec column
    try std.testing.expect(std.mem.indexOf(u8, output, "ops/sec") != null);

    // Verify output has section header
    try std.testing.expect(std.mem.indexOf(u8, output, "=== Buffer Operations ===") != null);
}

test "benchBuffer completes without error" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    // Should not raise error
    try benchBuffer(allocator, stream.writer());

    // Verify output is not empty
    const output = stream.getWritten();
    try std.testing.expect(output.len > 0);
}

test "runAll output contains header" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try runAll(allocator, stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "SAILOR PERFORMANCE BENCHMARKS");
}

test "runAll output contains footer" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try runAll(allocator, stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "BENCHMARKS COMPLETE");
}

test "runAll output contains buffer operations section" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try runAll(allocator, stream.writer());
    const output = stream.getWritten();

    try expectStringContains(output, "=== Buffer Operations ===");
}

test "runAll output contains all benchmark results" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try runAll(allocator, stream.writer());
    const output = stream.getWritten();

    // Verify output contains benchmark names from benchBuffer
    try expectStringContains(output, "Buffer init+deinit (80x24 cells)");
    try expectStringContains(output, "Buffer setChar (single character)");
    try expectStringContains(output, "Buffer setString (13 characters)");
    try expectStringContains(output, "Buffer clear (80x24 cells)");
    try expectStringContains(output, "Buffer diff (80x24 cells, with changes)");
}

test "runAll completes without error" {
    const allocator = std.testing.allocator;
    var buffer: [16384]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    // Should not raise error
    try runAll(allocator, stream.writer());

    // Verify output is not empty
    const output = stream.getWritten();
    try std.testing.expect(output.len > 0);
}

test "bench result with large numbers formats correctly" {
    const result = BenchResult{
        .name = "Large Benchmark",
        .iterations = 1_000_000,
        .total_ns = 10_000_000_000,
        .avg_ns = 10_000,
        .ops_per_sec = 100_000.0,
    };

    var output: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try result.format("", .{}, stream.writer());
    const formatted = stream.getWritten();

    // Verify large numbers are included
    try expectStringContains(formatted, "1000000");
    try expectStringContains(formatted, "10000.00");
    try expectStringContains(formatted, "100000");
}

test "bench result with small numbers formats correctly" {
    const result = BenchResult{
        .name = "Small",
        .iterations = 1,
        .total_ns = 1,
        .avg_ns = 1,
        .ops_per_sec = 1_000_000_000.0,
    };

    var output: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output);

    try result.format("", .{}, stream.writer());
    const formatted = stream.getWritten();

    try expectStringContains(formatted, "Small");
    try expectStringContains(formatted, "1");
}

// Helper function for expectStringContains
fn expectStringContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nexpectStringContains failed:\n", .{});
        std.debug.print("  Haystack: {s}\n", .{haystack});
        std.debug.print("  Looking for: {s}\n", .{needle});
        return error.TestExpectedEqual;
    }
}
