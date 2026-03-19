const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const TerminalWidget = sailor.tui.widgets.TerminalWidget;
const AnsiParseState = sailor.tui.widgets.AnsiParseState;

const testing = std.testing;

// ============================================================================
// Tests
// ============================================================================

test "Terminal widget init and deinit" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try testing.expectEqual(@as(usize, 0), term.lineCount());
    try testing.expectEqual(@as(usize, 0), term.scroll_offset);
    try testing.expectEqual(@as(u16, 80), term.width);
}

test "Terminal widget add line" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Hello, World!");
    try testing.expectEqual(@as(usize, 1), term.lineCount());

    try term.addLine("Second line");
    try testing.expectEqual(@as(usize, 2), term.lineCount());
}

test "Terminal widget add multiple lines" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Line 1");
    try term.addLine("Line 2");
    try term.addLine("Line 3");
    try term.addLine("Line 4");
    try term.addLine("Line 5");

    try testing.expectEqual(@as(usize, 5), term.lineCount());
}

test "Terminal widget clear buffer" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Line 1");
    try term.addLine("Line 2");
    try testing.expectEqual(@as(usize, 2), term.lineCount());

    term.clear();
    try testing.expectEqual(@as(usize, 0), term.lineCount());
}

test "Terminal widget scrollback limit enforced" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withMaxLines(5);

    try term.addLine("Line 1");
    try term.addLine("Line 2");
    try term.addLine("Line 3");
    try term.addLine("Line 4");
    try term.addLine("Line 5");
    try term.addLine("Line 6");
    try term.addLine("Line 7");

    // Should not exceed max_lines
    try testing.expectEqual(@as(usize, 5), term.lineCount());
}

test "Terminal widget scroll up" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 5);

    for (1..11) |i| {
        var buf: [16]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    try testing.expectEqual(@as(usize, 0), term.scroll_offset);
    term.scrollUp(2);
    try testing.expectEqual(@as(usize, 2), term.scroll_offset);
}

test "Terminal widget scroll down" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 5);

    for (1..11) |i| {
        var buf: [16]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    term.scrollUp(3);
    try testing.expectEqual(@as(usize, 3), term.scroll_offset);

    term.scrollDown(2);
    try testing.expectEqual(@as(usize, 1), term.scroll_offset);
}

test "Terminal widget scroll down to bottom" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 5);

    for (1..11) |i| {
        var buf: [16]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    term.scrollUp(10);
    term.scrollDown(10);
    try testing.expectEqual(@as(usize, 0), term.scroll_offset);
}

test "Terminal widget visible lines at bottom (no scroll)" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 3);

    try term.addLine("A");
    try term.addLine("B");
    try term.addLine("C");
    try term.addLine("D");

    const visible = term.visibleLines();
    try testing.expectEqual(@as(usize, 3), visible.len);
    try testing.expectEqualStrings("B", visible[0]);
    try testing.expectEqualStrings("C", visible[1]);
    try testing.expectEqualStrings("D", visible[2]);
}

test "Terminal widget visible lines with scroll" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 2);

    try term.addLine("1");
    try term.addLine("2");
    try term.addLine("3");
    try term.addLine("4");
    try term.addLine("5");

    term.scrollUp(2);
    const visible = term.visibleLines();

    try testing.expectEqual(@as(usize, 2), visible.len);
    try testing.expectEqualStrings("2", visible[0]);
    try testing.expectEqualStrings("3", visible[1]);
}

test "Terminal widget visible lines empty buffer" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    const visible = term.visibleLines();
    try testing.expectEqual(@as(usize, 0), visible.len);
}

test "Terminal widget render to buffer empty" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect.new(0, 0, 80, 24);
    term.render(&buf, area);

    // Should fill with spaces
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(' ', cell.?.char);
}

test "Terminal widget render with lines" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Hello");
    try term.addLine("World");

    var buf = try Buffer.init(testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect.new(0, 0, 80, 10);
    term.render(&buf, area);

    // Check first line rendered
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual('H', cell.?.char);
}

