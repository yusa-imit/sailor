//! Rating Widget — discrete star/symbol rating display
//!
//! Rating displays a discrete star-based rating widget, ideal for product reviews
//! and user ratings. It supports half-stars, customizable characters, and styling.
//!
//! ## Features
//! - Discrete rating from 0 to max (1-32)
//! - Half-star support (nearest 0.5 rounding)
//! - Custom characters (full, half, empty)
//! - Optional label prefix and value display
//! - Customizable styles (base, filled, focused)
//! - Block border support
//! - Builder pattern for fluent configuration

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Maximum allowed star count
const MAX_MAX = 32;

/// Rating widget — discrete star display
pub const Rating = struct {
    /// Current rating value (clamped to [0, max])
    value: f32 = 0.0,

    /// Maximum rating value (clamped to [1, 32])
    max: u8 = 5,

    /// Optional label prefix (e.g., "Rating")
    label: ?[]const u8 = null,

    /// Whether to show numeric value display
    show_value: bool = false,

    /// Whether rating is focused
    focused: bool = false,

    /// Character for full stars
    full_char: u21 = '★',

    /// Character for half stars
    half_char: u21 = '⯨',

    /// Character for empty stars
    empty_char: u21 = '☆',

    /// Base style (for empty stars)
    style: Style = .{},

    /// Style for filled stars
    filled_style: Style = .{},

    /// Style for focused state (overrides filled_style when focused=true)
    focused_style: Style = .{},

    /// Optional block border
    block: ?Block = null,

    /// Initialize a new rating with value and max stars
    /// Clamps value to [0, max] and max to [1, 32]
    pub fn init(value: f32, max: u8) Rating {
        // Normalize max: 0 -> 1, > 32 -> 32
        const normalized_max: u8 = if (max == 0) 1 else @min(max, MAX_MAX);

        // Clamp value to [0, normalized_max]
        const clamped_value = clampValue(value, @as(f32, @floatFromInt(normalized_max)));

        return .{
            .value = clamped_value,
            .max = normalized_max,
        };
    }

    /// Set label text (returns new Rating for chaining)
    pub fn withLabel(self: Rating, text: []const u8) Rating {
        var result = self;
        result.label = text;
        return result;
    }

    /// Set show_value flag (returns new Rating for chaining)
    pub fn withShowValue(self: Rating, show: bool) Rating {
        var result = self;
        result.show_value = show;
        return result;
    }

    /// Set focus state (returns new Rating for chaining)
    pub fn withFocus(self: Rating, focused: bool) Rating {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Set custom characters (returns new Rating for chaining)
    pub fn withChars(self: Rating, full: u21, half: u21, empty: u21) Rating {
        var result = self;
        result.full_char = full;
        result.half_char = half;
        result.empty_char = empty;
        return result;
    }

    /// Set base style for empty stars (returns new Rating for chaining)
    pub fn withStyle(self: Rating, new_style: Style) Rating {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Set style for filled stars (returns new Rating for chaining)
    pub fn withFilledStyle(self: Rating, new_style: Style) Rating {
        var result = self;
        result.filled_style = new_style;
        return result;
    }

    /// Set style for focused state (returns new Rating for chaining)
    pub fn withFocusedStyle(self: Rating, new_style: Style) Rating {
        var result = self;
        result.focused_style = new_style;
        return result;
    }

    /// Set block border (returns new Rating for chaining)
    pub fn withBlock(self: Rating, new_block: Block) Rating {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Render the rating widget
    pub fn render(self: Rating, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Handle block border if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
            if (inner_area.width == 0 or inner_area.height == 0) return;
        }

        // Current rendering position
        var x = inner_area.x;
        const y = inner_area.y;
        const max_x = inner_area.x + inner_area.width;

        // Render label if present
        if (self.label) |lbl| {
            // Write label characters
            for (lbl) |ch| {
                if (x >= max_x) break;
                buf.set(x, y, .{ .char = ch, .style = .{} });
                x += 1;
            }
            // Add space after label
            if (x < max_x) {
                buf.set(x, y, .{ .char = ' ', .style = .{} });
                x += 1;
            }
        }

        // Calculate star counts using nearest-0.5 rounding
        const rounded_value = @round(self.value * 2.0) / 2.0;
        const full_count: u8 = @intFromFloat(@floor(rounded_value));
        const has_half = (rounded_value - @as(f32, @floatFromInt(full_count))) > 0.0;
        const half_count: u8 = if (has_half) 1 else 0;
        const empty_count = self.max - full_count - half_count;

        // Render full stars
        for (0..full_count) |_| {
            if (x >= max_x) break;
            const star_style = if (self.focused) self.focused_style else self.filled_style;
            buf.set(x, y, .{ .char = self.full_char, .style = star_style });
            x += 1;
        }

        // Render half star if needed
        if (has_half) {
            if (x < max_x) {
                const star_style = if (self.focused) self.focused_style else self.filled_style;
                buf.set(x, y, .{ .char = self.half_char, .style = star_style });
                x += 1;
            }
        }

        // Render empty stars
        for (0..empty_count) |_| {
            if (x >= max_x) break;
            buf.set(x, y, .{ .char = self.empty_char, .style = self.style });
            x += 1;
        }

        // Render value display if requested
        if (self.show_value) {
            // Add space before value
            if (x < max_x) {
                buf.set(x, y, .{ .char = ' ', .style = .{} });
                x += 1;
            }

            // Format value/max with one decimal place
            var value_buf: [16]u8 = undefined;
            const value_str = std.fmt.bufPrint(&value_buf, "{d:.1}/{d}", .{ self.value, self.max }) catch "";

            // Write value string
            for (value_str) |ch| {
                if (x >= max_x) break;
                buf.set(x, y, .{ .char = ch, .style = .{} });
                x += 1;
            }
        }
    }
};

/// Clamp value to valid range, handling NaN and Infinity
fn clampValue(value: f32, max: f32) f32 {
    // Handle NaN -> 0.0
    if (std.math.isNan(value)) return 0.0;

    // Handle positive infinity -> max
    if (std.math.isPositiveInf(value)) return max;

    // Handle negative infinity -> 0.0
    if (std.math.isNegativeInf(value)) return 0.0;

    // Normal clamping
    return std.math.clamp(value, 0.0, max);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Rating.init sets value and max" {
    const rating = Rating.init(3.5, 5);
    try testing.expectEqual(3.5, rating.value);
    try testing.expectEqual(@as(u8, 5), rating.max);
}

test "Rating.init defaults label to null" {
    const rating = Rating.init(2.0, 5);
    try testing.expect(rating.label == null);
}

test "Rating.init defaults show_value to false" {
    const rating = Rating.init(2.0, 5);
    try testing.expect(!rating.show_value);
}

test "Rating.init defaults focused to false" {
    const rating = Rating.init(2.0, 5);
    try testing.expect(!rating.focused);
}

test "Rating.init defaults full_char to ★" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(u21, '★'), rating.full_char);
}

test "Rating.init defaults half_char to ⯨" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(u21, '⯨'), rating.half_char);
}

test "Rating.init defaults empty_char to ☆" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(u21, '☆'), rating.empty_char);
}

test "Rating.init defaults style to empty Style" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(Style{}, rating.style);
}

test "Rating.init defaults filled_style to empty Style" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(Style{}, rating.filled_style);
}

test "Rating.init defaults focused_style to empty Style" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(Style{}, rating.focused_style);
}

test "Rating.init defaults block to null" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(?Block, null), rating.block);
}
