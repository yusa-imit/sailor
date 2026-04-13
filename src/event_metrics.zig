const std = @import("std");
const Allocator = std.mem.Allocator;

/// Statistics for a single event type
pub const EventStats = struct {
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    count: u64,
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    queue_depth_max: u32,
};

/// Statistics aggregated across all event types
pub const TypeStats = struct {
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    count: u64,
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    queue_depth_max: u32,
};

/// Internal data for a single event type
const EventData = struct {
    latencies: std.ArrayList(u64),
    min_ns: u64,
    max_ns: u64,
    sum_ns: u64, // for average calculation
    queue_depth_max: u32,

    fn deinit(self: *EventData, allocator: Allocator) void {
        self.latencies.deinit(allocator);
    }
};

/// Internal data for type aggregation
const TypeData = struct {
    latencies: std.ArrayList(u64),
    min_ns: u64,
    max_ns: u64,
    sum_ns: u64,
    queue_depth_max: u32,

    fn deinit(self: *TypeData, allocator: Allocator) void {
        self.latencies.deinit(allocator);
    }
};

/// Metrics collector for tracking event processing performance
pub const EventMetricsCollector = struct {
    allocator: Allocator,
    events: std.StringHashMap(EventData),
    type_data: ?TypeData,

    pub fn init(allocator: Allocator) EventMetricsCollector {
        return .{
            .allocator = allocator,
            .events = std.StringHashMap(EventData).init(allocator),
            .type_data = null,
        };
    }

    pub fn deinit(self: *EventMetricsCollector) void {
        // Free all event data
        var event_it = self.events.iterator();
        while (event_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.events.deinit();

        // Free type data
        if (self.type_data) |*type_data| {
            type_data.deinit(self.allocator);
        }
    }

    pub fn recordEvent(self: *EventMetricsCollector, event_type: []const u8, latency_ns: u64, queue_depth: u32) void {
        self.recordEventInternal(event_type, latency_ns, queue_depth) catch |err| {
            std.debug.panic("recordEvent failed: {}", .{err});
        };
        self.recordTypeEvent(latency_ns, queue_depth) catch |err| {
            std.debug.panic("recordTypeEvent failed: {}", .{err});
        };
    }

    fn recordEventInternal(self: *EventMetricsCollector, event_type: []const u8, latency_ns: u64, queue_depth: u32) !void {
        const gop = try self.events.getOrPut(event_type);
        if (!gop.found_existing) {
            // New event type - initialize
            const owned_type = try self.allocator.dupe(u8, event_type);
            gop.key_ptr.* = owned_type;
            gop.value_ptr.* = .{
                .latencies = std.ArrayList(u64){},
                .min_ns = latency_ns,
                .max_ns = latency_ns,
                .sum_ns = latency_ns,
                .queue_depth_max = queue_depth,
            };
            try gop.value_ptr.latencies.append(self.allocator, latency_ns);
        } else {
            // Existing event type - update
            const data = gop.value_ptr;
            data.min_ns = @min(data.min_ns, latency_ns);
            data.max_ns = @max(data.max_ns, latency_ns);
            data.queue_depth_max = @max(data.queue_depth_max, queue_depth);
            // Use saturating add to prevent overflow
            data.sum_ns = std.math.add(u64, data.sum_ns, latency_ns) catch std.math.maxInt(u64);
            try data.latencies.append(self.allocator, latency_ns);
        }
    }

    fn recordTypeEvent(self: *EventMetricsCollector, latency_ns: u64, queue_depth: u32) !void {
        if (self.type_data) |*type_data| {
            // Existing type data - update
            type_data.min_ns = @min(type_data.min_ns, latency_ns);
            type_data.max_ns = @max(type_data.max_ns, latency_ns);
            type_data.queue_depth_max = @max(type_data.queue_depth_max, queue_depth);
            type_data.sum_ns = std.math.add(u64, type_data.sum_ns, latency_ns) catch std.math.maxInt(u64);
            try type_data.latencies.append(self.allocator, latency_ns);
        } else {
            // New type data - initialize
            self.type_data = .{
                .latencies = std.ArrayList(u64){},
                .min_ns = latency_ns,
                .max_ns = latency_ns,
                .sum_ns = latency_ns,
                .queue_depth_max = queue_depth,
            };
            try self.type_data.?.latencies.append(self.allocator, latency_ns);
        }
    }

    pub fn getEventStats(self: *EventMetricsCollector, event_type: []const u8) ?EventStats {
        const event_data = self.events.get(event_type) orelse return null;
        return self.calculateEventStats(event_data.latencies.items, event_data.min_ns, event_data.max_ns, event_data.sum_ns, event_data.queue_depth_max);
    }

    pub fn getTypeStats(self: *EventMetricsCollector) ?TypeStats {
        const type_data = self.type_data orelse return null;
        const base_stats = self.calculateEventStats(type_data.latencies.items, type_data.min_ns, type_data.max_ns, type_data.sum_ns, type_data.queue_depth_max);
        return .{
            .min_ns = base_stats.min_ns,
            .max_ns = base_stats.max_ns,
            .avg_ns = base_stats.avg_ns,
            .count = base_stats.count,
            .p50_ns = base_stats.p50_ns,
            .p95_ns = base_stats.p95_ns,
            .p99_ns = base_stats.p99_ns,
            .queue_depth_max = base_stats.queue_depth_max,
        };
    }

    fn calculateEventStats(self: *EventMetricsCollector, latencies: []const u64, min_ns: u64, max_ns: u64, sum_ns: u64, queue_depth_max: u32) EventStats {
        const count = latencies.len;
        if (count == 0) {
            return .{
                .min_ns = 0,
                .max_ns = 0,
                .avg_ns = 0,
                .count = 0,
                .p50_ns = 0,
                .p95_ns = 0,
                .p99_ns = 0,
                .queue_depth_max = 0,
            };
        }

        const avg_ns = sum_ns / count;

        // Calculate percentiles - need to sort a copy
        var sorted = std.ArrayList(u64){};
        defer sorted.deinit(self.allocator);
        sorted.appendSlice(self.allocator, latencies) catch unreachable;
        std.mem.sort(u64, sorted.items, {}, std.sort.asc(u64));

        return .{
            .min_ns = min_ns,
            .max_ns = max_ns,
            .avg_ns = avg_ns,
            .count = count,
            .p50_ns = percentile(sorted.items, 50),
            .p95_ns = percentile(sorted.items, 95),
            .p99_ns = percentile(sorted.items, 99),
            .queue_depth_max = queue_depth_max,
        };
    }

    pub fn reset(self: *EventMetricsCollector) void {
        // Free all event data
        var event_it = self.events.iterator();
        while (event_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.events.clearRetainingCapacity();

        // Free type data
        if (self.type_data) |*type_data| {
            type_data.deinit(self.allocator);
            self.type_data = null;
        }
    }

    pub fn resetEvent(self: *EventMetricsCollector, event_type: []const u8) void {
        var event_data = self.events.fetchRemove(event_type) orelse return;
        self.allocator.free(event_data.key);
        event_data.value.deinit(self.allocator);

        // Rebuild type stats from remaining events
        self.rebuildTypeStats();
    }

    fn rebuildTypeStats(self: *EventMetricsCollector) void {
        // If no events remain, clear type data
        if (self.events.count() == 0) {
            if (self.type_data) |*type_data| {
                type_data.deinit(self.allocator);
                self.type_data = null;
            }
            return;
        }

        // Free existing type data
        if (self.type_data) |*type_data| {
            type_data.deinit(self.allocator);
        }

        // Rebuild from scratch
        self.type_data = .{
            .latencies = std.ArrayList(u64){},
            .min_ns = std.math.maxInt(u64),
            .max_ns = 0,
            .sum_ns = 0,
            .queue_depth_max = 0,
        };

        var event_it = self.events.valueIterator();
        while (event_it.next()) |event_data| {
            for (event_data.latencies.items) |latency| {
                self.type_data.?.latencies.append(self.allocator, latency) catch unreachable;
                self.type_data.?.min_ns = @min(self.type_data.?.min_ns, latency);
                self.type_data.?.max_ns = @max(self.type_data.?.max_ns, latency);
                self.type_data.?.sum_ns = std.math.add(u64, self.type_data.?.sum_ns, latency) catch std.math.maxInt(u64);
            }
            self.type_data.?.queue_depth_max = @max(self.type_data.?.queue_depth_max, event_data.queue_depth_max);
        }
    }
};

/// Calculate percentile from sorted array
fn percentile(sorted: []const u64, p: u8) u64 {
    if (sorted.len == 0) return 0;
    if (sorted.len == 1) return sorted[0];

    // Formula: index = (percentile * (count - 1)) / 100
    // This is the standard "linear interpolation" method
    const index = (@as(u64, p) * (sorted.len - 1)) / 100;
    return sorted[@intCast(index)];
}

// ============================================================================
// TESTS
// ============================================================================

test "EventMetricsCollector init and deinit" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // Should initialize with no events
    try std.testing.expectEqual(@as(usize, 0), collector.events.count());
    try std.testing.expect(collector.type_data == null);
}

test "recordEvent single event" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 5);

    const stats = collector.getEventStats("input");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 1000), stats.?.min_ns);
    try std.testing.expectEqual(@as(u64, 1000), stats.?.max_ns);
    try std.testing.expectEqual(@as(u64, 1000), stats.?.avg_ns);
    try std.testing.expectEqual(@as(u64, 1), stats.?.count);
    try std.testing.expectEqual(@as(u32, 5), stats.?.queue_depth_max);
}

