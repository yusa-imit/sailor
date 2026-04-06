//! ChunkedBuffer widget tests
//!
//! Tests for v1.21.0 milestone — ChunkedBuffer widget for efficient large text rendering.
//! Focuses on lazy loading, scrolling (vertical/horizontal), wrapping, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;
const ChunkedBuffer = sailor.tui.widgets.ChunkedBuffer;

// ============================================================================
// Initialization Tests
// ============================================================================

test "ChunkedBuffer.init creates buffer with total line count" {
    const cb = ChunkedBuffer.init(1_000_000); // 1 million lines
    try testing.expectEqual(@as(usize, 1_000_000), cb.total_lines);
    try testing.expectEqual(@as(usize, 0), cb.line_offset);
    try testing.expectEqual(@as(usize, 0), cb.column_offset);
    try testing.expectEqual(@as(?Block, null), cb.block);
    try testing.expectEqual(false, cb.wrap);
}

test "ChunkedBuffer builder methods chain correctly" {
    const block = (Block{}).withBorders(.all);
    const style = Style{ .fg = .{ .indexed = 2 } };

    const cb = ChunkedBuffer.init(100)
        .withLineOffset(10)
        .withColumnOffset(5)
        .withBlock(block)
        .withTextStyle(style)
        .withWrap(true);

    try testing.expectEqual(@as(usize, 10), cb.line_offset);
    try testing.expectEqual(@as(usize, 5), cb.column_offset);
    try testing.expect(cb.block != null);
    try testing.expectEqual(true, cb.wrap);
}

// ============================================================================
// Basic Rendering Tests
// ============================================================================

test "ChunkedBuffer.render displays only visible lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const cb = ChunkedBuffer.init(100); // 100 total lines

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should call callback exactly 10 times (viewport height)
    try testing.expectEqual(@as(usize, 10), call_count);
}

test "ChunkedBuffer.render writes correct line content to buffer" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("Line {d}", .{line_index});
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Verify line 0 contains "Line 0"
    const line0 = buf.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "Line 0") != null);

    // Verify line 2 contains "Line 2"
    const line2 = buf.getLine(2, 0, 40);
    defer allocator.free(line2);
    try testing.expect(std.mem.indexOf(u8, line2, "Line 2") != null);
}

// ============================================================================
// Vertical Scrolling Tests
// ============================================================================

test "ChunkedBuffer.withLineOffset scrolls to different lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("Line {d}", .{line_index});
        }
    };

    // Scroll to line 50
    const cb = ChunkedBuffer.init(1000).withLineOffset(50);
    try cb.render(&buf, area, Ctx.callback, allocator);

    // First visible line should be line 50
    const line0 = buf.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "Line 50") != null);

    // Last visible line should be line 54
    const line4 = buf.getLine(4, 0, 40);
    defer allocator.free(line4);
    try testing.expect(std.mem.indexOf(u8, line4, "Line 54") != null);
}

test "ChunkedBuffer.withLineOffset clamps at boundaries" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    const Ctx = struct {
        var max_called: usize = 0;
        fn callback(line_index: usize, writer: anytype) !void {
            if (line_index > max_called) max_called = line_index;
            try writer.print("Line {d}", .{line_index});
        }
    };

    // Offset beyond total lines (only 20 lines total)
    const cb = ChunkedBuffer.init(20).withLineOffset(50);
    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should clamp to valid range — max line index should be < 20
    try testing.expect(Ctx.max_called < 20);
}

// ============================================================================
// Horizontal Scrolling Tests
// ============================================================================

test "ChunkedBuffer.withColumnOffset shifts text horizontally" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.writeAll("0123456789ABCDEFGHIJ"); // 20 chars
            _ = line_index;
        }
    };

    // Scroll horizontally by 10 columns
    const cb = ChunkedBuffer.init(10).withColumnOffset(10);
    try cb.render(&buf, area, Ctx.callback, allocator);

    // First visible character should be 'A' (index 10)
    const line0 = buf.getLine(0, 0, 20);
    defer allocator.free(line0);
    try testing.expect(std.mem.startsWith(u8, std.mem.trim(u8, line0, " "), "ABCDEFGHIJ"));
}

