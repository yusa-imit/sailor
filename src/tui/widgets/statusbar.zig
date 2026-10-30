//! StatusBar widget — horizontal information bar with left/center/right sections.
//!
//! StatusBar renders a single-line bar (typically at the bottom of the screen)
//! with three alignment zones: left, center, and right. It's commonly used for
//! displaying application state, mode indicators, and help text.
//!
//! ## Features
//! - Three alignment zones (left, center, right)
//! - Span-based styling for individual segments
//! - Automatic layout with proper spacing
//! - Full-width background color
//! - Overflow handling (truncate if total width exceeds available space)
//!
//! ## Usage
//! ```zig
//! const status = StatusBar{
//!     .left = &[_]Span{ Span.styled("NORMAL", .{ .fg = .{ .basic = .green } }) },
//!     .center = &[_]Span{ Span.raw("file.txt") },
//!     .right = &[_]Span{ Span.raw("Ln 10, Col 5") },
//!     .style = .{ .bg = .{ .basic = .black } },
//! };
//! status.render(buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const Span = style_mod.Span;
const Line = style_mod.Line;

/// Status bar widget typically shown at bottom of screen
pub const StatusBar = struct {
    /// Left-aligned items
    left: []const Span = &.{},

    /// Center-aligned items
    center: []const Span = &.{},

    /// Right-aligned items
    right: []const Span = &.{},

    /// Background style for entire bar
    style: Style = .{ .bg = .bright_black },

    /// Create a new status bar
    pub fn init() StatusBar {
        return .{};
    }

    /// Set left items
    pub fn withLeft(self: StatusBar, items: []const Span) StatusBar {
        var result = self;
        result.left = items;
        return result;
    }

    /// Set center items
    pub fn withCenter(self: StatusBar, items: []const Span) StatusBar {
        var result = self;
        result.center = items;
        return result;
    }

    /// Set right items
    pub fn withRight(self: StatusBar, items: []const Span) StatusBar {
        var result = self;
        result.right = items;
        return result;
    }

    /// Set background style
    pub fn withStyle(self: StatusBar, new_style: Style) StatusBar {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Calculate total display width of spans
    fn spansWidth(spans: []const Span) usize {
        var total: usize = 0;
        for (spans) |span| {
            total += span.content.len;
        }
        return total;
    }

    /// Render spans starting at x position
    fn renderSpans(buf: *Buffer, spans: []const Span, x_start: u16, y: u16, max_x: u16, bg_style: Style) u16 {
        var x = x_start;
        for (spans) |span| {
            if (x >= max_x) break;

            const remaining = max_x - x;
            const width: u16 = @intCast(@min(span.content.len, remaining));

            // Merge span style with background
            var merged_style = span.style;
            if (merged_style.bg == null) {
                merged_style.bg = bg_style.bg;
            }

            for (span.content[0..width], 0..) |c, offset| {
                buf.set(x + @as(u16, @intCast(offset)), y, .{ .char = c, .style = merged_style });
            }
            x += width;
        }
        return x;
    }

    /// Render the status bar widget
    pub fn render(self: StatusBar, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render on first line only
        const y = area.y;
        const x_start = area.x;
        const max_x = area.x + area.width;

        // Fill background
        for (0..area.width) |offset| {
            buf.set(@intCast(x_start + offset), y, .{ .char = ' ', .style = self.style });
        }

        // Calculate widths
        const left_width = spansWidth(self.left);
        const center_width = spansWidth(self.center);
        const right_width = spansWidth(self.right);

        // Render left items
        var x = x_start;
        if (left_width > 0) {
            x = renderSpans(buf, self.left, x, y, max_x, self.style);
        }

        // Render right items (from right edge)
        if (right_width > 0 and right_width < area.width) {
            const right_x: u16 = @intCast(x_start + area.width - right_width);
            _ = renderSpans(buf, self.right, right_x, y, max_x, self.style);
        }

        // Render center items (in remaining space)
        if (center_width > 0) {
            const available = area.width -| (left_width + right_width);
            if (center_width <= available) {
                const padding = (available - center_width) / 2;
                const center_x: u16 = @intCast(x_start + left_width + padding);
                _ = renderSpans(buf, self.center, center_x, y, max_x, self.style);
            }
        }
    }
};

// Tests

const bar_bg: Style = .{ .bg = .bright_black };

/// Assert that row `y` of `buf` reads exactly `expected` (ASCII only) over `expected.len` cells.
fn expectRow(buf: Buffer, y: u16, expected: []const u8) !void {
    try std.testing.expect(expected.len <= buf.width);
    for (expected, 0..) |c, x| {
        const cell = buf.getConst(@intCast(x), y).?;
        try std.testing.expectEqual(@as(u21, c), cell.char);
    }
}

/// Assert that every cell of row `y` in columns [x0, x1) carries exactly style `want`.
fn expectRowStyle(buf: Buffer, y: u16, x0: u16, x1: u16, want: Style) !void {
    var x = x0;
    while (x < x1) : (x += 1) {
        const cell = buf.getConst(x, y).?;
        try std.testing.expect(Cell.eql(cell, .{ .char = cell.char, .style = want }));
    }
}

const Cell = buffer_mod.Cell;

test "statusbar: init is empty with a bright-black background" {
    const bar = StatusBar.init();

    try std.testing.expectEqual(@as(usize, 0), bar.left.len);
    try std.testing.expectEqual(@as(usize, 0), bar.center.len);
    try std.testing.expectEqual(@as(usize, 0), bar.right.len);
    try std.testing.expectEqual(@as(?Color, .bright_black), bar.style.bg);
    try std.testing.expectEqual(@as(?Color, null), bar.style.fg);
}

test "statusbar: builders set one section each and leave the others untouched" {
    const l = [_]Span{Span.raw("Left")};
    const c = [_]Span{Span.raw("Center")};
    const r = [_]Span{Span.raw("Right")};
    const custom: Style = .{ .bg = .blue };

    const left_only = StatusBar.init().withLeft(&l);
    try std.testing.expectEqualStrings("Left", left_only.left[0].content);
    try std.testing.expectEqual(@as(usize, 0), left_only.center.len);
    try std.testing.expectEqual(@as(usize, 0), left_only.right.len);

    const center_only = StatusBar.init().withCenter(&c);
    try std.testing.expectEqualStrings("Center", center_only.center[0].content);
    try std.testing.expectEqual(@as(usize, 0), center_only.left.len);

    const right_only = StatusBar.init().withRight(&r);
    try std.testing.expectEqualStrings("Right", right_only.right[0].content);
    try std.testing.expectEqual(@as(usize, 0), right_only.left.len);

    const styled = StatusBar.init().withLeft(&l).withStyle(custom);
    try std.testing.expectEqual(@as(?Color, .blue), styled.style.bg);
    try std.testing.expectEqual(@as(usize, 1), styled.left.len);
}

test "statusbar: spansWidth sums span lengths and is zero for no spans" {
    const spans = [_]Span{ Span.raw("Hello"), Span.raw(" "), Span.raw("World") };
    try std.testing.expectEqual(@as(usize, 11), StatusBar.spansWidth(&spans));

    const none = [_]Span{};
    try std.testing.expectEqual(@as(usize, 0), StatusBar.spansWidth(&none));
}

test "statusbar: empty bar fills the whole width with the background and nothing else" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 12, 2);
    defer buf.deinit();

    StatusBar.init().render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });

    buf.check_invariants();
    try expectRow(buf, 0, " " ** 12);
    try expectRowStyle(buf, 0, 0, 12, bar_bg);
    // Row 1 is outside the bar and keeps the default cell.
    for (0..12) |x| {
        try std.testing.expect(buf.getConst(@intCast(x), 1).?.eql(Cell{}));
    }
}

