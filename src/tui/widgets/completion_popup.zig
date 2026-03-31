const std = @import("std");
const tui = @import("../tui.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const BoxSet = @import("../symbols.zig").BoxSet;

/// Completion item
pub const CompletionItem = struct {
    text: []const u8,
    description: ?[]const u8 = null,
};

/// Completion popup widget for REPL autocomplete
pub const CompletionPopup = struct {
    items: []const CompletionItem,
    selected_index: usize = 0,
    max_visible: usize = 10,
    scroll_offset: usize = 0,
    show_descriptions: bool = true,

    /// Position relative to cursor (x, y offset)
    position: struct { x: i16 = 0, y: i16 = 1 } = .{},

    /// Create completion popup with items to display.
    pub fn init(items: []const CompletionItem) CompletionPopup {
        return .{
            .items = items,
        };
    }

    /// Get the currently selected item
    pub fn getSelected(self: *const CompletionPopup) ?CompletionItem {
        if (self.items.len == 0) return null;
        if (self.selected_index >= self.items.len) return null;
        return self.items[self.selected_index];
    }

    /// Move selection to next item
    pub fn selectNext(self: *CompletionPopup) void {
        if (self.items.len == 0) return;

        self.selected_index = (self.selected_index + 1) % self.items.len;

        // Auto-scroll if needed
        if (self.selected_index >= self.scroll_offset + self.max_visible) {
            self.scroll_offset = self.selected_index - self.max_visible + 1;
        } else if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        }
    }

    /// Move selection to previous item
    pub fn selectPrev(self: *CompletionPopup) void {
        if (self.items.len == 0) return;

        if (self.selected_index == 0) {
            self.selected_index = self.items.len - 1;
            // Scroll to bottom
            if (self.items.len > self.max_visible) {
                self.scroll_offset = self.items.len - self.max_visible;
            } else {
                self.scroll_offset = 0;
            }
        } else {
            self.selected_index -= 1;

            // Auto-scroll if needed
            if (self.selected_index < self.scroll_offset) {
                self.scroll_offset = self.selected_index;
            } else if (self.selected_index >= self.scroll_offset + self.max_visible) {
                self.scroll_offset = self.selected_index - self.max_visible + 1;
            }
        }
    }

    /// Set selection by index
    pub fn setSelected(self: *CompletionPopup, index: usize) void {
        if (index >= self.items.len) return;
        self.selected_index = index;

        // Adjust scroll offset
        if (self.selected_index >= self.scroll_offset + self.max_visible) {
            self.scroll_offset = self.selected_index - self.max_visible + 1;
        } else if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        }
    }

    /// Calculate required width for popup
    pub fn calcWidth(self: *const CompletionPopup) u16 {
        var max_width: usize = 0;

        for (self.items) |item| {
            var width = item.text.len;
            if (self.show_descriptions and item.description != null) {
                width += 3 + item.description.?.len; // " - description"
            }
            if (width > max_width) max_width = width;
        }

        // Add padding and borders
        return @min(@as(u16, @intCast(max_width + 4)), 80);
    }

    /// Calculate required height for popup
    pub fn calcHeight(self: *const CompletionPopup) u16 {
        const visible = @min(self.items.len, self.max_visible);
        return @intCast(visible + 2); // +2 for borders
    }

    /// Render the popup at cursor position
    pub fn render(self: *const CompletionPopup, buf: *Buffer, cursor_x: u16, cursor_y: u16) void {
        if (self.items.len == 0) return;

        const width = self.calcWidth();
        const height = self.calcHeight();

        // Calculate popup position (below cursor, with bounds checking)
        const x: u16 = @intCast(@max(0, @min(
            @as(i32, cursor_x) + self.position.x,
            @as(i32, buf.width) - @as(i32, width)
        )));

        const y: u16 = @intCast(@max(0, @min(
            @as(i32, cursor_y) + self.position.y,
            @as(i32, buf.height) - @as(i32, height)
        )));

        const area = Rect{ .x = x, .y = y, .width = width, .height = height };

        // Draw border
        const block = Block{
            .title = "Completions",
            .borders = .all,
            .border_set = BoxSet.single,
            .style = .{ .fg = .{ .basic = .cyan } },
        };
        block.render(buf, area);
        const inner = block.inner(area);

        // Render visible items
        const visible_end = @min(self.scroll_offset + self.max_visible, self.items.len);
        var y_offset: u16 = inner.y;

        for (self.items[self.scroll_offset..visible_end], self.scroll_offset..) |item, i| {
            if (y_offset >= inner.y + inner.height) break;

            const is_selected = i == self.selected_index;
            const style: Style = if (is_selected)
                .{ .fg = .{ .basic = .black }, .bg = .{ .basic = .white }, .bold = true }
            else
                .{ .fg = .{ .basic = .white } };

            // Selection indicator
            const indicator = if (is_selected) "▶ " else "  ";
            buf.setString(inner.x, y_offset, indicator, style);

            // Item text
            var x_pos = inner.x + 2;
            const max_text_width = inner.width -| 2;
            const text_len = @min(item.text.len, max_text_width);
            buf.setString(x_pos, y_offset, item.text[0..text_len], style);
            x_pos += @intCast(text_len);

            // Description (if enabled and present)
            if (self.show_descriptions and item.description != null) {
                const remaining_width = inner.x + inner.width - x_pos;
                if (remaining_width > 3) {
                    buf.setString(x_pos, y_offset, " - ", .{ .fg = .{ .basic = .yellow } });
                    x_pos += 3;

                    const desc_width = @min(item.description.?.len, inner.x + inner.width - x_pos);
                    if (desc_width > 0) {
                        buf.setString(x_pos, y_offset, item.description.?[0..desc_width], .{ .fg = .{ .basic = .yellow } });
                    }
                }
            }

            y_offset += 1;
        }

        // Scroll indicators
        if (self.scroll_offset > 0) {
            buf.setString(inner.x + inner.width - 1, inner.y, "↑", .{ .fg = .{ .basic = .cyan } });
        }
        if (visible_end < self.items.len) {
            buf.setString(inner.x + inner.width - 1, inner.y + inner.height - 1, "↓", .{ .fg = .{ .basic = .cyan } });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "CompletionPopup: init" {
    const items = [_]CompletionItem{
        .{ .text = "foo", .description = "Foo function" },
        .{ .text = "bar", .description = "Bar function" },
    };

    const popup = CompletionPopup.init(&items);
    try testing.expectEqual(@as(usize, 2), popup.items.len);
    try testing.expectEqual(@as(usize, 0), popup.selected_index);
}

test "CompletionPopup: getSelected" {
    const items = [_]CompletionItem{
        .{ .text = "foo" },
        .{ .text = "bar" },
    };

    const popup = CompletionPopup.init(&items);
    const selected = popup.getSelected().?;
    try testing.expectEqualStrings("foo", selected.text);
}

test "CompletionPopup: getSelected empty" {
    const items = [_]CompletionItem{};
    const popup = CompletionPopup.init(&items);
    try testing.expect(popup.getSelected() == null);
}

test "CompletionPopup: selectNext" {
    const items = [_]CompletionItem{
        .{ .text = "foo" },
        .{ .text = "bar" },
        .{ .text = "baz" },
    };

    var popup = CompletionPopup.init(&items);
    try testing.expectEqual(@as(usize, 0), popup.selected_index);

    popup.selectNext();
    try testing.expectEqual(@as(usize, 1), popup.selected_index);

    popup.selectNext();
    try testing.expectEqual(@as(usize, 2), popup.selected_index);

    popup.selectNext(); // Wrap around
    try testing.expectEqual(@as(usize, 0), popup.selected_index);
}

test "CompletionPopup: selectPrev" {
    const items = [_]CompletionItem{
        .{ .text = "foo" },
        .{ .text = "bar" },
        .{ .text = "baz" },
    };

    var popup = CompletionPopup.init(&items);
    try testing.expectEqual(@as(usize, 0), popup.selected_index);

    popup.selectPrev(); // Wrap to end
    try testing.expectEqual(@as(usize, 2), popup.selected_index);

    popup.selectPrev();
    try testing.expectEqual(@as(usize, 1), popup.selected_index);

    popup.selectPrev();
    try testing.expectEqual(@as(usize, 0), popup.selected_index);
}

test "CompletionPopup: setSelected" {
    const items = [_]CompletionItem{
        .{ .text = "foo" },
        .{ .text = "bar" },
        .{ .text = "baz" },
    };

    var popup = CompletionPopup.init(&items);

    popup.setSelected(2);
    try testing.expectEqual(@as(usize, 2), popup.selected_index);

    popup.setSelected(0);
    try testing.expectEqual(@as(usize, 0), popup.selected_index);

    popup.setSelected(99); // Out of bounds - should be ignored
    try testing.expectEqual(@as(usize, 0), popup.selected_index);
}

test "CompletionPopup: calcWidth without descriptions" {
    const items = [_]CompletionItem{
        .{ .text = "short" },
        .{ .text = "much_longer_item" },
        .{ .text = "mid" },
    };

    var popup = CompletionPopup.init(&items);
    popup.show_descriptions = false;

    const width = popup.calcWidth();
    // "much_longer_item" (16) + padding (4) = 20
    try testing.expectEqual(@as(u16, 20), width);
}

test "CompletionPopup: calcWidth with descriptions" {
    const items = [_]CompletionItem{
        .{ .text = "foo", .description = "Foo function" },
        .{ .text = "bar", .description = "Very long description here" },
    };

    var popup = CompletionPopup.init(&items);
    popup.show_descriptions = true;

    const width = popup.calcWidth();
    // "bar" (3) + " - " (3) + "Very long description here" (26) + padding (4) = 36
    try testing.expectEqual(@as(u16, 36), width);
}

test "CompletionPopup: calcHeight" {
    const items = [_]CompletionItem{
        .{ .text = "1" },
        .{ .text = "2" },
        .{ .text = "3" },
    };

    const popup = CompletionPopup.init(&items);
    const height = popup.calcHeight();
    // 3 items + 2 borders = 5
    try testing.expectEqual(@as(u16, 5), height);
}

test "CompletionPopup: calcHeight with max_visible" {
    const items = [_]CompletionItem{
        .{ .text = "1" },
        .{ .text = "2" },
        .{ .text = "3" },
        .{ .text = "4" },
        .{ .text = "5" },
        .{ .text = "6" },
        .{ .text = "7" },
        .{ .text = "8" },
        .{ .text = "9" },
        .{ .text = "10" },
        .{ .text = "11" },
        .{ .text = "12" },
    };

    var popup = CompletionPopup.init(&items);
    popup.max_visible = 5;

    const height = popup.calcHeight();
    // max_visible (5) + 2 borders = 7
    try testing.expectEqual(@as(u16, 7), height);
}

test "CompletionPopup: scrolling with selectNext" {
    const items = [_]CompletionItem{
        .{ .text = "1" },
        .{ .text = "2" },
        .{ .text = "3" },
        .{ .text = "4" },
        .{ .text = "5" },
        .{ .text = "6" },
    };

    var popup = CompletionPopup.init(&items);
    popup.max_visible = 3;

    try testing.expectEqual(@as(usize, 0), popup.scroll_offset);

    popup.selectNext(); // Select 1, scroll_offset = 0
    try testing.expectEqual(@as(usize, 0), popup.scroll_offset);

    popup.selectNext(); // Select 2, scroll_offset = 0
    try testing.expectEqual(@as(usize, 0), popup.scroll_offset);

    popup.selectNext(); // Select 3, scroll_offset = 1 (scroll down)
    try testing.expectEqual(@as(usize, 1), popup.scroll_offset);

    popup.selectNext(); // Select 4, scroll_offset = 2
    try testing.expectEqual(@as(usize, 2), popup.scroll_offset);
}

test "CompletionPopup: scrolling with selectPrev" {
    const items = [_]CompletionItem{
        .{ .text = "1" },
        .{ .text = "2" },
        .{ .text = "3" },
        .{ .text = "4" },
        .{ .text = "5" },
        .{ .text = "6" },
    };

    var popup = CompletionPopup.init(&items);
    popup.max_visible = 3;
    popup.setSelected(5); // Start at last item

    // Should scroll to show last 3 items
    try testing.expectEqual(@as(usize, 3), popup.scroll_offset);

    popup.selectPrev(); // Select 4, scroll_offset = 3
    try testing.expectEqual(@as(usize, 3), popup.scroll_offset);

    popup.selectPrev(); // Select 3, scroll_offset = 2 (scroll up)
    try testing.expectEqual(@as(usize, 2), popup.scroll_offset);
}

test "CompletionPopup: render basic" {
    const allocator = testing.allocator;
    const items = [_]CompletionItem{
        .{ .text = "foo" },
        .{ .text = "bar" },
    };

    const popup = CompletionPopup.init(&items);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    popup.render(&buf, 10, 5);

    // Verify border exists
    const top_left = buf.get(10, 6); // y=5 + position.y=1
    try testing.expectEqual(@as(u21, '┌'), top_left.char);
}

test "CompletionPopup: render with descriptions" {
    const allocator = testing.allocator;
    const items = [_]CompletionItem{
        .{ .text = "foo", .description = "Foo func" },
        .{ .text = "bar", .description = "Bar func" },
    };

    var popup = CompletionPopup.init(&items);
    popup.show_descriptions = true;

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    popup.render(&buf, 10, 5);

    // Verify selection indicator
    const indicator_cell = buf.get(11, 7); // Inside border, first item
    try testing.expectEqual(@as(u21, '▶'), indicator_cell.char);
}

test "CompletionPopup: render empty" {
    const allocator = testing.allocator;
    const items = [_]CompletionItem{};
    const popup = CompletionPopup.init(&items);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    // Should not crash
    popup.render(&buf, 10, 5);
}

test "CompletionPopup: render near screen edge" {
    const allocator = testing.allocator;
    const items = [_]CompletionItem{
        .{ .text = "foo" },
        .{ .text = "bar" },
    };

    const popup = CompletionPopup.init(&items);

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit(allocator);

    // Render near right edge - should adjust position
    popup.render(&buf, 38, 1);

    // Render near bottom edge - should adjust position
    popup.render(&buf, 5, 9);
}

test "CompletionPopup: scroll indicators" {
    const allocator = testing.allocator;
    const items = [_]CompletionItem{
        .{ .text = "1" },
        .{ .text = "2" },
        .{ .text = "3" },
        .{ .text = "4" },
        .{ .text = "5" },
    };

    var popup = CompletionPopup.init(&items);
    popup.max_visible = 3;
    popup.setSelected(2); // Middle selection triggers scroll

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    popup.render(&buf, 10, 5);

    // Should show scroll down indicator when there are more items below
    const width = popup.calcWidth();
    const height = popup.calcHeight();

    // Check if scroll down indicator exists (at bottom-right of inner area)
    const scroll_x = 10 + width - 2; // -2 for border
    const scroll_y = 6 + height - 2; // y=6 (popup y), -2 for border
    const scroll_cell = buf.get(scroll_x, scroll_y);
    try testing.expectEqual(@as(u21, '↓'), scroll_cell.char);
}