test "ChunkedBuffer.withColumnOffset handles wide characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 2);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 2 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            // Mix ASCII and wide chars (e.g., emoji, CJK)
            try writer.writeAll("Hello世界🌍Wide");
            _ = line_index;
        }
    };

    // Column offset should respect display width, not byte count
    const cb = ChunkedBuffer.init(10).withColumnOffset(5);
    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should not crash and render without malformed characters
    const line0 = buf.getLine(0, 0, 20);
    defer allocator.free(line0);
    try testing.expect(line0.len > 0); // Basic sanity check
}

// ============================================================================
// Large Dataset Tests (Memory Efficiency)
// ============================================================================

test "ChunkedBuffer.render handles millions of lines without loading all into memory" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    // 10 million lines
    const cb = ChunkedBuffer.init(10_000_000).withLineOffset(5_000_000);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("Log line {d:10}: some log message here", .{line_index});
        }
    };

    // Should complete without memory issues (only renders 24 lines)
    try cb.render(&buf, area, Ctx.callback, allocator);

    // Verify correct line is at viewport start
    const line0 = buf.getLine(0, 0, 80);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "5000000") != null);
}

test "ChunkedBuffer.render callback invoked exactly viewport height times" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 15);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    var invocation_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {}", .{line_index});
        }
    };
    Ctx.count = &invocation_count;

    const cb = ChunkedBuffer.init(1_000_000);
    try cb.render(&buf, area, Ctx.callback, allocator);

    try testing.expectEqual(@as(usize, 15), invocation_count);
}

// ============================================================================
// Block Integration Tests
// ============================================================================

test "ChunkedBuffer.withBlock renders with borders" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const block = (Block{}).withBorders(.all).withTitle("Log Viewer", .top_left);

    const cb = ChunkedBuffer.init(50).withBlock(block);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("Line {d}", .{line_index});
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Verify top-left corner has border character
    if (buf.get(0, 0)) |cell| {
        try testing.expect(cell.char == '┌');
    }

    // Verify title is rendered
    const line0 = buf.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "Log Viewer") != null);
}

test "ChunkedBuffer.withBlock reduces effective render area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const block = (Block{}).withBorders(.all);

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    const cb = ChunkedBuffer.init(100).withBlock(block);
    try cb.render(&buf, area, Ctx.callback, allocator);

    // With borders, inner height is 10 - 2 = 8
    try testing.expectEqual(@as(usize, 8), call_count);
}

// ============================================================================
// Text Wrapping Tests
// ============================================================================

test "ChunkedBuffer.withWrap wraps long lines within viewport width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            // Single long line (40 chars) should wrap into 2 lines (20 char width)
            try writer.writeAll("This is a very long line that should wrap at width boundary");
            _ = line_index;
        }
    };

    const cb = ChunkedBuffer.init(5).withWrap(true);
    try cb.render(&buf, area, Ctx.callback, allocator);

    // Line 0 should have "This is a very long"
    const line0 = buf.getLine(0, 0, 20);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "This is") != null);

    // Line 1 should have continuation (or next logical chunk)
    const line1 = buf.getLine(1, 0, 20);
    defer allocator.free(line1);
    try testing.expect(line1.len > 0); // Should have wrapped content
}

test "ChunkedBuffer without wrap truncates long lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 15, 3);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 3 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.writeAll("This is a very long line");
            _ = line_index;
        }
    };

    const cb = ChunkedBuffer.init(5).withWrap(false);
    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 15);
    defer allocator.free(line0);

    // Line should be truncated at width 15 (not wrapped)
    const trimmed = std.mem.trim(u8, line0, " ");
    try testing.expect(trimmed.len <= 15);
}

// ============================================================================
// Edge Cases Tests
// ============================================================================

test "ChunkedBuffer.render handles zero total lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            _ = line_index;
            _ = writer;
        }
    };
    Ctx.count = &call_count;

    const cb = ChunkedBuffer.init(0); // Zero lines
    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should not call callback
    try testing.expectEqual(@as(usize, 0), call_count);
}

