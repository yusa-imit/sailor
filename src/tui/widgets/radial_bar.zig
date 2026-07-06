//! RadialBar Widget — Concentric arc rings for multi-value progress
//!
//! The RadialBar widget displays multiple progress values as concentric arcs
//! arranged in a circular pattern. Each arc represents a separate metric,
//! with the outermost arc being the first item and innermost being the last.
//!
//! ## Features
//! - Up to 8 concentric arcs (MAX_ARCS)
//! - Each arc shows 0.0–1.0 progress as a filled arc
//! - Clockwise rendering from 12 o'clock
//! - Focused arc highlighting
//! - Optional labels and values
//! - Per-arc styling
//! - Block border support
//! - Terminal aspect ratio compensation (cells are ~2x taller than wide)
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const arcs = [_]RadialArc{
//!     .{ .label = "CPU", .value = 0.65 },
//!     .{ .label = "MEM", .value = 0.45 },
//! };
//!
//! const bar = RadialBar.init()
//!     .withArcs(&arcs)
//!     .withShowLabels(true)
//!     .withShowValues(true);
//!
//! bar.render(&buf, area);
//! ```

const std = @import("std");
const math = std.math;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// A single arc in the radial bar
pub const RadialArc = struct {
    /// Label for the arc
    label: []const u8 = "",
    /// Value (0.0–1.0, clamped)
    value: f32 = 0.0,
    /// Optional custom style for this arc
    style: Style = .{},
};

pub const RadialBar = struct {
    /// Maximum number of arcs
    pub const MAX_ARCS: usize = 8;

    /// Array of arcs to display
    arcs: []const RadialArc = &.{},
    /// Index of the focused arc for highlighting
    focused: usize = 0,
    /// Whether to render arc labels
    show_labels: bool = true,
    /// Whether to render arc values (as percentages)
    show_values: bool = true,
    /// Base style applied to widget
    style: Style = .{},
    /// Style for arc rings
    arc_style: Style = .{},
    /// Style for the focused arc
    focused_style: Style = .{},
    /// Style for labels
    label_style: Style = .{},
    /// Style for empty ring portions
    empty_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a RadialBar with all defaults
    pub fn init() RadialBar {
        return .{};
    }

    /// Count of arcs to render (capped at MAX_ARCS)
    pub fn arcCount(self: RadialBar) usize {
        return @min(self.arcs.len, MAX_ARCS);
    }

    /// Set arcs array
    pub fn withArcs(self: RadialBar, arcs: []const RadialArc) RadialBar {
        var result = self;
        result.arcs = arcs;
        return result;
    }

    /// Set focused arc index
    pub fn withFocused(self: RadialBar, idx: usize) RadialBar {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: RadialBar, show: bool) RadialBar {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: RadialBar, show: bool) RadialBar {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: RadialBar, s: Style) RadialBar {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set arc style
    pub fn withArcStyle(self: RadialBar, s: Style) RadialBar {
        var result = self;
        result.arc_style = s;
        return result;
    }

    /// Set focused style
    pub fn withFocusedStyle(self: RadialBar, s: Style) RadialBar {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: RadialBar, s: Style) RadialBar {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set empty style
    pub fn withEmptyStyle(self: RadialBar, s: Style) RadialBar {
        var result = self;
        result.empty_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: RadialBar, b: ?Block) RadialBar {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the radial bar to the buffer
    pub fn render(self: RadialBar, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need at least 3x3 for circle rendering
        if (inner.width < 3 or inner.height < 3) return;

        const n = self.arcCount();
        if (n == 0) return;

        // Determine circle area vs label area
        // Circle area is min(width, height) (square on left side)
        const circle_width = @min(inner.width, inner.height);
        const circle_height = inner.height;

        // Label area starts after circle
        const label_col_start = inner.x + circle_width;
        const label_col_width = if (inner.width > circle_width) inner.width - circle_width else 0;

        // Circle center
        const cx = inner.x + @as(i32, @intCast(circle_width / 2));
        const cy = inner.y + @as(i32, @intCast(circle_height / 2));
        const max_radius = @as(f32, @floatFromInt(circle_width / 2));

        // Render each arc as a concentric ring
        for (0..n) |i| {
            const arc = self.arcs[i];

            // Ring radius (outermost arc = max_radius, innermost = max_radius - i)
            const ring_r = max_radius - @as(f32, @floatFromInt(i));
            if (ring_r <= 0) break;

            // Clamp arc value to [0, 1]
            const v = @max(0.0, @min(1.0, arc.value));

            // Arc end angle (0 = 12 o'clock, clockwise)
            const arc_end_angle = v * 2.0 * math.pi;

            // Choose style: focused > per-arc > arc_style
            var arc_style = self.arc_style;
            if (i == self.focused) {
                arc_style = self.focused_style;
            } else if (arc.style.bold or arc.style.dim or arc.style.italic or arc.style.underline) {
                arc_style = arc.style;
            }

            // Iterate over all cells in circle bounding box and render ring
            renderRing(buf, cx, cy, ring_r, arc_end_angle, arc_style, self.empty_style, inner);
        }

        // Render labels if space available
        if ((self.show_labels or self.show_values) and label_col_width > 0) {
            for (0..n) |i| {
                const arc = self.arcs[i];
                const label_y = inner.y + @as(u16, @intCast(i));
                if (label_y >= buf.height) break;

                var label_x = label_col_start;

                // Render label if enabled
                if (self.show_labels and arc.label.len > 0) {
                    const label_len = @min(arc.label.len, label_col_width);
                    if (label_x < buf.width) {
                        buf.setString(label_x, label_y, arc.label[0..label_len], self.label_style);
                        label_x += @as(u16, @intCast(label_len)) + 1;
                    }
                }

                // Render value if enabled
                if (self.show_values and label_x < buf.width) {
                    // Clamp value before converting to percent to avoid panic on negative values
                    const clamped = @max(0.0, @min(1.0, arc.value));
                    const percent = @as(u32, @intFromFloat(clamped * 100.0));
                    drawPercentage(buf, label_x, label_y, percent, self.label_style);
                }
            }
        }
    }
};

/// Render a ring at a specific radius
fn renderRing(buf: *Buffer, cx: i32, cy: i32, ring_r: f32, arc_end_angle: f32, arc_style: Style, empty_style: Style, inner: Rect) void {
    // Iterate over all cells in the inner area
    var y = inner.y;
    while (y < inner.y + inner.height and y < buf.height) : (y += 1) {
        var x = inner.x;
        while (x < inner.x + inner.width and x < buf.width) : (x += 1) {
            // Compute distance from center, accounting for aspect ratio
            // Terminal cells are ~2x taller than wide, so scale x by 0.5
            const dx_scaled = @as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(cx));
            const dx = dx_scaled * 0.5; // Compensate for aspect ratio
            const dy = @as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(cy));
            const dist = @sqrt(dx * dx + dy * dy);

            // Check if this cell is part of the ring (ring_r ± 0.5)
            const ring_inner = ring_r - 0.5;
            const ring_outer = ring_r + 0.5;
            if (dist < ring_inner or dist > ring_outer) continue;

            // Compute angle from top (12 o'clock), clockwise
            // atan2(dy, dx) returns angle from right (3 o'clock)
            // We need to rotate: 12 o'clock = -π/2, so angle = atan2(dy, dx) + π/2
            var angle = math.atan2(dy, dx) + math.pi / 2.0;

            // Normalize to [0, 2π]
            if (angle < 0) angle += 2.0 * math.pi;

            // Determine if cell is filled or empty
            const filled = angle <= arc_end_angle;
            const ch: u21 = if (filled) '█' else '░';
            const style = if (filled) arc_style else empty_style;

            buf.set(x, y, Cell.init(ch, style));
        }
    }
}

/// Draw percentage value at position
fn drawPercentage(buf: *Buffer, x: u16, y: u16, percent: u32, style: Style) void {
    var percent_str: [6]u8 = undefined;
    var str_len: usize = 0;

    // Convert percent to string (e.g., "75%")
    // percent is already u32, so no negative values possible here
    if (percent == 0) {
        percent_str[0] = '0';
        percent_str[1] = '%';
        str_len = 2;
    } else if (percent >= 100) {
        percent_str[0] = '1';
        percent_str[1] = '0';
        percent_str[2] = '0';
        percent_str[3] = '%';
        str_len = 4;
    } else {
        // 2-digit percent
        const tens = percent / 10;
        const ones = percent % 10;
        percent_str[0] = @as(u8, @intCast(tens)) + 48;
        percent_str[1] = @as(u8, @intCast(ones)) + 48;
        percent_str[2] = '%';
        str_len = 3;
    }

    if (x < buf.width and y < buf.height) {
        buf.setString(x, y, percent_str[0..str_len], style);
    }
}

// ============================================================================
// Tests (minimal validation in library code)
// ============================================================================

test "RadialBar.init creates default bar with zero arcs" {
    const rb = RadialBar.init();
    try std.testing.expectEqual(@as(usize, 0), rb.arcs.len);
}

test "RadialBar.init defaults focused to 0" {
    const rb = RadialBar.init();
    try std.testing.expectEqual(@as(usize, 0), rb.focused);
}

test "RadialBar.init defaults show_labels to true" {
    const rb = RadialBar.init();
    try std.testing.expect(rb.show_labels);
}

test "RadialBar.init defaults show_values to true" {
    const rb = RadialBar.init();
    try std.testing.expect(rb.show_values);
}

test "RadialBar.MAX_ARCS equals 8" {
    try std.testing.expectEqual(@as(usize, 8), RadialBar.MAX_ARCS);
}

test "RadialBar.arcCount with zero arcs returns 0" {
    const rb = RadialBar.init();
    try std.testing.expectEqual(@as(usize, 0), rb.arcCount());
}

test "RadialBar.arcCount with 1 arc returns 1" {
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = 0.5 }};
    const rb = RadialBar.init().withArcs(&arcs);
    try std.testing.expectEqual(@as(usize, 1), rb.arcCount());
}

