//! Histogram widget — frequency distribution bars
//!
//! Example usage:
//!
//! ```zig
//! const bins = [_]Histogram.Bin{
//!     .{ .label = "0-10", .count = 5 },
//!     .{ .label = "10-20", .count = 12 },
//!     .{ .label = "20-30", .count = 8 },
//!     .{ .label = "30-40", .count = 3 },
//! };
//!
//! const hist = Histogram.init(&bins)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Distribution"))
//!     .withBarStyle(.{ .fg = .{ .indexed = 2 } })
//!     .withOrientation(.vertical);
//!
//! hist.render(&buffer, area);
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

/// Histogram widget - frequency distribution bars
pub const Histogram = struct {
    pub const Bin = struct {
        label: []const u8,
        count: u64,
        style: ?Style = null, // Optional per-bin style
    };

    pub const Orientation = enum {
        vertical, // Bars grow upward
        horizontal, // Bars grow rightward
    };

    bins: []const Bin,
    block: ?Block = null,
    bar_style: Style = .{ .fg = .{ .indexed = 2 } }, // Default green
    label_style: Style = .{},
    orientation: Orientation = .vertical,
    bar_char: u21 = '█',
    show_values: bool = true,
    max_bar_height: ?u16 = null, // For vertical orientation
    max_bar_width: ?u16 = null, // For horizontal orientation

    /// Create a histogram with bins
    pub fn init(bins: []const Bin) Histogram {
        return .{ .bins = bins };
    }

    /// Set the block (border) for this histogram
    pub fn withBlock(self: Histogram, new_block: Block) Histogram {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set bar style
    pub fn withBarStyle(self: Histogram, new_style: Style) Histogram {
        var result = self;
        result.bar_style = new_style;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: Histogram, new_style: Style) Histogram {
        var result = self;
        result.label_style = new_style;
        return result;
    }

    /// Set orientation
    pub fn withOrientation(self: Histogram, orientation: Orientation) Histogram {
        var result = self;
        result.orientation = orientation;
        return result;
    }

    /// Set bar character
    pub fn withBarChar(self: Histogram, char: u21) Histogram {
        var result = self;
        result.bar_char = char;
        return result;
    }

    /// Show or hide count values
    pub fn withShowValues(self: Histogram, show: bool) Histogram {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set maximum bar height (for vertical orientation)
    pub fn withMaxBarHeight(self: Histogram, height: u16) Histogram {
        var result = self;
        result.max_bar_height = height;
        return result;
    }

    /// Set maximum bar width (for horizontal orientation)
    pub fn withMaxBarWidth(self: Histogram, width: u16) Histogram {
        var result = self;
        result.max_bar_width = width;
        return result;
    }

    /// Find maximum count across all bins
    fn maxCount(bins: []const Bin) u64 {
        var max: u64 = 0;
        for (bins) |bin| {
            if (bin.count > max) max = bin.count;
        }
        return max;
    }

    /// Render the histogram
    pub fn render(self: Histogram, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.width == 0 or render_area.height == 0) return;
        if (self.bins.len == 0) return;

        switch (self.orientation) {
            .vertical => self.renderVertical(buf, render_area),
            .horizontal => self.renderHorizontal(buf, render_area),
        }
    }

    fn renderVertical(self: Histogram, buf: *Buffer, area: Rect) void {
        const max = maxCount(self.bins);
        if (max == 0) return;

        // Reserve space for labels and values
        const label_height: u16 = 1;
        const value_height: u16 = if (self.show_values) 1 else 0;
        const bar_area_height = if (area.height > label_height + value_height)
            area.height - label_height - value_height
        else 0;

        if (bar_area_height == 0) return;

        const max_height = self.max_bar_height orelse bar_area_height;
        const effective_max_height = @min(max_height, bar_area_height);

        // Calculate bar width
        const bin_count: u16 = @intCast(@min(self.bins.len, area.width));
        const bar_width = if (bin_count > 0) area.width / bin_count else 0;
        if (bar_width == 0) return;

        for (self.bins, 0..) |bin, i| {
            const idx: u16 = @intCast(i);
            if (idx >= bin_count) break;

            const x_start = area.x + idx * bar_width;
            const bin_style = bin.style orelse self.bar_style;

            // Calculate bar height (clamp to prevent overflow)
            const bar_height: u16 = if (max > 0) blk: {
                const scaled = (bin.count * @as(u64, effective_max_height)) / max;
                break :blk @intCast(@min(scaled, effective_max_height));
            } else 0;

            // Draw bar (from bottom to top)
            const bar_bottom = area.y + area.height - label_height - 1;
            var y: u16 = 0;
            while (y < bar_height) : (y += 1) {
                const bar_y = bar_bottom - y;
                var x: u16 = 0;
                while (x < bar_width and x_start + x < area.x + area.width) : (x += 1) {
                    buf.setChar(x_start + x, bar_y, self.bar_char, bin_style);
                }
            }

            // Draw value on top of bar
            if (self.show_values and bar_height > 0) {
                var value_buf: [32]u8 = undefined;
                const value_str = std.fmt.bufPrint(&value_buf, "{d}", .{bin.count}) catch "";
                const value_y = bar_bottom - bar_height;
                const value_x = x_start + (bar_width / 2) - @as(u16, @intCast(@min(value_str.len / 2, bar_width / 2)));
                if (value_x + value_str.len <= area.x + area.width) {
                    buf.setString(value_x, value_y, value_str, self.label_style);
                }
            }

            // Draw label
            const label_y = area.y + area.height - 1;
            const label_x = x_start + (bar_width / 2) - @as(u16, @intCast(@min(bin.label.len / 2, bar_width / 2)));
            const truncated_label = if (bin.label.len > bar_width) bin.label[0..bar_width] else bin.label;
            if (label_x + truncated_label.len <= area.x + area.width) {
                buf.setString(label_x, label_y, truncated_label, self.label_style);
            }
        }
    }

    fn renderHorizontal(self: Histogram, buf: *Buffer, area: Rect) void {
        const max = maxCount(self.bins);
        if (max == 0) return;

        // Calculate max label width
        var max_label_len: u16 = 0;
        for (self.bins) |bin| {
            const len: u16 = @intCast(@min(bin.label.len, 20));
            if (len > max_label_len) max_label_len = len;
        }

        const label_width = max_label_len + 2; // +2 for spacing
        const bar_area_width = if (area.width > label_width) area.width - label_width else 0;
        if (bar_area_width == 0) return;

        const max_width = self.max_bar_width orelse bar_area_width;
        const effective_max_width = @min(max_width, bar_area_width);

        // Calculate space per bin
        const bin_count: u16 = @intCast(@min(self.bins.len, area.height));
        const row_height: u16 = 1;

        for (self.bins, 0..) |bin, i| {
            const idx: u16 = @intCast(i);
            if (idx >= bin_count) break;

            const y = area.y + idx * row_height;
            if (y >= area.y + area.height) break;

            const bin_style = bin.style orelse self.bar_style;

            // Draw label
            const truncated_label = if (bin.label.len > max_label_len) bin.label[0..max_label_len] else bin.label;
            buf.setString(area.x, y, truncated_label, self.label_style);

            // Calculate bar width (clamp to prevent overflow)
            const bar_width: u16 = if (max > 0) blk: {
                const scaled = (bin.count * @as(u64, effective_max_width)) / max;
                break :blk @intCast(@min(scaled, effective_max_width));
            } else 0;

            // Draw bar
            const bar_x_start = area.x + label_width;
            var x: u16 = 0;
            while (x < bar_width and bar_x_start + x < area.x + area.width) : (x += 1) {
                buf.setChar(bar_x_start + x, y, self.bar_char, bin_style);
            }

            // Draw value at end of bar
            if (self.show_values and bar_width > 0) {
                var value_buf: [32]u8 = undefined;
                const value_str = std.fmt.bufPrint(&value_buf, " {d}", .{bin.count}) catch "";
                const value_x = bar_x_start + bar_width;
                if (value_x + value_str.len <= area.x + area.width) {
                    buf.setString(value_x, y, value_str, self.label_style);
                }
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Histogram.init" {
    const bins = [_]Histogram.Bin{
        .{ .label = "A", .count = 5 },
        .{ .label = "B", .count = 10 },
    };
    const hist = Histogram.init(&bins);
    try std.testing.expectEqual(2, hist.bins.len);
    try std.testing.expect(hist.show_values);
    try std.testing.expectEqual(.vertical, hist.orientation);
}

test "Histogram.withBlock" {
    const bins = [_]Histogram.Bin{.{ .label = "A", .count = 1 }};
    const hist = Histogram.init(&bins).withBlock((Block{}));
    try std.testing.expect(hist.block != null);
}

test "Histogram.withBarStyle" {
    const bins = [_]Histogram.Bin{.{ .label = "A", .count = 1 }};
    const style = Style{ .fg = .{ .indexed = 5 } };
    const hist = Histogram.init(&bins).withBarStyle(style);
    try std.testing.expectEqual(5, hist.bar_style.fg.?.indexed);
}

test "Histogram.withOrientation" {
    const bins = [_]Histogram.Bin{.{ .label = "A", .count = 1 }};
    const hist = Histogram.init(&bins).withOrientation(.horizontal);
    try std.testing.expectEqual(.horizontal, hist.orientation);
}

test "Histogram.withBarChar" {
    const bins = [_]Histogram.Bin{.{ .label = "A", .count = 1 }};
    const hist = Histogram.init(&bins).withBarChar('▓');
    try std.testing.expectEqual('▓', hist.bar_char);
}

test "Histogram.withShowValues" {
    const bins = [_]Histogram.Bin{.{ .label = "A", .count = 1 }};
    const hist = Histogram.init(&bins).withShowValues(false);
    try std.testing.expect(!hist.show_values);
}

test "Histogram.maxCount" {
    const bins = [_]Histogram.Bin{
        .{ .label = "A", .count = 5 },
        .{ .label = "B", .count = 12 },
        .{ .label = "C", .count = 7 },
    };
    const max = Histogram.maxCount(&bins);
    try std.testing.expectEqual(12, max);
}

test "Histogram.maxCount empty" {
    const bins = [_]Histogram.Bin{};
    const max = Histogram.maxCount(&bins);
    try std.testing.expectEqual(0, max);
}

test "Histogram.render vertical empty" {
    const bins = [_]Histogram.Bin{};
    const hist = Histogram.init(&bins);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    hist.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // Should not crash
}

test "Histogram.render vertical with data" {
    const bins = [_]Histogram.Bin{
        .{ .label = "A", .count = 5 },
        .{ .label = "B", .count = 10 },
        .{ .label = "C", .count = 7 },
    };
    const hist = Histogram.init(&bins);

    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    hist.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 15 });

    // Verify bars were drawn (check for '█')
    var found = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '█') {
                found = true;
                break;
            }
        }
        if (found) break;
    }
    try std.testing.expect(found);
}