test "recordEvent multiple events same type" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);
    collector.recordEvent("input", 2000, 2);
    collector.recordEvent("input", 3000, 3);

    const stats = collector.getEventStats("input");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 1000), stats.?.min_ns);
    try std.testing.expectEqual(@as(u64, 3000), stats.?.max_ns);
    try std.testing.expectEqual(@as(u64, 2000), stats.?.avg_ns); // (1000+2000+3000)/3
    try std.testing.expectEqual(@as(u64, 3), stats.?.count);
    try std.testing.expectEqual(@as(u32, 3), stats.?.queue_depth_max);
}

test "recordEvent multiple event types" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);
    collector.recordEvent("render", 5000, 2);
    collector.recordEvent("input", 2000, 1);

    const input_stats = collector.getEventStats("input");
    try std.testing.expect(input_stats != null);
    try std.testing.expectEqual(@as(u64, 2), input_stats.?.count);
    try std.testing.expectEqual(@as(u64, 1500), input_stats.?.avg_ns); // (1000+2000)/2

    const render_stats = collector.getEventStats("render");
    try std.testing.expect(render_stats != null);
    try std.testing.expectEqual(@as(u64, 1), render_stats.?.count);
    try std.testing.expectEqual(@as(u64, 5000), render_stats.?.avg_ns);
}

