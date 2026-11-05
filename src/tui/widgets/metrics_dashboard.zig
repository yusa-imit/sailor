//! MetricsDashboard widget — real-time render, memory and event metrics.
//!
//! MetricsDashboard provides a comprehensive view of application performance metrics
//! in a configurable layout. It displays render performance, memory usage, and event
//! processing statistics from three separate metrics collectors.
//!
//! ## Features
//! - Three layout modes: vertical (three stacked sections), horizontal (three columns), grid
//!   (render and memory on the top row, event across the bottom row)
//! - Metrics from render, memory, and event collectors, read on every `render` call and
//!   aggregated over all widget types (memory peak is the sum of the per-type peaks)
//! - Automatic unit formatting (ns/μs/ms for time, B/KB/MB for memory)
//! - Color-coded warnings: P95 yellow and P99 red above 10 ms (render and event sections)
//! - "No data" for a collector with nothing recorded; sections too small to hold a header,
//!   separator and one row (under 20 columns or 2 rows) are skipped
//!
//! ## Not implemented
//! - Graphs: `show_graphs` is stored and reserved for sparklines; it does not change the output.
//! - Refresh pacing: `update_interval_ms` is stored for the caller's redraw loop; `render`
//!   always draws the current numbers and never reads a clock.
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
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
const assert = std.debug.assert;

const render_metrics = @import("../../render_metrics.zig");
const memory_metrics = @import("../../memory_metrics.zig");
const event_metrics = @import("../../event_metrics.zig");

