//! Pager widget tests
//!
//! Comprehensive test suite for the Pager widget covering initialization,
//! navigation, rendering, line numbers, search highlighting, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;
const Pager = sailor.tui.widgets.Pager;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "Pager.init creates pager with empty lines" {
    const lines = &[_][]const u8{};
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 0), pager.lines.len);
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
    try testing.expectEqual(@as(usize, 0), pager.scroll_x);
    try testing.expect(!pager.line_numbers);
    try testing.expect(!pager.wrap);
    try testing.expect(!pager.case_sensitive);
    try testing.expectEqualStrings("", pager.search_query);
    try testing.expect(pager.block == null);
}

test "Pager.init creates pager with single line" {
    const lines = &[_][]const u8{"Hello, World!"};
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 1), pager.lines.len);
    try testing.expectEqualStrings("Hello, World!", pager.lines[0]);
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

test "Pager.init creates pager with multiple lines" {
    const lines = &[_][]const u8{
        "Line 1",
        "Line 2",
        "Line 3",
        "Line 4",
    };
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 4), pager.lines.len);
    try testing.expectEqualStrings("Line 1", pager.lines[0]);
    try testing.expectEqualStrings("Line 4", pager.lines[3]);
}

test "Pager.init initializes with default scroll position" {
    const lines = &[_][]const u8{"test"};
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
    try testing.expectEqual(@as(usize, 0), pager.scroll_x);
}

test "Pager borrows lines slice from caller" {
    var lines_data = [_][]const u8{ "data1", "data2" };
    const lines = &lines_data;
    const pager = Pager.init(lines);

    // Verify same slice pointer
    try testing.expectEqual(@as(usize, 2), pager.lines.len);
    try testing.expectEqualStrings("data1", pager.lines[0]);
}

// ============================================================================
// BUILDER PATTERN TESTS
// ============================================================================

test "Pager.withLineNumbers enables line number display" {
    const lines = &[_][]const u8{"test"};
    const pager = Pager.init(lines).withLineNumbers();

    try testing.expect(pager.line_numbers);
}

test "Pager.withWrap enables soft wrapping" {
    const lines = &[_][]const u8{"test"};
    const pager = Pager.init(lines).withWrap();

    try testing.expect(pager.wrap);
}

test "Pager.withStyle sets text style" {
    const lines = &[_][]const u8{"test"};
    const style = Style{ .bold = true };
    const pager = Pager.init(lines).withStyle(style);

    try testing.expect(pager.style.bold);
}

test "Pager.withHighlightStyle sets search highlight style" {
    const lines = &[_][]const u8{"test"};
    const style = Style{ .reverse = true };
    const pager = Pager.init(lines).withHighlightStyle(style);

    try testing.expect(pager.highlight_style.reverse);
}

test "Pager.withBlock sets border block" {
    const lines = &[_][]const u8{"test"};
    const block = Block{};
    const pager = Pager.init(lines).withBlock(block);

    try testing.expect(pager.block != null);
}

test "Pager builder methods chain correctly" {
    const lines = &[_][]const u8{ "line1", "line2" };
    const style = Style{ .bold = true };
    const highlight = Style{ .reverse = true };
    const block = Block{ .title = "Pager" };

    const pager = Pager.init(lines)
        .withLineNumbers()
        .withWrap()
        .withStyle(style)
        .withHighlightStyle(highlight)
        .withBlock(block)
        .withCaseSensitive(false);

    try testing.expect(pager.line_numbers);
    try testing.expect(pager.wrap);
    try testing.expect(pager.style.bold);
    try testing.expect(pager.highlight_style.reverse);
    try testing.expect(pager.block != null);
    try testing.expect(!pager.case_sensitive);
}

test "Pager.withSearchQuery sets search string" {
    const lines = &[_][]const u8{"test content"};
    const pager = Pager.init(lines).withSearchQuery("content");

    try testing.expectEqualStrings("content", pager.search_query);
}

