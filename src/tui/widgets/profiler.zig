const std = @import("std");
const tui = @import("../tui.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const BoxSet = @import("../symbols.zig").BoxSet;
const Sparkline = @import("sparkline.zig").Sparkline;

/// Frame timing statistics
pub const FrameStats = struct {
    frame_time_ms: f64,
    render_time_ms: f64,
    event_time_ms: f64,
    timestamp: i64, // Unix timestamp in ms
};

/// Memory allocation statistics
pub const AllocStats = struct {
    total_allocated: usize,
    total_freed: usize,
    current_usage: usize,
    peak_usage: usize,
    alloc_count: usize,
    free_count: usize,
};

/// Hot path entry for profiling
pub const HotPath = struct {
    name: []const u8,
    call_count: usize,
    total_time_ms: f64,
    avg_time_ms: f64,
};

/// Display mode for the profiler
pub const ProfilerMode = enum {
    frame_times, // Frame time chart and stats
    memory, // Memory allocation statistics
    hot_paths, // Hot path performance table
    all, // Combined view
};

/// Performance profiler widget
pub const PerformanceProfiler = struct {
    frame_history: std.ArrayList(FrameStats),
    alloc_stats: AllocStats,
    hot_paths: std.ArrayList(HotPath),
    mode: ProfilerMode = .all,
    max_history: usize = 100,
    target_fps: f64 = 60.0,
    show_sparkline: bool = true,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PerformanceProfiler {
        return .{
            .frame_history = std.ArrayList(FrameStats).init(allocator),
            .alloc_stats = .{
                .total_allocated = 0,
                .total_freed = 0,
                .current_usage = 0,
                .peak_usage = 0,
                .alloc_count = 0,
                .free_count = 0,
            },
            .hot_paths = std.ArrayList(HotPath).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PerformanceProfiler) void {
        self.frame_history.deinit();
        self.hot_paths.deinit();
    }

    /// Record a frame timing sample
    pub fn recordFrame(self: *PerformanceProfiler, stats: FrameStats) !void {
        try self.frame_history.append(stats);

        // Trim history if exceeds max
        while (self.frame_history.items.len > self.max_history) {
            _ = self.frame_history.orderedRemove(0);
        }
    }

    /// Update memory statistics
    pub fn updateMemory(self: *PerformanceProfiler, stats: AllocStats) void {
        self.alloc_stats = stats;
    }

    /// Record a hot path entry
    pub fn recordHotPath(self: *PerformanceProfiler, path: HotPath) !void {
        // Check if path already exists
        for (self.hot_paths.items) |*existing| {
            if (std.mem.eql(u8, existing.name, path.name)) {
                existing.call_count = path.call_count;
                existing.total_time_ms = path.total_time_ms;
                existing.avg_time_ms = path.avg_time_ms;
                return;
            }
        }

        // Add new path
        try self.hot_paths.append(path);
    }

    /// Clear all hot paths
    pub fn clearHotPaths(self: *PerformanceProfiler) void {
        self.hot_paths.clearRetainingCapacity();
    }

    /// Set display mode
    pub fn setMode(self: *PerformanceProfiler, mode: ProfilerMode) void {
        self.mode = mode;
    }

    /// Get average FPS from frame history
    pub fn getAverageFPS(self: *const PerformanceProfiler) f64 {
        if (self.frame_history.items.len == 0) return 0.0;

        var total: f64 = 0.0;
        for (self.frame_history.items) |frame| {
            total += frame.frame_time_ms;
        }

        const avg_ms = total / @as(f64, @floatFromInt(self.frame_history.items.len));
        return if (avg_ms > 0) 1000.0 / avg_ms else 0.0;
    }

    /// Get minimum frame time
    pub fn getMinFrameTime(self: *const PerformanceProfiler) f64 {
        if (self.frame_history.items.len == 0) return 0.0;

        var min: f64 = self.frame_history.items[0].frame_time_ms;
        for (self.frame_history.items[1..]) |frame| {
            if (frame.frame_time_ms < min) min = frame.frame_time_ms;
        }
        return min;
    }

    /// Get maximum frame time
    pub fn getMaxFrameTime(self: *const PerformanceProfiler) f64 {
        if (self.frame_history.items.len == 0) return 0.0;

        var max: f64 = self.frame_history.items[0].frame_time_ms;
        for (self.frame_history.items[1..]) |frame| {
            if (frame.frame_time_ms > max) max = frame.frame_time_ms;
        }
        return max;
    }

    /// Render the profiler
    pub fn render(self: *const PerformanceProfiler, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        switch (self.mode) {
            .frame_times => try self.renderFrameTimes(buf, area),
            .memory => try self.renderMemory(buf, area),
            .hot_paths => try self.renderHotPaths(buf, area),
            .all => {
                // Split view: frame times (top), memory (middle), hot paths (bottom)
                const h1 = area.height / 3;
                const h2 = area.height / 3;
                const h3 = area.height - h1 - h2;

                const top = Rect{ .x = area.x, .y = area.y, .width = area.width, .height = h1 };
                const middle = Rect{ .x = area.x, .y = area.y + h1, .width = area.width, .height = h2 };
                const bottom = Rect{ .x = area.x, .y = area.y + h1 + h2, .width = area.width, .height = h3 };

                try self.renderFrameTimes(buf, top);
                try self.renderMemory(buf, middle);
                try self.renderHotPaths(buf, bottom);
            },
        }
    }

    fn renderFrameTimes(self: *const PerformanceProfiler, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Draw border
        const block = Block{
            .title = "Frame Performance",
            .borders = .all,
            .border_set = BoxSet.single,
        };
        block.render(buf, area);
        const inner = block.inner(area);

        if (inner.height < 2) return;

        // Stats line
        var stats_buf: [256]u8 = undefined;
        const avg_fps = self.getAverageFPS();
        const min_ms = self.getMinFrameTime();
        const max_ms = self.getMaxFrameTime();
        const target_ms = 1000.0 / self.target_fps;

        const stats = std.fmt.bufPrint(&stats_buf, "FPS: {d:.1} (target: {d:.0})  Min: {d:.2}ms  Max: {d:.2}ms  Samples: {}", .{
            avg_fps,
            self.target_fps,
            min_ms,
            max_ms,
            self.frame_history.items.len,
        }) catch "";

        const stats_style: Style = if (avg_fps >= self.target_fps * 0.9)
            .{ .fg = .{ .basic = .green }, .bold = true }
        else if (avg_fps >= self.target_fps * 0.7)
            .{ .fg = .{ .basic = .yellow }, .bold = true }
        else
            .{ .fg = .{ .basic = .red }, .bold = true };

        buf.setString(inner.x, inner.y, stats, stats_style);

        // Sparkline chart
        if (self.show_sparkline and inner.height > 2 and self.frame_history.items.len > 0) {
            // Convert frame times to u64 array for sparkline
            var frame_times = try self.allocator.alloc(u64, self.frame_history.items.len);
            defer self.allocator.free(frame_times);

            for (self.frame_history.items, 0..) |frame, i| {
                frame_times[i] = @intFromFloat(frame.frame_time_ms * 100.0); // Scale for precision
            }

            const sparkline = Sparkline{
                .data = frame_times,
                .max = @intFromFloat(target_ms * 2.0 * 100.0), // 2x target as max
            };

            const chart_area = Rect{
                .x = inner.x,
                .y = inner.y + 2,
                .width = inner.width,
                .height = inner.height -| 2,
            };

            sparkline.render(buf, chart_area);

            // Target line indicator
            const target_y = inner.y + 1;
            var target_buf: [64]u8 = undefined;
            const target_str = std.fmt.bufPrint(&target_buf, "Target: {d:.2}ms", .{target_ms}) catch "";
            buf.setString(inner.x, target_y, target_str, .{ .fg = .{ .basic = .cyan } });
        }
    }

    fn renderMemory(self: *const PerformanceProfiler, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Draw border
        const block = Block{
            .title = "Memory Usage",
            .borders = .all,
            .border_set = BoxSet.single,
        };
        block.render(buf, area);
        const inner = block.inner(area);

        var y = inner.y;
        const max_y = inner.y + inner.height;

        // Current usage
        if (y < max_y) {
            var buf1: [128]u8 = undefined;
            const line1 = std.fmt.bufPrint(&buf1, "Current: {}", .{std.fmt.fmtIntSizeBin(self.alloc_stats.current_usage)}) catch "";
            buf.setString(inner.x, y, line1, .{ .fg = .{ .basic = .white }, .bold = true });
            y += 1;
        }

        // Peak usage
        if (y < max_y) {
            var buf2: [128]u8 = undefined;
            const line2 = std.fmt.bufPrint(&buf2, "Peak:    {}", .{std.fmt.fmtIntSizeBin(self.alloc_stats.peak_usage)}) catch "";
            buf.setString(inner.x, y, line2, .{ .fg = .{ .basic = .yellow } });
            y += 1;
        }

        // Total allocated
        if (y < max_y) {
            var buf3: [128]u8 = undefined;
            const line3 = std.fmt.bufPrint(&buf3, "Total Allocated: {}", .{std.fmt.fmtIntSizeBin(self.alloc_stats.total_allocated)}) catch "";
            buf.setString(inner.x, y, line3, .{ .fg = .{ .basic = .cyan } });
            y += 1;
        }

        // Total freed
        if (y < max_y) {
            var buf4: [128]u8 = undefined;
            const line4 = std.fmt.bufPrint(&buf4, "Total Freed:     {}", .{std.fmt.fmtIntSizeBin(self.alloc_stats.total_freed)}) catch "";
            buf.setString(inner.x, y, line4, .{ .fg = .{ .basic = .cyan } });
            y += 1;
        }

        // Allocation count
        if (y < max_y) {
            var buf5: [128]u8 = undefined;
            const line5 = std.fmt.bufPrint(&buf5, "Allocations: {}  Frees: {}", .{ self.alloc_stats.alloc_count, self.alloc_stats.free_count }) catch "";
            buf.setString(inner.x, y, line5, .{ .fg = .{ .basic = .green } });
            y += 1;
        }

        // Memory leak indicator
        if (y < max_y) {
            const leaked = self.alloc_stats.alloc_count -| self.alloc_stats.free_count;
            if (leaked > 0) {
                var buf6: [128]u8 = undefined;
                const line6 = std.fmt.bufPrint(&buf6, "⚠ Potential Leaks: {} allocations not freed", .{leaked}) catch "";
                buf.setString(inner.x, y, line6, .{ .fg = .{ .basic = .red }, .bold = true });
            }
        }
    }

    fn renderHotPaths(self: *const PerformanceProfiler, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Draw border
        const block = Block{
            .title = "Hot Paths",
            .borders = .all,
            .border_set = BoxSet.single,
        };
        block.render(buf, area);
        const inner = block.inner(area);

        var y = inner.y;
        const max_y = inner.y + inner.height;

        // Header
        if (y < max_y) {
            const header = "Name                      Calls      Total (ms)    Avg (ms)";
            buf.setString(inner.x, y, header, .{ .fg = .{ .basic = .white }, .bold = true });
            y += 1;
        }

        // Sort hot paths by total time (descending)
        const sorted_paths = try self.allocator.alloc(HotPath, self.hot_paths.items.len);
        defer self.allocator.free(sorted_paths);
        @memcpy(sorted_paths, self.hot_paths.items);

        std.mem.sort(HotPath, sorted_paths, {}, struct {
            fn lessThan(_: void, a: HotPath, b: HotPath) bool {
                return a.total_time_ms > b.total_time_ms;
            }
        }.lessThan);

        // Render top paths
        for (sorted_paths) |path| {
            if (y >= max_y) break;

            var line_buf: [256]u8 = undefined;
            const name_max = @min(path.name.len, 24);
            const name = path.name[0..name_max];

            const line = std.fmt.bufPrint(&line_buf, "{s: <24}  {: >8}  {: >12.2}  {: >10.3}", .{
                name,
                path.call_count,
                path.total_time_ms,
                path.avg_time_ms,
            }) catch "";

            // Color based on average time
            const style: Style = if (path.avg_time_ms > 10.0)
                .{ .fg = .{ .basic = .red } }
            else if (path.avg_time_ms > 5.0)
                .{ .fg = .{ .basic = .yellow } }
            else
                .{ .fg = .{ .basic = .green } };

            buf.setString(inner.x, y, line, style);
            y += 1;
        }

        // Empty state
        if (self.hot_paths.items.len == 0 and y < max_y) {
            buf.setString(inner.x, y, "No profiling data available", .{ .fg = .{ .basic = .yellow } });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "PerformanceProfiler: init and deinit" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    try testing.expectEqual(ProfilerMode.all, profiler.mode);
    try testing.expectEqual(@as(usize, 0), profiler.frame_history.items.len);
    try testing.expectEqual(@as(usize, 0), profiler.hot_paths.items.len);
}

test "PerformanceProfiler: recordFrame" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    const frame = FrameStats{
        .frame_time_ms = 16.7,
        .render_time_ms = 12.5,
        .event_time_ms = 2.1,
        .timestamp = 1234567890,
    };

    try profiler.recordFrame(frame);
    try testing.expectEqual(@as(usize, 1), profiler.frame_history.items.len);
    try testing.expectEqual(16.7, profiler.frame_history.items[0].frame_time_ms);
}

test "PerformanceProfiler: max history trimming" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    profiler.max_history = 5;

    // Add 10 frames
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const frame = FrameStats{
            .frame_time_ms = @floatFromInt(i),
            .render_time_ms = 0,
            .event_time_ms = 0,
            .timestamp = @intCast(i),
        };
        try profiler.recordFrame(frame);
    }

    // Should only keep last 5
    try testing.expectEqual(@as(usize, 5), profiler.frame_history.items.len);
    try testing.expectEqual(5.0, profiler.frame_history.items[0].frame_time_ms);
    try testing.expectEqual(9.0, profiler.frame_history.items[4].frame_time_ms);
}

test "PerformanceProfiler: updateMemory" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    const stats = AllocStats{
        .total_allocated = 1024 * 1024,
        .total_freed = 512 * 1024,
        .current_usage = 512 * 1024,
        .peak_usage = 768 * 1024,
        .alloc_count = 100,
        .free_count = 50,
    };

    profiler.updateMemory(stats);
    try testing.expectEqual(@as(usize, 1024 * 1024), profiler.alloc_stats.total_allocated);
    try testing.expectEqual(@as(usize, 512 * 1024), profiler.alloc_stats.current_usage);
}

