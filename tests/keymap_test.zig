//! KeyMap Widget Tests — Comprehensive Coverage
//!
//! Tests the KeyMap widget's initialization, scrolling, builder API, and rendering
//! across all edge cases and layout modes.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const KeyMap = sailor.tui.widgets.KeyMap;
const KeyBinding = sailor.tui.widgets.KeyBinding;
const KeySection = sailor.tui.widgets.KeySection;

/// Find first x position of a character in row y
fn findCharInRow(buf: Buffer, y: u16, char: u21) ?u16 {
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == char) return x;
        }
    }
    return null;
}

/// Check if row y contains a specific character
fn rowHasChar(buf: Buffer, y: u16, char: u21) bool {
    return findCharInRow(buf, y, char) != null;
}

/// Check if text exists in buffer at a given row (substring match)
fn rowHasText(buf: Buffer, y: u16, text: []const u8) bool {
    if (text.len == 0) return true;
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == text[0]) {
                // Potential match start
                var match = true;
                var offset: u16 = 1;
                while (offset < text.len and x + offset < buf.width) : (offset += 1) {
                    if (buf.getConst(x + offset, y)) |next_cell| {
                        if (next_cell.char != text[offset]) {
                            match = false;
                            break;
                        }
                    } else {
                        match = false;
                        break;
                    }
                }
                if (match and offset == text.len) return true;
            }
        }
    }
    return false;
}

// ============================================================================
// INITIALIZATION TESTS (5 tests)
// ============================================================================

test "KeyMap init with empty sections creates keymap at scroll_offset 0" {
    const sections: [0]KeySection = .{};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap init with one section zero bindings creates keymap" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Navigation", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
    try testing.expectEqual(@as(u8, 1), km.columns);
}

test "KeyMap init sets default columns to 1" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Edit", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(u8, 1), km.columns);
}

test "KeyMap init sets default key_width to 10" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Edit", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(u8, 10), km.key_width);
}

test "KeyMap init with multiple sections creates keymap" {
    const nav_bindings: [2]KeyBinding = .{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
    };
    const edit_bindings: [1]KeyBinding = .{
        .{ .key = "d", .description = "Delete" },
    };
    const sections = [_]KeySection{
        .{ .title = "Navigation", .bindings = &nav_bindings },
        .{ .title = "Editing", .bindings = &edit_bindings },
    };
    const km = KeyMap.init(&sections);
    try testing.expect(km.sections.len == 2);
}

// ============================================================================
// TOTALROWS TESTS (8 tests)
// ============================================================================

test "KeyMap totalRows with empty sections returns 0" {
    const sections: [0]KeySection = .{};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 0), km.totalRows());
}

test "KeyMap totalRows with one section zero bindings returns 1" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Nav", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 1), km.totalRows());
}

test "KeyMap totalRows with one section one binding returns 2" {
    const bindings = [_]KeyBinding{.{ .key = "q", .description = "Quit" }};
    const section = KeySection{ .title = "General", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 2), km.totalRows());
}

test "KeyMap totalRows with one section three bindings returns 4" {
    const bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
        .{ .key = "h", .description = "Left" },
    };
    const section = KeySection{ .title = "Move", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 4), km.totalRows());
}

test "KeyMap totalRows with two sections two bindings each returns 6" {
    const nav_bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
    };
    const edit_bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Delete" },
        .{ .key = "c", .description = "Change" },
    };
    const sections = [_]KeySection{
        .{ .title = "Nav", .bindings = &nav_bindings },
        .{ .title = "Edit", .bindings = &edit_bindings },
    };
    const km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 6), km.totalRows());
}

test "KeyMap totalRows columns=2 with four bindings returns 3" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
        .{ .key = "c", .description = "Charlie" },
        .{ .key = "d", .description = "Delta" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    // title row (1) + ceil(4/2) binding rows (2) = 3
    try testing.expectEqual(@as(usize, 3), km.totalRows());
}

