//! Scrollable viewport widget for content larger than its visible area.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// Scrollable viewport widget for large content
pub const ScrollView = struct {
    /// Content height (total scrollable area)
    content_height: u16,
    /// Current vertical scroll offset
    scroll_y: u16 = 0,
    /// Content width (total scrollable area)
    content_width: u16 = 0,
    /// Current horizontal scroll offset
    scroll_x: u16 = 0,
    /// Optional block for border
    block: ?Block = null,
    /// Show scrollbar
    show_scrollbar: bool = true,
    /// Scrollbar style
    scrollbar_style: Style = .{},

    /// Scroll down by lines
    pub fn scrollDown(self: *ScrollView, lines: u16) void {
        self.scroll_y = @min(self.scroll_y +| lines, self.content_height);
    }

    /// Scroll up by lines
    pub fn scrollUp(self: *ScrollView, lines: u16) void {
        if (lines > self.scroll_y) {
            self.scroll_y = 0;
        } else {
            self.scroll_y -= lines;
        }
    }

    /// Scroll right by columns
    pub fn scrollRight(self: *ScrollView, cols: u16) void {
        self.scroll_x = @min(self.scroll_x +| cols, self.content_width);
    }

    /// Scroll left by columns
    pub fn scrollLeft(self: *ScrollView, cols: u16) void {
        if (cols > self.scroll_x) {
            self.scroll_x = 0;
        } else {
            self.scroll_x -= cols;
        }
    }

    /// Scroll to make position visible
    pub fn scrollTo(self: *ScrollView, y: u16, viewport_height: u16) void {
        if (y < self.scroll_y) {
            // Scroll up to show y
            self.scroll_y = y;
        } else if (y >= self.scroll_y +| viewport_height) {
            // Scroll down to show y
            self.scroll_y = y -| (viewport_height -| 1);
        }
    }

    /// Get visible content area
    pub fn getViewport(self: ScrollView, area: Rect) Rect {
        var inner = area;
        if (self.block) |blk| {
            inner = blk.inner(area);
        }

        // Reserve space for scrollbar if shown
        if (self.show_scrollbar and inner.width > 1) {
            inner.width -= 1;
        }

        return inner;
    }

    /// Get content rectangle (offset by scroll position)
    pub fn getContentRect(_: ScrollView, viewport: Rect) Rect {
        return Rect{
            .x = viewport.x,
            .y = viewport.y,
            .width = viewport.width,
            .height = viewport.height,
        };
    }

    /// Render the scrollview with content callback
    pub fn render(
        self: ScrollView,
        buf: *Buffer,
        area: Rect,
        renderContent: *const fn (*Buffer, Rect, u16, u16) void,
    ) void {
        // Render block border if present
        if (self.block) |blk| {
            blk.render(buf, area);
        }

        // Get viewport area
        const viewport = self.getViewport(area);
        if (viewport.width == 0 or viewport.height == 0) return;

        // Render content with scroll offset
        renderContent(buf, viewport, self.scroll_x, self.scroll_y);

        // Render scrollbar
        if (self.show_scrollbar) {
            self.renderScrollbar(buf, area, viewport);
        }
    }

    fn renderScrollbar(self: ScrollView, buf: *Buffer, area: Rect, viewport: Rect) void {
        const inner = if (self.block) |blk| blk.inner(area) else area;
        if (inner.height < 2 or inner.width < 2) return;

        // The scrollbar occupies the column reserved by getViewport, right of the content.
        const scrollbar_x = viewport.x + viewport.width;
        std.debug.assert(scrollbar_x == inner.x + inner.width - 1);
        const scrollbar_height = inner.height;

        // Thumb size is proportional to the visible fraction, clamped to [1, track height].
        const track: f64 = @floatFromInt(scrollbar_height);
        const visible_ratio = @as(f64, @floatFromInt(viewport.height)) /
            @as(f64, @floatFromInt(@max(1, self.content_height)));
        const thumb_size: u16 = @intFromFloat(@min(track, @max(1.0, track * visible_ratio)));

        // Thumb position follows the scroll offset, clamped to the end of the track.
        const scroll_ratio = if (self.content_height > viewport.height)
            @min(1.0, @as(f64, @floatFromInt(self.scroll_y)) /
                @as(f64, @floatFromInt(self.content_height - viewport.height)))
        else
            0.0;

        const free: f64 = @floatFromInt(scrollbar_height - thumb_size);
        const thumb_y: u16 = @intFromFloat(free * scroll_ratio);

        // Render scrollbar track
        var y: u16 = 0;
        while (y < scrollbar_height) : (y += 1) {
            const char: u21 = if (y >= thumb_y and y < thumb_y + thumb_size) '█' else '░';
            buf.set(scrollbar_x, inner.y + y, .{ .char = char, .style = self.scrollbar_style });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Content callback that records its arguments and marks the corners of the viewport it is given.
const Probe = struct {
    var calls: u32 = 0;
    var rect: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var offset_x: u16 = 0;
    var offset_y: u16 = 0;

    fn reset() void {
        calls = 0;
        rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        offset_x = 0;
        offset_y = 0;
    }

    fn render(buf: *Buffer, r: Rect, sx: u16, sy: u16) void {
        calls += 1;
        rect = r;
        offset_x = sx;
        offset_y = sy;
        buf.set(r.x, r.y, .{ .char = 'C' });
        buf.set(r.x + r.width - 1, r.y + r.height - 1, .{ .char = 'C' });
    }
};

fn noContent(_: *Buffer, _: Rect, _: u16, _: u16) void {}

/// Render column `x` from row `y0` into `out` as '#' (thumb), '.' (track), ' ' (blank),
/// or '?' (anything else).
fn column(buf: Buffer, x: u16, y0: u16, out: []u8) []const u8 {
    for (out, 0..) |*c, i| {
        const ch = buf.getChar(x, y0 + @as(u16, @intCast(i)));
        c.* = switch (ch) {
            '█' => '#',
            '░' => '.',
            ' ' => ' ',
            else => '?',
        };
    }
    return out;
}

fn expectColumn(buf: Buffer, x: u16, y0: u16, want: []const u8) !void {
    var storage: [64]u8 = undefined;
    try testing.expect(want.len <= storage.len);
    try testing.expectEqualStrings(want, column(buf, x, y0, storage[0..want.len]));
}

fn renderPlain(sv: ScrollView, buf: *Buffer, width: u16, height: u16) void {
    sv.render(buf, .{ .x = 0, .y = 0, .width = width, .height = height }, noContent);
}

test "scrollview: a fresh view starts at the origin" {
    const sv = ScrollView{ .content_height = 100, .content_width = 80 };

    try testing.expectEqual(@as(u16, 0), sv.scroll_y);
    try testing.expectEqual(@as(u16, 0), sv.scroll_x);
    try testing.expectEqual(@as(u16, 100), sv.content_height);
    try testing.expectEqual(@as(u16, 80), sv.content_width);
    try testing.expect(sv.show_scrollbar);
    try testing.expect(sv.block == null);
}

test "scrollview: scrollDown accumulates and clamps at content height" {
    var sv = ScrollView{ .content_height = 100 };

    sv.scrollDown(10);
    try testing.expectEqual(@as(u16, 10), sv.scroll_y);
    sv.scrollDown(50);
    try testing.expectEqual(@as(u16, 60), sv.scroll_y);
    sv.scrollDown(100);
    try testing.expectEqual(@as(u16, 100), sv.scroll_y);
    sv.scrollDown(0);
    try testing.expectEqual(@as(u16, 100), sv.scroll_y);
}

test "scrollview: scrollDown and scrollRight saturate instead of overflowing u16" {
    var sv = ScrollView{
        .content_height = std.math.maxInt(u16),
        .content_width = std.math.maxInt(u16),
        .scroll_y = 60000,
        .scroll_x = 60000,
    };

    sv.scrollDown(std.math.maxInt(u16));
    sv.scrollRight(std.math.maxInt(u16));

    try testing.expectEqual(@as(u16, std.math.maxInt(u16)), sv.scroll_y);
    try testing.expectEqual(@as(u16, std.math.maxInt(u16)), sv.scroll_x);
}

test "scrollview: scrollUp subtracts and clamps at zero" {
    var sv = ScrollView{ .content_height = 100, .scroll_y = 50 };

    sv.scrollUp(10);
    try testing.expectEqual(@as(u16, 40), sv.scroll_y);
    sv.scrollUp(40);
    try testing.expectEqual(@as(u16, 0), sv.scroll_y);
    sv.scrollUp(1);
    try testing.expectEqual(@as(u16, 0), sv.scroll_y);
}

test "scrollview: scrollRight accumulates and clamps at content width" {
    var sv = ScrollView{ .content_height = 0, .content_width = 200 };

    sv.scrollRight(20);
    try testing.expectEqual(@as(u16, 20), sv.scroll_x);
    sv.scrollRight(300);
    try testing.expectEqual(@as(u16, 200), sv.scroll_x);
}

test "scrollview: scrollLeft subtracts and clamps at zero" {
    var sv = ScrollView{ .content_height = 0, .content_width = 200, .scroll_x = 100 };

    sv.scrollLeft(30);
    try testing.expectEqual(@as(u16, 70), sv.scroll_x);
    sv.scrollLeft(100);
    try testing.expectEqual(@as(u16, 0), sv.scroll_x);
}

test "scrollview: scroll operations never touch the other axis" {
    var sv = ScrollView{
        .content_height = 100,
        .content_width = 100,
        .scroll_y = 7,
        .scroll_x = 9,
    };

    sv.scrollDown(3);
    sv.scrollUp(1);
    try testing.expectEqual(@as(u16, 9), sv.scroll_x);
    sv.scrollRight(3);
    sv.scrollLeft(1);
    try testing.expectEqual(@as(u16, 9), sv.scroll_y);
}

test "scrollview: scrollTo scrolls up, down, and leaves visible rows alone" {
    var sv = ScrollView{ .content_height = 100 };

    sv.scrollTo(50, 20);
    try testing.expectEqual(@as(u16, 31), sv.scroll_y); // 50 - (20 - 1): row 50 is the last row
    sv.scrollTo(10, 20);
    try testing.expectEqual(@as(u16, 10), sv.scroll_y);
    sv.scrollTo(15, 20);
    try testing.expectEqual(@as(u16, 10), sv.scroll_y);
}

test "scrollview: scrollTo boundary between last visible row and first hidden row" {
    var sv = ScrollView{ .content_height = 100, .scroll_y = 10 };

    sv.scrollTo(29, 20); // last visible row: 10..29
    try testing.expectEqual(@as(u16, 10), sv.scroll_y);
    sv.scrollTo(30, 20); // first hidden row
    try testing.expectEqual(@as(u16, 11), sv.scroll_y);
    sv.scrollTo(10, 20); // first visible row after the move is 11; 10 is hidden above
    try testing.expectEqual(@as(u16, 10), sv.scroll_y);
}

test "scrollview: scrollTo with zero viewport height and near-max offsets does not overflow" {
    var sv = ScrollView{ .content_height = 100, .scroll_y = 65000 };

    sv.scrollTo(65535, 1000); // scroll_y + viewport_height would overflow u16
    try testing.expectEqual(@as(u16, 64536), sv.scroll_y); // 65535 - (1000 - 1)

    sv.scroll_y = 3;
    sv.scrollTo(3, 0); // empty viewport: the row is "hidden" and lands at itself
    try testing.expectEqual(@as(u16, 3), sv.scroll_y);
}

test "scrollview: getViewport reserves one column for the scrollbar" {
    const sv = ScrollView{ .content_height = 100 };
    const viewport = sv.getViewport(.{ .x = 2, .y = 3, .width = 80, .height = 24 });

    try testing.expectEqual(Rect{ .x = 2, .y = 3, .width = 79, .height = 24 }, viewport);
}

test "scrollview: getViewport with block subtracts borders then the scrollbar column" {
    const sv = ScrollView{ .content_height = 100, .block = Block{ .borders = .all } };
    const viewport = sv.getViewport(.{ .x = 0, .y = 0, .width = 80, .height = 24 });

    try testing.expectEqual(Rect{ .x = 1, .y = 1, .width = 77, .height = 22 }, viewport);
}

test "scrollview: getViewport without scrollbar returns the whole area" {
    const sv = ScrollView{ .content_height = 100, .show_scrollbar = false };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    try testing.expectEqual(area, sv.getViewport(area));
}

test "scrollview: getViewport keeps a one-column area intact" {
    const sv = ScrollView{ .content_height = 100 };
    const viewport = sv.getViewport(.{ .x = 0, .y = 0, .width = 1, .height = 5 });

    try testing.expectEqual(@as(u16, 1), viewport.width);
}

test "scrollview: getContentRect mirrors the viewport" {
    const sv = ScrollView{ .content_height = 100, .scroll_y = 20 };
    const viewport = Rect{ .x = 4, .y = 5, .width = 80, .height = 24 };

    try testing.expectEqual(viewport, sv.getContentRect(viewport));
}

test "scrollview: render passes the viewport and scroll offsets to the content callback" {
    Probe.reset();
    var buf = try Buffer.init(testing.allocator, 10, 6);
    defer buf.deinit();

    const sv = ScrollView{ .content_height = 50, .scroll_y = 7, .scroll_x = 3, .content_width = 9 };
    sv.render(&buf, .{ .x = 1, .y = 1, .width = 8, .height = 4 }, Probe.render);

    try testing.expectEqual(@as(u32, 1), Probe.calls);
    try testing.expectEqual(Rect{ .x = 1, .y = 1, .width = 7, .height = 4 }, Probe.rect);
    try testing.expectEqual(@as(u16, 3), Probe.offset_x);
    try testing.expectEqual(@as(u16, 7), Probe.offset_y);
    // Content corners landed where the callback was told to draw.
    try testing.expectEqual(@as(u21, 'C'), buf.getChar(1, 1));
    try testing.expectEqual(@as(u21, 'C'), buf.getChar(7, 4));
}

test "scrollview: scrollbar thumb sits at the top when scrolled to the start" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    // 10 visible of 100 rows: thumb is 1 cell, track is the rightmost column.
    renderPlain(.{ .content_height = 100 }, &buf, 10, 10);

    try expectColumn(buf, 9, 0, "#.........");
    try expectColumn(buf, 8, 0, "          "); // content column untouched
}

test "scrollview: scrollbar thumb sits at the bottom when scrolled to the end" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    renderPlain(.{ .content_height = 100, .scroll_y = 90 }, &buf, 10, 10);

    try expectColumn(buf, 9, 0, ".........#");
}

test "scrollview: scrollbar thumb is mid-track at half scroll" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    renderPlain(.{ .content_height = 100, .scroll_y = 45 }, &buf, 10, 10);

    try expectColumn(buf, 9, 0, "....#.....");
}

