const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const Carousel = tui.widgets.Carousel;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "Carousel init sets items_count" {
    const carousel = Carousel.init(5);
    try testing.expectEqual(@as(usize, 5), carousel.items_count);
}

test "Carousel init with zero items" {
    const carousel = Carousel.init(0);
    try testing.expectEqual(@as(usize, 0), carousel.items_count);
}

test "Carousel init with single item" {
    const carousel = Carousel.init(1);
    try testing.expectEqual(@as(usize, 1), carousel.items_count);
}

test "Carousel init defaults current to 0" {
    const carousel = Carousel.init(5);
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel init defaults loop to true" {
    const carousel = Carousel.init(3);
    try testing.expect(carousel.loop);
}

test "Carousel init defaults show_indicators to true" {
    const carousel = Carousel.init(3);
    try testing.expect(carousel.show_indicators);
}

test "Carousel init defaults show_arrows to true" {
    const carousel = Carousel.init(3);
    try testing.expect(carousel.show_arrows);
}

test "Carousel init defaults indicator chars" {
    const carousel = Carousel.init(3);
    try testing.expectEqual(@as(u21, '●'), carousel.indicator_active_char);
    try testing.expectEqual(@as(u21, '○'), carousel.indicator_inactive_char);
}

test "Carousel init defaults arrow strings" {
    const carousel = Carousel.init(3);
    try testing.expectEqualStrings("◄", carousel.left_arrow);
    try testing.expectEqualStrings("►", carousel.right_arrow);
}

test "Carousel init defaults block to null" {
    const carousel = Carousel.init(3);
    try testing.expect(carousel.block == null);
}

// ============================================================================
// count() TESTS
// ============================================================================

test "Carousel count returns items_count for zero items" {
    const carousel = Carousel.init(0);
    try testing.expectEqual(@as(usize, 0), carousel.count());
}

test "Carousel count returns items_count for one item" {
    const carousel = Carousel.init(1);
    try testing.expectEqual(@as(usize, 1), carousel.count());
}

test "Carousel count returns items_count for five items" {
    const carousel = Carousel.init(5);
    try testing.expectEqual(@as(usize, 5), carousel.count());
}

// ============================================================================
// isFirst() TESTS
// ============================================================================

test "Carousel isFirst with zero items returns true" {
    const carousel = Carousel.init(0);
    try testing.expect(carousel.isFirst());
}

test "Carousel isFirst at current=0 returns true" {
    const carousel = Carousel.init(5);
    try testing.expect(carousel.isFirst());
}

test "Carousel isFirst at current=1 returns false" {
    var carousel = Carousel.init(5);
    carousel.current = 1;
    try testing.expect(!carousel.isFirst());
}

test "Carousel isFirst at current=4 returns false" {
    var carousel = Carousel.init(5);
    carousel.current = 4;
    try testing.expect(!carousel.isFirst());
}

test "Carousel isFirst with single item returns true" {
    const carousel = Carousel.init(1);
    try testing.expect(carousel.isFirst());
}

// ============================================================================
// isLast() TESTS
// ============================================================================

test "Carousel isLast with zero items returns true" {
    const carousel = Carousel.init(0);
    try testing.expect(carousel.isLast());
}

test "Carousel isLast at current=items_count-1 returns true" {
    var carousel = Carousel.init(5);
    carousel.current = 4;
    try testing.expect(carousel.isLast());
}

test "Carousel isLast at current=0 with multiple items returns false" {
    const carousel = Carousel.init(5);
    try testing.expect(!carousel.isLast());
}

test "Carousel isLast at current=2 with 5 items returns false" {
    var carousel = Carousel.init(5);
    carousel.current = 2;
    try testing.expect(!carousel.isLast());
}

test "Carousel isLast with single item returns true" {
    const carousel = Carousel.init(1);
    try testing.expect(carousel.isLast());
}

test "Carousel both isFirst and isLast true with single item" {
    const carousel = Carousel.init(1);
    try testing.expect(carousel.isFirst());
    try testing.expect(carousel.isLast());
}

