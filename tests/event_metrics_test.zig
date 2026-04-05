const std = @import("std");
const sailor = @import("sailor");
const EventMetricsCollector = sailor.event_metrics.EventMetricsCollector;
const EventStats = sailor.event_metrics.EventStats;
const TypeStats = sailor.event_metrics.TypeStats;

// ============================================================================
// BASIC RECORDING AND RETRIEVAL
// ============================================================================

test "EventMetricsCollector init and deinit" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();
}

test "record single event - stats should have min==max==avg" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const latency_ns: u64 = 1000;
    const queue_depth: u32 = 5;

    collector.recordEvent("key_press", latency_ns, queue_depth);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    try std.testing.expectEqual(latency_ns, stats.min_ns);
    try std.testing.expectEqual(latency_ns, stats.max_ns);
    try std.testing.expectEqual(latency_ns, stats.avg_ns);
    try std.testing.expectEqual(@as(u64, 1), stats.count);
    try std.testing.expectEqual(latency_ns, stats.p50_ns);
    try std.testing.expectEqual(latency_ns, stats.p95_ns);
    try std.testing.expectEqual(latency_ns, stats.p99_ns);
    try std.testing.expectEqual(queue_depth, stats.queue_depth_max);
}

test "record multiple events - stats should update correctly" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Record 5 events: 100, 200, 300, 400, 500
    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("key_press", 200, 2);
    collector.recordEvent("key_press", 300, 3);
    collector.recordEvent("key_press", 400, 2);
    collector.recordEvent("key_press", 500, 1);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 300), stats.avg_ns); // (100+200+300+400+500)/5 = 300
    try std.testing.expectEqual(@as(u64, 5), stats.count);
    try std.testing.expectEqual(@as(u64, 300), stats.p50_ns); // median
    try std.testing.expectEqual(@as(u32, 3), stats.queue_depth_max);
}

test "multiple event types - isolation" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("mouse_move", 200, 2);
    collector.recordEvent("resize", 300, 3);

    const stats1 = collector.getEventStats("key_press") orelse return error.Stats1NotFound;
    const stats2 = collector.getEventStats("mouse_move") orelse return error.Stats2NotFound;
    const stats3 = collector.getEventStats("resize") orelse return error.Stats3NotFound;

    try std.testing.expectEqual(@as(u64, 100), stats1.min_ns);
    try std.testing.expectEqual(@as(u64, 200), stats2.min_ns);
    try std.testing.expectEqual(@as(u64, 300), stats3.min_ns);
}

// ============================================================================
// PERCENTILE CALCULATIONS
// ============================================================================

test "percentile calculation - p50" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Odd number of samples: 1, 2, 3, 4, 5 -> median = 3
    collector.recordEvent("key_press", 1, 0);
    collector.recordEvent("key_press", 2, 0);
    collector.recordEvent("key_press", 3, 0);
    collector.recordEvent("key_press", 4, 0);
    collector.recordEvent("key_press", 5, 0);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 3), stats.p50_ns);
}

test "percentile calculation - p95" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // 20 samples: 1..20 -> p95 should be around 19
    var i: u64 = 1;
    while (i <= 20) : (i += 1) {
        collector.recordEvent("key_press", i, 0);
    }

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    // p95 of 20 samples = 95th percentile index = ceil(20 * 0.95) = 19
    try std.testing.expectEqual(@as(u64, 19), stats.p95_ns);
}

test "percentile calculation - p99" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // 100 samples: 1..100 -> p99 should be 99
    var i: u64 = 1;
    while (i <= 100) : (i += 1) {
        collector.recordEvent("key_press", i, 0);
    }

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    // p99 of 100 samples = 99th percentile index = 99
    try std.testing.expectEqual(@as(u64, 99), stats.p99_ns);
}