/// Smallest section that can hold a header, a separator and one row.
const section_width_min: u16 = 20;
const section_height_min: u16 = 2;
/// P95/P99 above this latency are drawn in a warning color.
const warn_threshold_ns: u64 = 10_000_000;

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
        vertical, // Stack sections top-to-bottom
        horizontal, // Place sections side-by-side
        grid, // render and memory on top, event across the bottom
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

    /// Store the refresh interval (ms) for the caller's redraw loop; `render` ignores it.
    pub fn setUpdateInterval(self: *MetricsDashboard, interval_ms: u64) void {
        self.update_interval_ms = interval_ms;
    }

    /// Reserved for sparkline graphs, which are not implemented: has no effect on `render`.
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
        const section_height = @divFloor(area.height, 3);
        if (section_height == 0) return;
        assert(section_height * 3 <= area.height);

        const render_area = subRect(area, 0, 0, area.width, section_height);
        const memory_area = subRect(area, 0, section_height, area.width, section_height);
        const event_height = area.height - section_height * 2;
        const event_area = subRect(area, 0, section_height * 2, area.width, event_height);

        try self.renderRenderMetrics(buf, render_area);
        try self.renderMemoryMetrics(buf, memory_area);
        try self.renderEventMetrics(buf, event_area);
    }

    fn renderHorizontal(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        // Split area into three sections horizontally
        const section_width = @divFloor(area.width, 3);
        if (section_width == 0) return;
        assert(section_width * 3 <= area.width);

        const render_area = subRect(area, 0, 0, section_width, area.height);
        const memory_area = subRect(area, section_width, 0, section_width, area.height);
        const event_width = area.width - section_width * 2;
        const event_area = subRect(area, section_width * 2, 0, event_width, area.height);

        try self.renderRenderMetrics(buf, render_area);
        try self.renderMemoryMetrics(buf, memory_area);
        try self.renderEventMetrics(buf, event_area);
    }

    fn renderGrid(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        // render/memory top row, event across the bottom row
        const half_width = @divFloor(area.width, 2);
        const half_height = @divFloor(area.height, 2);
        if (half_width == 0 or half_height == 0) return;
        assert(half_width * 2 <= area.width);

        const render_area = subRect(area, 0, 0, half_width, half_height);
        const memory_width = area.width - half_width;
        const memory_area = subRect(area, half_width, 0, memory_width, half_height);
        const event_height = area.height - half_height;
        const event_area = subRect(area, 0, half_height, area.width, event_height);

        try self.renderRenderMetrics(buf, render_area);
        try self.renderMemoryMetrics(buf, memory_area);
        try self.renderEventMetrics(buf, event_area);
    }

    /// Render statistics over every widget type the collector has seen, or null when nothing was
    /// recorded. Percentiles come from the merged samples, so this allocates `sample_count`
    /// u64 for the duration of the call.
    fn aggregateRender(self: *const MetricsDashboard) !?RenderAggregate {
        var sample_count: usize = 0;
        var type_iterator = self.render_metrics.types.valueIterator();
        while (type_iterator.next()) |type_data| sample_count += type_data.durations.items.len;
        if (sample_count == 0) return null;

        var samples = try std.ArrayList(u64).initCapacity(self.allocator, sample_count);
        defer samples.deinit(self.allocator);

        var aggregate = RenderAggregate{ .widget_count = 0, .avg_ns = 0, .p95_ns = 0, .p99_ns = 0 };
        var sum_ns: u64 = 0;
        type_iterator = self.render_metrics.types.valueIterator();
        while (type_iterator.next()) |type_data| {
            samples.appendSliceAssumeCapacity(type_data.durations.items);
            sum_ns = std.math.add(u64, sum_ns, type_data.sum_ns) catch std.math.maxInt(u64);
            aggregate.widget_count +|= type_data.widget_ids.count();
        }
        assert(samples.items.len == sample_count);

        std.mem.sort(u64, samples.items, {}, std.sort.asc(u64));
        aggregate.avg_ns = sum_ns / sample_count;
        aggregate.p95_ns = percentile(samples.items, 95);
        aggregate.p99_ns = percentile(samples.items, 99);
        return aggregate;
    }

    /// Memory statistics summed over every widget type, or null when nothing was recorded.
    /// `peak_bytes` is the sum of the per-type peaks: an upper bound of the true overall peak.
    fn aggregateMemory(self: *const MetricsDashboard) ?MemoryAggregate {
        var aggregate = MemoryAggregate{
            .peak_bytes = 0,
            .current_bytes = 0,
            .total_allocs = 0,
            .total_frees = 0,
        };
        var type_count: usize = 0;
        var type_iterator = self.memory_metrics.types.valueIterator();
        while (type_iterator.next()) |type_data| {
            type_count += 1;
            aggregate.peak_bytes +|= type_data.peak_bytes;
            aggregate.current_bytes +|= type_data.current_bytes;
            aggregate.total_allocs +|= type_data.total_allocs;
            aggregate.total_frees +|= type_data.total_frees;
        }
        if (type_count == 0) return null;
        return aggregate;
    }

    fn renderRenderMetrics(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        if (!drawSectionHead(buf, area, "Render Metrics", .cyan)) return;
        const stats = (try self.aggregateRender()) orelse return drawNoData(buf, area);

        var row: u16 = section_height_min;
        if (!try self.emit(buf, area, &row, .{}, "Widgets: {d}", .{stats.widget_count})) return;
        if (!try self.emitTime(buf, area, &row, "Avg", stats.avg_ns, null)) return;
        if (!try self.emitTime(buf, area, &row, "P95", stats.p95_ns, .yellow)) return;
        _ = try self.emitTime(buf, area, &row, "P99", stats.p99_ns, .red);
    }

    fn renderMemoryMetrics(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        if (!drawSectionHead(buf, area, "Memory Metrics", .green)) return;
        const stats = self.aggregateMemory() orelse return drawNoData(buf, area);

        var row: u16 = section_height_min;
        if (!try self.emitMemory(buf, area, &row, "Peak", stats.peak_bytes)) return;
        if (!try self.emitMemory(buf, area, &row, "Current", stats.current_bytes)) return;
        if (!try self.emit(buf, area, &row, .{}, "Allocs: {d}", .{stats.total_allocs})) return;
        _ = try self.emit(buf, area, &row, .{}, "Frees: {d}", .{stats.total_frees});
    }

    fn renderEventMetrics(self: *const MetricsDashboard, buf: *Buffer, area: Rect) !void {
        if (!drawSectionHead(buf, area, "Event Metrics", .magenta)) return;
        const stats = self.event_metrics.getTypeStats() orelse return drawNoData(buf, area);

        var row: u16 = section_height_min;
        if (!try self.emit(buf, area, &row, .{}, "Events: {d}", .{stats.count})) return;
        if (!try self.emitTime(buf, area, &row, "P95", stats.p95_ns, .yellow)) return;
        if (!try self.emitTime(buf, area, &row, "P99", stats.p99_ns, .red)) return;
        _ = try self.emit(buf, area, &row, .{}, "Max Queue: {d}", .{stats.queue_depth_max});
    }

    /// Prints one formatted line at `row.*` inside `area`, clipped to the area width, then
    /// advances `row`. Returns false (drawing nothing) when `area` has no row left.
    fn emit(
        self: *const MetricsDashboard,
        buf: *Buffer,
        area: Rect,
        row: *u16,
        style: Style,
        comptime fmt: []const u8,
        args: anytype,
    ) !bool {
        assert(row.* >= section_height_min);
        if (row.* >= area.height) return false;

        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);

        drawClipped(buf, area, row.*, text, style);
        row.* += 1;
        return true;
    }

    /// `emit` for a labelled duration; drawn in `warn` color above `warn_threshold_ns`.
    fn emitTime(
        self: *const MetricsDashboard,
        buf: *Buffer,
        area: Rect,
        row: *u16,
        label: []const u8,
        ns: u64,
        warn: ?Color,
    ) !bool {
        const time_text = try formatTime(self.allocator, ns);
        defer self.allocator.free(time_text);

        var style = Style{};
        if (warn != null and ns > warn_threshold_ns) style.fg = warn;
        return self.emit(buf, area, row, style, "{s}: {s}", .{ label, time_text });
    }

    /// `emit` for a labelled byte count.
    fn emitMemory(
        self: *const MetricsDashboard,
        buf: *Buffer,
        area: Rect,
        row: *u16,
        label: []const u8,
        bytes: usize,
    ) !bool {
        const memory_text = try formatMemory(self.allocator, bytes);
        defer self.allocator.free(memory_text);

        return self.emit(buf, area, row, .{}, "{s}: {s}", .{ label, memory_text });
    }
};