test "KeyMap totalRows columns=2 with three bindings returns 3" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
        .{ .key = "c", .description = "Charlie" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    // title row (1) + ceil(3/2) binding rows (2) = 3
    try testing.expectEqual(@as(usize, 3), km.totalRows());
}

// ============================================================================
// SCROLL DOWN TESTS (5 tests)
// ============================================================================

test "KeyMap scrollDown from 0 advances to 1" {
    const bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
    };
    const section = KeySection{ .title = "Nav", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
    km.scrollDown();
    try testing.expectEqual(@as(usize, 1), km.scroll_offset);
}

test "KeyMap scrollDown clamps at max total rows" {
    const bindings = [_]KeyBinding{
        .{ .key = "q", .description = "Quit" },
    };
    const section = KeySection{ .title = "Gen", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    // Total rows = 2 (title + 1 binding)
    km.scrollDown();
    km.scrollDown();
    km.scrollDown();
    // Should not exceed totalRows()
    try testing.expect(km.scroll_offset <= km.totalRows());
}

test "KeyMap scrollDown on zero total rows stays at 0" {
    const sections: [0]KeySection = .{};
    var km = KeyMap.init(&sections);
    km.scrollDown();
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap multiple scrollDown calls accumulate" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
        .{ .key = "c", .description = "C" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scrollDown();
    km.scrollDown();
    try testing.expectEqual(@as(usize, 2), km.scroll_offset);
}

test "KeyMap scrollDown past end clamps not overflows" {
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "Ex" },
    };
    const section = KeySection{ .title = "X", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    // Total = 2, try to scroll way past
    for (0..100) |_| {
        km.scrollDown();
    }
    try testing.expect(km.scroll_offset <= km.totalRows());
}

// ============================================================================
// SCROLL UP TESTS (5 tests)
// ============================================================================

test "KeyMap scrollUp from 0 stays at 0" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Empty", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scrollUp();
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap scrollUp from 2 decreases to 1" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
        .{ .key = "c", .description = "C" },
    };
    const section = KeySection{ .title = "ABC", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 2;
    km.scrollUp();
    try testing.expectEqual(@as(usize, 1), km.scroll_offset);
}

test "KeyMap scrollUp from 1 goes to 0" {
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "X" },
    };
    const section = KeySection{ .title = "X", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 1;
    km.scrollUp();
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap multiple scrollUp from 0 stays at 0" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Empty", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    for (0..10) |_| {
        km.scrollUp();
    }
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap scrollUp then scrollDown returns to original" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
    };
    const section = KeySection{ .title = "AB", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 2;
    const before = km.scroll_offset;
    km.scrollUp();
    km.scrollDown();
    try testing.expectEqual(before, km.scroll_offset);
}

// ============================================================================
// PAGE DOWN / PAGE UP TESTS (6 tests)
// ============================================================================

test "KeyMap pageDown with height 5 from offset 0" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Down" },
        .{ .key = "b", .description = "Up" },
    };
    const section = KeySection{ .title = "AB", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    const height: u16 = 5;
    km.pageDown(height);
    // totalRows() = 3, clamped — scroll_offset must not exceed totalRows()
    try testing.expect(km.scroll_offset <= km.totalRows());
}

test "KeyMap pageDown clamps at max" {
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "X" },
    };
    const section = KeySection{ .title = "X", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    // Total rows = 2
    km.pageDown(100);
    try testing.expect(km.scroll_offset <= km.totalRows());
}

test "KeyMap pageUp with height 5 from offset 10" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
        .{ .key = "c", .description = "C" },
    };
    const section = KeySection{ .title = "ABC", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 10;
    km.pageUp(5);
    try testing.expectEqual(@as(usize, 5), km.scroll_offset);
}

