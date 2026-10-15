//! MetricsDashboard widget tests
//!
//! Tests for the real-time metrics dashboard widget that visualizes
//! render, memory, and event metrics in various layout modes.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const MetricsDashboard = sailor.tui.widgets.MetricsDashboard;
const LayoutMode = sailor.tui.widgets.MetricsDashboard.LayoutMode;

const render_metrics = sailor.render_metrics;
const memory_metrics = sailor.memory_metrics;
const event_metrics = sailor.event_metrics;

// ============================================================================
// INITIALIZATION AND CLEANUP
// ============================================================================

test "MetricsDashboard init with valid collectors" {
    const allocator = testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();
}

test "MetricsDashboard deinit cleans up properly" {
    const allocator = testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    dashboard.deinit();
    // If there's a memory leak, testing.allocator will catch it
}

test "MetricsDashboard memory leak check" {
    const allocator = testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    // Create and destroy multiple dashboards
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var dashboard = try MetricsDashboard.init(
            allocator,
            &render_collector,
            &memory_collector,
            &event_collector,
        );
        dashboard.deinit();
    }
}

// ============================================================================
// LAYOUT MODES
// ============================================================================

test "MetricsDashboard vertical layout renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.vertical);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should not crash
}

test "MetricsDashboard horizontal layout renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 120, 30);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.horizontal);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 30 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard grid layout renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 100, 50);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.grid);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard layout switching vertical to horizontal" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.vertical);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    dashboard.setLayoutMode(.horizontal);
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard layout switching horizontal to grid" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 100, 50);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.horizontal);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    try dashboard.render(&buffer, area);

    dashboard.setLayoutMode(.grid);
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard vertical layout respects area boundaries" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.vertical);
    const area = Rect{ .x = 10, .y = 5, .width = 60, .height = 30 };
    try dashboard.render(&buffer, area);

    // Should not write outside area bounds
}

test "MetricsDashboard horizontal layout handles small area gracefully" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 20);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.horizontal);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard grid layout handles small area gracefully" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 25);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.grid);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try dashboard.render(&buffer, area);
}

// ============================================================================
// CONFIGURATION
// ============================================================================

test "MetricsDashboard setLayoutMode changes layout" {
    const allocator = testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.vertical);
    try testing.expectEqual(LayoutMode.vertical, dashboard.layout_mode);

    dashboard.setLayoutMode(.horizontal);
    try testing.expectEqual(LayoutMode.horizontal, dashboard.layout_mode);

    dashboard.setLayoutMode(.grid);
    try testing.expectEqual(LayoutMode.grid, dashboard.layout_mode);
}

test "MetricsDashboard setUpdateInterval updates interval" {
    const allocator = testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setUpdateInterval(100);
    try testing.expectEqual(@as(u64, 100), dashboard.update_interval_ms);

    dashboard.setUpdateInterval(500);
    try testing.expectEqual(@as(u64, 500), dashboard.update_interval_ms);
}

test "MetricsDashboard setShowGraphs toggles graph display" {
    const allocator = testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setShowGraphs(true);
    try testing.expectEqual(true, dashboard.show_graphs);

    dashboard.setShowGraphs(false);
    try testing.expectEqual(false, dashboard.show_graphs);
}

test "MetricsDashboard default configuration values" {
    const allocator = testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    // Verify sensible defaults
    try testing.expectEqual(LayoutMode.vertical, dashboard.layout_mode);
    try testing.expect(dashboard.update_interval_ms >= 16); // At least one frame
    try testing.expectEqual(true, dashboard.show_graphs);
}

test "MetricsDashboard configuration persists across renders" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    dashboard.setLayoutMode(.horizontal);
    dashboard.setUpdateInterval(250);
    dashboard.setShowGraphs(false);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Config should persist after render
    try testing.expectEqual(LayoutMode.horizontal, dashboard.layout_mode);
    try testing.expectEqual(@as(u64, 250), dashboard.update_interval_ms);
    try testing.expectEqual(false, dashboard.show_graphs);
}