const RenderAggregate = struct {
    widget_count: usize,
    avg_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
};

const MemoryAggregate = struct {
    peak_bytes: usize,
    current_bytes: usize,
    total_allocs: u64,
    total_frees: u64,
};

/// Sub-rectangle of `area` at offset (`dx`, `dy`). Offsets saturate: a section that starts
/// past the u16 grid lies beyond every buffer and draws nothing.
fn subRect(area: Rect, dx: u16, dy: u16, width: u16, height: u16) Rect {
    assert(dx <= area.width);
    assert(dy <= area.height);
    return .{ .x = area.x +| dx, .y = area.y +| dy, .width = width, .height = height };
}

/// Draws the header and separator of a section. Returns false when the section is too small.
fn drawSectionHead(buf: *Buffer, area: Rect, title: []const u8, color: Color) bool {
    if (area.width < section_width_min or area.height < section_height_min) return false;
    assert(title.len <= section_width_min);
    drawClipped(buf, area, 0, title, .{ .fg = color, .bold = true });
    const separator = Rect{ .x = area.x, .y = area.y +| 1, .width = area.width, .height = 1 };
    buf.fill(separator, '─', .{});
    return true;
}

/// Draws "No data" below the header, when the section is tall enough.
fn drawNoData(buf: *Buffer, area: Rect) void {
    if (area.height <= section_height_min) return;
    drawClipped(buf, area, section_height_min, "No data", .{ .fg = .bright_black });
}

/// Draws `text` on row `row` of `area`, cut to the area width in terminal cells.
fn drawClipped(buf: *Buffer, area: Rect, row: u16, text: []const u8, style: Style) void {
    assert(row < area.height);
    const y: u32 = @as(u32, area.y) + row;
    if (y >= buf.height) return;

    const clipped = clipToCells(text, area.width);
    buf.setString(area.x, @intCast(y), clipped, style);
}

/// Longest prefix of `text` that fits `cells_max` terminal cells, cut on a character boundary.
fn clipToCells(text: []const u8, cells_max: u16) []const u8 {
    var cells: u32 = 0;
    var i: usize = 0;
    // Bounded by text.len: every iteration advances `i` by at least one byte.
    while (i < text.len) {
        const byte = text[i];
        var len: usize = std.unicode.utf8ByteSequenceLength(byte) catch 1;
        if (i + len > text.len) len = 1;
        const cp: u21 = if (len == 1)
            byte
        else
            std.unicode.utf8Decode(text[i .. i + len]) catch blk: {
                len = 1;
                break :blk byte;
            };
        cells += UnicodeWidth.charWidth(cp);
        if (cells > cells_max) break;
        i += len;
    }
    assert(i <= text.len);
    return text[0..i];
}

/// Nearest-rank percentile over ascending `sorted`; the same formula as `render_metrics`.
fn percentile(sorted: []const u64, percent: u8) u64 {
    assert(sorted.len > 0);
    assert(percent <= 100);
    const index = (@as(u64, percent) * (sorted.len - 1)) / 100;
    return sorted[@intCast(index)];
}

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

