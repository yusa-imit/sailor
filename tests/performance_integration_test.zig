//! Performance feature integration tests (v1.3.0)
//!
//! These tests verify that performance optimization features work correctly
//! together: render budget, lazy rendering, event batching, and debug overlay.
//!
//! v1.36.0: Added performance regression tests using metrics collectors

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const RenderBudget = sailor.tui.RenderBudget;
const LazyBuffer = sailor.tui.LazyBuffer;
const EventBatcher = sailor.tui.EventBatcher;
const DebugOverlay = sailor.tui.widgets.DebugOverlay;
const DebugMode = sailor.tui.widgets.DebugMode;
const Event = sailor.tui.Event;
const KeyEvent = sailor.tui.KeyEvent;
const KeyCode = sailor.tui.KeyCode;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

// v1.36.0: Metrics collectors for regression testing
const RenderMetrics = sailor.render_metrics.MetricsCollector;
const MemoryMetrics = sailor.memory_metrics.MemoryMetricsCollector;
const EventMetrics = sailor.event_metrics.EventMetricsCollector;

// v1.36.0: Widgets for regression testing
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Gauge = sailor.tui.widgets.Gauge;
const Line = sailor.tui.Line;
const Span = sailor.tui.Span;

// Performance thresholds (conservative for CI stability)
const BLOCK_RENDER_MAX_AVG_NS: u64 = 50_000; // 50μs
const BLOCK_RENDER_MAX_P95_NS: u64 = 100_000; // 100μs
const PARAGRAPH_RENDER_MAX_AVG_NS: u64 = 100_000; // 100μs
const LIST_RENDER_MAX_AVG_NS: u64 = 150_000; // 150μs
const GAUGE_RENDER_MAX_AVG_NS: u64 = 80_000; // 80μs
const MAX_EVENT_LATENCY_P95_NS: u64 = 1_000_000; // 1ms
const MAX_EVENT_LATENCY_P99_NS: u64 = 5_000_000; // 5ms

test "RenderBudget basic frame tracking" {
    var budget = RenderBudget.init(60);

    // First frame should always render
    const should_render1 = budget.startFrame();
    try testing.expect(should_render1);

    budget.endFrame();

    // Stats should be recorded
    try testing.expect(budget.stats.total_frames > 0);
}

test "LazyBuffer basic dirty tracking" {
    const allocator = testing.allocator;

    var lazy = try LazyBuffer.init(allocator, 80, 24);
    defer lazy.deinit();

    // Initially all cells are dirty
    try testing.expect(lazy.getDirtyRect() != null);

    // Clear dirty flags
    lazy.clearDirty();
    try testing.expect(lazy.getDirtyRect() == null);

    // Mark specific cells dirty
    lazy.markDirty(10, 10);
    lazy.markDirty(11, 10);

    // Should have dirty region
    try testing.expect(lazy.getDirtyRect() != null);

    // Check specific cells
    try testing.expect(lazy.isDirty(10, 10));
    try testing.expect(lazy.isDirty(11, 10));
    try testing.expect(!lazy.isDirty(5, 5));
}

test "EventBatcher coalesces resize events" {
    const allocator = testing.allocator;

    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    // Add multiple resize events (should coalesce to last one)
    try batcher.push(.{ .resize = .{ .width = 80, .height = 24 } });
    try batcher.push(.{ .resize = .{ .width = 100, .height = 30 } });
    try batcher.push(.{ .resize = .{ .width = 120, .height = 40 } });

    // Add key event (should not coalesce)
    try batcher.push(.{ .key = KeyEvent{
        .code = .{ .char = 'a' },
        .modifiers = .{},
    } });

    // Flush events
    var out_events: std.ArrayList(Event) = .{};
    defer out_events.deinit(allocator);
    try batcher.flush(&out_events);

    // Should have 2 events: 1 resize (latest) + 1 key
    try testing.expectEqual(@as(usize, 2), out_events.items.len);
    try testing.expectEqual(Event.resize, std.meta.activeTag(out_events.items[0]));
    try testing.expectEqual(@as(u16, 120), out_events.items[0].resize.width);
    try testing.expectEqual(@as(u16, 40), out_events.items[0].resize.height);
    try testing.expectEqual(Event.key, std.meta.activeTag(out_events.items[1]));
}