test "getEventStats returns null for unknown event type" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    const stats = collector.getEventStats("unknown");
    try std.testing.expect(stats == null);
}

test "getEventStats empty collector returns null" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    const stats = collector.getEventStats("input");
    try std.testing.expect(stats == null);
}

test "getTypeStats aggregates across all event types" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);
    collector.recordEvent("render", 2000, 2);
    collector.recordEvent("input", 3000, 3);

    const stats = collector.getTypeStats();
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 3), stats.?.count);
    try std.testing.expectEqual(@as(u64, 1000), stats.?.min_ns);
    try std.testing.expectEqual(@as(u64, 3000), stats.?.max_ns);
    try std.testing.expectEqual(@as(u64, 2000), stats.?.avg_ns); // (1000+2000+3000)/3
    try std.testing.expectEqual(@as(u32, 3), stats.?.queue_depth_max);
}

test "getTypeStats returns null when no events recorded" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    const stats = collector.getTypeStats();
    try std.testing.expect(stats == null);
}

test "percentile calculation p50 with odd count" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // 5 values: 100, 200, 300, 400, 500 → p50 should be 300 (median)
    collector.recordEvent("test", 100, 1);
    collector.recordEvent("test", 200, 1);
    collector.recordEvent("test", 300, 1);
    collector.recordEvent("test", 400, 1);
    collector.recordEvent("test", 500, 1);

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 300), stats.?.p50_ns);
}

