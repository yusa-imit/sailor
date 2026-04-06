//! MetricsPanel widget — real-time metrics display with thresholds
//!
//! MetricsPanel renders multiple metrics (CPU, memory, network, custom) with
//! threshold-based coloring and optional sparkline/trend visualization. It's ideal
//! for monitoring dashboards and system status displays.
//!
//! ## Features
//! - Multiple metric types (gauge, counter, rate)
//! - Threshold-based coloring (normal/warning/critical zones)
//! - Optional sparkline visualization for trends
//! - Configurable layout (vertical, horizontal, grid)
//! - Real-time value updates
//! - Optional Block wrapper for borders and title
//!
//! ## Usage
//! ```zig
//! var panel = MetricsPanel.init(allocator);
//! defer panel.deinit();
//!
//! try panel.addMetric(.{
//!     .name = "CPU",
//!     .value = 75.5,
//!     .max_value = 100.0,
//!     .metric_type = .gauge,
//!     .thresholds = .{
//!         .warning = 70.0,
//!         .critical = 90.0,
//!     },
//! });
//!
//! panel.render(buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Metric type classification
pub const MetricType = enum {
    gauge, // Current value (e.g., CPU %, memory usage)
    counter, // Incrementing count (e.g., requests served)
    rate, // Change rate (e.g., requests/sec)
};

/// Threshold configuration for metric coloring
pub const Thresholds = struct {
    warning: f64 = 70.0,
    critical: f64 = 90.0,
};

/// Threshold status based on current value
pub const ThresholdStatus = enum {
    normal,
    warning,
    critical,
};

/// Layout direction for metrics
pub const Layout = enum {
    vertical,
    horizontal,
    grid,
};

/// Single metric configuration and state
pub const Metric = struct {
    name: []const u8,
    value: f64,
    max_value: f64 = 100.0,
    metric_type: MetricType = .gauge,
    thresholds: Thresholds = .{},
    history: ?[]const f64 = null, // For sparkline rendering
};

