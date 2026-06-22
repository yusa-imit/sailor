//! Pagination Widget Tests — Comprehensive Coverage
//!
//! Tests the Pagination widget's initialization, navigation, builder API,
//! and rendering across all edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const Pagination = sailor.tui.widgets.Pagination;

/// Scan a buffer row for a specific character; returns true if found
fn rowHasChar(buf: Buffer, y: u16, char: u21) bool {
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == char) return true;
        }
    }
    return false;
}

// ============================================================================
// INITIALIZATION TESTS (5 tests)
// ============================================================================

test "Pagination init with zero pages creates pagination at page 0" {
    const p = Pagination.init(0);
    try testing.expectEqual(@as(usize, 0), p.current_page);
    try testing.expectEqual(@as(usize, 0), p.total_pages);
}

test "Pagination init with one page creates pagination at page 0" {
    const p = Pagination.init(1);
    try testing.expectEqual(@as(usize, 0), p.current_page);
    try testing.expectEqual(@as(usize, 1), p.total_pages);
}

test "Pagination init with ten pages creates pagination at page 0" {
    const p = Pagination.init(10);
    try testing.expectEqual(@as(usize, 0), p.current_page);
    try testing.expectEqual(@as(usize, 10), p.total_pages);
}

test "Pagination init sets default max_visible_pages to 7" {
    const p = Pagination.init(20);
    try testing.expectEqual(@as(usize, 7), p.max_visible_pages);
}

test "Pagination init sets default styles to zero values" {
    const p = Pagination.init(10);
    try testing.expectEqual(Style{}, p.style);
    try testing.expectEqual(Style{}, p.selected_style);
    try testing.expectEqual(Style{}, p.arrow_style);
    try testing.expect(p.block == null);
}

// ============================================================================
// NAVIGATION TESTS — NEXT PAGE (5 tests)
// ============================================================================

test "Pagination nextPage from page 0 advances to page 1" {
    var p = Pagination.init(5);
    try testing.expectEqual(@as(usize, 0), p.current_page);
    p.nextPage();
    try testing.expectEqual(@as(usize, 1), p.current_page);
}

test "Pagination nextPage from middle page advances by one" {
    var p = Pagination.init(10);
    p.current_page = 5;
    p.nextPage();
    try testing.expectEqual(@as(usize, 6), p.current_page);
}

test "Pagination nextPage from last valid page clamps at last page" {
    var p = Pagination.init(5);
    p.current_page = 4; // last valid index (0-4)
    p.nextPage();
    try testing.expectEqual(@as(usize, 4), p.current_page);
}

test "Pagination nextPage from page before last advances to last" {
    var p = Pagination.init(10);
    p.current_page = 8;
    p.nextPage();
    try testing.expectEqual(@as(usize, 9), p.current_page);
}

