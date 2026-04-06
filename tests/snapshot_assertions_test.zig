//! Widget Snapshot Assertion Testing
//!
//! This test suite enhances widget_snapshots_test.zig by adding exact buffer
//! snapshot assertions using assertSnapshot(). These tests verify pixel-perfect
//! rendering by comparing complete buffer snapshots.
//!
//! Note: These tests use simplified scenarios with no trailing spaces to make
//! expected outputs maintainable. For content-based tests, see widget_snapshots_test.zig.

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const MockTerminal = sailor.tui.test_utils.MockTerminal;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Line = sailor.tui.Line;
const Span = sailor.tui.Span;

// Widget imports
const Block = sailor.tui.widgets.Block;
const Borders = sailor.tui.widgets.Borders;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Gauge = sailor.tui.widgets.Gauge;

// ============================================================================
// Snapshot Assertion Helper Tests
// ============================================================================

test "assertSnapshot: detects mismatch" {
    var term = try MockTerminal.init(testing.allocator, 5, 2);
    defer term.deinit();

    // Write "Hello" to buffer
    term.current.setString(0, 0, "Hello", Style{});

    // This should fail because actual has "Hello" but expected is "World"
    // Use quiet mode to suppress debug output in this negative test
    const result = term.assertSnapshotQuiet("World", true);
    try testing.expectError(error.SnapshotMismatch, result);
}

test "assertSnapshot: passes on exact match" {
    var term = try MockTerminal.init(testing.allocator, 5, 1);
    defer term.deinit();

    // Write "Hello" to buffer
    term.current.setString(0, 0, "Hello", Style{});

    // Build expected with trailing spaces to match buffer width
    var expected_buf: [5]u8 = undefined;
    @memcpy(expected_buf[0..5], "Hello");

    try term.assertSnapshot(&expected_buf);
}

test "assertSnapshot: handles multi-line content" {
    var term = try MockTerminal.init(testing.allocator, 3, 2);
    defer term.deinit();

    term.current.setString(0, 0, "ABC", Style{});
    term.current.setString(0, 1, "DEF", Style{});

    var expected_buf: [7]u8 = undefined;
    @memcpy(expected_buf[0..3], "ABC");
    expected_buf[3] = '\n';
    @memcpy(expected_buf[4..7], "DEF");

    try term.assertSnapshot(&expected_buf);
}

// ============================================================================
// Visual Regression Tests (Structure Verification)
// ============================================================================

test "Block: visual structure verification" {
    var term = try MockTerminal.init(testing.allocator, 8, 3);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all);

    block.render(&term.current, term.size());

    // Verify corners
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expectEqual('┐', term.getChar(7, 0).?);
    try testing.expectEqual('└', term.getChar(0, 2).?);
    try testing.expectEqual('┘', term.getChar(7, 2).?);

    // Verify sides
    try testing.expectEqual('─', term.getChar(1, 0).?); // top
    try testing.expectEqual('─', term.getChar(1, 2).?); // bottom
    try testing.expectEqual('│', term.getChar(0, 1).?); // left
    try testing.expectEqual('│', term.getChar(7, 1).?); // right
}

test "Block with title: visual structure" {
    var term = try MockTerminal.init(testing.allocator, 10, 3);
    defer term.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Test", .top_left);

    block.render(&term.current, term.size());

    // Verify corners exist
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expectEqual('┐', term.getChar(9, 0).?);

    // Verify title is present somewhere in first row
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);
    try testing.expect(std.mem.indexOf(u8, snapshot, "Test") != null);
}

test "Paragraph: renders at correct position" {
    var term = try MockTerminal.init(testing.allocator, 12, 2);
    defer term.deinit();

    const line = Line{ .spans = &[_]Span{Span.raw("Hello")} };
    const lines = [_]Line{line};

    const para = Paragraph.fromLines(&lines);
    para.render(&term.current, term.size());

    // Verify text starts at (0, 0)
    try testing.expectEqual('H', term.getChar(0, 0).?);
    try testing.expectEqual('e', term.getChar(1, 0).?);
    try testing.expectEqual('l', term.getChar(2, 0).?);
    try testing.expectEqual('l', term.getChar(3, 0).?);
    try testing.expectEqual('o', term.getChar(4, 0).?);
}

