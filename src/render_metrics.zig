const std = @import("std");
const Allocator = std.mem.Allocator;

/// Statistics for a single widget's render performance
pub const WidgetStats = struct {
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    count: u64,
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
};

/// Statistics aggregated across all widgets of the same type
pub const TypeStats = struct {
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    count: u64,
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    widget_count: u32,
};

/// Internal data for a single widget
const WidgetData = struct {
    widget_type: []const u8, // owned copy
    durations: std.ArrayList(u64),
    min_ns: u64,
    max_ns: u64,
    sum_ns: u64, // for average calculation

    fn deinit(self: *WidgetData, allocator: Allocator) void {
        allocator.free(self.widget_type);
        self.durations.deinit(allocator);
    }
};

/// Internal data for type aggregation
const TypeData = struct {
    durations: std.ArrayList(u64),
    min_ns: u64,
    max_ns: u64,
    sum_ns: u64,
    widget_ids: std.AutoHashMap(u32, void), // track unique widget IDs

    fn deinit(self: *TypeData, allocator: Allocator) void {
        self.durations.deinit(allocator);
        self.widget_ids.deinit();
    }
};

/// Metrics collector for tracking widget render performance
pub const MetricsCollector = struct {
    allocator: Allocator,
    widgets: std.AutoHashMap(u32, WidgetData),
    types: std.StringHashMap(TypeData),

    pub fn init(allocator: Allocator) MetricsCollector {
        return .{
            .allocator = allocator,
            .widgets = std.AutoHashMap(u32, WidgetData).init(allocator),
            .types = std.StringHashMap(TypeData).init(allocator),
        };
    }

    pub fn deinit(self: *MetricsCollector) void {
        // Free all widget data
        var widget_it = self.widgets.valueIterator();
        while (widget_it.next()) |widget_data| {
            widget_data.deinit(self.allocator);
        }
        self.widgets.deinit();

        // Free all type data
        var type_it = self.types.iterator();
        while (type_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.types.deinit();
    }

    pub fn recordRender(self: *MetricsCollector, widget_id: u32, widget_type: []const u8, duration_ns: u64) void {
        self.recordWidgetRender(widget_id, widget_type, duration_ns) catch |err| {
            std.debug.panic("recordRender failed: {}", .{err});
        };
        self.recordTypeRender(widget_id, widget_type, duration_ns) catch |err| {
            std.debug.panic("recordTypeRender failed: {}", .{err});
        };
    }

    fn recordWidgetRender(self: *MetricsCollector, widget_id: u32, widget_type: []const u8, duration_ns: u64) !void {
        const gop = try self.widgets.getOrPut(widget_id);
        if (!gop.found_existing) {
            // New widget - initialize
            const owned_type = try self.allocator.dupe(u8, widget_type);
            gop.value_ptr.* = .{
                .widget_type = owned_type,
                .durations = std.ArrayList(u64){},
                .min_ns = duration_ns,
                .max_ns = duration_ns,
                .sum_ns = duration_ns,
            };
            try gop.value_ptr.durations.append(self.allocator, duration_ns);
        } else {
            // Existing widget - update
            const data = gop.value_ptr;
            data.min_ns = @min(data.min_ns, duration_ns);
            data.max_ns = @max(data.max_ns, duration_ns);
            // Use saturating add to prevent overflow
            data.sum_ns = std.math.add(u64, data.sum_ns, duration_ns) catch std.math.maxInt(u64);
            try data.durations.append(self.allocator, duration_ns);
        }
    }

    fn recordTypeRender(self: *MetricsCollector, widget_id: u32, widget_type: []const u8, duration_ns: u64) !void {
        const gop = try self.types.getOrPut(widget_type);
        if (!gop.found_existing) {
            // New type - initialize
            const owned_type = try self.allocator.dupe(u8, widget_type);
            gop.key_ptr.* = owned_type;
            gop.value_ptr.* = .{
                .durations = std.ArrayList(u64){},
                .min_ns = duration_ns,
                .max_ns = duration_ns,
                .sum_ns = duration_ns,
                .widget_ids = std.AutoHashMap(u32, void).init(self.allocator),
            };
            try gop.value_ptr.durations.append(self.allocator, duration_ns);
            try gop.value_ptr.widget_ids.put(widget_id, {});
        } else {
            // Existing type - update
            const data = gop.value_ptr;
            data.min_ns = @min(data.min_ns, duration_ns);
            data.max_ns = @max(data.max_ns, duration_ns);
            data.sum_ns = std.math.add(u64, data.sum_ns, duration_ns) catch std.math.maxInt(u64);
            try data.durations.append(self.allocator, duration_ns);
            try data.widget_ids.put(widget_id, {}); // Track unique widget
        }
    }

    pub fn getStats(self: *MetricsCollector, widget_id: u32) ?WidgetStats {
        const widget_data = self.widgets.get(widget_id) orelse return null;
        return self.calculateStats(widget_data.durations.items, widget_data.min_ns, widget_data.max_ns, widget_data.sum_ns);
    }

    pub fn getTypeStats(self: *MetricsCollector, widget_type: []const u8) ?TypeStats {
        const type_data = self.types.get(widget_type) orelse return null;
        const base_stats = self.calculateStats(type_data.durations.items, type_data.min_ns, type_data.max_ns, type_data.sum_ns);
        return .{
            .min_ns = base_stats.min_ns,
            .max_ns = base_stats.max_ns,
            .avg_ns = base_stats.avg_ns,
            .count = base_stats.count,
            .p50_ns = base_stats.p50_ns,
            .p95_ns = base_stats.p95_ns,
            .p99_ns = base_stats.p99_ns,
            .widget_count = @intCast(type_data.widget_ids.count()),
        };
    }

    fn calculateStats(self: *MetricsCollector, durations: []const u64, min_ns: u64, max_ns: u64, sum_ns: u64) WidgetStats {
        const count = durations.len;
        if (count == 0) {
            return .{
                .min_ns = 0,
                .max_ns = 0,
                .avg_ns = 0,
                .count = 0,
                .p50_ns = 0,
                .p95_ns = 0,
                .p99_ns = 0,
            };
        }

        const avg_ns = sum_ns / count;

        // Calculate percentiles - need to sort a copy
        var sorted = std.ArrayList(u64){};
        defer sorted.deinit(self.allocator);
        sorted.appendSlice(self.allocator, durations) catch unreachable;
        std.mem.sort(u64, sorted.items, {}, std.sort.asc(u64));

        return .{
            .min_ns = min_ns,
            .max_ns = max_ns,
            .avg_ns = avg_ns,
            .count = count,
            .p50_ns = percentile(sorted.items, 50),
            .p95_ns = percentile(sorted.items, 95),
            .p99_ns = percentile(sorted.items, 99),
        };
    }

    pub fn reset(self: *MetricsCollector) void {
        // Free all widget data
        var widget_it = self.widgets.valueIterator();
        while (widget_it.next()) |widget_data| {
            widget_data.deinit(self.allocator);
        }
        self.widgets.clearRetainingCapacity();

        // Free all type data
        var type_it = self.types.iterator();
        while (type_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.types.clearRetainingCapacity();
    }

    pub fn resetWidget(self: *MetricsCollector, widget_id: u32) void {
        var widget_data = self.widgets.fetchRemove(widget_id) orelse return;
        const widget_type = widget_data.value.widget_type;

        // Remove widget from type tracking
        if (self.types.getPtr(widget_type)) |type_data| {
            _ = type_data.widget_ids.remove(widget_id);

            // Rebuild type stats by removing this widget's durations
            // This is complex - need to rebuild from remaining widgets
            self.rebuildTypeStats(widget_type);
        }

        widget_data.value.deinit(self.allocator);
    }

    fn rebuildTypeStats(self: *MetricsCollector, widget_type: []const u8) void {
        const type_data = self.types.getPtr(widget_type) orelse return;

        // If no widgets of this type remain, remove the type entry
        if (type_data.widget_ids.count() == 0) {
            var entry = self.types.fetchRemove(widget_type).?;
            self.allocator.free(entry.key);
            entry.value.deinit(self.allocator);
            return;
        }

        // Rebuild durations from remaining widgets
        type_data.durations.clearRetainingCapacity();
        type_data.sum_ns = 0;
        type_data.min_ns = std.math.maxInt(u64);
        type_data.max_ns = 0;

        var widget_id_it = type_data.widget_ids.keyIterator();
        while (widget_id_it.next()) |widget_id_ptr| {
            if (self.widgets.get(widget_id_ptr.*)) |widget_data| {
                if (std.mem.eql(u8, widget_data.widget_type, widget_type)) {
                    for (widget_data.durations.items) |duration| {
                        type_data.durations.append(self.allocator, duration) catch unreachable;
                        type_data.min_ns = @min(type_data.min_ns, duration);
                        type_data.max_ns = @max(type_data.max_ns, duration);
                        type_data.sum_ns = std.math.add(u64, type_data.sum_ns, duration) catch std.math.maxInt(u64);
                    }
                }
            }
        }
    }
};

/// Calculate percentile from sorted array
fn percentile(sorted: []const u64, p: u8) u64 {
    if (sorted.len == 0) return 0;
    if (sorted.len == 1) return sorted[0];

    // Formula: index = (percentile * (count - 1)) / 100
    const index = (@as(u64, p) * (sorted.len - 1)) / 100;
    return sorted[@intCast(index)];
}

// ============================================================================
// TESTS
// ============================================================================

test "MetricsCollector init and deinit" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();
}

test "record single render - stats should have min==max==avg" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;
    const duration_ns: u64 = 1000;

    collector.recordRender(widget_id, "Button", duration_ns);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(duration_ns, stats.min_ns);
    try std.testing.expectEqual(duration_ns, stats.max_ns);
    try std.testing.expectEqual(duration_ns, stats.avg_ns);
    try std.testing.expectEqual(@as(u64, 1), stats.count);
    try std.testing.expectEqual(duration_ns, stats.p50_ns);
    try std.testing.expectEqual(duration_ns, stats.p95_ns);
    try std.testing.expectEqual(duration_ns, stats.p99_ns);
}

