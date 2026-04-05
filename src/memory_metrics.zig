const std = @import("std");
const Allocator = std.mem.Allocator;

/// Memory statistics for a single widget
pub const WidgetMemStats = struct {
    peak_bytes: usize,
    current_bytes: usize,
    total_allocs: u64,
    total_frees: u64,
    active_allocs: u64,
};

/// Memory statistics aggregated across all widgets of the same type
pub const TypeMemStats = struct {
    peak_bytes: usize,
    current_bytes: usize,
    total_allocs: u64,
    total_frees: u64,
    active_allocs: u64,
    widget_count: u32,
};

/// Internal data for a single widget's memory tracking
const WidgetMemData = struct {
    widget_type: []const u8, // owned copy
    peak_bytes: usize,
    current_bytes: usize,
    total_allocs: u64,
    total_frees: u64,

    fn deinit(self: *WidgetMemData, allocator: Allocator) void {
        allocator.free(self.widget_type);
    }
};

/// Internal data for type memory aggregation
const TypeMemData = struct {
    peak_bytes: usize,
    current_bytes: usize,
    total_allocs: u64,
    total_frees: u64,
    widget_ids: std.AutoHashMap(u32, void), // track unique widget IDs

    fn deinit(self: *TypeMemData) void {
        self.widget_ids.deinit();
    }
};

