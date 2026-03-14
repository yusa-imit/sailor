//! Multi-cursor editing widget tests
//!
//! Tests for v1.13.0 Multi-Cursor Editing feature.
//! Tests the MultiCursor widget that provides Sublime Text / VSCode-style multi-cursor editing.
//!
//! CRITICAL: These tests are designed to FAIL initially (TDD Red phase).
//! The implementation (src/tui/widgets/multicursor.zig) does not exist yet.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;

// This import will fail until implementation exists (expected TDD red state)
const MultiCursor = sailor.tui.widgets.MultiCursor;
const Position = MultiCursor.Position;
const Cursor = MultiCursor.Cursor;

// ============================================================================
// Initialization Tests
// ============================================================================

test "multicursor init creates empty cursor list" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try testing.expectEqual(@as(usize, 0), mc.cursors.items.len);
    try testing.expect(mc.primary_cursor == null);
}

test "multicursor init with text buffer" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");
    try testing.expectEqual(@as(usize, 3), mc.lines.items.len);
}

// ============================================================================
// Cursor Management Tests
// ============================================================================

test "multicursor add single cursor" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello world");
    try mc.addCursor(.{ .line = 0, .col = 5 });

    try testing.expectEqual(@as(usize, 1), mc.cursors.items.len);
    try testing.expectEqual(@as(usize, 0), mc.cursors.items[0].pos.line);
    try testing.expectEqual(@as(usize, 5), mc.cursors.items[0].pos.col);
}

test "multicursor add multiple cursors" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 1, .col = 0 });
    try mc.addCursor(.{ .line = 2, .col = 0 });

    try testing.expectEqual(@as(usize, 3), mc.cursors.items.len);
    try testing.expectEqual(@as(usize, 1), mc.cursors.items[1].pos.line);
}

test "multicursor add duplicate cursor merges" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 5 });
    try mc.addCursor(.{ .line = 0, .col = 5 }); // duplicate

    // Should only have one cursor after merging
    try testing.expectEqual(@as(usize, 1), mc.cursors.items.len);
}

test "multicursor remove cursor" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 1, .col = 0 });

    try mc.removeCursor(0);
    try testing.expectEqual(@as(usize, 1), mc.cursors.items.len);
    try testing.expectEqual(@as(usize, 1), mc.cursors.items[0].pos.line);
}

test "multicursor remove all cursors" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 0, .col = 5 });

    mc.clearCursors();
    try testing.expectEqual(@as(usize, 0), mc.cursors.items.len);
}

test "multicursor add cursor at invalid position fails" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");

    // Line out of bounds
    const result = mc.addCursor(.{ .line = 10, .col = 0 });
    try testing.expectError(error.InvalidPosition, result);
}

test "multicursor add cursor at invalid column fails" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");

    // Column out of bounds (max is 5 for "hello")
    const result = mc.addCursor(.{ .line = 0, .col = 100 });
    try testing.expectError(error.InvalidPosition, result);
}

// ============================================================================
// Primary Cursor Tests
// ============================================================================

test "multicursor first added cursor becomes primary" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 0 });

    try testing.expect(mc.primary_cursor != null);
    try testing.expectEqual(@as(usize, 0), mc.primary_cursor.?);
}

test "multicursor set primary cursor" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 1, .col = 0 });

    try mc.setPrimaryCursor(1);
    try testing.expectEqual(@as(usize, 1), mc.primary_cursor.?);
}

test "multicursor set primary cursor out of range fails" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 0 });

    const result = mc.setPrimaryCursor(10);
    try testing.expectError(error.InvalidCursorIndex, result);
}

test "multicursor primary cursor removed updates index" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld\ntest");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 1, .col = 0 });
    try mc.addCursor(.{ .line = 2, .col = 0 });

    try mc.setPrimaryCursor(1);
    try mc.removeCursor(1);

    // Primary should shift or become null
    try testing.expect(mc.primary_cursor == null or mc.primary_cursor.? != 1);
}

// ============================================================================
// Text Insertion Tests
// ============================================================================