test "PerformanceProfiler: recordHotPath" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    const path1 = HotPath{
        .name = "render_widgets",
        .call_count = 100,
        .total_time_ms = 250.0,
        .avg_time_ms = 2.5,
    };

    try profiler.recordHotPath(path1);
    try testing.expectEqual(@as(usize, 1), profiler.hot_paths.items.len);
    try testing.expectEqualStrings("render_widgets", profiler.hot_paths.items[0].name);
}

test "PerformanceProfiler: recordHotPath updates existing" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    const path1 = HotPath{
        .name = "render",
        .call_count = 100,
        .total_time_ms = 250.0,
        .avg_time_ms = 2.5,
    };

    try profiler.recordHotPath(path1);

    const path2 = HotPath{
        .name = "render",
        .call_count = 200,
        .total_time_ms = 500.0,
        .avg_time_ms = 2.5,
    };

    try profiler.recordHotPath(path2);

    // Should update, not add
    try testing.expectEqual(@as(usize, 1), profiler.hot_paths.items.len);
    try testing.expectEqual(@as(usize, 200), profiler.hot_paths.items[0].call_count);
    try testing.expectEqual(500.0, profiler.hot_paths.items[0].total_time_ms);
}

test "PerformanceProfiler: clearHotPaths" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    const path = HotPath{
        .name = "test",
        .call_count = 10,
        .total_time_ms = 100.0,
        .avg_time_ms = 10.0,
    };

    try profiler.recordHotPath(path);
    try testing.expectEqual(@as(usize, 1), profiler.hot_paths.items.len);

    profiler.clearHotPaths();
    try testing.expectEqual(@as(usize, 0), profiler.hot_paths.items.len);
}

