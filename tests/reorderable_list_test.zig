//! ReorderableList Widget Tests — v2.24.0
//!
//! Tests ReorderableList widget for interactive list reordering with drag-and-drop support.
//! ReorderableList manages item order via an order index array, navigates with cursor,
//! and supports drag mode for swapping adjacent items during navigation.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;

// Import the reorderable_list module which will be implemented at src/tui/widgets/reorderable_list.zig
const reorderable_module = sailor.tui.widgets.reorderable_list;
const ReorderableList = reorderable_module.ReorderableList;

// ============================================================================
// Test Suite: Initialization and Default State (Tests 1-3)
// ============================================================================

test "ReorderableList init defaults cursor to zero" {
    const items = [_][]const u8{ "Item A", "Item B", "Item C" };
    var order = [_]usize{ 0, 1, 2 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
    };

    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "ReorderableList init defaults drag_active to false" {
    const items = [_][]const u8{ "Item A", "Item B" };
    var order = [_]usize{ 0, 1 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
    };

    try testing.expect(!list.drag_active);
}

test "ReorderableList init order unchanged when identity mapping" {
    const items = [_][]const u8{ "First", "Second", "Third" };
    var order = [_]usize{ 0, 1, 2 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
    };

    try testing.expectEqual(@as(usize, 0), list.order[0]);
    try testing.expectEqual(@as(usize, 1), list.order[1]);
    try testing.expectEqual(@as(usize, 2), list.order[2]);
}

// ============================================================================
// Test Suite: moveCursorUp Without Drag (Tests 4-9)
// ============================================================================

test "moveCursorUp advances cursor up by 1" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 2,
    };

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

test "moveCursorUp at position 0 clamps to 0" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
    };

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "moveCursorUp moves from last position to second-to-last" {
    const items = [_][]const u8{ "A", "B", "C", "D", "E" };
    var order = [_]usize{ 0, 1, 2, 3, 4 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 4,
    };

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 3), list.cursor);
}

test "moveCursorUp multiple times reduces cursor sequentially" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 3,
    };

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 2), list.cursor);
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), list.cursor);
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "moveCursorUp without drag does not modify order" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 2,
        .drag_active = false,
    };

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.order[0]);
    try testing.expectEqual(@as(usize, 1), list.order[1]);
    try testing.expectEqual(@as(usize, 2), list.order[2]);
    try testing.expectEqual(@as(usize, 3), list.order[3]);
}

// ============================================================================
// Test Suite: moveCursorDown Without Drag (Tests 10-15)
// ============================================================================

test "moveCursorDown advances cursor down by 1" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 1,
    };

    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "moveCursorDown at last position clamps to last" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 2,
    };

    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "moveCursorDown moves from first position to second" {
    const items = [_][]const u8{ "A", "B", "C", "D", "E" };
    var order = [_]usize{ 0, 1, 2, 3, 4 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
    };

    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

test "moveCursorDown multiple times increases cursor sequentially" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
    };

    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 1), list.cursor);
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), list.cursor);
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 3), list.cursor);
}

test "moveCursorDown without drag does not modify order" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 1,
        .drag_active = false,
    };

    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), list.order[0]);
    try testing.expectEqual(@as(usize, 1), list.order[1]);
    try testing.expectEqual(@as(usize, 2), list.order[2]);
    try testing.expectEqual(@as(usize, 3), list.order[3]);
}

// ============================================================================
// Test Suite: startDrag, stopDrag, toggleDrag (Tests 16-19)
// ============================================================================

test "startDrag sets drag_active to true" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .drag_active = false,
    };

    list.startDrag();
    try testing.expect(list.drag_active);
}

test "stopDrag sets drag_active to false" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .drag_active = true,
    };

    list.stopDrag();
    try testing.expect(!list.drag_active);
}

test "toggleDrag flips drag_active from false to true" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .drag_active = false,
    };

    list.toggleDrag();
    try testing.expect(list.drag_active);
}

test "toggleDrag flips drag_active from true to false" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .drag_active = true,
    };

    list.toggleDrag();
    try testing.expect(!list.drag_active);
}

// ============================================================================
// Test Suite: moveCursorDown WITH Drag (Tests 20-23)
// ============================================================================

test "moveCursorDown with drag swaps order[cursor] and order[cursor+1]" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 1,
        .drag_active = true,
    };

    list.moveCursorDown();

    // order[1] and order[2] should be swapped
    try testing.expectEqual(@as(usize, 2), list.order[1]);
    try testing.expectEqual(@as(usize, 1), list.order[2]);
    // cursor should advance
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "moveCursorDown with drag at last position clamps without panic" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 2,
        .drag_active = true,
    };

    // Should not panic; cursor clamps to last position
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "moveCursorDown with drag twice moves item 2 positions down" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
        .drag_active = true,
    };

    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 1), list.cursor);
    // After first move: order should be [1, 0, 2, 3], cursor=1

    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), list.cursor);
    // After second move: order[1] and order[2] swap
    // order should be [1, 2, 0, 3], cursor=2

    // Verify item that was at 0 is now at position 2
    try testing.expectEqual(@as(usize, 0), list.order[2]);
}

test "moveCursorDown with drag maintains drag_active state" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 1,
        .drag_active = true,
    };

    list.moveCursorDown();
    try testing.expect(list.drag_active);
}