test "record multiple renders - stats should update correctly" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // Record 5 renders: 100, 200, 300, 400, 500
    collector.recordRender(widget_id, "Button", 100);
    collector.recordRender(widget_id, "Button", 200);
    collector.recordRender(widget_id, "Button", 300);
    collector.recordRender(widget_id, "Button", 400);
    collector.recordRender(widget_id, "Button", 500);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 300), stats.avg_ns); // (100+200+300+400+500)/5 = 300
    try std.testing.expectEqual(@as(u64, 5), stats.count);
    try std.testing.expectEqual(@as(u64, 300), stats.p50_ns); // median
}

test "multiple widgets - isolation" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Label", 200);
    collector.recordRender(3, "Input", 300);

    const stats1 = collector.getStats(1) orelse return error.Stats1NotFound;
    const stats2 = collector.getStats(2) orelse return error.Stats2NotFound;
    const stats3 = collector.getStats(3) orelse return error.Stats3NotFound;

    try std.testing.expectEqual(@as(u64, 100), stats1.min_ns);
    try std.testing.expectEqual(@as(u64, 200), stats2.min_ns);
    try std.testing.expectEqual(@as(u64, 300), stats3.min_ns);
}

test "percentile calculation - p50" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // Odd number of samples: 1, 2, 3, 4, 5 -> median = 3
    collector.recordRender(widget_id, "Button", 1);
    collector.recordRender(widget_id, "Button", 2);
    collector.recordRender(widget_id, "Button", 3);
    collector.recordRender(widget_id, "Button", 4);
    collector.recordRender(widget_id, "Button", 5);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 3), stats.p50_ns);
}