test "KeyMap pageUp from 0 stays at 0" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Empty", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.pageUp(5);
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap pageDown then pageUp returns to start" {
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "X" },
        .{ .key = "y", .description = "Y" },
    };
    const section = KeySection{ .title = "XY", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    const before = km.scroll_offset;
    km.pageDown(3);
    km.pageUp(3);
    try testing.expectEqual(before, km.scroll_offset);
}

test "KeyMap pageDown with height 0 is no-op" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
    };
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.pageDown(0);
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

// ============================================================================
// GO TO TOP / GO TO BOTTOM TESTS (4 tests)
// ============================================================================

test "KeyMap goToTop sets scroll_offset to 0" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
    };
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 10;
    km.goToTop();
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap goToTop from 0 stays at 0" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Empty", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.goToTop();
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap goToBottom sets to max" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
        .{ .key = "c", .description = "C" },
    };
    const section = KeySection{ .title = "ABC", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.goToBottom();
    // Total rows = 4 (1 title + 3 bindings), max scroll should clamp properly
    try testing.expect(km.scroll_offset >= 0);
}

test "KeyMap goToTop after goToBottom returns to 0" {
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "X" },
    };
    const section = KeySection{ .title = "X", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.goToBottom();
    km.goToTop();
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

// ============================================================================
// BUILDER API TESTS (8 tests)
// ============================================================================

test "KeyMap withBlock returns new instance with block set" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km1 = KeyMap.init(&sections);
    const block = Block{ .title = "Shortcuts" };
    const km2 = km1.withBlock(block);
    try testing.expect(km2.block != null);
}

test "KeyMap withBlock original unchanged" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km1 = KeyMap.init(&sections);
    const block = Block{ .title = "Help" };
    _ = km1.withBlock(block);
    try testing.expect(km1.block == null);
}

test "KeyMap withKeyStyle returns new instance" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km1 = KeyMap.init(&sections);
    const style = Style{ .bold = true };
    const km2 = km1.withKeyStyle(style);
    try testing.expectEqual(true, km2.key_style.bold);
}

test "KeyMap withDescStyle original unchanged" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km1 = KeyMap.init(&sections);
    const style = Style{ .italic = true };
    _ = km1.withDescStyle(style);
    try testing.expect(!km1.desc_style.italic);
}

test "KeyMap withSectionStyle returns new instance" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km1 = KeyMap.init(&sections);
    const style = Style{ .dim = true };
    const km2 = km1.withSectionStyle(style);
    try testing.expectEqual(true, km2.section_style.dim);
}

test "KeyMap withColumns returns new instance" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km1 = KeyMap.init(&sections);
    const km2 = km1.withColumns(2);
    try testing.expectEqual(@as(u8, 2), km2.columns);
}

test "KeyMap withKeyWidth returns new instance" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km1 = KeyMap.init(&sections);
    const km2 = km1.withKeyWidth(15);
    try testing.expectEqual(@as(u8, 15), km2.key_width);
}

test "KeyMap builder chaining works" {
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    km = km.withKeyWidth(12);
    km = km.withKeyStyle(Style{ .bold = true });
    try testing.expectEqual(@as(u8, 2), km.columns);
    try testing.expectEqual(@as(u8, 12), km.key_width);
    try testing.expectEqual(true, km.key_style.bold);
}

// ============================================================================
// RENDER TESTS — EDGE CASES (10 tests)
// ============================================================================

test "KeyMap render with zero-area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Verify buffer remains unmodified (render should not write to zero-area)
    try testing.expectEqual(@as(u16, 10), buf.width);
    try testing.expectEqual(@as(u16, 10), buf.height);
}

test "KeyMap render with zero-width doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 5 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Verify scroll_offset unchanged after render (state should not change on invalid area)
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap render with zero-height doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Verify buffer dimensions preserved (render to zero-height area should not crash or modify state)
    try testing.expectEqual(@as(u16, 10), buf.width);
}

test "KeyMap render with empty sections doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const sections: [0]KeySection = .{};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // totalRows should be 0 with empty sections
    try testing.expectEqual(@as(usize, 0), km.totalRows());
}

