//! Completion popup widget: a filtered, keyboard-navigable suggestion list anchored to an input.
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const BoxSet = @import("../symbols.zig").BoxSet;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
const assert = std.debug.assert;

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

    /// Calculate required width for popup, in terminal cells (text, description, padding).
    pub fn calcWidth(self: *const CompletionPopup) u16 {
        var max_width: usize = 0;

        for (self.items) |item| {
            var width = UnicodeWidth.stringWidth(item.text);
            if (self.show_descriptions and item.description != null) {
                width += 3 + UnicodeWidth.stringWidth(item.description.?); // " - description"
            }
            if (width > max_width) max_width = width;
        }

        // Add padding and borders; clamp before narrowing so huge items cannot overflow u16.
        const padded = @min(max_width +| 4, max_popup_width);
        assert(padded <= max_popup_width);
        return @intCast(padded);
    }

    /// Calculate required height for popup
    pub fn calcHeight(self: *const CompletionPopup) u16 {
        const visible = @min(self.items.len, self.max_visible);
        const padded = @min(visible +| 2, std.math.maxInt(u16)); // +2 for borders
        assert(padded >= 2);
        return @intCast(padded);
    }

    /// Render the popup at cursor position
    pub fn render(self: *const CompletionPopup, buf: *Buffer, cursor_x: u16, cursor_y: u16) void {
        if (self.items.len == 0) return;

        const width = self.calcWidth();
        const height = self.calcHeight();

        // Calculate popup position (below cursor, with bounds checking)
        const x_max: i32 = @as(i32, buf.width) - @as(i32, width);
        const x: u16 = @intCast(@max(0, @min(@as(i32, cursor_x) + self.position.x, x_max)));

        const y_max: i32 = @as(i32, buf.height) - @as(i32, height);
        const y: u16 = @intCast(@max(0, @min(@as(i32, cursor_y) + self.position.y, y_max)));

        const area = Rect{ .x = x, .y = y, .width = width, .height = height };

        // Draw border
        const block = Block{
            .title = "Completions",
            .borders = .all,
            .border_set = BoxSet.single,
            .border_style = .{ .fg = .cyan },
        };
        block.render(buf, area);
        const inner = block.inner(area);

        // Render visible items
        const visible_end = @min(self.scroll_offset + self.max_visible, self.items.len);
        var y_offset: u16 = inner.y;

        for (self.items[self.scroll_offset..visible_end], self.scroll_offset..) |item, i| {
            if (y_offset >= inner.y + inner.height) break;
            self.renderRow(buf, inner, y_offset, item, i == self.selected_index);
            y_offset += 1;
        }

        // Scroll indicators
        if (inner.height == 0 or inner.width == 0) return;
        const cyan: Style = .{ .fg = .cyan };
        if (self.scroll_offset > 0) {
            buf.setString(inner.x + inner.width - 1, inner.y, "↑", cyan);
        }
        if (visible_end < self.items.len) {
            buf.setString(inner.x + inner.width - 1, inner.y + inner.height - 1, "↓", cyan);
        }
    }

    /// Draw one item row: indicator, text, optional description, clipped to `inner` by cells.
    fn renderRow(
        self: *const CompletionPopup,
        buf: *Buffer,
        inner: Rect,
        row_y: u16,
        item: CompletionItem,
        is_selected: bool,
    ) void {
        const style: Style = if (is_selected)
            .{ .fg = .black, .bg = .white, .bold = true }
        else
            .{ .fg = .white };

        // Selection indicator (2 cells wide: glyph plus space)
        buf.setString(inner.x, row_y, if (is_selected) "▶ " else "  ", style);

        // Item text, truncated on a character boundary to the remaining cells
        const row_end = inner.x + inner.width;
        var x_pos = inner.x + 2;
        const max_text_width = inner.width -| 2;
        x_pos += drawClipped(buf, x_pos, row_y, item.text, max_text_width, style);

        // Description (if enabled and present)
        const desc = item.description orelse return;
        if (!self.show_descriptions) return;
        const yellow: Style = .{ .fg = .yellow };
        if (row_end - x_pos > 3) {
            buf.setString(x_pos, row_y, " - ", yellow);
            x_pos += 3;
            _ = drawClipped(buf, x_pos, row_y, desc, row_end - x_pos, yellow);
        }
    }
};

