//! Rating Widget Tests — TDD Red Phase
//!
//! Tests Rating widget (star/symbol rating display with discrete out-of-N display).
//! Rating is distinct from RangeSlider (continuous drag) and Gauge (percentage bar)
//! because it shows discrete symbols, like a product review widget.
//!
//! Tests cover:
//! - Initialization with value and max (clamping, NaN/Infinity handling)
//! - Default max=1 normalization when init with max=0
//! - Default fields: label=null, show_value=false, focused=false
//! - Default chars: '★' (full), '⯨' (half), '☆' (empty)
//! - Default styles: empty Style{}
//! - Builder immutability: each withX method returns new value without mutating original
//! - Value clamping: [0, max] with NaN->0, +Infinity->max, -Infinity->0
//! - Max capping: values > 32 capped to 32 (prevent unbounded loops)
//! - Star math: count full/half/empty stars using nearest-0.5 rounding
//!   - value=3.5, max=5 → 3 full + 1 half + 1 empty
//!   - value=5.0, max=5 → 5 full + 0 half + 0 empty
//!   - value=0.0, max=5 → 0 full + 0 half + 5 empty
//!   - value=2.24, max=5 → 2 full + 0 half + 3 empty (rounds down to 2.0)
//!   - value=2.26, max=5 → 2 full + 1 half + 2 empty (rounds to 2.5)
//! - Rendering: stars rendered in order (full/half/empty) with proper styles
//! - Label rendering: label prefix before stars, space-separated
//! - show_value rendering: " value/max" suffix (always one decimal place, e.g. "3.0/5")
//! - Edge cases: zero-width/zero-height area (no panic, no-op)
//! - Block rendering: border + inset stars into block inner area
//! - Style precedence: empty_style for empty stars, filled_style for full/half,
//!   focused_style overrides filled_style when focused=true
//! - Focused state rendering: applies focused_style to full/half stars

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const Rating = sailor.tui.widgets.Rating;

// ============================================================================
// Group 1: Rating Init and Defaults
// ============================================================================

test "Rating.init sets value and max" {
    const rating = Rating.init(3.5, 5);
    try testing.expectEqual(3.5, rating.value);
    try testing.expectEqual(@as(u8, 5), rating.max);
}

test "Rating.init defaults label to null" {
    const rating = Rating.init(2.0, 5);
    try testing.expect(rating.label == null);
}

test "Rating.init defaults show_value to false" {
    const rating = Rating.init(2.0, 5);
    try testing.expect(!rating.show_value);
}

test "Rating.init defaults focused to false" {
    const rating = Rating.init(2.0, 5);
    try testing.expect(!rating.focused);
}

test "Rating.init defaults full_char to ★" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(u21, '★'), rating.full_char);
}

test "Rating.init defaults half_char to ⯨" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(u21, '⯨'), rating.half_char);
}

test "Rating.init defaults empty_char to ☆" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(u21, '☆'), rating.empty_char);
}

test "Rating.init defaults style to empty Style" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(Style{}, rating.style);
}

test "Rating.init defaults filled_style to empty Style" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(Style{}, rating.filled_style);
}

test "Rating.init defaults focused_style to empty Style" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(Style{}, rating.focused_style);
}

test "Rating.init defaults block to null" {
    const rating = Rating.init(2.0, 5);
    try testing.expectEqual(@as(?Block, null), rating.block);
}

// ============================================================================
// Group 2: Rating Value Clamping
// ============================================================================

test "Rating.init clamps negative value to 0" {
    const rating = Rating.init(-5.0, 5);
    try testing.expectEqual(0.0, rating.value);
}

test "Rating.init clamps value exceeding max to max" {
    const rating = Rating.init(999.0, 5);
    try testing.expectEqual(5.0, rating.value);
}

test "Rating.init clamps NaN value to 0" {
    const rating = Rating.init(std.math.nan(f32), 5);
    try testing.expectEqual(0.0, rating.value);
}

test "Rating.init clamps positive infinity to max" {
    const rating = Rating.init(std.math.inf(f32), 5);
    try testing.expectEqual(5.0, rating.value);
}

