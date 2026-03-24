const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Virtual List widget - efficient rendering for massive item counts
/// Only renders visible items, supports iterators/callbacks for lazy loading
pub const VirtualList = struct {
    /// Total number of items (can be massive, e.g., 1M+)
    total_items: usize,
    /// Selected item index
    selected: ?usize = null,
    /// Scroll offset (index of first visible item)
    offset: usize = 0,
    /// Optional block (border)
    block: ?Block = null,
    /// Style for unselected items
    item_style: Style = .{},
    /// Style for selected item
    selected_style: Style = .{},
    /// Highlight symbol for selected item
    highlight_symbol: []const u8 = "> ",

    /// Callback type for fetching item text
    /// Takes item index and writes to writer
    pub const ItemCallback = *const fn (index: usize, writer: anytype) anyerror!void;

    /// Create a virtual list with total item count
    pub fn init(total: usize) VirtualList {
        return .{ .total_items = total };
    }

    /// Set selected item
    pub fn withSelected(self: VirtualList, index: ?usize) VirtualList {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set scroll offset
    pub fn withOffset(self: VirtualList, new_offset: usize) VirtualList {
        var result = self;
        result.offset = new_offset;
        return result;
    }

    /// Set block
    pub fn withBlock(self: VirtualList, new_block: Block) VirtualList {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set item style
    pub fn withItemStyle(self: VirtualList, new_style: Style) VirtualList {
        var result = self;
        result.item_style = new_style;
        return result;
    }

    /// Set selected style
    pub fn withSelectedStyle(self: VirtualList, new_style: Style) VirtualList {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set highlight symbol
    pub fn withHighlightSymbol(self: VirtualList, symbol: []const u8) VirtualList {
        var result = self;
        result.highlight_symbol = symbol;
        return result;
    }

    /// Calculate visible range based on viewport height
    fn visibleRange(self: VirtualList, height: u16) struct { start: usize, end: usize } {
        const max_items = @min(self.total_items, height);

        // Auto-scroll to keep selected item visible
        if (self.selected) |sel| {
            var start = self.offset;
            var end = start + max_items;

            // Selected is below viewport - scroll down
            if (sel >= end) {
                start = sel - max_items + 1;
                end = sel + 1;
            }
            // Selected is above viewport - scroll up
            else if (sel < start) {
                start = sel;
                end = sel + max_items;
            }

            // Clamp to bounds
            if (end > self.total_items) {
                end = self.total_items;
                start = if (self.total_items >= max_items) self.total_items - max_items else 0;
            }

            return .{ .start = start, .end = end };
        }

        // No selection - use offset
        const start = @min(self.offset, self.total_items);
        const end = @min(start + max_items, self.total_items);
        return .{ .start = start, .end = end };
    }

    /// Render virtual list using callback to fetch items on-demand
    pub fn render(self: VirtualList, buf: *Buffer, area: Rect, comptime callback: ItemCallback, allocator: std.mem.Allocator) !void {
        var render_area = area;

        // Render block if present
        if (self.block) |b| {
            b.render(buf, area);
            render_area = b.inner(area);
        }

        if (render_area.height == 0) return;

        const range = self.visibleRange(render_area.height);

        // Render only visible items
        var y: u16 = 0;
        for (range.start..range.end) |i| {
            if (y >= render_area.height) break;

            const is_selected = if (self.selected) |sel| sel == i else false;
            const style = if (is_selected) self.selected_style else self.item_style;

            // Render highlight symbol for selected item
            var x: u16 = 0;
            if (is_selected) {
                buf.setString(
                    render_area.x,
                    render_area.y + y,
                    self.highlight_symbol,
                    style,
                ) catch {};
                x = @intCast(self.highlight_symbol.len);
            } else {
                // Indent non-selected to align with selected
                x = @intCast(self.highlight_symbol.len);
            }

            // Fetch item text via callback and render
            var item_buf = std.ArrayList(u8).init(allocator);
            defer item_buf.deinit();

            try callback(i, item_buf.writer());

            const max_width = if (render_area.width > x) render_area.width - x else 0;
            const item_text = if (item_buf.items.len > max_width)
                item_buf.items[0..max_width]
            else
                item_buf.items;

            buf.setString(
                render_area.x + x,
                render_area.y + y,
                item_text,
                style,
            ) catch {};

            y += 1;
        }
    }

    /// Convenience render for slice-based items (wraps callback)
    pub fn renderSlice(self: VirtualList, buf: *Buffer, area: Rect, items: []const []const u8, allocator: std.mem.Allocator) !void {
        const Ctx = struct {
            items_ptr: []const []const u8,
            fn cb(index: usize, writer: anytype) !void {
                if (index < @This().items_ptr.len) {
                    try writer.writeAll(@This().items_ptr[index]);
                }
            }
        };
        Ctx.items_ptr = items;
        try self.render(buf, area, Ctx.cb, allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "VirtualList.init creates list with total count" {
    const list = VirtualList.init(1000000); // 1 million items
    try testing.expectEqual(@as(usize, 1000000), list.total_items);
    try testing.expectEqual(@as(?usize, null), list.selected);
    try testing.expectEqual(@as(usize, 0), list.offset);
}

test "VirtualList.visibleRange calculates viewport slice" {
    const list = VirtualList.init(100).withOffset(10);
    const range = list.visibleRange(20);

    try testing.expectEqual(@as(usize, 10), range.start);
    try testing.expectEqual(@as(usize, 30), range.end);
}

test "VirtualList.visibleRange auto-scrolls to selected" {
    var list = VirtualList.init(100).withOffset(0).withSelected(50);
    const range = list.visibleRange(20); // Height 20

    // Selected at 50, viewport height 20 → should scroll to show item 50
    try testing.expect(range.start <= 50);
    try testing.expect(range.end > 50);
}

test "VirtualList.visibleRange clamps at boundaries" {
    const list = VirtualList.init(10).withOffset(50); // Offset beyond items
    const range = list.visibleRange(20);

    try testing.expectEqual(@as(usize, 10), range.start); // Clamped to total
    try testing.expectEqual(@as(usize, 10), range.end);
}

test "VirtualList.render calls callback only for visible items" {
    var list = VirtualList.init(1000).withOffset(100);
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn cb(index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Item {}", .{index});
        }
    };
    Ctx.count = &call_count;

    try list.render(&buf, area, Ctx.cb, testing.allocator);

    // Should call callback exactly 10 times (viewport height)
    try testing.expectEqual(@as(usize, 10), call_count);
}

test "VirtualList.render handles huge item counts efficiently" {
    var list = VirtualList.init(10_000_000).withOffset(5_000_000).withSelected(5_000_005);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const Ctx = struct {
        fn cb(index: usize, writer: anytype) !void {
            try writer.print("Row {d:10}", .{index});
        }
    };

    // Should complete without memory issues
    try list.render(&buf, area, Ctx.cb, testing.allocator);

    // Verify selected item is visible in buffer
    const expected_line = "Row    5000005";
    const found = for (0..24) |y| {
        const line = buf.getLine(@intCast(y), 0, 80);
        defer testing.allocator.free(line);
        if (std.mem.indexOf(u8, line, expected_line)) |_| break true;
    } else false;

    try testing.expect(found);
}

test "VirtualList.renderSlice convenience method" {
    const items = [_][]const u8{ "Item 0", "Item 1", "Item 2", "Item 3", "Item 4" };
    var list = VirtualList.init(items.len).withSelected(2);
    var buf = try Buffer.init(testing.allocator, 30, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };

    try list.renderSlice(&buf, area, &items, testing.allocator);

    // Check selected item is highlighted
    const line2 = buf.getLine(2, 0, 30);
    defer testing.allocator.free(line2);
    try testing.expect(std.mem.indexOf(u8, line2, ">") != null);
    try testing.expect(std.mem.indexOf(u8, line2, "Item 2") != null);
}