test "Histogram.render horizontal with data" {
    const bins = [_]Histogram.Bin{
        .{ .label = "First", .count = 5 },
        .{ .label = "Second", .count = 10 },
        .{ .label = "Third", .count = 7 },
    };
    const hist = Histogram.init(&bins).withOrientation(.horizontal);

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    hist.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 10 });

    // Verify bars were drawn
    var found = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '█') {
                found = true;
                break;
            }
        }
        if (found) break;
    }
    try std.testing.expect(found);

    // Verify labels
    const first_label = buf.get(0, 0);
    try std.testing.expectEqual('F', first_label.char);
}

test "Histogram.render with block" {
    const bins = [_]Histogram.Bin{
        .{ .label = "A", .count = 5 },
    };
    const hist = Histogram.init(&bins)
        .withBlock((Block{}).withBorders(.all).withTitle("Histogram"));

    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    hist.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 15 });

    // Check for title
    const title_cell = buf.get(1, 0);
    try std.testing.expectEqual('H', title_cell.char);
}

test "Histogram.render zero-size area" {
    const bins = [_]Histogram.Bin{.{ .label = "A", .count = 5 }};
    const hist = Histogram.init(&bins);

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    hist.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "Histogram.render custom bar char" {
    const bins = [_]Histogram.Bin{
        .{ .label = "A", .count = 5 },
    };
    const hist = Histogram.init(&bins).withBarChar('▓');

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    hist.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Verify custom bar char
    var found = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '▓') {
                found = true;
                break;
            }
        }
        if (found) break;
    }
    try std.testing.expect(found);
}

test "Histogram.render values disabled" {
    const bins = [_]Histogram.Bin{
        .{ .label = "A", .count = 5 },
    };
    const hist = Histogram.init(&bins).withShowValues(false);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    hist.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // Should render without values (no verification needed, just shouldn't crash)
}
