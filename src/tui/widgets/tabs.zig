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

/// Tabs widget for navigation between sections
pub const Tabs = struct {
    /// Tab titles
    titles: []const []const u8,

    /// Currently selected tab index
    selected: usize = 0,

    /// Style for selected tab
    selected_style: Style = .{ .fg = .cyan, . bold = true },

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
            inner_area = blk.innerArea(area);
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

            // Render tab title
            var remaining_width = max_x - x;
            const title_width = @min(title.len, remaining_width);

            for (title[0..title_width], 0..) |c, offset| {
                buf.setCell(x + offset, y, c, tab_style);
            }
            x += title_width;

            // Render divider if not last tab and we have space
            if (i < self.titles.len - 1 and x < max_x) {
                remaining_width = max_x - x;
                const divider_width = @min(self.divider.len, remaining_width);

                for (self.divider[0..divider_width], 0..) |c, offset| {
                    buf.setCell(x + offset, y, c, self.normal_style);
                }
                x += divider_width;
            }
        }
    }
};

// Tests

test "Tabs.init" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles);

    try std.testing.expectEqual(3, tabs.titles.len);
    try std.testing.expectEqual(0, tabs.selected);
    try std.testing.expectEqualStrings(" │ ", tabs.divider);
}

test "Tabs.withSelected" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles).withSelected(1);

    try std.testing.expectEqual(1, tabs.selected);
}

test "Tabs.withSelected clamps to valid range" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles).withSelected(10);

    try std.testing.expectEqual(2, tabs.selected); // Should clamp to last index
}

test "Tabs.withSelected empty titles" {
    const titles = [_][]const u8{};
    const tabs = Tabs.init(&titles).withSelected(5);

    try std.testing.expectEqual(0, tabs.selected); // Should be 0 for empty
}

test "Tabs.withDivider" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles).withDivider(" | ");

    try std.testing.expectEqualStrings(" | ", tabs.divider);
}

test "Tabs.withSelectedStyle" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const custom_style = Style{ .fg = .red };
    const tabs = Tabs.init(&titles).withSelectedStyle(custom_style);

    try std.testing.expectEqual(Color.red, tabs.selected_style.fg);
}

test "Tabs.withNormalStyle" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const custom_style = Style{ .fg = .green };
    const tabs = Tabs.init(&titles).withNormalStyle(custom_style);

    try std.testing.expectEqual(Color.green, tabs.normal_style.fg);
}

test "Tabs.render basic" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "Home", "Edit", "View" };
    const tabs = Tabs.init(&titles).withSelected(1);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    tabs.render(&buf, area);

    // Check first tab (normal style)
    try std.testing.expectEqual('H', buf.get(0, 0).char);
    try std.testing.expectEqual('o', buf.get(1, 0).char);
    try std.testing.expectEqual('m', buf.get(2, 0).char);
    try std.testing.expectEqual('e', buf.get(3, 0).char);

    // Check divider
    try std.testing.expectEqual(' ', buf.get(4, 0).char);

    // Check second tab (selected, should have different style)
    try std.testing.expectEqual('E', buf.get(6, 0).char);
    try std.testing.expectEqual('d', buf.get(7, 0).char);
    try std.testing.expectEqual('i', buf.get(8, 0).char);
    try std.testing.expectEqual('t', buf.get(9, 0).char);
}

test "Tabs.render with custom divider" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B", "C" };
    const tabs = Tabs.init(&titles).withDivider(" / ");

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    tabs.render(&buf, area);

    try std.testing.expectEqual('A', buf.get(0, 0).char);
    try std.testing.expectEqual(' ', buf.get(1, 0).char);
    try std.testing.expectEqual('/', buf.get(2, 0).char);
    try std.testing.expectEqual(' ', buf.get(3, 0).char);
    try std.testing.expectEqual('B', buf.get(4, 0).char);
}

test "Tabs.render truncates when too wide" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "VeryLongTab1", "VeryLongTab2", "Tab3" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    tabs.render(&buf, area);

    // Should render first tab and possibly truncate
    try std.testing.expectEqual('V', buf.get(0, 0).char);
    try std.testing.expectEqual('e', buf.get(1, 0).char);
}

test "Tabs.render with block" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const blk = Block.init().withBorders(.all).withTitle("Navigation");
    const tabs = Tabs.init(&titles).withBlock(blk);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    tabs.render(&buf, area);

    // Block should be rendered (check border)
    try std.testing.expectEqual('┌', buf.get(0, 0).char);

    // Tabs should be inside block (at y=1, x=1 due to border)
    try std.testing.expectEqual('T', buf.get(1, 1).char);
    try std.testing.expectEqual('a', buf.get(2, 1).char);
    try std.testing.expectEqual('b', buf.get(3, 1).char);
    try std.testing.expectEqual('1', buf.get(4, 1).char);
}

test "Tabs.render empty titles" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{};
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    tabs.render(&buf, area);

    // Should not crash, buffer should remain empty/default
    try std.testing.expectEqual(' ', buf.get(0, 0).char);
}

test "Tabs.render zero width area" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    tabs.render(&buf, area);

    // Should not crash
}

test "Tabs.render selected style applied" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const selected_style = Style{ .fg = .red, . bold = true };
    const normal_style = Style{ .fg = .white };
    const tabs = Tabs.init(&titles)
        .withSelected(1)
        .withSelectedStyle(selected_style)
        .withNormalStyle(normal_style);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    tabs.render(&buf, area);

    // First tab should have normal style
    const first_char_style = buf.get(0, 0).style;
    try std.testing.expectEqual(Color.white, first_char_style.fg);

    // Second tab (selected) should have selected style
    // Position after "Tab1 │ " = 7 chars
    const selected_char_style = buf.get(7, 0).style;
    try std.testing.expectEqual(Color.red, selected_char_style.fg);
    try std.testing.expect(selected_char_style.attrs.bold);
}