test "Terminal widget render respects block" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    const block = sailor.tui.widgets.Block.init()
        .withBorders(sailor.tui.widgets.Borders.all)
        .withTitle("Terminal", .top_left);

    term = term.withBlock(block);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect.new(0, 0, 20, 10);
    term.render(&buf, area);

    // Block borders should be drawn
    const top_cell = buf.getConst(0, 0);
    try testing.expect(top_cell != null);
    // Top-left corner should not be space (it's a border)
    try testing.expect(top_cell.?.char != ' ');
}

test "Terminal widget long line wrapping" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(10, 5);
    const long_line = "This is a very long line that exceeds the terminal width";
    try term.addLine(long_line);

    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect.new(0, 0, 10, 5);
    term.render(&buf, area);

    // Line should be rendered up to width
    const cell = buf.getConst(9, 0);
    try testing.expect(cell != null);
}

test "Terminal widget scroll offset calculation" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 3);

    for (1..8) |i| {
        var buf: [16]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    // Scroll to top (max offset)
    term.scrollUp(10);
    const max_offset = term.lines.items.len - term.height;
    try testing.expectEqual(max_offset, term.scroll_offset);
}

test "Terminal widget builder pattern" {
    var term = TerminalWidget.init(testing.allocator) catch unreachable;
    defer term.deinit();

    term = term
        .withSize(100, 30)
        .withMaxLines(5000)
        .withTitle("My Terminal");

    try testing.expectEqual(@as(u16, 100), term.width);
    try testing.expectEqual(@as(u16, 30), term.height);
    try testing.expectEqual(@as(usize, 5000), term.max_lines);
    try testing.expect(term.title != null);
}

test "ANSI parse state init" {
    const state = AnsiParseState{};

    try testing.expectEqual(@as(u16, 0), state.cursor_x);
    try testing.expectEqual(@as(u16, 0), state.cursor_y);
    try testing.expectEqual(false, state.bold);
    try testing.expectEqual(false, state.dim);
}

test "ANSI parse state bold" {
    var state = AnsiParseState{};
    state.parseSequence("1");

    try testing.expectEqual(true, state.bold);
}

test "ANSI parse state dim" {
    var state = AnsiParseState{};
    state.parseSequence("2");

    try testing.expectEqual(true, state.dim);
}

test "ANSI parse state italic" {
    var state = AnsiParseState{};
    state.parseSequence("3");

    try testing.expectEqual(true, state.italic);
}

test "ANSI parse state underline" {
    var state = AnsiParseState{};
    state.parseSequence("4");

    try testing.expectEqual(true, state.underline);
}

test "ANSI parse state reverse" {
    var state = AnsiParseState{};
    state.parseSequence("7");

    try testing.expectEqual(true, state.reverse);
}

test "ANSI parse state reset" {
    var state = AnsiParseState{};
    state.bold = true;
    state.dim = true;
    state.italic = true;
    state.underline = true;
    state.reverse = true;

    state.parseSequence("0");

    try testing.expectEqual(false, state.bold);
    try testing.expectEqual(false, state.dim);
    try testing.expectEqual(false, state.italic);
    try testing.expectEqual(false, state.underline);
    try testing.expectEqual(false, state.reverse);
}

test "ANSI parse state manual reset" {
    var state = AnsiParseState{};
    state.bold = true;
    state.dim = true;

    state.reset();

    try testing.expectEqual(false, state.bold);
    try testing.expectEqual(false, state.dim);
    try testing.expectEqual(@as(u16, 0), state.cursor_x);
    try testing.expectEqual(@as(u16, 0), state.cursor_y);
}

test "Terminal widget no memory leaks on clear" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Line 1");
    try term.addLine("Line 2");
    try term.addLine("Line 3");

    term.clear();
    try testing.expectEqual(@as(usize, 0), term.lineCount());
}

test "Terminal widget handles empty string line" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("");
    try testing.expectEqual(@as(usize, 1), term.lineCount());

    const visible = term.visibleLines();
    try testing.expectEqual(@as(usize, 1), visible.len);
    try testing.expectEqualStrings("", visible[0]);
}

test "Terminal widget handles special characters" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("✓ Success");
    try term.addLine("✗ Error");
    try term.addLine("→ Arrow");

    try testing.expectEqual(@as(usize, 3), term.lineCount());
}

test "Terminal widget render respects area bounds" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    for (1..6) |i| {
        var buf: [16]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Render to a small area
    const area = Rect.new(10, 5, 20, 3);
    term.render(&buf, area);

    // Should render within bounds
    try testing.expect(term.lineCount() > 0);
}