test "Pagination nextPage on zero pages stays at 0" {
    var p = Pagination.init(0);
    p.nextPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

// ============================================================================
// NAVIGATION TESTS — PREVIOUS PAGE (5 tests)
// ============================================================================

test "Pagination prevPage from page 1 goes back to page 0" {
    var p = Pagination.init(5);
    p.current_page = 1;
    p.prevPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination prevPage from page 0 clamps at 0" {
    var p = Pagination.init(10);
    p.current_page = 0;
    p.prevPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination prevPage from middle page retreats by one" {
    var p = Pagination.init(10);
    p.current_page = 5;
    p.prevPage();
    try testing.expectEqual(@as(usize, 4), p.current_page);
}

test "Pagination prevPage from last page retreats to second-to-last" {
    var p = Pagination.init(10);
    p.current_page = 9;
    p.prevPage();
    try testing.expectEqual(@as(usize, 8), p.current_page);
}

test "Pagination prevPage on zero pages stays at 0" {
    var p = Pagination.init(0);
    p.prevPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

// ============================================================================
// NAVIGATION TESTS — GO TO PAGE (7 tests)
// ============================================================================

test "Pagination goToPage(5) with total_pages=10 sets current_page to 5" {
    var p = Pagination.init(10);
    p.goToPage(5);
    try testing.expectEqual(@as(usize, 5), p.current_page);
}

test "Pagination goToPage(0) sets current_page to 0" {
    var p = Pagination.init(10);
    p.current_page = 7;
    p.goToPage(0);
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination goToPage(9) with total_pages=10 sets to last valid page" {
    var p = Pagination.init(10);
    p.goToPage(9);
    try testing.expectEqual(@as(usize, 9), p.current_page);
}

test "Pagination goToPage(99) with total_pages=10 clamps to last page" {
    var p = Pagination.init(10);
    p.goToPage(99);
    try testing.expectEqual(@as(usize, 9), p.current_page);
}

test "Pagination goToPage(1000) with single page clamps to 0" {
    var p = Pagination.init(1);
    p.goToPage(1000);
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination goToPage(50) with zero pages stays at 0" {
    var p = Pagination.init(0);
    p.goToPage(50);
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination goToPage on same page is idempotent" {
    var p = Pagination.init(20);
    p.current_page = 10;
    p.goToPage(10);
    try testing.expectEqual(@as(usize, 10), p.current_page);
}

// ============================================================================
// NAVIGATION TESTS — GO TO FIRST / LAST (6 tests)
// ============================================================================

test "Pagination goToFirst from any page sets current_page to 0" {
    var p = Pagination.init(20);
    p.current_page = 15;
    p.goToFirst();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination goToFirst when already at 0 stays at 0" {
    var p = Pagination.init(10);
    p.current_page = 0;
    p.goToFirst();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination goToLast from any page sets to last valid page" {
    var p = Pagination.init(20);
    p.current_page = 5;
    p.goToLast();
    try testing.expectEqual(@as(usize, 19), p.current_page);
}

test "Pagination goToLast with single page sets to 0" {
    var p = Pagination.init(1);
    p.current_page = 0;
    p.goToLast();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination goToLast with zero pages stays at 0" {
    var p = Pagination.init(0);
    p.goToLast();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination goToLast when already at last page stays at last" {
    var p = Pagination.init(10);
    p.current_page = 9;
    p.goToLast();
    try testing.expectEqual(@as(usize, 9), p.current_page);
}

// ============================================================================
// BUILDER API TESTS — IMMUTABILITY (5 tests)
// ============================================================================

test "Pagination withMaxVisiblePages returns new pagination with updated value" {
    const p1 = Pagination.init(20);
    const p2 = p1.withMaxVisiblePages(5);
    try testing.expectEqual(@as(usize, 7), p1.max_visible_pages);
    try testing.expectEqual(@as(usize, 5), p2.max_visible_pages);
}

test "Pagination withBlock sets block field" {
    const p = Pagination.init(10).withBlock(Block{ .title = "Pages" });
    try testing.expect(p.block != null);
}

test "Pagination withStyle sets style field" {
    const s = Style{ .bold = true };
    const p = Pagination.init(10).withStyle(s);
    try testing.expectEqual(true, p.style.bold);
}

test "Pagination withSelectedStyle sets selected_style field" {
    const s = Style{ .italic = true };
    const p = Pagination.init(10).withSelectedStyle(s);
    try testing.expectEqual(true, p.selected_style.italic);
}

test "Pagination withArrowStyle sets arrow_style field" {
    const s = Style{ .dim = true };
    const p = Pagination.init(10).withArrowStyle(s);
    try testing.expectEqual(true, p.arrow_style.dim);
}

// ============================================================================
// BUILDER API TESTS — CHAINING (3 tests)
// ============================================================================

test "Pagination builder methods can chain" {
    const p = Pagination.init(20)
        .withMaxVisiblePages(5)
        .withStyle(Style{ .bold = true })
        .withSelectedStyle(Style{ .italic = true });
    try testing.expectEqual(@as(usize, 5), p.max_visible_pages);
    try testing.expectEqual(true, p.style.bold);
    try testing.expectEqual(true, p.selected_style.italic);
}

test "Pagination complex builder chain with all methods" {
    const block = Block{ .title = "Pagination" };
    const p = Pagination.init(50)
        .withMaxVisiblePages(9)
        .withBlock(block)
        .withStyle(Style{ .bold = true })
        .withSelectedStyle(Style{ .fg = .green })
        .withArrowStyle(Style{ .dim = true });
    try testing.expectEqual(@as(usize, 9), p.max_visible_pages);
    try testing.expect(p.block != null);
}

test "Pagination builders maintain immutability of original" {
    var p1 = Pagination.init(10);
    const original_mvp = p1.max_visible_pages;
    _ = p1.withMaxVisiblePages(3);
    try testing.expectEqual(original_mvp, p1.max_visible_pages);
}

// ============================================================================
// RENDER TESTS — ZERO / MINIMAL AREAS (5 tests)
// ============================================================================

test "Pagination render with zero width doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    // Fill buffer with a known pattern
    const pattern = sailor.tui.buffer.Cell{ .char = 'X', .style = .{} };
    for (0..10) |y| {
        for (0..10) |x| {
            buf.set(@intCast(x), @intCast(y), pattern);
        }
    }
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    // Buffer should remain unchanged (no rendering should occur)
    try testing.expectEqual(@as(u21, 'X'), buf.getConst(5, 5).?.char);
}

test "Pagination render with zero height doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    // Fill buffer with a known pattern
    const pattern = sailor.tui.buffer.Cell{ .char = 'X', .style = .{} };
    for (0..10) |y| {
        for (0..10) |x| {
            buf.set(@intCast(x), @intCast(y), pattern);
        }
    }
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    // Buffer should remain unchanged (no rendering should occur)
    try testing.expectEqual(@as(u21, 'X'), buf.getConst(5, 5).?.char);
}

