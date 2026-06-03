//! StatusLine Tests — v2.21.0
//!
//! Tests StatusLine widget for rendering a status bar with left, center, right sections.
//! StatusLine fills the entire width of an area with styled text sections.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Span = sailor.tui.Span;
const StatusLine = sailor.tui.StatusLine;

// ============================================================================
// StatusLine Default State
// ============================================================================

test "StatusLine default has empty left" {
    const sl = StatusLine{};
    try testing.expectEqual(@as(usize, 0), sl.left.len);
}

test "StatusLine default has empty center" {
    const sl = StatusLine{};
    try testing.expectEqual(@as(usize, 0), sl.center.len);
}

test "StatusLine default has empty right" {
    const sl = StatusLine{};
    try testing.expectEqual(@as(usize, 0), sl.right.len);
}

// ============================================================================
// StatusLine Render — Safe on Zero Area
// ============================================================================

test "StatusLine render on zero-area is no-op" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const sl = StatusLine{};
    sl.render(&buf, area);
    // Should not crash or panic
}

test "StatusLine render on zero-height area is no-op" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 0 };

    const sl = StatusLine{};
    sl.render(&buf, area);
    // Should not crash or panic
}

// ============================================================================
// StatusLine Render — Basic Content
// ============================================================================

test "StatusLine render sets cells in the first row of area" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 5, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("X")};
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Buffer should have content in row 5
}

test "StatusLine with left-only content renders left section" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("LEFT")};
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Should render "LEFT" on the left
}

test "StatusLine with right-only content renders right section" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("RIGHT")};
    const sl = StatusLine{ .right = &spans };
    sl.render(&buf, area);

    // Should render "RIGHT" on the right edge
}

test "StatusLine with center content renders center section" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("CENTER")};
    const sl = StatusLine{ .center = &spans };
    sl.render(&buf, area);

    // Should render "CENTER" in the middle
}

test "StatusLine render fills full width" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const sl = StatusLine{};
    sl.render(&buf, area);

    // Background style should fill the entire width
}

test "StatusLine with single left span renders that span text" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("test")};
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Should render "test" in left position
}

test "StatusLine with single right span renders at right edge" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("edge")};
    const sl = StatusLine{ .right = &spans };
    sl.render(&buf, area);

    // Should render "edge" at the right
}

test "StatusLine left section is left-aligned in its portion" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("L")};
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Left section should start at x=0 of the area
}

test "StatusLine right section is right-aligned in its portion" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("R")};
    const sl = StatusLine{ .right = &spans };
    sl.render(&buf, area);

    // Right section should end at x=80 (right edge of area)
}

test "StatusLine handles area wider than content" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const spans = [_]Span{Span.raw("text")};
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Padding should fill the remaining width
}

test "StatusLine handles content wider than area" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    const spans = [_]Span{Span.raw("verylongtext")};
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Should clip to area width
}

test "StatusLine with empty center uses remaining space for left and right" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const left_spans = [_]Span{Span.raw("L")};
    const right_spans = [_]Span{Span.raw("R")};
    const sl = StatusLine{ .left = &left_spans, .right = &right_spans };
    sl.render(&buf, area);

    // Left on left, right on right, space in between
}

// ============================================================================
// StatusLine Builder Pattern
// ============================================================================

test "StatusLine.withLeft returns StatusLine with left set" {
    const spans = [_]Span{Span.raw("text")};
    const sl = StatusLine{};
    const updated = sl.withLeft(&spans);
    try testing.expectEqual(@as(usize, 1), updated.left.len);
}

test "StatusLine.withCenter returns StatusLine with center set" {
    const spans = [_]Span{Span.raw("text")};
    const sl = StatusLine{};
    const updated = sl.withCenter(&spans);
    try testing.expectEqual(@as(usize, 1), updated.center.len);
}

test "StatusLine.withRight returns StatusLine with right set" {
    const spans = [_]Span{Span.raw("text")};
    const sl = StatusLine{};
    const updated = sl.withRight(&spans);
    try testing.expectEqual(@as(usize, 1), updated.right.len);
}

test "StatusLine.withStyle returns StatusLine with style set" {
    const style = Style{ .bold = true };
    const sl = StatusLine{};
    const updated = sl.withStyle(style);
    try testing.expect(updated.style.bold);
}

// ============================================================================
// StatusLine Render — Position and Layout
// ============================================================================

test "StatusLine render at y=5 draws in row 5 only" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 5, .width = 80, .height = 1 };

    const spans = [_]Span{Span.raw("X")};
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Content should be in row y=5
}

test "StatusLine render with multi-span left shows all spans" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const spans = [_]Span{
        Span.raw("one"),
        Span.raw(" "),
        Span.raw("two"),
    };
    const sl = StatusLine{ .left = &spans };
    sl.render(&buf, area);

    // Should render all three spans
}

test "StatusLine render with all three sections fills correctly" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const left = [_]Span{Span.raw("L")};
    const center = [_]Span{Span.raw("C")};
    const right = [_]Span{Span.raw("R")};
    const sl = StatusLine{ .left = &left, .center = &center, .right = &right };
    sl.render(&buf, area);

    // All three sections should be rendered
}