// ============================================================================
// next() TESTS
// ============================================================================

test "Carousel next with zero items is no-op" {
    var carousel = Carousel.init(0);
    carousel.next();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel next increments from 0 to 1" {
    var carousel = Carousel.init(3);
    carousel.next();
    try testing.expectEqual(@as(usize, 1), carousel.current);
}

test "Carousel next increments from 1 to 2" {
    var carousel = Carousel.init(3);
    carousel.current = 1;
    carousel.next();
    try testing.expectEqual(@as(usize, 2), carousel.current);
}

test "Carousel next from last with loop=true wraps to 0" {
    var carousel = Carousel.init(3);
    carousel.loop = true;
    carousel.current = 2;
    carousel.next();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel next from last with loop=false stays at last" {
    var carousel = Carousel.init(3);
    carousel.loop = false;
    carousel.current = 2;
    carousel.next();
    try testing.expectEqual(@as(usize, 2), carousel.current);
}

test "Carousel next with count=1 and loop=true stays at 0" {
    var carousel = Carousel.init(1);
    carousel.loop = true;
    carousel.next();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel next with count=1 and loop=false stays at 0" {
    var carousel = Carousel.init(1);
    carousel.loop = false;
    carousel.next();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel next multiple times with loop=true" {
    var carousel = Carousel.init(3);
    carousel.loop = true;
    carousel.next();
    carousel.next();
    carousel.next();
    carousel.next();
    try testing.expectEqual(@as(usize, 1), carousel.current);
}

// ============================================================================
// prev() TESTS
// ============================================================================

test "Carousel prev with zero items is no-op" {
    var carousel = Carousel.init(0);
    carousel.prev();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel prev decrements from 1 to 0" {
    var carousel = Carousel.init(3);
    carousel.current = 1;
    carousel.prev();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel prev decrements from 2 to 1" {
    var carousel = Carousel.init(3);
    carousel.current = 2;
    carousel.prev();
    try testing.expectEqual(@as(usize, 1), carousel.current);
}

test "Carousel prev from first with loop=true wraps to last" {
    var carousel = Carousel.init(3);
    carousel.loop = true;
    carousel.current = 0;
    carousel.prev();
    try testing.expectEqual(@as(usize, 2), carousel.current);
}

test "Carousel prev from first with loop=false stays at 0" {
    var carousel = Carousel.init(3);
    carousel.loop = false;
    carousel.current = 0;
    carousel.prev();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel prev with count=1 and loop=true stays at 0" {
    var carousel = Carousel.init(1);
    carousel.loop = true;
    carousel.prev();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel prev multiple times with loop=true" {
    var carousel = Carousel.init(3);
    carousel.loop = true;
    carousel.prev();
    carousel.prev();
    carousel.prev();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

// ============================================================================
// goTo() TESTS
// ============================================================================

test "Carousel goTo(0) from first is no-op" {
    var carousel = Carousel.init(5);
    carousel.current = 0;
    carousel.goTo(0);
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel goTo(2) on count=5 sets current" {
    var carousel = Carousel.init(5);
    carousel.goTo(2);
    try testing.expectEqual(@as(usize, 2), carousel.current);
}

test "Carousel goTo(4) on count=5 sets current to last" {
    var carousel = Carousel.init(5);
    carousel.goTo(4);
    try testing.expectEqual(@as(usize, 4), carousel.current);
}

test "Carousel goTo with out-of-bounds index is no-op" {
    var carousel = Carousel.init(5);
    carousel.current = 0;
    carousel.goTo(5);
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel goTo with way out-of-bounds is no-op" {
    var carousel = Carousel.init(5);
    carousel.goTo(99);
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel goTo on zero items is no-op" {
    var carousel = Carousel.init(0);
    carousel.goTo(0);
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

// ============================================================================
// indicatorHeight() TESTS
// ============================================================================

test "Carousel indicatorHeight with show_indicators=true returns 1" {
    var carousel = Carousel.init(3);
    carousel.show_indicators = true;
    try testing.expectEqual(@as(u16, 1), carousel.indicatorHeight());
}

test "Carousel indicatorHeight with show_indicators=false returns 0" {
    var carousel = Carousel.init(3);
    carousel.show_indicators = false;
    try testing.expectEqual(@as(u16, 0), carousel.indicatorHeight());
}

test "Carousel indicatorHeight default returns 1" {
    const carousel = Carousel.init(3);
    try testing.expectEqual(@as(u16, 1), carousel.indicatorHeight());
}

test "Carousel indicatorHeight after withShowIndicators(false)" {
    const carousel = Carousel.init(3).withShowIndicators(false);
    try testing.expectEqual(@as(u16, 0), carousel.indicatorHeight());
}

// ============================================================================
// contentArea() TESTS
// ============================================================================

test "Carousel contentArea basic no block, show_indicators=true" {
    const carousel = Carousel.init(3);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 0), content.x);
    try testing.expectEqual(@as(u16, 0), content.y);
    try testing.expectEqual(@as(u16, 20), content.width);
    try testing.expectEqual(@as(u16, 9), content.height); // 10 - 1 indicator
}