test "percentile calculation - unsorted input" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Insert in random order: 500, 100, 300, 200, 400
    collector.recordEvent("key_press", 500, 0);
    collector.recordEvent("key_press", 100, 0);
    collector.recordEvent("key_press", 300, 0);
    collector.recordEvent("key_press", 200, 0);
    collector.recordEvent("key_press", 400, 0);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 300), stats.p50_ns); // median of sorted [100,200,300,400,500]
}

test "percentile with even number of samples" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Even number: 1, 2, 3, 4 -> median should be (2+3)/2 = 2.5, but we use integer so 2 or 3
    collector.recordEvent("key_press", 1, 0);
    collector.recordEvent("key_press", 2, 0);
    collector.recordEvent("key_press", 3, 0);
    collector.recordEvent("key_press", 4, 0);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    // p50 for even samples can be either middle value or average of two middle
    // Accept either 2 or 3 as valid median
    try std.testing.expect(stats.p50_ns == 2 or stats.p50_ns == 3);
}

test "single data point - all percentiles equal" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 1234, 5);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 1234), stats.p50_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.p95_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.p99_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 1234), stats.avg_ns);
    try std.testing.expectEqual(@as(u32, 5), stats.queue_depth_max);
}

// ============================================================================
// QUEUE DEPTH TRACKING
// ============================================================================

test "queue depth tracking - max queue depth" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("key_press", 200, 5);
    collector.recordEvent("key_press", 300, 3);
    collector.recordEvent("key_press", 400, 10); // max
    collector.recordEvent("key_press", 500, 2);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u32, 10), stats.queue_depth_max);
}

test "queue depth tracking - zero queue depths" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 0);
    collector.recordEvent("key_press", 200, 0);
    collector.recordEvent("key_press", 300, 0);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u32, 0), stats.queue_depth_max);
}

test "queue depth tracking - incremental max" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    var stats = collector.getEventStats("key_press").?;
    try std.testing.expectEqual(@as(u32, 1), stats.queue_depth_max);

    collector.recordEvent("key_press", 200, 3);
    stats = collector.getEventStats("key_press").?;
    try std.testing.expectEqual(@as(u32, 3), stats.queue_depth_max);

    collector.recordEvent("key_press", 300, 2); // lower than current max
    stats = collector.getEventStats("key_press").?;
    try std.testing.expectEqual(@as(u32, 3), stats.queue_depth_max); // should remain 3
}

// ============================================================================
// TYPE AGGREGATION
// ============================================================================

test "type aggregation - multiple event types" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // key events: 100, 200
    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("key_release", 200, 2);

    // mouse events: 300, 400
    collector.recordEvent("mouse_move", 300, 3);
    collector.recordEvent("mouse_click", 400, 4);

    const type_stats = collector.getTypeStats() orelse return error.TypeStatsNotFound;

    // Aggregated across all types: 100, 200, 300, 400
    try std.testing.expectEqual(@as(u64, 100), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 400), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 250), type_stats.avg_ns); // (100+200+300+400)/4
    try std.testing.expectEqual(@as(u64, 4), type_stats.count);
    try std.testing.expectEqual(@as(u32, 4), type_stats.queue_depth_max); // max across all
}

test "type aggregation - all same event type" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("key_press", 200, 2);
    collector.recordEvent("key_press", 300, 3);

    const type_stats = collector.getTypeStats() orelse return error.TypeStatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 300), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 200), type_stats.avg_ns);
    try std.testing.expectEqual(@as(u64, 3), type_stats.count);
    try std.testing.expectEqual(@as(u32, 3), type_stats.queue_depth_max);
}

test "type aggregation - percentiles across types" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // key_press: 100, 200, 300
    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("key_press", 200, 1);
    collector.recordEvent("key_press", 300, 1);

    // mouse_move: 400, 500
    collector.recordEvent("mouse_move", 400, 2);
    collector.recordEvent("mouse_move", 500, 2);

    const type_stats = collector.getTypeStats() orelse return error.TypeStatsNotFound;

    // All events: 100, 200, 300, 400, 500 (5 samples)
    try std.testing.expectEqual(@as(u64, 100), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 300), type_stats.p50_ns); // median
    try std.testing.expectEqual(@as(u64, 5), type_stats.count);
}

