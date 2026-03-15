//! Render profiling tools for identifying performance bottlenecks
//!
//! This module provides profiling utilities to measure widget render times,
//! detect slow widgets, and track performance metrics across frames.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Profile entry for a single widget render
pub const RenderProfile = struct {
    widget_name: []const u8,
    duration_ns: u64,
    timestamp: i128,

    pub fn durationMs(self: RenderProfile) f64 {
        return @as(f64, @floatFromInt(self.duration_ns)) / 1_000_000.0;
    }

    pub fn durationUs(self: RenderProfile) f64 {
        return @as(f64, @floatFromInt(self.duration_ns)) / 1_000.0;
    }
};

/// Profiler that tracks widget render times and detects bottlenecks
pub const Profiler = struct {
    allocator: Allocator,
    profiles: std.ArrayList(RenderProfile),
    current_frame: u64,
    threshold_ms: f64, // Bottleneck threshold in milliseconds

    const Self = @This();

    /// Initialize a new profiler
    pub fn init(allocator: Allocator, threshold_ms: f64) !Self {
        return Self{
            .allocator = allocator,
            .profiles = .{},
            .current_frame = 0,
            .threshold_ms = threshold_ms,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.profiles.deinit(self.allocator);
    }

    /// Start profiling a widget render
    pub fn start(self: *Self, widget_name: []const u8) !ProfileGuard {
        return ProfileGuard{
            .profiler = self,
            .widget_name = widget_name,
            .start_time = std.time.nanoTimestamp(),
        };
    }

    /// Record a completed profile entry
    fn record(self: *Self, widget_name: []const u8, duration_ns: u64) !void {
        try self.profiles.append(self.allocator, .{
            .widget_name = widget_name,
            .duration_ns = duration_ns,
            .timestamp = std.time.milliTimestamp(),
        });
    }

    /// Get profiles for the current frame
    pub fn frameProfiles(self: *Self) []const RenderProfile {
        return self.profiles.items;
    }

    /// Detect bottlenecks (widgets exceeding threshold)
    pub fn detectBottlenecks(self: *Self, allocator: Allocator) ![]RenderProfile {
        var bottlenecks: std.ArrayList(RenderProfile) = .{};
        errdefer bottlenecks.deinit(allocator);

        for (self.profiles.items) |profile| {
            if (profile.durationMs() > self.threshold_ms) {
                try bottlenecks.append(allocator, profile);
            }
        }

        return bottlenecks.toOwnedSlice(allocator);
    }

    /// Get statistics for widget render times
    pub fn getStats(self: *Self, widget_name: []const u8) Stats {
        var total_ns: u64 = 0;
        var count: usize = 0;
        var min_ns: u64 = std.math.maxInt(u64);
        var max_ns: u64 = 0;

        for (self.profiles.items) |profile| {
            if (std.mem.eql(u8, profile.widget_name, widget_name)) {
                total_ns += profile.duration_ns;
                count += 1;
                if (profile.duration_ns < min_ns) min_ns = profile.duration_ns;
                if (profile.duration_ns > max_ns) max_ns = profile.duration_ns;
            }
        }

        const avg_ns: u64 = if (count > 0) total_ns / count else 0;

        return Stats{
            .count = count,
            .avg_ns = avg_ns,
            .min_ns = if (count > 0) min_ns else 0,
            .max_ns = max_ns,
            .total_ns = total_ns,
        };
    }

    /// Clear profiles for the next frame
    pub fn nextFrame(self: *Self) void {
        self.profiles.clearRetainingCapacity();
        self.current_frame += 1;
    }

    /// Reset profiler state
    pub fn reset(self: *Self) void {
        self.profiles.clearRetainingCapacity();
        self.current_frame = 0;
    }

    /// Get the slowest widget in current frame
    pub fn slowestWidget(self: *Self) ?RenderProfile {
        if (self.profiles.items.len == 0) return null;

        var slowest = self.profiles.items[0];
        for (self.profiles.items[1..]) |profile| {
            if (profile.duration_ns > slowest.duration_ns) {
                slowest = profile;
            }
        }

        return slowest;
    }

    /// Get the fastest widget in current frame
    pub fn fastestWidget(self: *Self) ?RenderProfile {
        if (self.profiles.items.len == 0) return null;

        var fastest = self.profiles.items[0];
        for (self.profiles.items[1..]) |profile| {
            if (profile.duration_ns < fastest.duration_ns) {
                fastest = profile;
            }
        }

        return fastest;
    }

    /// Get total render time for current frame
    pub fn totalRenderTime(self: *Self) u64 {
        var total: u64 = 0;
        for (self.profiles.items) |profile| {
            total += profile.duration_ns;
        }
        return total;
    }
};

/// Statistics for a widget's render performance
pub const Stats = struct {
    count: usize,
    avg_ns: u64,
    min_ns: u64,
    max_ns: u64,
    total_ns: u64,

    pub fn avgMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.avg_ns)) / 1_000_000.0;
    }

    pub fn minMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.min_ns)) / 1_000_000.0;
    }

    pub fn maxMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.max_ns)) / 1_000_000.0;
    }

    pub fn totalMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.total_ns)) / 1_000_000.0;
    }
};