test "percentile calculation - p95" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // 20 samples: 1..20 -> p95 should be around 19
    var i: u64 = 1;
    while (i <= 20) : (i += 1) {
        collector.recordRender(widget_id, "Button", i);
    }

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    // p95 of 20 samples = 95th percentile index = ceil(20 * 0.95) = 19
    try std.testing.expectEqual(@as(u64, 19), stats.p95_ns);
}

test "percentile calculation - p99" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // 100 samples: 1..100 -> p99 should be 99
    var i: u64 = 1;
    while (i <= 100) : (i += 1) {
        collector.recordRender(widget_id, "Button", i);
    }

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    // p99 of 100 samples = 99th percentile index = 99
    try std.testing.expectEqual(@as(u64, 99), stats.p99_ns);
}

test "percentile calculation - unsorted input" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // Insert in random order: 500, 100, 300, 200, 400
    collector.recordRender(widget_id, "Button", 500);
    collector.recordRender(widget_id, "Button", 100);
    collector.recordRender(widget_id, "Button", 300);
    collector.recordRender(widget_id, "Button", 200);
    collector.recordRender(widget_id, "Button", 400);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 300), stats.p50_ns); // median of sorted [100,200,300,400,500]
}

test "average calculation correctness" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // Sum = 1000 + 2000 + 3000 = 6000, avg = 2000
    collector.recordRender(widget_id, "Button", 1000);
    collector.recordRender(widget_id, "Button", 2000);
    collector.recordRender(widget_id, "Button", 3000);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 2000), stats.avg_ns);
}