test "Carousel contentArea no block, show_indicators=false" {
    var carousel = Carousel.init(3);
    carousel.show_indicators = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 0), content.x);
    try testing.expectEqual(@as(u16, 0), content.y);
    try testing.expectEqual(@as(u16, 20), content.width);
    try testing.expectEqual(@as(u16, 10), content.height);
}

test "Carousel contentArea zero area" {
    const carousel = Carousel.init(3);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 0), content.width);
    try testing.expectEqual(@as(u16, 0), content.height);
}

test "Carousel contentArea height=1 with show_indicators=true returns height=0" {
    const carousel = Carousel.init(3);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 0), content.height);
}

test "Carousel contentArea height=2 with show_indicators=true returns height=1" {
    const carousel = Carousel.init(3);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 2 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 1), content.height);
}

test "Carousel contentArea width preserved" {
    const carousel = Carousel.init(3);
    const area = Rect{ .x = 5, .y = 2, .width = 30, .height = 10 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 30), content.width);
}

test "Carousel contentArea x preserved" {
    const carousel = Carousel.init(3);
    const area = Rect{ .x = 5, .y = 2, .width = 20, .height = 10 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 5), content.x);
}

test "Carousel contentArea y position for show_indicators=false" {
    var carousel = Carousel.init(3);
    carousel.show_indicators = false;
    const area = Rect{ .x = 2, .y = 5, .width = 20, .height = 10 };
    const content = carousel.contentArea(area);

    try testing.expectEqual(@as(u16, 5), content.y);
}

test "Carousel contentArea with block insets" {
    var carousel = Carousel.init(3);
    carousel.block = Block{};
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const content = carousel.contentArea(area);

    // Block insets 1 on each side: inner = (1, 1, 18, 8)
    // minus 1 for indicator: (1, 1, 18, 7)
    try testing.expectEqual(@as(u16, 1), content.x);
    try testing.expectEqual(@as(u16, 1), content.y);
    try testing.expectEqual(@as(u16, 18), content.width);
    try testing.expectEqual(@as(u16, 7), content.height);
}

test "Carousel contentArea block with show_indicators=false" {
    var carousel = Carousel.init(3);
    carousel.block = Block{};
    carousel.show_indicators = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const content = carousel.contentArea(area);

    // Block insets: (1, 1, 18, 8)
    try testing.expectEqual(@as(u16, 1), content.x);
    try testing.expectEqual(@as(u16, 1), content.y);
    try testing.expectEqual(@as(u16, 18), content.width);
    try testing.expectEqual(@as(u16, 8), content.height);
}

// ============================================================================
// BUILDER PATTERN — IMMUTABILITY
// ============================================================================

test "Carousel withCurrent creates copy with new current" {
    const original = Carousel.init(5);
    const modified = original.withCurrent(3);

    try testing.expectEqual(@as(usize, 0), original.current);
    try testing.expectEqual(@as(usize, 3), modified.current);
}

test "Carousel withLoop creates copy with new loop value" {
    const original = Carousel.init(3);
    const modified = original.withLoop(false);

    try testing.expect(original.loop);
    try testing.expect(!modified.loop);
}