test "multicursor insertChar at all cursors" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 0, .col = 5 }); // end of "hello"
    try mc.addCursor(.{ .line = 1, .col = 5 }); // end of "world"

    try mc.insertChar('!');

    try testing.expectEqualStrings("hello!", mc.lines.items[0]);
    try testing.expectEqualStrings("world!", mc.lines.items[1]);

    // Cursors should have moved
    try testing.expectEqual(@as(usize, 6), mc.cursors.items[0].pos.col);
    try testing.expectEqual(@as(usize, 6), mc.cursors.items[1].pos.col);
}

test "multicursor insertChar with different positions" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("abc\ndef\nghi");
    try mc.addCursor(.{ .line = 0, .col = 1 }); // a_bc
    try mc.addCursor(.{ .line = 1, .col = 1 }); // d_ef
    try mc.addCursor(.{ .line = 2, .col = 1 }); // g_hi

    try mc.insertChar('X');

    try testing.expectEqualStrings("aXbc", mc.lines.items[0]);
    try testing.expectEqualStrings("dXef", mc.lines.items[1]);
    try testing.expectEqualStrings("gXhi", mc.lines.items[2]);
}

test "multicursor insertChar updates all cursors" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("test");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 0, .col = 2 }); // t_est

    try mc.insertChar('X');

    // First cursor: X at 0 -> "Xtest", cursor at 1
    // Second cursor was at 2, after first insert it shifts to 3, then inserts -> "XteXst", cursor at 4
    try testing.expectEqualStrings("XteXst", mc.lines.items[0]);
    try testing.expectEqual(@as(usize, 1), mc.cursors.items[0].pos.col);
    try testing.expectEqual(@as(usize, 4), mc.cursors.items[1].pos.col);
}

// ============================================================================
// Text Deletion Tests
// ============================================================================

test "multicursor deleteChar at all cursors" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello!\nworld!");
    try mc.addCursor(.{ .line = 0, .col = 6 }); // after !
    try mc.addCursor(.{ .line = 1, .col = 6 }); // after !

    try mc.deleteChar();

    try testing.expectEqualStrings("hello", mc.lines.items[0]);
    try testing.expectEqualStrings("world", mc.lines.items[1]);

    // Cursors should have moved back
    try testing.expectEqual(@as(usize, 5), mc.cursors.items[0].pos.col);
    try testing.expectEqual(@as(usize, 5), mc.cursors.items[1].pos.col);
}

test "multicursor deleteChar at beginning does nothing" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 0 });

    try mc.deleteChar();

    // Should not delete anything at col 0
    try testing.expectEqualStrings("hello", mc.lines.items[0]);
    try testing.expectEqual(@as(usize, 0), mc.cursors.items[0].pos.col);
}

test "multicursor deleteChar with multiple cursors on same line" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("abcdef");
    try mc.addCursor(.{ .line = 0, .col = 3 }); // abc_def
    try mc.addCursor(.{ .line = 0, .col = 6 }); // abcdef_

    try mc.deleteChar();

    // Delete 'c' at pos 3 and 'f' at pos 6
    // After first delete: "abdef", second cursor shifts from 6 to 5
    // After second delete: "abde"
    try testing.expectEqualStrings("abde", mc.lines.items[0]);
}

// ============================================================================
// Newline Insertion Tests
// ============================================================================

test "multicursor insertNewline at all cursors" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 0, .col = 5 });
    try mc.addCursor(.{ .line = 1, .col = 5 });

    try mc.insertNewline();

    // Should create new lines
    try testing.expect(mc.lines.items.len > 2);
    try testing.expectEqualStrings("hello", mc.lines.items[0]);
    try testing.expectEqualStrings("", mc.lines.items[1]); // empty line after newline
}

test "multicursor insertNewline splits line" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello world");
    try mc.addCursor(.{ .line = 0, .col = 5 }); // hello_ world

    try mc.insertNewline();

    try testing.expectEqual(@as(usize, 2), mc.lines.items.len);
    try testing.expectEqualStrings("hello", mc.lines.items[0]);
    try testing.expectEqualStrings(" world", mc.lines.items[1]);
    try testing.expectEqual(@as(usize, 1), mc.cursors.items[0].pos.line);
    try testing.expectEqual(@as(usize, 0), mc.cursors.items[0].pos.col);
}