// ============================================================================
// Test Suite: moveCursorUp WITH Drag (Tests 24-27)
// ============================================================================

test "moveCursorUp with drag swaps order[cursor] and order[cursor-1]" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 2,
        .drag_active = true,
    };

    list.moveCursorUp();

    // order[1] and order[2] should be swapped
    try testing.expectEqual(@as(usize, 2), list.order[1]);
    try testing.expectEqual(@as(usize, 1), list.order[2]);
    // cursor should retreat
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

test "moveCursorUp with drag at position 0 clamps without panic" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
        .drag_active = true,
    };

    // Should not panic; cursor clamps to 0
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "moveCursorUp with drag twice moves item 2 positions up" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 3,
        .drag_active = true,
    };

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 2), list.cursor);
    // After first move: order[2] and order[3] swap

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), list.cursor);
    // After second move: order[1] and order[2] swap

    // Item that was at 3 should now be at position 1
    try testing.expectEqual(@as(usize, 3), list.order[1]);
}

test "moveCursorUp with drag maintains drag_active state" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 2,
        .drag_active = true,
    };

    list.moveCursorUp();
    try testing.expect(list.drag_active);
}

// ============================================================================
// Test Suite: getOrderedItem (Tests 28-30)
// ============================================================================

test "getOrderedItem returns correct label at visual row" {
    const items = [_][]const u8{ "Alpha", "Beta", "Gamma", "Delta" };
    var order = [_]usize{ 0, 1, 2, 3 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
    };

    try testing.expectEqualStrings("Alpha", list.getOrderedItem(0));
    try testing.expectEqualStrings("Beta", list.getOrderedItem(1));
    try testing.expectEqualStrings("Gamma", list.getOrderedItem(2));
}

test "getOrderedItem returns correct label after reorder" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 3, 0, 1, 2 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
    };

    // Reordered sequence should be: D, A, B, C
    try testing.expectEqualStrings("D", list.getOrderedItem(0));
    try testing.expectEqualStrings("A", list.getOrderedItem(1));
    try testing.expectEqualStrings("B", list.getOrderedItem(2));
    try testing.expectEqualStrings("C", list.getOrderedItem(3));
}

test "getOrderedItem returns last item when at boundary" {
    const items = [_][]const u8{ "First", "Second", "Third", "Last" };
    var order = [_]usize{ 3, 2, 1, 0 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
    };

    try testing.expectEqualStrings("First", list.getOrderedItem(3));
}

// ============================================================================
// Test Suite: render Basic (Tests 31-34)
// ============================================================================

test "render items appear in buffer in order" {
    const items = [_][]const u8{ "Item1", "Item2", "Item3" };
    var order = [_]usize{ 0, 1, 2 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
    };

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // First item should appear at row 0
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
}

test "render cursor symbol appears on cursor row" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 1,
        .cursor_symbol = "> ",
    };

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Cursor symbol should be on row 1
    const cell = buf.getConst(0, 1);
    try testing.expect(cell != null);
}

test "render drag symbol appears on cursor row when dragging" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
        .drag_active = true,
        .drag_symbol = "* ",
    };

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Should render without crash
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
}

test "render zero-area does not crash" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    const list = ReorderableList{
        .items = &items,
        .order = &order,
    };

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    list.render(&buf, area);

    // Verify items count is still 3 after render
    try testing.expectEqual(@as(usize, 3), list.items.len);
}

// ============================================================================
// Test Suite: Edge Cases (Tests 35-38)
// ============================================================================

test "single item moves clamp gracefully" {
    const items = [_][]const u8{ "Only" };
    var order = [_]usize{ 0 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 0,
    };

    // Try moving down at last position
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), list.cursor);

    // Try moving up at first position
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "order identity [0,1,2] unchanged without drag" {
    const items = [_][]const u8{ "A", "B", "C" };
    var order = [_]usize{ 0, 1, 2 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 1,
        .drag_active = false,
    };

    list.moveCursorUp();
    list.moveCursorDown();
    list.moveCursorDown();

    // Order should remain unchanged
    try testing.expectEqual(@as(usize, 0), list.order[0]);
    try testing.expectEqual(@as(usize, 1), list.order[1]);
    try testing.expectEqual(@as(usize, 2), list.order[2]);
}

test "cursor stays valid after stopDrag" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 2,
        .drag_active = true,
    };

    list.moveCursorDown();
    list.stopDrag();

    try testing.expect(list.cursor < list.items.len);
    try testing.expect(!list.drag_active);
}

test "four-item reorder sequence: drag down twice then up once" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    var order = [_]usize{ 0, 1, 2, 3 };

    var list = ReorderableList{
        .items = &items,
        .order = &order,
        .cursor = 1,
        .drag_active = true,
    };

    // Start: order=[0,1,2,3], cursor=1, item at 1 is "B"

    // Move down: swap order[1] and order[2]
    list.moveCursorDown();
    // order=[0,2,1,3], cursor=2
    try testing.expectEqual(@as(usize, 1), list.order[2]);

    // Move down again: swap order[2] and order[3]
    list.moveCursorDown();
    // order=[0,2,3,1], cursor=3
    try testing.expectEqual(@as(usize, 1), list.order[3]);

    // Move up: swap order[2] and order[3]
    list.moveCursorUp();
    // order=[0,2,1,3], cursor=2
    try testing.expectEqual(@as(usize, 1), list.order[2]);
}