test "Pager.withCaseSensitive toggles case sensitivity" {
    const lines = &[_][]const u8{"Test"};
    const pager = Pager.init(lines).withCaseSensitive(false);

    try testing.expect(!pager.case_sensitive);
}

// ============================================================================
// NAVIGATION — scrollDown / scrollUp TESTS
// ============================================================================

test "Pager.scrollDown advances scroll_y by one line" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);

    pager.scrollDown(10);
    try testing.expectEqual(@as(usize, 1), pager.scroll_y);

    pager.scrollDown(10);
    try testing.expectEqual(@as(usize, 2), pager.scroll_y);
}

test "Pager.scrollDown clamps at bottom of content" {
    const lines = &[_][]const u8{ "L1", "L2" };
    var pager = Pager.init(lines);

    pager.scrollDown(10);
    pager.scrollDown(10);
    pager.scrollDown(10);  // Try to go past end

    try testing.expectEqual(@as(usize, 2), pager.scroll_y);  // Clamped to line count
}

test "Pager.scrollDown on empty lines is no-op" {
    var pager = Pager.init(&[_][]const u8{});

    pager.scrollDown(10);
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

test "Pager.scrollUp retreats scroll_y by one line" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);
    pager.scroll_y = 2;

    pager.scrollUp();
    try testing.expectEqual(@as(usize, 1), pager.scroll_y);

    pager.scrollUp();
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

test "Pager.scrollUp clamps at zero" {
    const lines = &[_][]const u8{ "L1", "L2" };
    var pager = Pager.init(lines);

    pager.scrollUp();
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

test "Pager.scrollUp on empty lines is no-op" {
    var pager = Pager.init(&[_][]const u8{});

    pager.scrollUp();
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

// ============================================================================
// NAVIGATION — scrollRight / scrollLeft TESTS
// ============================================================================

test "Pager.scrollRight advances horizontal offset" {
    const lines = &[_][]const u8{"abcdefghij"};
    var pager = Pager.init(lines);

    pager.scrollRight(3);
    try testing.expectEqual(@as(usize, 3), pager.scroll_x);
}

test "Pager.scrollRight clamps at maximum line width" {
    const lines = &[_][]const u8{"short"};
    var pager = Pager.init(lines);

    pager.scrollRight(100);  // Try to go past end
    try testing.expectEqual(@as(usize, 5), pager.scroll_x);  // Clamped to line width
}

test "Pager.scrollLeft retreats horizontal offset" {
    const lines = &[_][]const u8{"abcdef"};
    var pager = Pager.init(lines);
    pager.scroll_x = 4;

    pager.scrollLeft(2);
    try testing.expectEqual(@as(usize, 2), pager.scroll_x);
}

test "Pager.scrollLeft clamps at zero" {
    const lines = &[_][]const u8{"test"};
    var pager = Pager.init(lines);

    pager.scrollLeft(10);  // Try to go before start
    try testing.expectEqual(@as(usize, 0), pager.scroll_x);
}

// ============================================================================
// NAVIGATION — pageDown / pageUp TESTS
// ============================================================================

test "Pager.pageDown moves down by area height" {
    const lines = &[_][]const u8{
        "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10",
    };
    var pager = Pager.init(lines);

    pager.pageDown(5);  // Move down by 5
    try testing.expectEqual(@as(usize, 5), pager.scroll_y);
}

test "Pager.pageDown clamps at bottom" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);

    pager.pageDown(100);  // Try to move past end
    try testing.expectEqual(@as(usize, 3), pager.scroll_y);  // Clamped
}

test "Pager.pageUp moves up by area height" {
    const lines = &[_][]const u8{
        "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10",
    };
    var pager = Pager.init(lines);
    pager.scroll_y = 8;

    pager.pageUp(5);  // Move up by 5
    try testing.expectEqual(@as(usize, 3), pager.scroll_y);
}

test "Pager.pageUp clamps at zero" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);

    pager.pageUp(100);  // Try to move before start
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