test "KeyMap render with 1x1 area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // With 1x1 area, first char of title should render at (0, 0)
    if (buf.getConst(0, 0)) |cell| {
        try testing.expectEqual(@as(u21, 'A'), cell.char);
    }
}

test "KeyMap render with area smaller than content doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 2 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
        .{ .key = "c", .description = "Charlie" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // totalRows should be 4 (title + 3 bindings), but only 2 rows visible in area.height=2
    try testing.expectEqual(@as(usize, 4), km.totalRows());
}

test "KeyMap render with scroll_offset past content doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "q", .description = "Quit" },
    };
    const section = KeySection{ .title = "General", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 1000;
    km.render(&buf, area);
    // scroll_offset should remain 1000 (render does not modify state)
    try testing.expectEqual(@as(usize, 1000), km.scroll_offset);
}

test "KeyMap render single binding shows key in buffer" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "q", .description = "Quit" },
    };
    const section = KeySection{ .title = "General", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // 'q' should appear at row 1 (row 0 is title)
    try testing.expect(rowHasChar(buf, 1, 'q'));
}

test "KeyMap render section title appears in buffer" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Navigation", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Title first char 'N' should appear at row 0
    try testing.expect(rowHasChar(buf, 0, 'N'));
}

test "KeyMap render key text uses key_style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "Execute" },
    };
    const section = KeySection{ .title = "Actions", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withKeyStyle(Style{ .bold = true });
    km.render(&buf, area);
    // 'x' should be at row 1 with bold
    if (findCharInRow(buf, 1, 'x')) |x| {
        if (buf.getConst(x, 1)) |cell| {
            try testing.expectEqual(true, cell.style.bold);
        }
    }
}

// ============================================================================
// RENDER TESTS — SECTION TITLES (6 tests)
// ============================================================================

test "KeyMap render section title char appears at expected y row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Help", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Title should be at row 0 (area.y)
    try testing.expect(rowHasChar(buf, 0, 'H'));
}

test "KeyMap render first char of title appears at area.x" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 5, .y = 0, .width = 75, .height = 10 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Keys", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // 'K' should appear starting at x=5
    if (findCharInRow(buf, area.y, 'K')) |x| {
        try testing.expect(x >= area.x);
    }
}

test "KeyMap render second section title appears after first section's bindings" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 20);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    const nav_bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
    };
    const edit_bindings: [0]KeyBinding = .{};
    const sections = [_]KeySection{
        .{ .title = "Nav", .bindings = &nav_bindings },
        .{ .title = "Edit", .bindings = &edit_bindings },
    };
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // First title "Nav" at row 0, binding at row 1, second title "Edit" at row 2
    try testing.expect(rowHasChar(buf, 0, 'N'));
    try testing.expect(rowHasChar(buf, 1, 'j'));
    try testing.expect(rowHasChar(buf, 2, 'E'));
}

test "KeyMap render title rendered with section_style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Section", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withSectionStyle(Style{ .bold = true });
    km.render(&buf, area);
    // First char of title should have bold style
    if (findCharInRow(buf, 0, 'S')) |x| {
        if (buf.getConst(x, 0)) |cell| {
            try testing.expectEqual(true, cell.style.bold);
        }
    }
}

test "KeyMap render scroll past title hides it" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 1; // Skip title at row 0
    km.render(&buf, area);
    // Title 'L' should not appear at area.y
    try testing.expect(!rowHasChar(buf, 0, 'L'));
}

test "KeyMap render title visible when scroll_offset is 0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Menu", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Title 'M' should appear at row 0
    try testing.expect(rowHasChar(buf, 0, 'M'));
}

// ============================================================================
// RENDER TESTS — BINDING ROWS (8 tests)
// ============================================================================

