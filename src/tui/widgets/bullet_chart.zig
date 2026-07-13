//! BulletChart Widget — KPI value-vs-target-vs-qualitative-range horizontal bars
//!
//! The BulletChart widget displays multiple KPI metrics as horizontal bars,
//! showing actual value, target reference, and qualitative ranges (poor/satisfactory/good).
//! Each bullet gets a horizontal row with optional label and value text.
//!
//! ## Features
//! - Up to 32 bullets (MAX_BULLETS)
//! - Qualitative range bands (background shading light to dark)
//! - Value bar fill (actual performance)
//! - Target tick mark (reference line)
//! - Optional labels and formatted value text
//! - Focused bullet highlighting
//! - Block border support
//! - No heap allocations
//! - Robust out-of-range handling (no panics)
//!
//! ## Usage
//! ```zig
//! var ranges1 = [_]f32{ 0.5, 0.8, 1.0 };
//! const bullets = [_]Bullet{
//!     .{ .label = "Revenue", .value = 85.0, .target = 100.0, .ranges = &ranges1 },
//!     .{ .label = "Profit", .value = 92.0, .target = 90.0, .ranges = &ranges1 },
//! };
//!
//! const chart = BulletChart.init()
//!     .withBullets(&bullets)
//!     .withMaxValue(100.0)
//!     .withShowLabels(true)
//!     .withShowValues(true);
//!
//! chart.render(&buf, area);
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

/// Single bullet KPI metric
pub const Bullet = struct {
    /// Label for the metric (e.g., "Revenue")
    label: []const u8 = "",
    /// Current value
    value: f32 = 0.0,
    /// Target/goal value
    target: f32 = 0.0,
    /// Qualitative range boundaries (ascending, e.g., [0.5, 0.8, 1.0])
    ranges: []const f32 = &.{},
    /// Optional custom style for this bullet
    style: Style = .{},
};