// ============================================================================
// RESET OPERATIONS
// ============================================================================

test "reset all metrics" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("mouse_move", 200, 2);

    collector.reset();

    // After reset, stats should return null
    const stats1 = collector.getEventStats("key_press");
    const stats2 = collector.getEventStats("mouse_move");
    const type_stats = collector.getTypeStats();

    try std.testing.expectEqual(@as(?EventStats, null), stats1);
    try std.testing.expectEqual(@as(?EventStats, null), stats2);
    try std.testing.expectEqual(@as(?TypeStats, null), type_stats);
}

test "reset all then record again" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.reset();
    collector.recordEvent("key_press", 200, 2);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    // Should only have the new recording
    try std.testing.expectEqual(@as(u64, 200), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 200), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 1), stats.count);
    try std.testing.expectEqual(@as(u32, 2), stats.queue_depth_max);
}

test "reset specific event type" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("mouse_move", 200, 2);

    collector.resetEvent("key_press");

    // key_press should have no stats
    const stats1 = collector.getEventStats("key_press");
    try std.testing.expectEqual(@as(?EventStats, null), stats1);

    // mouse_move should still have stats
    const stats2 = collector.getEventStats("mouse_move") orelse return error.Stats2NotFound;
    try std.testing.expectEqual(@as(u64, 200), stats2.min_ns);
}

test "reset specific event affects type stats" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("mouse_move", 200, 2);

    collector.resetEvent("key_press");

    const type_stats = collector.getTypeStats() orelse return error.TypeStatsNotFound;

    // Should only count mouse_move now
    try std.testing.expectEqual(@as(u64, 200), type_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 200), type_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 1), type_stats.count);
}

test "reset non-existent event type - no error" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);

    // Should not crash or error
    collector.resetEvent("non_existent");

    // Original event should still exist
    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
}

// ============================================================================
// EDGE CASES
// ============================================================================

test "query non-existent event returns null" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);

    const stats = collector.getEventStats("non_existent");
    try std.testing.expectEqual(@as(?EventStats, null), stats);
}

test "query empty collector returns null" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const stats = collector.getEventStats("key_press");
    const type_stats = collector.getTypeStats();

    try std.testing.expectEqual(@as(?EventStats, null), stats);
    try std.testing.expectEqual(@as(?TypeStats, null), type_stats);
}

test "zero latency events" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 0, 1);
    collector.recordEvent("key_press", 100, 2);
    collector.recordEvent("key_press", 0, 3);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    try std.testing.expectEqual(@as(u64, 0), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 100), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 33), stats.avg_ns); // (0+100+0)/3 = 33 (truncated)
    try std.testing.expectEqual(@as(u64, 3), stats.count);
    try std.testing.expectEqual(@as(u32, 3), stats.queue_depth_max);
}

test "very large latency values" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const max_u64 = std.math.maxInt(u64);
    const large_val = max_u64 - 1000;

    collector.recordEvent("key_press", large_val, 1);
    collector.recordEvent("key_press", max_u64, 2);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    try std.testing.expectEqual(large_val, stats.min_ns);
    try std.testing.expectEqual(max_u64, stats.max_ns);
    try std.testing.expectEqual(@as(u64, 2), stats.count);
}

test "overflow protection - sum overflow" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const large_val: u64 = std.math.maxInt(u64) / 2;

    // Two very large values - sum would overflow u64
    collector.recordEvent("key_press", large_val, 1);
    collector.recordEvent("key_press", large_val, 2);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    // Average should still be calculated correctly (implementation should handle overflow)
    try std.testing.expectEqual(@as(u64, 2), stats.count);
    try std.testing.expect(stats.avg_ns >= large_val - 1 and stats.avg_ns <= large_val + 1);
}

