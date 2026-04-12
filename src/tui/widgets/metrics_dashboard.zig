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