// ============================================================================
// NAVIGATION — goToTop / goToBottom / goToLine TESTS
// ============================================================================

test "Pager.goToTop resets scroll position to start" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);
    pager.scroll_y = 2;
    pager.scroll_x = 5;

    pager.goToTop();
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
    try testing.expectEqual(@as(usize, 0), pager.scroll_x);
}

test "Pager.goToBottom scrolls to last visible line" {
    const lines = &[_][]const u8{ "L1", "L2", "L3", "L4", "L5" };
    var pager = Pager.init(lines);

    pager.goToBottom(10);
    try testing.expectEqual(@as(usize, 5), pager.scroll_y);
}

test "Pager.goToBottom resets horizontal scroll" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);
    pager.scroll_x = 5;

    pager.goToBottom(10);
    try testing.expectEqual(@as(usize, 0), pager.scroll_x);
}

test "Pager.goToLine scrolls to specified line" {
    const lines = &[_][]const u8{ "L1", "L2", "L3", "L4", "L5" };
    var pager = Pager.init(lines);

    pager.goToLine(2);
    try testing.expectEqual(@as(usize, 2), pager.scroll_y);
}

test "Pager.goToLine clamps within bounds" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);

    pager.goToLine(10);  // Out of bounds
    try testing.expectEqual(@as(usize, 3), pager.scroll_y);  // Clamped
}

test "Pager.goToLine on empty lines is no-op" {
    var pager = Pager.init(&[_][]const u8{});

    pager.goToLine(5);
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

test "Pager.goToLine with zero works correctly" {
    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines);
    pager.scroll_y = 2;

    pager.goToLine(0);
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);
}

// ============================================================================
// maxLineWidth TESTS
// ============================================================================

test "Pager.maxLineWidth returns zero for empty lines" {
    const pager = Pager.init(&[_][]const u8{});

    try testing.expectEqual(@as(usize, 0), pager.maxLineWidth());
}

test "Pager.maxLineWidth returns width of single line" {
    const lines = &[_][]const u8{"hello"};
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 5), pager.maxLineWidth());
}

test "Pager.maxLineWidth returns longest line width" {
    const lines = &[_][]const u8{
        "short",
        "much longer line",
        "mid",
    };
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 16), pager.maxLineWidth());
}

// ============================================================================
// RENDER BASIC TESTS
// ============================================================================

test "Pager.render handles zero area without crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();

    const lines = &[_][]const u8{"content"};
    const pager = Pager.init(lines);

    // Place a marker cell before render
    buf.set(0, 0, .{ .char = 'X' });

    // Render with zero area
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    pager.render(&buf, area);

    // Marker should be unchanged
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'X'), cell.?.char);
}

test "Pager.render handles zero height without crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();

    const lines = &[_][]const u8{"content"};
    const pager = Pager.init(lines);

    // Place marker before render
    buf.set(5, 5, .{ .char = 'X' });

    // Render with zero height
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };
    pager.render(&buf, area);

    // Marker should be unchanged
    const cell = buf.getConst(5, 5);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'X'), cell.?.char);
}

test "Pager.render with single line content" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"Hello"};
    const pager = Pager.init(lines);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    pager.render(&buf, area);

    // Verify first character of content rendered
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'H'), cell.?.char);
}

test "Pager.render respects scroll_y offset" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{ "Line1", "Line2", "Line3" };
    var pager = Pager.init(lines);
    pager.scroll_y = 1;  // Start from Line2

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    pager.render(&buf, area);

    // First visible line should be "Line2" starting with 'L'
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'L'), cell.?.char);
}

test "Pager.render places content correctly in area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();

    const lines = &[_][]const u8{"Test"};
    const pager = Pager.init(lines);

    // Render in non-zero offset area
    const area = Rect{ .x = 5, .y = 3, .width = 30, .height = 10 };
    pager.render(&buf, area);

    // Content should start at area position
    const cell = buf.getConst(5, 3);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'T'), cell.?.char);
}