test "average calculation correctness" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Sum = 1000 + 2000 + 3000 = 6000, avg = 2000
    collector.recordEvent("key_press", 1000, 1);
    collector.recordEvent("key_press", 2000, 2);
    collector.recordEvent("key_press", 3000, 3);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 2000), stats.avg_ns);
}

// ============================================================================
// MEMORY SAFETY
// ============================================================================

test "memory leak check - init and deinit" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("mouse_move", 200, 2);
    collector.deinit();
    // If there's a leak, testing.allocator will catch it
}

test "memory leak check - reset actually frees memory" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Record some data
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        collector.recordEvent("key_press", 100, 1);
    }

    // Reset should free internal allocations
    collector.reset();

    // Record again
    collector.recordEvent("key_press", 100, 1);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 1), stats.count);
}

test "memory leak check - reset event frees memory" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        collector.recordEvent("key_press", 100, 1);
        collector.recordEvent("mouse_move", 200, 2);
    }

    collector.resetEvent("key_press");

    const stats = collector.getEventStats("mouse_move") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 50), stats.count);
}

// ============================================================================
// STRESS TESTS
// ============================================================================

test "stress test - 1000 event types" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var buf: [64]u8 = undefined;
        const event_type = try std.fmt.bufPrint(&buf, "event_{d}", .{i});
        collector.recordEvent(event_type, i * 100, i % 10);
    }

    // Verify some samples
    const stats0 = collector.getEventStats("event_0") orelse return error.Stats0NotFound;
    try std.testing.expectEqual(@as(u64, 0), stats0.min_ns);

    const stats999 = collector.getEventStats("event_999") orelse return error.Stats999NotFound;
    try std.testing.expectEqual(@as(u64, 99900), stats999.min_ns);

    const type_stats = collector.getTypeStats() orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u64, 1000), type_stats.count);
}

test "stress test - 10000 events per type" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // 10000 events for single type
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        collector.recordEvent("key_press", i, @intCast(i % 100));
    }

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;
    try std.testing.expectEqual(@as(u64, 0), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 9999), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 10000), stats.count);
    try std.testing.expectEqual(@as(u32, 99), stats.queue_depth_max);
}

test "stress test - multiple types with 10000 events each" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    const event_types = [_][]const u8{
        "key_press",
        "key_release",
        "mouse_move",
        "mouse_click",
        "resize",
    };

    for (event_types) |event_type| {
        var i: u64 = 0;
        while (i < 10000) : (i += 1) {
            collector.recordEvent(event_type, i, @intCast(i % 50));
        }
    }

    // Verify each type
    for (event_types) |event_type| {
        const stats = collector.getEventStats(event_type) orelse return error.StatsNotFound;
        try std.testing.expectEqual(@as(u64, 10000), stats.count);
        try std.testing.expectEqual(@as(u32, 49), stats.queue_depth_max);
    }

    // Verify type aggregation
    const type_stats = collector.getTypeStats() orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u64, 50000), type_stats.count); // 5 types * 10000
}

// ============================================================================
// CUSTOM EVENT TYPES
// ============================================================================

test "custom event types - string-based" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("custom_event_1", 100, 1);
    collector.recordEvent("custom_event_2", 200, 2);
    collector.recordEvent("my_special_event", 300, 3);

    const stats1 = collector.getEventStats("custom_event_1") orelse return error.Stats1NotFound;
    const stats2 = collector.getEventStats("custom_event_2") orelse return error.Stats2NotFound;
    const stats3 = collector.getEventStats("my_special_event") orelse return error.Stats3NotFound;

    try std.testing.expectEqual(@as(u64, 100), stats1.min_ns);
    try std.testing.expectEqual(@as(u64, 200), stats2.min_ns);
    try std.testing.expectEqual(@as(u64, 300), stats3.min_ns);
}