// ============================================================================
// Cursor Merging Tests
// ============================================================================

test "multicursor merge overlapping cursors after insertion" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("test");
    try mc.addCursor(.{ .line = 0, .col = 2 });
    try mc.addCursor(.{ .line = 0, .col = 3 });

    // After inserting, if cursors end up at same position, they should merge
    try mc.insertChar('X');
    mc.mergeCursors();

    // Check that overlapping cursors were merged
    try testing.expect(mc.cursors.items.len <= 2);
}

test "multicursor merge cursors at same position" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 5 });
    try mc.addCursor(.{ .line = 0, .col = 5 });

    mc.mergeCursors();
    try testing.expectEqual(@as(usize, 1), mc.cursors.items.len);
}

test "multicursor no merge when positions different" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello world");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 0, .col = 6 });

    mc.mergeCursors();
    try testing.expectEqual(@as(usize, 2), mc.cursors.items.len);
}

// ============================================================================
// Column Mode Tests
// ============================================================================

test "multicursor add column mode cursors" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");

    // Add cursors at column 5 on all lines
    try mc.addColumnCursors(.{ .start_line = 0, .end_line = 2, .col = 5 });

    try testing.expectEqual(@as(usize, 3), mc.cursors.items.len);
    try testing.expectEqual(@as(usize, 0), mc.cursors.items[0].pos.line);
    try testing.expectEqual(@as(usize, 5), mc.cursors.items[0].pos.col);
    try testing.expectEqual(@as(usize, 1), mc.cursors.items[1].pos.line);
    try testing.expectEqual(@as(usize, 5), mc.cursors.items[1].pos.col);
    try testing.expectEqual(@as(usize, 2), mc.cursors.items[2].pos.line);
    try testing.expectEqual(@as(usize, 5), mc.cursors.items[2].pos.col);
}

test "multicursor column mode with varying line lengths" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("short\nthis is longer\nmed");

    // Add cursors at column 10 - should clamp to line length
    try mc.addColumnCursors(.{ .start_line = 0, .end_line = 2, .col = 10 });

    try testing.expectEqual(@as(usize, 3), mc.cursors.items.len);
    try testing.expectEqual(@as(usize, 5), mc.cursors.items[0].pos.col); // "short" ends at 5
    try testing.expectEqual(@as(usize, 10), mc.cursors.items[1].pos.col); // long enough
    try testing.expectEqual(@as(usize, 3), mc.cursors.items[2].pos.col); // "med" ends at 3
}

test "multicursor column mode with empty lines" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\n\nworld");

    try mc.addColumnCursors(.{ .start_line = 0, .end_line = 2, .col = 3 });

    try testing.expectEqual(@as(usize, 3), mc.cursors.items.len);
    try testing.expectEqual(@as(usize, 0), mc.cursors.items[1].pos.col); // empty line -> col 0
}

// ============================================================================
// Selection Range Tests
// ============================================================================

test "multicursor cursor with selection range" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello world");
    try mc.addCursor(.{ .line = 0, .col = 0 });

    mc.setSelection(0, .{ .line = 0, .col = 0 }, .{ .line = 0, .col = 5 });

    const cursor = mc.cursors.items[0];
    try testing.expect(cursor.selection != null);
    try testing.expect(!cursor.selection.?.isEmpty());
}

test "multicursor multiple cursors with independent selections" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("line one\nline two");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 1, .col = 0 });

    mc.setSelection(0, .{ .line = 0, .col = 0 }, .{ .line = 0, .col = 4 });
    mc.setSelection(1, .{ .line = 1, .col = 0 }, .{ .line = 1, .col = 4 });

    try testing.expect(mc.cursors.items[0].selection != null);
    try testing.expect(mc.cursors.items[1].selection != null);

    // Selections should be independent
    try testing.expectEqual(@as(usize, 0), mc.cursors.items[0].selection.?.start.line);
    try testing.expectEqual(@as(usize, 1), mc.cursors.items[1].selection.?.start.line);
}

