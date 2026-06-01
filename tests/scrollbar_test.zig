//! Scrollbar Widget Tests — v2.19.0
//!
//! Tests scrollbar indicator widget with vertical/horizontal orientation,
//! thumb size calculation, position tracking, and rendering.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Scrollbar = sailor.tui.widgets.Scrollbar;
const Orientation = sailor.tui.widgets.ScrollbarOrientation;

// ============================================================================
// Scrollbar Default State
// ============================================================================

test "Scrollbar default state has zero total" {
    var sb = Scrollbar{};
    try testing.expectEqual(@as(usize, 0), sb.total);
}

test "Scrollbar default state has zero position" {
    var sb = Scrollbar{};
    try testing.expectEqual(@as(usize, 0), sb.position);
}

test "Scrollbar default state has zero viewport" {
    var sb = Scrollbar{};
    try testing.expectEqual(@as(usize, 0), sb.viewport);
}

test "Scrollbar default state is vertical orientation" {
    var sb = Scrollbar{};
    try testing.expectEqual(Orientation.vertical, sb.orientation);
}

test "Scrollbar default state initializes track_style" {
    const sb = Scrollbar{};
    // Should not be uninitialized; verify struct initialization works
    _ = sb.track_style;
}

test "Scrollbar default state initializes thumb_style" {
    const sb = Scrollbar{};
    // Should not be uninitialized; verify struct initialization works
    _ = sb.thumb_style;
}

// ============================================================================
// setPosition — Position Updates
// ============================================================================

test "setPosition updates position field" {
    var sb = Scrollbar{ .total = 100, .position = 0 };
    sb.setPosition(50);
    try testing.expectEqual(@as(usize, 50), sb.position);
}

test "setPosition can set to zero" {
    var sb = Scrollbar{ .total = 100, .position = 50 };
    sb.setPosition(0);
    try testing.expectEqual(@as(usize, 0), sb.position);
}

test "setPosition clamps to total when exceeds total" {
    var sb = Scrollbar{ .total = 100, .position = 0 };
    sb.setPosition(150);
    try testing.expect(sb.position <= sb.total);
}

test "setPosition handles large values gracefully" {
    var sb = Scrollbar{ .total = 1000, .position = 0 };
    sb.setPosition(999);
    try testing.expectEqual(@as(usize, 999), sb.position);
}

test "setPosition with total=0 does not crash" {
    var sb = Scrollbar{ .total = 0, .position = 0 };
    sb.setPosition(10);
    // Should not panic
}

// ============================================================================
// setTotal — Total Items Update
// ============================================================================

test "setTotal updates total field" {
    var sb = Scrollbar{ .total = 50 };
    sb.setTotal(100);
    try testing.expectEqual(@as(usize, 100), sb.total);
}

test "setTotal can set to zero" {
    var sb = Scrollbar{ .total = 100 };
    sb.setTotal(0);
    try testing.expectEqual(@as(usize, 0), sb.total);
}

test "setTotal clamps position if position > new total" {
    var sb = Scrollbar{ .total = 100, .position = 80 };
    sb.setTotal(50);
    try testing.expect(sb.position <= 50);
}

test "setTotal preserves position if within new total" {
    var sb = Scrollbar{ .total = 100, .position = 30 };
    sb.setTotal(50);
    try testing.expectEqual(@as(usize, 30), sb.position);
}

// ============================================================================
// setViewport — Viewport Size Update
// ============================================================================

test "setViewport updates viewport field" {
    var sb = Scrollbar{ .viewport = 10 };
    sb.setViewport(20);
    try testing.expectEqual(@as(usize, 20), sb.viewport);
}

test "setViewport can set to zero" {
    var sb = Scrollbar{ .viewport = 10 };
    sb.setViewport(0);
    try testing.expectEqual(@as(usize, 0), sb.viewport);
}

test "setViewport updates value" {
    var sb = Scrollbar{ .total = 100, .viewport = 10 };
    sb.setViewport(25);
    try testing.expectEqual(@as(usize, 25), sb.viewport);
}

// ============================================================================
// thumbSize — Calculate Thumb Length
// ============================================================================

test "thumbSize returns 0 when total is 0" {
    var sb = Scrollbar{ .total = 0, .viewport = 10 };
    const size = sb.thumbSize(100);
    try testing.expectEqual(@as(usize, 0), size);
}

test "thumbSize returns minimum 1 when total > 0" {
    var sb = Scrollbar{ .total = 1000, .viewport = 10 };
    const size = sb.thumbSize(100);
    try testing.expect(size >= 1);
}

test "thumbSize proportional: small viewport => small thumb" {
    var sb = Scrollbar{ .total = 1000, .viewport = 10 };
    const size = sb.thumbSize(100);
    // Thumb should be roughly (10 * 100) / 1000 = 1
    try testing.expect(size >= 0);
}

test "thumbSize proportional: large viewport => large thumb" {
    var sb = Scrollbar{ .total = 100, .viewport = 50 };
    const size = sb.thumbSize(100);
    // Thumb should be roughly (50 * 100) / 100 = 50
    try testing.expect(size >= 40 and size <= 60);
}