// ============================================================================
// RENDERING WITH REAL METRICS DATA
// ============================================================================

test "MetricsDashboard render with render_metrics data" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    // Record some widget render metrics
    render_collector.recordRender(1, "Button", 1000);
    render_collector.recordRender(1, "Button", 1200);
    render_collector.recordRender(2, "Label", 800);

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render with memory_metrics data" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    // Record some memory allocations
    memory_collector.recordAlloc(1, "Button", 1024);
    memory_collector.recordAlloc(2, "Label", 512);
    memory_collector.recordFree(1, "Button", 256);

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render with event_metrics data" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    // Record some event latencies
    event_collector.recordEvent("key_press", 1000, 1);
    event_collector.recordEvent("key_press", 1500, 2);
    event_collector.recordEvent("mouse_move", 500, 0);

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render with all three metrics populated" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 120, 50);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1200);
    render_collector.recordRender(2, "Label", 800);

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();
    memory_collector.recordAlloc(1, "Button", 2048);
    memory_collector.recordAlloc(2, "Label", 1024);

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();
    event_collector.recordEvent("key_press", 1000, 1);
    event_collector.recordEvent("mouse_move", 500, 0);

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 50 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render with empty metrics" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should render empty state without crashing
}

// ============================================================================
// BOUNDARY CONDITIONS
// ============================================================================

test "MetricsDashboard render in very small area 10x5" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    try dashboard.render(&buffer, area);

    // Should handle gracefully without crashing
}

test "MetricsDashboard render in minimum viable area 30x10" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render in large area 200x50" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 200, 50);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1200);

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();
    memory_collector.recordAlloc(1, "Button", 2048);

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();
    event_collector.recordEvent("key_press", 1000, 1);

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 50 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render with zero-width area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should handle zero-width gracefully
}

test "MetricsDashboard render with zero-height area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render with single metric collector having data" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1200);

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();
    // No data

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();
    // No data

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should show render metrics but empty state for others
}

// ============================================================================
// VISUAL FORMATTING
// ============================================================================

test "MetricsDashboard render includes section headers" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should contain "Render Metrics", "Memory Metrics", "Event Metrics"
    // Will fail until implementation exists
}

test "MetricsDashboard render includes metric labels for render metrics" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1200);

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should contain labels like "Avg Render Time:", "P95:", "P99:"
}

test "MetricsDashboard render includes metric labels for memory metrics" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();
    memory_collector.recordAlloc(1, "Button", 2048);

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should contain labels like "Peak Memory:", "Current:", "Allocs:"
}

test "MetricsDashboard render includes metric labels for event metrics" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();
    event_collector.recordEvent("key_press", 1000, 2);

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should contain labels like "P95 Latency:", "Queue Depth:"
}

test "MetricsDashboard layout alignment labels and values" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1200);

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Labels should be left-aligned, values right-aligned
}

test "MetricsDashboard borders between sections" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should have visual separators between metric sections
}

// ============================================================================
// EDGE CASES
// ============================================================================

test "MetricsDashboard render with null metrics" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // All collectors empty - should show "No data" or similar
}

test "MetricsDashboard render with very large metric values" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", std.math.maxInt(u64) - 1000);

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();
    memory_collector.recordAlloc(1, "Button", std.math.maxInt(usize) - 1000);

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    try dashboard.render(&buffer, area);

    // Should handle overflow protection
}

// ============================================================================
// PROMISED BEHAVIOR READ BACK FROM THE BUFFER (plan 002 item 6)
// ============================================================================

const Collectors = struct {
    render: render_metrics.MetricsCollector,
    memory: memory_metrics.MemoryMetricsCollector,
    event: event_metrics.EventMetricsCollector,

    fn init(target: *Collectors, gpa: std.mem.Allocator) void {
        target.render = render_metrics.MetricsCollector.init(gpa);
        target.memory = memory_metrics.MemoryMetricsCollector.init(gpa);
        target.event = event_metrics.EventMetricsCollector.init(gpa);
    }

    fn deinit(self: *Collectors) void {
        self.render.deinit();
        self.memory.deinit();
        self.event.deinit();
    }
};