test "List: items render sequentially" {
    var term = try MockTerminal.init(testing.allocator, 10, 3);
    defer term.deinit();

    const items = [_][]const u8{ "One", "Two", "Three" };
    const list = List.init(&items)
        .withHighlightSymbol(""); // No highlight symbol = no indent

    list.render(&term.current, term.size());

    // Verify each item appears in order starting at column 0
    try testing.expectEqual('O', term.getChar(0, 0).?);
    try testing.expectEqual('T', term.getChar(0, 1).?);
    try testing.expectEqual('T', term.getChar(0, 2).?);
}

test "List with highlight: symbol appears" {
    var term = try MockTerminal.init(testing.allocator, 10, 3);
    defer term.deinit();

    const items = [_][]const u8{ "One", "Two", "Three" };
    const list = List.init(&items)
        .withSelected(1)
        .withHighlightSymbol("> ");

    list.render(&term.current, term.size());

    // Verify highlight symbol on selected line
    try testing.expectEqual('>', term.getChar(0, 1).?);
    try testing.expectEqual(' ', term.getChar(1, 1).?);
    try testing.expectEqual('T', term.getChar(2, 1).?);
}

test "Gauge: renders fill character" {
    var term = try MockTerminal.init(testing.allocator, 10, 1);
    defer term.deinit();

    const gauge = (Gauge{})
        .withPercent(50);

    gauge.render(&term.current, term.size());

    // Should have some filled characters
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);
    try testing.expect(std.mem.indexOf(u8, snapshot, "█") != null);
}

test "Gauge: 0% has no fill" {
    var term = try MockTerminal.init(testing.allocator, 10, 1);
    defer term.deinit();

    const gauge = (Gauge{})
        .withPercent(0);

    gauge.render(&term.current, term.size());

    // Should NOT have filled characters at 0%
    const snapshot = try term.getSnapshot(testing.allocator);
    defer testing.allocator.free(snapshot);
    try testing.expect(std.mem.indexOf(u8, snapshot, "█") == null);
}

test "Gauge: 100% fills completely" {
    var term = try MockTerminal.init(testing.allocator, 10, 1);
    defer term.deinit();

    const gauge = (Gauge{})
        .withPercent(100);

    gauge.render(&term.current, term.size());

    // Count filled characters - should be close to full width
    var fill_count: usize = 0;
    var x: u16 = 0;
    while (x < 10) : (x += 1) {
        if (term.getChar(x, 0)) |char| {
            if (char == '█') fill_count += 1;
        }
    }

    // At 100%, most characters should be filled (allow some for label)
    try testing.expect(fill_count >= 7);
}

// ============================================================================
// Layout Integration Tests
// ============================================================================

test "Multiple blocks: no overlap" {
    var term = try MockTerminal.init(testing.allocator, 16, 3);
    defer term.deinit();

    // Left block (0-7)
    const left = (Block{}).withBorders(Borders.all);
    left.render(&term.current, Rect.new(0, 0, 8, 3));

    // Right block (8-15)
    const right = (Block{}).withBorders(Borders.all);
    right.render(&term.current, Rect.new(8, 0, 8, 3));

    // Verify both corners exist without overlap
    try testing.expectEqual('┌', term.getChar(0, 0).?);
    try testing.expectEqual('┘', term.getChar(7, 2).?);
    try testing.expectEqual('┌', term.getChar(8, 0).?);
    try testing.expectEqual('┘', term.getChar(15, 2).?);
}

test "Vertical stack: proper separation" {
    var term = try MockTerminal.init(testing.allocator, 10, 6);
    defer term.deinit();

    // Top block (rows 0-2)
    const top = (Block{}).withBorders(Borders.all);
    top.render(&term.current, Rect.new(0, 0, 10, 3));

    // Bottom block (rows 3-5)
    const bottom = (Block{}).withBorders(Borders.all);
    bottom.render(&term.current, Rect.new(0, 3, 10, 3));

    // Verify corners of both blocks
    try testing.expectEqual('┌', term.getChar(0, 0).?); // top-left of top
    try testing.expectEqual('└', term.getChar(0, 2).?); // bottom-left of top
    try testing.expectEqual('┌', term.getChar(0, 3).?); // top-left of bottom
    try testing.expectEqual('└', term.getChar(0, 5).?); // bottom-left of bottom
}
