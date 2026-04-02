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
    is_cache_hit: bool = false,

    /// Returns the duration in milliseconds.
    pub fn durationMs(self: RenderProfile) f64 {
        return @as(f64, @floatFromInt(self.duration_ns)) / 1_000_000.0;
    }

    /// Returns the duration in microseconds.
    pub fn durationUs(self: RenderProfile) f64 {
        return @as(f64, @floatFromInt(self.duration_ns)) / 1_000.0;
    }
};

/// Represents a nested profiling scope for flame graph visualization
pub const ProfilerFrame = struct {
    name: []const u8,
    self_time_ns: u64, // Exclusive time (excluding children)
    total_time_ns: u64, // Inclusive time (including children)
    children: []ProfilerFrame,

    /// Recursively free all children
    pub fn deinitRecursive(self: *ProfilerFrame, allocator: Allocator) void {
        for (self.children) |*child| {
            child.deinitRecursive(allocator);
        }
        allocator.free(self.children);
    }
};

/// Extended metrics for a widget's render performance
pub const WidgetMetrics = struct {
    render_count: usize,
    cache_hits: usize,
    cache_misses: usize,
    avg_duration_ns: u64,

    /// Calculate cache hit rate (0.0 to 1.0)
    pub fn cacheHitRate(self: WidgetMetrics) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total));
    }
};