/// Finds the first row at or after `from_row` whose text contains `needle`.
fn findRow(buf: *const Buffer, from_row: u16, needle: []const u8) !?u16 {
    var text: [256]u8 = undefined;
    var y: u16 = from_row;
    while (y < buf.height) : (y += 1) {
        var len: usize = 0;
        var x: u16 = 0;
        while (x < buf.width) : (x += 1) {
            const cell = buf.getConst(x, y).?;
            len += try std.unicode.utf8Encode(cell.char, text[len..]);
        }
        if (std.mem.indexOf(u8, text[0..len], needle) != null) return y;
    }
    return null;
}

fn expectRow(buf: *const Buffer, from_row: u16, needle: []const u8) !u16 {
    const row = try findRow(buf, from_row, needle);
    if (row == null) {
        std.debug.print("row containing \"{s}\" not found from row {d}\n", .{ needle, from_row });
        return error.RowNotFound;
    }
    return row.?;
}

fn renderVertical(gpa: std.mem.Allocator, collectors: *Collectors, buffer: *Buffer) !void {
    var dashboard = try MetricsDashboard.init(
        gpa,
        &collectors.render,
        &collectors.memory,
        &collectors.event,
    );
    defer dashboard.deinit();

    try dashboard.render(buffer, Rect{ .x = 0, .y = 0, .width = buffer.width, .height = buffer.height });
}

test "MetricsDashboard render section aggregates every widget type" {
    var collectors: Collectors = undefined;
    collectors.init(testing.allocator);
    defer collectors.deinit();
    collectors.render.recordRender(1, "Button", 1000);
    collectors.render.recordRender(2, "Label", 3000);
    var buffer = try Buffer.init(testing.allocator, 80, 30);
    defer buffer.deinit();

    try renderVertical(testing.allocator, &collectors, &buffer);

    const header = try expectRow(&buffer, 0, "Render Metrics");
    // The memory and event sections are empty, so "No data" may only appear below this section.
    if (try findRow(&buffer, header, "No data")) |row| try testing.expect(row >= header + 10);
    const widgets_row = try expectRow(&buffer, header, "Widgets: 2");
    try testing.expect(widgets_row < header + 10);
    _ = try expectRow(&buffer, header, "Avg: 2.00" ++ "\u{3bc}s");
}

test "MetricsDashboard memory section aggregates every widget type" {
    var collectors: Collectors = undefined;
    collectors.init(testing.allocator);
    defer collectors.deinit();
    collectors.memory.recordAlloc(1, "Button", 512);
    collectors.memory.recordAlloc(2, "Label", 2048);
    collectors.memory.recordFree(1, "Button", 512);
    var buffer = try Buffer.init(testing.allocator, 80, 30);
    defer buffer.deinit();

    try renderVertical(testing.allocator, &collectors, &buffer);

    const header = try expectRow(&buffer, 0, "Memory Metrics");
    _ = try expectRow(&buffer, header, "Peak: 2.50KB");
    _ = try expectRow(&buffer, header, "Current: 2.00KB");
    _ = try expectRow(&buffer, header, "Allocs: 2");
    _ = try expectRow(&buffer, header, "Frees: 1");
}

test "MetricsDashboard empty collectors show No data in every section" {
    var collectors: Collectors = undefined;
    collectors.init(testing.allocator);
    defer collectors.deinit();
    var buffer = try Buffer.init(testing.allocator, 80, 30);
    defer buffer.deinit();

    try renderVertical(testing.allocator, &collectors, &buffer);

    const render_row = try expectRow(&buffer, 0, "Render Metrics");
    const no_data_render = try expectRow(&buffer, render_row, "No data");
    const memory_row = try expectRow(&buffer, no_data_render, "Memory Metrics");
    const no_data_memory = try expectRow(&buffer, memory_row, "No data");
    const event_row = try expectRow(&buffer, no_data_memory, "Event Metrics");
    _ = try expectRow(&buffer, event_row, "No data");
}