/// Real-time metrics panel widget
pub const MetricsPanel = struct {
    metrics: std.ArrayList(Metric),
    layout: Layout = .vertical,
    block: ?Block = null,
    show_sparklines: bool = false,
    allocator: std.mem.Allocator,

    /// Create a new metrics panel
    pub fn init(allocator: std.mem.Allocator) MetricsPanel {
        return .{
            .metrics = std.ArrayList(Metric).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *MetricsPanel) void {
        self.metrics.deinit();
    }

    /// Add a metric to the panel
    pub fn addMetric(self: *MetricsPanel, metric: Metric) !void {
        try self.metrics.append(metric);
    }

    /// Update a metric's value by name
    pub fn updateMetric(self: *MetricsPanel, name: []const u8, value: f64) void {
        for (self.metrics.items) |*metric| {
            if (std.mem.eql(u8, metric.name, name)) {
                metric.value = value;
                return;
            }
        }
    }

    /// Set layout direction
    pub fn withLayout(self: MetricsPanel, new_layout: Layout) MetricsPanel {
        var result = self;
        result.layout = new_layout;
        return result;
    }

    /// Set block for borders/title
    pub fn withBlock(self: MetricsPanel, new_block: Block) MetricsPanel {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Enable/disable sparkline visualization
    pub fn withSparklines(self: MetricsPanel, enabled: bool) MetricsPanel {
        var result = self;
        result.show_sparklines = enabled;
        return result;
    }

    /// Evaluate threshold status for a metric
    pub fn evaluateThreshold(metric: Metric) ThresholdStatus {
        const percent = if (metric.max_value > 0)
            (metric.value / metric.max_value) * 100.0
        else
            0.0;

        if (percent >= metric.thresholds.critical) {
            return .critical;
        } else if (percent >= metric.thresholds.warning) {
            return .warning;
        } else {
            return .normal;
        }
    }

    /// Get color for threshold status
    pub fn getColorForStatus(status: ThresholdStatus) Color {
        return switch (status) {
            .normal => .green,
            .warning => .yellow,
            .critical => .red,
        };
    }

    /// Render the metrics panel widget
    pub fn render(self: MetricsPanel, buf: *Buffer, area: Rect) void {
        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        // Nothing to render if area too small or no metrics
        if (inner_area.width == 0 or inner_area.height == 0 or self.metrics.items.len == 0) return;

        switch (self.layout) {
            .vertical => self.renderVertical(buf, inner_area),
            .horizontal => self.renderHorizontal(buf, inner_area),
            .grid => self.renderGrid(buf, inner_area),
        }
    }

    /// Render metrics in vertical layout (stacked)
    fn renderVertical(self: MetricsPanel, buf: *Buffer, area: Rect) void {
        const metrics_per_row: usize = 1;
        var y: u16 = area.y;

        for (self.metrics.items) |metric| {
            if (y >= area.y + area.height) break;

            const metric_area = Rect{
                .x = area.x,
                .y = y,
                .width = area.width,
                .height = @min(3, area.y + area.height - y),
            };

            self.renderMetric(buf, metric_area, metric);
            y += @min(3, metric_area.height);
        }
        _ = metrics_per_row;
    }

    /// Render metrics in horizontal layout (side-by-side)
    fn renderHorizontal(self: MetricsPanel, buf: *Buffer, area: Rect) void {
        if (self.metrics.items.len == 0) return;

        const metric_width = area.width / @as(u16, @intCast(self.metrics.items.len));
        if (metric_width == 0) return;

        for (self.metrics.items, 0..) |metric, i| {
            const x = area.x + @as(u16, @intCast(i)) * metric_width;
            if (x >= area.x + area.width) break;

            const metric_area = Rect{
                .x = x,
                .y = area.y,
                .width = @min(metric_width, area.x + area.width - x),
                .height = area.height,
            };

            self.renderMetric(buf, metric_area, metric);
        }
    }

    /// Render metrics in grid layout
    fn renderGrid(self: MetricsPanel, buf: *Buffer, area: Rect) void {
        if (self.metrics.items.len == 0) return;

        // Calculate grid dimensions (try to make it roughly square)
        const total = self.metrics.items.len;
        const cols: usize = @intFromFloat(@ceil(@sqrt(@as(f64, @floatFromInt(total)))));
        const rows: usize = (total + cols - 1) / cols;

        const cell_width = area.width / @as(u16, @intCast(cols));
        const cell_height = area.height / @as(u16, @intCast(rows));

        if (cell_width == 0 or cell_height == 0) return;

        for (self.metrics.items, 0..) |metric, i| {
            const row = i / cols;
            const col = i % cols;

            const x = area.x + @as(u16, @intCast(col)) * cell_width;
            const y = area.y + @as(u16, @intCast(row)) * cell_height;

            if (y >= area.y + area.height) break;

            const metric_area = Rect{
                .x = x,
                .y = y,
                .width = @min(cell_width, area.x + area.width - x),
                .height = @min(cell_height, area.y + area.height - y),
            };

            self.renderMetric(buf, metric_area, metric);
        }
    }

    /// Render a single metric
    fn renderMetric(self: MetricsPanel, buf: *Buffer, area: Rect, metric: Metric) void {
        if (area.width < 3 or area.height == 0) return;

        const status = evaluateThreshold(metric);
        const color = getColorForStatus(status);
        const style = Style{ .fg = color };

        // Format value based on metric type
        var value_buf: [64]u8 = undefined;
        const value_str = self.formatMetricValue(&value_buf, metric) catch return;

        // Render name on first line
        if (area.height >= 1) {
            var x = area.x;
            for (metric.name) |c| {
                if (x >= area.x + area.width) break;
                buf.setChar(x, area.y, c, .{});
                x += 1;
            }
        }

        // Render value on second line with color
        if (area.height >= 2) {
            var x = area.x;
            for (value_str) |c| {
                if (x >= area.x + area.width) break;
                buf.setChar(x, area.y + 1, c, style);
                x += 1;
            }
        }

        // Render sparkline on third line if enabled and history available
        if (self.show_sparklines and area.height >= 3) {
            if (metric.history) |history| {
                self.renderSparkline(buf, area.y + 2, area.x, area.width, history, style);
            }
        }
    }

    /// Format metric value based on type
    fn formatMetricValue(self: MetricsPanel, buf: []u8, metric: Metric) ![]const u8 {
        _ = self;
        return switch (metric.metric_type) {
            .gauge => std.fmt.bufPrint(buf, "{d:.1}%", .{(metric.value / metric.max_value) * 100.0}),
            .counter => std.fmt.bufPrint(buf, "{d:.0}", .{metric.value}),
            .rate => std.fmt.bufPrint(buf, "{d:.1}/s", .{metric.value}),
        };
    }

    /// Render a sparkline for metric history
    fn renderSparkline(self: MetricsPanel, buf: *Buffer, y: u16, x_start: u16, width: u16, history: []const f64, style: Style) void {
        _ = self;
        if (history.len == 0 or width == 0) return;

        // Find max value for scaling
        var max_val: f64 = history[0];
        for (history) |val| {
            if (val > max_val) max_val = val;
        }

        // Sparkline characters (8 levels)
        const bars = "▁▂▃▄▅▆▇█";
        var bar_chars: [8]u21 = undefined;
        var bar_count: usize = 0;
        var bar_iter = std.unicode.Utf8View.initUnchecked(bars).iterator();
        while (bar_iter.nextCodepoint()) |cp| : (bar_count += 1) {
            bar_chars[bar_count] = cp;
        }

        // Sample history to fit width
        const step: usize = if (history.len > width) (history.len + width - 1) / width else 1;

        var x = x_start;
        var i: usize = 0;
        while (i < history.len and x < x_start + width) : ({
            i += step;
            x += 1;
        }) {
            const val = history[i];
            const bar_idx: usize = if (max_val > 0)
                @min(@as(usize, @intFromFloat(val / max_val * @as(f64, @floatFromInt(bar_count - 1)))), bar_count - 1)
            else
                0;

            buf.setChar(x, y, bar_chars[bar_idx], style);
        }
    }
};

// Tests

test "MetricsPanel.init" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try std.testing.expectEqual(@as(usize, 0), panel.metrics.items.len);
    try std.testing.expectEqual(Layout.vertical, panel.layout);
    try std.testing.expectEqual(false, panel.show_sparklines);
}

test "MetricsPanel.addMetric basic" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "CPU",
        .value = 50.0,
        .max_value = 100.0,
        .metric_type = .gauge,
    });

    try std.testing.expectEqual(@as(usize, 1), panel.metrics.items.len);
    try std.testing.expectEqualStrings("CPU", panel.metrics.items[0].name);
    try std.testing.expectEqual(50.0, panel.metrics.items[0].value);
}