test "standard event types - key events" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("key_press", 100, 1);
    collector.recordEvent("key_release", 150, 2);

    const press_stats = collector.getEventStats("key_press") orelse return error.PressStatsNotFound;
    const release_stats = collector.getEventStats("key_release") orelse return error.ReleaseStatsNotFound;

    try std.testing.expectEqual(@as(u64, 100), press_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 150), release_stats.min_ns);
}

test "standard event types - mouse events" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("mouse_move", 50, 1);
    collector.recordEvent("mouse_click", 100, 2);

    const move_stats = collector.getEventStats("mouse_move") orelse return error.MoveStatsNotFound;
    const click_stats = collector.getEventStats("mouse_click") orelse return error.ClickStatsNotFound;

    try std.testing.expectEqual(@as(u64, 50), move_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 100), click_stats.min_ns);
}

test "standard event types - terminal events" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.recordEvent("resize", 200, 5);
    collector.recordEvent("focus", 50, 1);

    const resize_stats = collector.getEventStats("resize") orelse return error.ResizeStatsNotFound;
    const focus_stats = collector.getEventStats("focus") orelse return error.FocusStatsNotFound;

    try std.testing.expectEqual(@as(u64, 200), resize_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 50), focus_stats.min_ns);
}

// ============================================================================
// MIXED SCENARIOS
// ============================================================================

test "mixed scenario - realistic event stream" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Simulate a realistic event stream
    collector.recordEvent("key_press", 1200, 0);
    collector.recordEvent("key_release", 800, 0);
    collector.recordEvent("mouse_move", 500, 1);
    collector.recordEvent("mouse_move", 450, 2);
    collector.recordEvent("key_press", 1100, 1);
    collector.recordEvent("mouse_click", 2000, 3);
    collector.recordEvent("key_press", 1300, 2);
    collector.recordEvent("resize", 5000, 10); // resize is slow

    // Check key_press stats
    const key_stats = collector.getEventStats("key_press") orelse return error.KeyStatsNotFound;
    try std.testing.expectEqual(@as(u64, 1100), key_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 1300), key_stats.max_ns);
    try std.testing.expectEqual(@as(u64, 3), key_stats.count);
    try std.testing.expectEqual(@as(u32, 2), key_stats.queue_depth_max);

    // Check mouse_move stats
    const mouse_stats = collector.getEventStats("mouse_move") orelse return error.MouseStatsNotFound;
    try std.testing.expectEqual(@as(u64, 450), mouse_stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), mouse_stats.max_ns);
    try std.testing.expectEqual(@as(u32, 2), mouse_stats.queue_depth_max);

    // Check type stats
    const type_stats = collector.getTypeStats() orelse return error.TypeStatsNotFound;
    try std.testing.expectEqual(@as(u64, 8), type_stats.count);
    try std.testing.expectEqual(@as(u32, 10), type_stats.queue_depth_max); // from resize
}

test "mixed scenario - input lag detection" {
    var collector = EventMetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Most events are fast
    var i: u64 = 0;
    while (i < 95) : (i += 1) {
        collector.recordEvent("key_press", 1000 + i, 0); // 1000-1094 ns
    }

    // But 5 events have high latency (input lag)
    collector.recordEvent("key_press", 50000, 5); // 50 us lag!
    collector.recordEvent("key_press", 60000, 8);
    collector.recordEvent("key_press", 55000, 6);
    collector.recordEvent("key_press", 70000, 10);
    collector.recordEvent("key_press", 65000, 7);

    const stats = collector.getEventStats("key_press") orelse return error.StatsNotFound;

    // p99 catches the input lag outliers (with 100 samples, p99 = sorted[98] is in the slow range)
    try std.testing.expect(stats.p99_ns >= 50000); // p99 catches the outliers
    try std.testing.expect(stats.p50_ns < 5000); // median is still low
    try std.testing.expectEqual(@as(u32, 10), stats.queue_depth_max);
}