test "statusbar: left span renders at the left edge over a filled background" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const left = [_]Span{Span.raw("Left")};
    StatusBar.init().withLeft(&left).render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 1 });

    try expectRow(buf, 0, "Left" ++ " " ** 26);
    // The span has no bg of its own, so it inherits the bar background.
    try expectRowStyle(buf, 0, 0, 30, bar_bg);
}

test "statusbar: right span is flush with the right edge" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const left = [_]Span{Span.raw("Left")};
    const right = [_]Span{Span.raw("Right")};
    const bar = StatusBar.init().withLeft(&left).withRight(&right);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 1 });

    try expectRow(buf, 0, "Left" ++ " " ** 21 ++ "Right");
}

test "statusbar: center span sits in the middle of the free space" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const center = [_]Span{Span.raw("Center")};
    const bar = StatusBar.init().withCenter(&center);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 1 });

    // (30 - 6) / 2 = 12 blanks on each side.
    try expectRow(buf, 0, " " ** 12 ++ "Center" ++ " " ** 12);
}

test "statusbar: all three sections land at left, middle of the gap, and right" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const l = [_]Span{Span.raw("L")};
    const c = [_]Span{Span.raw("C")};
    const r = [_]Span{Span.raw("R")};
    const bar = StatusBar.init().withLeft(&l).withCenter(&c).withRight(&r);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 50, .height = 1 });

    // Gap between L and R is columns 1..48 (48 cells); C has (48 - 1) / 2 = 23 blanks before it.
    try expectRow(buf, 0, "L" ++ " " ** 23 ++ "C" ++ " " ** 24 ++ "R");
}

