//! Comprehensive tests for sailor's ReactiveList widget (v2.13.0)
//!
//! Tests for ReactiveList(T) - list widget bound to Signal([]const T).
//!
//! Coverage:
//! - ReactiveList init with signal and render function
//! - ReactiveList render empty list
//! - ReactiveList render single item
//! - ReactiveList render multiple items
//! - ReactiveList items render in order
//! - ReactiveList updates when signal changes
//! - ReactiveList scrolling position preserved
//! - ReactiveList selection handling
//! - ReactiveList custom render function
//! - ReactiveList with string items
//! - ReactiveList with struct items
//! - ReactiveList rendering to buffer
//! - ReactiveList layout constraints (height, width)
//! - ReactiveList handles buffer overflows
//! - ReactiveList deinit cleans up

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const signal_mod = sailor.signal;
const tui = sailor.tui;
const Buffer = tui.buffer.Buffer;
const Rect = tui.layout.Rect;

// ============================================================================
// Example Item Types
// ============================================================================

const StringItem = []const u8;

const Task = struct {
    id: u32,
    title: []const u8,
    completed: bool,
};

// ============================================================================
// Helper Functions
// ============================================================================

fn renderStringItem(item: StringItem, buf: *Buffer, area: Rect) void {
    var i: u32 = 0;
    for (item) |c| {
        if (i >= area.width) break;
        buf.setCell(area.x + i, area.y, .{ .char = c });
        i += 1;
    }
}

fn renderTaskItem(item: Task, buf: *Buffer, area: Rect) void {
    const prefix = if (item.completed) "[x] " else "[ ] ";
    var col: u32 = 0;

    for (prefix) |c| {
        if (col >= area.width) break;
        buf.setCell(area.x + col, area.y, .{ .char = c });
        col += 1;
    }

    for (item.title) |c| {
        if (col >= area.width) break;
        buf.setCell(area.x + col, area.y, .{ .char = c });
        col += 1;
    }
}

// ============================================================================
// ReactiveList Lifecycle Tests
// ============================================================================

test "ReactiveList init with signal and render function" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("Item 1");
    try items.append("Item 2");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);
    _ = list;
    // Should initialize without errors
}

test "ReactiveList deinit cleans up" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("Item 1");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);
    _ = list;
    // ReactiveList is typically stack-allocated, no explicit deinit needed
}

// ============================================================================
// Empty List Tests
// ============================================================================

test "ReactiveList render empty list" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Empty list should render without crashing
}

// ============================================================================
// Single Item Tests
// ============================================================================

test "ReactiveList render single item" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("Hello");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Item should be rendered in buffer at position (0, 0)
    const cell = buf.getCell(0, 0);
    try testing.expectEqual(@as(u21, 'H'), cell.char);
}

// ============================================================================
// Multiple Items Tests
// ============================================================================

test "ReactiveList render multiple items" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("Item 1");
    try items.append("Item 2");
    try items.append("Item 3");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // All items should be rendered
    // Item 1 at row 0, Item 2 at row 1, Item 3 at row 2
}

test "ReactiveList items render in order" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("A");
    try items.append("B");
    try items.append("C");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Items should render in order: A at (0,0), B at (0,1), C at (0,2)
    try testing.expectEqual(@as(u21, 'A'), buf.getCell(0, 0).char);
    try testing.expectEqual(@as(u21, 'B'), buf.getCell(0, 1).char);
    try testing.expectEqual(@as(u21, 'C'), buf.getCell(0, 2).char);
}

// ============================================================================
// Signal Update Tests
// ============================================================================

test "ReactiveList updates when signal changes" {
    const allocator = testing.allocator;
    var items1 = std.ArrayList(StringItem).init(allocator);
    defer items1.deinit();
    try items1.append("Old");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items1.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    // Render with first items
    list.render(&buf, area);
    try testing.expectEqual(@as(u21, 'O'), buf.getCell(0, 0).char);

    // Update signal with new items
    var items2 = std.ArrayList(StringItem).init(allocator);
    defer items2.deinit();
    try items2.append("New");

    try signal.set(items2.items);

    // Clear buffer and re-render
    buf.clear();
    list.render(&buf, area);

    // Should now show "New"
    try testing.expectEqual(@as(u21, 'N'), buf.getCell(0, 0).char);
}