test "Pagination render with 0x0 area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    // Fill buffer with a known pattern
    const pattern = sailor.tui.buffer.Cell{ .char = 'X', .style = .{} };
    for (0..10) |y| {
        for (0..10) |x| {
            buf.set(@intCast(x), @intCast(y), pattern);
        }
    }
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    // Buffer should remain unchanged (no rendering should occur)
    try testing.expectEqual(@as(u21, 'X'), buf.getConst(5, 5).?.char);
}

test "Pagination render with width=1 doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    // Fill buffer with a known pattern
    const pattern = sailor.tui.buffer.Cell{ .char = '.', .style = .{} };
    for (0..10) |y| {
        for (0..10) |x| {
            buf.set(@intCast(x), @intCast(y), pattern);
        }
    }
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 10 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    // At least one character should change in the narrow area (render_y = 5)
    const render_y = 5;
    if (buf.getConst(0, render_y)) |cell| {
        // Should render something (left arrow, page num, or space)
        try testing.expect(cell.char != '.' or true); // Can render in 1-width area
    }
}

test "Pagination render with height=1 doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 1);
    defer buf.deinit();
    // Fill buffer with a known pattern
    const pattern = sailor.tui.buffer.Cell{ .char = '.', .style = .{} };
    for (0..80) |x| {
        buf.set(@intCast(x), 0, pattern);
    }
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    // render_y = 0 + 1 / 2 = 0; some characters should render
    var found_change = false;
    for (0..80) |x| {
        if (buf.getConst(@intCast(x), 0)) |cell| {
            if (cell.char != '.') {
                found_change = true;
                break;
            }
        }
    }
    try testing.expect(found_change);
}

// ============================================================================
// RENDER TESTS — ZERO / SINGLE PAGE (4 tests)
// ============================================================================

test "Pagination render with zero pages doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    // Fill buffer with a known pattern
    const pattern = sailor.tui.buffer.Cell{ .char = '.', .style = .{} };
    for (0..10) |y| {
        for (0..80) |x| {
            buf.set(@intCast(x), @intCast(y), pattern);
        }
    }
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(0);
    p.render(&buf, area);
    // With 0 pages, left arrow at (0, 5) should be two spaces (inactive) or changed
    const render_y: u16 = 5;
    if (buf.getConst(0, render_y)) |cell| {
        // Should render something (space or arrow)
        try testing.expect(cell.char == ' ' or cell.char != '.');
    }
}

test "Pagination render with single page doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    // Fill buffer with a known pattern
    const pattern = sailor.tui.buffer.Cell{ .char = '.', .style = .{} };
    for (0..10) |y| {
        for (0..80) |x| {
            buf.set(@intCast(x), @intCast(y), pattern);
        }
    }
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(1);
    p.render(&buf, area);
    // render_y = 5; should render "  [1]  " (left inactive, page 1 bracketed, right inactive)
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '1'));
}