/// Profiler that tracks widget render times and detects bottlenecks
pub const Profiler = struct {
    allocator: Allocator,
    profiles: std.ArrayList(RenderProfile),
    current_frame: u64,
    threshold_ms: f64, // Bottleneck threshold in milliseconds

    // Flame graph support
    scope_stack: std.ArrayList(ScopeEntry),
    root_scopes: std.ArrayList(ScopeEntry),

    const Self = @This();

    const ScopeEntry = struct {
        name: []const u8,
        start_time: i128,
        end_time: i128 = 0,
        children: std.ArrayList(ScopeEntry),

        fn deinit(self: *ScopeEntry, allocator: Allocator) void {
            for (self.children.items) |*child| {
                child.deinit(allocator);
            }
            self.children.deinit(allocator);
        }

        fn totalTime(self: *const ScopeEntry) u64 {
            if (self.end_time == 0) return 0;
            return @intCast(self.end_time - self.start_time);
        }

        fn childrenTime(self: *const ScopeEntry) u64 {
            var total: u64 = 0;
            for (self.children.items) |*child| {
                total += child.totalTime();
            }
            return total;
        }

        fn selfTime(self: *const ScopeEntry) u64 {
            const total = self.totalTime();
            const children = self.childrenTime();
            if (total > children) return total - children;
            return 0;
        }
    };

    /// Initialize a new profiler
    pub fn init(allocator: Allocator, threshold_ms: f64) !Self {
        return Self{
            .allocator = allocator,
            .profiles = .{},
            .current_frame = 0,
            .threshold_ms = threshold_ms,
            .scope_stack = .{},
            .root_scopes = .{},
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.profiles.deinit(self.allocator);
        for (self.scope_stack.items) |*scope| {
            scope.deinit(self.allocator);
        }
        self.scope_stack.deinit(self.allocator);
        for (self.root_scopes.items) |*scope| {
            scope.deinit(self.allocator);
        }
        self.root_scopes.deinit(self.allocator);
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
            .is_cache_hit = false,
        });
    }

    /// Record a completed profile entry with cache information
    pub fn recordWithCache(self: *Self, widget_name: []const u8, duration_ns: u64, is_cache_hit: bool) !void {
        try self.profiles.append(self.allocator, .{
            .widget_name = widget_name,
            .duration_ns = duration_ns,
            .timestamp = std.time.milliTimestamp(),
            .is_cache_hit = is_cache_hit,
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

    // ========================================================================
    // Flame Graph Support (v1.31.0)
    // ========================================================================

    /// Begin a new profiling scope for flame graph
    pub fn beginScope(self: *Self, name: []const u8) !void {
        const entry = ScopeEntry{
            .name = name,
            .start_time = std.time.nanoTimestamp(),
            .children = .{},
        };
        try self.scope_stack.append(self.allocator, entry);
    }

    /// End the current profiling scope
    pub fn endScope(self: *Self) !void {
        if (self.scope_stack.items.len == 0) {
            return error.NoScopeToEnd;
        }

        const last_idx = self.scope_stack.items.len - 1;
        self.scope_stack.items[last_idx].end_time = std.time.nanoTimestamp();

        const scope = self.scope_stack.orderedRemove(last_idx);

        if (self.scope_stack.items.len == 0) {
            // This is a root scope
            try self.root_scopes.append(self.allocator, scope);
        } else {
            // Add to parent's children
            var parent = &self.scope_stack.items[self.scope_stack.items.len - 1];
            try parent.children.append(self.allocator, scope);
        }
    }

    /// Export flame graph data
    pub fn flameGraphData(self: *Self, allocator: Allocator) ![]ProfilerFrame {
        var frames: std.ArrayList(ProfilerFrame) = .{};
        errdefer {
            for (frames.items) |*frame| {
                frame.deinitRecursive(allocator);
            }
            frames.deinit(allocator);
        }

        for (self.root_scopes.items) |*scope| {
            try frames.append(allocator, try scopeToFrame(allocator, scope));
        }

        return frames.toOwnedSlice(allocator);
    }

    fn scopeToFrame(allocator: Allocator, scope: *const ScopeEntry) !ProfilerFrame {
        var children: std.ArrayList(ProfilerFrame) = .{};
        errdefer {
            for (children.items) |*child| {
                child.deinitRecursive(allocator);
            }
            children.deinit(allocator);
        }

        for (scope.children.items) |*child| {
            try children.append(allocator, try scopeToFrame(allocator, child));
        }

        return ProfilerFrame{
            .name = scope.name,
            .self_time_ns = scope.selfTime(),
            .total_time_ns = scope.totalTime(),
            .children = try children.toOwnedSlice(allocator),
        };
    }

    // ========================================================================
    // Extended Widget Metrics (v1.31.0)
    // ========================================================================

    /// Get extended metrics for a specific widget
    pub fn getWidgetMetrics(self: *Self, widget_name: []const u8) !WidgetMetrics {
        var render_count: usize = 0;
        var cache_hits: usize = 0;
        var cache_misses: usize = 0;
        var total_duration: u64 = 0;

        for (self.profiles.items) |profile| {
            if (std.mem.eql(u8, profile.widget_name, widget_name)) {
                render_count += 1;
                total_duration += profile.duration_ns;
                if (profile.is_cache_hit) {
                    cache_hits += 1;
                } else {
                    cache_misses += 1;
                }
            }
        }

        const avg_duration = if (render_count > 0) total_duration / render_count else 0;

        return WidgetMetrics{
            .render_count = render_count,
            .cache_hits = cache_hits,
            .cache_misses = cache_misses,
            .avg_duration_ns = avg_duration,
        };
    }
};

/// Statistics for a widget's render performance
pub const Stats = struct {
    count: usize,
    avg_ns: u64,
    min_ns: u64,
    max_ns: u64,
    total_ns: u64,

    /// Returns the average duration in milliseconds.
    pub fn avgMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.avg_ns)) / 1_000_000.0;
    }

    /// Returns the minimum duration in milliseconds.
    pub fn minMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.min_ns)) / 1_000_000.0;
    }

    /// Returns the maximum duration in milliseconds.
    pub fn maxMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.max_ns)) / 1_000_000.0;
    }

    /// Returns the total duration in milliseconds.
    pub fn totalMs(self: Stats) f64 {
        return @as(f64, @floatFromInt(self.total_ns)) / 1_000_000.0;
    }
};