test "statusbar: center is centered within the gap of unequal left and right" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const l = [_]Span{Span.raw("AB")};
    const c = [_]Span{Span.raw("XY")};
    const r = [_]Span{Span.raw("123456")};
    const bar = StatusBar.init().withLeft(&l).withCenter(&c).withRight(&r);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 1 });

    // Gap is columns 2..13 (12 cells); XY starts 5 cells into it.
    try expectRow(buf, 0, "AB" ++ " " ** 5 ++ "XY" ++ " " ** 5 ++ "123456");
}

test "statusbar: span fg is kept and the bar bg fills in" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const red: Style = .{ .fg = .red, .bold = true };
    const left = [_]Span{Span.styled("Error", red)};
    StatusBar.init().withLeft(&left).render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 1 });

    const want: Style = .{ .fg = .red, .bg = .bright_black, .bold = true };
    try expectRow(buf, 0, "Error" ++ " " ** 15);
    try expectRowStyle(buf, 0, 0, 5, want);
    try expectRowStyle(buf, 0, 5, 20, bar_bg);
}

test "statusbar: a span with its own bg overrides the bar bg" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const mode: Style = .{ .fg = .black, .bg = .green };
    const left = [_]Span{Span.styled("NORM", mode)};
    StatusBar.init().withLeft(&left).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try expectRowStyle(buf, 0, 0, 4, mode);
    try expectRowStyle(buf, 0, 4, 10, bar_bg);
}

test "statusbar: bar style with no bg leaves span bg unset" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 8, 1);
    defer buf.deinit();

    const left = [_]Span{Span.styled("ab", .{ .fg = .cyan })};
    const bar = StatusBar.init().withLeft(&left).withStyle(.{});
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 1 });

    try expectRowStyle(buf, 0, 0, 2, .{ .fg = .cyan });
    try expectRowStyle(buf, 0, 2, 8, .{});
}

test "statusbar: multiple spans in one section are laid out back to back with own styles" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const left = [_]Span{
        Span.styled("Part1", .{ .fg = .red }),
        Span.raw(" "),
        Span.styled("Part2", .{ .fg = .green }),
    };
    StatusBar.init().withLeft(&left).render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 1 });

    try expectRow(buf, 0, "Part1 Part2" ++ " " ** 19);
    try expectRowStyle(buf, 0, 0, 5, .{ .fg = .red, .bg = .bright_black });
    try expectRowStyle(buf, 0, 5, 6, bar_bg);
    try expectRowStyle(buf, 0, 6, 11, .{ .fg = .green, .bg = .bright_black });
}