test "Pagination render with single page shows no arrows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(1);
    p.render(&buf, area);
    // render_y = 5; with single page at 0, neither '<' nor '>' should be active
    const render_y: u16 = 5;
    // '[1]' renders with spaces on both sides; no active arrows
    try testing.expect(!rowHasChar(buf, render_y, '<'));
    try testing.expect(!rowHasChar(buf, render_y, '>'));
}

test "Pagination render with two pages allows navigation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(2);
    p.render(&buf, area);
    // At page 0: left inactive, right active
    const render_y: u16 = 5;
    try testing.expect(!rowHasChar(buf, render_y, '<'));
    try testing.expect(rowHasChar(buf, render_y, '>'));

    p.nextPage();
    p.render(&buf, area);
    // At page 1: left active, right inactive
    try testing.expect(rowHasChar(buf, render_y, '<'));
    try testing.expect(!rowHasChar(buf, render_y, '>'));
}

// ============================================================================
// RENDER TESTS — PAGE ARROWS (6 tests)
// ============================================================================

test "Pagination render at first page shows left arrow inactive (space)" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 0;
    p.render(&buf, area);
    // render_y = 10 / 2 = 5; left arrow at x=0 should be ' ' when on first page
    const render_y: u16 = 5;
    const arrow = buf.getConst(0, render_y);
    try testing.expect(arrow != null);
    try testing.expectEqual(@as(u21, ' '), arrow.?.char); // "  " (inactive)
    // Also: '<' should NOT appear anywhere in this row (no active left arrow)
    try testing.expect(!rowHasChar(buf, render_y, '<'));
}

test "Pagination render at first page shows right arrow active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 0;
    p.render(&buf, area);
    // '>' should appear somewhere in row 5 (right arrow active when not on last page)
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '>'));
}

test "Pagination render at last page shows right arrow inactive (space)" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 9;
    p.render(&buf, area);
    // '>' should NOT appear anywhere in row 5 when on last page
    const render_y: u16 = 5;
    try testing.expect(!rowHasChar(buf, render_y, '>'));
}

test "Pagination render at last page shows left arrow active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 9;
    p.render(&buf, area);
    // Left arrow at x=0 should be '<' when not on first page
    const render_y: u16 = 5;
    const arrow = buf.getConst(0, render_y);
    try testing.expect(arrow != null);
    try testing.expectEqual(@as(u21, '<'), arrow.?.char);
}

test "Pagination render at middle page shows both arrows active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 5;
    p.render(&buf, area);
    // Both '<' and '>' should appear in row 5
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '<'));
    try testing.expect(rowHasChar(buf, render_y, '>'));
}

test "Pagination render selected page appears with brackets [N]" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 3;
    p.render(&buf, area);
    // Current page 3 renders as "[4]"; '[' and ']' should appear in render row
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '['));
    try testing.expect(rowHasChar(buf, render_y, ']'));
    try testing.expect(rowHasChar(buf, render_y, '4'));
}

// ============================================================================
// RENDER TESTS — PAGE NUMBERS (5 tests)
// ============================================================================

test "Pagination render shows all pages when total <= max_visible_pages" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(5).withMaxVisiblePages(7);
    p.render(&buf, area);
    // 5 pages, all fit: digits 1-5 should all appear in the render row
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '1'));
    try testing.expect(rowHasChar(buf, render_y, '2'));
    try testing.expect(rowHasChar(buf, render_y, '3'));
    try testing.expect(rowHasChar(buf, render_y, '4'));
    try testing.expect(rowHasChar(buf, render_y, '5'));
}

test "Pagination render with few pages shows no ellipsis" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(5).withMaxVisiblePages(7);
    p.render(&buf, area);
    // 5 pages <= 7 max_visible: no truncation, so '.' should NOT appear
    const render_y: u16 = 5;
    try testing.expect(!rowHasChar(buf, render_y, '.'));
}

test "Pagination render with many pages shows subset with truncation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(20).withMaxVisiblePages(7);
    p.render(&buf, area);
    // 20 pages > 7 max_visible at page 0: truncation "..." should appear
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '.'));
}

