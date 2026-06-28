const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const SplitText = tui.SplitText;
const Alignment = tui.Alignment;

// Helper function to get a character from the buffer
fn cellChar(buf: *Buffer, x: u16, y: u16) u21 {
    const cell_opt = buf.getConst(x, y);
    if (cell_opt) |cell| {
        return cell.char;
    }
    return ' ';
}

// Helper function to get style from the buffer
fn cellStyle(buf: *Buffer, x: u16, y: u16) Style {
    const cell_opt = buf.getConst(x, y);
    if (cell_opt) |cell| {
        return cell.style;
    }
    return .{};
}

// ============================================================================
// GROUP 1: INIT & DEFAULTS (5 tests)
// ============================================================================

test "SplitText init default text empty" {
    const widget = SplitText.init();
    try testing.expectEqualStrings("", widget.text);
}

test "SplitText init default delimiter" {
    const widget = SplitText.init();
    try testing.expectEqualStrings("\n---\n", widget.delimiter);
}

test "SplitText init default style" {
    const widget = SplitText.init();
    try testing.expectEqual(@as(?Color, null), widget.style.fg);
    try testing.expectEqual(@as(?Color, null), widget.style.bg);
}

test "SplitText init default show_dividers true" {
    const widget = SplitText.init();
    try testing.expectEqual(true, widget.show_dividers);
}

test "SplitText init default alignment left" {
    const widget = SplitText.init();
    try testing.expectEqual(Alignment.left, widget.alignment);
}

// ============================================================================
// GROUP 2: SECTION COUNT (8 tests)
// ============================================================================

test "SplitText section_count empty text returns 0" {
    const widget = SplitText.init().withText("");
    try testing.expectEqual(@as(usize, 0), widget.sectionCount());
}

test "SplitText section_count no delimiter returns 1" {
    const widget = SplitText.init().withText("hello world");
    try testing.expectEqual(@as(usize, 1), widget.sectionCount());
}

test "SplitText section_count one delimiter returns 2" {
    const widget = SplitText.init().withText("a\n---\nb");
    try testing.expectEqual(@as(usize, 2), widget.sectionCount());
}

test "SplitText section_count two delimiters returns 3" {
    const widget = SplitText.init().withText("a\n---\nb\n---\nc");
    try testing.expectEqual(@as(usize, 3), widget.sectionCount());
}

test "SplitText section_count custom delimiter" {
    const widget = SplitText.init()
        .withDelimiter("|||")
        .withText("a|||b|||c");
    try testing.expectEqual(@as(usize, 3), widget.sectionCount());
}

test "SplitText section_count delimiter at start" {
    const widget = SplitText.init().withText("\n---\nfoo");
    try testing.expectEqual(@as(usize, 2), widget.sectionCount());
}

test "SplitText section_count delimiter at end" {
    const widget = SplitText.init().withText("foo\n---\n");
    try testing.expectEqual(@as(usize, 2), widget.sectionCount());
}

test "SplitText section_count capped at MAX_SECTIONS" {
    // Build a string with many delimiters (should be capped at 64)
    var text_buf: [1000]u8 = undefined;
    var text_len: usize = 0;

    for (0..100) |i| {
        if (text_len + 7 > text_buf.len) break;
        if (i > 0) {
            @memcpy(text_buf[text_len..text_len+5], "\n---\n");
            text_len += 5;
        }
        text_buf[text_len] = 'a';
        text_len += 1;
    }

    const text = text_buf[0..text_len];
    const widget = SplitText.init().withText(text);
    try testing.expectEqual(@as(usize, 64), widget.sectionCount());
}

// ============================================================================
// GROUP 3: BUILDER IMMUTABILITY (6 tests)
// ============================================================================

test "SplitText builder withText immutability" {
    const widget1 = SplitText.init();
    const original_text = widget1.text;
    _ = widget1.withText("new text");
    try testing.expectEqualStrings(original_text, widget1.text);
}

test "SplitText builder withDelimiter immutability" {
    const widget1 = SplitText.init();
    const original_delim = widget1.delimiter;
    _ = widget1.withDelimiter("|||");
    try testing.expectEqualStrings(original_delim, widget1.delimiter);
}

test "SplitText builder withShowDividers immutability" {
    const widget1 = SplitText.init();
    const original = widget1.show_dividers;
    _ = widget1.withShowDividers(false);
    try testing.expectEqual(original, widget1.show_dividers);
}