/// Memory metrics collector for tracking widget allocation patterns
pub const MemoryMetricsCollector = struct {
    allocator: Allocator,
    widgets: std.AutoHashMap(u32, WidgetMemData),
    types: std.StringHashMap(TypeMemData),

    pub fn init(allocator: Allocator) MemoryMetricsCollector {
        return .{
            .allocator = allocator,
            .widgets = std.AutoHashMap(u32, WidgetMemData).init(allocator),
            .types = std.StringHashMap(TypeMemData).init(allocator),
        };
    }

    pub fn deinit(self: *MemoryMetricsCollector) void {
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
            entry.value_ptr.deinit();
        }
        self.types.deinit();
    }

    /// Record memory allocation for a widget
    pub fn recordAlloc(self: *MemoryMetricsCollector, widget_id: u32, widget_type: []const u8, bytes: usize) void {
        self.recordWidgetAlloc(widget_id, widget_type, bytes) catch |err| {
            std.debug.panic("recordAlloc failed: {}", .{err});
        };
        self.recordTypeAlloc(widget_id, widget_type, bytes) catch |err| {
            std.debug.panic("recordTypeAlloc failed: {}", .{err});
        };
    }

    /// Record memory deallocation for a widget
    pub fn recordFree(self: *MemoryMetricsCollector, widget_id: u32, widget_type: []const u8, bytes: usize) void {
        self.recordWidgetFree(widget_id, widget_type, bytes) catch |err| {
            std.debug.panic("recordFree failed: {}", .{err});
        };
        self.recordTypeFree(widget_id, widget_type, bytes) catch |err| {
            std.debug.panic("recordTypeFree failed: {}", .{err});
        };
    }

    fn recordWidgetAlloc(self: *MemoryMetricsCollector, widget_id: u32, widget_type: []const u8, bytes: usize) !void {
        const gop = try self.widgets.getOrPut(widget_id);
        if (!gop.found_existing) {
            // New widget - initialize
            const owned_type = try self.allocator.dupe(u8, widget_type);
            gop.value_ptr.* = .{
                .widget_type = owned_type,
                .peak_bytes = bytes,
                .current_bytes = bytes,
                .total_allocs = 1,
                .total_frees = 0,
            };
        } else {
            // Existing widget - update
            const data = gop.value_ptr;
            data.current_bytes = std.math.add(usize, data.current_bytes, bytes) catch std.math.maxInt(usize);
            data.peak_bytes = @max(data.peak_bytes, data.current_bytes);
            data.total_allocs = std.math.add(u64, data.total_allocs, 1) catch std.math.maxInt(u64);
        }
    }

    fn recordWidgetFree(self: *MemoryMetricsCollector, widget_id: u32, widget_type: []const u8, bytes: usize) !void {
        const gop = try self.widgets.getOrPut(widget_id);
        if (!gop.found_existing) {
            // Widget not tracked yet - initialize with free
            const owned_type = try self.allocator.dupe(u8, widget_type);
            gop.value_ptr.* = .{
                .widget_type = owned_type,
                .peak_bytes = 0,
                .current_bytes = 0,
                .total_allocs = 0,
                .total_frees = 1,
            };
        } else {
            // Existing widget - update
            const data = gop.value_ptr;
            if (data.current_bytes >= bytes) {
                data.current_bytes -= bytes;
            } else {
                data.current_bytes = 0; // Prevent underflow
            }
            data.total_frees = std.math.add(u64, data.total_frees, 1) catch std.math.maxInt(u64);
        }
    }

    fn recordTypeAlloc(self: *MemoryMetricsCollector, widget_id: u32, widget_type: []const u8, bytes: usize) !void {
        const gop = try self.types.getOrPut(widget_type);
        if (!gop.found_existing) {
            // New type - initialize
            const owned_type = try self.allocator.dupe(u8, widget_type);
            gop.key_ptr.* = owned_type;
            gop.value_ptr.* = .{
                .peak_bytes = bytes,
                .current_bytes = bytes,
                .total_allocs = 1,
                .total_frees = 0,
                .widget_ids = std.AutoHashMap(u32, void).init(self.allocator),
            };
            try gop.value_ptr.widget_ids.put(widget_id, {});
        } else {
            // Existing type - update
            const data = gop.value_ptr;
            data.current_bytes = std.math.add(usize, data.current_bytes, bytes) catch std.math.maxInt(usize);
            data.peak_bytes = @max(data.peak_bytes, data.current_bytes);
            data.total_allocs = std.math.add(u64, data.total_allocs, 1) catch std.math.maxInt(u64);
            try data.widget_ids.put(widget_id, {}); // Track unique widget
        }
    }

    fn recordTypeFree(self: *MemoryMetricsCollector, widget_id: u32, widget_type: []const u8, bytes: usize) !void {
        const gop = try self.types.getOrPut(widget_type);
        if (!gop.found_existing) {
            // Type not tracked yet - initialize with free
            const owned_type = try self.allocator.dupe(u8, widget_type);
            gop.key_ptr.* = owned_type;
            gop.value_ptr.* = .{
                .peak_bytes = 0,
                .current_bytes = 0,
                .total_allocs = 0,
                .total_frees = 1,
                .widget_ids = std.AutoHashMap(u32, void).init(self.allocator),
            };
            try gop.value_ptr.widget_ids.put(widget_id, {});
        } else {
            // Existing type - update
            const data = gop.value_ptr;
            if (data.current_bytes >= bytes) {
                data.current_bytes -= bytes;
            } else {
                data.current_bytes = 0; // Prevent underflow
            }
            data.total_frees = std.math.add(u64, data.total_frees, 1) catch std.math.maxInt(u64);
            try data.widget_ids.put(widget_id, {}); // Track unique widget
        }
    }

    pub fn getStats(self: *MemoryMetricsCollector, widget_id: u32) ?WidgetMemStats {
        const widget_data = self.widgets.get(widget_id) orelse return null;
        const active_allocs = if (widget_data.total_allocs >= widget_data.total_frees)
            widget_data.total_allocs - widget_data.total_frees
        else
            0;
        return .{
            .peak_bytes = widget_data.peak_bytes,
            .current_bytes = widget_data.current_bytes,
            .total_allocs = widget_data.total_allocs,
            .total_frees = widget_data.total_frees,
            .active_allocs = active_allocs,
        };
    }

    pub fn getTypeStats(self: *MemoryMetricsCollector, widget_type: []const u8) ?TypeMemStats {
        const type_data = self.types.get(widget_type) orelse return null;
        const active_allocs = if (type_data.total_allocs >= type_data.total_frees)
            type_data.total_allocs - type_data.total_frees
        else
            0;
        return .{
            .peak_bytes = type_data.peak_bytes,
            .current_bytes = type_data.current_bytes,
            .total_allocs = type_data.total_allocs,
            .total_frees = type_data.total_frees,
            .active_allocs = active_allocs,
            .widget_count = @intCast(type_data.widget_ids.count()),
        };
    }

    pub fn reset(self: *MemoryMetricsCollector) void {
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
            entry.value_ptr.deinit();
        }
        self.types.clearRetainingCapacity();
    }

    pub fn resetWidget(self: *MemoryMetricsCollector, widget_id: u32) void {
        var widget_data = self.widgets.fetchRemove(widget_id) orelse return;
        const widget_type = widget_data.value.widget_type;

        // Remove widget from type tracking
        if (self.types.getPtr(widget_type)) |type_data| {
            _ = type_data.widget_ids.remove(widget_id);

            // If no widgets of this type remain, remove the type entry
            if (type_data.widget_ids.count() == 0) {
                var entry = self.types.fetchRemove(widget_type).?;
                self.allocator.free(entry.key);
                entry.value.deinit();
            }
        }

        widget_data.value.deinit(self.allocator);
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "MemoryMetricsCollector init and deinit" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();
}

test "record single alloc" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;
    const bytes: usize = 1024;

    collector.recordAlloc(widget_id, "Button", bytes);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(bytes, stats.peak_bytes);
    try std.testing.expectEqual(bytes, stats.current_bytes);
    try std.testing.expectEqual(@as(u64, 1), stats.total_allocs);
    try std.testing.expectEqual(@as(u64, 0), stats.total_frees);
    try std.testing.expectEqual(@as(u64, 1), stats.active_allocs);
}

