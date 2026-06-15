const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const List = sailor.tui.widgets.List;
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const Color = sailor.tui.Color;

test "List initialization with items" {
    const items = &[_][]const u8{ "Item 1", "Item 2", "Item 3" };
    const list = List.init(items);

    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expectEqual(@as(?usize, null), list.selected);
    try testing.expectEqual(@as(usize, 0), list.offset);
    try testing.expectEqualStrings("> ", list.highlight_symbol);
}

test "List initialization with empty items" {
    const items = &[_][]const u8{};
    const list = List.init(items);

    try testing.expectEqual(@as(usize, 0), list.items.len);
    try testing.expectEqual(@as(?usize, null), list.selected);
}

test "List.withSelected sets selected index" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const list = List.init(items).withSelected(1);

    try testing.expectEqual(@as(?usize, 1), list.selected);
}

test "List.withSelected preserves immutability" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const original = List.init(items);
    const modified = original.withSelected(2);

    try testing.expectEqual(@as(?usize, null), original.selected);
    try testing.expectEqual(@as(?usize, 2), modified.selected);
}

test "List.withOffset sets scroll offset" {
    const items = &[_][]const u8{ "A", "B", "C", "D" };
    const list = List.init(items).withOffset(2);

    try testing.expectEqual(@as(usize, 2), list.offset);
}

test "List.withBlock sets block border" {
    const items = &[_][]const u8{ "Item" };
    const block = Block{};
    const list = List.init(items).withBlock(block);

    try testing.expect(list.block != null);
}

test "List.withItemStyle sets unselected item style" {
    const items = &[_][]const u8{ "A" };
    const style = Style{ .bold = true };
    const list = List.init(items).withItemStyle(style);

    try testing.expect(list.item_style.bold);
}

test "List.withSelectedStyle sets selected item style" {
    const items = &[_][]const u8{ "A" };
    const style = Style{ .fg = Color.cyan };
    const list = List.init(items).withSelectedStyle(style);

    try testing.expectEqual(Color.cyan, list.selected_style.fg);
}

test "List.withHighlightSymbol sets highlight symbol" {
    const items = &[_][]const u8{ "A" };
    const list = List.init(items).withHighlightSymbol("* ");

    try testing.expectEqualStrings("* ", list.highlight_symbol);
}

test "List render single item without selection" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const items = &[_][]const u8{"Hello"};
    const list = List.init(items);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Should render at x=2 (after highlight symbol space)
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char); // Highlight symbol space
    try testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char); // Highlight symbol space
    try testing.expectEqual(@as(u21, 'H'), buf.get(2, 0).?.char);
}

test "List render single item with selection" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const items = &[_][]const u8{"Hello"};
    const list = List.init(items).withSelected(0);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Should render highlight symbol
    try testing.expectEqual(@as(u21, '>'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'H'), buf.get(2, 0).?.char);
}

test "List render multiple items" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const items = &[_][]const u8{ "One", "Two", "Three" };
    const list = List.init(items);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Check all items rendered (with highlight symbol offset)
    try testing.expectEqual(@as(u21, 'O'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'T'), buf.get(2, 1).?.char);
    try testing.expectEqual(@as(u21, 'T'), buf.get(2, 2).?.char);
}

test "List render selection highlighting" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const items = &[_][]const u8{ "A", "B", "C" };
    const selected_style = Style{ .bold = true };
    const list = List.init(items)
        .withSelected(1)
        .withSelectedStyle(selected_style);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Selected item (row 1) should have highlight symbol
    try testing.expectEqual(@as(u21, '>'), buf.get(0, 1).?.char);

    // Selected item should have bold style
    try testing.expectEqual(true, buf.get(2, 1).?.style.bold);

    // Non-selected items should not have highlight symbol
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 2).?.char);
}

test "List render custom highlight symbol" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const items = &[_][]const u8{ "A", "B" };
    const list = List.init(items)
        .withSelected(0)
        .withHighlightSymbol("* ");

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Should use custom symbol
    try testing.expectEqual(@as(u21, '*'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char);
}

test "List render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const items = &[_][]const u8{"Item"};
    const block = Block{};
    const list = List.init(items).withBlock(block);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Check border is rendered
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Item should be inside border (at y=1, x=3 for symbol + space)
    try testing.expectEqual(@as(u21, 'I'), buf.get(3, 1).?.char);
}

test "List render with scrolling offset" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 3);
    defer buf.deinit();

    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items).withOffset(2);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 3 };
    list.render(&buf, area);

    // Should show items C, D, E (offset 2)
    try testing.expectEqual(@as(u21, 'C'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'D'), buf.get(2, 1).?.char);
    try testing.expectEqual(@as(u21, 'E'), buf.get(2, 2).?.char);
}

test "List render clipping text at width boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 8, 1);
    defer buf.deinit();

    const items = &[_][]const u8{"Very Long Item Text"};
    const list = List.init(items);

    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 1 };
    list.render(&buf, area);

    // Should clip at width boundary (after "> ")
    try testing.expectEqual(@as(u21, 'V'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
}

test "List render with offset area position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = &[_][]const u8{ "A", "B" };
    const list = List.init(items).withSelected(0);

    const area = Rect{ .x = 5, .y = 3, .width = 10, .height = 5 };
    list.render(&buf, area);

    // Should render at offset position
    try testing.expectEqual(@as(u21, '>'), buf.get(5, 3).?.char);
    try testing.expectEqual(@as(u21, 'A'), buf.get(7, 3).?.char);
}