test "ChunkedBuffer.render handles viewport larger than content" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    const cb = ChunkedBuffer.init(5); // Only 5 lines, viewport height 20
    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should only render 5 lines (not fill entire viewport)
    try testing.expectEqual(@as(usize, 5), call_count);
}

test "ChunkedBuffer.render handles empty area (width or height zero)" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            _ = line_index;
            _ = writer;
        }
    };
    Ctx.count = &call_count;

    // Zero height area
    const zero_height = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };
    const cb1 = ChunkedBuffer.init(100);
    try cb1.render(&buf, zero_height, Ctx.callback, allocator);
    try testing.expectEqual(@as(usize, 0), call_count);

    // Zero width area
    call_count = 0;
    const zero_width = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    const cb2 = ChunkedBuffer.init(100);
    try cb2.render(&buf, zero_width, Ctx.callback, allocator);
    try testing.expectEqual(@as(usize, 0), call_count);
}

// ============================================================================
// Callback Error Handling Tests
// ============================================================================

test "ChunkedBuffer.render propagates callback errors" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = writer;
            // Fail on line 5
            if (line_index == 5) return error.TestError;
        }
    };

    const cb = ChunkedBuffer.init(100);
    const result = cb.render(&buf, area, Ctx.callback, allocator);

    // Should propagate error from callback
    try testing.expectError(error.TestError, result);
}

test "ChunkedBuffer.render handles out-of-memory from callback" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            _ = writer;
            return error.OutOfMemory;
        }
    };

    const cb = ChunkedBuffer.init(100);
    const result = cb.render(&buf, area, Ctx.callback, allocator);

    try testing.expectError(error.OutOfMemory, result);
}

// ============================================================================
// Style Application Tests
// ============================================================================

test "ChunkedBuffer.withTextStyle applies style to rendered text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    const text_style = Style{ .fg = .{ .indexed = 3 }, .bold = true };

    const cb = ChunkedBuffer.init(10).withTextStyle(text_style);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("Line {d}", .{line_index});
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Verify first cell has the correct style
    if (buf.get(0, 0)) |cell| {
        try testing.expectEqual(Color{ .indexed = 3 }, cell.style.fg.?);
        try testing.expectEqual(true, cell.style.bold);
    }
}

// ============================================================================
// Integration: Scrolling + Wrapping + Block
// ============================================================================

test "ChunkedBuffer full integration: scroll + wrap + block" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 15);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    const block = (Block{}).withBorders(.all).withTitle("Logs", .top_center);
    const text_style = Style{ .fg = .{ .indexed = 7 } };

    const cb = ChunkedBuffer.init(1000)
        .withLineOffset(100)
        .withColumnOffset(5)
        .withBlock(block)
        .withTextStyle(text_style)
        .withWrap(true);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("[{d:5}] Log entry with some content", .{line_index});
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Verify border exists
    if (buf.get(0, 0)) |cell| {
        try testing.expect(cell.char == '┌');
    }

    // Verify title
    const line0 = buf.getLine(0, 0, 50);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "Logs") != null);

    // Verify content starts from line 100 (offset), inside border
    const line1 = buf.getLine(1, 1, 48); // Inside border
    defer allocator.free(line1);
    try testing.expect(std.mem.indexOf(u8, line1, "100") != null);
}

// ============================================================================
// Regression Tests (Common Pitfalls)
// ============================================================================

test "ChunkedBuffer does not render beyond buffer bounds" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    // Area larger than buffer — should clamp
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.writeAll("X" ** 200); // Very long line
            _ = line_index;
        }
    };

    const cb = ChunkedBuffer.init(100);
    // Should not crash
    try cb.render(&buf, area, Ctx.callback, allocator);
}

test "ChunkedBuffer handles line_offset at exact total_lines boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("{d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    // Offset exactly at boundary (20 lines total, offset 20)
    const cb = ChunkedBuffer.init(20).withLineOffset(20);
    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should not call callback (no lines beyond boundary)
    try testing.expectEqual(@as(usize, 0), call_count);
}