test "PerformanceProfiler: setMode" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    profiler.setMode(.frame_times);
    try testing.expectEqual(ProfilerMode.frame_times, profiler.mode);

    profiler.setMode(.memory);
    try testing.expectEqual(ProfilerMode.memory, profiler.mode);

    profiler.setMode(.hot_paths);
    try testing.expectEqual(ProfilerMode.hot_paths, profiler.mode);
}

test "PerformanceProfiler: getAverageFPS" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    // Empty history
    try testing.expectEqual(0.0, profiler.getAverageFPS());

    // 60 FPS (16.67ms per frame)
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const frame = FrameStats{
            .frame_time_ms = 16.67,
            .render_time_ms = 0,
            .event_time_ms = 0,
            .timestamp = 0,
        };
        try profiler.recordFrame(frame);
    }

    const fps = profiler.getAverageFPS();
    try testing.expect(fps > 59.0 and fps < 61.0); // ~60 FPS
}

test "PerformanceProfiler: getMinMaxFrameTime" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    // Add varied frame times
    const times = [_]f64{ 16.0, 20.0, 12.0, 18.0, 25.0 };
    for (times) |time| {
        const frame = FrameStats{
            .frame_time_ms = time,
            .render_time_ms = 0,
            .event_time_ms = 0,
            .timestamp = 0,
        };
        try profiler.recordFrame(frame);
    }

    try testing.expectEqual(12.0, profiler.getMinFrameTime());
    try testing.expectEqual(25.0, profiler.getMaxFrameTime());
}

