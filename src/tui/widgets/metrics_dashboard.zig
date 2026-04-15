//! MetricsDashboard widget — Real-time metrics visualization combining render, memory, and event metrics.
//!
//! MetricsDashboard provides a comprehensive view of application performance metrics
//! in a configurable layout. It displays render performance, memory usage, and event
//! processing statistics from three separate metrics collectors.
//!
//! ## Features
//! - Three layout modes: vertical, horizontal, grid
//! - Real-time metrics from render, memory, and event collectors
//! - Automatic unit formatting (ns/μs/ms for time, B/KB/MB for memory)
//! - Color-coded warnings for performance thresholds
//! - Optional graph visualization
//! - Graceful handling of empty metrics and small areas
//!
//! ## Usage
//! ```zig
//! var dashboard = try MetricsDashboard.init(
//!     allocator,
//!     &render_collector,
//!     &memory_collector,
//!     &event_collector,
//! );
//! defer dashboard.deinit();
//!
//! dashboard.setLayoutMode(.grid);
//! dashboard.setUpdateInterval(100);
//! try dashboard.render(&buffer, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;

const render_metrics = @import("../../render_metrics.zig");
const memory_metrics = @import("../../memory_metrics.zig");
const event_metrics = @import("../../event_metrics.zig");

/// Real-time metrics dashboard widget
pub const MetricsDashboard = struct {
    allocator: std.mem.Allocator,
    render_metrics: *render_metrics.MetricsCollector,
    memory_metrics: *memory_metrics.MemoryMetricsCollector,
    event_metrics: *event_metrics.EventMetricsCollector,
    layout_mode: LayoutMode,
    update_interval_ms: u64,
    show_graphs: bool,

    /// Layout mode for metrics sections
    pub const LayoutMode = enum {
        vertical,   // Stack sections top-to-bottom
        horizontal, // Place sections side-by-side
        grid,       // 2x2 layout
    };

    /// Initialize a new MetricsDashboard
    pub fn init(
        allocator: std.mem.Allocator,
        render_collector: *render_metrics.MetricsCollector,
        memory_collector: *memory_metrics.MemoryMetricsCollector,
        event_collector: *event_metrics.EventMetricsCollector,
    ) !MetricsDashboard {
        return .{
            .allocator = allocator,
            .render_metrics = render_collector,
            .memory_metrics = memory_collector,
            .event_metrics = event_collector,
            .layout_mode = .vertical,
            .update_interval_ms = 16, // ~60 FPS
            .show_graphs = true,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *MetricsDashboard) void {
        _ = self;
        // No resources to clean up currently
    }

    /// Set the layout mode
    pub fn setLayoutMode(self: *MetricsDashboard, mode: LayoutMode) void {
        self.layout_mode = mode;
    }

    /// Set the update interval in milliseconds
    pub fn setUpdateInterval(self: *MetricsDashboard, interval_ms: u64) void {
        self.update_interval_ms = interval_ms;
    }

    /// Enable or disable graph visualization
    pub fn setShowGraphs(self: *MetricsDashboard, show: bool) void {
        self.show_graphs = show;
    }

    /// Render the dashboard
    pub fn render(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        switch (self.layout_mode) {
            .vertical => try self.renderVertical(buf, area),
            .horizontal => try self.renderHorizontal(buf, area),
            .grid => try self.renderGrid(buf, area),
        }
    }

    fn renderVertical(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        // Split area into three sections vertically
        const section_height = area.height / 3;
        if (section_height == 0) return;

        const render_area = Rect{ .x = area.x, .y = area.y, .width = area.width, .height = section_height };
        const memory_area = Rect{ .x = area.x, .y = area.y + section_height, .width = area.width, .height = section_height };
        const event_area = Rect{ .x = area.x, .y = area.y + section_height * 2, .width = area.width, .height = area.height - section_height * 2 };

        try self.renderRenderMetrics(buf, render_area);
        try self.renderMemoryMetrics(buf, memory_area);
        try self.renderEventMetrics(buf, event_area);
    }

    fn renderHorizontal(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        // Split area into three sections horizontally
        const section_width = area.width / 3;
        if (section_width == 0) return;

        const render_area = Rect{ .x = area.x, .y = area.y, .width = section_width, .height = area.height };
        const memory_area = Rect{ .x = area.x + section_width, .y = area.y, .width = section_width, .height = area.height };
        const event_area = Rect{ .x = area.x + section_width * 2, .y = area.y, .width = area.width - section_width * 2, .height = area.height };

        try self.renderRenderMetrics(buf, render_area);
        try self.renderMemoryMetrics(buf, memory_area);
        try self.renderEventMetrics(buf, event_area);
    }

    fn renderGrid(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        // 2x2 grid: render/memory top row, event/summary bottom row
        const half_width = area.width / 2;
        const half_height = area.height / 2;
        if (half_width == 0 or half_height == 0) return;

        const render_area = Rect{ .x = area.x, .y = area.y, .width = half_width, .height = half_height };
        const memory_area = Rect{ .x = area.x + half_width, .y = area.y, .width = area.width - half_width, .height = half_height };
        const event_area = Rect{ .x = area.x, .y = area.y + half_height, .width = area.width, .height = area.height - half_height };

        try self.renderRenderMetrics(buf, render_area);
        try self.renderMemoryMetrics(buf, memory_area);
        try self.renderEventMetrics(buf, event_area);
    }

    fn renderRenderMetrics(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        if (area.width < 20 or area.height < 2) return;

        // Header
        const header = "Render Metrics";
        const header_style = Style{ .fg = .cyan, .bold = true };
        buf.setString(area.x, area.y, header, header_style);

        // Draw separator
        if (area.height > 1 and area.width > 0) {
            for (0..area.width) |offset| {
                buf.set(area.x + @as(u16, @intCast(offset)), area.y + 1, .{ .char = '─', .style = .{} });
            }
        }

        // Get aggregated type stats (all widgets)
        const maybe_stats = self.render_metrics.getTypeStats("");
        if (maybe_stats == null) {
            // No data yet
            if (area.height > 2) {
                buf.setString(area.x, area.y + 2, "No data", .{ .fg = .bright_black });
            }
            return;
        }

        const stats = maybe_stats.?;
        var y: u16 = area.y + 2;

        // Widget count
        if (y < area.y + area.height) {
            const count_str = try std.fmt.allocPrint(self.allocator, "Widgets: {d}", .{stats.widget_count});
            defer self.allocator.free(count_str);
            buf.setString(area.x, y, count_str, .{});
            y += 1;
        }

        // Average render time
        if (y < area.y + area.height) {
            const avg_str = try formatTime(self.allocator, stats.avg_ns);
            defer self.allocator.free(avg_str);
            const label = try std.fmt.allocPrint(self.allocator, "Avg: {s}", .{avg_str});
            defer self.allocator.free(label);
            buf.setString(area.x, y, label, .{});
            y += 1;
        }

        // P95
        if (y < area.y + area.height) {
            const p95_str = try formatTime(self.allocator, stats.p95_ns);
            defer self.allocator.free(p95_str);
            const label = try std.fmt.allocPrint(self.allocator, "P95: {s}", .{p95_str});
            defer self.allocator.free(label);

            // Warn if p95 > 10ms
            const p95_style = if (stats.p95_ns > 10_000_000) Style{ .fg = .yellow } else Style{};
            buf.setString(area.x, y, label, p95_style);
            y += 1;
        }

        // P99
        if (y < area.y + area.height) {
            const p99_str = try formatTime(self.allocator, stats.p99_ns);
            defer self.allocator.free(p99_str);
            const label = try std.fmt.allocPrint(self.allocator, "P99: {s}", .{p99_str});
            defer self.allocator.free(label);

            // Warn if p99 > 10ms
            const p99_style = if (stats.p99_ns > 10_000_000) Style{ .fg = .red } else Style{};
            buf.setString(area.x, y, label, p99_style);
            y += 1;
        }

        _ = self.show_graphs; // Future: render sparklines
    }

    fn renderMemoryMetrics(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        if (area.width < 20 or area.height < 2) return;

        // Header
        const header = "Memory Metrics";
        const header_style = Style{ .fg = .green, .bold = true };
        buf.setString(area.x, area.y, header, header_style);

        // Draw separator
        if (area.height > 1 and area.width > 0) {
            for (0..area.width) |offset| {
                buf.set(area.x + @as(u16, @intCast(offset)), area.y + 1, .{ .char = '─', .style = .{} });
            }
        }

        // Get aggregated type stats
        const maybe_stats = self.memory_metrics.getTypeStats("");
        if (maybe_stats == null) {
            if (area.height > 2) {
                buf.setString(area.x, area.y + 2, "No data", .{ .fg = .bright_black });
            }
            return;
        }

        const stats = maybe_stats.?;
        var y: u16 = area.y + 2;

        // Peak memory
        if (y < area.y + area.height) {
            const peak_str = try formatMemory(self.allocator, stats.peak_bytes);
            defer self.allocator.free(peak_str);
            const label = try std.fmt.allocPrint(self.allocator, "Peak: {s}", .{peak_str});
            defer self.allocator.free(label);
            buf.setString(area.x, y, label, .{});
            y += 1;
        }

        // Current memory
        if (y < area.y + area.height) {
            const current_str = try formatMemory(self.allocator, stats.current_bytes);
            defer self.allocator.free(current_str);
            const label = try std.fmt.allocPrint(self.allocator, "Current: {s}", .{current_str});
            defer self.allocator.free(label);
            buf.setString(area.x, y, label, .{});
            y += 1;
        }

        // Alloc count
        if (y < area.y + area.height) {
            const label = try std.fmt.allocPrint(self.allocator, "Allocs: {d}", .{stats.total_allocs});
            defer self.allocator.free(label);
            buf.setString(area.x, y, label, .{});
            y += 1;
        }

        // Free count
        if (y < area.y + area.height) {
            const label = try std.fmt.allocPrint(self.allocator, "Frees: {d}", .{stats.total_frees});
            defer self.allocator.free(label);
            buf.setString(area.x, y, label, .{});
            y += 1;
        }
    }

    fn renderEventMetrics(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        if (area.width < 20 or area.height < 2) return;

        // Header
        const header = "Event Metrics";
        const header_style = Style{ .fg = .magenta, .bold = true };
        buf.setString(area.x, area.y, header, header_style);

        // Draw separator
        if (area.height > 1 and area.width > 0) {
            for (0..area.width) |offset| {
                buf.set(area.x + @as(u16, @intCast(offset)), area.y + 1, .{ .char = '─', .style = .{} });
            }
        }

        // Get aggregated type stats
        const maybe_stats = self.event_metrics.getTypeStats();
        if (maybe_stats == null) {
            if (area.height > 2) {
                buf.setString(area.x, area.y + 2, "No data", .{ .fg = .bright_black });
            }
            return;
        }

        const stats = maybe_stats.?;
        var y: u16 = area.y + 2;

        // Event count
        if (y < area.y + area.height) {
            const label = try std.fmt.allocPrint(self.allocator, "Events: {d}", .{stats.count});
            defer self.allocator.free(label);
            buf.setString(area.x, y, label, .{});
            y += 1;
        }

        // P95 latency
        if (y < area.y + area.height) {
            const p95_str = try formatTime(self.allocator, stats.p95_ns);
            defer self.allocator.free(p95_str);
            const label = try std.fmt.allocPrint(self.allocator, "P95: {s}", .{p95_str});
            defer self.allocator.free(label);

            const p95_style = if (stats.p95_ns > 10_000_000) Style{ .fg = .yellow } else Style{};
            buf.setString(area.x, y, label, p95_style);
            y += 1;
        }

        // P99 latency
        if (y < area.y + area.height) {
            const p99_str = try formatTime(self.allocator, stats.p99_ns);
            defer self.allocator.free(p99_str);
            const label = try std.fmt.allocPrint(self.allocator, "P99: {s}", .{p99_str});
            defer self.allocator.free(label);

            const p99_style = if (stats.p99_ns > 10_000_000) Style{ .fg = .red } else Style{};
            buf.setString(area.x, y, label, p99_style);
            y += 1;
        }

        // Max queue depth
        if (y < area.y + area.height) {
            const label = try std.fmt.allocPrint(self.allocator, "Max Queue: {d}", .{stats.queue_depth_max});
            defer self.allocator.free(label);
            buf.setString(area.x, y, label, .{});
            y += 1;
        }
    }
};

/// Format time in nanoseconds to human-readable string
fn formatTime(allocator: std.mem.Allocator, ns: u64) ![]const u8 {
    if (ns < 1000) {
        return std.fmt.allocPrint(allocator, "{d}ns", .{ns});
    } else if (ns < 1_000_000) {
        const us = @as(f64, @floatFromInt(ns)) / 1000.0;
        return std.fmt.allocPrint(allocator, "{d:.2}μs", .{us});
    } else {
        const ms = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
        return std.fmt.allocPrint(allocator, "{d:.2}ms", .{ms});
    }
}

/// Format memory in bytes to human-readable string
fn formatMemory(allocator: std.mem.Allocator, bytes: usize) ![]const u8 {
    const kb: usize = 1024;
    const mb: usize = kb * 1024;

    if (bytes >= mb) {
        const mb_f = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(mb));
        return std.fmt.allocPrint(allocator, "{d:.2}MB", .{mb_f});
    } else if (bytes >= kb) {
        const kb_f = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(kb));
        return std.fmt.allocPrint(allocator, "{d:.2}KB", .{kb_f});
    } else {
        return std.fmt.allocPrint(allocator, "{d}B", .{bytes});
    }
}