/// RAII guard for automatic profiling
pub const ProfileGuard = struct {
    profiler: *Profiler,
    widget_name: []const u8,
    start_time: i128,

    /// Ends profiling and records the duration.
    /// Call this when the profiled operation completes.
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

// ============================================================================
// v1.31.0 Enhancement Tests — Flame Graph & Extended Metrics
// ============================================================================

test "flame graph nested scopes track hierarchy" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    // Nested profiling: root -> child1 -> grandchild
    try profiler.beginScope("root");
    std.Thread.sleep(1_000_000); // 1ms
    try profiler.beginScope("child1");
    std.Thread.sleep(500_000); // 0.5ms
    try profiler.beginScope("grandchild");
    std.Thread.sleep(200_000); // 0.2ms
    try profiler.endScope(); // grandchild
    try profiler.endScope(); // child1
    try profiler.beginScope("child2");
    std.Thread.sleep(300_000); // 0.3ms
    try profiler.endScope(); // child2
    try profiler.endScope(); // root

    const flame_data = try profiler.flameGraphData(allocator);
    defer {
        for (flame_data) |*frame| {
            var mutable_frame = frame.*;
            mutable_frame.deinitRecursive(allocator);
        }
        allocator.free(flame_data);
    }

    // Should have root with 2 children, child1 with 1 child
    try testing.expectEqual(@as(usize, 1), flame_data.len); // 1 root
    try testing.expect(std.mem.eql(u8, "root", flame_data[0].name));
    try testing.expectEqual(@as(usize, 2), flame_data[0].children.len); // child1, child2
    try testing.expect(flame_data[0].total_time_ns > 2_000_000); // > 2ms inclusive
    try testing.expect(flame_data[0].children[0].children.len == 1); // child1 has grandchild
}

test "flame graph self time excludes children" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.beginScope("parent");
    std.Thread.sleep(1_000_000); // 1ms self
    try profiler.beginScope("child");
    std.Thread.sleep(500_000); // 0.5ms child
    try profiler.endScope();
    std.Thread.sleep(500_000); // 0.5ms more self
    try profiler.endScope();

    const flame_data = try profiler.flameGraphData(allocator);
    defer {
        for (flame_data) |*frame| {
            var mutable_frame = frame.*;
            mutable_frame.deinitRecursive(allocator);
        }
        allocator.free(flame_data);
    }

    const parent = flame_data[0];
    // self_time should be ~1.5ms (total 2ms - child 0.5ms)
    try testing.expect(parent.self_time_ns < parent.total_time_ns);
    try testing.expect(parent.self_time_ns >= 1_000_000); // at least 1ms self
    try testing.expect(parent.total_time_ns >= 2_000_000); // at least 2ms total
}

test "flame graph multiple sibling scopes" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    try profiler.beginScope("root");
    try profiler.beginScope("sibling1");
    std.Thread.sleep(100_000);
    try profiler.endScope();
    try profiler.beginScope("sibling2");
    std.Thread.sleep(200_000);
    try profiler.endScope();
    try profiler.beginScope("sibling3");
    std.Thread.sleep(150_000);
    try profiler.endScope();
    try profiler.endScope();

    const flame_data = try profiler.flameGraphData(allocator);
    defer {
        for (flame_data) |*frame| {
            var mutable_frame = frame.*;
            mutable_frame.deinitRecursive(allocator);
        }
        allocator.free(flame_data);
    }

    try testing.expectEqual(@as(usize, 3), flame_data[0].children.len);
    try testing.expect(std.mem.eql(u8, "sibling1", flame_data[0].children[0].name));
    try testing.expect(std.mem.eql(u8, "sibling2", flame_data[0].children[1].name));
    try testing.expect(std.mem.eql(u8, "sibling3", flame_data[0].children[2].name));
}

test "flame graph error on unmatched endScope" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    const result = profiler.endScope();
    try testing.expectError(error.NoScopeToEnd, result);
}

test "extended widget metrics track render count" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    // Simulate 3 renders of button widget
    try profiler.record("button", 1_000_000);
    try profiler.record("button", 1_200_000);
    try profiler.record("button", 900_000);

    const metrics = try profiler.getWidgetMetrics("button");
    try testing.expectEqual(@as(usize, 3), metrics.render_count);
    try testing.expectEqual(@as(u64, 1_033_333), metrics.avg_duration_ns); // (1.0 + 1.2 + 0.9) / 3
}

test "extended widget metrics track cache hits and misses" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 16.0);
    defer profiler.deinit();

    // Record widget with cache hits/misses
    try profiler.recordWithCache("table", 2_000_000, true); // cache hit
    try profiler.recordWithCache("table", 5_000_000, false); // cache miss
    try profiler.recordWithCache("table", 2_100_000, true); // cache hit

    const metrics = try profiler.getWidgetMetrics("table");
    try testing.expectEqual(@as(usize, 3), metrics.render_count);
    try testing.expectEqual(@as(usize, 2), metrics.cache_hits);
    try testing.expectEqual(@as(usize, 1), metrics.cache_misses);

    // Cache hit rate should be ~66.67%
    const hit_rate = metrics.cacheHitRate();
    try testing.expectApproxEqAbs(@as(f64, 0.6667), hit_rate, 0.01);
}

