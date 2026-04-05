//! Metrics Dashboard Example - Performance Monitoring Demo
//!
//! Demonstrates:
//! - Real-time performance metrics visualization
//! - Render metrics (widget render times, P95/P99 percentiles)
//! - Memory metrics (allocation tracking, peak usage)
//! - Event metrics (event processing latency, queue depth)
//! - Three layout modes (vertical, horizontal, grid)
//!
//! Run with: zig build example-metrics-dashboard

const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const MetricsDashboard = sailor.tui.widgets.MetricsDashboard;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const layout = sailor.tui.layout;

const RenderMetrics = sailor.render_metrics.MetricsCollector;
const MemoryMetrics = sailor.memory_metrics.MemoryMetricsCollector;
const EventMetrics = sailor.event_metrics.EventMetricsCollector;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize metrics collectors
    var render_metrics = RenderMetrics.init(allocator);
    defer render_metrics.deinit();

    var memory_metrics = MemoryMetrics.init(allocator);
    defer memory_metrics.deinit();

    var event_metrics = EventMetrics.init(allocator);
    defer event_metrics.deinit();

    // Simulate some widget rendering metrics
    try simulateRenderMetrics(&render_metrics);

    // Simulate some memory allocations
    try simulateMemoryMetrics(&memory_metrics);

    // Simulate some event processing
    try simulateEventMetrics(&event_metrics);

    // Use fixed size for demo (avoids TTY requirement)
    const width: u16 = 80;
    const height: u16 = 30;

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    _ = Rect.new(0, 0, width, height);

    // Title
    buffer.setString(2, 0, "Sailor Performance Metrics Dashboard", Style{ .bold = true, .fg = Color{ .indexed = 14 } });

    // Metrics Dashboard (vertical layout)
    var dashboard = try MetricsDashboard.init(
        allocator,
        &render_metrics,
        &memory_metrics,
        &event_metrics,
    );
    defer dashboard.deinit();

    // Show metrics in vertical layout (from row 2)
    const dashboard_area = Rect.new(0, 2, width, height - 5);
    dashboard.setLayoutMode(.vertical);
    dashboard.setShowGraphs(false);
    try dashboard.render(&buffer, dashboard_area);

    // Footer
    const footer_y = height - 3;
    buffer.setString(0, footer_y, "Tip: MetricsDashboard supports vertical, horizontal, and grid layouts", Style{});
    buffer.setString(0, footer_y + 1, "Use setLayoutMode() to switch between them", Style{ .fg = Color{ .indexed = 8 } });

    // Report metrics (use first widget type from simulation)
    const render_stats = render_metrics.getTypeStats("Table");
    const memory_stats = memory_metrics.getTypeStats("Table");
    const event_stats = event_metrics.getTypeStats();

    std.debug.print("\n✓ Metrics Dashboard Example Completed\n", .{});
    std.debug.print("=====================================\n\n", .{});

    if (render_stats) |stats| {
        std.debug.print("Render Metrics (Table widgets):\n", .{});
        std.debug.print("  Count: {d}\n", .{stats.count});
        std.debug.print("  Avg: {d}ns, P95: {d}ns, P99: {d}ns\n\n", .{ stats.avg_ns, stats.p95_ns, stats.p99_ns });
    }

    if (memory_stats) |stats| {
        std.debug.print("Memory Metrics (Table widgets):\n", .{});
        std.debug.print("  Peak: {d} bytes\n", .{stats.peak_bytes});
        std.debug.print("  Total allocs: {d}\n\n", .{stats.total_allocs});
    }

    if (event_stats) |stats| {
        std.debug.print("Event Metrics (key_press):\n", .{});
        std.debug.print("  Count: {d}\n", .{stats.count});
        std.debug.print("  P95: {d}ns, P99: {d}ns\n", .{ stats.p95_ns, stats.p99_ns });
        std.debug.print("  Max queue depth: {d}\n\n", .{stats.queue_depth_max});
    }

    std.debug.print("Dashboard buffer: {d}x{d} cells (vertical layout)\n", .{ buffer.width, buffer.height });
    std.debug.print("Try setLayoutMode() to switch: .vertical, .horizontal, .grid\n", .{});
}

fn simulateRenderMetrics(metrics: *RenderMetrics) !void {
    // Simulate different widget types with varying render times
    const widget_types = [_][]const u8{
        "Block",
        "Paragraph",
        "List",
        "Table",
        "Gauge",
    };

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    // Record render times for each widget type (10 renders each)
    var widget_id: u32 = 0;
    for (widget_types) |widget_type| {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            // Base render time varies by widget complexity
            const base_time: u64 = switch (widget_type[0]) {
                'B' => 500, // Block - simple
                'P' => 800, // Paragraph - medium
                'L' => 1200, // List - medium-complex
                'T' => 2000, // Table - complex
                'G' => 600, // Gauge - simple
                else => 1000,
            };

            // Add some randomness (±30%)
            const variance = base_time * 30 / 100;
            const time = base_time + (random.uintLessThan(u64, variance * 2)) - variance;

            metrics.recordRender(widget_id, widget_type, time);
            widget_id += 1;
        }
    }
}

fn simulateMemoryMetrics(metrics: *MemoryMetrics) !void {
    // Simulate memory allocations for different widget types
    const widget_types = [_][]const u8{
        "Block",
        "Paragraph",
        "List",
        "Table",
        "Gauge",
    };

    var prng = std.Random.DefaultPrng.init(123);
    const random = prng.random();

    var widget_id: u32 = 0;
    for (widget_types) |widget_type| {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            // Base memory varies by widget complexity
            const base_mem: usize = switch (widget_type[0]) {
                'B' => 256, // Block - small
                'P' => 512, // Paragraph - medium
                'L' => 1024, // List - larger
                'T' => 4096, // Table - large
                'G' => 384, // Gauge - small-medium
                else => 512,
            };

            // Add some randomness (±20%)
            const variance = base_mem * 20 / 100;
            const mem = base_mem + (random.uintLessThan(usize, variance * 2)) - variance;

            metrics.recordAlloc(widget_id, widget_type, mem);
            widget_id += 1;
        }
    }
}

fn simulateEventMetrics(metrics: *EventMetrics) !void {
    // Simulate various event types with different latencies
    const event_types = [_][]const u8{
        "key_press",
        "mouse_move",
        "mouse_click",
        "resize",
        "focus",
    };

    var prng = std.Random.DefaultPrng.init(456);
    const random = prng.random();

    for (event_types) |event_type| {
        var i: usize = 0;
        while (i < 40) : (i += 1) {
            // Base latency varies by event type
            const base_latency: u64 = switch (event_type[0]) {
                'k' => 500, // key_press - fast
                'm' => if (event_type[6] == 'm') 200 else 400, // mouse_move vs mouse_click
                'r' => 2000, // resize - slower
                'f' => 300, // focus - fast
                else => 500,
            };

            // Add some randomness (±40%)
            const variance = base_latency * 40 / 100;
            const latency = base_latency + (random.uintLessThan(u64, variance * 2)) - variance;

            // Queue depth varies (mostly 0-2, occasionally higher)
            const queue_depth = if (random.uintLessThan(u8, 100) < 90)
                random.uintLessThan(u32, 3)
            else
                random.uintLessThan(u32, 10);

            metrics.recordEvent(event_type, latency, queue_depth);
        }
    }
}