pub const BulletChart = struct {
    /// Maximum number of bullets (capped at 32 for rendering)
    pub const MAX_BULLETS: usize = 32;

    /// Array of bullets to display
    bullets: []const Bullet = &.{},
    /// Index of the focused bullet for highlighting
    focused: usize = 0,
    /// Maximum value for scaling (denominator for normalization)
    max_value: f32 = 1.0,
    /// Whether to render bullet labels
    show_labels: bool = true,
    /// Whether to render value/target text
    show_values: bool = false,
    /// Base style applied to all bullets
    style: Style = .{},
    /// Style for qualitative range bands
    range_style: Style = .{},
    /// Style for value bar
    bar_style: Style = .{},
    /// Style for target tick mark
    target_style: Style = .{},
    /// Style for focused bullet
    focused_style: Style = .{},
    /// Style for bullet labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a BulletChart with all defaults
    pub fn init() BulletChart {
        return .{};
    }

    /// Count of bullets to render (capped at MAX_BULLETS)
    pub fn bulletCount(self: BulletChart) usize {
        return @min(self.bullets.len, MAX_BULLETS);
    }

    /// Set bullets array
    pub fn withBullets(self: BulletChart, b: []const Bullet) BulletChart {
        var result = self;
        result.bullets = b;
        return result;
    }

    /// Set focused bullet index
    pub fn withFocused(self: BulletChart, idx: usize) BulletChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set max_value for scaling
    pub fn withMaxValue(self: BulletChart, v: f32) BulletChart {
        var result = self;
        result.max_value = v;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: BulletChart, show: bool) BulletChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: BulletChart, show: bool) BulletChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: BulletChart, s: Style) BulletChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set range_style
    pub fn withRangeStyle(self: BulletChart, s: Style) BulletChart {
        var result = self;
        result.range_style = s;
        return result;
    }

    /// Set bar_style
    pub fn withBarStyle(self: BulletChart, s: Style) BulletChart {
        var result = self;
        result.bar_style = s;
        return result;
    }

    /// Set target_style
    pub fn withTargetStyle(self: BulletChart, s: Style) BulletChart {
        var result = self;
        result.target_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: BulletChart, s: Style) BulletChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: BulletChart, s: Style) BulletChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: BulletChart, b: ?Block) BulletChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the bullet chart to the buffer
    pub fn render(self: BulletChart, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        const n = self.bulletCount();
        if (n == 0) return;

        // Need minimum area to render
        if (inner.width == 0 or inner.height == 0) return;

        // ========== Step 1: Determine label column width ==========
        var label_width: usize = 0;
        if (self.show_labels) {
            label_width = 10; // default minimum
            for (0..n) |i| {
                const bullet = self.bullets[i];
                if (bullet.label.len > label_width) {
                    label_width = bullet.label.len;
                }
            }
            label_width = @min(label_width, inner.width);
        }

        // ========== Step 2: Render each bullet as a horizontal bar ==========
        for (0..n) |i| {
            const bullet_y = inner.y + @as(u16, @intCast(i));

            // Stop rendering if we've exceeded the inner height
            if (bullet_y >= inner.y + inner.height) break;

            const bullet = self.bullets[i];

            // Determine if this bullet is focused
            const is_focused = (i == self.focused);

            // Check if focused_style is explicitly set
            const focused_style_is_set = self.focused_style.bold or self.focused_style.dim or
                self.focused_style.italic or self.focused_style.underline or self.focused_style.blink or
                self.focused_style.reverse or self.focused_style.strikethrough or
                self.focused_style.fg != null or self.focused_style.bg != null;

            // Compute bar area (after label column)
            const bar_x = inner.x + @as(u16, @intCast(label_width));
            const bar_width = if (inner.x + inner.width > bar_x)
                inner.x + inner.width - bar_x
            else
                0;

            // Render label if enabled
            if (self.show_labels and label_width > 0) {
                const label_style = if (is_focused and focused_style_is_set) self.focused_style else self.label_style;
                renderLabel(buf, inner.x, bullet_y, label_width, bullet.label, label_style);
            }

            // Skip bar rendering if no width left
            if (bar_width == 0) continue;

            // Clamp max_value to a safe denominator
            const safe_max_value = if (self.max_value > 0.0) self.max_value else 1.0;

            // Normalize and clamp value, target, and ranges to [0, 1]
            const normalized_value = std.math.clamp(bullet.value / safe_max_value, 0.0, 1.0);
            const normalized_target = std.math.clamp(bullet.target / safe_max_value, 0.0, 1.0);

            // ========== Render range bands (qualitative background) ==========
            if (bullet.ranges.len > 0) {
                // Band characters cycle through light to dark: '░' -> '▒' -> '▓' -> '░'...
                const band_chars = [_]u21{ '░', '▒', '▓' };

                for (0..bullet.ranges.len) |r| {
                    const range_boundary = bullet.ranges[r];
                    const normalized_boundary = std.math.clamp(range_boundary / safe_max_value, 0.0, 1.0);
                    const boundary_col = @as(usize, @intFromFloat(normalized_boundary * @as(f32, @floatFromInt(bar_width))));

                    if (boundary_col == 0) continue; // Skip zero-width bands

                    const band_char = band_chars[r % band_chars.len];
                    var start_col: usize = 0;
                    if (r > 0) {
                        const prev_boundary = bullet.ranges[r - 1];
                        const normalized_prev = std.math.clamp(prev_boundary / safe_max_value, 0.0, 1.0);
                        start_col = @as(usize, @intFromFloat(normalized_prev * @as(f32, @floatFromInt(bar_width))));
                    }
                    const end_col = boundary_col;

                    for (start_col..end_col) |col| {
                        if (bar_x + @as(u16, @intCast(col)) < inner.x + inner.width) {
                            buf.set(bar_x + @as(u16, @intCast(col)), bullet_y, Cell.init(band_char, self.range_style));
                        }
                    }
                }
            }

            // ========== Render value bar ==========
            const value_col = @as(usize, @intFromFloat(normalized_value * @as(f32, @floatFromInt(bar_width))));
            for (0..value_col) |col| {
                if (bar_x + @as(u16, @intCast(col)) < inner.x + inner.width) {
                    buf.set(bar_x + @as(u16, @intCast(col)), bullet_y, Cell.init('█', self.bar_style));
                }
            }

            // ========== Render target tick ==========
            const target_col = @as(usize, @intFromFloat(normalized_target * @as(f32, @floatFromInt(bar_width))));
            if (target_col < bar_width and bar_x + @as(u16, @intCast(target_col)) < inner.x + inner.width) {
                buf.set(bar_x + @as(u16, @intCast(target_col)), bullet_y, Cell.init('│', self.target_style));
            }

            // ========== Render value text if enabled ==========
            if (self.show_values) {
                const value_text = formatValue(bullet.value, bullet.target);
                const text_x = bar_x + @as(u16, @intCast(bar_width)) + 1;
                if (text_x < inner.x + inner.width) {
                    renderValueText(buf, text_x, bullet_y, inner.x + inner.width, value_text, self.label_style);
                }
            }
        }
    }
};