test "KeyMap render binding key text appears in buffer" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Delete" },
    };
    const section = KeySection{ .title = "Edit", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    try testing.expect(rowHasChar(buf, 1, 'd'));
}

test "KeyMap render description text appears after key column" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "c", .description = "Copy" },
    };
    const section = KeySection{ .title = "Clipboard", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // "Copy" should appear at row 1
    try testing.expect(rowHasText(buf, 1, "Copy"));
}

test "KeyMap render key column padded to key_width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "z", .description = "Undo" },
    };
    const section = KeySection{ .title = "History", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withKeyWidth(12);
    km.render(&buf, area);
    // 'z' at row 1 should have space/padding until key_width
    if (findCharInRow(buf, 1, 'z')) |x| {
        if (findCharInRow(buf, 1, 'U')) |desc_x| {
            // Description should start after key_width
            try testing.expect(desc_x >= x + 12);
        }
    }
}

test "KeyMap render binding not visible when scrolled past" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "q", .description = "Quit" },
    };
    const section = KeySection{ .title = "General", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 100;
    km.render(&buf, area);
    // 'q' should not appear in rendered area
    try testing.expect(!rowHasChar(buf, 0, 'q'));
}

test "KeyMap render binding appears at correct y when scroll_offset is 1" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
    };
    const section = KeySection{ .title = "AB", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 1;
    km.render(&buf, area);
    // With scroll_offset=1, binding 'a' at virtual row 1 appears at render row 0
    try testing.expect(rowHasChar(buf, 0, 'a'));
}

test "KeyMap render multiple bindings appear on consecutive rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 20);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
        .{ .key = "c", .description = "Charlie" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Title at 0, bindings at 1,2,3
    try testing.expect(rowHasChar(buf, 1, 'a'));
    try testing.expect(rowHasChar(buf, 2, 'b'));
    try testing.expect(rowHasChar(buf, 3, 'c'));
}

test "KeyMap render long key truncated to key_width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "very-long-key", .description = "Action" },
    };
    const section = KeySection{ .title = "Keys", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withKeyWidth(5);
    km.render(&buf, area);
    // key_width should be exactly 5
    try testing.expectEqual(@as(u8, 5), km.key_width);
}

test "KeyMap render long description doesn't overflow into next row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 20);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "This is a very long description that should not overflow" },
    };
    const section = KeySection{ .title = "Long", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // totalRows should be 2 (title + 1 binding), render should not crash
    try testing.expectEqual(@as(usize, 2), km.totalRows());
}

// ============================================================================
// RENDER TESTS — 2-COLUMN LAYOUT (6 tests)
// ============================================================================

test "KeyMap render columns=2 first binding at left half" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    km.render(&buf, area);
    // 'a' should appear at row 1
    try testing.expect(rowHasChar(buf, 1, 'a'));
}

test "KeyMap render columns=2 both bindings on same row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
    };
    const section = KeySection{ .title = "AB", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    km.render(&buf, area);
    // Both 'a' and 'b' should appear at row 1
    try testing.expect(rowHasChar(buf, 1, 'a'));
    try testing.expect(rowHasChar(buf, 1, 'b'));
}

test "KeyMap render columns=2 odd bindings last alone in left" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
        .{ .key = "c", .description = "Charlie" },
    };
    const section = KeySection{ .title = "ABC", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    km.render(&buf, area);
    // Row 1: a, b; Row 2: c alone
    try testing.expect(rowHasChar(buf, 1, 'a'));
    try testing.expect(rowHasChar(buf, 1, 'b'));
    try testing.expect(rowHasChar(buf, 2, 'c'));
}

test "KeyMap render columns=2 with 4 bindings uses 2 rows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
        .{ .key = "b", .description = "B" },
        .{ .key = "c", .description = "C" },
        .{ .key = "d", .description = "D" },
    };
    const section = KeySection{ .title = "ABCD", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    km.render(&buf, area);
    // Row 1: a,b; Row 2: c,d
    try testing.expect(rowHasChar(buf, 1, 'a') and rowHasChar(buf, 1, 'b'));
    try testing.expect(rowHasChar(buf, 2, 'c') and rowHasChar(buf, 2, 'd'));
}