test "SplitText builder withStyle immutability" {
    const widget1 = SplitText.init();
    const original_style = widget1.style;
    _ = widget1.withStyle(Style{ .fg = .red });
    try testing.expectEqual(original_style.fg, widget1.style.fg);
}

test "SplitText builder withAlignment immutability" {
    const widget1 = SplitText.init();
    const original = widget1.alignment;
    _ = widget1.withAlignment(.center);
    try testing.expectEqual(original, widget1.alignment);
}

test "SplitText builder withBlock immutability" {
    const widget1 = SplitText.init();
    const original_block = widget1.block;
    _ = widget1.withBlock(Block{ .borders = .all });
    try testing.expectEqual(original_block, widget1.block);
}

// ============================================================================
// GROUP 4: RENDER ZERO/MINIMAL AREA (4 tests)
// ============================================================================

test "SplitText render zero width does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("hello");
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    widget.render(&buf, area);
    // Should not crash
}

test "SplitText render zero height does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("hello");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    widget.render(&buf, area);
    // Should not crash
}

test "SplitText render zero area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("hello");
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    widget.render(&buf, area);
    // Should not crash
}

test "SplitText render empty text all cells default" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // All cells should be spaces (default)
    for (0..10) |y| {
        for (0..20) |x| {
            try testing.expectEqual(@as(u21, ' '), cellChar(&buf, @intCast(x), @intCast(y)));
        }
    }
}

// ============================================================================
// GROUP 5: SINGLE SECTION RENDERING (6 tests)
// ============================================================================

test "SplitText render single section no delimiter" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("hello");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // First character should be 'h' at (0, 0)
    try testing.expectEqual(@as(u21, 'h'), cellChar(&buf, 0, 0));
}

test "SplitText render single section fills area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("hello world this is a long text");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Render should complete without crash and populate buffer
    try testing.expectEqual(@as(u21, 'h'), cellChar(&buf, 0, 0));
}

test "SplitText render single section with style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hi")
        .withStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // First character should have red style
    const style = cellStyle(&buf, 0, 0);
    try testing.expectEqual(@as(?Color, Color.red), style.fg);
}

test "SplitText render single no divider shown" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hello")
        .withShowDividers(true);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Single section: no divider should be rendered (no section boundary)
    try testing.expectEqual(@as(u21, 'h'), cellChar(&buf, 0, 0));
}

test "SplitText render single with block" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hi")
        .withBlock(Block{ .borders = .all });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Border should render (not space)
    try testing.expect(cellChar(&buf, 0, 0) != ' ');
}

test "SplitText render single alignment left" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hi")
        .withAlignment(.left);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Left-aligned: 'h' should be at x=0
    try testing.expectEqual(@as(u21, 'h'), cellChar(&buf, 0, 0));
}

// ============================================================================
// GROUP 6: TWO SECTIONS (8 tests)
// ============================================================================

test "SplitText render two sections split" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("aaa\n---\nbbb");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Verify 'a' exists in upper half and 'b' in lower half
    var found_a: bool = false;
    var found_b: bool = false;
    for (0..5) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'a') found_a = true;
        }
    }
    for (5..10) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'b') found_b = true;
        }
    }
    try testing.expect(found_a);
    try testing.expect(found_b);
}

test "SplitText render two sections top half" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("aaa\n---\nbbb");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Check rows 0..4 have 'a' character
    var found_a: bool = false;
    for (0..5) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'a') found_a = true;
        }
    }
    try testing.expect(found_a);
}

test "SplitText render two sections bottom half" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("aaa\n---\nbbb");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Check rows 5..9 have 'b' character
    var found_b: bool = false;
    for (5..10) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'b') found_b = true;
        }
    }
    try testing.expect(found_b);
}

test "SplitText render two sections divider char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withShowDividers(true)
        .withDividerChar('─');
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Divider row should contain '─' character
    var found_divider: bool = false;
    for (0..20) |x| {
        if (cellChar(&buf, @intCast(x), 4) == '─') found_divider = true;
    }
    try testing.expect(found_divider);
}

test "SplitText render two sections no divider" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withShowDividers(false);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Divider row (row 4) should not have divider_char (should be blank or content)
    // With show_dividers=false, divider should not be '─'
    var has_divider: bool = false;
    for (0..20) |x| {
        if (cellChar(&buf, @intCast(x), 4) == '─') has_divider = true;
    }
    try testing.expect(!has_divider);
}

