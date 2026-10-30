//! Tabs widget — horizontal navigation bar with selectable tabs.
//!
//! Tabs renders a horizontal list of clickable tab titles with highlighting
//! for the active tab. It's commonly used for multi-panel interfaces and
//! navigation between different views.
//!
//! ## Features
//! - Configurable tab titles
//! - Active tab highlighting
//! - Customizable divider character
//! - Optional Block wrapper for borders
//! - Horizontal overflow handling (truncate with "...")
//!
//! ## Usage
//! ```zig
//! const tabs = Tabs{
//!     .titles = &[_][]const u8{ "Home", "Settings", "About" },
//!     .selected = 0, // "Home" is active
//!     .selected_style = .{ .fg = .{ .basic = .cyan }, .bold = true },
//!     .divider = " | ",
//! };
//! tabs.render(buf, area);
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
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

/// Tabs widget for navigation between sections
pub const Tabs = struct {
    /// Tab titles
    titles: []const []const u8,

    /// Currently selected tab index
    selected: usize = 0,

    /// Style for selected tab
    selected_style: Style = .{ .fg = .cyan, .bold = true },

    /// Style for normal tabs
    normal_style: Style = .{},

    /// Style for divider between tabs
    divider: []const u8 = " │ ",

    /// Optional block for borders/title
    block: ?Block = null,

    /// Create a new tabs widget
    pub fn init(titles: []const []const u8) Tabs {
        return .{ .titles = titles };
    }

    /// Set selected tab index
    pub fn withSelected(self: Tabs, index: usize) Tabs {
        var result = self;
        result.selected = @min(index, if (self.titles.len > 0) self.titles.len - 1 else 0);
        return result;
    }

    /// Set selected tab style
    pub fn withSelectedStyle(self: Tabs, new_style: Style) Tabs {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set normal tab style
    pub fn withNormalStyle(self: Tabs, new_style: Style) Tabs {
        var result = self;
        result.normal_style = new_style;
        return result;
    }

    /// Set divider string
    pub fn withDivider(self: Tabs, new_divider: []const u8) Tabs {
        var result = self;
        result.divider = new_divider;
        return result;
    }

    /// Set block for borders/title
    pub fn withBlock(self: Tabs, new_block: Block) Tabs {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Render the tabs widget
    pub fn render(self: Tabs, buf: *Buffer, area: Rect) void {
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
        var x = inner_area.x;
        const max_x = inner_area.x + inner_area.width;

        for (self.titles, 0..) |title, i| {
            // Check if we have space for this tab
            if (x >= max_x) break;

            // Determine style
            const tab_style = if (i == self.selected) self.selected_style else self.normal_style;

            // Render tab title (widths are in terminal cells, not bytes)
            const title_bytes = UnicodeWidth.truncate(title, max_x - x);
            buf.setString(x, y, title[0..title_bytes], tab_style);
            x += @as(u16, @intCast(UnicodeWidth.stringWidth(title[0..title_bytes])));

            // Render divider if not last tab and we have space
            if (i < self.titles.len - 1 and x < max_x) {
                const divider_bytes = UnicodeWidth.truncate(self.divider, max_x - x);
                buf.setString(x, y, self.divider[0..divider_bytes], self.normal_style);
                x += @as(u16, @intCast(UnicodeWidth.stringWidth(self.divider[0..divider_bytes])));
            }
        }
    }
};

// Tests

const testing = std.testing;

/// Assert that `text` is drawn at (x, y) one codepoint per cell, every cell carrying `want`.
fn expectText(buf: Buffer, x: u16, y: u16, text: []const u8, want: Style) !void {
    var view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    var col = x;
    while (it.nextCodepoint()) |cp| : (col += 1) {
        const cell = buf.getConst(col, y) orelse return error.TestUnexpectedResult;
        try testing.expectEqual(cp, cell.char);
        try testing.expectEqual(want, cell.style);
    }
}

/// Assert every cell in the buffer is still the default blank cell.
fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| {
        try testing.expectEqual(@as(u21, ' '), cell.char);
        try testing.expectEqual(Style{}, cell.style);
    }
}

test "tabs: init uses documented defaults" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles);

    try testing.expectEqual(@as(usize, 3), tabs.titles.len);
    try testing.expectEqual(@as(usize, 0), tabs.selected);
    try testing.expectEqualStrings(" │ ", tabs.divider);
    try testing.expectEqual(Style{ .fg = .cyan, .bold = true }, tabs.selected_style);
    try testing.expectEqual(Style{}, tabs.normal_style);
    try testing.expect(tabs.block == null);
}

test "tabs: withSelected stores an in-range index" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles).withSelected(1);

    try testing.expectEqual(@as(usize, 1), tabs.selected);
}

test "tabs: withSelected clamps an out-of-range index to the last tab" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles).withSelected(10);

    try testing.expectEqual(@as(usize, 2), tabs.selected);
}

test "tabs: withSelected on empty titles yields index zero" {
    const titles = [_][]const u8{};
    const tabs = Tabs.init(&titles).withSelected(5);

    try testing.expectEqual(@as(usize, 0), tabs.selected);
}

test "tabs: with-builders replace only their own field" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const base = Tabs.init(&titles);
    const sel = Style{ .fg = .red };
    const nor = Style{ .fg = .green };
    const tabs = base.withDivider(" | ").withSelectedStyle(sel).withNormalStyle(nor);

    try testing.expectEqualStrings(" | ", tabs.divider);
    try testing.expectEqual(@as(?Color, .red), tabs.selected_style.fg);
    try testing.expectEqual(@as(?Color, .green), tabs.normal_style.fg);
    try testing.expectEqual(base.selected, tabs.selected);
    try testing.expectEqual(base.titles.len, tabs.titles.len);
}

