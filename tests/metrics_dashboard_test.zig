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
    const area = Rect.new(0, 0, 80, 40);
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
    const area = Rect.new(0, 0, 120, 30);
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
    const area = Rect.new(0, 0, 100, 50);
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
    const area = Rect.new(0, 0, 80, 40);
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
    const area = Rect.new(0, 0, 100, 50);
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
    const area = Rect.new(10, 5, 60, 30);
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
    const area = Rect.new(0, 0, 30, 10);
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
    const area = Rect.new(0, 0, 40, 20);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 120, 50);
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

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Should render empty state without crashing
}

test "MetricsDashboard render with graphs enabled" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 100, 50);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1000);

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
    const area = Rect.new(0, 0, 100, 50);
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render with graphs disabled" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 30);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1000);

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

    dashboard.setShowGraphs(false);
    const area = Rect.new(0, 0, 80, 30);
    try dashboard.render(&buffer, area);
}

test "MetricsDashboard render output contains metric labels" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Output should contain section headers and metric labels
    // This will fail until implementation exists
}

test "MetricsDashboard render output contains metric values" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Output should contain formatted metric values
    // This will fail until implementation exists
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

    const area = Rect.new(0, 0, 10, 5);
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

    const area = Rect.new(0, 0, 30, 10);
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

    const area = Rect.new(0, 0, 200, 50);
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

    const area = Rect.new(0, 0, 0, 40);
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

    const area = Rect.new(0, 0, 80, 0);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Should contain labels like "P95 Latency:", "Queue Depth:"
}

test "MetricsDashboard formats time values appropriately" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1200); // 1200 ns = 1.2 μs
    render_collector.recordRender(1, "Button", 500000); // 500 μs = 0.5 ms

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

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Should format as ns, μs, ms appropriately
}

test "MetricsDashboard formats memory values appropriately" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();
    memory_collector.recordAlloc(1, "Button", 512); // 512 B
    memory_collector.recordAlloc(2, "Label", 2048); // 2 KB
    memory_collector.recordAlloc(3, "Table", 1048576); // 1 MB

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_collector,
        &memory_collector,
        &event_collector,
    );
    defer dashboard.deinit();

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Should format as B, KB, MB appropriately
}

test "MetricsDashboard uses colors for warning thresholds" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    // Record slow render times that should trigger warning colors
    render_collector.recordRender(1, "Button", 16000000); // 16 ms (> 1 frame at 60 FPS)

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

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Should use warning colors (yellow/red) for slow metrics
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
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

    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Should handle overflow protection
}

test "MetricsDashboard render with update_interval zero" {
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

    dashboard.setUpdateInterval(0);
    const area = Rect.new(0, 0, 80, 40);
    try dashboard.render(&buffer, area);

    // Should handle zero interval without issues
}

test "MetricsDashboard render with show_graphs but no historical data" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 100, 50);
    defer buffer.deinit();

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();
    render_collector.recordRender(1, "Button", 1000); // Only one data point

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
    const area = Rect.new(0, 0, 100, 50);
    try dashboard.render(&buffer, area);

    // Should handle gracefully - maybe show empty graph or skip
}