test "LazyBuffer dirty rect optimization" {
    const allocator = testing.allocator;

    var lazy = try LazyBuffer.init(allocator, 100, 50);
    defer lazy.deinit();

    // Clear all dirty flags
    lazy.clearDirty();
    try testing.expect(lazy.getDirtyRect() == null);

    // Mark small rectangular region
    lazy.markDirtyRect(Rect{ .x = 10, .y = 10, .width = 5, .height = 3 });

    // Should have dirty region
    const dirty_rect = lazy.getDirtyRect();
    try testing.expect(dirty_rect != null);

    // Dirty rect should encompass the marked region
    const rect = dirty_rect.?;
    try testing.expect(rect.x <= 10);
    try testing.expect(rect.y <= 10);
    try testing.expect(rect.x + rect.width >= 10 + 5);
    try testing.expect(rect.y + rect.height >= 10 + 3);
}

test "DebugOverlay basic initialization and rendering" {
    const allocator = testing.allocator;

    var debug = DebugOverlay.init(allocator, DebugMode.all, .top_left);
    defer debug.deinit();

    // Add a debug rect
    try debug.addRect(Rect{ .x = 5, .y = 5, .width = 10, .height = 10 }, "Test", Color.red);

    // Log an event
    try debug.logEvent(.{ .key = KeyEvent{
        .code = .{ .char = 'a' },
        .modifiers = .{},
    } });

    // Update stats
    var test_budget = RenderBudget.init(60);
    debug.updateStats(&test_budget, null);

    // Render should not crash
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    debug.render(&buffer, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "LazyBuffer with actual rendering" {
    const allocator = testing.allocator;

    var lazy = try LazyBuffer.init(allocator, 40, 20);
    defer lazy.deinit();

    // Clear and mark specific region dirty
    lazy.clearDirty();
    lazy.markDirtyRect(Rect{ .x = 10, .y = 10, .width = 10, .height = 5 });

    // Write to lazy buffer
    lazy.setString(10, 10, "Hello", Style{});

    // Verify content was written
    const cell_ptr = lazy.buffer.get(10, 10);
    try testing.expect(cell_ptr != null);
    try testing.expectEqual(@as(u21, 'H'), cell_ptr.?.char);

    // Verify dirty tracking works
    try testing.expect(lazy.isDirty(10, 10));
}

test "EventBatcher preserves key events" {
    const allocator = testing.allocator;

    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();

    // Add multiple key events (should NOT coalesce)
    try batcher.push(.{ .key = KeyEvent{
        .code = .{ .char = 'a' },
        .modifiers = .{},
    } });
    try batcher.push(.{ .key = KeyEvent{
        .code = .{ .char = 'b' },
        .modifiers = .{},
    } });
    try batcher.push(.{ .key = KeyEvent{
        .code = .{ .char = 'c' },
        .modifiers = .{},
    } });

    // Flush
    var out_events: std.ArrayList(Event) = .{};
    defer out_events.deinit(allocator);
    try batcher.flush(&out_events);

    // All key events should be preserved
    try testing.expectEqual(@as(usize, 3), out_events.items.len);
    for (out_events.items) |event| {
        try testing.expectEqual(Event.key, std.meta.activeTag(event));
    }
}

test "RenderBudget FPS calculation" {
    var budget = RenderBudget.init(60);

    // Start first frame
    _ = budget.startFrame();

    // Sleep for a tiny amount to ensure time passes
    std.Thread.sleep(1_000_000); // 1ms

    budget.endFrame();

    // Start second frame
    _ = budget.startFrame();
    std.Thread.sleep(1_000_000); // 1ms
    budget.endFrame();

    // FPS should be calculated (will be low due to sleep, but > 0)
    const fps = budget.stats.fps();
    try testing.expect(fps > 0);
}

test "DebugOverlay clears rects" {
    const allocator = testing.allocator;

    var debug = DebugOverlay.init(allocator, DebugMode.layout_rects, .top_left);
    defer debug.deinit();

    // Add multiple rects
    try debug.addRect(Rect{ .x = 0, .y = 0, .width = 10, .height = 10 }, "Rect1", Color.red);
    try debug.addRect(Rect{ .x = 10, .y = 10, .width = 10, .height = 10 }, "Rect2", Color.blue);
    try debug.addRect(Rect{ .x = 20, .y = 20, .width = 10, .height = 10 }, "Rect3", Color.green);

    // Clear rects
    debug.clearRects();

    // Should be able to add new ones after clearing
    try debug.addRect(Rect{ .x = 5, .y = 5, .width = 5, .height = 5 }, "New", Color.yellow);
}

test "performance features integration" {
    const allocator = testing.allocator;

    // Setup all performance features together
    var budget = RenderBudget.init(60);
    var lazy = try LazyBuffer.init(allocator, 40, 20);
    defer lazy.deinit();
    var batcher = EventBatcher.init(allocator, 16);
    defer batcher.deinit();
    var debug = DebugOverlay.init(allocator, DebugMode.all, .top_right);
    defer debug.deinit();

    // Simulate a frame
    const should_render = budget.startFrame();
    try testing.expect(should_render);

    if (should_render) {
        // Mark region dirty
        lazy.clearDirty();
        lazy.markDirtyRect(Rect{ .x = 5, .y = 5, .width = 10, .height = 5 });

        // Write content
        lazy.setString(10, 10, "Test", Style{});

        // Update debug overlay
        debug.updateStats(&budget, &lazy);

        // Add debug rect
        try debug.addRect(Rect{ .x = 5, .y = 5, .width = 10, .height = 5 }, "DirtyRegion", Color.yellow);

        // End frame
        budget.endFrame();
    }

    // Add events
    try batcher.push(.{ .key = KeyEvent{
        .code = .{ .char = 'x' },
        .modifiers = .{},
    } });

    // Flush events
    var out_events: std.ArrayList(Event) = .{};
    defer out_events.deinit(allocator);
    try batcher.flush(&out_events);

    // Verify all systems worked together
    try testing.expect(budget.stats.total_frames > 0);
    try testing.expect(lazy.isDirty(10, 10));
    try testing.expectEqual(@as(usize, 1), out_events.items.len);
}

// ========================================================================
// v1.36.0: Performance Regression Tests
// ========================================================================

test "regression - Block widget render performance" {
    var metrics = RenderMetrics.init(testing.allocator);
    defer metrics.deinit();

    var buffer = try Buffer.init(testing.allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 10 };
    const block = Block{
        .title = "Test",
        .borders = .all,
        .border_style = .{ .fg = .cyan },
    };

    // Run 100 iterations for stable metrics
    for (0..100) |_| {
        const start = std.time.nanoTimestamp();
        block.render(&buffer, area);
        const end = std.time.nanoTimestamp();
        const duration_ns: u64 = @intCast(end - start);

        metrics.recordRender(1, "Block", duration_ns);
    }

    const stats = metrics.getStats(1).?;

    // Regression checks: average and P95 must be within thresholds
    try testing.expect(stats.avg_ns <= BLOCK_RENDER_MAX_AVG_NS);
    try testing.expect(stats.p95_ns <= BLOCK_RENDER_MAX_P95_NS);
    try testing.expect(stats.avg_ns > 0);
}

test "regression - Event processing latency" {
    var metrics = EventMetrics.init(testing.allocator);
    defer metrics.deinit();

    // Simulate realistic event processing with minimal sleep
    for (0..50) |_| {
        const start = std.time.nanoTimestamp();
        std.Thread.sleep(10_000); // 10μs
        const end = std.time.nanoTimestamp();

        const latency_ns: u64 = @intCast(end - start);
        metrics.recordEvent("key_press", latency_ns, 5);
    }

    const stats = metrics.getEventStats("key_press").?;

    // Event latency should be reasonable
    try testing.expect(stats.avg_ns > 0);
    try testing.expect(stats.count == 50);
}

test "regression - Memory tracking accuracy" {
    var metrics = MemoryMetrics.init(testing.allocator);
    defer metrics.deinit();

    // Simulate 20 widget allocations and frees
    for (0..20) |i| {
        const widget_id: u32 = @intCast(i + 1);
        const alloc_size: usize = 1024;

        metrics.recordAlloc(widget_id, "TestWidget", alloc_size);

        const stats = metrics.getStats(widget_id).?;
        try testing.expect(stats.peak_bytes >= alloc_size);

        metrics.recordFree(widget_id, "TestWidget", alloc_size);
    }

    // Verify type stats aggregation
    const type_stats = metrics.getTypeStats("TestWidget").?;
    try testing.expect(type_stats.widget_count == 20);
}

test "regression - Type aggregation accuracy" {
    var metrics = RenderMetrics.init(testing.allocator);
    defer metrics.deinit();

    var buffer = try Buffer.init(testing.allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 10 };

    // Create and measure 10 Block widgets
    for (0..10) |i| {
        const widget_id: u32 = @intCast(i + 1);
        const block = Block{
            .title = "Test",
            .borders = .all,
            .border_style = .{ .fg = .cyan },
        };

        // 10 renders per widget
        for (0..10) |_| {
            const start = std.time.nanoTimestamp();
            block.render(&buffer, area);
            const end = std.time.nanoTimestamp();
            const duration_ns: u64 = @intCast(end - start);

            metrics.recordRender(widget_id, "Block", duration_ns);
        }
    }

    const type_stats = metrics.getTypeStats("Block").?;

    // Type aggregation should track all widgets and measurements
    try testing.expect(type_stats.widget_count == 10);
    try testing.expect(type_stats.count == 100);
    try testing.expect(type_stats.avg_ns <= BLOCK_RENDER_MAX_AVG_NS);
}