test "Rating.init clamps negative infinity to 0" {
    const rating = Rating.init(-std.math.inf(f32), 5);
    try testing.expectEqual(0.0, rating.value);
}

test "Rating.init allows value equal to max" {
    const rating = Rating.init(5.0, 5);
    try testing.expectEqual(5.0, rating.value);
}

test "Rating.init allows value of 0" {
    const rating = Rating.init(0.0, 5);
    try testing.expectEqual(0.0, rating.value);
}

// ============================================================================
// Group 3: Rating Max Normalization and Capping
// ============================================================================

test "Rating.init normalizes max=0 to max=1" {
    const rating = Rating.init(0.5, 0);
    try testing.expectEqual(@as(u8, 1), rating.max);
}

test "Rating.init caps max > 32 to 32" {
    const rating = Rating.init(50.0, 100);
    try testing.expectEqual(@as(u8, 32), rating.max);
    // Value should be clamped to new max
    try testing.expectEqual(32.0, rating.value);
}

test "Rating.init allows max=1" {
    const rating = Rating.init(0.5, 1);
    try testing.expectEqual(@as(u8, 1), rating.max);
}

test "Rating.init allows max=32 exactly" {
    const rating = Rating.init(16.0, 32);
    try testing.expectEqual(@as(u8, 32), rating.max);
}

// ============================================================================
// Group 4: Rating Builder Immutability
// ============================================================================

test "withLabel does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const r2 = r1.withLabel("Rating");
    try testing.expect(r1.label == null);
    try testing.expect(r2.label != null);
    try testing.expectEqualStrings("Rating", r2.label.?);
}

test "withShowValue does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const r2 = r1.withShowValue(true);
    try testing.expect(!r1.show_value);
    try testing.expect(r2.show_value);
}

test "withFocus does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const r2 = r1.withFocus(true);
    try testing.expect(!r1.focused);
    try testing.expect(r2.focused);
}

test "withChars does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const r2 = r1.withChars('★', '⯨', '☆');
    try testing.expectEqual(@as(u21, '★'), r1.full_char);
    try testing.expectEqual(@as(u21, '★'), r2.full_char);
}

test "withChars customizes characters correctly" {
    const r = Rating.init(2.0, 5).withChars('=', '-', 'o');
    try testing.expectEqual(@as(u21, '='), r.full_char);
    try testing.expectEqual(@as(u21, '-'), r.half_char);
    try testing.expectEqual(@as(u21, 'o'), r.empty_char);
}

test "withStyle does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const style = Style{ .fg = .red };
    const r2 = r1.withStyle(style);
    try testing.expectEqual(Style{}, r1.style);
    try testing.expectEqual(style, r2.style);
}

test "withFilledStyle does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const style = Style{ .fg = .green };
    const r2 = r1.withFilledStyle(style);
    try testing.expectEqual(Style{}, r1.filled_style);
    try testing.expectEqual(style, r2.filled_style);
}

test "withFocusedStyle does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const style = Style{ .bold = true };
    const r2 = r1.withFocusedStyle(style);
    try testing.expectEqual(Style{}, r1.focused_style);
    try testing.expectEqual(style, r2.focused_style);
}

test "withBlock does not modify original" {
    const r1 = Rating.init(2.0, 5);
    const blk = Block{};
    const r2 = r1.withBlock(blk);
    try testing.expectEqual(@as(?Block, null), r1.block);
    try testing.expect(r2.block != null);
}

test "builder chain preserves immutability" {
    const r1 = Rating.init(2.0, 5);
    const r2 = r1
        .withLabel("Score")
        .withShowValue(true)
        .withFocus(true)
        .withChars('#', '-', 'x');

    try testing.expect(r1.label == null);
    try testing.expect(!r1.show_value);
    try testing.expect(!r1.focused);
    try testing.expectEqual(@as(u21, '★'), r1.full_char);

    try testing.expectEqualStrings("Score", r2.label.?);
    try testing.expect(r2.show_value);
    try testing.expect(r2.focused);
    try testing.expectEqual(@as(u21, '#'), r2.full_char);
}