test "type aggregation - single type multiple widgets" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // 3 buttons with different IDs
    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Button", 200);
    collector.recordRender(3, "Button", 300);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 300), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 200), type_stats.avg_ns); // (100+200+300)/3
    try std.testing.expectEqual(@as(u64, 3), type_stats.count);
    try std.testing.expectEqual(@as(u32, 3), type_stats.widget_count);
}

test "type aggregation - mixed types no cross-contamination" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Button", 200);
    collector.recordRender(3, "Label", 300);
    collector.recordRender(4, "Label", 400);

    const button_stats = collector.getTypeStats("Button") orelse return error.ButtonStatsNotFound;
    const label_stats = collector.getTypeStats("Label") orelse return error.LabelStatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), button_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 200), button_stats.max_ns);
    try std.testing.expectEqual(@as(u32, 2), button_stats.widget_count);

    try std.testing.expectEqual(@as(u64, 300), label_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 400), label_stats.max_ns);
    try std.testing.expectEqual(@as(u32, 2), label_stats.widget_count);
}

test "type aggregation - widget count tracking" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // 5 unique buttons
    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Button", 100);
    collector.recordRender(3, "Button", 100);
    collector.recordRender(4, "Button", 100);
    collector.recordRender(5, "Button", 100);

    // Widget 1 renders again - should not increase widget_count
    collector.recordRender(1, "Button", 150);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u32, 5), type_stats.widget_count); // 5 unique widgets
    try std.testing.expectEqual(@as(u64, 6), type_stats.count); // 6 total renders
}

test "type aggregation - multiple renders per widget" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Widget 1: 100, 200
    collector.recordRender(1, "Button", 100);
    collector.recordRender(1, "Button", 200);

    // Widget 2: 300, 400
    collector.recordRender(2, "Button", 300);
    collector.recordRender(2, "Button", 400);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 400), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 250), type_stats.avg_ns); // (100+200+300+400)/4
    try std.testing.expectEqual(@as(u64, 4), type_stats.count);
    try std.testing.expectEqual(@as(u32, 2), type_stats.widget_count);
}

test "reset all metrics" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Label", 200);

    collector.reset();

    // After reset, stats should return null
    const stats1 = collector.getStats(1);
    const stats2 = collector.getStats(2);
    const type_stats = collector.getTypeStats("Button");

    try std.testing.expectEqual(@as(?WidgetStats, null), stats1);
    try std.testing.expectEqual(@as(?WidgetStats, null), stats2);
    try std.testing.expectEqual(@as(?TypeStats, null), type_stats);
}

test "reset all then record again" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);
    collector.reset();
    collector.recordRender(1, "Button", 200);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    // Should only have the new recording
    try std.testing.expectEqual(@as(u64, 200), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 200), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 1), stats.count);
}

test "reset specific widget" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Button", 200);

    collector.resetWidget(1);

    // Widget 1 should have no stats
    const stats1 = collector.getStats(1);
    try std.testing.expectEqual(@as(?WidgetStats, null), stats1);

    // Widget 2 should still have stats
    const stats2 = collector.getStats(2) orelse return error.Stats2NotFound;
    try std.testing.expectEqual(@as(u64, 200), stats2.min_ns);
}

test "reset specific widget affects type stats" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Button", 200);

    collector.resetWidget(1);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;

    // Should only count widget 2 now
    try std.testing.expectEqual(@as(u64, 200), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 200), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 1), type_stats.count);
    try std.testing.expectEqual(@as(u32, 1), type_stats.widget_count);
}

test "query non-existent widget returns null" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);

    const stats = collector.getStats(999);
    try std.testing.expectEqual(@as(?WidgetStats, null), stats);
}

test "query non-existent type returns null" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 100);

    const type_stats = collector.getTypeStats("NonExistent");
    try std.testing.expectEqual(@as(?TypeStats, null), type_stats);
}

test "query empty collector returns null" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const stats = collector.getStats(1);
    const type_stats = collector.getTypeStats("Button");

    try std.testing.expectEqual(@as(?WidgetStats, null), stats);
    try std.testing.expectEqual(@as(?TypeStats, null), type_stats);
}

test "zero duration renders" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 0);
    collector.recordRender(1, "Button", 100);
    collector.recordRender(1, "Button", 0);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 0), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 100), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 33), stats.avg_ns); // (0+100+0)/3 = 33 (truncated)
    try std.testing.expectEqual(@as(u64, 3), stats.count);
}