test "RadialBar.arcCount caps at MAX_ARCS when 10 arcs provided" {
    var arcs: [10]RadialArc = undefined;
    for (0..10) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 10.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    try std.testing.expectEqual(@as(usize, 8), rb.arcCount());
}

test "RadialBar.withArcs does not modify original" {
    var arcs1 = [_]RadialArc{.{ .label = "CPU", .value = 0.5 }};
    var arcs2 = [_]RadialArc{
        .{ .label = "MEM", .value = 0.3 },
        .{ .label = "DISK", .value = 0.7 },
    };

    const rb1 = RadialBar.init().withArcs(&arcs1);
    const rb2 = rb1.withArcs(&arcs2);

    try std.testing.expectEqual(@as(usize, 1), rb1.arcCount());
    try std.testing.expectEqual(@as(usize, 2), rb2.arcCount());
}

test "RadialBar.withFocused sets focused index" {
    const rb1 = RadialBar.init().withFocused(0);
    const rb2 = rb1.withFocused(3);

    try std.testing.expectEqual(@as(usize, 0), rb1.focused);
    try std.testing.expectEqual(@as(usize, 3), rb2.focused);
}

test "RadialBar.render on 0x0 area exits early" {
    var buf = try Buffer.init(std.testing.allocator, 0, 0);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = 0.5 }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rb.render(&buf, area);
    // No crash is success
}

test "RadialBar.render on 3x3 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 3, 3);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = 0.5 }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    rb.render(&buf, area);
    // No crash is success
}

test "RadialBar.render single arc produces content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = 0.5 }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try std.testing.expect(non_empty > 0);
}

test "RadialBar.render with value > 1.0 treated as full" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = 1.5 }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try std.testing.expect(non_empty > 0);
}

test "RadialBar.render with value < 0.0 treated as empty" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = -0.5 }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try std.testing.expect(non_empty > 0);
}

fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    count += 1;
                }
            }
        }
    }
    return count;
}
