//! LogViewer Widget Tests — TDD Red Phase
//!
//! Tests LogViewer widget with scrollable log pane, level coloring,
//! search/highlight, and tail mode. Validates scrolling, filtering,
//! styling, and edge case handling.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const LogViewer = sailor.tui.widgets.LogViewer;
const LogEntry = sailor.tui.widgets.LogEntry;
const LogLevel = sailor.tui.widgets.LogLevel;

// ============================================================================
// Init Tests (5 tests)
// ============================================================================

test "LogViewer.init creates viewer with entries slice" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Hello", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    try testing.expectEqual(@as(usize, 1), viewer.entries.len);
}

test "LogViewer.init sets scroll_offset to 0" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Test", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "LogViewer.init sets search_query to empty string" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .debug, .message = "Msg", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    try testing.expectEqualStrings("", viewer.search_query);
}

test "LogViewer.init sets tail_mode to false" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Message", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    try testing.expect(viewer.tail_mode == false);
}

test "LogViewer.init sets show_level_tags to true" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .warn, .message = "Warning", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    try testing.expect(viewer.show_level_tags == true);
}

// ============================================================================
// scrollDown Tests (7 tests)
// ============================================================================

test "scrollDown increments scroll_offset by 1" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "M1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "M2", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 1), viewer.scroll_offset);
}

test "scrollDown clamps at entries.len - 1" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 1; // At last entry
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 1), viewer.scroll_offset);
}

test "scrollDown on empty entries has no effect" {
    var entries: [0]LogEntry = undefined;
    var viewer = LogViewer.init(&entries);
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "scrollDown on single entry has no effect" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .debug, .message = "Only", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "scrollDown multiple times accumulates offset" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scrollDown();
    viewer.scrollDown();
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 3), viewer.scroll_offset);
}

test "scrollDown from middle position to near end" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 1;
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
}

test "scrollDown to last entry position" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "A", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "B", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "C", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scrollDown();
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
}

// ============================================================================
// scrollUp Tests (5 tests)
// ============================================================================

test "scrollUp decrements scroll_offset by 1" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "M1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "M2", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 1;
    viewer.scrollUp();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "scrollUp clamps at 0" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Entry", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scrollUp();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "scrollUp on empty entries has no effect" {
    var entries: [0]LogEntry = undefined;
    var viewer = LogViewer.init(&entries);
    viewer.scrollUp();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "scrollUp multiple times from high position" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 3;
    viewer.scrollUp();
    viewer.scrollUp();
    try testing.expectEqual(@as(usize, 1), viewer.scroll_offset);
}

test "scrollUp from middle to start" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .debug, .message = "First", .source = null },
        .{ .timestamp_ms = 2000, .level = .debug, .message = "Second", .source = null },
        .{ .timestamp_ms = 3000, .level = .debug, .message = "Third", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 2;
    viewer.scrollUp();
    viewer.scrollUp();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

// ============================================================================
// pageDown/pageUp Tests (6 tests)
// ============================================================================

test "pageDown adds page_size to scroll_offset" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
        .{ .timestamp_ms = 5000, .level = .info, .message = "E5", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.pageDown(2);
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
}

test "pageDown clamps at entries.len - 1" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.pageDown(10);
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
}

test "pageUp subtracts page_size from scroll_offset" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
        .{ .timestamp_ms = 5000, .level = .info, .message = "E5", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 4;
    viewer.pageUp(2);
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
}

test "pageUp clamps at 0" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Entry", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 1;
    viewer.pageUp(5);
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "pageDown on empty entries has no effect" {
    var entries: [0]LogEntry = undefined;
    var viewer = LogViewer.init(&entries);
    viewer.pageDown(5);
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "pageUp on empty entries has no effect" {
    var entries: [0]LogEntry = undefined;
    var viewer = LogViewer.init(&entries);
    viewer.pageUp(5);
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

// ============================================================================
// goToTop/goToBottom Tests (5 tests)
// ============================================================================

test "goToTop resets scroll_offset to 0" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 2;
    viewer.goToTop();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "goToBottom sets scroll_offset to entries.len - 1" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.goToBottom();
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
}

test "goToTop on empty entries" {
    var entries: [0]LogEntry = undefined;
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 5;
    viewer.goToTop();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "goToBottom on empty entries stays at 0" {
    var entries: [0]LogEntry = undefined;
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 10;
    viewer.goToBottom();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "goToBottom on single entry sets to 0" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .warn, .message = "Only", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.goToBottom();
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

// ============================================================================
// search/clearSearch Tests (5 tests)
// ============================================================================

test "search sets search_query" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Hello world", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.search("world");
    try testing.expectEqualStrings("world", viewer.search_query);
}

test "search does NOT scroll" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 2;
    viewer.search("query");
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
}

test "clearSearch resets search_query to empty string" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Text", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.search("find");
    try testing.expectEqualStrings("find", viewer.search_query);
    viewer.clearSearch();
    try testing.expectEqualStrings("", viewer.search_query);
}

