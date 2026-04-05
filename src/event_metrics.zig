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
