//! Benchmark regression detection tool
//!
//! Parses benchmark output and compares against baseline to detect performance regressions.
//!
//! Usage:
//!   zig run scripts/check_benchmarks.zig -- <current_results.txt> [baseline_results.txt]
//!
//! Exit codes:
//!   0 - No regression detected
//!   1 - Regression detected (> threshold)
//!   2 - Error (missing files, parse error, etc.)

const std = @import("std");

const REGRESSION_THRESHOLD_PERCENT = 10.0; // Fail if >10% slower

const BenchmarkResult = struct {
    name: []const u8,
    total_ms: f64,
    per_op_ms: f64,
    ops_per_sec: f64,

    pub fn parseFromLine(allocator: std.mem.Allocator, line: []const u8) !?BenchmarkResult {
        // Expected format: "Block.render: 12.34ms total, 0.0012ms per op (833333 ops/sec)"
        const colon_idx = std.mem.indexOf(u8, line, ":") orelse return null;
        const name = try allocator.dupe(u8, std.mem.trim(u8, line[0..colon_idx], " \t"));

        // Parse "12.34ms total"
        const total_marker = "ms total";
        const total_idx = std.mem.indexOf(u8, line, total_marker) orelse return null;
        var total_start = colon_idx + 1;
        while (total_start < total_idx and (line[total_start] == ' ' or line[total_start] == '\t')) : (total_start += 1) {}
        const total_str = line[total_start..total_idx];
        const total_ms = std.fmt.parseFloat(f64, total_str) catch return null;

        // Parse "0.0012ms per op"
        const per_op_marker = "ms per op";
        const per_op_idx = std.mem.indexOf(u8, line, per_op_marker) orelse return null;
        var per_op_start = total_idx + total_marker.len + 1;
        while (per_op_start < per_op_idx and (line[per_op_start] == ' ' or line[per_op_start] == '\t' or line[per_op_start] == ',')) : (per_op_start += 1) {}
        const per_op_str = line[per_op_start..per_op_idx];
        const per_op_ms = std.fmt.parseFloat(f64, per_op_str) catch return null;

        // Parse "833333 ops/sec"
        const ops_marker = " ops/sec)";
        const ops_end_idx = std.mem.indexOf(u8, line, ops_marker) orelse return null;
        const ops_start_marker = "(";
        const ops_start_idx = std.mem.lastIndexOf(u8, line[0..ops_end_idx], ops_start_marker) orelse return null;
        const ops_str = line[ops_start_idx + 1 .. ops_end_idx];
        const ops_per_sec = std.fmt.parseFloat(f64, ops_str) catch return null;

        return BenchmarkResult{
            .name = name,
            .total_ms = total_ms,
            .per_op_ms = per_op_ms,
            .ops_per_sec = ops_per_sec,
        };
    }

    pub fn deinit(self: BenchmarkResult, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }

    pub fn calculateRegression(self: BenchmarkResult, baseline: BenchmarkResult) f64 {
        // Calculate regression as percentage increase in per-op time
        // Positive = slower (regression), negative = faster (improvement)
        return ((self.per_op_ms - baseline.per_op_ms) / baseline.per_op_ms) * 100.0;
    }
};

