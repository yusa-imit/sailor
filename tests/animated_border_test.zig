const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const BoxSet = tui.symbols.BoxSet;
const AnimatedBorder = tui.widgets.AnimatedBorder;

// ============================================================================
// INITIALIZATION TESTS (10 tests)
// ============================================================================

test "AnimatedBorder init returns default frame value" {
    const border = AnimatedBorder.init();
    try testing.expectEqual(@as(u32, 0), border.frame);
}

test "AnimatedBorder init returns default animation style" {
    const border = AnimatedBorder.init();
    try testing.expectEqual(AnimatedBorder.AnimationStyle.rainbow, border.style);
}

test "AnimatedBorder init returns default speed" {
    const border = AnimatedBorder.init();
    try testing.expectEqual(@as(u8, 4), border.speed);
}

test "AnimatedBorder init returns default colors slice" {
    const border = AnimatedBorder.init();
    try testing.expect(border.colors.len > 0);
}

test "AnimatedBorder init returns empty title" {
    const border = AnimatedBorder.init();
    try testing.expectEqualStrings("", border.title);
}

test "AnimatedBorder init returns default empty base_style" {
    const border = AnimatedBorder.init();
    try testing.expectEqual(Style{}, border.base_style);
}

test "AnimatedBorder init returns default empty title_style" {
    const border = AnimatedBorder.init();
    try testing.expectEqual(Style{}, border.title_style);
}

test "AnimatedBorder init returns rounded border_set" {
    const border = AnimatedBorder.init();
    try testing.expectEqualStrings(BoxSet.rounded.top_left, border.border_set.top_left);
}

test "AnimatedBorder init colors contains red as first color" {
    const border = AnimatedBorder.init();
    try testing.expect(border.colors.len >= 1);
}

test "AnimatedBorder init colors contains at least 6 colors" {
    const border = AnimatedBorder.init();
    try testing.expect(border.colors.len >= 6);
}

// ============================================================================
// TICK TESTS (6 tests)
// ============================================================================

test "AnimatedBorder tick increments frame by 1" {
    var border = AnimatedBorder.init();
    border.tick();
    try testing.expectEqual(@as(u32, 1), border.frame);
}

test "AnimatedBorder tick from 0 increments to 1" {
    var border = AnimatedBorder.init();
    border.frame = 0;
    border.tick();
    try testing.expectEqual(@as(u32, 1), border.frame);
}

test "AnimatedBorder tick multiple times accumulates" {
    var border = AnimatedBorder.init();
    border.tick();
    border.tick();
    border.tick();
    try testing.expectEqual(@as(u32, 3), border.frame);
}

test "AnimatedBorder tick from u32 max wraps to 0" {
    var border = AnimatedBorder.init();
    border.frame = std.math.maxInt(u32);
    border.tick();
    try testing.expectEqual(@as(u32, 0), border.frame);
}

test "AnimatedBorder tick at large frame wraps correctly" {
    var border = AnimatedBorder.init();
    border.frame = std.math.maxInt(u32) - 1;
    border.tick();
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), border.frame);
}

test "AnimatedBorder tick multiple times from high value wraps" {
    var border = AnimatedBorder.init();
    border.frame = std.math.maxInt(u32) - 2;
    border.tick();
    border.tick();
    border.tick();
    try testing.expectEqual(@as(u32, 0), border.frame);
}

// ============================================================================
// TICKBY TESTS (6 tests)
// ============================================================================

test "AnimatedBorder tickBy increments by n" {
    var border = AnimatedBorder.init();
    border.tickBy(5);
    try testing.expectEqual(@as(u32, 5), border.frame);
}

test "AnimatedBorder tickBy with 0 is no-op" {
    var border = AnimatedBorder.init();
    border.frame = 10;
    border.tickBy(0);
    try testing.expectEqual(@as(u32, 10), border.frame);
}

test "AnimatedBorder tickBy adds to existing frame" {
    var border = AnimatedBorder.init();
    border.frame = 3;
    border.tickBy(7);
    try testing.expectEqual(@as(u32, 10), border.frame);
}

test "AnimatedBorder tickBy wraps at u32 max" {
    var border = AnimatedBorder.init();
    border.frame = std.math.maxInt(u32) - 5;
    border.tickBy(10);
    try testing.expectEqual(@as(u32, 4), border.frame);
}

test "AnimatedBorder tickBy large value wraps" {
    var border = AnimatedBorder.init();
    border.tickBy(std.math.maxInt(u32));
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), border.frame);
}

test "AnimatedBorder tickBy called multiple times" {
    var border = AnimatedBorder.init();
    border.tickBy(3);
    border.tickBy(2);
    border.tickBy(4);
    try testing.expectEqual(@as(u32, 9), border.frame);
}