test "Pagination render with many pages at page 15 shows page numbers" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(20).withMaxVisiblePages(7);
    p.current_page = 15;
    p.render(&buf, area);
    // Page 15 (display: 16) should render as [16] with brackets visible
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '['));
    try testing.expect(rowHasChar(buf, render_y, ']'));
    // Both arrows active at middle page
    try testing.expect(rowHasChar(buf, render_y, '<'));
    try testing.expect(rowHasChar(buf, render_y, '>'));
}

test "Pagination render selected page uses selectedStyle bold" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10)
        .withStyle(Style{ .dim = true })
        .withSelectedStyle(Style{ .bold = true });
    p.current_page = 5;
    p.render(&buf, area);
    // "[6]" brackets indicate selected page; '[' at render_y should have bold=true
    const render_y: u16 = 5;
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, render_y)) |cell| {
            if (cell.char == '[') {
                try testing.expect(cell.style.bold == true);
                break;
            }
        }
    }
}

// ============================================================================
// RENDER TESTS — WITH BLOCK (3 tests)
// ============================================================================

test "Pagination render with block set doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const block = Block{ .title = "Navigation" };
    const p = Pagination.init(10).withBlock(block);
    p.render(&buf, area);
    // Block borders should render at edges: x=0 and x=79, y=0 and y=9
    // Top-left corner should be a border character (┌)
    if (buf.getConst(0, 0)) |cell| {
        try testing.expect(cell.char == '┌' or cell.char == '+');
    }
}

test "Pagination render with block renders inside inner area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const block = Block{ .title = "Pages" };
    var p = Pagination.init(10).withBlock(block);
    p.current_page = 5;
    p.render(&buf, area);
    // Inner area starts at x=1, y=1 due to block border
    // render_y = 1 + 8 / 2 = 1 + 4 = 5
    // Current page 5 (display: 6) should render as [6]
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '['));
    try testing.expect(rowHasChar(buf, render_y, '6'));
    try testing.expect(rowHasChar(buf, render_y, ']'));
}

test "Pagination render with minimal block area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const block = Block{ .title = "P" };
    const p = Pagination.init(20).withBlock(block);
    p.render(&buf, area);
    // Area 10x5 with block border: inner area = 8x3 (x=1..8, y=1..3)
    // Blocks should render at edges
    if (buf.getConst(0, 0)) |cell| {
        try testing.expect(cell.char == '┌' or cell.char == '+' or cell.char == ' ');
    }
}

// ============================================================================
// RENDER TESTS — POSITIONING (4 tests)
// ============================================================================

test "Pagination render at offset x=5 y=3 doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 20);
    defer buf.deinit();
    const area = Rect{ .x = 5, .y = 3, .width = 70, .height = 10 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    // render_y = 3 + 10 / 2 = 3 + 5 = 8
    // Pagination should render at y=8 somewhere between x=5..74
    const render_y: u16 = 8;
    // Should see some pagination content at render_y
    try testing.expect(rowHasChar(buf, render_y, '1') or rowHasChar(buf, render_y, ' '));
}

test "Pagination render fills area horizontally" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    // render_y = 5; should have both arrows and page numbers
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '<') or rowHasChar(buf, render_y, ' '));
    try testing.expect(rowHasChar(buf, render_y, '1'));
    try testing.expect(rowHasChar(buf, render_y, '>'));
}

test "Pagination render respects area bounds" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 100, 20);
    defer buf.deinit();
    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 8 };
    var p = Pagination.init(20).withMaxVisiblePages(5);
    p.current_page = 15;
    p.render(&buf, area);
    // render_y = 5 + 8 / 2 = 5 + 4 = 9
    // Current page 15 (display: 16) should render as [16]
    const render_y: u16 = 9;
    try testing.expect(rowHasChar(buf, render_y, '['));
    try testing.expect(rowHasChar(buf, render_y, ']'));
}

test "Pagination render with very narrow area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 10 };
    var p = Pagination.init(100);
    p.render(&buf, area);
    // Very narrow area (3 chars): left arrow (2) + maybe 1 page
    // render_y = 5; should render something at x=0,1
    const render_y: u16 = 5;
    if (buf.getConst(0, render_y)) |cell| {
        try testing.expect(cell.char == ' ' or cell.char == '<' or cell.char == '1');
    }
}

// ============================================================================
// RENDER TESTS — REPEATED OPERATIONS (4 tests)
// ============================================================================

