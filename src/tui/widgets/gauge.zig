//! Gauge widget — progress bar with percentage display.
//!
//! Gauge renders a horizontal progress bar with customizable fill characters,
//! colors, and optional label overlay. It's ideal for showing progress of
//! long-running operations.
//!
//! ## Features
//! - Configurable fill and empty characters
//! - Ratio-based progress (0.0 to 1.0)
//! - Optional label overlay (e.g., "50%")
//! - Customizable filled/empty styles
//! - Optional Block wrapper for borders and title
//!
//! ## Usage
//! ```zig
//! const gauge = Gauge{
//!     .ratio = 0.65, // 65% complete
//!     .label = "65%",
//!     .filled_style = .{ .fg = .{ .basic = .green } },
//!     .empty_style = .{ .fg = .{ .basic = .dark_gray } },
//! };
//! gauge.render(buf, area);
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

/// Progress gauge widget
pub const Gauge = struct {
    /// Progress ratio (0.0 to 1.0)
    ratio: f64 = 0.0,

    /// Label to display (e.g., "50%")
    label: ?[]const u8 = null,

    /// Character to use for filled portion
    filled_char: u21 = '█',

    /// Character to use for empty portion
    empty_char: u21 = ' ',

    /// Style for filled portion
    filled_style: Style = .{ .fg = .green },

    /// Style for empty portion
    empty_style: Style = .{},

    /// Style for label text
    label_style: Style = .{ . bold = true },

    /// Optional block for borders/title
    block: ?Block = null,

    /// Create a new gauge widget
    pub fn init() Gauge {
        return .{};
    }

    /// Set progress ratio (clamped to 0.0-1.0)
    pub fn withRatio(self: Gauge, value: f64) Gauge {
        var result = self;
        result.ratio = std.math.clamp(value, 0.0, 1.0);
        return result;
    }

    /// Set progress from percentage (0-100)
    pub fn withPercent(self: Gauge, value: u8) Gauge {
        var result = self;
        result.ratio = @as(f64, @floatFromInt(@min(value, 100))) / 100.0;
        return result;
    }

    /// Set label text
    pub fn withLabel(self: Gauge, text: []const u8) Gauge {
        var result = self;
        result.label = text;
        return result;
    }

    /// Set filled character
    pub fn withFilledChar(self: Gauge, char: u21) Gauge {
        var result = self;
        result.filled_char = char;
        return result;
    }

    /// Set empty character
    pub fn withEmptyChar(self: Gauge, char: u21) Gauge {
        var result = self;
        result.empty_char = char;
        return result;
    }

    /// Set filled style
    pub fn withFilledStyle(self: Gauge, new_style: Style) Gauge {
        var result = self;
        result.filled_style = new_style;
        return result;
    }

    /// Set empty style
    pub fn withEmptyStyle(self: Gauge, new_style: Style) Gauge {
        var result = self;
        result.empty_style = new_style;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: Gauge, new_style: Style) Gauge {
        var result = self;
        result.label_style = new_style;
        return result;
    }

    /// Set block for borders/title
    pub fn withBlock(self: Gauge, new_block: Block) Gauge {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Render the gauge widget
    pub fn render(self: Gauge, buf: *Buffer, area: Rect) void {
        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        // Nothing to render if area too small
        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Render on first line only
        const y = inner_area.y;
        const x_start = inner_area.x;
        const width = inner_area.width;

        // Calculate filled width
        const filled_width: usize = @intFromFloat(@as(f64, @floatFromInt(width)) * self.ratio);

        // Render filled portion
        for (0..filled_width) |offset| {
            buf.setChar(@intCast(x_start + offset), y, self.filled_char, self.filled_style);
        }

        // Render empty portion
        for (filled_width..width) |offset| {
            buf.setChar(@intCast(x_start + offset), y, self.empty_char, self.empty_style);
        }

        // Render label if present (centered)
        if (self.label) |label| {
            if (label.len <= width) {
                const label_x = x_start + (width - label.len) / 2;

                for (label, 0..) |c, offset| {
                    const x = label_x + offset;
                    // Determine background based on position
                    var label_style = self.label_style;
                    if (x - x_start < filled_width) {
                        // Over filled portion
                        if (label_style.bg == null) {
                            label_style.bg = self.filled_style.bg;
                        }
                    } else {
                        // Over empty portion
                        if (label_style.bg == null) {
                            label_style.bg = self.empty_style.bg;
                        }
                    }
                    buf.setChar(@intCast(x), y, c, label_style);
                }
            }
        }
    }
};

// Tests

test "Gauge.init" {
    const gauge = Gauge.init();

    try std.testing.expectEqual(0.0, gauge.ratio);
    try std.testing.expectEqual(null, gauge.label);
    try std.testing.expectEqual('█', gauge.filled_char);
    try std.testing.expectEqual(' ', gauge.empty_char);
}

test "Gauge.withRatio" {
    const gauge = Gauge.init().withRatio(0.75);

    try std.testing.expectEqual(0.75, gauge.ratio);
}

test "Gauge.withRatio clamps to 0.0-1.0" {
    const gauge1 = Gauge.init().withRatio(-0.5);
    try std.testing.expectEqual(0.0, gauge1.ratio);

    const gauge2 = Gauge.init().withRatio(1.5);
    try std.testing.expectEqual(1.0, gauge2.ratio);
}

test "Gauge.withPercent" {
    const gauge = Gauge.init().withPercent(50);

    try std.testing.expectEqual(0.5, gauge.ratio);
}

test "Gauge.withPercent clamps to 100" {
    const gauge = Gauge.init().withPercent(150);

    try std.testing.expectEqual(1.0, gauge.ratio);
}

test "Gauge.withLabel" {
    const gauge = Gauge.init().withLabel("50%");

    try std.testing.expect(gauge.label != null);
    try std.testing.expectEqualStrings("50%", gauge.label.?);
}

test "Gauge.withFilledChar" {
    const gauge = Gauge.init().withFilledChar('=');

    try std.testing.expectEqual('=', gauge.filled_char);
}

test "Gauge.withEmptyChar" {
    const gauge = Gauge.init().withEmptyChar('-');

    try std.testing.expectEqual('-', gauge.empty_char);
}

test "Gauge.withFilledStyle" {
    const style = Style{ .fg = .blue };
    const gauge = Gauge.init().withFilledStyle(style);

    try std.testing.expectEqual(Color.blue, gauge.filled_style.fg);
}

test "Gauge.withEmptyStyle" {
    const style = Style{ .fg = .red };
    const gauge = Gauge.init().withEmptyStyle(style);

    try std.testing.expectEqual(Color.red, gauge.empty_style.fg);
}

test "Gauge.withLabelStyle" {
    const style = Style{ .fg = .yellow };
    const gauge = Gauge.init().withLabelStyle(style);

    try std.testing.expectEqual(Color.yellow, gauge.label_style.fg);
}

test "Gauge.render basic" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const gauge = Gauge.init().withRatio(0.5);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buf, area);

    // First half should be filled
    for (0..10) |x| {
        try std.testing.expectEqual('█', buf.get(x, 0).char);
    }

    // Second half should be empty
    for (10..20) |x| {
        try std.testing.expectEqual(' ', buf.get(x, 0).char);
    }
}