test "search with empty string" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .debug, .message = "Message", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.search("");
    try testing.expectEqualStrings("", viewer.search_query);
}

test "clearSearch on already empty search_query is safe" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .warn, .message = "Entry", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.clearSearch();
    try testing.expectEqualStrings("", viewer.search_query);
}

// ============================================================================
// setTailMode Tests (3 tests)
// ============================================================================

test "setTailMode sets tail_mode to true" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.setTailMode(true);
    try testing.expect(viewer.tail_mode == true);
}

test "setTailMode sets tail_mode to false" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.tail_mode = true;
    viewer.setTailMode(false);
    try testing.expect(viewer.tail_mode == false);
}

test "setTailMode toggles between true and false" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    try testing.expect(viewer.tail_mode == false);
    viewer.setTailMode(true);
    try testing.expect(viewer.tail_mode == true);
    viewer.setTailMode(false);
    try testing.expect(viewer.tail_mode == false);
}

// ============================================================================
// LogLevel.color() Tests (6 tests)
// ============================================================================

test "LogLevel.trace has gray color" {
    try testing.expectEqual(sailor.tui.Color.bright_black, LogLevel.trace.defaultColor());
}

test "LogLevel.debug has cyan color" {
    try testing.expectEqual(sailor.tui.Color.cyan, LogLevel.debug.defaultColor());
}

test "LogLevel.info has green color" {
    try testing.expectEqual(sailor.tui.Color.green, LogLevel.info.defaultColor());
}

test "LogLevel.warn has yellow color" {
    try testing.expectEqual(sailor.tui.Color.yellow, LogLevel.warn.defaultColor());
}

test "LogLevel.err has red color" {
    try testing.expectEqual(sailor.tui.Color.red, LogLevel.err.defaultColor());
}

test "LogLevel.fatal has magenta color" {
    try testing.expectEqual(sailor.tui.Color.magenta, LogLevel.fatal.defaultColor());
}

// ============================================================================
// Builder API Tests (5 tests)
// ============================================================================

test "withBlock returns viewer with block set" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    const block = Block{};
    const viewer2 = viewer.withBlock(block);
    try testing.expect(viewer2.block != null);
}

test "withLevelStyle returns viewer with level_style set" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    const style = Style{ .bold = true };
    const viewer2 = viewer.withLevelStyle(style);
    try testing.expect(viewer2.level_style.bold == true);
}

test "withSearchStyle returns viewer with search_style set" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    const style = Style{ .italic = true };
    const viewer2 = viewer.withSearchStyle(style);
    try testing.expect(viewer2.search_style.italic == true);
}

test "withShowLevels returns viewer with show_level_tags set to false" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    const viewer2 = viewer.withShowLevels(false);
    try testing.expect(viewer2.show_level_tags == false);
}

test "withTailMode returns viewer with tail_mode set to true" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    const viewer2 = viewer.withTailMode(true);
    try testing.expect(viewer2.tail_mode == true);
}

// ============================================================================
// Render — Basic Tests (8 tests)
// ============================================================================

test "render on zero-area does not crash" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
}

test "render with empty entries does not crash" {
    var entries: [0]LogEntry = undefined;
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render single entry does not crash" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Single", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render writes message text to buffer" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Hello", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // With show_level_tags=true (default), first char is '[' from level tag "[INFO] "
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    // Message "Hello" starts at col 7 (after "[INFO] ")
    const h_cell = buf.getConst(7, 0);
    try testing.expect(h_cell != null);
    try testing.expectEqual(@as(u21, 'H'), h_cell.?.char);
}