test "scrollview: thumb length is proportional to the visible fraction" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    // Half of the content is visible: a 5-cell thumb.
    renderPlain(.{ .content_height = 20 }, &buf, 10, 10);
    try expectColumn(buf, 9, 0, "#####.....");

    renderPlain(.{ .content_height = 20, .scroll_y = 10 }, &buf, 10, 10);
    try expectColumn(buf, 9, 0, ".....#####");
}

test "scrollview: scroll past the end keeps the thumb inside the track" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    // scrollDown clamps to content_height, which exceeds the last valid offset (10).
    var sv = ScrollView{ .content_height = 20 };
    sv.scrollDown(500);
    try testing.expectEqual(@as(u16, 20), sv.scroll_y);
    renderPlain(sv, &buf, 10, 10);

    try expectColumn(buf, 9, 0, ".....#####");
}

test "scrollview: content shorter than the viewport fills the whole track with the thumb" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    renderPlain(.{ .content_height = 4 }, &buf, 10, 10);
    try expectColumn(buf, 9, 0, "##########");

    renderPlain(.{ .content_height = 0 }, &buf, 10, 10);
    try expectColumn(buf, 9, 0, "##########");
}

test "scrollview: scrollbar uses its configured style and content cells keep theirs" {
    var buf = try Buffer.init(testing.allocator, 6, 4);
    defer buf.deinit();

    const style = Style{ .fg = .green, .bold = true };
    renderPlain(.{ .content_height = 40, .scrollbar_style = style }, &buf, 6, 4);

    var y: u16 = 0;
    while (y < 4) : (y += 1) {
        try testing.expectEqual(style, buf.getStyle(5, y));
        try testing.expectEqual(Style{}, buf.getStyle(4, y));
    }
}