/// RAII guard for automatic profiling
pub const ProfileGuard = struct {
    profiler: *Profiler,
    widget_name: []const u8,
    start_time: i128,

    pub fn end(self: ProfileGuard) !void {
        const end_time = std.time.nanoTimestamp();
        const duration_ns: u64 = @intCast(end_time - self.start_time);
        try self.profiler.record(self.widget_name, duration_ns);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "profiler init and deinit" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try testing.expectEqual(@as(u64, 0), profiler.current_frame);
    try testing.expectEqual(@as(f64, 16.0), profiler.threshold_ms);
}

test "profile guard records duration" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    {
        var guard = try profiler.start("test_widget");
        std.Thread.sleep(1_000_000); // 1ms
        try guard.end();
    }

    const profiles = profiler.frameProfiles();
    try testing.expectEqual(@as(usize, 1), profiles.len);
    try testing.expect(std.mem.eql(u8, "test_widget", profiles[0].widget_name));
    try testing.expect(profiles[0].duration_ns > 0);
}

test "detect bottlenecks" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 5.0); // 5ms threshold
    defer profiler.deinit();

    // Fast widget (< 5ms)
    try profiler.record("fast", 1_000_000); // 1ms

    // Slow widget (> 5ms)
    try profiler.record("slow", 10_000_000); // 10ms

    const bottlenecks = try profiler.detectBottlenecks(allocator);
    defer allocator.free(bottlenecks);

    try testing.expectEqual(@as(usize, 1), bottlenecks.len);
    try testing.expect(std.mem.eql(u8, "slow", bottlenecks[0].widget_name));
}

test "get statistics for widget" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.record("widget_a", 1_000_000); // 1ms
    try profiler.record("widget_a", 3_000_000); // 3ms
    try profiler.record("widget_a", 2_000_000); // 2ms
    try profiler.record("widget_b", 5_000_000); // 5ms

    const stats = profiler.getStats("widget_a");
    try testing.expectEqual(@as(usize, 3), stats.count);
    try testing.expectEqual(@as(u64, 2_000_000), stats.avg_ns); // (1+3+2)/3 = 2ms
    try testing.expectEqual(@as(u64, 1_000_000), stats.min_ns);
    try testing.expectEqual(@as(u64, 3_000_000), stats.max_ns);
}

test "slowest and fastest widget" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.record("fast", 1_000_000); // 1ms
    try profiler.record("medium", 5_000_000); // 5ms
    try profiler.record("slow", 10_000_000); // 10ms

    const slowest = profiler.slowestWidget();
    try testing.expect(slowest != null);
    try testing.expect(std.mem.eql(u8, "slow", slowest.?.widget_name));

    const fastest = profiler.fastestWidget();
    try testing.expect(fastest != null);
    try testing.expect(std.mem.eql(u8, "fast", fastest.?.widget_name));
}

test "total render time" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.record("a", 1_000_000); // 1ms
    try profiler.record("b", 2_000_000); // 2ms
    try profiler.record("c", 3_000_000); // 3ms

    const total = profiler.totalRenderTime();
    try testing.expectEqual(@as(u64, 6_000_000), total); // 6ms
}

test "next frame clears profiles" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.record("widget", 1_000_000);
    try testing.expectEqual(@as(usize, 1), profiler.frameProfiles().len);

    profiler.nextFrame();
    try testing.expectEqual(@as(usize, 0), profiler.frameProfiles().len);
    try testing.expectEqual(@as(u64, 1), profiler.current_frame);
}

test "reset clears all state" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.record("widget", 1_000_000);
    profiler.nextFrame();
    profiler.reset();

    try testing.expectEqual(@as(usize, 0), profiler.frameProfiles().len);
    try testing.expectEqual(@as(u64, 0), profiler.current_frame);
}

test "duration conversions" {
    const profile = RenderProfile{
        .widget_name = "test",
        .duration_ns = 1_500_000, // 1.5ms
        .timestamp = 0,
    };

    try testing.expectApproxEqAbs(@as(f64, 1.5), profile.durationMs(), 0.01);
    try testing.expectApproxEqAbs(@as(f64, 1500.0), profile.durationUs(), 0.1);
}

test "stats conversions" {
    const stats = Stats{
        .count = 3,
        .avg_ns = 2_500_000, // 2.5ms
        .min_ns = 1_000_000, // 1ms
        .max_ns = 5_000_000, // 5ms
        .total_ns = 7_500_000, // 7.5ms
    };

    try testing.expectApproxEqAbs(@as(f64, 2.5), stats.avgMs(), 0.01);
    try testing.expectApproxEqAbs(@as(f64, 1.0), stats.minMs(), 0.01);
    try testing.expectApproxEqAbs(@as(f64, 5.0), stats.maxMs(), 0.01);
    try testing.expectApproxEqAbs(@as(f64, 7.5), stats.totalMs(), 0.01);
}

test "empty profiler operations" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try testing.expect(profiler.slowestWidget() == null);
    try testing.expect(profiler.fastestWidget() == null);
    try testing.expectEqual(@as(u64, 0), profiler.totalRenderTime());

    const stats = profiler.getStats("nonexistent");
    try testing.expectEqual(@as(usize, 0), stats.count);
    try testing.expectEqual(@as(u64, 0), stats.avg_ns);
}

test "multiple widgets same frame" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.record("button", 1_000_000);
    try profiler.record("table", 3_000_000);
    try profiler.record("list", 2_000_000);
    try profiler.record("button", 1_500_000);

    const button_stats = profiler.getStats("button");
    try testing.expectEqual(@as(usize, 2), button_stats.count);
    try testing.expectEqual(@as(u64, 1_250_000), button_stats.avg_ns); // (1+1.5)/2
}