test "render with show_level_tags true includes level prefix" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .warn, .message = "Warning", .source = null },
    };
    var viewer = LogViewer.init(&entries).withShowLevels(true);
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
    // "[WARN] " is 7 chars; col 0 should be '[', col 1 'W', col 2 'A', col 3 'R', col 4 'N'
    const cell0 = buf.getConst(0, 0);
    try testing.expect(cell0 != null);
    try testing.expectEqual(@as(u21, '['), cell0.?.char);
    const cell1 = buf.getConst(1, 0);
    try testing.expect(cell1 != null);
    try testing.expectEqual(@as(u21, 'W'), cell1.?.char);
}

test "render respects scroll_offset (skips earlier entries)" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "First", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Second", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "Third", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scroll_offset = 1;
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // With scroll_offset=1, "Second" is first visible entry; message starts at col 7
    const s_cell = buf.getConst(7, 0);
    try testing.expect(s_cell != null);
    try testing.expectEqual(@as(u21, 'S'), s_cell.?.char);
    // "First" should NOT appear — row 0 shows "Second", not "First"
    // Verify row 1 shows "Third"
    const t_cell = buf.getConst(7, 1);
    try testing.expect(t_cell != null);
    try testing.expectEqual(@as(u21, 'T'), t_cell.?.char);
}

test "render with block border does not crash" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    const block = Block{};
    var viewer = LogViewer.init(&entries).withBlock(block);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render fills available rows up to height" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Line1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Line2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "Line3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // All 3 entries should occupy rows 0, 1, 2; message starts at col 7
    const l1 = buf.getConst(7, 0);
    try testing.expect(l1 != null);
    try testing.expectEqual(@as(u21, 'L'), l1.?.char); // "Line1"
    const l2 = buf.getConst(7, 1);
    try testing.expect(l2 != null);
    try testing.expectEqual(@as(u21, 'L'), l2.?.char); // "Line2"
    const l3 = buf.getConst(7, 2);
    try testing.expect(l3 != null);
    try testing.expectEqual(@as(u21, 'L'), l3.?.char); // "Line3"
    // Row 3 should be blank (no 4th entry)
    const blank = buf.getConst(7, 3);
    try testing.expect(blank != null);
    try testing.expectEqual(@as(u21, ' '), blank.?.char);
}

// ============================================================================
// Render — Level Tag Tests (4 tests)
// ============================================================================

test "render debug level tag appears with cyan color" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .debug, .message = "Debug msg", .source = null },
    };
    var viewer = LogViewer.init(&entries).withShowLevels(true);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "[DEBUG]" tag at col 0; fg should be .cyan (debug defaultColor)
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    try testing.expectEqual(@as(?sailor.tui.Color, .cyan), cell.?.style.fg);
}

test "render info level tag appears with green color" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Info msg", .source = null },
    };
    var viewer = LogViewer.init(&entries).withShowLevels(true);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "[INFO] " tag at col 0; fg should be .green
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    try testing.expectEqual(@as(?sailor.tui.Color, .green), cell.?.style.fg);
}

test "render warn level tag appears with yellow color" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .warn, .message = "Warning", .source = null },
    };
    var viewer = LogViewer.init(&entries).withShowLevels(true);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "[WARN] " tag at col 0; fg should be .yellow
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    try testing.expectEqual(@as(?sailor.tui.Color, .yellow), cell.?.style.fg);
}

test "render err level tag appears with red color" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .err, .message = "Error occurred", .source = null },
    };
    var viewer = LogViewer.init(&entries).withShowLevels(true);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "[ERR]  " tag at col 0; fg should be .red
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
    try testing.expectEqual(@as(?sailor.tui.Color, .red), cell.?.style.fg);
}

// ============================================================================
// Render — Search Highlight Tests (4 tests)
// ============================================================================

test "render with search_query highlights matching text in entry" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "find this text", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.search("this");
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "[INFO] " is 7 chars, "find " is 5 chars → "this" starts at col 12
    // search_style = .{ .bg = .yellow, .fg = .black }
    const t_cell = buf.getConst(12, 0);
    try testing.expect(t_cell != null);
    try testing.expectEqual(@as(u21, 't'), t_cell.?.char);
    try testing.expectEqual(@as(?sailor.tui.Color, .yellow), t_cell.?.style.bg);
    try testing.expectEqual(@as(?sailor.tui.Color, .black), t_cell.?.style.fg);
    // "find" before the match should NOT have search_style bg
    const f_cell = buf.getConst(7, 0);
    try testing.expect(f_cell != null);
    try testing.expectEqual(@as(u21, 'f'), f_cell.?.char);
    try testing.expect(f_cell.?.style.bg == null); // no highlight
}