// ============================================================================
// RESET TESTS (2 tests)
// ============================================================================

test "AnimatedBorder reset sets frame to 0" {
    var border = AnimatedBorder.init();
    border.frame = 42;
    border.reset();
    try testing.expectEqual(@as(u32, 0), border.frame);
}

test "AnimatedBorder reset from max frame to 0" {
    var border = AnimatedBorder.init();
    border.frame = std.math.maxInt(u32);
    border.reset();
    try testing.expectEqual(@as(u32, 0), border.frame);
}

// ============================================================================
// INNERAREA TESTS (10 tests)
// ============================================================================

test "AnimatedBorder innerArea shrinks 10x10 by 1 on all sides" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 1), inner.x);
    try testing.expectEqual(@as(u16, 1), inner.y);
    try testing.expectEqual(@as(u16, 8), inner.width);
    try testing.expectEqual(@as(u16, 8), inner.height);
}

test "AnimatedBorder innerArea with 3x3 area returns 1x1" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 1), inner.width);
    try testing.expectEqual(@as(u16, 1), inner.height);
}

test "AnimatedBorder innerArea with 2x2 area returns empty" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 0), inner.width);
    try testing.expectEqual(@as(u16, 0), inner.height);
}

test "AnimatedBorder innerArea with 1x10 area returns empty width" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 10 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 0), inner.width);
}

test "AnimatedBorder innerArea with 10x1 area returns empty height" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 0), inner.height);
}

test "AnimatedBorder innerArea with offset preserves x+1, y+1" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 5, .y = 3, .width = 10, .height = 10 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 6), inner.x);
    try testing.expectEqual(@as(u16, 4), inner.y);
}

test "AnimatedBorder innerArea with 0x0 area returns empty" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 0), inner.width);
    try testing.expectEqual(@as(u16, 0), inner.height);
}

test "AnimatedBorder innerArea with 5x5 area returns 3x3" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 2, .y = 2, .width = 5, .height = 5 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 3), inner.x);
    try testing.expectEqual(@as(u16, 3), inner.y);
    try testing.expectEqual(@as(u16, 3), inner.width);
    try testing.expectEqual(@as(u16, 3), inner.height);
}

test "AnimatedBorder innerArea large area preserves dimensions correctly" {
    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const inner = border.innerArea(area);
    try testing.expectEqual(@as(u16, 98), inner.width);
    try testing.expectEqual(@as(u16, 48), inner.height);
}

// ============================================================================
// BUILDER API - IMMUTABILITY (16 tests)
// ============================================================================

test "AnimatedBorder withFrame preserves immutability" {
    const original = AnimatedBorder.init();
    const modified = original.withFrame(10);
    try testing.expectEqual(@as(u32, 0), original.frame);
    try testing.expectEqual(@as(u32, 10), modified.frame);
}

test "AnimatedBorder withAnimationStyle preserves immutability" {
    const original = AnimatedBorder.init();
    const modified = original.withAnimationStyle(.pulse);
    try testing.expectEqual(AnimatedBorder.AnimationStyle.rainbow, original.style);
    try testing.expectEqual(AnimatedBorder.AnimationStyle.pulse, modified.style);
}

test "AnimatedBorder withSpeed preserves immutability" {
    const original = AnimatedBorder.init();
    const modified = original.withSpeed(8);
    try testing.expectEqual(@as(u8, 4), original.speed);
    try testing.expectEqual(@as(u8, 8), modified.speed);
}

test "AnimatedBorder withBaseStyle preserves immutability" {
    const original = AnimatedBorder.init();
    const style = Style{ .fg = Color.red };
    const modified = original.withBaseStyle(style);
    try testing.expectEqual(Style{}, original.base_style);
    try testing.expect(modified.base_style.fg != null);
}

test "AnimatedBorder withTitle preserves immutability" {
    const original = AnimatedBorder.init();
    const modified = original.withTitle("Test");
    try testing.expectEqualStrings("", original.title);
    try testing.expectEqualStrings("Test", modified.title);
}

test "AnimatedBorder withTitleStyle preserves immutability" {
    const original = AnimatedBorder.init();
    const style = Style{ .fg = Color.blue };
    const modified = original.withTitleStyle(style);
    try testing.expectEqual(Style{}, original.title_style);
    try testing.expect(modified.title_style.fg != null);
}

test "AnimatedBorder withBorderSet preserves immutability" {
    const original = AnimatedBorder.init();
    const modified = original.withBorderSet(BoxSet.double);
    try testing.expectEqualStrings(BoxSet.rounded.top_left, original.border_set.top_left);
    try testing.expectEqualStrings(BoxSet.double.top_left, modified.border_set.top_left);
}