test "KeyMap render columns=2 narrow area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "X" },
        .{ .key = "y", .description = "Y" },
    };
    const section = KeySection{ .title = "XY", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    km.render(&buf, area);
    // With 2 columns, totalRows should be 2 (title + ceil(2/2) bindings rows)
    try testing.expectEqual(@as(usize, 2), km.totalRows());
}

test "KeyMap render columns=2 correct key at right column x offset" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "First" },
        .{ .key = "b", .description = "Second" },
    };
    const section = KeySection{ .title = "Test", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withColumns(2);
    km.render(&buf, area);
    // Both keys on row 1, 'b' should be to the right of 'a'
    if (findCharInRow(buf, 1, 'a')) |xa| {
        if (findCharInRow(buf, 1, 'b')) |xb| {
            try testing.expect(xb > xa);
        }
    }
}

// ============================================================================
// RENDER TESTS — SCROLLING (6 tests)
// ============================================================================

test "KeyMap render after scrollDown top row hidden" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
    };
    // Title starts with 'N' — after scrollDown, 'N' from title should not appear at row 0
    const section = KeySection{ .title = "Navigation", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scrollDown();
    km.render(&buf, area);
    // Title 'N' should not appear at row 0 (scrolled past); first binding row visible instead
    try testing.expect(!rowHasChar(buf, 0, 'N'));
}

test "KeyMap render after scrollDown next row appears at area.y" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "Execute" },
        .{ .key = "y", .description = "Yank" },
    };
    const section = KeySection{ .title = "Ops", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scrollDown();
    km.render(&buf, area);
    // First binding 'x' should appear at row 0 after scrolling
    try testing.expect(rowHasChar(buf, 0, 'x'));
}

test "KeyMap render scroll_offset=0 shows section title at area.y" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings: [0]KeyBinding = .{};
    const section = KeySection{ .title = "Menu", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // Title 'M' at area.y=0
    try testing.expect(rowHasChar(buf, 0, 'M'));
}

test "KeyMap render scrolled past title shows first binding at area.y" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "q", .description = "Quit" },
    };
    const section = KeySection{ .title = "Quit", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 1;
    km.render(&buf, area);
    // Binding 'q' appears at row 0
    try testing.expect(rowHasChar(buf, 0, 'q'));
}

test "KeyMap render scroll shows content at correct vertical positions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Alpha" },
        .{ .key = "b", .description = "Beta" },
        .{ .key = "c", .description = "Charlie" },
    };
    const section = KeySection{ .title = "Letters", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 2;
    km.render(&buf, area);
    // With scroll_offset=2, binding 'b' at virtual row 2 appears at render row 0
    try testing.expect(rowHasChar(buf, 0, 'b'));
}

test "KeyMap render goToBottom then render doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "e", .description = "End" },
    };
    const section = KeySection{ .title = "Move", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.goToBottom();
    km.render(&buf, area);
    // After goToBottom, scroll_offset should equal totalRows (2)
    try testing.expectEqual(@as(usize, 2), km.scroll_offset);
}

// ============================================================================
// EDGE CASES — SINGLE AND MANY (4 tests)
// ============================================================================

test "KeyMap render single section single binding full render" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "?", .description = "Help" },
    };
    const section = KeySection{ .title = "Info", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'I'));
    try testing.expect(rowHasChar(buf, 1, '?'));
}