test "render search highlight case-insensitive" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Find This Text", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.search("this");
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "Find " (5) + level (7) = "This" starts at col 12, should have search bg
    const cell = buf.getConst(12, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'T'), cell.?.char);
    try testing.expectEqual(@as(?sailor.tui.Color, .yellow), cell.?.style.bg);
}

test "render no search_query renders without highlight" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Some message", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    // search_query = "" (default) — message chars should have no bg color
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "Some" starts at col 7; no search highlight → bg should be null
    const s_cell = buf.getConst(7, 0);
    try testing.expect(s_cell != null);
    try testing.expectEqual(@as(u21, 'S'), s_cell.?.char);
    try testing.expect(s_cell.?.style.bg == null);
}

test "render search with no matches renders normally" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Lorem ipsum", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.search("xyz123");
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "Lorem" starts at col 7, no search match → normal style (no bg)
    const l_cell = buf.getConst(7, 0);
    try testing.expect(l_cell != null);
    try testing.expectEqual(@as(u21, 'L'), l_cell.?.char);
    try testing.expect(l_cell.?.style.bg == null);
}

// ============================================================================
// Render — Tail Mode Tests (3 tests)
// ============================================================================

test "render with tail_mode true shows latest entries at bottom" {
    // 3 entries, height=3 → tail starts at index 0 (all fit); last entry "New" at row 2
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Old1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Old2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "New", .source = null },
    };
    var viewer = LogViewer.init(&entries).withTailMode(true);
    var buf = try Buffer.init(testing.allocator, 40, 3);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 3 });
    // All 3 entries fit; "New" is at row 2, message starts at col 7
    const n_cell = buf.getConst(7, 2);
    try testing.expect(n_cell != null);
    try testing.expectEqual(@as(u21, 'N'), n_cell.?.char);
}

test "render with tail_mode true truncates oldest when overflow" {
    // 5 entries, height=3 → tail shows last 3 (E3, E4, E5)
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
        .{ .timestamp_ms = 5000, .level = .info, .message = "E5", .source = null },
    };
    var viewer = LogViewer.init(&entries).withTailMode(true);
    var buf = try Buffer.init(testing.allocator, 40, 3);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 3 });
    // Row 0 = "E3", row 1 = "E4", row 2 = "E5"; message starts at col 7
    const e3 = buf.getConst(7, 0);
    try testing.expect(e3 != null);
    try testing.expectEqual(@as(u21, 'E'), e3.?.char);
    const e5 = buf.getConst(7, 2);
    try testing.expect(e5 != null);
    try testing.expectEqual(@as(u21, 'E'), e5.?.char);
    // E1 and E2 should NOT be in buffer (row 0 shows E3, not E1)
    const col8 = buf.getConst(8, 0); // second char of message
    try testing.expect(col8 != null);
    try testing.expectEqual(@as(u21, '3'), col8.?.char); // "E3" not "E1"
}

test "render with tail_mode false shows earliest entries at top" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "First", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Second", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "Third", .source = null },
    };
    var viewer = LogViewer.init(&entries).withTailMode(false);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // Normal mode: "First" at row 0, message starts at col 7
    const f_cell = buf.getConst(7, 0);
    try testing.expect(f_cell != null);
    try testing.expectEqual(@as(u21, 'F'), f_cell.?.char);
}

test "render tail_mode ignores scroll_offset (always shows latest)" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
    };
    var viewer = LogViewer.init(&entries).withTailMode(true);
    viewer.scroll_offset = 1; // scroll_offset ignored in tail mode
    var buf = try Buffer.init(testing.allocator, 40, 2);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 2 });
    // With height=2, tail shows E3 (row 0) and E4 (row 1), not E2 (scroll_offset=1)
    const r0 = buf.getConst(8, 0); // second char of "E3"
    try testing.expect(r0 != null);
    try testing.expectEqual(@as(u21, '3'), r0.?.char);
    const r1 = buf.getConst(8, 1); // second char of "E4"
    try testing.expect(r1 != null);
    try testing.expectEqual(@as(u21, '4'), r1.?.char);
}