fn parseBenchmarkFile(allocator: std.mem.Allocator, path: []const u8) !std.StringHashMap(BenchmarkResult) {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var results = std.StringHashMap(BenchmarkResult).init(allocator);
    errdefer {
        var it = results.valueIterator();
        while (it.next()) |result| result.deinit(allocator);
        results.deinit();
    }

    const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (try BenchmarkResult.parseFromLine(allocator, line)) |result| {
            try results.put(result.name, result);
        }
    }

    return results;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <current_results.txt> [baseline_results.txt]\n", .{args[0]});
        std.process.exit(2);
    }

    const current_path = args[1];
    const baseline_path = if (args.len > 2) args[2] else null;

    // Parse current results
    var current_results = try parseBenchmarkFile(allocator, current_path);
    defer {
        var it = current_results.valueIterator();
        while (it.next()) |result| result.deinit(allocator);
        current_results.deinit();
    }

    std.debug.print("\n=== Benchmark Results ===\n\n", .{});

    if (baseline_path) |baseline| {
        // Parse baseline results
        var baseline_results = try parseBenchmarkFile(allocator, baseline);
        defer {
            var it = baseline_results.valueIterator();
            while (it.next()) |result| result.deinit(allocator);
            baseline_results.deinit();
        }

        // Compare results
        var has_regression = false;
        var it = current_results.iterator();

        std.debug.print("Benchmark                           Current      Baseline     Change\n", .{});
        std.debug.print("================================================================\n", .{});

        while (it.next()) |entry| {
            const current = entry.value_ptr.*;
            if (baseline_results.get(current.name)) |base| {
                const regression_pct = current.calculateRegression(base);
                const symbol = if (regression_pct > REGRESSION_THRESHOLD_PERCENT)
                    "❌"
                else if (regression_pct > 0)
                    "⚠️ "
                else
                    "✅";

                const sign: u8 = if (regression_pct >= 0) '+' else '-';
                std.debug.print("{s} {s:<30} {d:>7.4}ms   {d:>7.4}ms   {c}{d:>5.1}%\n", .{
                    symbol,
                    current.name,
                    current.per_op_ms,
                    base.per_op_ms,
                    sign,
                    @abs(regression_pct),
                });

                if (regression_pct > REGRESSION_THRESHOLD_PERCENT) {
                    has_regression = true;
                }
            } else {
                std.debug.print("➕ {s:<30} {d:>7.4}ms   (new)\n", .{ current.name, current.per_op_ms });
            }
        }

        // Check for removed benchmarks
        var baseline_it = baseline_results.iterator();
        while (baseline_it.next()) |entry| {
            if (!current_results.contains(entry.key_ptr.*)) {
                std.debug.print("➖ {s:<30} (removed)\n", .{entry.key_ptr.*});
            }
        }

        std.debug.print("\n", .{});

        if (has_regression) {
            std.debug.print("⚠️  PERFORMANCE REGRESSION DETECTED ⚠️\n", .{});
            std.debug.print("Some benchmarks are >{}% slower than baseline.\n", .{REGRESSION_THRESHOLD_PERCENT});
            std.process.exit(1);
        } else {
            std.debug.print("✅ No performance regressions detected.\n", .{});
            std.process.exit(0);
        }
    } else {
        // No baseline - just print current results
        var it = current_results.iterator();
        while (it.next()) |entry| {
            const result = entry.value_ptr.*;
            std.debug.print("{s}: {d:.4}ms per op ({d:.0} ops/sec)\n", .{
                result.name,
                result.per_op_ms,
                result.ops_per_sec,
            });
        }
        std.debug.print("\nℹ️  No baseline provided. Skipping regression detection.\n", .{});
        std.process.exit(0);
    }
}

// Tests

const testing = std.testing;

test "BenchmarkResult.parseFromLine: valid line" {
    const line = "Block.render: 12.34ms total, 0.0012ms per op (833333 ops/sec)";
    const result = try BenchmarkResult.parseFromLine(testing.allocator, line);
    try testing.expect(result != null);
    defer result.?.deinit(testing.allocator);

    try testing.expectEqualStrings("Block.render", result.?.name);
    try testing.expectApproxEqAbs(12.34, result.?.total_ms, 0.01);
    try testing.expectApproxEqAbs(0.0012, result.?.per_op_ms, 0.0001);
    try testing.expectApproxEqAbs(833333.0, result.?.ops_per_sec, 1.0);
}

test "BenchmarkResult.parseFromLine: invalid line" {
    const line = "This is not a benchmark result";
    const result = try BenchmarkResult.parseFromLine(testing.allocator, line);
    try testing.expect(result == null);
}

test "BenchmarkResult.calculateRegression: slower" {
    const current = BenchmarkResult{
        .name = "test",
        .total_ms = 100.0,
        .per_op_ms = 1.1,
        .ops_per_sec = 909.0,
    };
    const baseline = BenchmarkResult{
        .name = "test",
        .total_ms = 100.0,
        .per_op_ms = 1.0,
        .ops_per_sec = 1000.0,
    };

    const regression = current.calculateRegression(baseline);
    try testing.expectApproxEqAbs(10.0, regression, 0.1); // 10% slower
}

test "BenchmarkResult.calculateRegression: faster" {
    const current = BenchmarkResult{
        .name = "test",
        .total_ms = 100.0,
        .per_op_ms = 0.9,
        .ops_per_sec = 1111.0,
    };
    const baseline = BenchmarkResult{
        .name = "test",
        .total_ms = 100.0,
        .per_op_ms = 1.0,
        .ops_per_sec = 1000.0,
    };

    const regression = current.calculateRegression(baseline);
    try testing.expectApproxEqAbs(-10.0, regression, 0.1); // 10% faster (improvement)
}