test "List render selection full-width highlight" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const items = &[_][]const u8{"A"};
    const selected_style = Style{ .bg = Color.fromIndexed(240) };
    const list = List.init(items)
        .withSelected(0)
        .withSelectedStyle(selected_style);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    list.render(&buf, area);

    // Selected row should have background all the way across
    for (0..10) |x| {
        const cell = buf.get(@intCast(x), 0).?;
        try testing.expect(cell.style.bg != null);
    }
}

test "List render empty area does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const items = &[_][]const u8{ "A", "B" };
    const list = List.init(items);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 5 };
    list.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "List scrollDown increments offset" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items);

    const scrolled = list.scrollDown(2, null);
    try testing.expectEqual(@as(usize, 2), scrolled.offset);

    const scrolled_more = scrolled.scrollDown(1, null);
    try testing.expectEqual(@as(usize, 3), scrolled_more.offset);
}

test "List scrollDown respects visible_rows bounds" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items);

    // With 3 visible rows, max offset is 5 - 3 = 2
    const scrolled = list.scrollDown(10, 3);
    try testing.expectEqual(@as(usize, 2), scrolled.offset);
}

test "List scrollDown without visible_rows clamps to item count" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const list = List.init(items);

    const scrolled = list.scrollDown(100, null);
    try testing.expectEqual(@as(usize, 3), scrolled.offset);
}

test "List scrollUp decrements offset" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const list = List.init(items).withOffset(2);

    const scrolled = list.scrollUp(1);
    try testing.expectEqual(@as(usize, 1), scrolled.offset);

    const scrolled_more = scrolled.scrollUp(1);
    try testing.expectEqual(@as(usize, 0), scrolled_more.offset);
}

test "List scrollUp never goes below zero" {
    const items = &[_][]const u8{"A"};
    const list = List.init(items).withOffset(1);

    const scrolled = list.scrollUp(100);
    try testing.expectEqual(@as(usize, 0), scrolled.offset);
}

test "List scrollToTop resets offset" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const list = List.init(items).withOffset(2);

    const scrolled = list.scrollToTop();
    try testing.expectEqual(@as(usize, 0), scrolled.offset);
}

test "List scrollToBottom with visible_rows" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items);

    // With 3 visible rows, offset should be 5 - 3 = 2
    const scrolled = list.scrollToBottom(3);
    try testing.expectEqual(@as(usize, 2), scrolled.offset);
}

test "List scrollToBottom with visible_rows larger than items" {
    const items = &[_][]const u8{ "A", "B" };
    const list = List.init(items);

    const scrolled = list.scrollToBottom(10);
    try testing.expectEqual(@as(usize, 0), scrolled.offset);
}

test "List scroll methods can be chained" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items);

    const scrolled = list.scrollDown(3, null).scrollUp(1).scrollDown(1, null);
    try testing.expectEqual(@as(usize, 3), scrolled.offset);
}

test "List scroll methods immutable" {
    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const original = List.init(items);

    const scrolled = original.scrollDown(2, null);

    try testing.expectEqual(@as(usize, 0), original.offset);
    try testing.expectEqual(@as(usize, 2), scrolled.offset);
}

test "List saveState captures current state" {
    const items = &[_][]const u8{ "Item 1", "Item 2", "Item 3" };
    const list = List.init(items)
        .withSelected(1)
        .scrollDown(2, null)
        .withHighlightSymbol("→ ");

    const state = list.saveState();

    try testing.expectEqual(@as(?usize, 1), state.selected);
    try testing.expectEqual(@as(usize, 2), state.offset);
    try testing.expectEqualStrings("→ ", state.highlight_symbol);
}

test "List restoreState restores all fields" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const original = List.init(items).withSelected(2).scrollDown(1, null);
    const state = original.saveState();

    const fresh = List.init(items);
    const restored = fresh.restoreState(state);

    try testing.expectEqual(@as(?usize, 2), restored.selected);
    try testing.expectEqual(@as(usize, 1), restored.offset);
}

test "List builder chain preserves immutability" {
    const items = &[_][]const u8{ "A", "B", "C" };
    const original = List.init(items);

    const modified = original
        .withSelected(1)
        .withOffset(2)
        .withHighlightSymbol("* ");

    try testing.expectEqual(@as(?usize, null), original.selected);
    try testing.expectEqual(@as(usize, 0), original.offset);
    try testing.expectEqualStrings("> ", original.highlight_symbol);

    try testing.expectEqual(@as(?usize, 1), modified.selected);
    try testing.expectEqual(@as(usize, 2), modified.offset);
    try testing.expectEqualStrings("* ", modified.highlight_symbol);
}

test "List render selection scrolls into view" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 3);
    defer buf.deinit();

    const items = &[_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List.init(items).withSelected(4); // Select last item

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 3 };
    list.render(&buf, area);

    // Should show items C, D, E (scrolled to show selection)
    try testing.expectEqual(@as(u21, 'C'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'D'), buf.get(2, 1).?.char);
    try testing.expectEqual(@as(u21, 'E'), buf.get(2, 2).?.char);
}

test "List render with many items exceeding visible area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 3);
    defer buf.deinit();

    const items = &[_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" };
    const list = List.init(items).withOffset(5);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 3 };
    list.render(&buf, area);

    // Should show items 6, 7, 8 (offset 5)
    try testing.expectEqual(@as(u21, '6'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, '7'), buf.get(2, 1).?.char);
    try testing.expectEqual(@as(u21, '8'), buf.get(2, 2).?.char);
}