test "record alloc then free" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;
    const bytes: usize = 1024;

    collector.recordAlloc(widget_id, "Button", bytes);
    collector.recordFree(widget_id, "Button", bytes);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(bytes, stats.peak_bytes); // Peak remains
    try std.testing.expectEqual(@as(usize, 0), stats.current_bytes); // Current drops to 0
    try std.testing.expectEqual(@as(u64, 1), stats.total_allocs);
    try std.testing.expectEqual(@as(u64, 1), stats.total_frees);
    try std.testing.expectEqual(@as(u64, 0), stats.active_allocs);
}

test "multiple allocs - peak tracking" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    collector.recordAlloc(widget_id, "Button", 100);
    collector.recordAlloc(widget_id, "Button", 200);
    collector.recordAlloc(widget_id, "Button", 300);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(usize, 600), stats.peak_bytes); // 100+200+300
    try std.testing.expectEqual(@as(usize, 600), stats.current_bytes);
    try std.testing.expectEqual(@as(u64, 3), stats.total_allocs);
}

test "alloc and partial free - current bytes tracking" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    collector.recordAlloc(widget_id, "Button", 1000);
    collector.recordFree(widget_id, "Button", 300);

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(usize, 1000), stats.peak_bytes);
    try std.testing.expectEqual(@as(usize, 700), stats.current_bytes); // 1000-300
    try std.testing.expectEqual(@as(u64, 1), stats.total_allocs);
    try std.testing.expectEqual(@as(u64, 1), stats.total_frees);
}

test "multiple widgets - isolation" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Label", 200);
    collector.recordAlloc(3, "Input", 300);

    const stats1 = collector.getStats(1) orelse return error.Stats1NotFound;
    const stats2 = collector.getStats(2) orelse return error.Stats2NotFound;
    const stats3 = collector.getStats(3) orelse return error.Stats3NotFound;

    try std.testing.expectEqual(@as(usize, 100), stats1.current_bytes);
    try std.testing.expectEqual(@as(usize, 200), stats2.current_bytes);
    try std.testing.expectEqual(@as(usize, 300), stats3.current_bytes);
}

test "type aggregation - single type multiple widgets" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Button", 200);
    collector.recordAlloc(3, "Button", 300);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;

    try std.testing.expectEqual(@as(usize, 600), type_stats.peak_bytes); // 100+200+300
    try std.testing.expectEqual(@as(usize, 600), type_stats.current_bytes);
    try std.testing.expectEqual(@as(u64, 3), type_stats.total_allocs);
    try std.testing.expectEqual(@as(u32, 3), type_stats.widget_count);
}

test "type aggregation - mixed types no cross-contamination" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Button", 200);
    collector.recordAlloc(3, "Label", 300);
    collector.recordAlloc(4, "Label", 400);

    const button_stats = collector.getTypeStats("Button") orelse return error.ButtonStatsNotFound;
    const label_stats = collector.getTypeStats("Label") orelse return error.LabelStatsNotFound;

    try std.testing.expectEqual(@as(usize, 300), button_stats.current_bytes); // 100+200
    try std.testing.expectEqual(@as(u32, 2), button_stats.widget_count);

    try std.testing.expectEqual(@as(usize, 700), label_stats.current_bytes); // 300+400
    try std.testing.expectEqual(@as(u32, 2), label_stats.widget_count);
}

test "type stats with allocs and frees" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Button", 200);
    collector.recordFree(1, "Button", 50);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;

    try std.testing.expectEqual(@as(usize, 300), type_stats.peak_bytes); // 100+200 at peak
    try std.testing.expectEqual(@as(usize, 250), type_stats.current_bytes); // (100-50)+200
    try std.testing.expectEqual(@as(u64, 2), type_stats.total_allocs);
    try std.testing.expectEqual(@as(u64, 1), type_stats.total_frees);
    try std.testing.expectEqual(@as(u64, 1), type_stats.active_allocs);
}

test "reset all metrics" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Label", 200);

    collector.reset();

    const stats1 = collector.getStats(1);
    const stats2 = collector.getStats(2);
    const type_stats = collector.getTypeStats("Button");

    try std.testing.expectEqual(@as(?WidgetMemStats, null), stats1);
    try std.testing.expectEqual(@as(?WidgetMemStats, null), stats2);
    try std.testing.expectEqual(@as(?TypeMemStats, null), type_stats);
}

test "reset specific widget" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Button", 200);

    collector.resetWidget(1);

    const stats1 = collector.getStats(1);
    try std.testing.expectEqual(@as(?WidgetMemStats, null), stats1);

    const stats2 = collector.getStats(2) orelse return error.Stats2NotFound;
    try std.testing.expectEqual(@as(usize, 200), stats2.current_bytes);

    // Type stats should still exist but only count widget 2
    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u32, 1), type_stats.widget_count);
}

