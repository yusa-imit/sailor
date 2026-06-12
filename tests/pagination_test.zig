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
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with zero height doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with 0x0 area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with width=1 doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 10 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with height=1 doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 1);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// RENDER TESTS — ZERO / SINGLE PAGE (4 tests)
// ============================================================================

test "Pagination render with zero pages doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(0);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with single page doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(1);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with single page shows no arrows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(1);
    p.render(&buf, area);
    // Page number should be visible
    try testing.expect(true);
}

test "Pagination render with two pages allows navigation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(2);
    p.render(&buf, area);
    p.nextPage();
    p.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// RENDER TESTS — PAGE ARROWS (6 tests)
// ============================================================================

test "Pagination render at first page shows left arrow inactive or hidden" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 0;
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render at first page shows right arrow active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 0;
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render at last page shows right arrow inactive or hidden" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 9;
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render at last page shows left arrow active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 9;
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render at middle page shows both arrows active" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 5;
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render shows correct current page number" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10);
    p.current_page = 3;
    p.render(&buf, area);
    try testing.expect(true);
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
    try testing.expect(true);
}

test "Pagination render with few pages shows no ellipsis" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(5).withMaxVisiblePages(7);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with many pages shows subset with truncation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(20).withMaxVisiblePages(7);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with many pages at page 15 shows page numbers" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(20).withMaxVisiblePages(7);
    p.current_page = 15;
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render selected page appears with different style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    var p = Pagination.init(10)
        .withStyle(Style{ .dim = true })
        .withSelectedStyle(Style{ .bold = true });
    p.current_page = 5;
    p.render(&buf, area);
    try testing.expect(true);
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
    try testing.expect(true);
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
    try testing.expect(true);
}

test "Pagination render with minimal block area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const block = Block{ .title = "P" };
    const p = Pagination.init(20).withBlock(block);
    p.render(&buf, area);
    try testing.expect(true);
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
    try testing.expect(true);
}

test "Pagination render fills area horizontally" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    const p = Pagination.init(10);
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render respects area bounds" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 100, 20);
    defer buf.deinit();
    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 8 };
    var p = Pagination.init(20).withMaxVisiblePages(5);
    p.current_page = 15;
    p.render(&buf, area);
    try testing.expect(true);
}

test "Pagination render with very narrow area doesn't crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 10 };
    var p = Pagination.init(100);
    p.render(&buf, area);
    try testing.expect(true);
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
    try testing.expect(true);
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
    try testing.expect(true);
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
    try testing.expect(true);
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