test "MetricsPanel.addMetric multiple types" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "CPU",
        .value = 75.5,
        .metric_type = .gauge,
    });

    try panel.addMetric(.{
        .name = "Requests",
        .value = 1234,
        .metric_type = .counter,
    });

    try panel.addMetric(.{
        .name = "Req/s",
        .value = 45.2,
        .metric_type = .rate,
    });

    try std.testing.expectEqual(@as(usize, 3), panel.metrics.items.len);
    try std.testing.expectEqual(MetricType.gauge, panel.metrics.items[0].metric_type);
    try std.testing.expectEqual(MetricType.counter, panel.metrics.items[1].metric_type);
    try std.testing.expectEqual(MetricType.rate, panel.metrics.items[2].metric_type);
}

test "MetricsPanel.addMetric with thresholds" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "Memory",
        .value = 80.0,
        .max_value = 100.0,
        .thresholds = .{
            .warning = 60.0,
            .critical = 85.0,
        },
    });

    const metric = panel.metrics.items[0];
    try std.testing.expectEqual(60.0, metric.thresholds.warning);
    try std.testing.expectEqual(85.0, metric.thresholds.critical);
}

test "MetricsPanel.updateMetric existing" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "CPU",
        .value = 50.0,
    });

    panel.updateMetric("CPU", 75.5);

    try std.testing.expectEqual(75.5, panel.metrics.items[0].value);
}

test "MetricsPanel.updateMetric nonexistent" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "CPU",
        .value = 50.0,
    });

    // Should not crash when updating nonexistent metric
    panel.updateMetric("Memory", 100.0);

    // Original metric should be unchanged
    try std.testing.expectEqual(50.0, panel.metrics.items[0].value);
}