// ============================================================================
// Tests
// ============================================================================

test "MetricsDashboard - init and deinit" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    try std.testing.expectEqual(MetricsDashboard.LayoutMode.vertical, dashboard.layout_mode);
    try std.testing.expectEqual(16, dashboard.update_interval_ms);
    try std.testing.expect(dashboard.show_graphs);
}

test "MetricsDashboard - setLayoutMode" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    dashboard.setLayoutMode(.horizontal);
    try std.testing.expectEqual(MetricsDashboard.LayoutMode.horizontal, dashboard.layout_mode);

    dashboard.setLayoutMode(.grid);
    try std.testing.expectEqual(MetricsDashboard.LayoutMode.grid, dashboard.layout_mode);
}

test "MetricsDashboard - setUpdateInterval" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    dashboard.setUpdateInterval(100);
    try std.testing.expectEqual(100, dashboard.update_interval_ms);
}

test "MetricsDashboard - setShowGraphs" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    dashboard.setShowGraphs(false);
    try std.testing.expect(!dashboard.show_graphs);

    dashboard.setShowGraphs(true);
    try std.testing.expect(dashboard.show_graphs);
}

test "MetricsDashboard - render empty area" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    // Zero-size area should not crash
    try dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 0 });
    try dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 24 });
}

test "MetricsDashboard - render vertical layout" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    dashboard.setLayoutMode(.vertical);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try dashboard.render(&buf, area);

    // Should not crash, no verification of content in unit tests
}