/// Three collectors and a dashboard over them, pinned in place so the pointers stay valid.
const Fixture = struct {
    render_collector: render_metrics.MetricsCollector,
    memory_collector: memory_metrics.MemoryMetricsCollector,
    event_collector: event_metrics.EventMetricsCollector,
    dashboard: MetricsDashboard,

    fn setUp(self: *Fixture, allocator: std.mem.Allocator) !void {
        self.render_collector = render_metrics.MetricsCollector.init(allocator);
        self.memory_collector = memory_metrics.MemoryMetricsCollector.init(allocator);
        self.event_collector = event_metrics.EventMetricsCollector.init(allocator);
        self.dashboard = try MetricsDashboard.init(
            allocator,
            &self.render_collector,
            &self.memory_collector,
            &self.event_collector,
        );
    }

    fn tearDown(self: *Fixture) void {
        self.dashboard.deinit();
        self.event_collector.deinit();
        self.memory_collector.deinit();
        self.render_collector.deinit();
    }

    /// Two 20 ms renders, 1 KiB allocated and 512 B freed, one 100 us event at queue depth 3.
    fn record(self: *Fixture) void {
        self.render_collector.recordRender(1, "button", 20_000_000);
        self.render_collector.recordRender(1, "button", 20_000_000);
        self.memory_collector.recordAlloc(1, "button", 1024);
        self.memory_collector.recordFree(1, "button", 512);
        self.event_collector.recordEvent("key", 100_000, 3);
    }
};

/// Expects `text` (one cell per code point) at (`x`, `y`) of `buf`.
fn expectText(buf: *const Buffer, x: u16, y: u16, text: []const u8) !void {
    var col = x;
    var it = (try std.unicode.Utf8View.init(text)).iterator();
    while (it.nextCodepoint()) |cp| : (col += 1) {
        const cell = buf.getConst(col, y) orelse return error.OutOfBounds;
        try std.testing.expectEqual(cp, cell.char);
    }
}

/// Expects every cell of `buf` to be an untouched default cell.
fn expectBlank(buf: *const Buffer) !void {
    for (buf.cells) |cell| {
        try std.testing.expectEqual(@as(u21, ' '), cell.char);
        try std.testing.expect(cell.style.fg == null);
    }
}

test "MetricsDashboard - init and deinit" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();

    try std.testing.expectEqual(MetricsDashboard.LayoutMode.vertical, fx.dashboard.layout_mode);
    try std.testing.expectEqual(16, fx.dashboard.update_interval_ms);
    try std.testing.expect(fx.dashboard.show_graphs);
}

test "MetricsDashboard - setLayoutMode" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();

    fx.dashboard.setLayoutMode(.horizontal);
    try std.testing.expectEqual(MetricsDashboard.LayoutMode.horizontal, fx.dashboard.layout_mode);

    fx.dashboard.setLayoutMode(.grid);
    try std.testing.expectEqual(MetricsDashboard.LayoutMode.grid, fx.dashboard.layout_mode);
}

test "MetricsDashboard - setUpdateInterval and setShowGraphs" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();

    fx.dashboard.setUpdateInterval(100);
    try std.testing.expectEqual(100, fx.dashboard.update_interval_ms);

    fx.dashboard.setShowGraphs(false);
    try std.testing.expect(!fx.dashboard.show_graphs);
    fx.dashboard.setShowGraphs(true);
    try std.testing.expect(fx.dashboard.show_graphs);
}

test "MetricsDashboard - render empty area draws nothing" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 0 });
    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 24 });
    try expectBlank(&buf);
}

test "MetricsDashboard - vertical layout without data" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
    try expectText(&buf, 0, 0, "Render Metrics");
    try expectText(&buf, 0, 2, "No data");
    try expectText(&buf, 0, 8, "Memory Metrics");
    try expectText(&buf, 0, 10, "No data");
    try expectText(&buf, 0, 16, "Event Metrics");
    try expectText(&buf, 0, 18, "No data");
    try std.testing.expectEqual(@as(u21, '─'), buf.getConst(79, 1).?.char);
    try std.testing.expectEqual(Color.cyan, buf.getConst(0, 0).?.style.fg.?);
    try std.testing.expect(buf.getConst(0, 0).?.style.bold);
}