// ============================================================================
// Edge Case Tests (5 tests)
// ============================================================================

test "render with single entry renders on first row" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Only entry", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "Only" starts at col 7; row 0 should have 'O'
    const o_cell = buf.getConst(7, 0);
    try testing.expect(o_cell != null);
    try testing.expectEqual(@as(u21, 'O'), o_cell.?.char);
    // Row 1 should be blank
    const blank = buf.getConst(7, 1);
    try testing.expect(blank != null);
    try testing.expectEqual(@as(u21, ' '), blank.?.char);
}

test "render with narrow width (10) truncates message" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Very long message that exceeds width", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    // Width=10; level tag "[INFO] " is 7 chars → only 3 chars of message fit
    // Col 9 (last col) should be within bounds and not crash
    const last_cell = buf.getConst(9, 0);
    try testing.expect(last_cell != null);
    // Col 10 (out of bounds) should return null
    const oob = buf.getConst(10, 0);
    try testing.expect(oob == null);
}

test "render with height=1 renders only one entry" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Line1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Line2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "Line3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 1 });
    // Only row 0 exists; "Line1" at col 7
    const l1_cell = buf.getConst(7, 0);
    try testing.expect(l1_cell != null);
    try testing.expectEqual(@as(u21, 'L'), l1_cell.?.char);
    // Row 1 is OOB — buffer only has 1 row
    const oob = buf.getConst(0, 1);
    try testing.expect(oob == null);
}

test "render with very long entry message handled safely" {
    const long_msg = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua";
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = long_msg, .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "render multiple entries in narrow area wraps or clips" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .debug, .message = "Msg1", .source = null },
        .{ .timestamp_ms = 2000, .level = .debug, .message = "Msg2", .source = null },
        .{ .timestamp_ms = 3000, .level = .debug, .message = "Msg3", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });
}

// ============================================================================
// Integration & Complex Scenarios (6 tests)
// ============================================================================

test "scrolling with multiple entries maintains scroll position" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.scrollDown();
    viewer.scrollDown();
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
    viewer.scrollUp();
    try testing.expectEqual(@as(usize, 1), viewer.scroll_offset);
}

test "search and scroll together preserves both states" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "First log", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Second log", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "Third entry", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.search("log");
    const query_before = viewer.search_query;
    viewer.scrollDown();
    try testing.expectEqualStrings(query_before, viewer.search_query);
    try testing.expectEqual(@as(usize, 1), viewer.scroll_offset);
}

test "builder chaining all methods" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "Log", .source = null },
    };
    const viewer = LogViewer.init(&entries);
    const block = Block{};
    const style = Style{ .bold = true };
    const viewer2 = viewer
        .withBlock(block)
        .withLevelStyle(style)
        .withTailMode(true)
        .withShowLevels(false);
    try testing.expect(viewer2.block != null);
    try testing.expect(viewer2.tail_mode == true);
    try testing.expect(viewer2.show_level_tags == false);
}

test "render all log levels with different colors in single view" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .debug, .message = "Debug", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Info", .source = null },
        .{ .timestamp_ms = 3000, .level = .warn, .message = "Warning", .source = null },
        .{ .timestamp_ms = 4000, .level = .err, .message = "Error", .source = null },
    };
    var viewer = LogViewer.init(&entries).withShowLevels(true);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "goToTop then render shows first entry at top" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "First", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "Middle", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "Last", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    viewer.goToBottom();
    viewer.goToTop();
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    viewer.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "pageDown then pageUp returns to original position" {
    var entries = [_]LogEntry{
        .{ .timestamp_ms = 1000, .level = .info, .message = "E1", .source = null },
        .{ .timestamp_ms = 2000, .level = .info, .message = "E2", .source = null },
        .{ .timestamp_ms = 3000, .level = .info, .message = "E3", .source = null },
        .{ .timestamp_ms = 4000, .level = .info, .message = "E4", .source = null },
        .{ .timestamp_ms = 5000, .level = .info, .message = "E5", .source = null },
    };
    var viewer = LogViewer.init(&entries);
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
    viewer.pageDown(2);
    try testing.expectEqual(@as(usize, 2), viewer.scroll_offset);
    viewer.pageUp(2);
    try testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}