test "very large duration values" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const max_u64 = std.math.maxInt(u64);
    const large_val = max_u64 - 1000;

    collector.recordRender(1, "Button", large_val);
    collector.recordRender(1, "Button", max_u64);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    try std.testing.expectEqual(large_val, stats.min_ns);
    try std.testing.expectEqual(max_u64, stats.max_ns);
    try std.testing.expectEqual(@as(u64, 2), stats.count);
}

test "memory leak check - init and deinit" {
    var collector = MetricsCollector.init(std.testing.allocator);
    collector.recordRender(1, "Button", 100);
    collector.recordRender(2, "Label", 200);
    collector.deinit();
    // If there's a leak, testing.allocator will catch it
}

test "memory leak check - reset actually frees memory" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Record some data
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        collector.recordRender(i, "Button", 100);
    }

    // Reset should free internal allocations
    collector.reset();

    // Record again
    collector.recordRender(1, "Button", 100);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 1), stats.count);
}

test "stress test - large number of widgets" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // 1000 widgets
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        collector.recordRender(i, "Button", i * 100);
    }

    // Verify some samples
    const stats0 = collector.getStats(0) orelse return error.Stats0NotFound;
    try std.testing.expectEqual(@as(u64, 0), stats0.min_ns);

    const stats999 = collector.getStats(999) orelse return error.Stats999NotFound;
    try std.testing.expectEqual(@as(u64, 99900), stats999.min_ns);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u32, 1000), type_stats.widget_count);
    try std.testing.expectEqual(@as(u64, 1000), type_stats.count);
}

test "stress test - many renders per widget" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // 10000 renders for single widget
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        collector.recordRender(widget_id, "Button", i);
    }

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 0), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 9999), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 10000), stats.count);
}

test "percentile with even number of samples" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    // Even number: 1, 2, 3, 4 -> median should be (2+3)/2 = 2.5, but we use integer so 2 or 3
    collector.recordRender(widget_id, "Button", 1);
    collector.recordRender(widget_id, "Button", 2);
    collector.recordRender(widget_id, "Button", 3);
    collector.recordRender(widget_id, "Button", 4);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    // p50 for even samples can be either middle value or average of two middle
    // Accept either 2 or 3 as valid median
    try std.testing.expect(stats.p50_ns == 2 or stats.p50_ns == 3);
}

test "single data point - all percentiles equal" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordRender(1, "Button", 1234);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 1234), stats.p50_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.p95_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.p99_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.avg_ns);
}

test "type stats percentiles with mixed widget renders" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Widget 1: renders at 100, 200, 300
    collector.recordRender(1, "Button", 100);
    collector.recordRender(1, "Button", 200);
    collector.recordRender(1, "Button", 300);

    // Widget 2: renders at 400, 500
    collector.recordRender(2, "Button", 400);
    collector.recordRender(2, "Button", 500);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;

    // All renders: 100, 200, 300, 400, 500 (5 samples)
    try std.testing.expectEqual(@as(u64, 100), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 300), type_stats.p50_ns); // median
    try std.testing.expectEqual(@as(u64, 5), type_stats.count);
}

test "duplicate widget IDs but different types should be separate" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Same widget ID but different types - should track separately
    collector.recordRender(1, "Button", 100);
    collector.recordRender(1, "Label", 200);

    // Widget stats should be type-agnostic (last type wins or error?)
    // Type stats should be separate
    const button_stats = collector.getTypeStats("Button") orelse return error.ButtonStatsNotFound;
    const label_stats = collector.getTypeStats("Label") orelse return error.LabelStatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), button_stats.min_ns);
    try std.testing.expectEqual(@as(u32, 1), button_stats.widget_count);

    try std.testing.expectEqual(@as(u64, 200), label_stats.min_ns);
    try std.testing.expectEqual(@as(u32, 1), label_stats.widget_count);
}

test "average with potential overflow prevention" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const large_val: u64 = std.math.maxInt(u64) / 2;

    // Two very large values - sum would overflow u64
    collector.recordRender(1, "Button", large_val);
    collector.recordRender(1, "Button", large_val);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    // Average should still be calculated correctly (implementation should handle overflow)
    try std.testing.expectEqual(@as(u64, 2), stats.count);
    try std.testing.expect(stats.avg_ns >= large_val - 1 and stats.avg_ns <= large_val + 1);
}
