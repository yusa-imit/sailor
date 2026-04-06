//! List widget — scrollable item list with selection highlighting.
//!
//! List displays a scrollable collection of text items with optional selection
//! highlighting. It's commonly used for menus, file pickers, and option lists.
//!
//! ## Features
//! - Vertical scrolling for lists exceeding display area
//! - Selection highlighting with customizable style
//! - Highlight symbol (default: "> ") for selected item
//! - Optional Block wrapper for borders and title
//! - Automatic scroll-to-selected behavior
//!
//! ## Usage
//! ```zig
//! var list = List.init(&[_][]const u8{ "Item 1", "Item 2", "Item 3" });
//! list.selected = 0; // Select first item
//! list.selected_style = .{ .fg = .{ .basic = .cyan }, .bold = true };
//! list.render(buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// List widget - scrollable item list with selection highlight
pub const List = struct {
    items: []const []const u8,
    selected: ?usize = null,
    offset: usize = 0,
    block: ?Block = null,
    item_style: Style = .{},
    selected_style: Style = .{},
    highlight_symbol: []const u8 = "> ",

    /// Create a list with items
    pub fn init(items: []const []const u8) List {
        return .{ .items = items };
    }

    /// Set the selected item index
    pub fn withSelected(self: List, index: ?usize) List {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set scroll offset
    pub fn withOffset(self: List, new_offset: usize) List {
        var result = self;
        result.offset = new_offset;
        return result;
    }

    /// Set the block (border) for this list
    pub fn withBlock(self: List, new_block: Block) List {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set the style for unselected items
    pub fn withItemStyle(self: List, new_style: Style) List {
        var result = self;
        result.item_style = new_style;
        return result;
    }

    /// Set the style for the selected item
    pub fn withSelectedStyle(self: List, new_style: Style) List {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set the highlight symbol (prefix for selected item)
    pub fn withHighlightSymbol(self: List, symbol: []const u8) List {
        var result = self;
        result.highlight_symbol = symbol;
        return result;
    }

    /// Calculate the visible range of items
    fn visibleRange(self: List, height: u16) struct { start: usize, end: usize } {
        const max_items = @min(self.items.len, height);

        // Ensure selected item is visible
        if (self.selected) |sel| {
            var start = self.offset;
            var end = start + max_items;

            // Scroll down if selected is below visible range
            if (sel >= end) {
                start = sel - max_items + 1;
                end = sel + 1;
            }
            // Scroll up if selected is above visible range
            else if (sel < start) {
                start = sel;
                end = sel + max_items;
            }

            // Ensure we don't exceed bounds
            if (end > self.items.len) {
                end = self.items.len;
                start = if (self.items.len >= max_items) self.items.len - max_items else 0;
            }

            return .{ .start = start, .end = end };
        }

        // No selection - just use offset
        const start = @min(self.offset, self.items.len);
        const end = @min(start + max_items, self.items.len);
        return .{ .start = start, .end = end };
    }

    /// Render the list widget
    pub fn render(self: List, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Calculate visible items
        const range = self.visibleRange(inner_area.height);

        // Render items
        var y = inner_area.y;
        for (range.start..range.end) |i| {
            if (y >= inner_area.y + inner_area.height) break;

            const is_selected = if (self.selected) |sel| i == sel else false;
            const item_style = if (is_selected) self.selected_style else self.item_style;

            var x = inner_area.x;

            // Render highlight symbol for selected item
            if (is_selected) {
                for (self.highlight_symbol) |c| {
                    if (x >= inner_area.x + inner_area.width) break;
                    buf.setChar(x, y, c, item_style);
                    x += 1;
                }
            } else {
                // Skip the same width for unselected items (alignment)
                x += @min(@as(u16, @intCast(self.highlight_symbol.len)), inner_area.width);
            }

            // Render item text
            const item = self.items[i];
            for (item) |c| {
                if (x >= inner_area.x + inner_area.width) break;
                buf.setChar(x, y, c, item_style);
                x += 1;
            }

            // Fill remaining width with spaces if selected (for full-width highlight)
            if (is_selected) {
                while (x < inner_area.x + inner_area.width) : (x += 1) {
                    buf.setChar(x, y, ' ', item_style);
                }
            }

            y += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "List.init creates list with items" {
    const items = &[_][]const u8{ "Item 1", "Item 2", "Item 3" };
    const list = List.init(items);

    try std.testing.expectEqual(3, list.items.len);
    try std.testing.expectEqual(@as(?usize, null), list.selected);
    try std.testing.expectEqual(@as(usize, 0), list.offset);
}

test "List.withSelected sets selected index" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const list = List.init(items).withSelected(1);

    try std.testing.expectEqual(@as(?usize, 1), list.selected);
}

test "List.withOffset sets scroll offset" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const list = List.init(items).withOffset(1);

    try std.testing.expectEqual(@as(usize, 1), list.offset);
}

test "List.withBlock sets block" {
    const items = &[_][]const u8{ "A" };
    const block = (Block{});
    const list = List.init(items).withBlock(block);

    try std.testing.expect(list.block != null);
}

test "List.withItemStyle sets item style" {
    const items = &[_][]const u8{ "A" };
    const style = Style{ .bold = true };
    const list = List.init(items).withItemStyle(style);

    try std.testing.expectEqual(true, list.item_style.bold);
}

test "List.withSelectedStyle sets selected style" {
    const items = &[_][]const u8{ "A" };
    const style = Style{ .italic = true };
    const list = List.init(items).withSelectedStyle(style);

    try std.testing.expectEqual(true, list.selected_style.italic);
}

test "List.withHighlightSymbol sets symbol" {
    const items = &[_][]const u8{ "A" };
    const list = List.init(items).withHighlightSymbol("* ");

    try std.testing.expectEqualStrings("* ", list.highlight_symbol);
}

test "List.visibleRange with no selection" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items);

    const range = list.visibleRange(3);
    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(@as(usize, 3), range.end);
}

test "List.visibleRange with offset" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items).withOffset(2);

    const range = list.visibleRange(3);
    try std.testing.expectEqual(@as(usize, 2), range.start);
    try std.testing.expectEqual(@as(usize, 5), range.end);
}