test "MetricsDashboard - render horizontal layout" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    dashboard.setLayoutMode(.horizontal);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try dashboard.render(&buf, area);
}

test "MetricsDashboard - render grid layout" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    dashboard.setLayoutMode(.grid);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try dashboard.render(&buf, area);
}

test "MetricsDashboard - render small area" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit(allocator);

    // Small area should not crash
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try dashboard.render(&buf, area);
}

test "MetricsDashboard - render with metrics data" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    // Record some sample metrics
    try render_collector.record("test_widget", 1_000_000); // 1ms
    try render_collector.record("test_widget", 2_000_000); // 2ms
    try memory_collector.recordAlloc("test", 1024);
    try memory_collector.recordFree("test", 512);
    try event_collector.record(100_000); // 100μs

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try dashboard.render(&buf, area);

    // Should render without errors
}

test "formatTime - nanoseconds" {
    const allocator = std.testing.allocator;

    const str = try formatTime(allocator, 999);
    defer allocator.free(str);

    try std.testing.expect(std.mem.eql(u8, str, "999ns"));
}

test "formatTime - microseconds" {
    const allocator = std.testing.allocator;

    const str = try formatTime(allocator, 1500);
    defer allocator.free(str);

    try std.testing.expect(std.mem.startsWith(u8, str, "1.50"));
    try std.testing.expect(std.mem.endsWith(u8, str, "μs"));
}