// ============================================================================
// v1.31.0 Memory Allocation Tracker
// ============================================================================

/// Memory allocation event for tracking hot spots
pub const AllocEvent = struct {
    location: []const u8, // Call site identifier (widget name, function, etc.)
    size: usize, // Allocation size in bytes
    timestamp: i128,
    allocation_type: AllocType,

    pub const AllocType = enum {
        allocate,
        free,
        resize,
    };
};

/// Statistics for memory allocations at a specific location
pub const AllocStats = struct {
    location: []const u8,
    total_allocated: usize, // Total bytes allocated
    total_freed: usize, // Total bytes freed
    peak_allocated: usize, // Peak concurrent allocation
    alloc_count: usize, // Number of allocations
    free_count: usize, // Number of frees
    avg_alloc_size: usize, // Average allocation size

    /// Net allocated bytes (allocated - freed)
    pub fn netAllocated(self: AllocStats) isize {
        return @as(isize, @intCast(self.total_allocated)) - @as(isize, @intCast(self.total_freed));
    }

    /// Potential leak detection (alloc_count > free_count)
    pub fn hasLeak(self: AllocStats) bool {
        return self.alloc_count > self.free_count;
    }

    /// Leak count (unfreed allocations)
    pub fn leakCount(self: AllocStats) usize {
        if (self.alloc_count > self.free_count) {
            return self.alloc_count - self.free_count;
        }
        return 0;
    }
};