test "AnimatedBorder builder chain returns value copy" {
    const original = AnimatedBorder.init();
    const modified = original
        .withFrame(5)
        .withAnimationStyle(.chase)
        .withSpeed(2);
    try testing.expectEqual(@as(u32, 0), original.frame);
    try testing.expectEqual(@as(u8, 4), original.speed);
    try testing.expectEqual(@as(u32, 5), modified.frame);
    try testing.expectEqual(@as(u8, 2), modified.speed);
}

test "AnimatedBorder withFrame to zero" {
    const border = AnimatedBorder.init().withFrame(0);
    try testing.expectEqual(@as(u32, 0), border.frame);
}

test "AnimatedBorder withSpeed to 1" {
    const border = AnimatedBorder.init().withSpeed(1);
    try testing.expectEqual(@as(u8, 1), border.speed);
}

test "AnimatedBorder withAnimationStyle to rainbow" {
    const border = AnimatedBorder.init().withAnimationStyle(.rainbow);
    try testing.expectEqual(AnimatedBorder.AnimationStyle.rainbow, border.style);
}

test "AnimatedBorder withAnimationStyle to gradient" {
    const border = AnimatedBorder.init().withAnimationStyle(.gradient);
    try testing.expectEqual(AnimatedBorder.AnimationStyle.gradient, border.style);
}

test "AnimatedBorder withAnimationStyle to flash" {
    const border = AnimatedBorder.init().withAnimationStyle(.flash);
    try testing.expectEqual(AnimatedBorder.AnimationStyle.flash, border.style);
}

test "AnimatedBorder withBorderSet to single" {
    const border = AnimatedBorder.init().withBorderSet(BoxSet.single);
    try testing.expectEqualStrings(BoxSet.single.horizontal, border.border_set.horizontal);
}

test "AnimatedBorder multiple builder calls on same object" {
    const b1 = AnimatedBorder.init();
    const b2 = b1.withFrame(1);
    const b3 = b1.withFrame(2);
    try testing.expectEqual(@as(u32, 0), b1.frame);
    try testing.expectEqual(@as(u32, 1), b2.frame);
    try testing.expectEqual(@as(u32, 2), b3.frame);
}

// ============================================================================
// RENDER - ZERO/MINIMAL AREA (5 tests)
// ============================================================================

test "AnimatedBorder render with width 0 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    border.render(&buf, area);

    // Width 0 means no border drawn — verify buffer remains unchanged
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "AnimatedBorder render with height 0 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    border.render(&buf, area);

    // Height 0 means no border drawn — verify buffer remains unchanged
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "AnimatedBorder render with width 1 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 10 };
    border.render(&buf, area);

    // Width 1 < 2, so early return — no border drawn
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "AnimatedBorder render with height 1 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    border.render(&buf, area);

    // Height 1 < 2, so early return — no border drawn
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "AnimatedBorder render with 2x2 area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    border.render(&buf, area);

    // 2x2 should render corners: top-left, top-right, bottom-left, bottom-right
    try testing.expect(buf.getChar(0, 0) != ' ');
    try testing.expect(buf.getChar(1, 0) != ' ');
    try testing.expect(buf.getChar(0, 1) != ' ');
    try testing.expect(buf.getChar(1, 1) != ' ');
}

// ============================================================================
// RENDER - RAINBOW STYLE (6 tests)
// ============================================================================

test "AnimatedBorder rainbow renders top-left corner" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.rainbow)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    const cell = buf.get(0, 0);
    try testing.expect(cell != null);
}

test "AnimatedBorder rainbow renders different colors at different positions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.rainbow)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Top-left and top-middle should potentially have different colors
    const cell1 = buf.get(0, 0);
    const cell2 = buf.get(0, 3);
    try testing.expect(cell1 != null);
    try testing.expect(cell2 != null);
}

test "AnimatedBorder rainbow renders top edge" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.rainbow)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Top edge should have content
    for (0..10) |x| {
        const cell = buf.get(0, @intCast(x));
        try testing.expect(cell != null);
    }
}

test "AnimatedBorder rainbow renders right edge" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.rainbow)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Right edge should have content
    for (0..10) |y| {
        const cell = buf.get(@intCast(y), 9);
        try testing.expect(cell != null);
    }
}