// ============================================================================
// Group 5: Rating Star Math (Rounding and Count)
// ============================================================================

test "star math: value=3.5, max=5 produces 3 full + 1 half + 1 empty" {
    const rating = Rating.init(3.5, 5);
    // This test indirectly verifies star math through render+buffer inspection
    // With value=3.5/max=5, we expect: ★★★⯨☆ (3 full, 1 half, 1 empty)
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Position 0-2 should be full stars
    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(2, 0).?.char);
    // Position 3 should be half star
    try testing.expectEqual(@as(u21, '⯨'), buf.getConst(3, 0).?.char);
    // Position 4 should be empty star
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(4, 0).?.char);
}

test "star math: value=5.0, max=5 produces 5 full stars" {
    const rating = Rating.init(5.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // All 5 positions should be full stars
    for (0..5) |i| {
        try testing.expectEqual(@as(u21, '★'), buf.getConst(@intCast(i), 0).?.char);
    }
}

test "star math: value=0.0, max=5 produces 5 empty stars" {
    const rating = Rating.init(0.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // All 5 positions should be empty stars
    for (0..5) |i| {
        try testing.expectEqual(@as(u21, '☆'), buf.getConst(@intCast(i), 0).?.char);
    }
}

test "star math: value=2.24, max=5 rounds to 2.0 full (2 full + 0 half + 3 empty)" {
    const rating = Rating.init(2.24, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // 0-1: full, 2-4: empty
    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(3, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(4, 0).?.char);
}

test "star math: value=2.26, max=5 rounds to 2.5 (2 full + 1 half + 2 empty)" {
    const rating = Rating.init(2.26, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // 0-1: full, 2: half, 3-4: empty
    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, '⯨'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(3, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(4, 0).?.char);
}

test "star math: value=1.0, max=5 produces 1 full + 0 half + 4 empty" {
    const rating = Rating.init(1.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    for (1..5) |i| {
        try testing.expectEqual(@as(u21, '☆'), buf.getConst(@intCast(i), 0).?.char);
    }
}

test "star math: value=2.5, max=5 produces 2 full + 1 half + 2 empty" {
    const rating = Rating.init(2.5, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, '⯨'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(3, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(4, 0).?.char);
}

test "star math: value=0.5, max=5 produces 0 full + 1 half + 4 empty" {
    const rating = Rating.init(0.5, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '⯨'), buf.getConst(0, 0).?.char);
    for (1..5) |i| {
        try testing.expectEqual(@as(u21, '☆'), buf.getConst(@intCast(i), 0).?.char);
    }
}

// ============================================================================
// Group 6: Rating Rendering — Basic Stars
// ============================================================================

test "render writes stars in left-to-right order" {
    const rating = Rating.init(3.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Verify sequence: ★★★☆☆
    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(3, 0).?.char);
    try testing.expectEqual(@as(u21, '☆'), buf.getConst(4, 0).?.char);
}

test "render applies empty_style to empty stars" {
    const rating = Rating.init(2.0, 5).withStyle(Style{ .fg = .gray });
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Empty stars at positions 2-4 should have gray color
    try testing.expectEqual(.gray, buf.getConst(2, 0).?.style.fg);
}

test "render applies filled_style to full stars" {
    const rating = Rating.init(3.0, 5).withFilledStyle(Style{ .fg = .green });
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Full stars at positions 0-2 should have green color
    try testing.expectEqual(.green, buf.getConst(0, 0).?.style.fg);
    try testing.expectEqual(.green, buf.getConst(1, 0).?.style.fg);
    try testing.expectEqual(.green, buf.getConst(2, 0).?.style.fg);
}

test "render applies filled_style to half stars" {
    const rating = Rating.init(2.5, 5).withFilledStyle(Style{ .fg = .yellow });
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Half star at position 2 should have yellow color
    try testing.expectEqual(.yellow, buf.getConst(2, 0).?.style.fg);
}

// ============================================================================
// Group 7: Rating Rendering — Label Prefix
// ============================================================================

test "render with label prefixes stars" {
    const rating = Rating.init(3.0, 5).withLabel("Score");
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    rating.render(&buf, area);

    // Label "Score" at start, space at position 5, then stars starting at position 6
    try testing.expectEqual(@as(u21, 'S'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'c'), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'r'), buf.getConst(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.getConst(4, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.getConst(5, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(6, 0).?.char);
}

test "render with label truncates if area too narrow" {
    const rating = Rating.init(3.0, 5).withLabel("VeryLongLabel");
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    rating.render(&buf, area);

    // Should not panic; content gracefully truncated
    try testing.expect(buf.getConst(0, 0) != null);
}

test "render without label renders stars at position 0" {
    const rating = Rating.init(2.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Stars should start at position 0
    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(1, 0).?.char);
}

// ============================================================================
// Group 8: Rating Rendering — show_value Text
// ============================================================================

test "render with show_value=false does not show numeric text" {
    const rating = Rating.init(3.0, 5).withShowValue(false);
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    rating.render(&buf, area);

    // Positions 5-11 should not contain numeric text (only stars and empty)
    // Stars are at 0-4, rest should be empty/space
    try testing.expect(buf.getConst(5, 0).?.char == ' ' or buf.getConst(5, 0).?.char == '☆');
}

test "render with show_value=true and value=3.5 shows ' 3.5/5'" {
    const rating = Rating.init(3.5, 5).withShowValue(true);
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    rating.render(&buf, area);

    // Stars occupy 0-4, space at 5, text " 3.5/5" starting at 6
    // Position 6 should be space, then '3', '.', '5', '/', '5'
    try testing.expectEqual(@as(u21, ' '), buf.getConst(5, 0).?.char);
    try testing.expectEqual(@as(u21, '3'), buf.getConst(6, 0).?.char);
    try testing.expectEqual(@as(u21, '.'), buf.getConst(7, 0).?.char);
    try testing.expectEqual(@as(u21, '5'), buf.getConst(8, 0).?.char);
    try testing.expectEqual(@as(u21, '/'), buf.getConst(9, 0).?.char);
    try testing.expectEqual(@as(u21, '5'), buf.getConst(10, 0).?.char);
}

test "render with show_value=true and value=3.0 shows ' 3.0/5'" {
    const rating = Rating.init(3.0, 5).withShowValue(true);
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    rating.render(&buf, area);

    // Should show "3.0/5" not "3/5"
    try testing.expectEqual(@as(u21, '3'), buf.getConst(6, 0).?.char);
    try testing.expectEqual(@as(u21, '.'), buf.getConst(7, 0).?.char);
    try testing.expectEqual(@as(u21, '0'), buf.getConst(8, 0).?.char);
    try testing.expectEqual(@as(u21, '/'), buf.getConst(9, 0).?.char);
    try testing.expectEqual(@as(u21, '5'), buf.getConst(10, 0).?.char);
}

test "render with show_value=true and value=0.5 shows ' 0.5/5'" {
    const rating = Rating.init(0.5, 5).withShowValue(true);
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '0'), buf.getConst(6, 0).?.char);
    try testing.expectEqual(@as(u21, '.'), buf.getConst(7, 0).?.char);
    try testing.expectEqual(@as(u21, '5'), buf.getConst(8, 0).?.char);
    try testing.expectEqual(@as(u21, '/'), buf.getConst(9, 0).?.char);
    try testing.expectEqual(@as(u21, '5'), buf.getConst(10, 0).?.char);
}

test "render with show_value=true and max=10 shows ' 5.0/10'" {
    const rating = Rating.init(5.0, 10).withShowValue(true);
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    rating.render(&buf, area);

    // Stars at 0-9, space at 10, text starting at 11
    try testing.expectEqual(@as(u21, ' '), buf.getConst(10, 0).?.char);
    try testing.expectEqual(@as(u21, '5'), buf.getConst(11, 0).?.char);
    try testing.expectEqual(@as(u21, '.'), buf.getConst(12, 0).?.char);
    try testing.expectEqual(@as(u21, '0'), buf.getConst(13, 0).?.char);
    try testing.expectEqual(@as(u21, '/'), buf.getConst(14, 0).?.char);
    try testing.expectEqual(@as(u21, '1'), buf.getConst(15, 0).?.char);
    try testing.expectEqual(@as(u21, '0'), buf.getConst(16, 0).?.char);
}

// ============================================================================
// Group 9: Rating Rendering — Label + show_value
// ============================================================================

test "render with label and show_value renders both" {
    const rating = Rating.init(3.0, 5)
        .withLabel("Rating")
        .withShowValue(true);
    var buf = try Buffer.init(testing.allocator, 50, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    rating.render(&buf, area);

    // Label "Rating" (0-5), space (6), stars (7-11), space (12), text (13+)
    try testing.expectEqual(@as(u21, 'R'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(7, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.getConst(12, 0).?.char);
    try testing.expectEqual(@as(u21, '3'), buf.getConst(13, 0).?.char);
}

// ============================================================================
// Group 10: Rating Rendering — Edge Cases
// ============================================================================

test "render with zero-width area does not panic" {
    const rating = Rating.init(3.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    rating.render(&buf, area);
    // Should not crash; buffer unchanged
    try testing.expectEqual(@as(u21, ' '), buf.getConst(0, 0).?.char);
}

test "render with zero-height area does not panic" {
    const rating = Rating.init(3.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    rating.render(&buf, area);
    // Should not crash; buffer unchanged
    try testing.expectEqual(@as(u21, ' '), buf.getConst(0, 0).?.char);
}

test "render with area wider than needed renders all stars" {
    const rating = Rating.init(3.0, 5);
    var buf = try Buffer.init(testing.allocator, 100, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    rating.render(&buf, area);

    // All 5 stars should render
    for (0..5) |i| {
        const cell = buf.getConst(@intCast(i), 0);
        try testing.expect(cell != null);
        try testing.expect(cell.?.char == '★' or cell.?.char == '☆');
    }
}

test "render at offset position (x, y) respects area origin" {
    const rating = Rating.init(3.0, 5);
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const area = Rect{ .x = 10, .y = 5, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // First star should be at absolute position (10, 5)
    const star = buf.getConst(10, 5);
    try testing.expect(star != null);
    try testing.expectEqual(@as(u21, '★'), star.?.char);
}

test "render with very narrow area (width < max_stars) truncates gracefully" {
    const rating = Rating.init(5.0, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 1 };
    rating.render(&buf, area);

    // Should render only 2 stars (truncated from 5)
    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '★'), buf.getConst(1, 0).?.char);
}

// ============================================================================
// Group 11: Rating Rendering — Block Border
// ============================================================================

test "render with block border renders border and insets stars" {
    const blk = (Block{}).withTitle("Rating", .top_left);
    const rating = Rating.init(3.0, 5).withBlock(blk);
    var buf = try Buffer.init(testing.allocator, 30, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    rating.render(&buf, area);

    // Block corner should be at (0, 0)
    const corner = buf.getConst(0, 0);
    try testing.expect(corner != null);
    try testing.expect(corner.?.char != ' ' and corner.?.char != '★' and corner.?.char != '☆');
    // Stars should be inset (not at (0, 0))
}

test "render with block does not panic on zero dimensions" {
    const blk = Block{};
    const rating = Rating.init(3.0, 5).withBlock(blk);
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rating.render(&buf, area);
    // Should not crash
    try testing.expect(buf.getConst(0, 0) != null);
}

// ============================================================================
// Group 12: Rating Style Precedence and Focus
// ============================================================================

test "focused_style overrides filled_style when focused=true" {
    const filled_style = Style{ .fg = .green };
    const focused_style = Style{ .bold = true };
    const rating = Rating.init(3.0, 5)
        .withFilledStyle(filled_style)
        .withFocusedStyle(focused_style)
        .withFocus(true);

    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Full stars should have focused_style (bold), not filled_style
    try testing.expect(buf.getConst(0, 0).?.style.bold);
}

test "filled_style used when focused=false" {
    const filled_style = Style{ .fg = .green };
    const rating = Rating.init(3.0, 5)
        .withFilledStyle(filled_style)
        .withFocus(false);

    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // Full stars should have filled_style (green)
    try testing.expectEqual(.green, buf.getConst(0, 0).?.style.fg);
}

test "render applies consistent styles to all full stars" {
    const filled_style = Style{ .fg = .cyan };
    const rating = Rating.init(3.0, 5).withFilledStyle(filled_style);

    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // All full stars should have cyan color
    for (0..3) |i| {
        try testing.expectEqual(.cyan, buf.getConst(@intCast(i), 0).?.style.fg);
    }
}

test "render applies consistent styles to all empty stars" {
    const empty_style = Style{ .fg = .gray };
    const rating = Rating.init(2.0, 5).withStyle(empty_style);

    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    // All empty stars should have gray color
    for (2..5) |i| {
        try testing.expectEqual(.gray, buf.getConst(@intCast(i), 0).?.style.fg);
    }
}

// ============================================================================
// Group 13: Rating with Max=1 (minimum case)
// ============================================================================

test "rating with max=1 and value=0.5 shows half star" {
    const rating = Rating.init(0.5, 1);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '⯨'), buf.getConst(0, 0).?.char);
}

test "rating with max=1 and value=1.0 shows full star" {
    const rating = Rating.init(1.0, 1);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '★'), buf.getConst(0, 0).?.char);
}

// ============================================================================
// Group 14: Rating with Max=32 (maximum case)
// ============================================================================

test "rating with max=32 renders all 32 stars without panic" {
    const rating = Rating.init(16.0, 32);
    var buf = try Buffer.init(testing.allocator, 35, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 35, .height = 1 };
    rating.render(&buf, area);

    // First 16 should be full
    for (0..16) |i| {
        try testing.expectEqual(@as(u21, '★'), buf.getConst(@intCast(i), 0).?.char);
    }
    // Next 16 should be empty
    for (16..32) |i| {
        try testing.expectEqual(@as(u21, '☆'), buf.getConst(@intCast(i), 0).?.char);
    }
}

test "rating initialized with max > 32 is capped to 32" {
    const rating = Rating.init(50.0, 100);
    try testing.expectEqual(@as(u8, 32), rating.max);
    try testing.expectEqual(32.0, rating.value); // Clamped to new max
}

// ============================================================================
// Group 15: Rating with Custom Characters
// ============================================================================

test "render with custom characters uses all three customizations" {
    const rating = Rating.init(2.5, 5).withChars('=', '-', 'o');
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '='), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '='), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, '-'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.getConst(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.getConst(4, 0).?.char);
}

// ============================================================================
// Group 16: Rating Fractional Edge Cases
// ============================================================================

test "star math: value=4.74, max=5 rounds to 4.5 (4 full + 1 half + 0 empty)" {
    const rating = Rating.init(4.74, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    for (0..4) |i| {
        try testing.expectEqual(@as(u21, '★'), buf.getConst(@intCast(i), 0).?.char);
    }
    try testing.expectEqual(@as(u21, '⯨'), buf.getConst(4, 0).?.char);
}

test "star math: value=0.24, max=5 rounds to 0.0 (0 full + 0 half + 5 empty)" {
    const rating = Rating.init(0.24, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    for (0..5) |i| {
        try testing.expectEqual(@as(u21, '☆'), buf.getConst(@intCast(i), 0).?.char);
    }
}

test "star math: value=0.26, max=5 rounds to 0.5 (0 full + 1 half + 4 empty)" {
    const rating = Rating.init(0.26, 5);
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rating.render(&buf, area);

    try testing.expectEqual(@as(u21, '⯨'), buf.getConst(0, 0).?.char);
    for (1..5) |i| {
        try testing.expectEqual(@as(u21, '☆'), buf.getConst(@intCast(i), 0).?.char);
    }
}
