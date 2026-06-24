const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const MiniMap = tui.widgets.MiniMap;

// ============================================================================
// INIT & DEFAULTS (6 tests)
// ============================================================================

test "MiniMap init returns empty lines" {
    const widget = MiniMap.init();
    try testing.expectEqual(@as(usize, 0), widget.lines.len);
}

test "MiniMap init returns viewport_top = 0" {
    const widget = MiniMap.init();
    try testing.expectEqual(@as(usize, 0), widget.viewport_top);
}

test "MiniMap init returns viewport_height = 10" {
    const widget = MiniMap.init();
    try testing.expectEqual(@as(usize, 10), widget.viewport_height);
}

test "MiniMap init returns default style with no color" {
    const widget = MiniMap.init();
    try testing.expect(widget.style.fg == null);
    try testing.expect(widget.style.bg == null);
}

test "MiniMap init returns highlight_char = '▌'" {
    const widget = MiniMap.init();
    try testing.expectEqual(@as(u21, '▌'), widget.highlight_char);
}

test "MiniMap init returns empty_char = ' '" {
    const widget = MiniMap.init();
    try testing.expectEqual(@as(u21, ' '), widget.empty_char);
}

// ============================================================================
// BUILDER API (9 tests — verify immutability)
// ============================================================================

test "MiniMap withLines returns new copy with lines set" {
    const widget1 = MiniMap.init();
    const lines = [_][]const u8{ "test", "content" };
    const widget2 = widget1.withLines(&lines);
    try testing.expectEqual(@as(usize, 2), widget2.lines.len);
    try testing.expectEqual(@as(usize, 0), widget1.lines.len);
}

test "MiniMap withViewportTop returns new copy" {
    const widget1 = MiniMap.init();
    const widget2 = widget1.withViewportTop(5);
    try testing.expectEqual(@as(usize, 5), widget2.viewport_top);
    try testing.expectEqual(@as(usize, 0), widget1.viewport_top);
}

test "MiniMap withViewportHeight returns new copy" {
    const widget1 = MiniMap.init();
    const widget2 = widget1.withViewportHeight(20);
    try testing.expectEqual(@as(usize, 20), widget2.viewport_height);
    try testing.expectEqual(@as(usize, 10), widget1.viewport_height);
}

test "MiniMap withStyle returns new copy" {
    const widget1 = MiniMap.init();
    const new_style = Style{ .fg = .red };
    const widget2 = widget1.withStyle(new_style);
    try testing.expectEqual(Color.red, widget2.style.fg.?);
    try testing.expect(widget1.style.fg == null);
}

test "MiniMap withViewportStyle returns new copy" {
    const widget1 = MiniMap.init();
    const new_style = Style{ .bg = .blue };
    const widget2 = widget1.withViewportStyle(new_style);
    try testing.expectEqual(Color.blue, widget2.viewport_style.bg.?);
    try testing.expect(widget1.viewport_style.bg == null);
}

test "MiniMap withHighlightChar returns new copy" {
    const widget1 = MiniMap.init();
    const widget2 = widget1.withHighlightChar('█');
    try testing.expectEqual(@as(u21, '█'), widget2.highlight_char);
    try testing.expectEqual(@as(u21, '▌'), widget1.highlight_char);
}

test "MiniMap withEmptyChar returns new copy" {
    const widget1 = MiniMap.init();
    const widget2 = widget1.withEmptyChar('·');
    try testing.expectEqual(@as(u21, '·'), widget2.empty_char);
    try testing.expectEqual(@as(u21, ' '), widget1.empty_char);
}

test "MiniMap withBlock returns new copy" {
    const widget1 = MiniMap.init();
    const block_val = Block{ .borders = .all };
    const widget2 = widget1.withBlock(block_val);
    try testing.expect(widget2.block != null);
    try testing.expect(widget1.block == null);
}

test "MiniMap builder original unchanged after withStyle" {
    const widget1 = MiniMap.init();
    const style1 = widget1.style;
    _ = widget1.withStyle(Style{ .fg = .green });
    try testing.expectEqual(style1.fg, widget1.style.fg);
}

// ============================================================================
// RENDER: ZERO/MINIMAL AREA (4 tests)
// ============================================================================

test "MiniMap render zero width does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "MiniMap render zero height does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "MiniMap render 1x1 area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"a"};
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
}