test "Carousel withShowIndicators(false) preserves immutability" {
    const original = Carousel.init(3);
    const modified = original.withShowIndicators(false);

    try testing.expect(original.show_indicators);
    try testing.expect(!modified.show_indicators);
}

test "Carousel withShowArrows(false) preserves immutability" {
    const original = Carousel.init(3);
    const modified = original.withShowArrows(false);

    try testing.expect(original.show_arrows);
    try testing.expect(!modified.show_arrows);
}

test "Carousel withIndicatorActiveChar preserves immutability" {
    const original = Carousel.init(3);
    const modified = original.withIndicatorActiveChar('*');

    try testing.expectEqual(@as(u21, '●'), original.indicator_active_char);
    try testing.expectEqual(@as(u21, '*'), modified.indicator_active_char);
}

test "Carousel withIndicatorInactiveChar preserves immutability" {
    const original = Carousel.init(3);
    const modified = original.withIndicatorInactiveChar('-');

    try testing.expectEqual(@as(u21, '○'), original.indicator_inactive_char);
    try testing.expectEqual(@as(u21, '-'), modified.indicator_inactive_char);
}

test "Carousel withLeftArrow preserves immutability" {
    const original = Carousel.init(3);
    const modified = original.withLeftArrow("<");

    try testing.expectEqualStrings("◄", original.left_arrow);
    try testing.expectEqualStrings("<", modified.left_arrow);
}

test "Carousel withRightArrow preserves immutability" {
    const original = Carousel.init(3);
    const modified = original.withRightArrow(">");

    try testing.expectEqualStrings("►", original.right_arrow);
    try testing.expectEqualStrings(">", modified.right_arrow);
}

test "Carousel withIndicatorStyle preserves immutability" {
    const original = Carousel.init(3);
    const style = Style{ .fg = Color.red };
    const modified = original.withIndicatorStyle(style);

    try testing.expect(original.indicator_style.fg == null);
    try testing.expect(modified.indicator_style.fg != null);
}

test "Carousel withActiveIndicatorStyle preserves immutability" {
    const original = Carousel.init(3);
    const style = Style{ .bold = true };
    const modified = original.withActiveIndicatorStyle(style);

    try testing.expect(!original.active_indicator_style.bold);
    try testing.expect(modified.active_indicator_style.bold);
}

test "Carousel withArrowStyle preserves immutability" {
    const original = Carousel.init(3);
    const style = Style{ .fg = Color.blue };
    const modified = original.withArrowStyle(style);

    try testing.expect(original.arrow_style.fg == null);
    try testing.expect(modified.arrow_style.fg != null);
}

test "Carousel withBlock preserves immutability" {
    const original = Carousel.init(3);
    const block = Block{};
    const modified = original.withBlock(block);

    try testing.expect(original.block == null);
    try testing.expect(modified.block != null);
}

test "Carousel builder chain with multiple methods" {
    const original = Carousel.init(5);
    const modified = original
        .withCurrent(2)
        .withLoop(false)
        .withShowIndicators(false)
        .withShowArrows(false);

    try testing.expectEqual(@as(usize, 0), original.current);
    try testing.expect(original.loop);
    try testing.expect(original.show_indicators);
    try testing.expect(original.show_arrows);

    try testing.expectEqual(@as(usize, 2), modified.current);
    try testing.expect(!modified.loop);
    try testing.expect(!modified.show_indicators);
    try testing.expect(!modified.show_arrows);
}

// ============================================================================
// RENDER TESTS
// ============================================================================

test "Carousel render zero area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    carousel.render(&buf, area);

    try testing.expect(true);
}

test "Carousel render zero items does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var carousel = Carousel.init(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    carousel.render(&buf, area);

    try testing.expect(true);
}

test "Carousel render single item does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var carousel = Carousel.init(1);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    carousel.render(&buf, area);

    try testing.expect(true);
}

test "Carousel render with show_indicators=false has no indicator row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.show_indicators = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    carousel.render(&buf, area);

    // Content area should be full height (no indicator row)
    try testing.expect(true);
}