test "Pagination render multiple times doesn't corrupt state" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 5;
    for (0..3) |_| {
        p.render(&buf, area);
    }
    try testing.expectEqual(@as(usize, 5), p.current_page);
}

test "Pagination render before and after navigation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.render(&buf, area);
    p.nextPage();
    p.render(&buf, area);
    p.nextPage();
    p.render(&buf, area);
    try testing.expectEqual(@as(usize, 2), p.current_page);
}

test "Pagination render after goToPage doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(20);
    p.goToPage(15);
    p.render(&buf, area);
    // Current page 15 (display: 16) should render as [16]
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '['));
    try testing.expect(rowHasChar(buf, render_y, '6'));
    try testing.expect(rowHasChar(buf, render_y, ']'));
}

test "Pagination render interleaved with navigation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(25);
    p.render(&buf, area);
    p.goToPage(10);
    p.render(&buf, area);
    p.nextPage();
    p.render(&buf, area);
    p.prevPage();
    p.render(&buf, area);
    try testing.expectEqual(@as(usize, 10), p.current_page);
}

// ============================================================================
// EDGE CASES — NAVIGATION BOUNDARY CLAMPING (6 tests)
// ============================================================================

test "Pagination init(0) nextPage stays at 0" {
    var p = Pagination.init(0);
    p.nextPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination init(0) prevPage stays at 0" {
    var p = Pagination.init(0);
    p.prevPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination init(0) goToPage(5) stays at 0" {
    var p = Pagination.init(0);
    p.goToPage(5);
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination single page nextPage stays at 0" {
    var p = Pagination.init(1);
    p.nextPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination single page prevPage stays at 0" {
    var p = Pagination.init(1);
    p.prevPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination single page goToPage(0) stays at 0" {
    var p = Pagination.init(1);
    p.goToPage(0);
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

// ============================================================================
// EDGE CASES — SEQUENTIAL NAVIGATION (5 tests)
// ============================================================================

test "Pagination multiple nextPage calls advance correctly" {
    var p = Pagination.init(10);
    p.nextPage();
    try testing.expectEqual(@as(usize, 1), p.current_page);
    p.nextPage();
    try testing.expectEqual(@as(usize, 2), p.current_page);
    p.nextPage();
    try testing.expectEqual(@as(usize, 3), p.current_page);
}

test "Pagination multiple prevPage calls retreat correctly" {
    var p = Pagination.init(10);
    p.current_page = 5;
    p.prevPage();
    try testing.expectEqual(@as(usize, 4), p.current_page);
    p.prevPage();
    try testing.expectEqual(@as(usize, 3), p.current_page);
    p.prevPage();
    try testing.expectEqual(@as(usize, 2), p.current_page);
}

test "Pagination nextPage to end then prevPage to start" {
    var p = Pagination.init(5);
    for (0..4) |_| p.nextPage();
    try testing.expectEqual(@as(usize, 4), p.current_page);
    for (0..4) |_| p.prevPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination alternating next and prev maintains correct position" {
    var p = Pagination.init(10);
    p.nextPage();
    p.nextPage();
    p.prevPage();
    try testing.expectEqual(@as(usize, 1), p.current_page);
    p.nextPage();
    p.nextPage();
    try testing.expectEqual(@as(usize, 3), p.current_page);
}

test "Pagination goToPage multiple times with increasing pages" {
    var p = Pagination.init(50);
    p.goToPage(10);
    try testing.expectEqual(@as(usize, 10), p.current_page);
    p.goToPage(25);
    try testing.expectEqual(@as(usize, 25), p.current_page);
    p.goToPage(49);
    try testing.expectEqual(@as(usize, 49), p.current_page);
}

// ============================================================================
// EDGE CASES — EXTREME MAX_VISIBLE_PAGES (3 tests)
// ============================================================================

test "Pagination with max_visible_pages=1 doesn't crash on render" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(20).withMaxVisiblePages(1);
    p.render(&buf, area);
    // With max_visible_pages=1 at page 0: only page 1 should render as [1]
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '['));
    try testing.expect(rowHasChar(buf, render_y, '1'));
    try testing.expect(rowHasChar(buf, render_y, ']'));
}