test "reset widget removes type when last widget" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);

    collector.resetWidget(1);

    const type_stats = collector.getTypeStats("Button");
    try std.testing.expectEqual(@as(?TypeMemStats, null), type_stats);
}

test "query non-existent widget returns null" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);

    const stats = collector.getStats(999);
    try std.testing.expectEqual(@as(?WidgetMemStats, null), stats);
}

test "query non-existent type returns null" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);

    const type_stats = collector.getTypeStats("NonExistent");
    try std.testing.expectEqual(@as(?TypeMemStats, null), type_stats);
}

test "zero byte allocations" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 0);
    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(1, "Button", 0);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(usize, 100), stats.peak_bytes);
    try std.testing.expectEqual(@as(usize, 100), stats.current_bytes);
    try std.testing.expectEqual(@as(u64, 3), stats.total_allocs);
}

test "free more than allocated - underflow prevention" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordFree(1, "Button", 200); // Free more than allocated

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(usize, 0), stats.current_bytes); // Should not underflow
    try std.testing.expectEqual(@as(u64, 1), stats.total_allocs);
    try std.testing.expectEqual(@as(u64, 1), stats.total_frees);
}

test "free before alloc - edge case" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Free before any alloc - should create entry with zero state
    collector.recordFree(1, "Button", 100);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(usize, 0), stats.peak_bytes);
    try std.testing.expectEqual(@as(usize, 0), stats.current_bytes);
    try std.testing.expectEqual(@as(u64, 0), stats.total_allocs);
    try std.testing.expectEqual(@as(u64, 1), stats.total_frees);
}

test "peak bytes tracking with fluctuations" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    collector.recordAlloc(widget_id, "Button", 1000); // current: 1000, peak: 1000
    collector.recordAlloc(widget_id, "Button", 500); // current: 1500, peak: 1500
    collector.recordFree(widget_id, "Button", 800); // current: 700, peak: 1500
    collector.recordAlloc(widget_id, "Button", 300); // current: 1000, peak: 1500
    collector.recordFree(widget_id, "Button", 500); // current: 500, peak: 1500

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(usize, 1500), stats.peak_bytes); // Peak should be highest point
    try std.testing.expectEqual(@as(usize, 500), stats.current_bytes);
}

test "very large allocation values" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const max_usize = std.math.maxInt(usize);
    const large_val = max_usize - 1000;

    collector.recordAlloc(1, "Button", large_val);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;

    try std.testing.expectEqual(large_val, stats.peak_bytes);
    try std.testing.expectEqual(large_val, stats.current_bytes);
}

test "memory leak check - init and deinit" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Label", 200);
    collector.deinit();
}

test "memory leak check - reset frees memory" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        collector.recordAlloc(i, "Button", 100);
    }

    collector.reset();

    collector.recordAlloc(1, "Button", 100);

    const stats = collector.getStats(1) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 1), stats.total_allocs);
}

test "stress test - large number of widgets" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        collector.recordAlloc(i, "Button", i * 100);
    }

    const stats0 = collector.getStats(0) orelse return error.Stats0NotFound;
    try std.testing.expectEqual(@as(usize, 0), stats0.current_bytes);

    const stats999 = collector.getStats(999) orelse return error.Stats999NotFound;
    try std.testing.expectEqual(@as(usize, 99900), stats999.current_bytes);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u32, 1000), type_stats.widget_count);
}

test "stress test - many allocs and frees per widget" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    var i: u64 = 0;
    while (i < 5000) : (i += 1) {
        collector.recordAlloc(widget_id, "Button", 100);
    }

    while (i < 10000) : (i += 1) {
        collector.recordFree(widget_id, "Button", 100);
    }

    const stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 5000), stats.total_allocs);
    try std.testing.expectEqual(@as(u64, 5000), stats.total_frees);
    try std.testing.expectEqual(@as(u64, 0), stats.active_allocs);
}

test "active allocations tracking" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const widget_id: u32 = 1;

    collector.recordAlloc(widget_id, "Button", 100);
    collector.recordAlloc(widget_id, "Button", 200);
    collector.recordAlloc(widget_id, "Button", 300);

    var stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 3), stats.active_allocs);

    collector.recordFree(widget_id, "Button", 100);

    stats = collector.getStats(widget_id) orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 2), stats.active_allocs);
}

test "widget count tracking across allocs and frees" {
    var collector = MemoryMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordAlloc(1, "Button", 100);
    collector.recordAlloc(2, "Button", 200);
    collector.recordFree(1, "Button", 50);
    collector.recordAlloc(3, "Button", 300);

    const type_stats = collector.getTypeStats("Button") orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u32, 3), type_stats.widget_count);
}