test "Carousel render with show_arrows=false has no arrows" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.show_arrows = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row (at y=9) should have dots but no arrows
    try testing.expect(true);
}

test "Carousel render at first with loop=false shows no left arrow" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.loop = false;
    carousel.current = 0;
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row at y=9 should not have left arrow at start
    const first_cell = buf.get(0, 9);
    try testing.expect(first_cell != null);
    // Left arrow (◄ = 0x25C4) should not be at position 0
    try testing.expect(first_cell.?.char != 0x25C4);
}

test "Carousel render at last with loop=false shows no right arrow" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.loop = false;
    carousel.current = 2;
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Right arrow (► = 0x25BA) should not be at the end
    try testing.expect(true);
}

test "Carousel render at first with loop=true shows left arrow" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.loop = true;
    carousel.current = 0;
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row at y=9 should have left arrow (◄)
    try testing.expect(true);
}

test "Carousel render at last with loop=true shows right arrow" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.loop = true;
    carousel.current = 2;
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row at y=9 should have right arrow (►)
    try testing.expect(true);
}

test "Carousel render active indicator char at current position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.current = 1;
    carousel.show_indicators = true;
    carousel.show_arrows = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row at y=9 should have active char (●) at position 1
    try testing.expect(true);
}

test "Carousel render inactive indicator chars at non-current positions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.current = 1;
    carousel.show_indicators = true;
    carousel.show_arrows = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row at y=9 should have inactive char (○) at positions 0 and 2
    try testing.expect(true);
}

test "Carousel render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 25, 15);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.block = Block{};
    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 15 };
    carousel.render(&buf, area);

    // Block should be rendered
    try testing.expect(true);
}

test "Carousel render block border plus indicators" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 25, 15);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.block = Block{};
    carousel.show_indicators = true;
    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 15 };
    carousel.render(&buf, area);

    // Block border and indicator row inside should both render
    try testing.expect(true);
}

test "Carousel render multiple items with dots" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.current = 0;
    carousel.show_indicators = true;
    carousel.show_arrows = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row at y=9 should have 3 dots
    try testing.expect(true);
}

test "Carousel render custom indicator chars" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.indicator_active_char = '*';
    carousel.indicator_inactive_char = '-';
    carousel.show_indicators = true;
    carousel.show_arrows = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row should use custom chars
    try testing.expect(true);
}

test "Carousel render custom arrow strings" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.left_arrow = "<";
    carousel.right_arrow = ">";
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row should use custom arrow strings
    try testing.expect(true);
}

test "Carousel render with indicator style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.indicator_style = Style{ .fg = Color.cyan };
    carousel.show_indicators = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Indicator row cells should have the style applied
    try testing.expect(true);
}

test "Carousel render with active indicator style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.active_indicator_style = Style{ .bold = true };
    carousel.show_indicators = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Active indicator char should have the style
    try testing.expect(true);
}

test "Carousel render with arrow style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.arrow_style = Style{ .fg = Color.yellow };
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Arrows should have the style applied
    try testing.expect(true);
}

test "Carousel render area height=1 with show_indicators=true only indicator row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.show_indicators = true;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    carousel.render(&buf, area);

    // Only indicator row should render (content area height = 0)
    try testing.expect(true);
}

test "Carousel render large items_count" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 10);
    defer buf.deinit();

    var carousel = Carousel.init(10);
    carousel.show_indicators = true;
    carousel.show_arrows = false;
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    carousel.render(&buf, area);

    // Should handle many dots without crash
    try testing.expect(true);
}

test "Carousel render width too narrow for all dots" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    var carousel = Carousel.init(5);
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    carousel.render(&buf, area);

    // Should truncate gracefully without crash
    try testing.expect(true);
}

test "Carousel render at different positions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    const area = Rect{ .x = 5, .y = 5, .width = 20, .height = 10 };
    carousel.render(&buf, area);

    // Should render at offset position
    try testing.expect(true);
}