test "MetricsDashboard - vertical layout with data" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
    try expectText(&buf, 0, 2, "Widgets: 1");
    try expectText(&buf, 0, 3, "Avg: 20.00ms");
    try expectText(&buf, 0, 4, "P95: 20.00ms");
    try expectText(&buf, 0, 5, "P99: 20.00ms");
    try expectText(&buf, 0, 10, "Peak: 1.00KB");
    try expectText(&buf, 0, 11, "Current: 512B");
    try expectText(&buf, 0, 12, "Allocs: 1");
    try expectText(&buf, 0, 13, "Frees: 1");
    try expectText(&buf, 0, 18, "Events: 1");
    try expectText(&buf, 0, 19, "P95: 100.00μs");
    try expectText(&buf, 0, 20, "P99: 100.00μs");
    try expectText(&buf, 0, 21, "Max Queue: 3");
    // P95 above 10 ms is yellow, P99 red; the fast event latency is not colored.
    try std.testing.expectEqual(Color.yellow, buf.getConst(0, 4).?.style.fg.?);
    try std.testing.expectEqual(Color.red, buf.getConst(0, 5).?.style.fg.?);
    try std.testing.expect(buf.getConst(0, 19).?.style.fg == null);
    try std.testing.expect(buf.getConst(0, 3).?.style.fg == null);
}

test "MetricsDashboard - horizontal layout puts sections in thirds" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();

    var buf = try Buffer.init(std.testing.allocator, 90, 10);
    defer buf.deinit();

    fx.dashboard.setLayoutMode(.horizontal);
    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 90, .height = 10 });
    try expectText(&buf, 0, 0, "Render Metrics");
    try expectText(&buf, 30, 0, "Memory Metrics");
    try expectText(&buf, 60, 0, "Event Metrics");
    try expectText(&buf, 30, 2, "Peak: 1.00KB");
    try expectText(&buf, 60, 5, "Max Queue: 3");
}

test "MetricsDashboard - grid layout puts event section across the bottom" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();
    fx.dashboard.setLayoutMode(.grid);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
    try expectText(&buf, 0, 0, "Render Metrics");
    try expectText(&buf, 40, 0, "Memory Metrics");
    try expectText(&buf, 0, 12, "Event Metrics");
    try expectText(&buf, 0, 14, "Events: 1");
    try std.testing.expectEqual(@as(u21, '─'), buf.getConst(79, 13).?.char);
}

test "MetricsDashboard - section below minimum size is skipped" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    // 10 rows split in thirds leave 3 rows per section: header, separator, one data row.
    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    try expectText(&buf, 0, 0, "Render Metrics");
    try expectText(&buf, 0, 2, "Widgets: 1");
    try expectText(&buf, 0, 3, "Memory Metrics");
    try expectText(&buf, 0, 5, "Peak: 1.00KB");
    // The memory section has no row left for "Current".
    try expectText(&buf, 0, 6, "Event Metrics");

    // 19 columns is below the 20 column minimum: nothing is drawn.
    var narrow = try Buffer.init(std.testing.allocator, 19, 10);
    defer narrow.deinit();

    try fx.dashboard.render(&narrow, Rect{ .x = 0, .y = 0, .width = 19, .height = 10 });
    try expectBlank(&narrow);
}

test "MetricsDashboard - 20x2 area splits into sections below the minimum" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();
    fx.dashboard.setLayoutMode(.grid);

    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    // Grid halves a 20x2 area to 10x1 sections: all below the minimum, so nothing is drawn.
    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 2 });
    try expectBlank(&buf);

    fx.dashboard.setLayoutMode(.horizontal);
    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 2 });
    try expectBlank(&buf);
}

test "MetricsDashboard - 1x1 buffer draws nothing" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();

    var buf = try Buffer.init(std.testing.allocator, 1, 1);
    defer buf.deinit();

    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 1, .height = 1 });
    try expectBlank(&buf);
}

test "MetricsDashboard - far offset area does not overflow u16" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const modes = [_]MetricsDashboard.LayoutMode{ .vertical, .horizontal, .grid };
    for (modes) |mode| {
        fx.dashboard.setLayoutMode(mode);
        const far = Rect{ .x = 60_000, .y = 60_000, .width = 30_000, .height = 30_000 };
        try fx.dashboard.render(&buf, far);
        const max = std.math.maxInt(u16);
        try fx.dashboard.render(&buf, Rect{ .x = max, .y = max, .width = max, .height = max });
    }
    try expectBlank(&buf);
}