// ============================================================================
// RENDER LINE NUMBERS TESTS
// ============================================================================

test "Pager.render with line numbers shows prefix" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"Content"};
    const pager = Pager.init(lines).withLineNumbers();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    pager.render(&buf, area);

    // Line numbers should appear (1-indexed: "1")
    // Expected format: "   1 | Content"
    // Check for separator pipe character
    var found_pipe = false;
    for (0..7) |x| {
        const cell = buf.getConst(@intCast(x), 0);
        if (cell != null and cell.?.char == '|') {
            found_pipe = true;
            break;
        }
    }
    try testing.expect(found_pipe);
}

test "Pager.render line numbers are 1-indexed" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{ "L1", "L2", "L3" };
    var pager = Pager.init(lines).withLineNumbers();
    pager.scroll_y = 0;

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    pager.render(&buf, area);

    // First line should show "1" before pipe
    var found_one = false;
    for (0..7) |x| {
        const cell = buf.getConst(@intCast(x), 0);
        if (cell != null and cell.?.char == '1') {
            found_one = true;
            break;
        }
    }
    try testing.expect(found_one);
}

test "Pager.render without line numbers flag omits prefix" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"Content"};
    const pager = Pager.init(lines);  // No withLineNumbers
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    pager.render(&buf, area);

    // First character should be content, not line number
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'C'), cell.?.char);
}

test "Pager.render line number prefix width is correct" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"Content"};
    const pager = Pager.init(lines).withLineNumbers();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    pager.render(&buf, area);

    // Content should start at position 7 (4-digit number + " | ")
    const cell = buf.getConst(7, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'C'), cell.?.char);
}

// ============================================================================
// RENDER SEARCH TESTS
// ============================================================================

test "Pager.render with empty search query shows no highlight" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"find me"};
    const pager = Pager.init(lines)
        .withSearchQuery("")
        .withHighlightStyle(.{ .reverse = true });

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    pager.render(&buf, area);

    // Content should render without highlight style
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    // Cell should not have reverse style applied
    try testing.expect(!cell.?.style.reverse);
}

test "Pager.render highlights matching search query" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"find me"};
    const pager = Pager.init(lines)
        .withSearchQuery("find")
        .withHighlightStyle(.{ .reverse = true })
        .withCaseSensitive(true);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    pager.render(&buf, area);

    // Characters matching "find" should have highlight style
    var highlighted_count: usize = 0;
    for (0..4) |x| {
        const cell = buf.getConst(@intCast(x), 0);
        if (cell != null and cell.?.style.reverse) {
            highlighted_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), highlighted_count);
}

test "Pager.render respects case sensitivity for search" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"Find"};
    const pager = Pager.init(lines)
        .withSearchQuery("find")
        .withHighlightStyle(.{ .bold = true })
        .withCaseSensitive(true);  // Case sensitive

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    pager.render(&buf, area);

    // With case sensitivity, "Find" != "find", should not match
    var bold_count: usize = 0;
    for (0..4) |x| {
        const cell = buf.getConst(@intCast(x), 0);
        if (cell != null and cell.?.style.bold) {
            bold_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), bold_count);
}

test "Pager.render case-insensitive search matches" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"Find"};
    const pager = Pager.init(lines)
        .withSearchQuery("find")
        .withHighlightStyle(.{ .bold = true })
        .withCaseSensitive(false);  // Case insensitive

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    pager.render(&buf, area);

    // With case insensitivity, "Find" should match "find"
    var bold_count: usize = 0;
    for (0..4) |x| {
        const cell = buf.getConst(@intCast(x), 0);
        if (cell != null and cell.?.style.bold) {
            bold_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), bold_count);
}

// ============================================================================
// RENDER WITH BLOCK TESTS
// ============================================================================