test "Gauge.render 0% progress" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = Gauge.init().withRatio(0.0);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // All should be empty
    for (0..10) |x| {
        try std.testing.expectEqual(' ', buf.get(x, 0).char);
    }
}

test "Gauge.render 100% progress" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = Gauge.init().withRatio(1.0);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // All should be filled
    for (0..10) |x| {
        try std.testing.expectEqual('█', buf.get(x, 0).char);
    }
}

test "Gauge.render with custom chars" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = Gauge.init()
        .withRatio(0.5)
        .withFilledChar('=')
        .withEmptyChar('-');

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // First half should be '='
    for (0..5) |x| {
        try std.testing.expectEqual('=', buf.get(x, 0).char);
    }

    // Second half should be '-'
    for (5..10) |x| {
        try std.testing.expectEqual('-', buf.get(x, 0).char);
    }
}

test "Gauge.render with label" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const gauge = Gauge.init()
        .withRatio(0.5)
        .withLabel("50%");

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buf, area);

    // Label should be centered (20 - 3) / 2 = 8
    try std.testing.expectEqual('5', buf.get(8, 0).char);
    try std.testing.expectEqual('0', buf.get(9, 0).char);
    try std.testing.expectEqual('%', buf.get(10, 0).char);
}

test "Gauge.render with styles" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const filled_style = Style{ .fg = .blue };
    const empty_style = Style{ .fg = .red };

    const gauge = Gauge.init()
        .withRatio(0.5)
        .withFilledStyle(filled_style)
        .withEmptyStyle(empty_style);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    gauge.render(&buf, area);

    // Check filled portion style
    try std.testing.expectEqual(Color.blue, buf.get(0, 0).style.fg);

    // Check empty portion style
    try std.testing.expectEqual(Color.red, buf.get(5, 0).style.fg);
}

test "Gauge.render with block" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const blk = Block.init().withBorders(.all).withTitle("Progress");
    const gauge = Gauge.init()
        .withRatio(0.5)
        .withBlock(blk);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    gauge.render(&buf, area);

    // Block border should be rendered
    try std.testing.expectEqual('┌', buf.get(0, 0).char);

    // Gauge should be inside block (at y=1, x=1)
    // Inner width is 18 (20 - 2 for borders)
    // 50% of 18 = 9
    try std.testing.expectEqual('█', buf.get(1, 1).char);
}

test "Gauge.render zero width" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const gauge = Gauge.init().withRatio(0.5);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    gauge.render(&buf, area);

    // Should not crash
}

test "Gauge.render label too long" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const gauge = Gauge.init()
        .withRatio(0.5)
        .withLabel("Very Long Label");

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    gauge.render(&buf, area);

    // Should not render label (too long)
    // Just check it doesn't crash and gauge is rendered
    for (0..2) |x| {
        try std.testing.expectEqual('█', buf.get(x, 0).char);
    }
}

test "Gauge.render fractional progress" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 7, 1);
    defer buf.deinit();

    const gauge = Gauge.init().withRatio(0.42); // 42% of 7 = 2.94, should be 2

    const area = Rect{ .x = 0, .y = 0, .width = 7, .height = 1 };
    gauge.render(&buf, area);

    // First 2 should be filled
    try std.testing.expectEqual('█', buf.get(0, 0).char);
    try std.testing.expectEqual('█', buf.get(1, 0).char);

    // Rest should be empty
    for (2..7) |x| {
        try std.testing.expectEqual(' ', buf.get(x, 0).char);
    }
}