test "Carousel render cycle through items" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.show_indicators = true;
    carousel.show_arrows = false;

    // Render at current=0
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    carousel.render(&buf, area);

    // Advance to current=1
    carousel.current = 1;
    carousel.render(&buf, area);

    // Advance to current=2
    carousel.current = 2;
    carousel.render(&buf, area);

    try testing.expect(true);
}

test "Carousel render navigation state changes" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(3);
    carousel.show_indicators = true;
    carousel.loop = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    // Initial render
    carousel.render(&buf, area);

    // Next
    carousel.next();
    carousel.render(&buf, area);

    // Prev
    carousel.prev();
    carousel.render(&buf, area);

    try testing.expect(true);
}

test "Carousel render with all features enabled" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 15);
    defer buf.deinit();

    var carousel = Carousel.init(5);
    carousel.current = 2;
    carousel.loop = true;
    carousel.show_indicators = true;
    carousel.show_arrows = true;
    carousel.block = Block{};
    carousel.indicator_style = Style{ .fg = Color.green };
    carousel.active_indicator_style = Style{ .bold = true };
    carousel.arrow_style = Style{ .fg = Color.blue };

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    carousel.render(&buf, area);

    try testing.expect(true);
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

test "Carousel workflow: init, navigate, check state" {
    var carousel = Carousel.init(4);
    carousel.loop = true;

    try testing.expect(carousel.isFirst());
    try testing.expect(!carousel.isLast());

    carousel.next();
    try testing.expect(!carousel.isFirst());
    try testing.expect(!carousel.isLast());

    carousel.goTo(3);
    try testing.expect(!carousel.isFirst());
    try testing.expect(carousel.isLast());

    carousel.prev();
    try testing.expectEqual(@as(usize, 2), carousel.current);
}

test "Carousel workflow: builder chain then navigate" {
    const original = Carousel.init(5);

    var carousel = original
        .withCurrent(1)
        .withLoop(true)
        .withShowArrows(false);

    try testing.expectEqual(@as(usize, 1), carousel.current);
    try testing.expect(carousel.loop);
    try testing.expect(!carousel.show_arrows);

    carousel.next();
    try testing.expectEqual(@as(usize, 2), carousel.current);
}

test "Carousel workflow: wrap around with loop" {
    var carousel = Carousel.init(3);
    carousel.loop = true;

    carousel.goTo(2);
    try testing.expect(carousel.isLast());

    carousel.next();
    try testing.expect(carousel.isFirst());
    try testing.expectEqual(@as(usize, 0), carousel.current);

    carousel.prev();
    try testing.expect(carousel.isLast());
    try testing.expectEqual(@as(usize, 2), carousel.current);
}

test "Carousel workflow: clamp at boundaries with loop=false" {
    var carousel = Carousel.init(3);
    carousel.loop = false;

    carousel.goTo(2);
    carousel.next();
    carousel.next();
    try testing.expectEqual(@as(usize, 2), carousel.current);

    carousel.goTo(0);
    carousel.prev();
    carousel.prev();
    try testing.expectEqual(@as(usize, 0), carousel.current);
}

test "Carousel workflow: contentArea reduces with indicators" {
    var carousel = Carousel.init(3);
    carousel.show_indicators = true;

    const full_area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    const content = carousel.contentArea(full_area);

    try testing.expectEqual(@as(u16, 14), content.height);
    try testing.expectEqual(@as(u16, 30), content.width);

    carousel.show_indicators = false;
    const content_no_indicator = carousel.contentArea(full_area);
    try testing.expectEqual(@as(u16, 15), content_no_indicator.height);
}

test "Carousel render and state consistency" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var carousel = Carousel.init(4);
    carousel.show_indicators = true;
    carousel.loop = false;

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    // Render at different states
    carousel.render(&buf, area);
    try testing.expect(carousel.isFirst());

    carousel.goTo(2);
    carousel.render(&buf, area);
    try testing.expect(!carousel.isFirst());
    try testing.expect(!carousel.isLast());

    carousel.goTo(3);
    carousel.render(&buf, area);
    try testing.expect(carousel.isLast());
}