test "tabs: render lays out titles and default divider by cell width" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "Home", "Edit", "View" };
    const tabs = Tabs.init(&titles).withSelected(1);
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 3 });
    buf.check_invariants();

    const sel = tabs.selected_style;
    try expectText(buf, 0, 0, "Home", .{});
    try expectText(buf, 4, 0, " │ ", .{});
    try expectText(buf, 7, 0, "Edit", sel);
    try expectText(buf, 11, 0, " │ ", .{});
    try expectText(buf, 14, 0, "View", .{});
    // Nothing past the last tab, and nothing below the first row.
    try expectText(buf, 18, 0, "            ", .{});
    try expectText(buf, 0, 1, " " ** 30, .{});
    try expectText(buf, 0, 2, " " ** 30, .{});
}

test "tabs: render with custom divider places next title right after it" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B", "C" };
    const tabs = Tabs.init(&titles).withDivider(" / ");
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 1 });

    try expectText(buf, 0, 0, "A", tabs.selected_style);
    try expectText(buf, 1, 0, " / ", .{});
    try expectText(buf, 4, 0, "B", .{});
    try expectText(buf, 5, 0, " / ", .{});
    try expectText(buf, 8, 0, "C", .{});
    try expectText(buf, 9, 0, " " ** 11, .{});
}

test "tabs: render applies selected style to the selected title only" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const sel = Style{ .fg = .red, .bold = true };
    const nor = Style{ .fg = .white };
    const tabs = Tabs.init(&titles).withSelected(1).withSelectedStyle(sel).withNormalStyle(nor);
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 1 });

    try expectText(buf, 0, 0, "Tab1", nor);
    // The divider takes the normal style, not the style of a neighbouring tab.
    try expectText(buf, 4, 0, " │ ", nor);
    try expectText(buf, 7, 0, "Tab2", sel);
    // Unwritten cells keep the default style.
    try testing.expectEqual(Style{}, buf.getStyle(11, 0));
}

test "tabs: selected index past the last title styles no tab as selected" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    var tabs = Tabs.init(&titles);
    tabs.selected = 7;
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 1 });

    try expectText(buf, 0, 0, "Tab1 │ Tab2", .{});
}

test "tabs: render truncates a title that exceeds the area and draws no further tab" {
    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "VeryLongTab1", "VeryLongTab2", "Tab3" };
    const tabs = Tabs.init(&titles);
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try expectText(buf, 0, 0, "VeryLongTa", tabs.selected_style);
    // Cells beyond the area stay blank even though the buffer is wider.
    try expectText(buf, 10, 0, "  ", .{});
}

test "tabs: render clips the divider at the area edge" {
    var buf = try Buffer.init(testing.allocator, 8, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "AB", "CD" };
    const tabs = Tabs.init(&titles).withDivider(" | ");
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 1 });

    try expectText(buf, 0, 0, "AB", tabs.selected_style);
    try expectText(buf, 2, 0, " |", .{});
    // The second title does not fit and must not be drawn.
    try expectText(buf, 4, 0, "    ", .{});
}

test "tabs: render honours area offset and wide characters" {
    var buf = try Buffer.init(testing.allocator, 30, 4);
    defer buf.deinit();

    const titles = [_][]const u8{ "你好", "Go" };
    const tabs = Tabs.init(&titles);
    tabs.render(&buf, .{ .x = 3, .y = 2, .width = 20, .height = 1 });

    // Wide glyph occupies two cells, so the divider starts at x = 3 + 4.
    try testing.expectEqual(@as(u21, '你'), buf.getChar(3, 2));
    try testing.expectEqual(tabs.selected_style, buf.getStyle(3, 2));
    try testing.expectEqual(@as(u21, '好'), buf.getChar(5, 2));
    try expectText(buf, 7, 2, " │ ", .{});
    try expectText(buf, 10, 2, "Go", .{});
    // Rows and columns outside the area are untouched.
    try expectText(buf, 0, 2, "   ", .{});
    try expectText(buf, 0, 0, " " ** 30, .{});
    try expectText(buf, 0, 3, " " ** 30, .{});
}

test "tabs: render inside a block draws border, title, and tabs in the inner row" {
    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const blk = (Block{}).withBorders(.all).withTitle("Nav", .top_left);
    const tabs = Tabs.init(&titles).withBlock(blk);
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 5 });

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(19, 0));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(0, 4));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(19, 4));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(0, 1));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(19, 1));
    try expectText(buf, 2, 0, "Nav", .{});
    try expectText(buf, 1, 1, "Tab1", tabs.selected_style);
    try expectText(buf, 5, 1, " │ ", .{});
    try expectText(buf, 8, 1, "Tab2", .{});
    // Only the first inner row carries tabs.
    try expectText(buf, 1, 2, " " ** 18, .{});
}

test "tabs: block leaving no inner room draws no tab text" {
    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();

    const titles = [_][]const u8{"Tab1"};
    const tabs = Tabs.init(&titles).withBlock(Block{});
    // Height 2 with top and bottom borders leaves zero inner rows.
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 2 });

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(0, 1));
    for (buf.cells) |cell| try testing.expect(cell.char != 'T');
}

test "tabs: render with empty titles leaves the buffer blank" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{};
    Tabs.init(&titles).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try expectBlank(buf);
}

test "tabs: render into a zero-width or zero-height area leaves the buffer blank" {
    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 1 });
    tabs.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });

    try expectBlank(buf);
}

test "tabs: render outside the buffer is clipped without writing" {
    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);
    tabs.render(&buf, .{ .x = 0, .y = 5, .width = 10, .height = 1 });
    tabs.render(&buf, .{ .x = 12, .y = 0, .width = 10, .height = 1 });

    try expectBlank(buf);
    buf.check_invariants();
}