test "multicursor clear selection for cursor" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    mc.setSelection(0, .{ .line = 0, .col = 0 }, .{ .line = 0, .col = 5 });

    mc.clearSelection(0);
    try testing.expect(mc.cursors.items[0].selection == null);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "multicursor empty buffer" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("");

    try testing.expectEqual(@as(usize, 1), mc.lines.items.len);
    try testing.expectEqualStrings("", mc.lines.items[0]);
}

test "multicursor operations on empty buffer" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("");
    try mc.addCursor(.{ .line = 0, .col = 0 });

    try mc.insertChar('a');
    try testing.expectEqualStrings("a", mc.lines.items[0]);
}

test "multicursor buffer with only newlines" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("\n\n\n");
    try testing.expectEqual(@as(usize, 4), mc.lines.items.len);

    try mc.addCursor(.{ .line = 1, .col = 0 });
    try mc.insertChar('X');
    try testing.expectEqualStrings("X", mc.lines.items[1]);
}

test "multicursor very long line" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    const long_line = "a" ** 10000;
    try mc.setText(long_line);

    try mc.addCursor(.{ .line = 0, .col = 5000 });
    try mc.insertChar('X');

    try testing.expectEqual(@as(usize, 10001), mc.lines.items[0].len);
}

test "multicursor many cursors performance" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    var text: std.ArrayList(u8) = .{};
    defer text.deinit(allocator);

    // Create 100 lines
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try text.appendSlice(allocator, "line\n");
    }

    try mc.setText(text.items);

    // Add 100 cursors
    i = 0;
    while (i < 100) : (i += 1) {
        try mc.addCursor(.{ .line = i, .col = 2 });
    }

    try testing.expectEqual(@as(usize, 100), mc.cursors.items.len);

    // Insert at all cursors
    try mc.insertChar('X');

    // All lines should have 'X' inserted
    try testing.expectEqualStrings("liXne", mc.lines.items[0]);
}

test "multicursor cursor at end of line boundary" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello");
    try mc.addCursor(.{ .line = 0, .col = 5 }); // at end

    try mc.insertChar('!');
    try testing.expectEqualStrings("hello!", mc.lines.items[0]);
}

test "multicursor delete at line boundaries" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 0, .col = 0 });

    // Delete at col 0 should do nothing
    try mc.deleteChar();
    try testing.expectEqualStrings("hello", mc.lines.items[0]);
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "multicursor no memory leaks with GPA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 1, .col = 0 });
    try mc.addCursor(.{ .line = 2, .col = 0 });

    try mc.insertChar('X');
    try mc.deleteChar();
    mc.mergeCursors();
}

test "multicursor deinit cleans up all allocations" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);

    try mc.setText("test line");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    mc.setSelection(0, .{ .line = 0, .col = 0 }, .{ .line = 0, .col = 4 });

    mc.deinit();
    // If this doesn't crash and test allocator doesn't report leaks, we're good
}

// ============================================================================
// Rendering Tests (Basic)
// ============================================================================

test "multicursor render with buffer" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 0, .col = 2 });
    try mc.addCursor(.{ .line = 1, .col = 2 });

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mc.render(&buffer, area);

    // Should render text with multiple cursor highlights
    // Cursors should be visible at (2, 0) and (2, 1)
}

test "multicursor render with selections highlighted" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello world");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    mc.setSelection(0, .{ .line = 0, .col = 0 }, .{ .line = 0, .col = 5 });

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mc.render(&buffer, area);

    // Selection should be highlighted
}

test "multicursor render distinguishes primary cursor" {
    const allocator = testing.allocator;
    var mc = try MultiCursor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try mc.addCursor(.{ .line = 1, .col = 0 });
    try mc.setPrimaryCursor(1);

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mc.render(&buffer, area);

    // Primary cursor should have different style
}