test "formatTime - milliseconds" {
    const allocator = std.testing.allocator;

    const str = try formatTime(allocator, 2_500_000);
    defer allocator.free(str);

    try std.testing.expect(std.mem.startsWith(u8, str, "2.50"));
    try std.testing.expect(std.mem.endsWith(u8, str, "ms"));
}

test "formatMemory - bytes" {
    const allocator = std.testing.allocator;

    const str = try formatMemory(allocator, 999);
    defer allocator.free(str);

    try std.testing.expect(std.mem.eql(u8, str, "999B"));
}

test "formatMemory - kilobytes" {
    const allocator = std.testing.allocator;

    const str = try formatMemory(allocator, 2048);
    defer allocator.free(str);

    try std.testing.expect(std.mem.startsWith(u8, str, "2.00"));
    try std.testing.expect(std.mem.endsWith(u8, str, "KB"));
}

test "formatMemory - megabytes" {
    const allocator = std.testing.allocator;

    const str = try formatMemory(allocator, 3 * 1024 * 1024);
    defer allocator.free(str);

    try std.testing.expect(std.mem.startsWith(u8, str, "3.00"));
    try std.testing.expect(std.mem.endsWith(u8, str, "MB"));
}

test "MetricsDashboard - all three layout modes without crash" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    // Test all three modes in sequence
    dashboard.setLayoutMode(.vertical);
    try dashboard.render(&buf, area);

    dashboard.setLayoutMode(.horizontal);
    try dashboard.render(&buf, area);

    dashboard.setLayoutMode(.grid);
    try dashboard.render(&buf, area);
}