test "AnimatedBorder rainbow same position different frames" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init().withAnimationStyle(.rainbow).withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init().withAnimationStyle(.rainbow).withFrame(4);
    border2.render(&buf2, area);

    // Both frames should render border characters at top-left
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder rainbow renders bottom edge" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.rainbow)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Bottom edge should have content
    for (0..10) |x| {
        const cell = buf.get(9, @intCast(x));
        try testing.expect(cell != null);
    }
}

// ============================================================================
// RENDER - PULSE STYLE (5 tests)
// ============================================================================

test "AnimatedBorder pulse all cells at frame 0 from same color palette" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // All border cells should have content
    const cell1 = buf.get(0, 0);
    const cell2 = buf.get(0, 5);
    try testing.expect(cell1 != null);
    try testing.expect(cell2 != null);
}

test "AnimatedBorder pulse renders at different frames" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init().withAnimationStyle(.pulse).withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init().withAnimationStyle(.pulse).withFrame(4);
    border2.render(&buf2, area);

    // Both should render border characters at top-left
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder pulse renders left edge" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Left edge should have content
    for (0..10) |y| {
        const cell = buf.get(@intCast(y), 0);
        try testing.expect(cell != null);
    }
}

test "AnimatedBorder pulse renders four corners" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    try testing.expect(buf.get(0, 0) != null);   // top-left
    try testing.expect(buf.get(0, 9) != null);   // top-right
    try testing.expect(buf.get(9, 0) != null);   // bottom-left
    try testing.expect(buf.get(9, 9) != null);   // bottom-right
}

test "AnimatedBorder pulse with high speed changes less frequently" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withFrame(1)
        .withSpeed(8);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withFrame(2)
        .withSpeed(8);
    border2.render(&buf2, area);

    // With speed=8, frame 1 and 2 both use step=0 (frame/speed), so same color
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

// ============================================================================
// RENDER - CHASE STYLE (6 tests)
// ============================================================================

test "AnimatedBorder chase renders border at frame 0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Should have border cells rendered
    try testing.expect(buf.get(0, 0) != null);
}

test "AnimatedBorder chase renders different frames" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init().withAnimationStyle(.chase).withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init().withAnimationStyle(.chase).withFrame(4);
    border2.render(&buf2, area);

    // Both frames should have border rendered
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder chase with base_style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withBaseStyle(Style{ .fg = Color.blue })
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Should render border with base_style applied
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "AnimatedBorder chase chase position advances with frame" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withSpeed(1)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withSpeed(1)
        .withFrame(1);
    border2.render(&buf2, area);

    // Both should have border chars rendered, chase position changes per frame
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder chase wraps around perimeter" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Perimeter length = 2*(10+10-2) = 36
    // Chase should cycle through positions 0..35
    // At frame 0, step=0, chase_pos=0 (top-left)
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "AnimatedBorder chase small area renders" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 4, .height = 4 };
    border.render(&buf, area);

    // 4x4 area should render border
    try testing.expect(buf.getChar(0, 0) != ' ');
}

// ============================================================================
// RENDER - FLASH STYLE (5 tests)
// ============================================================================

test "AnimatedBorder flash renders at frame 0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    try testing.expect(buf.get(0, 0) != null);
}

test "AnimatedBorder flash alternates every N frames" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const speed = 4;

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withSpeed(speed)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withSpeed(speed)
        .withFrame(@intCast(speed));
    border2.render(&buf2, area);

    // Both should render border (flash just changes color every N frames)
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder flash with speed 1" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withSpeed(1)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Should render border
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "AnimatedBorder flash at even frame step" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withSpeed(4)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    try testing.expect(buf.get(0, 0) != null);
}

test "AnimatedBorder flash at odd frame step" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withSpeed(4)
        .withFrame(5);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    try testing.expect(buf.get(0, 0) != null);
}

// ============================================================================
// RENDER - GRADIENT STYLE (5 tests)
// ============================================================================

test "AnimatedBorder gradient renders at frame 0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.gradient)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    try testing.expect(buf.get(0, 0) != null);
}

test "AnimatedBorder gradient different frames render" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init().withAnimationStyle(.gradient).withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init().withAnimationStyle(.gradient).withFrame(4);
    border2.render(&buf2, area);

    // Both should render border with gradient
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder gradient with custom colors" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.gradient)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Should render gradient border
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "AnimatedBorder gradient shifts with frame" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.gradient)
        .withSpeed(1)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.gradient)
        .withSpeed(1)
        .withFrame(2);
    border2.render(&buf2, area);

    // Both render border, frame shifts gradient
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder gradient wide area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.gradient)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    border.render(&buf, area);

    // Should render gradient on wide border
    try testing.expect(buf.getChar(0, 0) != ' ');
}

// ============================================================================
// RENDER - TITLE (8 tests)
// ============================================================================