test "scrollview: scrollbar stays inside the block and leaves the right border intact" {
    var buf = try Buffer.init(testing.allocator, 12, 6);
    defer buf.deinit();

    const sv = ScrollView{ .content_height = 8, .block = Block{ .borders = .all } };
    renderPlain(sv, &buf, 12, 6);

    // Inner area is x 1..10, y 1..4; the scrollbar is the last inner column (x = 10).
    try expectColumn(buf, 10, 1, "##..");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(11, 1));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(11, 4));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(11, 0));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(11, 5));
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(0, 5));
}

test "scrollview: scrollbar honours a non-zero area origin" {
    var buf = try Buffer.init(testing.allocator, 12, 8);
    defer buf.deinit();

    const sv = ScrollView{ .content_height = 40 };
    sv.render(&buf, .{ .x = 2, .y = 3, .width = 6, .height = 4 }, noContent);

    try expectColumn(buf, 7, 3, "#...");
    try expectColumn(buf, 7, 2, " "); // row above the area is untouched
    try expectColumn(buf, 8, 3, "    "); // column right of the area is untouched
    try expectColumn(buf, 1, 3, "    ");
}

test "scrollview: show_scrollbar=false gives content the full width and draws no track" {
    Probe.reset();
    var buf = try Buffer.init(testing.allocator, 10, 4);
    defer buf.deinit();

    const sv = ScrollView{ .content_height = 100, .show_scrollbar = false };
    sv.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 4 }, Probe.render);

    try testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 10, .height = 4 }, Probe.rect);
    for (buf.cells) |cell| {
        try testing.expect(cell.char != '█' and cell.char != '░');
    }
    try testing.expectEqual(@as(u21, 'C'), buf.getChar(9, 3));
}