test "PerformanceProfiler: render frame_times mode" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    // Add some frames
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const frame = FrameStats{
            .frame_time_ms = 16.7,
            .render_time_ms = 12.0,
            .event_time_ms = 2.0,
            .timestamp = 0,
        };
        try profiler.recordFrame(frame);
    }

    profiler.setMode(.frame_times);
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Verify border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).char);

    // Verify title
    const title = buf.getString(1, 0, 17);
    defer allocator.free(title);
    try testing.expectEqualStrings("Frame Performance", title);
}

test "PerformanceProfiler: render memory mode" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    const stats = AllocStats{
        .total_allocated = 1024,
        .total_freed = 512,
        .current_usage = 512,
        .peak_usage = 768,
        .alloc_count = 10,
        .free_count = 5,
    };
    profiler.updateMemory(stats);
    profiler.setMode(.memory);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Verify border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).char);

    // Verify title
    const title = buf.getString(1, 0, 12);
    defer allocator.free(title);
    try testing.expectEqualStrings("Memory Usage", title);
}

test "PerformanceProfiler: render hot_paths mode" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    const path1 = HotPath{
        .name = "render_widgets",
        .call_count = 100,
        .total_time_ms = 250.0,
        .avg_time_ms = 2.5,
    };
    try profiler.recordHotPath(path1);

    const path2 = HotPath{
        .name = "handle_events",
        .call_count = 200,
        .total_time_ms = 150.0,
        .avg_time_ms = 0.75,
    };
    try profiler.recordHotPath(path2);

    profiler.setMode(.hot_paths);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Verify border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).char);

    // Verify title
    const title = buf.getString(1, 0, 9);
    defer allocator.free(title);
    try testing.expectEqualStrings("Hot Paths", title);
}

test "PerformanceProfiler: render all mode" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    profiler.setMode(.all);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // All three sections should render (verify borders at different y positions)
    // Top section (frame times)
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).char);

    // Middle section (memory) - starts at height/3
    const mid_y = 24 / 3;
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, mid_y).char);
}

test "PerformanceProfiler: zero-size area" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    // Should not crash
    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 10 });
}

test "PerformanceProfiler: empty data renders gracefully" {
    const allocator = testing.allocator;
    var profiler = PerformanceProfiler.init(allocator);
    defer profiler.deinit();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    // All modes should render without data
    profiler.setMode(.frame_times);
    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    buf.clear();
    profiler.setMode(.memory);
    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    buf.clear();
    profiler.setMode(.hot_paths);
    try profiler.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}