test "MetricsPanel.updateMetric multiple updates" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "CPU",
        .value = 50.0,
    });

    panel.updateMetric("CPU", 60.0);
    panel.updateMetric("CPU", 70.0);
    panel.updateMetric("CPU", 80.0);

    try std.testing.expectEqual(80.0, panel.metrics.items[0].value);
}

test "MetricsPanel.withLayout" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    const updated = panel.withLayout(.horizontal);

    try std.testing.expectEqual(Layout.horizontal, updated.layout);
}

test "MetricsPanel.withSparklines" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    const updated = panel.withSparklines(true);

    try std.testing.expectEqual(true, updated.show_sparklines);
}

test "MetricsPanel.evaluateThreshold normal zone" {
    const metric = Metric{
        .name = "Test",
        .value = 50.0,
        .max_value = 100.0,
        .thresholds = .{
            .warning = 70.0,
            .critical = 90.0,
        },
    };

    const status = MetricsPanel.evaluateThreshold(metric);
    try std.testing.expectEqual(ThresholdStatus.normal, status);
}

test "MetricsPanel.evaluateThreshold warning zone" {
    const metric = Metric{
        .name = "Test",
        .value = 75.0,
        .max_value = 100.0,
        .thresholds = .{
            .warning = 70.0,
            .critical = 90.0,
        },
    };

    const status = MetricsPanel.evaluateThreshold(metric);
    try std.testing.expectEqual(ThresholdStatus.warning, status);
}

test "MetricsPanel.evaluateThreshold critical zone" {
    const metric = Metric{
        .name = "Test",
        .value = 95.0,
        .max_value = 100.0,
        .thresholds = .{
            .warning = 70.0,
            .critical = 90.0,
        },
    };

    const status = MetricsPanel.evaluateThreshold(metric);
    try std.testing.expectEqual(ThresholdStatus.critical, status);
}

test "MetricsPanel.evaluateThreshold boundary warning" {
    const metric = Metric{
        .name = "Test",
        .value = 70.0,
        .max_value = 100.0,
        .thresholds = .{
            .warning = 70.0,
            .critical = 90.0,
        },
    };

    const status = MetricsPanel.evaluateThreshold(metric);
    try std.testing.expectEqual(ThresholdStatus.warning, status);
}

test "MetricsPanel.evaluateThreshold boundary critical" {
    const metric = Metric{
        .name = "Test",
        .value = 90.0,
        .max_value = 100.0,
        .thresholds = .{
            .warning = 70.0,
            .critical = 90.0,
        },
    };

    const status = MetricsPanel.evaluateThreshold(metric);
    try std.testing.expectEqual(ThresholdStatus.critical, status);
}

test "MetricsPanel.evaluateThreshold zero max" {
    const metric = Metric{
        .name = "Test",
        .value = 50.0,
        .max_value = 0.0,
        .thresholds = .{
            .warning = 70.0,
            .critical = 90.0,
        },
    };

    const status = MetricsPanel.evaluateThreshold(metric);
    // Division by zero should result in normal status
    try std.testing.expectEqual(ThresholdStatus.normal, status);
}

test "MetricsPanel.getColorForStatus normal" {
    const color = MetricsPanel.getColorForStatus(.normal);
    try std.testing.expectEqual(Color.green, color);
}

test "MetricsPanel.getColorForStatus warning" {
    const color = MetricsPanel.getColorForStatus(.warning);
    try std.testing.expectEqual(Color.yellow, color);
}

test "MetricsPanel.getColorForStatus critical" {
    const color = MetricsPanel.getColorForStatus(.critical);
    try std.testing.expectEqual(Color.red, color);
}

test "MetricsPanel.render empty panel" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    panel.render(buf, area);

    // Should not crash with empty panel
}

test "MetricsPanel.render single metric" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "CPU",
        .value = 50.0,
        .max_value = 100.0,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Should render without crashing
}

test "MetricsPanel.render multiple metrics vertical" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{ .name = "CPU", .value = 50.0 });
    try panel.addMetric(.{ .name = "Memory", .value = 75.0 });
    try panel.addMetric(.{ .name = "Disk", .value = 30.0 });

    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    panel.render(buf, area);

    // Should render all metrics vertically
}