test "scrollview: a one-column or one-row area draws content but no scrollbar" {
    Probe.reset();
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const sv = ScrollView{ .content_height = 100 };
    sv.render(&buf, .{ .x = 0, .y = 0, .width = 1, .height = 5 }, Probe.render);
    try testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 1, .height = 5 }, Probe.rect);

    sv.render(&buf, .{ .x = 3, .y = 0, .width = 6, .height = 1 }, noContent);

    for (buf.cells) |cell| {
        try testing.expect(cell.char != '█' and cell.char != '░');
    }
}

test "scrollview: zero-sized area never calls the content callback and writes nothing" {
    Probe.reset();
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const sv = ScrollView{ .content_height = 100 };
    sv.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 }, Probe.render);
    sv.render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 0 }, Probe.render);

    try testing.expectEqual(@as(u32, 0), Probe.calls);
    for (buf.cells) |cell| try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "scrollview: a block that consumes the whole area skips content and scrollbar" {
    Probe.reset();
    var buf = try Buffer.init(testing.allocator, 4, 4);
    defer buf.deinit();

    const sv = ScrollView{ .content_height = 100, .block = Block{ .borders = .all } };
    sv.render(&buf, .{ .x = 0, .y = 0, .width = 2, .height = 2 }, Probe.render);

    try testing.expectEqual(@as(u32, 0), Probe.calls);
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(1, 1));
    for (buf.cells) |cell| {
        try testing.expect(cell.char != '█' and cell.char != '░');
    }
}

test "scrollview: an area wider than the buffer is clipped without writing out of bounds" {
    var buf = try Buffer.init(testing.allocator, 5, 3);
    defer buf.deinit();

    renderPlain(.{ .content_height = 30 }, &buf, 20, 8);

    // The scrollbar column (x = 19) lies outside the buffer, so no track cell exists.
    for (buf.cells) |cell| {
        try testing.expect(cell.char != '█' and cell.char != '░');
    }
    buf.check_invariants();
}