test "statusbar: overlong left text is truncated at the area edge" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 8, 1);
    defer buf.deinit();

    const left = [_]Span{Span.raw("VeryLongText")};
    StatusBar.init().withLeft(&left).render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 1 });

    try expectRow(buf, 0, "VeryL");
    // Cells beyond the area are untouched.
    for (5..8) |x| {
        try std.testing.expect(buf.getConst(@intCast(x), 0).?.eql(Cell{}));
    }
}

test "statusbar: spans after the truncation point are not drawn" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 6, 1);
    defer buf.deinit();

    const left = [_]Span{ Span.raw("abcd"), Span.raw("efgh"), Span.raw("ZZZ") };
    StatusBar.init().withLeft(&left).render(&buf, .{ .x = 0, .y = 0, .width = 6, .height = 1 });

    try expectRow(buf, 0, "abcdef");
}

test "statusbar: right text wins the overlap when left is too long" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const left = [_]Span{Span.raw("VeryLongLeft")};
    const right = [_]Span{Span.raw("Right")};
    const bar = StatusBar.init().withLeft(&left).withRight(&right);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try expectRow(buf, 0, "VeryLRight");
}

test "statusbar: center that does not fit in the gap is dropped" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const left = [_]Span{Span.raw("1234")};
    const center = [_]Span{Span.raw("MIDDLE")};
    const right = [_]Span{Span.raw("5678")};
    const bar = StatusBar.init().withLeft(&left).withCenter(&center).withRight(&right);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    // Gap is 2 cells; MIDDLE needs 6.
    try expectRow(buf, 0, "1234  5678");
}

test "statusbar: render honors the area offset and only touches the first row" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const left = [_]Span{Span.raw("hi")};
    const right = [_]Span{Span.raw("yo")};
    const bar = StatusBar.init().withLeft(&left).withRight(&right);
    bar.render(&buf, .{ .x = 3, .y = 1, .width = 10, .height = 2 });

    // Columns 3..12 of row 1 carry the bar; "yo" is flush with column 12.
    try expectRow(buf, 1, "   hi      yo");
    try expectRowStyle(buf, 1, 3, 13, bar_bg);
    try std.testing.expect(buf.getConst(2, 1).?.eql(Cell{}));
    try std.testing.expect(buf.getConst(13, 1).?.eql(Cell{}));
    // Rows 0 and 2, including the bar's second declared row, are untouched.
    for (0..20) |x| {
        try std.testing.expect(buf.getConst(@intCast(x), 0).?.eql(Cell{}));
        try std.testing.expect(buf.getConst(@intCast(x), 2).?.eql(Cell{}));
    }
}

test "statusbar: zero width or zero height renders nothing" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const left = [_]Span{Span.raw("Left")};
    const bar = StatusBar.init().withLeft(&left);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 1 });
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });

    for (buf.cells) |cell| try std.testing.expect(cell.eql(Cell{}));
}

test "statusbar: area wider than the buffer clips without writing out of bounds" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 4, 1);
    defer buf.deinit();

    const left = [_]Span{Span.raw("ab")};
    const right = [_]Span{Span.raw("yz")};
    const bar = StatusBar.init().withLeft(&left).withRight(&right);
    bar.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    buf.check_invariants();
    // The right span sits at columns 8..9, outside the 4-wide buffer, so only the left shows.
    try expectRow(buf, 0, "ab  ");
}

test "statusbar: area below the buffer renders nothing" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 6, 2);
    defer buf.deinit();

    const left = [_]Span{Span.raw("gone")};
    StatusBar.init().withLeft(&left).render(&buf, .{ .x = 0, .y = 5, .width = 6, .height = 1 });

    for (buf.cells) |cell| try std.testing.expect(cell.eql(Cell{}));
}