const max_popup_width: usize = 80;

/// Draw `text` at (x, y) clipped to `max_cells` terminal cells without splitting a UTF-8
/// character. Returns the number of cells the clipped text occupies.
fn drawClipped(buf: *Buffer, x: u16, y: u16, text: []const u8, max_cells: u16, style: Style) u16 {
    const end = UnicodeWidth.truncate(text, max_cells);
    assert(end <= text.len);
    buf.setString(x, y, text[0..end], style);
    const used = UnicodeWidth.stringWidth(text[0..end]);
    assert(used <= max_cells);
    return @intCast(used);
}

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

    popup.selectPrev(); // Select index 4, scroll_offset = 3
    try testing.expectEqual(@as(usize, 3), popup.scroll_offset);

    popup.selectPrev(); // Select index 3: still the first row of the window, no scroll
    try testing.expectEqual(@as(usize, 3), popup.scroll_offset);

    popup.selectPrev(); // Select index 2: above the window, scroll up
    try testing.expectEqual(@as(usize, 2), popup.scroll_offset);
    try testing.expectEqual(@as(usize, 2), popup.selected_index);
}

/// Assert the narrow (1-cell) glyphs of `expected` occupy consecutive cells starting at (x, y).
fn expectRow(buf: *const Buffer, x: u16, y: u16, expected: []const u8) !void {
    var it = (try std.unicode.Utf8View.init(expected)).iterator();
    var col = x;
    while (it.nextCodepoint()) |cp| : (col += 1) {
        try testing.expectEqual(cp, buf.getChar(col, y));
    }
}

test "CompletionPopup: render draws border, selected row and plain row at exact cells" {
    const items = [_]CompletionItem{ .{ .text = "foo" }, .{ .text = "bar" } };
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    popup.render(&buf, 10, 5);

    // Area is x=10, y=6 (cursor_y + position.y), width 3+4=7, height 2+2=4.
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(10, 6));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(16, 6));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(10, 9));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(16, 9));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(10, 7));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(16, 8));
    try expectRow(&buf, 11, 7, "▶ foo");
    try expectRow(&buf, 11, 8, "  bar");
    try testing.expect(buf.getStyle(13, 7).bold);
    try testing.expect(!buf.getStyle(13, 8).bold);
    try testing.expectEqual(Color.white, buf.getStyle(13, 7).bg.?);
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 7)); // nothing outside the popup
    try testing.expectEqual(@as(u21, ' '), buf.getChar(17, 7));
}

test "CompletionPopup: render shows description after separator in yellow" {
    const items = [_]CompletionItem{
        .{ .text = "foo", .description = "Foo func" },
        .{ .text = "bar", .description = "Bar func" },
    };
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    popup.render(&buf, 10, 5);

    // Width = 3 + 3 + 8 + 4 = 18, so inner spans x=11..26 and the right border is x=27.
    try expectRow(&buf, 11, 7, "▶ foo - Foo func");
    try expectRow(&buf, 11, 8, "  bar - Bar func");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(27, 7));
    try testing.expectEqual(Color.yellow, buf.getStyle(19, 7).fg.?);
    try testing.expectEqual(Color.yellow, buf.getStyle(16, 7).fg.?);
}

test "CompletionPopup: show_descriptions false hides descriptions and narrows popup" {
    const items = [_]CompletionItem{.{ .text = "foo", .description = "Foo func" }};
    var popup = CompletionPopup.init(&items);
    popup.show_descriptions = false;
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    popup.render(&buf, 0, 0);

    // Width 7: x=0..6, inner x=1..5, right border at x=6.
    try expectRow(&buf, 1, 2, "▶ foo");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(6, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(7, 2));
}

test "CompletionPopup: render empty item list leaves the buffer untouched" {
    const items = [_]CompletionItem{};
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    popup.render(&buf, 10, 5);

    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

test "CompletionPopup: render near right edge shifts the popup left to fit" {
    const items = [_]CompletionItem{ .{ .text = "foo" }, .{ .text = "bar" } };
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    popup.render(&buf, 38, 1);

    // x_max = 40 - 7 = 33, so the popup occupies x=33..39, y=2..5.
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(33, 2));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(39, 2));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(33, 5));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(39, 5));
    try expectRow(&buf, 34, 3, "▶ foo");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(32, 3));
}