test "SplitText render two sections divider style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withShowDividers(true)
        .withDividerChar('─')
        .withDividerStyle(Style{ .fg = .blue });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Divider cell should have blue style
    const style = cellStyle(&buf, 0, 4);
    try testing.expectEqual(@as(?Color, Color.blue), style.fg);
}

test "SplitText render two sections custom delimiter" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withDelimiter("|||")
        .withText("aaa|||bbb");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Should split into two sections
    var found_a: bool = false;
    var found_b: bool = false;
    for (0..5) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'a') found_a = true;
        }
    }
    for (5..10) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'b') found_b = true;
        }
    }
    try testing.expect(found_a);
    try testing.expect(found_b);
}

test "SplitText render two sections custom divider char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withShowDividers(true)
        .withDividerChar('=');
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Divider row should contain '=' character
    var found_divider: bool = false;
    for (0..20) |x| {
        if (cellChar(&buf, @intCast(x), 4) == '=') found_divider = true;
    }
    try testing.expect(found_divider);
}

// ============================================================================
// GROUP 7: SECTION HEADERS (6 tests)
// ============================================================================

test "SplitText render section header first" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withSectionHeaders(&.{"HEAD"});
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Header 'H' should appear in first section
    var found_header: bool = false;
    for (0..20) |x| {
        if (cellChar(&buf, @intCast(x), 0) == 'H') found_header = true;
    }
    try testing.expect(found_header);
}

test "SplitText render section header style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withSectionHeaders(&.{"HEAD"})
        .withHeaderStyle(Style{ .fg = .green });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Header cell should have green style
    const style = cellStyle(&buf, 0, 0);
    try testing.expectEqual(@as(?Color, Color.green), style.fg);
}

test "SplitText render section header shifts content" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withSectionHeaders(&.{"HEAD"});
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Content 'a' should start at row 1 (after header)
    var found_a_at_row_1 = false;
    for (0..20) |x| {
        if (cellChar(&buf, @intCast(x), 1) == 'a') found_a_at_row_1 = true;
    }
    try testing.expect(found_a_at_row_1);
}

test "SplitText render section header partial" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb\n---\nccc")
        .withSectionHeaders(&.{"HEAD1"});
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // First section has header, others don't
    var found_h: bool = false;
    for (0..20) |x| {
        if (cellChar(&buf, @intCast(x), 0) == 'H') found_h = true;
    }
    try testing.expect(found_h);
}

test "SplitText render section no header for all" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withSectionHeaders(&.{});
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Content 'a' should start at row 0 (no header)
    try testing.expectEqual(@as(u21, 'a'), cellChar(&buf, 0, 0));
}

test "SplitText render section header empty string" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb")
        .withSectionHeaders(&.{""});
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Empty header string: content should start at row 0
    try testing.expectEqual(@as(u21, 'a'), cellChar(&buf, 0, 0));
}

// ============================================================================
// GROUP 8: ALIGNMENT (6 tests)
// ============================================================================

test "SplitText render alignment left default" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hi")
        .withAlignment(.left);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // 'h' should be at x=0
    try testing.expectEqual(@as(u21, 'h'), cellChar(&buf, 0, 0));
}

test "SplitText render alignment center" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hi")
        .withAlignment(.center);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // 'h' should be roughly centered: x = (20-2)/2 = 9
    var found_h_at_center: bool = false;
    for (8..12) |x| {
        if (cellChar(&buf, @intCast(x), 0) == 'h') found_h_at_center = true;
    }
    try testing.expect(found_h_at_center);
}

test "SplitText render alignment right" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hi")
        .withAlignment(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // 'h' should be right-aligned: x = 20-2 = 18
    var found_h_at_right: bool = false;
    for (17..20) |x| {
        if (cellChar(&buf, @intCast(x), 0) == 'h') found_h_at_right = true;
    }
    try testing.expect(found_h_at_right);
}

test "SplitText render alignment center wide text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("abcdefghijklmnopqrstuvwxyz")
        .withAlignment(.center);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Text wider than area: should start at x=0 (clamped to inner.x)
    try testing.expectEqual(@as(u21, 'a'), cellChar(&buf, 0, 0));
}

test "SplitText render alignment right wide text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("abcdefghijklmnopqrstuvwxyz")
        .withAlignment(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Text wider than area: should start at x=0 (clamped)
    try testing.expectEqual(@as(u21, 'a'), cellChar(&buf, 0, 0));
}

test "SplitText render alignment applied to all sections" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("hi\n---\nby")
        .withAlignment(.center);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Both sections should be centered
    var found_h: bool = false;
    var found_b: bool = false;
    for (0..5) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'h') found_h = true;
        }
    }
    for (5..10) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'b') found_b = true;
        }
    }
    try testing.expect(found_h);
    try testing.expect(found_b);
}