/// Memory allocation tracker for identifying hot spots and leaks
pub const MemoryTracker = struct {
    allocator: Allocator,
    events: std.ArrayList(AllocEvent),
    current_allocated: std.StringHashMap(usize), // location -> bytes
    peak_allocated: std.StringHashMap(usize), // location -> peak bytes
    enabled: bool,

    const Self = @This();

    /// Initialize memory tracker
    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .events = .{},
            .current_allocated = std.StringHashMap(usize).init(allocator),
            .peak_allocated = std.StringHashMap(usize).init(allocator),
            .enabled = true,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.events.deinit(self.allocator);
        self.current_allocated.deinit();
        self.peak_allocated.deinit();
    }

    /// Record an allocation event
    pub fn recordAlloc(self: *Self, location: []const u8, size: usize) !void {
        if (!self.enabled) return;

        try self.events.append(self.allocator, .{
            .location = location,
            .size = size,
            .timestamp = std.time.nanoTimestamp(),
            .allocation_type = .allocate,
        });

        // Update current allocated
        const current = self.current_allocated.get(location) orelse 0;
        const new_current = current + size;
        try self.current_allocated.put(location, new_current);

        // Update peak if needed
        const peak = self.peak_allocated.get(location) orelse 0;
        if (new_current > peak) {
            try self.peak_allocated.put(location, new_current);
        }
    }

    /// Record a free event
    pub fn recordFree(self: *Self, location: []const u8, size: usize) !void {
        if (!self.enabled) return;

        try self.events.append(self.allocator, .{
            .location = location,
            .size = size,
            .timestamp = std.time.nanoTimestamp(),
            .allocation_type = .free,
        });

        // Update current allocated
        const current = self.current_allocated.get(location) orelse 0;
        if (current >= size) {
            try self.current_allocated.put(location, current - size);
        }
    }

    /// Record a resize event
    pub fn recordResize(self: *Self, location: []const u8, old_size: usize, new_size: usize) !void {
        if (!self.enabled) return;

        try self.events.append(self.allocator, .{
            .location = location,
            .size = new_size,
            .timestamp = std.time.nanoTimestamp(),
            .allocation_type = .resize,
        });

        // Update current allocated (net change)
        const current = self.current_allocated.get(location) orelse 0;
        const net_change = if (new_size > old_size) new_size - old_size else 0;
        const new_current = current + net_change;
        try self.current_allocated.put(location, new_current);

        // Update peak if needed
        const peak = self.peak_allocated.get(location) orelse 0;
        if (new_current > peak) {
            try self.peak_allocated.put(location, new_current);
        }
    }

    /// Get allocation statistics for a specific location
    pub fn getStats(self: *Self, location: []const u8) !AllocStats {
        var total_allocated: usize = 0;
        var total_freed: usize = 0;
        var alloc_count: usize = 0;
        var free_count: usize = 0;

        for (self.events.items) |event| {
            if (!std.mem.eql(u8, event.location, location)) continue;

            switch (event.allocation_type) {
                .allocate => {
                    total_allocated += event.size;
                    alloc_count += 1;
                },
                .free => {
                    total_freed += event.size;
                    free_count += 1;
                },
                .resize => {
                    // Resize counts as both alloc and free
                    alloc_count += 1;
                },
            }
        }

        const avg_alloc_size = if (alloc_count > 0) total_allocated / alloc_count else 0;
        const peak = self.peak_allocated.get(location) orelse 0;

        return AllocStats{
            .location = location,
            .total_allocated = total_allocated,
            .total_freed = total_freed,
            .peak_allocated = peak,
            .alloc_count = alloc_count,
            .free_count = free_count,
            .avg_alloc_size = avg_alloc_size,
        };
    }

    /// Get top N allocation hot spots by total bytes allocated
    pub fn getHotSpots(self: *Self, allocator: Allocator, top_n: usize) ![]AllocStats {
        var location_map = std.StringHashMap(void).init(allocator);
        defer location_map.deinit();

        // Collect unique locations
        for (self.events.items) |event| {
            try location_map.put(event.location, {});
        }

        // Get stats for each location
        var all_stats = try std.ArrayList(AllocStats).initCapacity(allocator, location_map.count());
        defer all_stats.deinit(allocator);

        var iter = location_map.keyIterator();
        while (iter.next()) |location| {
            const stats = try self.getStats(location.*);
            try all_stats.append(allocator, stats);
        }

        // Sort by total_allocated descending
        const items = all_stats.items;
        std.mem.sort(AllocStats, items, {}, struct {
            fn lessThan(_: void, a: AllocStats, b: AllocStats) bool {
                return a.total_allocated > b.total_allocated;
            }
        }.lessThan);

        // Return top N
        const count = @min(top_n, items.len);
        const result = try allocator.alloc(AllocStats, count);
        @memcpy(result, items[0..count]);
        return result;
    }

    /// Detect potential memory leaks (allocations without corresponding frees)
    pub fn detectLeaks(self: *Self, allocator: Allocator) ![]AllocStats {
        var location_map = std.StringHashMap(void).init(allocator);
        defer location_map.deinit();

        // Collect unique locations
        for (self.events.items) |event| {
            try location_map.put(event.location, {});
        }

        // Check each location for leaks
        var leaks: std.ArrayList(AllocStats) = .{};
        errdefer leaks.deinit(allocator);

        var iter = location_map.keyIterator();
        while (iter.next()) |location| {
            const stats = try self.getStats(location.*);
            if (stats.hasLeak()) {
                try leaks.append(allocator, stats);
            }
        }

        return leaks.toOwnedSlice(allocator);
    }

    /// Get total bytes currently allocated across all locations
    pub fn totalCurrentAllocated(self: *Self) usize {
        var total: usize = 0;
        var iter = self.current_allocated.valueIterator();
        while (iter.next()) |bytes| {
            total += bytes.*;
        }
        return total;
    }

    /// Get peak total allocated across all locations
    pub fn totalPeakAllocated(self: *Self) usize {
        var total: usize = 0;
        var iter = self.peak_allocated.valueIterator();
        while (iter.next()) |bytes| {
            total += bytes.*;
        }
        return total;
    }

    /// Reset all tracking data
    pub fn reset(self: *Self) void {
        self.events.clearRetainingCapacity();
        self.current_allocated.clearRetainingCapacity();
        self.peak_allocated.clearRetainingCapacity();
    }

    /// Enable tracking
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable tracking
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }
};

// ============================================================================
// Memory Tracker Tests
// ============================================================================