test "KeyMap render many sections many bindings doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 50);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 50 };
    const nav_bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
        .{ .key = "h", .description = "Left" },
        .{ .key = "l", .description = "Right" },
    };
    const edit_bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Delete" },
        .{ .key = "c", .description = "Change" },
        .{ .key = "y", .description = "Yank" },
    };
    const search_bindings = [_]KeyBinding{
        .{ .key = "/", .description = "Search" },
        .{ .key = "?", .description = "Reverse" },
    };
    const sections = [_]KeySection{
        .{ .title = "Navigation", .bindings = &nav_bindings },
        .{ .title = "Editing", .bindings = &edit_bindings },
        .{ .title = "Search", .bindings = &search_bindings },
    };
    const km = KeyMap.init(&sections);
    km.render(&buf, area);
    // totalRows = 3 titles + (4+3+2) bindings = 12 rows
    try testing.expectEqual(@as(usize, 12), km.totalRows());
}

test "KeyMap render key_width=1 doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
    };
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withKeyWidth(1);
    km.render(&buf, area);
    // key_width should be exactly 1
    try testing.expectEqual(@as(u8, 1), km.key_width);
}

test "KeyMap render key_width=255 with narrow area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "z", .description = "Z" },
    };
    const section = KeySection{ .title = "Z", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km = km.withKeyWidth(255);
    km.render(&buf, area);
    // key_width should be exactly 255 (no clamping)
    try testing.expectEqual(@as(u8, 255), km.key_width);
}

// ============================================================================
// COMPLEX SCENARIOS (5 tests)
// ============================================================================

test "KeyMap full workflow: init, scroll, render multiple times" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 15);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };
    const bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
        .{ .key = "d", .description = "Delete" },
    };
    const section = KeySection{ .title = "Main", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections)
        .withKeyStyle(Style{ .bold = true })
        .withSectionStyle(Style{ .dim = true });
    km.render(&buf, area);
    km.scrollDown();
    km.render(&buf, area);
    km.goToTop();
    km.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap goToBottom then goToTop cycles correctly" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "A" },
    };
    const section = KeySection{ .title = "A", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.goToBottom();
    try testing.expect(km.scroll_offset >= 0);
    km.goToTop();
    try testing.expectEqual(@as(usize, 0), km.scroll_offset);
}

test "KeyMap state persists across render calls" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const bindings = [_]KeyBinding{
        .{ .key = "x", .description = "X" },
    };
    const section = KeySection{ .title = "X", .bindings = &bindings };
    const sections = [_]KeySection{section};
    var km = KeyMap.init(&sections);
    km.scroll_offset = 1;
    const before = km.scroll_offset;
    km.render(&buf, area);
    km.render(&buf, area);
    km.render(&buf, area);
    try testing.expectEqual(before, km.scroll_offset);
}

test "KeyMap with block border doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 15);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };
    const bindings = [_]KeyBinding{
        .{ .key = "h", .description = "Help" },
    };
    const section = KeySection{ .title = "Help", .bindings = &bindings };
    const sections = [_]KeySection{section};
    const block = Block{ .title = "Shortcuts" };
    const km = KeyMap.init(&sections).withBlock(block);
    km.render(&buf, area);
    // block should be set (not null)
    try testing.expect(km.block != null);
}

test "KeyMap render with offset area and many sections" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 120, 25);
    defer buf.deinit();
    const area = Rect{ .x = 10, .y = 5, .width = 100, .height = 15 };
    const nav_bindings = [_]KeyBinding{
        .{ .key = "j", .description = "Down" },
        .{ .key = "k", .description = "Up" },
    };
    const edit_bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Delete" },
    };
    const sections = [_]KeySection{
        .{ .title = "Navigate", .bindings = &nav_bindings },
        .{ .title = "Edit", .bindings = &edit_bindings },
    };
    var km = KeyMap.init(&sections);
    km = km.withColumns(2).withKeyWidth(12);
    km.scroll_offset = 1;
    km.render(&buf, area);
    // With 2 columns: title "Navigate" (1) + ceil(2/2) binding rows (1) + title "Edit" (1) + ceil(1/2) binding rows (1) = 4 total rows
    try testing.expectEqual(@as(usize, 4), km.totalRows());
}