test "MiniMap render empty lines uses empty_char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // All rows should use empty_char (space)
    for (0..5) |y| {
        for (0..10) |x| {
            try testing.expectEqual(@as(u21, ' '), buf.getChar(@intCast(x), @intCast(y)));
        }
    }
}

// ============================================================================
// RENDER: BASIC CONTENT (8 tests)
// ============================================================================

test "MiniMap lines with content shows highlight_char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"test"};
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // First row has content, should show highlight_char
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
}

test "MiniMap all empty lines uses empty_char on all rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "", "", "" };
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // All rows should show empty_char
    for (0..5) |y| {
        try testing.expectEqual(@as(u21, ' '), buf.getChar(0, @intCast(y)));
    }
}

test "MiniMap single content line shows highlight_char in first row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"content"};
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // First row has content
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(1, 0));
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(2, 0));
}

test "MiniMap lines count == inner.height shows one line per row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // Row 0: line 0 (content)
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
    // Row 1: line 1 (content)
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 1));
    // Row 2: line 2 (content)
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 2));
}

test "MiniMap lines count > inner.height applies scaling" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d", "e", "f" };
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // scale = 2, so each row represents 2 lines
    // Row 0: lines 0-1
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
}

test "MiniMap lines count < inner.height shows content in first rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "x", "y" };
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // First 2 rows have content
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 1));
    // Remaining rows are empty
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 3));
}

test "MiniMap custom highlight_char appears in buffer" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"test"};
    widget = widget.withLines(&lines).withHighlightChar('█');
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, '█'), buf.getChar(0, 0));
}

test "MiniMap custom empty_char appears in buffer for empty lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{""};
    widget = widget.withLines(&lines).withEmptyChar('·');
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, '·'), buf.getChar(0, 0));
}

// ============================================================================
// RENDER: VIEWPORT (10 tests)
// ============================================================================

test "MiniMap viewport at top uses viewport_style on first rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d", "e" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(0)
        .withViewportHeight(2)
        .withViewportStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // First row(s) in viewport should have viewport_style (red)
    const cell0 = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.red, cell0.style.fg.?);
}

test "MiniMap viewport in middle highlights correct rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d", "e" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(2)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .green });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // Row 2 is in viewport (lines 2)
    const cell_row2 = buf.getConst(0, 2).?;
    try testing.expectEqual(Color.green, cell_row2.style.fg.?);
}

test "MiniMap viewport at bottom highlights last rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d", "e" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(3)
        .withViewportHeight(2)
        .withViewportStyle(Style{ .fg = .blue });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // Last rows should be in viewport
    const cell_row4 = buf.getConst(0, 4).?;
    try testing.expectEqual(Color.blue, cell_row4.style.fg.?);
}

test "MiniMap viewport_height = 0 means no rows highlighted" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(0)
        .withViewportHeight(0)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // No rows should have viewport_style (red), all should have base style (white)
    for (0..3) |y| {
        const cell = buf.getConst(0, @intCast(y)).?;
        try testing.expectEqual(Color.white, cell.style.fg.?);
    }
}

test "MiniMap viewport larger than total_lines highlights all rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(0)
        .withViewportHeight(100)
        .withViewportStyle(Style{ .fg = .yellow });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // All rows should be in viewport (yellow)
    for (0..2) |y| {
        const cell = buf.getConst(0, @intCast(y)).?;
        try testing.expectEqual(Color.yellow, cell.style.fg.?);
    }
}

test "MiniMap viewport_top beyond total_lines no viewport highlight" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(100)
        .withViewportHeight(10)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // No rows should have viewport_style, all white
    for (0..3) |y| {
        const cell = buf.getConst(0, @intCast(y)).?;
        try testing.expectEqual(Color.white, cell.style.fg.?);
    }
}

test "MiniMap viewport style applies to all cells in viewport row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(1)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .cyan });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // Row 1 (viewport): all cells should have cyan
    for (0..5) |x| {
        const cell = buf.getConst(@intCast(x), 1).?;
        try testing.expectEqual(Color.cyan, cell.style.fg.?);
    }
}

test "MiniMap non-viewport rows use base style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(1)
        .withViewportHeight(1)
        .withStyle(Style{ .fg = .green })
        .withViewportStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // Row 0 (not in viewport): green
    const cell0 = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.green, cell0.style.fg.?);
    // Row 2 (not in viewport): green
    const cell2 = buf.getConst(0, 2).?;
    try testing.expectEqual(Color.green, cell2.style.fg.?);
}