test "CompletionPopup: render near bottom edge shifts the popup up to fit" {
    const items = [_]CompletionItem{ .{ .text = "foo" }, .{ .text = "bar" } };
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    popup.render(&buf, 5, 9);

    // y_max = 10 - 4 = 6, so the popup occupies y=6..9, x=5..11.
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(5, 6));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(11, 9));
    try expectRow(&buf, 6, 7, "▶ foo");
    try expectRow(&buf, 6, 8, "  bar");
}

test "CompletionPopup: popup larger than the buffer is clipped at the origin" {
    const items = [_]CompletionItem{ .{ .text = "foo" }, .{ .text = "bar" } };
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 3, 3);
    defer buf.deinit();

    popup.render(&buf, 2, 2);

    // Negative room clamps x and y to 0; only the top-left 3x3 of the popup is visible.
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(0, 1));
    try testing.expectEqual(@as(u21, '▶'), buf.getChar(1, 1));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(2, 1));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(0, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(1, 2));
}

test "CompletionPopup: scroll down indicator replaces last visible cell, no up indicator" {
    const items = [_]CompletionItem{
        .{ .text = "1" }, .{ .text = "2" }, .{ .text = "3" }, .{ .text = "4" }, .{ .text = "5" },
    };
    var popup = CompletionPopup.init(&items);
    popup.max_visible = 3;
    popup.setSelected(2); // still inside the first window
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    popup.render(&buf, 10, 5);

    // Area x=10, y=6, width 5, height 5; inner x=11..13, y=7..9.
    try testing.expectEqual(@as(u21, '↓'), buf.getChar(13, 9));
    try testing.expectEqual(Color.cyan, buf.getStyle(13, 9).fg.?);
    try testing.expectEqual(@as(u21, '1'), buf.getChar(13, 7)); // no up indicator
    try testing.expectEqual(@as(u21, '▶'), buf.getChar(11, 9)); // row 3 is selected
}

test "CompletionPopup: scroll up indicator when window is scrolled to the end" {
    const items = [_]CompletionItem{
        .{ .text = "1" }, .{ .text = "2" }, .{ .text = "3" }, .{ .text = "4" }, .{ .text = "5" },
    };
    var popup = CompletionPopup.init(&items);
    popup.max_visible = 3;
    popup.setSelected(4);
    try testing.expectEqual(@as(usize, 2), popup.scroll_offset);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    popup.render(&buf, 10, 5);

    try testing.expectEqual(@as(u21, '↑'), buf.getChar(13, 7));
    try testing.expectEqual(@as(u21, '5'), buf.getChar(13, 9)); // last item, no down indicator
    try expectRow(&buf, 11, 9, "▶ 5");
    try expectRow(&buf, 11, 8, "  4");
}

test "CompletionPopup: multibyte text advances by cells so the description stays aligned" {
    const items = [_]CompletionItem{.{ .text = "日本", .description = "x" }};
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    popup.render(&buf, 10, 0);

    // Text is 4 cells (6 bytes): width = 4 + 3 + 1 + 4 = 12, area x=10..21, inner x=11..20.
    try testing.expectEqual(@as(u21, '日'), buf.getChar(13, 2));
    try testing.expectEqual(@as(u21, '本'), buf.getChar(15, 2));
    try expectRow(&buf, 17, 2, " - x");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(21, 2));
}

test "CompletionPopup: calcWidth counts cells, not bytes, for multibyte text" {
    const items = [_]CompletionItem{ .{ .text = "é" }, .{ .text = "日本" } };
    var popup = CompletionPopup.init(&items);
    popup.show_descriptions = false;

    try testing.expectEqual(@as(u16, 8), popup.calcWidth()); // 4 cells + 4 padding
}

test "CompletionPopup: calcWidth saturates at 80 for oversized items instead of overflowing" {
    const huge = try testing.allocator.alloc(u8, 70_000);
    defer testing.allocator.free(huge);
    @memset(huge, 'a');
    const items = [_]CompletionItem{.{ .text = huge }};
    const popup = CompletionPopup.init(&items);

    try testing.expectEqual(@as(u16, 80), popup.calcWidth());
}