test "percentile calculation p50 with even count" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // 4 values: 100, 200, 300, 400 → p50 index = (50*(4-1))/100 = 1.5 → 1 → 200
    collector.recordEvent("test", 100, 1);
    collector.recordEvent("test", 200, 1);
    collector.recordEvent("test", 300, 1);
    collector.recordEvent("test", 400, 1);

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 200), stats.?.p50_ns);
}

test "percentile calculation p95 accuracy" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // 100 values: 0, 1, 2, ..., 99
    // p95 index = (95 * 99) / 100 = 94.05 → 94 → value 94
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        collector.recordEvent("test", i, 1);
    }

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 94), stats.?.p95_ns);
}

test "percentile calculation p99 accuracy" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // 100 values: 0, 1, 2, ..., 99
    // p99 index = (99 * 99) / 100 = 98.01 → 98 → value 98
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        collector.recordEvent("test", i, 1);
    }

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 98), stats.?.p99_ns);
}

test "percentile with single value" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("test", 1234, 1);

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 1234), stats.?.p50_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.?.p95_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.?.p99_ns);
}

test "percentile with unsorted input" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // Record in random order
    collector.recordEvent("test", 500, 1);
    collector.recordEvent("test", 100, 1);
    collector.recordEvent("test", 300, 1);
    collector.recordEvent("test", 200, 1);
    collector.recordEvent("test", 400, 1);

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    // After sorting: [100, 200, 300, 400, 500] → p50 = 300
    try std.testing.expectEqual(@as(u64, 300), stats.?.p50_ns);
}

test "overflow handling in sum_ns" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // Record values that will overflow u64
    const large_value = std.math.maxInt(u64) - 100;
    collector.recordEvent("test", large_value, 1);
    collector.recordEvent("test", 200, 1); // This should trigger saturating add

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    // sum_ns should be saturated to maxInt(u64)
    // avg_ns = maxInt(u64) / 2
    try std.testing.expectEqual(std.math.maxInt(u64) / 2, stats.?.avg_ns);
}

test "reset clears all events and type data" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);
    collector.recordEvent("render", 2000, 2);

    collector.reset();

    try std.testing.expectEqual(@as(usize, 0), collector.events.count());
    try std.testing.expect(collector.type_data == null);
    try std.testing.expect(collector.getEventStats("input") == null);
    try std.testing.expect(collector.getTypeStats() == null);
}

test "reset can be called on empty collector" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // Should not crash
    collector.reset();

    try std.testing.expectEqual(@as(usize, 0), collector.events.count());
    try std.testing.expect(collector.type_data == null);
}

test "resetEvent removes specific event type" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);
    collector.recordEvent("render", 2000, 2);
    collector.recordEvent("input", 1500, 1);

    collector.resetEvent("input");

    // Input should be gone
    try std.testing.expect(collector.getEventStats("input") == null);

    // Render should remain
    const render_stats = collector.getEventStats("render");
    try std.testing.expect(render_stats != null);
    try std.testing.expectEqual(@as(u64, 1), render_stats.?.count);
}