test "MiniMap viewport covers entire widget uses viewport_style everywhere" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(0)
        .withViewportHeight(3)
        .withViewportStyle(Style{ .fg = .magenta });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // All rows in viewport
    for (0..3) |y| {
        const cell = buf.getConst(0, @intCast(y)).?;
        try testing.expectEqual(Color.magenta, cell.style.fg.?);
    }
}

test "MiniMap viewport exactly covers 1 row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(1)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 4 };
    widget.render(&buf, area);

    // Only row 1 should be in viewport (white)
    const cell1 = buf.getConst(0, 1).?;
    try testing.expectEqual(Color.white, cell1.style.fg.?);
}

// ============================================================================
// RENDER: SCALING (6 tests)
// ============================================================================

test "MiniMap 10 lines in 5-row widget scale equals 2" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" };
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // scale = 2: each row represents 2 lines
    // Row 0: lines 0-1 (both have content)
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
}

test "MiniMap 100 lines in 10-row widget scale equals 10" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    var lines_buf: [100][]const u8 = undefined;
    for (0..100) |i| {
        lines_buf[i] = "x";
    }
    widget = widget.withLines(&lines_buf);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    widget.render(&buf, area);

    // All rows should have content
    for (0..10) |y| {
        try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, @intCast(y)));
    }
}

test "MiniMap scale calculation is (total_lines + height - 1) / height" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    var lines_buf: [90][]const u8 = undefined;
    for (0..90) |i| {
        lines_buf[i] = "x";
    }
    widget = widget.withLines(&lines_buf);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    widget.render(&buf, area);

    // scale = (90 + 10 - 1) / 10 = 99 / 10 = 9
    // Each row represents ~9 lines
    for (0..10) |y| {
        try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, @intCast(y)));
    }
}

test "MiniMap scale applied to viewport detection" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d", "e", "f" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(2)
        .withViewportHeight(2)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // scale = 2: row 0 covers lines 0-1, row 1 covers lines 2-3, row 2 covers lines 4-5
    // viewport covers lines 2-3
    // so row 1 should be red (in viewport), others white
    const cell0 = buf.getConst(0, 0).?;
    const cell1 = buf.getConst(0, 1).?;
    const cell2 = buf.getConst(0, 2).?;
    try testing.expectEqual(Color.white, cell0.style.fg.?);
    try testing.expectEqual(Color.red, cell1.style.fg.?);
    try testing.expectEqual(Color.white, cell2.style.fg.?);
}

test "MiniMap first row after viewport uses base style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d", "e" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(0)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // Row 1 is after viewport
    const cell = buf.getConst(0, 1).?;
    try testing.expectEqual(Color.white, cell.style.fg.?);
}

test "MiniMap empty lines within scale range uses empty_char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "", "", "x", "x" };
    widget = widget.withLines(&lines).withEmptyChar('·');
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 2 };
    widget.render(&buf, area);

    // Row 0: lines 0-1 (both empty) → empty_char
    try testing.expectEqual(@as(u21, '·'), buf.getChar(0, 0));
    // Row 1: lines 2-3 (both have content) → highlight_char
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 1));
}

// ============================================================================
// RENDER: BLOCK BORDER (4 tests)
// ============================================================================

test "MiniMap block border renders at area edges" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"a"};
    widget = widget.withLines(&lines).withBlock(Block{ .borders = .all });
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Border should be at corners (not space)
    try testing.expect(buf.getChar(0, 0) != ' ');
    try testing.expect(buf.getChar(9, 0) != ' ');
    try testing.expect(buf.getChar(0, 4) != ' ');
    try testing.expect(buf.getChar(9, 4) != ' ');
}

test "MiniMap content renders inside inner area with block" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"a"};
    widget = widget.withLines(&lines).withBlock(Block{ .borders = .all });
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Content should be at (x=1, y=1) for inner area
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(1, 1));
}

test "MiniMap zero-size inner area with block does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"a"};
    widget = widget.withLines(&lines).withBlock(Block{ .borders = .all });
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    widget.render(&buf, area);

    // Should not crash, border should still render
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "MiniMap block with title renders title" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"content"};
    var block = Block{ .borders = .all };
    block.title = "Title";
    widget = widget.withLines(&lines).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    widget.render(&buf, area);

    // Border should render
    try testing.expect(buf.getChar(0, 0) != ' ');
}