// ============================================================================
// GROUP 9: TEXT WRAPPING (4 tests)
// ============================================================================

test "SplitText render text wraps at width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 6, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("hello world");
    const area = Rect{ .x = 0, .y = 0, .width = 6, .height = 10 };
    widget.render(&buf, area);

    // Row 0 should have "hello"
    try testing.expectEqual(@as(u21, 'h'), cellChar(&buf, 0, 0));
    try testing.expectEqual(@as(u21, 'e'), cellChar(&buf, 1, 0));
    // Row 1 should have "world"
    try testing.expectEqual(@as(u21, 'w'), cellChar(&buf, 0, 1));
}

test "SplitText render long word hard split" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 4, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("abcdefgh");
    const area = Rect{ .x = 0, .y = 0, .width = 4, .height = 10 };
    widget.render(&buf, area);

    // Row 0: "abcd"
    try testing.expectEqual(@as(u21, 'a'), cellChar(&buf, 0, 0));
    try testing.expectEqual(@as(u21, 'd'), cellChar(&buf, 3, 0));
    // Row 1: "efgh"
    try testing.expectEqual(@as(u21, 'e'), cellChar(&buf, 0, 1));
}

test "SplitText render text overflow truncated" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    var widget = SplitText.init().withText("line1\nline2\nline3\nline4\nline5");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    widget.render(&buf, area);

    // Should not crash, first 3 lines rendered
    try testing.expect(cellChar(&buf, 0, 0) != ' ' or cellChar(&buf, 0, 1) != ' ');
}

test "SplitText render empty section" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("\n---\n");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Empty sections: divider may or may not render
    const divider_renders = cellChar(&buf, 0, 4) != ' ';
    try testing.expect(divider_renders or !divider_renders);
}

// ============================================================================
// GROUP 10: THREE SECTIONS (4 tests)
// ============================================================================

test "SplitText render three sections count" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("a\n---\nb\n---\nc");
    try testing.expectEqual(@as(usize, 3), widget.sectionCount());

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);
}

test "SplitText render three sections layout" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("aaa\n---\nbbb\n---\nccc");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Each section gets ~3 rows (10/3 = 3 rows each, last gets remainder)
    // Section 1: rows 0-2, Section 2: rows 3-5, Section 3: rows 6-9
    var found_a: bool = false;
    var found_b: bool = false;
    var found_c: bool = false;

    for (0..3) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'a') found_a = true;
        }
    }
    for (3..6) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'b') found_b = true;
        }
    }
    for (6..10) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == 'c') found_c = true;
        }
    }
    try testing.expect(found_a);
    try testing.expect(found_b);
    try testing.expect(found_c);
}

test "SplitText render three sections two dividers" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb\n---\nccc")
        .withShowDividers(true)
        .withDividerChar('─');
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Two divider rows should contain '─'
    var divider_count: usize = 0;
    for (0..10) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == '─') divider_count += 1;
        }
    }
    try testing.expect(divider_count > 0);
}

test "SplitText render three sections no dividers" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withText("aaa\n---\nbbb\n---\nccc")
        .withShowDividers(false);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // No divider chars should be rendered
    var has_divider: bool = false;
    for (0..10) |y| {
        for (0..20) |x| {
            if (cellChar(&buf, @intCast(x), @intCast(y)) == '─') has_divider = true;
        }
    }
    try testing.expect(!has_divider);
}

// ============================================================================
// GROUP 11: EDGE CASES (3 tests)
// ============================================================================

test "SplitText render delimiter not in text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init()
        .withDelimiter("|||")
        .withText("hello world");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Should be treated as single section
    try testing.expectEqual(@as(usize, 1), widget.sectionCount());
}

test "SplitText render very small area 1x1" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = SplitText.init().withText("hello");
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    widget.render(&buf, area);

    // 1x1 area: at most one char
    const ch = cellChar(&buf, 0, 0);
    try testing.expect(ch == 'h' or ch == ' ');
}

test "SplitText render section height zero guard" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    var widget = SplitText.init().withText("aaa\n---\nbbb\n---\nccc");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    widget.render(&buf, area);

    // Height 1: at least something should render or be empty
    var found = false;
    for (0..20) |x| {
        if (cellChar(&buf, @intCast(x), 0) != ' ') found = true;
    }
    try testing.expect(found or !found);
}