test "memory tracker init and deinit" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try testing.expect(tracker.enabled);
    try testing.expectEqual(@as(usize, 0), tracker.events.items.len);
}

test "memory tracker records allocations" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("widget_render", 1024);
    try tracker.recordAlloc("widget_render", 512);
    try tracker.recordAlloc("event_loop", 2048);

    try testing.expectEqual(@as(usize, 3), tracker.events.items.len);
    try testing.expectEqual(@as(usize, 1024), tracker.events.items[0].size);
}

test "memory tracker calculates stats correctly" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("button", 1000);
    try tracker.recordAlloc("button", 2000);
    try tracker.recordFree("button", 1000);

    const stats = try tracker.getStats("button");
    try testing.expectEqual(@as(usize, 3000), stats.total_allocated);
    try testing.expectEqual(@as(usize, 1000), stats.total_freed);
    try testing.expectEqual(@as(usize, 2), stats.alloc_count);
    try testing.expectEqual(@as(usize, 1), stats.free_count);
    try testing.expectEqual(@as(usize, 1500), stats.avg_alloc_size); // 3000/2
}

test "memory tracker tracks peak allocation" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("table", 1000);
    try tracker.recordAlloc("table", 2000); // peak = 3000
    try tracker.recordFree("table", 1000); // current = 2000

    const stats = try tracker.getStats("table");
    try testing.expectEqual(@as(usize, 3000), stats.peak_allocated);
}

test "memory tracker detects leaks" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    // No leak
    try tracker.recordAlloc("safe", 1000);
    try tracker.recordFree("safe", 1000);

    // Has leak
    try tracker.recordAlloc("leaky", 2000);
    try tracker.recordAlloc("leaky", 1000);
    try tracker.recordFree("leaky", 1000);

    const leaks = try tracker.detectLeaks(allocator);
    defer allocator.free(leaks);

    try testing.expectEqual(@as(usize, 1), leaks.len);
    try testing.expect(std.mem.eql(u8, "leaky", leaks[0].location));
    try testing.expectEqual(@as(usize, 1), leaks[0].leakCount());
}

test "memory tracker hot spots sorted by total allocated" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("small", 100);
    try tracker.recordAlloc("large", 10000);
    try tracker.recordAlloc("medium", 1000);

    const hot_spots = try tracker.getHotSpots(allocator, 3);
    defer allocator.free(hot_spots);

    try testing.expectEqual(@as(usize, 3), hot_spots.len);
    try testing.expect(std.mem.eql(u8, "large", hot_spots[0].location));
    try testing.expect(std.mem.eql(u8, "medium", hot_spots[1].location));
    try testing.expect(std.mem.eql(u8, "small", hot_spots[2].location));
}

test "memory tracker resize updates correctly" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("buffer", 1000);
    try tracker.recordResize("buffer", 1000, 2000); // Grow by 1000

    const stats = try tracker.getStats("buffer");
    try testing.expectEqual(@as(usize, 1000), stats.total_allocated); // Original alloc
    try testing.expectEqual(@as(usize, 2), stats.alloc_count); // alloc + resize
}

test "memory tracker total allocated" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("a", 1000);
    try tracker.recordAlloc("b", 2000);
    try tracker.recordAlloc("c", 500);

    const total = tracker.totalCurrentAllocated();
    try testing.expectEqual(@as(usize, 3500), total);
}

test "memory tracker enable/disable" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("test", 1000);
    try testing.expectEqual(@as(usize, 1), tracker.events.items.len);

    tracker.disable();
    try tracker.recordAlloc("test", 2000);
    try testing.expectEqual(@as(usize, 1), tracker.events.items.len); // Not recorded

    tracker.enable();
    try tracker.recordAlloc("test", 3000);
    try testing.expectEqual(@as(usize, 2), tracker.events.items.len); // Recorded
}

test "memory tracker reset clears all data" {
    const allocator = testing.allocator;
    var tracker = try MemoryTracker.init(allocator);
    defer tracker.deinit();

    try tracker.recordAlloc("test", 1000);
    tracker.reset();

    try testing.expectEqual(@as(usize, 0), tracker.events.items.len);
    try testing.expectEqual(@as(usize, 0), tracker.totalCurrentAllocated());
}