test "List.visibleRange scrolls to show selection" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items).withSelected(4);

    const range = list.visibleRange(3);
    try std.testing.expectEqual(@as(usize, 2), range.start); // Scrolled to show item 4
    try std.testing.expectEqual(@as(usize, 5), range.end);
}

test "List.visibleRange handles small lists" {
    const items = &[_][]const u8{ "A", "B" };
    const list = List.init(items);

    const range = list.visibleRange(10);
    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(@as(usize, 2), range.end);
}

test "List.render empty area does nothing" {
    const items = &[_][]const u8{ "A" };
    const list = List.init(items);

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    list.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "List.render single item" {
    const items = &[_][]const u8{"Hello"};
    const list = List.init(items).withSelected(0); // Select first item to show highlight

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Check first item is rendered with highlight symbol
    try std.testing.expectEqual(@as(u21, '>'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(2, 0).?.char);
}

test "List.render multiple items" {
    const items = &[_][]const u8{ "One", "Two", "Three" };
    const list = List.init(items);

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Check all items are rendered
    try std.testing.expectEqual(@as(u21, 'O'), buf.get(2, 0).?.char); // "One"
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(2, 1).?.char); // "Two"
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(2, 2).?.char); // "Three"
}

test "List.render with selection highlights item" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const selected_style = Style{ .bold = true };
    const list = List.init(items).withSelected(1).withSelectedStyle(selected_style);

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Selected item should have highlight symbol
    try std.testing.expectEqual(@as(u21, '>'), buf.get(0, 1).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(1, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(2, 1).?.char);

    // Selected item should have bold style
    try std.testing.expectEqual(true, buf.get(2, 1).?.style.bold);

    // Non-selected items should not have highlight symbol at position 0
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 2).?.char);
}

test "List.render with custom highlight symbol" {
    const items = &[_][]const u8{ "A", "B" };
    const list = List.init(items).withSelected(0).withHighlightSymbol("* ");

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Should use custom symbol
    try std.testing.expectEqual(@as(u21, '*'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char);
}

test "List.render with block border" {
    const items = &[_][]const u8{ "Item" };
    const block = (Block{});
    const list = List.init(items).withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Check border is rendered
    try std.testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Check item is inside border
    try std.testing.expectEqual(@as(u21, 'I'), buf.get(3, 1).?.char);
}

test "List.render with scrolling" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items).withOffset(2);

    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 3 };
    list.render(&buf, area);

    // Should show items C, D, E (offset 2)
    try std.testing.expectEqual(@as(u21, 'C'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'D'), buf.get(2, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(2, 2).?.char);
}

test "List.render clips text at width boundary" {
    const items = &[_][]const u8{"Very Long Item Text"};
    const list = List.init(items);

    var buf = try Buffer.init(std.testing.allocator, 8, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 1 };
    list.render(&buf, area);

    // Should clip at width boundary
    try std.testing.expectEqual(@as(u21, 'V'), buf.get(2, 0).?.char); // After "> "
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
    // Width is 8, so only "> Very " should fit
}

test "List.render with offset area" {
    const items = &[_][]const u8{ "A", "B" };
    const list = List.init(items).withSelected(0); // Select first item to show highlight

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 5, .y = 3, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Should render at offset position with highlight symbol
    try std.testing.expectEqual(@as(u21, '>'), buf.get(5, 3).?.char);
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(7, 3).?.char);
}

test "List.render selection full-width highlight" {
    const items = &[_][]const u8{"A"};
    const selected_style = Style{ .bg = .{ .indexed = 240 } };
    const list = List.init(items).withSelected(0).withSelectedStyle(selected_style);

    var buf = try Buffer.init(std.testing.allocator, 10, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    list.render(&buf, area);

    // Selected row should have background all the way across
    for (0..10) |x| {
        const cell = buf.get(@intCast(x), 0).?;
        try std.testing.expect(cell.style.bg != null);
    }
}