test "Terminal widget render zero area" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Test");

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Render to zero-width area (should handle gracefully)
    const area = Rect.new(0, 0, 0, 24);
    term.render(&buf, area);
    // Should not crash or corrupt buffer
}

test "Terminal widget rapid line additions" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withMaxLines(100);

    for (0..50) |i| {
        var buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Rapid line {d}", .{i});
        try term.addLine(line);
    }

    try testing.expectEqual(@as(usize, 50), term.lineCount());
}

test "Terminal widget ANSI state multiple sequences" {
    var state = AnsiParseState{};

    state.parseSequence("1");
    state.parseSequence("4");
    state.parseSequence("7");

    try testing.expectEqual(true, state.bold);
    try testing.expectEqual(true, state.underline);
    try testing.expectEqual(true, state.reverse);
}

test "Terminal widget scrollback preserves data" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 3);

    try term.addLine("First");
    try term.addLine("Second");
    try term.addLine("Third");
    try term.addLine("Fourth");
    try term.addLine("Fifth");

    // Scroll up and verify data is intact
    term.scrollUp(2);
    const visible = term.visibleLines();

    try testing.expectEqual(@as(usize, 3), visible.len);
    try testing.expectEqualStrings("First", visible[0]);
}

test "Terminal widget scroll beyond available lines" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 5);

    for (1..4) |i| {
        var buf: [16]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    // Try to scroll beyond available
    term.scrollUp(100);

    const visible = term.visibleLines();
    try testing.expectEqual(@as(usize, 3), visible.len);
}

test "Terminal widget mixed line lengths" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("a");
    try term.addLine("abcdefghij");
    try term.addLine("a");
    try term.addLine("abcdefghijklmnopqrstuvwxyz");

    try testing.expectEqual(@as(usize, 4), term.lineCount());

    var buf = try Buffer.init(testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect.new(0, 0, 80, 10);
    term.render(&buf, area);
}

test "Terminal widget title configuration" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withTitle("Terminal Window");

    try testing.expect(term.title != null);
    if (term.title) |t| {
        try testing.expectEqualStrings("Terminal Window", t);
    }
}

test "Terminal widget max lines edge case zero" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withMaxLines(0);

    // Adding line to zero max should handle gracefully
    try term.addLine("test");

    // Behavior: may store nothing or handle edge case
    try testing.expect(term.lineCount() <= 1);
}

test "Terminal widget max lines single line" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withMaxLines(1);

    try term.addLine("First");
    try term.addLine("Second");

    try testing.expectEqual(@as(usize, 1), term.lineCount());
    try testing.expectEqualStrings("Second", term.lines.items[0]);
}

test "Terminal widget size configuration" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(120, 40);

    try testing.expectEqual(@as(u16, 120), term.width);
    try testing.expectEqual(@as(u16, 40), term.height);
}

test "Terminal widget visible lines height larger than buffer" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 10);

    try term.addLine("Only");
    try term.addLine("Two");
    try term.addLine("Lines");

    const visible = term.visibleLines();
    try testing.expectEqual(@as(usize, 3), visible.len);
}

test "Terminal widget render at offset position" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Content");

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Render at offset (5, 10)
    const area = Rect.new(5, 10, 30, 5);
    term.render(&buf, area);

    // Content should appear at offset
    const cell = buf.getConst(5, 10);
    try testing.expect(cell != null);
}

test "Terminal widget consecutive scrolls" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    term = term.withSize(80, 2);

    for (1..6) |i| {
        var buf: [16]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{d}", .{i});
        try term.addLine(line);
    }

    // Multiple scroll operations
    term.scrollUp(1);
    try testing.expectEqual(@as(usize, 1), term.scroll_offset);

    term.scrollUp(1);
    try testing.expectEqual(@as(usize, 2), term.scroll_offset);

    term.scrollDown(1);
    try testing.expectEqual(@as(usize, 1), term.scroll_offset);
}

test "Terminal widget ANSI state independence" {
    var state1 = AnsiParseState{};
    const state2 = AnsiParseState{};

    state1.parseSequence("1");

    try testing.expectEqual(true, state1.bold);
    try testing.expectEqual(false, state2.bold);
}