test "MetricsDashboard - maximal area fills the buffer without overflow" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const max = std.math.maxInt(u16);
    const modes = [_]MetricsDashboard.LayoutMode{ .vertical, .horizontal, .grid };
    for (modes) |mode| {
        fx.dashboard.setLayoutMode(mode);
        try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = max, .height = max });
        try expectText(&buf, 0, 0, "Render Metrics");
    }
}

test "MetricsDashboard - lines are clipped to their section" {
    var fx: Fixture = undefined;
    try fx.setUp(std.testing.allocator);
    defer fx.tearDown();
    fx.record();
    fx.dashboard.setLayoutMode(.horizontal);

    // 28-character "Allocs: 18446744073709551615" must stop at the 20 column section edge.
    fx.memory_collector.types.getPtr("button").?.total_allocs = std.math.maxInt(u64);

    var buf = try Buffer.init(std.testing.allocator, 60, 10);
    defer buf.deinit();

    // The event section is only 20 wide too; clear its data so it cannot overwrite row 4.
    fx.event_collector.reset();
    try fx.dashboard.render(&buf, Rect{ .x = 0, .y = 0, .width = 60, .height = 10 });
    try expectText(&buf, 20, 4, "Allocs: 184467440737");
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(40, 4).?.char);
}

test "MetricsDashboard - multibyte text is clipped on a character boundary" {
    try std.testing.expectEqualStrings("P95: 1.5", clipToCells("P95: 1.5μs", 8));
    try std.testing.expectEqualStrings("P95: 1.5μ", clipToCells("P95: 1.5μs", 9));
    try std.testing.expectEqualStrings("P95: 1.5μs", clipToCells("P95: 1.5μs", 10));
    try std.testing.expectEqualStrings("世", clipToCells("世界", 3));
    try std.testing.expectEqualStrings("", clipToCells("世界", 1));
    try std.testing.expectEqualStrings("", clipToCells("abc", 0));
}

test "formatTime - nanoseconds" {
    const str = try formatTime(std.testing.allocator, 999);
    defer std.testing.allocator.free(str);

    try std.testing.expectEqualStrings("999ns", str);
}

test "formatTime - microseconds and milliseconds" {
    const us = try formatTime(std.testing.allocator, 1500);
    defer std.testing.allocator.free(us);

    try std.testing.expectEqualStrings("1.50μs", us);

    const ms = try formatTime(std.testing.allocator, 2_500_000);
    defer std.testing.allocator.free(ms);

    try std.testing.expectEqualStrings("2.50ms", ms);
}

test "formatTime - boundary values" {
    const us = try formatTime(std.testing.allocator, 1000);
    defer std.testing.allocator.free(us);

    try std.testing.expectEqualStrings("1.00μs", us);

    const ms = try formatTime(std.testing.allocator, 1_000_000);
    defer std.testing.allocator.free(ms);

    try std.testing.expectEqualStrings("1.00ms", ms);

    const top = try formatTime(std.testing.allocator, std.math.maxInt(u64));
    defer std.testing.allocator.free(top);

    try std.testing.expect(std.mem.endsWith(u8, top, "ms"));
}

test "formatMemory - bytes, kilobytes, megabytes" {
    const bytes = try formatMemory(std.testing.allocator, 999);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings("999B", bytes);

    const kb = try formatMemory(std.testing.allocator, 2048);
    defer std.testing.allocator.free(kb);

    try std.testing.expectEqualStrings("2.00KB", kb);

    const mb = try formatMemory(std.testing.allocator, 3 * 1024 * 1024);
    defer std.testing.allocator.free(mb);

    try std.testing.expectEqualStrings("3.00MB", mb);
}

test "formatMemory - boundary values" {
    const kb = try formatMemory(std.testing.allocator, 1024);
    defer std.testing.allocator.free(kb);

    try std.testing.expectEqualStrings("1.00KB", kb);

    const mb = try formatMemory(std.testing.allocator, 1024 * 1024);
    defer std.testing.allocator.free(mb);

    try std.testing.expectEqualStrings("1.00MB", mb);

    const top = try formatMemory(std.testing.allocator, std.math.maxInt(usize));
    defer std.testing.allocator.free(top);

    try std.testing.expect(std.mem.endsWith(u8, top, "MB"));
}