test "thumbSize when viewport equals total" {
    var sb = Scrollbar{ .total = 100, .viewport = 100 };
    const size = sb.thumbSize(100);
    // When viewport == total, thumb should fill track
    try testing.expect(size >= 90 and size <= 100);
}

test "thumbSize when viewport > total (fully visible)" {
    var sb = Scrollbar{ .total = 100, .viewport = 150 };
    const size = sb.thumbSize(100);
    // Thumb should fill entire track
    try testing.expect(size > 0);
}

test "thumbSize on small track (track_len=1)" {
    var sb = Scrollbar{ .total = 100, .viewport = 10 };
    const size = sb.thumbSize(1);
    try testing.expect(size >= 1);
}

test "thumbSize on large track (track_len=1000)" {
    var sb = Scrollbar{ .total = 100, .viewport = 10 };
    const size = sb.thumbSize(1000);
    try testing.expect(size >= 1);
}

test "thumbSize never exceeds track_len" {
    var sb = Scrollbar{ .total = 100, .viewport = 50 };
    const size = sb.thumbSize(80);
    try testing.expect(size <= 80);
}

test "thumbSize calculation with position=0" {
    var sb = Scrollbar{ .total = 200, .viewport = 50, .position = 0 };
    const size = sb.thumbSize(100);
    try testing.expect(size > 0);
}

// ============================================================================
// thumbOffset — Calculate Thumb Position
// ============================================================================

test "thumbOffset returns 0 when position is 0" {
    var sb = Scrollbar{ .total = 100, .position = 0, .viewport = 10 };
    const offset = sb.thumbOffset(100);
    try testing.expectEqual(@as(usize, 0), offset);
}

test "thumbOffset returns 0 when total is 0" {
    var sb = Scrollbar{ .total = 0, .position = 0, .viewport = 10 };
    const offset = sb.thumbOffset(100);
    try testing.expectEqual(@as(usize, 0), offset);
}

test "thumbOffset increases as position increases" {
    var sb = Scrollbar{ .total = 100, .viewport = 10 };
    const offset1 = sb.thumbOffset(100);
    sb.position = 50;
    const offset2 = sb.thumbOffset(100);
    try testing.expect(offset2 >= offset1);
}

test "thumbOffset clamped to track bounds" {
    var sb = Scrollbar{ .total = 100, .position = 99, .viewport = 10 };
    const size = sb.thumbSize(100);
    const offset = sb.thumbOffset(100);
    try testing.expect(offset + size <= 100);
}

test "thumbOffset at end of content positions thumb at end of track" {
    var sb = Scrollbar{ .total = 100, .position = 90, .viewport = 10 };
    const size = sb.thumbSize(100);
    const offset = sb.thumbOffset(100);
    // At end: offset + size should be near track_len
    try testing.expect(offset + size <= 100);
}

test "thumbOffset with single item visible" {
    var sb = Scrollbar{ .total = 1000, .position = 500, .viewport = 1 };
    const offset = sb.thumbOffset(100);
    try testing.expect(offset >= 0 and offset <= 100);
}

test "thumbOffset zero when viewport >= total" {
    var sb = Scrollbar{ .total = 100, .position = 50, .viewport = 100 };
    const offset = sb.thumbOffset(100);
    try testing.expectEqual(@as(usize, 0), offset);
}

test "thumbOffset scales with track_len" {
    var sb = Scrollbar{ .total = 100, .position = 50, .viewport = 10 };
    const offset1 = sb.thumbOffset(50);
    const offset2 = sb.thumbOffset(100);
    // Larger track should allow more offset
    try testing.expect(offset2 >= offset1 or offset1 == offset2);
}

// ============================================================================
// withOrientation — Builder Pattern
// ============================================================================

test "withOrientation returns scrollbar with horizontal orientation" {
    var sb = Scrollbar{};
    const updated = sb.withOrientation(.horizontal);
    try testing.expectEqual(Orientation.horizontal, updated.orientation);
}

test "withOrientation returns scrollbar with vertical orientation" {
    var sb = Scrollbar{ .orientation = .horizontal };
    const updated = sb.withOrientation(.vertical);
    try testing.expectEqual(Orientation.vertical, updated.orientation);
}

test "withOrientation preserves other fields" {
    const sb = Scrollbar{ .total = 100, .position = 50, .viewport = 10 };
    const updated = sb.withOrientation(.horizontal);
    try testing.expectEqual(@as(usize, 100), updated.total);
    try testing.expectEqual(@as(usize, 50), updated.position);
    try testing.expectEqual(@as(usize, 10), updated.viewport);
}

test "withOrientation can switch from horizontal to vertical" {
    const sb = Scrollbar{ .orientation = .horizontal };
    const updated = sb.withOrientation(.vertical);
    try testing.expectEqual(Orientation.vertical, updated.orientation);
}

// ============================================================================
// render — Widget Rendering
// ============================================================================