/// Render a label in the label column (left-aligned, truncated)
fn renderLabel(buf: *Buffer, x: u16, y: u16, width: usize, label: []const u8, style: Style) void {
    var pos = x;
    for (0..@min(label.len, width)) |i| {
        if (pos >= x + @as(u16, @intCast(width))) break;
        const char = label[i];
        buf.set(pos, y, Cell.init(char, style));
        pos += 1;
    }

    // Pad with spaces if label is shorter
    while (pos < x + @as(u16, @intCast(width))) : (pos += 1) {
        buf.set(pos, y, Cell.init(' ', style));
    }
}

/// Format value/target as "VALUE/TARGET" text
fn formatValue(value: f32, target: f32) [32]u8 {
    var buffer: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buffer, "{d:.1}/{d:.1}", .{ value, target }) catch "N/A";
    var output: [32]u8 = undefined;
    @memcpy(output[0..result.len], result);
    // Zero-pad the rest
    for (result.len..32) |i| {
        output[i] = 0;
    }
    return output;
}

/// Render formatted value text in the value area
fn renderValueText(buf: *Buffer, start_x: u16, y: u16, max_x: u16, value_buf: [32]u8, style: Style) void {
    var pos = start_x;

    // Find the actual end of the string (first null byte)
    var len: usize = 0;
    while (len < 32 and value_buf[len] != 0) : (len += 1) {}

    for (0..len) |i| {
        if (pos >= max_x) break;
        buf.set(pos, y, Cell.init(value_buf[i], style));
        pos += 1;
    }
}

// ============================================================================
// In-file library tests (minimal — main test suite in tests/bullet_chart_test.zig)
// ============================================================================

test "BulletChart.init creates default chart with zero bullets" {
    const chart = BulletChart.init();
    try std.testing.expectEqual(@as(usize, 0), chart.bullets.len);
}

test "BulletChart.init defaults max_value to 1.0" {
    const chart = BulletChart.init();
    try std.testing.expect(@abs(chart.max_value - 1.0) < 0.001);
}

test "BulletChart.init defaults show_labels to true" {
    const chart = BulletChart.init();
    try std.testing.expectEqual(true, chart.show_labels);
}

test "BulletChart.bulletCount caps at MAX_BULLETS" {
    var bullets: [50]Bullet = undefined;
    for (0..50) |i| {
        bullets[i] = .{
            .label = "B",
            .value = 0.5,
            .target = 1.0,
        };
    }
    const chart = BulletChart.init().withBullets(&bullets);
    try std.testing.expectEqual(@as(usize, 32), chart.bulletCount());
}

test "BulletChart.withBullets maintains immutability" {
    var bullets1 = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0 }};
    var bullets2 = [_]Bullet{
        .{ .label = "X", .value = 0.3, .target = 1.0 },
        .{ .label = "Y", .value = 0.7, .target = 1.0 },
    };

    const chart1 = BulletChart.init().withBullets(&bullets1);
    const chart2 = chart1.withBullets(&bullets2);

    try std.testing.expectEqual(@as(usize, 1), chart1.bulletCount());
    try std.testing.expectEqual(@as(usize, 2), chart2.bulletCount());
}

test "BulletChart.render with zero area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0 }};
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render with empty bullets renders nothing" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const chart = BulletChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    chart.render(&buf, area);

    // Should produce no visible content
    var non_empty: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    non_empty += 1;
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), non_empty);
}

test "BulletChart.render with single bullet produces content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "Revenue", .value = 0.75, .target = 1.0 }};
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);

    // Should produce some content
    var non_empty: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    non_empty += 1;
                }
            }
        }
    }
    try std.testing.expect(non_empty > 0);
}

test "BulletChart.render with out-of-range value does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    // Malformed bullet: value (1,000,000) far exceeds max_value (1.0)
    var bullets = [_]Bullet{
        .{ .label = "Huge", .value = 1_000_000.0, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    // This render should NOT panic/crash
    chart.render(&buf, area);
}

test "BulletChart.render with max_value zero does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Z", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(0.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
    // No crash is success
}