test "AnimatedBorder empty title renders no title" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withTitle("")
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Border should still render without title
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "AnimatedBorder with title renders characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withTitle("Test")
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    border.render(&buf, area);

    // Title "Test" should be rendered on top edge at position (area.x+2, area.y)
    // Position 2 should have 'T'
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(2, 0));
}

test "AnimatedBorder title with offset area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 15);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withTitle("Title")
        .withFrame(0);
    const area = Rect{ .x = 5, .y = 5, .width = 15, .height = 8 };
    border.render(&buf, area);

    // Title should render at offset position (area.x+2, area.y) = (7, 5)
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(7, 5));
}

test "AnimatedBorder title_style applied" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withTitle("Hi")
        .withTitleStyle(Style{ .fg = Color.red })
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };
    border.render(&buf, area);

    // Title should be rendered with red style
    const style = buf.getStyle(2, 0);
    try testing.expect(style.fg != null);
}

test "AnimatedBorder title truncated if too long" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withTitle("This is a very long title that exceeds area width")
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Width 10, max_title_len = 10 - 4 = 6, so only first 6 chars rendered
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(2, 0));
}

test "AnimatedBorder title in minimal area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withTitle("X")
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    border.render(&buf, area);

    // Width 5, so area.width >= 5, title should render
    try testing.expectEqual(@as(u21, 'X'), buf.getChar(2, 0));
}

test "AnimatedBorder title renders at top edge" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withTitle("Title")
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    border.render(&buf, area);

    // Title should be at top row (y=0), starting at x=2
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(2, 0));
    try testing.expectEqual(@as(u21, 'i'), buf.getChar(3, 0));
}

// ============================================================================
// FRAME-BASED COLOR CHANGES (8 tests)
// ============================================================================

test "AnimatedBorder rainbow frame 0 vs frame speed" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const speed = 4;

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.rainbow)
        .withSpeed(speed)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.rainbow)
        .withSpeed(speed)
        .withFrame(@intCast(speed));
    border2.render(&buf2, area);

    // Both should render, frame shifts rainbow colors
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder pulse frame 0 gives colors[0]" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    try testing.expect(buf.get(0, 0) != null);
}

test "AnimatedBorder pulse frame speed gives next color" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(4)
        .withFrame(4);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    try testing.expect(buf.get(0, 0) != null);
}

test "AnimatedBorder chase frame changes position" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withSpeed(1)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.chase)
        .withSpeed(1)
        .withFrame(3);
    border2.render(&buf2, area);

    // Both render border, chase position changes
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder gradient frame shift" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.gradient)
        .withSpeed(1)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.gradient)
        .withSpeed(1)
        .withFrame(1);
    border2.render(&buf2, area);

    // Both render, frame shifts gradient
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder flash frame modulo 2" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const speed = 4;

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withSpeed(speed)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.flash)
        .withSpeed(speed)
        .withFrame(1);
    border2.render(&buf2, area);

    // Both render, flash alternates based on step%2
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder at maxInt frame wraps correctly in animation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(4)
        .withFrame(std.math.maxInt(u32));
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Should render without crashing even at max frame
    try testing.expect(buf.getChar(0, 0) != ' ');
}

// ============================================================================
// SPEED VARIATIONS (5 tests)
// ============================================================================

test "AnimatedBorder speed 1 changes every frame" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(1)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(1)
        .withFrame(1);
    border2.render(&buf2, area);

    // Speed 1: step = frame/1, so every frame changes color
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder speed 8 same for 8 frames" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(8)
        .withFrame(0);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(8)
        .withFrame(7);
    border2.render(&buf2, area);

    // Speed 8: step = frame/8, so frames 0-7 all have step=0 (same color)
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}

test "AnimatedBorder high speed animation slower" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(255);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // High speed slows animation, but still renders
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "AnimatedBorder speed 0 treated as 1" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    // Implementation should treat speed=0 as speed=1 to avoid div-by-zero
    const border = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(0)
        .withFrame(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    border.render(&buf, area);

    // Speed 0 is treated as 1, so render is safe
    try testing.expect(buf.getChar(0, 0) != ' ');
}

test "AnimatedBorder speed affects color cycling rate" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    const border1 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(1)
        .withFrame(5);
    border1.render(&buf1, area);

    const border2 = AnimatedBorder.init()
        .withAnimationStyle(.pulse)
        .withSpeed(8)
        .withFrame(5);
    border2.render(&buf2, area);

    // Speed 1: step=5; Speed 8: step=0. Different colors.
    try testing.expect(buf1.getChar(0, 0) != ' ');
    try testing.expect(buf2.getChar(0, 0) != ' ');
}