// ============================================================================
// RENDER: STYLE (5 tests)
// ============================================================================

test "MiniMap viewport_style applied to cells in viewport rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(1)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .green, .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // Row 1 cells should have green fg and bold
    const cell = buf.getConst(0, 1).?;
    try testing.expectEqual(Color.green, cell.style.fg.?);
    try testing.expect(cell.style.bold);
}

test "MiniMap base style applied to cells outside viewport" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(1)
        .withViewportHeight(1)
        .withStyle(Style{ .fg = .blue });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // Row 0 (not in viewport): blue
    const cell = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.blue, cell.style.fg.?);
}

test "MiniMap row with content in viewport uses viewport_style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "x", "y", "z" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(0)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // Row 0 in viewport: red (even though it has content)
    const cell = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.red, cell.style.fg.?);
}

test "MiniMap row with content not in viewport uses base style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "x", "y", "z" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(1)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .green });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };
    widget.render(&buf, area);

    // Row 0 not in viewport: green
    const cell0 = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.green, cell0.style.fg.?);
}

test "MiniMap style on empty rows uses correct style based on viewport" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"", "", "", ""};
    widget = widget
        .withLines(&lines)
        .withViewportTop(1)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 4 };
    widget.render(&buf, area);

    // Row 1 in viewport, empty line: should use viewport_style (red)
    const cell_vp = buf.getConst(0, 1).?;
    try testing.expectEqual(Color.red, cell_vp.style.fg.?);
    // Row 0 not in viewport, empty line: should use base style (white)
    const cell_base = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.white, cell_base.style.fg.?);
}

// ============================================================================
// RENDER: EDGE CASES (6 tests)
// ============================================================================

test "MiniMap all lines non-empty shows highlight_char on all rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b", "c", "d" };
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 4 };
    widget.render(&buf, area);

    // All rows have content
    for (0..4) |y| {
        try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, @intCast(y)));
    }
}

test "MiniMap some empty lines within scale range shows empty_char for those rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "x", "", "y", "" };
    widget = widget.withLines(&lines).withEmptyChar('·');
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 2 };
    widget.render(&buf, area);

    // scale = 2
    // Row 0: lines 0-1 (one empty, one not) → has content → highlight_char
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
    // Row 1: lines 2-3 (one empty, one not) → has content → highlight_char
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 1));
}

test "MiniMap viewport_top beyond total_lines does not highlight" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{ "a", "b" };
    widget = widget
        .withLines(&lines)
        .withViewportTop(1000)
        .withViewportHeight(10)
        .withViewportStyle(Style{ .fg = .red })
        .withStyle(Style{ .fg = .white });
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // No viewport highlight, all white
    for (0..5) |y| {
        const cell = buf.getConst(0, @intCast(y)).?;
        try testing.expect(cell.style.fg == null or cell.style.fg.? == Color.white);
    }
}

test "MiniMap 1 line large widget height shows content in first row only" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"x"};
    widget = widget.withLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 20 };
    widget.render(&buf, area);

    // First row has content
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 0));
    // Rest are empty
    for (1..20) |y| {
        try testing.expectEqual(@as(u21, ' '), buf.getChar(0, @intCast(y)));
    }
}

test "MiniMap 1 line content in last position shows highlight_char in correct row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    var lines_buf: [20][]const u8 = undefined;
    for (0..19) |i| {
        lines_buf[i] = "";
    }
    lines_buf[19] = "x";
    widget = widget.withLines(&lines_buf);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    widget.render(&buf, area);

    // Last row should show content
    try testing.expectEqual(@as(u21, '▌'), buf.getChar(0, 9));
}

test "MiniMap very wide area all columns in row get same char and style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    var widget = MiniMap.init();
    const lines = [_][]const u8{"content"};
    widget = widget
        .withLines(&lines)
        .withViewportTop(0)
        .withViewportHeight(1)
        .withViewportStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 3 };
    widget.render(&buf, area);

    // First row: all columns should have same char (highlight_char) and style (red)
    for (0..50) |x| {
        const cell = buf.getConst(@intCast(x), 0).?;
        try testing.expectEqual(@as(u21, '▌'), cell.char);
        try testing.expectEqual(Color.red, cell.style.fg.?);
    }
}