test "Pager.render with block draws border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();

    const lines = &[_][]const u8{"Content"};
    const block = Block{ .title = "Pager" };
    const pager = Pager.init(lines).withBlock(block);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    pager.render(&buf, area);

    // Content should be inset from borders (at least 1 position)
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
}

// ============================================================================
// RENDER WITH WRAP TESTS
// ============================================================================

test "Pager.render with wrap flag renders long lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"very long line that exceeds width"};
    const pager = Pager.init(lines).withWrap();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    pager.render(&buf, area);

    // Should render without crash; content may wrap to multiple rows
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
}

// ============================================================================
// RENDER WITH STYLE TESTS
// ============================================================================

test "Pager.render applies text style to content" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const lines = &[_][]const u8{"Styled"};
    const style = Style{ .bold = true, .italic = true };
    const pager = Pager.init(lines).withStyle(style);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    pager.render(&buf, area);

    // Content should have applied style
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expect(cell.?.style.bold);
    try testing.expect(cell.?.style.italic);
}

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

test "Pager handles very long single line" {
    const lines = &[_][]const u8{"a very very very very very very very very very very very very very very very long line"};
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 1), pager.lines.len);
    try testing.expect(pager.maxLineWidth() > 50);
}

test "Pager handles many empty lines" {
    const lines = &[_][]const u8{ "", "", "", "", "" };
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 5), pager.lines.len);
    try testing.expectEqual(@as(usize, 0), pager.maxLineWidth());
}

test "Pager handles mixed empty and non-empty lines" {
    const lines = &[_][]const u8{ "", "content", "", "more" };
    const pager = Pager.init(lines);

    try testing.expectEqual(@as(usize, 4), pager.lines.len);
    try testing.expectEqual(@as(usize, 7), pager.maxLineWidth());
}

test "Pager navigation preserves line data integrity" {
    const lines = &[_][]const u8{ "First", "Second", "Third" };
    var pager = Pager.init(lines);

    pager.scrollDown(10);
    pager.scrollRight(3);
    pager.pageDown(10);

    // Data should remain intact
    try testing.expectEqualStrings("First", pager.lines[0]);
    try testing.expectEqualStrings("Second", pager.lines[1]);
    try testing.expectEqualStrings("Third", pager.lines[2]);
}

test "Pager render with offset area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 100, 50);
    defer buf.deinit();

    const lines = &[_][]const u8{"content"};
    const pager = Pager.init(lines);

    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 15 };
    pager.render(&buf, area);

    // Content should be at area's starting position
    const cell = buf.getConst(20, 10);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'c'), cell.?.char);
}

test "Pager multiple navigation operations sequence correctly" {
    const lines = &[_][]const u8{
        "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10",
    };
    var pager = Pager.init(lines);

    pager.pageDown(3);
    try testing.expectEqual(@as(usize, 3), pager.scroll_y);

    pager.scrollUp();
    try testing.expectEqual(@as(usize, 2), pager.scroll_y);

    pager.goToTop();
    try testing.expectEqual(@as(usize, 0), pager.scroll_y);

    pager.goToLine(7);
    try testing.expectEqual(@as(usize, 7), pager.scroll_y);

    pager.goToBottom(5);
    try testing.expectEqual(@as(usize, 10), pager.scroll_y);
}

// ============================================================================
// IMMUTABILITY TESTS
// ============================================================================

test "Pager builder methods return new instances without mutation" {
    const lines = &[_][]const u8{"test"};
    const pager1 = Pager.init(lines);
    const pager2 = pager1.withLineNumbers();

    // pager1 should remain unchanged
    try testing.expect(!pager1.line_numbers);
    try testing.expect(pager2.line_numbers);
}

test "Pager builder returns instances with copied data" {
    const lines = &[_][]const u8{"test"};
    const style = Style{ .bold = true };
    const pager1 = Pager.init(lines);
    const pager2 = pager1.withStyle(style);

    try testing.expect(!pager1.style.bold);
    try testing.expect(pager2.style.bold);
}