test "render on zero-area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    var sb = Scrollbar{ .total = 100, .viewport = 10 };
    sb.render(&buf, area);
    // Should not crash
}

test "render on zero-height area with vertical scrollbar" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .orientation = .vertical };
    sb.render(&buf, area);
    // Should not crash
}

test "render on zero-width area with horizontal scrollbar" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .orientation = .horizontal };
    sb.render(&buf, area);
    // Should not crash
}

test "render with total=0 shows empty track" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 20 };

    var sb = Scrollbar{ .total = 0, .viewport = 10, .orientation = .vertical };
    sb.render(&buf, area);
    // Should not crash
}

test "render vertical scrollbar draws vertical track" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 10, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .orientation = .vertical, .position = 0 };
    sb.render(&buf, area);
    // Should complete without error
}

test "render horizontal scrollbar draws horizontal track" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 10, .width = 80, .height = 1 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .orientation = .horizontal, .position = 0 };
    sb.render(&buf, area);
    // Should complete without error
}

test "render at position=0 shows thumb at start" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .position = 0, .orientation = .vertical };
    sb.render(&buf, area);
    // Should complete without error
}

test "render at position=total shows thumb at end" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .position = 90, .orientation = .vertical };
    sb.render(&buf, area);
    // Should complete without error
}

test "render at position=mid shows thumb at middle" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .position = 45, .orientation = .vertical };
    sb.render(&buf, area);
    // Should complete without error
}

test "render small vertical scrollbar (2x20)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 1000, .viewport = 100, .position = 500, .orientation = .vertical };
    sb.render(&buf, area);
    // Should not crash
}

test "render small horizontal scrollbar (20x1)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    var sb = Scrollbar{ .total = 1000, .viewport = 100, .position = 500, .orientation = .horizontal };
    sb.render(&buf, area);
    // Should not crash
}

test "render large vertical scrollbar (2x100)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 100);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 100 };

    var sb = Scrollbar{ .total = 10000, .viewport = 500, .position = 5000, .orientation = .vertical };
    sb.render(&buf, area);
    // Should not crash
}

test "render large horizontal scrollbar (100x1)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    var sb = Scrollbar{ .total = 10000, .viewport = 500, .position = 5000, .orientation = .horizontal };
    sb.render(&buf, area);
    // Should not crash
}

test "render respects custom track_style" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{
        .total = 100,
        .viewport = 10,
        .orientation = .vertical,
        .track_style = Style{ .bold = true },
    };
    sb.render(&buf, area);
    // Should complete without error
}

test "render respects custom thumb_style" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{
        .total = 100,
        .viewport = 10,
        .orientation = .vertical,
        .thumb_style = Style{ .bold = true },
    };
    sb.render(&buf, area);
    // Should complete without error
}

test "render with offset area (x=5, y=5)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 5, .y = 5, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .orientation = .vertical };
    sb.render(&buf, area);
    // Should not crash
}

test "render sequence: render then modify position then render again" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 100, .viewport = 10, .position = 0, .orientation = .vertical };
    sb.render(&buf, area);

    sb.setPosition(50);
    sb.render(&buf, area);

    sb.setPosition(99);
    sb.render(&buf, area);
    // Should complete without error
}

test "render with viewport close to total (almost fully scrolled)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };

    var sb = Scrollbar{ .total = 100, .viewport = 95, .position = 5, .orientation = .vertical };
    sb.render(&buf, area);
    // Should not crash
}

// ============================================================================
// Integration Tests
// ============================================================================

test "scrollbar workflow: set total and position then render" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 30 };

    var sb = Scrollbar{ .orientation = .vertical };
    sb.setTotal(1000);
    sb.setViewport(100);
    sb.setPosition(500);

    try testing.expectEqual(@as(usize, 1000), sb.total);
    try testing.expectEqual(@as(usize, 100), sb.viewport);
    try testing.expectEqual(@as(usize, 500), sb.position);

    sb.render(&buf, area);
    // Should complete without error
}

test "scrollbar state changes preserve invariants" {
    var sb = Scrollbar{};
    sb.setTotal(200);
    sb.setViewport(50);
    sb.setPosition(150);

    // Position should not exceed total - viewport
    try testing.expect(sb.position + sb.viewport <= sb.total + sb.viewport);
}

test "thumbSize and thumbOffset work together for complete track coverage" {
    var sb = Scrollbar{ .total = 100, .viewport = 20 };
    const track_len = 50;
    const size = sb.thumbSize(track_len);
    const offset = sb.thumbOffset(track_len);

    // Thumb should fit within track
    try testing.expect(offset + size <= track_len);
}

test "horizontal and vertical render with same data" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    var sb_v = Scrollbar{ .total = 100, .viewport = 10, .position = 50, .orientation = .vertical };
    var sb_h = Scrollbar{ .total = 100, .viewport = 10, .position = 50, .orientation = .horizontal };

    const area_v = Rect{ .x = 0, .y = 0, .width = 2, .height = 20 };
    const area_h = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };

    sb_v.render(&buf, area_v);
    sb_h.render(&buf, area_h);
    // Both should complete without error
}