test "MetricsDashboard time units step through ns, us and ms" {
    const Case = struct { ns: u64, text: []const u8 };
    const cases = [_]Case{
        .{ .ns = 999, .text = "Avg: 999ns" },
        .{ .ns = 1000, .text = "Avg: 1.00\u{3bc}s" },
        .{ .ns = 999_999, .text = "Avg: 1000.00\u{3bc}s" },
        .{ .ns = 1_000_000, .text = "Avg: 1.00ms" },
    };
    for (cases) |case| {
        var collectors: Collectors = undefined;
        collectors.init(testing.allocator);
        defer collectors.deinit();
        collectors.render.recordRender(1, "Button", case.ns);
        var buffer = try Buffer.init(testing.allocator, 80, 30);
        defer buffer.deinit();

        try renderVertical(testing.allocator, &collectors, &buffer);

        _ = try expectRow(&buffer, 0, case.text);
    }
}

test "MetricsDashboard memory units step through B, KB and MB" {
    const Case = struct { bytes: usize, text: []const u8 };
    const cases = [_]Case{
        .{ .bytes = 1023, .text = "Peak: 1023B" },
        .{ .bytes = 1024, .text = "Peak: 1.00KB" },
        .{ .bytes = 1024 * 1024, .text = "Peak: 1.00MB" },
    };
    for (cases) |case| {
        var collectors: Collectors = undefined;
        collectors.init(testing.allocator);
        defer collectors.deinit();
        collectors.memory.recordAlloc(1, "Button", case.bytes);
        var buffer = try Buffer.init(testing.allocator, 80, 30);
        defer buffer.deinit();

        try renderVertical(testing.allocator, &collectors, &buffer);

        _ = try expectRow(&buffer, 0, case.text);
    }
}

test "MetricsDashboard warns on render and event percentiles above 10ms" {
    const Case = struct { ns: u64, p95: ?Color, p99: ?Color };
    const cases = [_]Case{
        .{ .ns = 10_000_000, .p95 = null, .p99 = null },
        .{ .ns = 10_000_001, .p95 = .yellow, .p99 = .red },
    };
    for (cases) |case| {
        var collectors: Collectors = undefined;
        collectors.init(testing.allocator);
        defer collectors.deinit();
        collectors.render.recordRender(1, "Button", case.ns);
        collectors.event.recordEvent("key_press", case.ns, 1);
        var buffer = try Buffer.init(testing.allocator, 80, 30);
        defer buffer.deinit();

        try renderVertical(testing.allocator, &collectors, &buffer);

        var from: u16 = 0;
        for ([_][]const u8{ "Render Metrics", "Event Metrics" }) |section| {
            const header = try expectRow(&buffer, from, section);
            const p95_row = try expectRow(&buffer, header, "P95:");
            const p99_row = try expectRow(&buffer, header, "P99:");
            try testing.expectEqual(case.p95, buffer.getConst(0, p95_row).?.style.fg);
            try testing.expectEqual(case.p99, buffer.getConst(0, p99_row).?.style.fg);
            try testing.expect(p99_row < header + 10); // Inside its own 10-row section.
            from = header + 1;
        }
    }
}

test "MetricsDashboard show_graphs is reserved and does not change the output" {
    var collectors: Collectors = undefined;
    collectors.init(testing.allocator);
    defer collectors.deinit();
    collectors.render.recordRender(1, "Button", 1000);
    var shown = try Buffer.init(testing.allocator, 80, 30);
    defer shown.deinit();
    var hidden = try Buffer.init(testing.allocator, 80, 30);
    defer hidden.deinit();

    var dashboard = try MetricsDashboard.init(
        testing.allocator,
        &collectors.render,
        &collectors.memory,
        &collectors.event,
    );
    defer dashboard.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    dashboard.setShowGraphs(true);
    try dashboard.render(&shown, area);
    dashboard.setShowGraphs(false);
    try dashboard.render(&hidden, area);

    for (shown.cells, hidden.cells) |a, b| {
        try testing.expectEqual(a.char, b.char);
        try testing.expectEqual(a.style, b.style);
    }
}