test "CompletionPopup: calcHeight saturates at u16 max for more items than fit" {
    const items = try testing.allocator.alloc(CompletionItem, 70_000);
    defer testing.allocator.free(items);
    @memset(items, .{ .text = "x" });
    var popup = CompletionPopup.init(items);
    popup.max_visible = 70_000;

    try testing.expectEqual(@as(u16, std.math.maxInt(u16)), popup.calcHeight());
}

test "CompletionPopup: over-long text is truncated inside the right border" {
    const long = "a" ** 100;
    const items = [_]CompletionItem{.{ .text = long }};
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 100, 10);
    defer buf.deinit();

    popup.render(&buf, 0, 0);

    // Width 80: x=0..79, inner x=1..78, text cells x=3..78, right border at x=79.
    try testing.expectEqual(@as(u21, 'a'), buf.getChar(78, 2));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(79, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(80, 2));
}

test "CompletionPopup: wide text is cut on a character boundary at the cell limit" {
    const long = "a" ** 74 ++ "日日日"; // 80 cells; text room is 76 cells at width 80
    const items = [_]CompletionItem{.{ .text = long }};
    const popup = CompletionPopup.init(&items);
    var buf = try Buffer.init(testing.allocator, 100, 10);
    defer buf.deinit();

    popup.render(&buf, 0, 0);

    // Room is 76 cells: 74 'a' + one wide char (2 cells) fills it; the next wide char is cut.
    try testing.expectEqual(@as(u21, '日'), buf.getChar(77, 2));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(79, 2));
}

test "CompletionPopup: max_visible zero draws only the border and no stray indicator" {
    const items = [_]CompletionItem{.{ .text = "foo" }};
    var popup = CompletionPopup.init(&items);
    popup.max_visible = 0;
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    popup.render(&buf, 0, 0);

    // Height 2: top border y=1, bottom border y=2, no inner rows.
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 1));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(0, 2));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(3, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(1, 3));
}

test "CompletionPopup: getSelected is null when selected_index is out of range" {
    const items = [_]CompletionItem{.{ .text = "foo" }};
    var popup = CompletionPopup.init(&items);
    popup.selected_index = 5;

    try testing.expect(popup.getSelected() == null);
}

test "CompletionPopup: navigation on an empty list is a no-op" {
    const items = [_]CompletionItem{};
    var popup = CompletionPopup.init(&items);

    popup.selectNext();
    popup.selectPrev();
    popup.setSelected(0);

    try testing.expectEqual(@as(usize, 0), popup.selected_index);
    try testing.expectEqual(@as(usize, 0), popup.scroll_offset);
}

fn checkInvariants(popup: *const CompletionPopup) !void {
    try testing.expect(popup.selected_index < popup.items.len);
    try testing.expect(popup.selected_index >= popup.scroll_offset);
    try testing.expect(popup.selected_index < popup.scroll_offset + popup.max_visible);
}

test "CompletionPopup: seeded navigation matches a modular-index reference model" {
    const items = [_]CompletionItem{
        .{ .text = "0" }, .{ .text = "1" }, .{ .text = "2" }, .{ .text = "3" },
        .{ .text = "4" }, .{ .text = "5" }, .{ .text = "6" }, .{ .text = "7" },
    };
    var prng = std.Random.DefaultPrng.init(0x5eed_c0de);
    const random = prng.random();
    var popup = CompletionPopup.init(&items);
    popup.max_visible = 3;
    var model: usize = 0;

    for (0..500) |_| {
        switch (random.uintLessThan(u8, 3)) {
            0 => {
                popup.selectNext();
                model = (model + 1) % items.len;
            },
            1 => {
                popup.selectPrev();
                model = (model + items.len - 1) % items.len;
            },
            else => {
                const target = random.uintLessThan(usize, items.len + 3);
                popup.setSelected(target);
                if (target < items.len) model = target;
            },
        }
        try testing.expectEqual(model, popup.selected_index);
        try checkInvariants(&popup);
    }
}