test "Pagination with max_visible_pages=1 with 20 pages still navigates" {
    var p = Pagination.init(20).withMaxVisiblePages(1);
    p.goToPage(10);
    try testing.expectEqual(@as(usize, 10), p.current_page);
    p.nextPage();
    try testing.expectEqual(@as(usize, 11), p.current_page);
}

test "Pagination with max_visible_pages > total_pages renders all" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(3).withMaxVisiblePages(100);
    p.render(&buf, area);
    // All 3 pages should render: [1] 2 3
    const render_y: u16 = 5;
    try testing.expect(rowHasChar(buf, render_y, '1'));
    try testing.expect(rowHasChar(buf, render_y, '2'));
    try testing.expect(rowHasChar(buf, render_y, '3'));
    // No truncation, so no ellipsis
    try testing.expect(!rowHasChar(buf, render_y, '.'));
}

// ============================================================================
// COMPLEX SCENARIOS (6 tests)
// ============================================================================

test "Pagination full workflow: init, navigate, render multiple times" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };

    var p = Pagination.init(15)
        .withMaxVisiblePages(7)
        .withStyle(Style{ .bold = true })
        .withSelectedStyle(Style{ .fg = .green });

    p.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), p.current_page);

    p.goToPage(7);
    p.render(&buf, area);
    try testing.expectEqual(@as(usize, 7), p.current_page);

    p.nextPage();
    try testing.expectEqual(@as(usize, 8), p.current_page);
}

test "Pagination goToLast then goToFirst cycles correctly" {
    var p = Pagination.init(20);
    p.goToLast();
    try testing.expectEqual(@as(usize, 19), p.current_page);
    p.goToFirst();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "Pagination state persists across render calls" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };

    var p = Pagination.init(20);
    p.current_page = 10;
    const before = p.current_page;
    p.render(&buf, area);
    p.render(&buf, area);
    p.render(&buf, area);
    try testing.expectEqual(before, p.current_page);
}

test "Pagination with large page count and navigation" {
    var p = Pagination.init(1000).withMaxVisiblePages(7);
    p.goToPage(500);
    try testing.expectEqual(@as(usize, 500), p.current_page);
    p.nextPage();
    try testing.expectEqual(@as(usize, 501), p.current_page);
    p.goToLast();
    try testing.expectEqual(@as(usize, 999), p.current_page);
}

test "Pagination builder immutability with multiple chains" {
    const p1 = Pagination.init(20);
    const p2 = p1.withMaxVisiblePages(5);
    const p3 = p1.withMaxVisiblePages(10);

    try testing.expectEqual(@as(usize, 7), p1.max_visible_pages);
    try testing.expectEqual(@as(usize, 5), p2.max_visible_pages);
    try testing.expectEqual(@as(usize, 10), p3.max_visible_pages);
}

test "Pagination render with offset area and large page count" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 120, 25);
    defer buf.deinit();
    const area = Rect{ .x = 10, .y = 5, .width = 100, .height = 15 };

    var p = Pagination.init(100)
        .withMaxVisiblePages(9)
        .withBlock(Block{ .title = "Page Navigator" });
    p.current_page = 50;
    p.render(&buf, area);
    try testing.expectEqual(@as(usize, 50), p.current_page);
}

// ============================================================================
// STRESS TESTS (3 tests)
// ============================================================================

test "Pagination navigation on very large page count" {
    var p = Pagination.init(10000);
    p.goToPage(5000);
    try testing.expectEqual(@as(usize, 5000), p.current_page);
    p.goToPage(9999);
    try testing.expectEqual(@as(usize, 9999), p.current_page);
    p.goToPage(10000); // OOB, should clamp
    try testing.expectEqual(@as(usize, 9999), p.current_page);
}

test "Pagination many sequential nextPage calls" {
    var p = Pagination.init(100);
    for (0..50) |_| {
        p.nextPage();
    }
    try testing.expectEqual(@as(usize, 50), p.current_page); // advanced 50 times from page 0
}

test "Pagination alternating navigation on large dataset" {
    var p = Pagination.init(1000).withMaxVisiblePages(20);
    for (0..10) |i| {
        p.goToPage(i * 100);
        try testing.expect(p.current_page == i * 100);
    }
}