test "MetricsPanel.render multiple metrics horizontal" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{ .name = "CPU", .value = 50.0 });
    try panel.addMetric(.{ .name = "Memory", .value = 75.0 });

    var buf = try Buffer.init(std.testing.allocator, 60, 5);
    defer buf.deinit();

    const updated = panel.withLayout(.horizontal);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };
    updated.render(buf, area);

    // Should render all metrics horizontally
}

test "MetricsPanel.render with block" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{ .name = "CPU", .value = 50.0 });

    const blk = (Block{}).withBorders(.all).withTitle("Metrics");
    const updated = panel.withBlock(blk);

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    updated.render(buf, area);

    // Should render both block and metrics
}

test "MetricsPanel.render zero width area" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{ .name = "CPU", .value = 50.0 });

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    panel.render(buf, area);

    // Should not crash with zero width
}

test "MetricsPanel.render zero height area" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{ .name = "CPU", .value = 50.0 });

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    panel.render(buf, area);

    // Should not crash with zero height
}

test "MetricsPanel.render negative values" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "Delta",
        .value = -25.5,
        .max_value = 100.0,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Should handle negative values without crashing
}

test "MetricsPanel.render value exceeds max" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "Overflow",
        .value = 150.0,
        .max_value = 100.0,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Should handle overflow gracefully (likely show as critical)
    const status = MetricsPanel.evaluateThreshold(panel.metrics.items[0]);
    try std.testing.expectEqual(ThresholdStatus.critical, status);
}

test "MetricsPanel.render with sparklines enabled" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    const history = [_]f64{ 10.0, 20.0, 30.0, 40.0, 50.0 };
    try panel.addMetric(.{
        .name = "CPU",
        .value = 50.0,
        .max_value = 100.0,
        .history = &history,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const updated = panel.withSparklines(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    updated.render(buf, area);

    // Should render metric with sparkline visualization
}

test "MetricsPanel.render grid layout 4 metrics" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{ .name = "CPU", .value = 50.0 });
    try panel.addMetric(.{ .name = "Memory", .value = 75.0 });
    try panel.addMetric(.{ .name = "Disk", .value = 30.0 });
    try panel.addMetric(.{ .name = "Network", .value = 60.0 });

    var buf = try Buffer.init(std.testing.allocator, 60, 20);
    defer buf.deinit();

    const updated = panel.withLayout(.grid);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    updated.render(buf, area);

    // Should render metrics in grid layout (2x2 or similar)
}

test "MetricsPanel.render custom thresholds applied" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "Strict",
        .value = 50.0,
        .max_value = 100.0,
        .thresholds = .{
            .warning = 30.0,
            .critical = 50.0,
        },
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Value of 50% should be critical with these thresholds
    const status = MetricsPanel.evaluateThreshold(panel.metrics.items[0]);
    try std.testing.expectEqual(ThresholdStatus.critical, status);
}

test "MetricsPanel.render counter type large value" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "Requests",
        .value = 123456789.0,
        .metric_type = .counter,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Should render large counter values without crashing
}

test "MetricsPanel.render rate type decimal precision" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    try panel.addMetric(.{
        .name = "Throughput",
        .value = 123.456789,
        .metric_type = .rate,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Should handle decimal precision for rate metrics
}

test "MetricsPanel.render many metrics overflow" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    // Add more metrics than can fit
    for (0..20) |i| {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Metric{d}", .{i});
        try panel.addMetric(.{
            .name = name,
            .value = @as(f64, @floatFromInt(i * 5)),
        });
    }

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Should handle overflow gracefully (truncate or scroll)
}

test "MetricsPanel memory safety" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();

    // Add and update metrics multiple times
    try panel.addMetric(.{ .name = "Test1", .value = 10.0 });
    try panel.addMetric(.{ .name = "Test2", .value = 20.0 });
    try panel.addMetric(.{ .name = "Test3", .value = 30.0 });

    panel.updateMetric("Test1", 100.0);
    panel.updateMetric("Test2", 200.0);
    panel.updateMetric("Test3", 300.0);

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    panel.render(buf, area);

    // Should not leak memory
}