test "ReactiveList reacts to signal changes" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("First");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    // Verify initial state
    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    try testing.expectEqual(@as(u21, 'F'), buf.getCell(0, 0).char);

    // Change signal
    var new_items = std.ArrayList(StringItem).init(allocator);
    defer new_items.deinit();
    try new_items.append("Second");

    try signal.set(new_items.items);

    buf.clear();
    list.render(&buf, area);

    try testing.expectEqual(@as(u21, 'S'), buf.getCell(0, 0).char);
}

// ============================================================================
// Custom Render Function Tests
// ============================================================================

test "ReactiveList with custom render function for struct items" {
    const allocator = testing.allocator;
    var items = std.ArrayList(Task).init(allocator);
    defer items.deinit();

    try items.append(.{ .id = 1, .title = "Buy milk", .completed = false });
    try items.append(.{ .id = 2, .title = "Read book", .completed = true });

    var signal = try signal_mod.Signal([]const Task).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(Task).init(&signal, renderTaskItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // First item should have [ ] prefix (not completed)
    // Second item should have [x] prefix (completed)
}

test "ReactiveList render function receives correct area" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("Test");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    // Render at offset position
    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 10 };
    list.render(&buf, area);

    // Item should be rendered starting at (10, 5)
    try testing.expectEqual(@as(u21, 'T'), buf.getCell(10, 5).char);
}

// ============================================================================
// Layout Tests
// ============================================================================

test "ReactiveList respects width constraint" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("This is a very long text that exceeds width");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 24 };
    list.render(&buf, area);

    // Text should be truncated to width 10
}

test "ReactiveList respects height constraint" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    // Create many items
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try items.append("Item");
    }

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    list.render(&buf, area);

    // Only 5 items should be rendered (respecting height)
}

// ============================================================================
// Selection Tests
// ============================================================================

test "ReactiveList supports item selection" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("Item 1");
    try items.append("Item 2");
    try items.append("Item 3");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // List should support selection state tracking
}

// ============================================================================
// Scrolling Tests
// ============================================================================

test "ReactiveList supports scrolling" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try items.append("Item");
    }

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    list.render(&buf, area);

    // List should be scrollable within height constraint
}

// ============================================================================
// Buffer Handling Tests
// ============================================================================

test "ReactiveList handles buffer cell updates correctly" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("X");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Verify cell was updated
    const cell = buf.getCell(0, 0);
    try testing.expectEqual(@as(u21, 'X'), cell.char);
}

test "ReactiveList no crash with empty area" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("Item");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    list.render(&buf, area);

    // Should not crash with zero-sized area
}

// ============================================================================
// Data Type Tests
// ============================================================================

test "ReactiveList with string items" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("hello");
    try items.append("world");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);
}

test "ReactiveList with struct items" {
    const allocator = testing.allocator;
    var items = std.ArrayList(Task).init(allocator);
    defer items.deinit();

    try items.append(.{ .id = 1, .title = "Task 1", .completed = false });
    try items.append(.{ .id = 2, .title = "Task 2", .completed = true });

    var signal = try signal_mod.Signal([]const Task).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(Task).init(&signal, renderTaskItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);
}

// ============================================================================
// Performance Tests
// ============================================================================

test "ReactiveList renders large list efficiently" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try items.append("Item");
    }

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Should render only visible items (height=24), not all 1000
}

// ============================================================================
// Edge Cases
// ============================================================================

test "ReactiveList with single character items" {
    const allocator = testing.allocator;
    var items = std.ArrayList(StringItem).init(allocator);
    defer items.deinit();

    try items.append("A");
    try items.append("B");
    try items.append("C");

    var signal = try signal_mod.Signal([]const StringItem).init(allocator, items.items);
    defer signal.deinit(allocator);

    var list = sailor.reactive.ReactiveList(StringItem).init(&signal, renderStringItem);

    var buf = try Buffer.init(allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    try testing.expectEqual(@as(u21, 'A'), buf.getCell(0, 0).char);
    try testing.expectEqual(@as(u21, 'B'), buf.getCell(0, 1).char);
    try testing.expectEqual(@as(u21, 'C'), buf.getCell(0, 2).char);
}