test "resetEvent rebuilds type stats correctly" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);
    collector.recordEvent("render", 2000, 2);
    collector.recordEvent("input", 3000, 3);

    // Type stats before reset: 3 events (1000, 2000, 3000)
    const before_stats = collector.getTypeStats();
    try std.testing.expect(before_stats != null);
    try std.testing.expectEqual(@as(u64, 3), before_stats.?.count);

    collector.resetEvent("input");

    // Type stats after reset: 1 event (2000)
    const after_stats = collector.getTypeStats();
    try std.testing.expect(after_stats != null);
    try std.testing.expectEqual(@as(u64, 1), after_stats.?.count);
    try std.testing.expectEqual(@as(u64, 2000), after_stats.?.min_ns);
    try std.testing.expectEqual(@as(u64, 2000), after_stats.?.max_ns);
    try std.testing.expectEqual(@as(u64, 2000), after_stats.?.avg_ns);
}

test "resetEvent clears type data when last event removed" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);

    collector.resetEvent("input");

    try std.testing.expect(collector.type_data == null);
    try std.testing.expect(collector.getTypeStats() == null);
}

test "resetEvent on unknown event type is no-op" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 1000, 1);

    // Should not crash
    collector.resetEvent("unknown");

    const stats = collector.getEventStats("input");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 1), stats.?.count);
}

test "many events performance stress test" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    // Record 1000 events
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        collector.recordEvent("stress", i, @intCast(i % 10));
    }

    const stats = collector.getEventStats("stress");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 1000), stats.?.count);
    try std.testing.expectEqual(@as(u64, 0), stats.?.min_ns);
    try std.testing.expectEqual(@as(u64, 999), stats.?.max_ns);
    // avg = sum(0..999) / 1000 = 999*1000/2 / 1000 = 499.5 → 499
    try std.testing.expectEqual(@as(u64, 499), stats.?.avg_ns);
    try std.testing.expectEqual(@as(u32, 9), stats.?.queue_depth_max);
}

test "queue_depth_max tracks maximum across events" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("test", 100, 5);
    collector.recordEvent("test", 200, 10);
    collector.recordEvent("test", 300, 3);
    collector.recordEvent("test", 400, 20);

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u32, 20), stats.?.queue_depth_max);

    const type_stats = collector.getTypeStats();
    try std.testing.expect(type_stats != null);
    try std.testing.expectEqual(@as(u32, 20), type_stats.?.queue_depth_max);
}

test "percentile edge case with two values" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("test", 100, 1);
    collector.recordEvent("test", 200, 1);

    const stats = collector.getEventStats("test");
    try std.testing.expect(stats != null);
    // p50 index = (50 * 1) / 100 = 0 → value 100
    try std.testing.expectEqual(@as(u64, 100), stats.?.p50_ns);
    // p95 index = (95 * 1) / 100 = 0 → value 100
    try std.testing.expectEqual(@as(u64, 100), stats.?.p95_ns);
    // p99 index = (99 * 1) / 100 = 0 → value 100
    try std.testing.expectEqual(@as(u64, 100), stats.?.p99_ns);
}

test "type stats with mixed event types and queue depths" {
    const allocator = std.testing.allocator;
    var collector = EventMetricsCollector.init(allocator);
    defer collector.deinit();

    collector.recordEvent("input", 100, 1);
    collector.recordEvent("render", 500, 10);
    collector.recordEvent("timer", 200, 5);

    const type_stats = collector.getTypeStats();
    try std.testing.expect(type_stats != null);
    try std.testing.expectEqual(@as(u64, 3), type_stats.?.count);
    try std.testing.expectEqual(@as(u64, 100), type_stats.?.min_ns);
    try std.testing.expectEqual(@as(u64, 500), type_stats.?.max_ns);
    // avg = (100 + 500 + 200) / 3 = 266
    try std.testing.expectEqual(@as(u64, 266), type_stats.?.avg_ns);
    try std.testing.expectEqual(@as(u32, 10), type_stats.?.queue_depth_max);
}