test "MetricsDashboard - edge case: very small buffer" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    // 1x1 buffer
    var buf = try Buffer.init(allocator, 1, 1);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    // Should handle gracefully without crashes
    try dashboard.render(&buf, area);
}

test "MetricsDashboard - boundary: exactly 20x2 (minimum meaningful size)" {
    const allocator = std.testing.allocator;

    var render_collector = render_metrics.MetricsCollector.init(allocator);
    defer render_collector.deinit();

    var memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
    defer memory_collector.deinit();

    var event_collector = event_metrics.EventMetricsCollector.init(allocator);
    defer event_collector.deinit();

    var dashboard = try MetricsDashboard.init(allocator, &render_collector, &memory_collector, &event_collector);
    defer dashboard.deinit();

    var buf = try Buffer.init(allocator, 20, 2);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 2 };

    // Should render minimal content
    try dashboard.render(&buf, area);
}

test "formatTime - boundary values" {
    const allocator = std.testing.allocator;

    // Exactly 1000ns (threshold to μs)
    {
        const str = try formatTime(allocator, 1000);
        defer allocator.free(str);
        try std.testing.expect(std.mem.endsWith(u8, str, "μs"));
    }

    // Exactly 1_000_000ns (threshold to ms)
    {
        const str = try formatTime(allocator, 1_000_000);
        defer allocator.free(str);
        try std.testing.expect(std.mem.endsWith(u8, str, "ms"));
    }
}

test "formatMemory - boundary values" {
    const allocator = std.testing.allocator;

    // Exactly 1KB
    {
        const str = try formatMemory(allocator, 1024);
        defer allocator.free(str);
        try std.testing.expect(std.mem.endsWith(u8, str, "KB"));
    }

    // Exactly 1MB
    {
        const str = try formatMemory(allocator, 1024 * 1024);
        defer allocator.free(str);
        try std.testing.expect(std.mem.endsWith(u8, str, "MB"));
    }
}
