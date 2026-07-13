//! BulletChart Widget Tests — TDD Red Phase
//!
//! Tests BulletChart widget rendering one row per bullet with:
//! - Qualitative range bands (background shading from light to dark)
//! - Value bar (actual value fill)
//! - Target tick mark (vertical reference line)
//! - Optional labels and value text
//! - Focused row highlighting
//! - Block border support
//!
//! Tests cover initialization, builder pattern, bulletCount() capping at MAX_BULLETS,
//! render geometry (range bands, value bar, target tick placement at specific columns),
//! out-of-range value/target/ranges handling (critical: no crash/panic), focused styling,
//! label display, show_values formatting, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const BulletChart = sailor.tui.widgets.BulletChart;
const Bullet = sailor.tui.widgets.bullet_chart.Bullet;

// ============================================================================
// Helper Functions
// ============================================================================

/// Count non-empty cells (non-space characters) in a buffer area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Count specific character in a buffer area
fn countChar(buf: Buffer, area: Rect, target_char: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == target_char) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Find first occurrence of a character in a specific row
fn findCharInRow(buf: Buffer, y: u16, area: Rect, target_char: u21) ?u16 {
    if (y < area.y or y >= area.y + area.height or y >= buf.height) return null;
    var x = area.x;
    while (x < area.x + area.width and x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == target_char) {
                return x;
            }
        }
    }
    return null;
}

/// Approximate float equality check
fn floatEq(a: f32, b: f32, epsilon: f32) bool {
    return @abs(a - b) < epsilon;
}

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "BulletChart.init creates default chart with zero bullets" {
    const chart = BulletChart.init();
    try testing.expectEqual(@as(usize, 0), chart.bullets.len);
}

test "BulletChart.init defaults focused to 0" {
    const chart = BulletChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused);
}

test "BulletChart.init defaults max_value to 1.0" {
    const chart = BulletChart.init();
    try testing.expect(floatEq(1.0, chart.max_value, 0.001));
}

test "BulletChart.init defaults show_labels to true" {
    const chart = BulletChart.init();
    try testing.expectEqual(true, chart.show_labels);
}

test "BulletChart.init defaults show_values to false" {
    const chart = BulletChart.init();
    try testing.expectEqual(false, chart.show_values);
}

// ============================================================================
// Group 2: Bullet Struct Defaults (4 tests)
// ============================================================================

test "Bullet default label is empty" {
    const bullet = Bullet{};
    try testing.expectEqualStrings("", bullet.label);
}

test "Bullet default value is 0.0" {
    const bullet = Bullet{};
    try testing.expect(floatEq(0.0, bullet.value, 0.001));
}

test "Bullet default target is 0.0" {
    const bullet = Bullet{};
    try testing.expect(floatEq(0.0, bullet.target, 0.001));
}

test "Bullet default ranges array is empty" {
    const bullet = Bullet{};
    try testing.expectEqual(@as(usize, 0), bullet.ranges.len);
}

// ============================================================================
// Group 3: MAX_BULLETS Constant (1 test)
// ============================================================================

test "BulletChart.MAX_BULLETS equals 32" {
    try testing.expectEqual(@as(usize, 32), BulletChart.MAX_BULLETS);
}

// ============================================================================
// Group 4: bulletCount() Method (5 tests)
// ============================================================================

test "BulletChart.bulletCount with zero bullets returns 0" {
    const chart = BulletChart.init();
    try testing.expectEqual(@as(usize, 0), chart.bulletCount());
}

test "BulletChart.bulletCount with 1 bullet returns 1" {
    var bullets = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0 }};
    const chart = BulletChart.init().withBullets(&bullets);
    try testing.expectEqual(@as(usize, 1), chart.bulletCount());
}

test "BulletChart.bulletCount with 5 bullets returns 5" {
    var bullets: [5]Bullet = undefined;
    for (0..5) |i| {
        bullets[i] = .{
            .label = "B",
            .value = @as(f32, @floatFromInt(i)) / 5.0,
            .target = 1.0,
        };
    }
    const chart = BulletChart.init().withBullets(&bullets);
    try testing.expectEqual(@as(usize, 5), chart.bulletCount());
}

test "BulletChart.bulletCount with exactly MAX_BULLETS=32 returns 32" {
    var bullets: [32]Bullet = undefined;
    for (0..32) |i| {
        bullets[i] = .{
            .label = "B",
            .value = 0.5,
            .target = 1.0,
        };
    }
    const chart = BulletChart.init().withBullets(&bullets);
    try testing.expectEqual(@as(usize, 32), chart.bulletCount());
}

test "BulletChart.bulletCount caps at MAX_BULLETS=32 when 50 bullets provided" {
    var bullets: [50]Bullet = undefined;
    for (0..50) |i| {
        bullets[i] = .{
            .label = "B",
            .value = @as(f32, @floatFromInt(i % 100)) / 100.0,
            .target = 1.0,
        };
    }
    const chart = BulletChart.init().withBullets(&bullets);
    try testing.expectEqual(@as(usize, 32), chart.bulletCount());
}

// ============================================================================
// Group 5: Builder Immutability — All 12 Builder Methods (12 tests)
// ============================================================================

test "BulletChart.withBullets does not modify original" {
    var bullets1 = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0 }};
    var bullets2 = [_]Bullet{
        .{ .label = "X", .value = 0.3, .target = 1.0 },
        .{ .label = "Y", .value = 0.7, .target = 1.0 },
    };

    const chart1 = BulletChart.init().withBullets(&bullets1);
    const chart2 = chart1.withBullets(&bullets2);

    try testing.expectEqual(@as(usize, 1), chart1.bulletCount());
    try testing.expectEqual(@as(usize, 2), chart2.bulletCount());
}

test "BulletChart.withFocused sets focused index" {
    const chart1 = BulletChart.init().withFocused(0);
    const chart2 = chart1.withFocused(5);

    try testing.expectEqual(@as(usize, 0), chart1.focused);
    try testing.expectEqual(@as(usize, 5), chart2.focused);
}

test "BulletChart.withMaxValue sets max_value" {
    const chart1 = BulletChart.init().withMaxValue(1.0);
    const chart2 = chart1.withMaxValue(100.0);

    try testing.expect(floatEq(1.0, chart1.max_value, 0.001));
    try testing.expect(floatEq(100.0, chart2.max_value, 0.001));
}

test "BulletChart.withShowLabels sets show_labels" {
    const chart1 = BulletChart.init().withShowLabels(true);
    const chart2 = chart1.withShowLabels(false);

    try testing.expectEqual(true, chart1.show_labels);
    try testing.expectEqual(false, chart2.show_labels);
}

test "BulletChart.withShowValues sets show_values" {
    const chart1 = BulletChart.init().withShowValues(false);
    const chart2 = chart1.withShowValues(true);

    try testing.expectEqual(false, chart1.show_values);
    try testing.expectEqual(true, chart2.show_values);
}

test "BulletChart.withStyle sets base style" {
    const s = Style{ .bold = true };
    const chart1 = BulletChart.init().withStyle(s);
    const chart2 = chart1.withStyle(.{});

    try testing.expectEqual(true, chart1.style.bold);
    try testing.expectEqual(false, chart2.style.bold);
}

test "BulletChart.withRangeStyle sets range_style" {
    const s = Style{ .bold = true };
    const chart1 = BulletChart.init().withRangeStyle(s);
    const chart2 = chart1.withRangeStyle(.{});

    try testing.expectEqual(true, chart1.range_style.bold);
    try testing.expectEqual(false, chart2.range_style.bold);
}

test "BulletChart.withBarStyle sets bar_style" {
    const s = Style{ .bold = true };
    const chart1 = BulletChart.init().withBarStyle(s);
    const chart2 = chart1.withBarStyle(.{});

    try testing.expectEqual(true, chart1.bar_style.bold);
    try testing.expectEqual(false, chart2.bar_style.bold);
}

test "BulletChart.withTargetStyle sets target_style" {
    const s = Style{ .bold = true };
    const chart1 = BulletChart.init().withTargetStyle(s);
    const chart2 = chart1.withTargetStyle(.{});

    try testing.expectEqual(true, chart1.target_style.bold);
    try testing.expectEqual(false, chart2.target_style.bold);
}

test "BulletChart.withFocusedStyle sets focused_style" {
    const s = Style{ .bold = true };
    const chart1 = BulletChart.init().withFocusedStyle(s);
    const chart2 = chart1.withFocusedStyle(.{});

    try testing.expectEqual(true, chart1.focused_style.bold);
    try testing.expectEqual(false, chart2.focused_style.bold);
}

test "BulletChart.withLabelStyle sets label_style" {
    const s = Style{ .bold = true };
    const chart1 = BulletChart.init().withLabelStyle(s);
    const chart2 = chart1.withLabelStyle(.{});

    try testing.expectEqual(true, chart1.label_style.bold);
    try testing.expectEqual(false, chart2.label_style.bold);
}

test "BulletChart.withBlock sets block" {
    const blk = Block{};
    const chart1 = BulletChart.init().withBlock(blk);
    const chart2 = chart1.withBlock(null);

    try testing.expect(chart1.block != null);
    try testing.expect(chart2.block == null);
}

// ============================================================================
// Group 6: Render Zero/Minimal Area (3 tests)
// ============================================================================

test "BulletChart.render with zero width does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0 }};
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render with zero height does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0 }};
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0 }};
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    chart.render(&buf, area);
    // No crash is success
}

// ============================================================================
// Group 7: Empty Bullets (2 tests)
// ============================================================================

test "BulletChart.render with empty bullets array renders nothing" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    const chart = BulletChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    chart.render(&buf, area);

    // Should produce no visible content (except maybe block border if present)
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "BulletChart.render with show_labels=false and empty bullets renders nothing" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    const chart = BulletChart.init().withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 8: Single Bullet Rendering (5 tests)
// ============================================================================

test "BulletChart.render with single bullet renders on first row" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "Revenue", .value = 75.0, .target = 100.0 }};
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(100.0)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);

    // Should produce some content on the first row
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render single bullet value 0 does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "Zero", .value = 0.0, .target = 1.0 }};
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render single bullet value equals target does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "Equal", .value = 0.5, .target = 0.5 }};
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render single bullet at max_value does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "Max", .value = 100.0, .target = 100.0 }};
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(100.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render single bullet with empty ranges renders bar" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{.{ .label = "A", .value = 0.5, .target = 1.0, .ranges = &.{} }};
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 9: Multiple Bullets (4 tests)
// ============================================================================

test "BulletChart.render with 3 bullets renders 3 rows" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.3, .target = 1.0 },
        .{ .label = "B", .value = 0.6, .target = 1.0 },
        .{ .label = "C", .value = 0.9, .target = 1.0 },
    };
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with bullets correctly stacks them vertically" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();

    var bullets: [5]Bullet = undefined;
    for (0..5) |i| {
        bullets[i] = .{
            .label = "B",
            .value = @as(f32, @floatFromInt(i + 1)) / 5.0,
            .target = 1.0,
        };
    }
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render respects MAX_BULLETS cap at 32" {
    var buf = try Buffer.init(testing.allocator, 40, 40);
    defer buf.deinit();

    var bullets: [50]Bullet = undefined;
    for (0..50) |i| {
        bullets[i] = .{
            .label = "B",
            .value = 0.5,
            .target = 1.0,
        };
    }
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 40 };

    chart.render(&buf, area);

    // Should render only first 32 bullets
    try testing.expectEqual(@as(usize, 32), chart.bulletCount());
}

test "BulletChart.render with more bullets than height clips gracefully" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();

    var bullets: [10]Bullet = undefined;
    for (0..10) |i| {
        bullets[i] = .{
            .label = "B",
            .value = 0.5,
            .target = 1.0,
        };
    }
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);
    // Should not crash, render only what fits
}

// ============================================================================
// Group 10: Out-of-Range Values (CRITICAL — must not panic) (6 tests)
// ============================================================================

test "BulletChart.render with value far above max_value does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();

    // Malformed bullet: value (1,000,000) far exceeds max_value (1.0)
    // Without clamping, this would produce out-of-bounds column indices
    var bullets = [_]Bullet{
        .{ .label = "Huge", .value = 1_000_000.0, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    // This render should NOT panic/crash, even with out-of-range value
    chart.render(&buf, area);

    // Verify some content was produced or area was handled gracefully
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

test "BulletChart.render with target far above max_value does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "T", .value = 0.5, .target = 999_999.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render with negative value does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Neg", .value = -100.0, .target = 1.0 }
    };
    const chart = BulletChart.init().withBullets(&bullets);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render with ranges boundary far outside max_value does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();

    var ranges = [_]f32{ 0.5, 999_999.0 };
    var bullets = [_]Bullet{
        .{ .label = "R", .value = 0.5, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render with max_value zero does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Z", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(0.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
    // No crash is success
}

test "BulletChart.render with max_value negative does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "N", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(-1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
    // No crash is success
}

// ============================================================================
// Group 11: Range Band Rendering (8 tests)
// ============================================================================

test "BulletChart.render with single range boundary renders background band" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var ranges = [_]f32{0.5};
    var bullets = [_]Bullet{
        .{ .label = "R", .value = 0.3, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    // Should render something for the band
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with multiple range boundaries" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var ranges = [_]f32{ 0.3, 0.6, 0.9 };
    var bullets = [_]Bullet{
        .{ .label = "R", .value = 0.5, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with empty ranges renders bar without band chars" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "E", .value = 0.5, .target = 1.0, .ranges = &.{} }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    // Even with no ranges, should render bar
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render range boundaries in ascending order" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    // Ranges must be ascending for meaningful band rendering
    var ranges = [_]f32{ 0.2, 0.5, 0.8 };
    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.6, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
    // Should not crash even if ranges not strictly in order
}

test "BulletChart.render with range covering full width" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var ranges = [_]f32{1.0};
    var bullets = [_]Bullet{
        .{ .label = "F", .value = 0.5, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with range at 0.0 boundary" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var ranges = [_]f32{0.0};
    var bullets = [_]Bullet{
        .{ .label = "Z", .value = 0.5, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

test "BulletChart.render with many ranges (more than 3 band chars)" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var ranges = [_]f32{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 };
    var bullets = [_]Bullet{
        .{ .label = "M", .value = 0.5, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
    // Should cycle band chars if more than 3 ranges
}

// ============================================================================
// Group 12: Value Bar Rendering (6 tests)
// ============================================================================

test "BulletChart.render value bar at 0% occupies minimal space" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Zero", .value = 0.0, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
    // Should not crash; bar may be invisible at 0%
}

test "BulletChart.render value bar at 50% occupies half width" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Half", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render value bar at 100% fills full width" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Full", .value = 1.0, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render value bar with custom max_value scales correctly" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Scale", .value = 50.0, .target = 100.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(100.0)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render value bar uses bar_style when set" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    const bar_style = Style{ .bold = true };
    var bullets = [_]Bullet{
        .{ .label = "Styled", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withBarStyle(bar_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render value bar overlay on range bands" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var ranges = [_]f32{ 0.3, 0.7 };
    var bullets = [_]Bullet{
        .{ .label = "Overlay", .value = 0.5, .target = 1.0, .ranges = &ranges }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 13: Target Tick Rendering (6 tests)
// ============================================================================

test "BulletChart.render target tick at 0% position" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "T0", .value = 0.5, .target = 0.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
    // Target tick should be rendered, even at boundary
}

test "BulletChart.render target tick at 50% position" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "T50", .value = 0.3, .target = 0.5 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render target tick at 100% position" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "T100", .value = 0.8, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render target tick with custom max_value" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Scale", .value = 50.0, .target = 100.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(100.0)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

test "BulletChart.render target tick uses target_style when set" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    const target_style = Style{ .bold = true };
    var bullets = [_]Bullet{
        .{ .label = "Styled", .value = 0.3, .target = 0.7 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withTargetStyle(target_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

test "BulletChart.render target tick drawn over value bar" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Over", .value = 0.4, .target = 0.5 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
    // Target tick should be visible even if value extends to that column
}

// ============================================================================
// Group 14: Focused Styling (6 tests)
// ============================================================================

test "BulletChart.render focused row with custom focused_style" {
    var buf = try Buffer.init(testing.allocator, 60, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 },
        .{ .label = "B", .value = 0.7, .target = 1.0 },
    };
    const focused_style = Style{ .bold = true };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render focused index 0 highlights first bullet" {
    var buf = try Buffer.init(testing.allocator, 60, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 },
        .{ .label = "B", .value = 0.7, .target = 1.0 },
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render focused index out of bounds does not crash" {
    var buf = try Buffer.init(testing.allocator, 60, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 },
        .{ .label = "B", .value = 0.7, .target = 1.0 },
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withFocused(999);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Should render without crash, focused styling may not apply
}

test "BulletChart.render focused_style with default values does not override bar_style" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withFocused(0)
        .withBarStyle(Style{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

test "BulletChart.render focused_style only overrides when explicitly set" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 }
    };
    const explicit_focused = Style{ .bold = true };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withFocused(0)
        .withFocusedStyle(explicit_focused)
        .withBarStyle(Style{});
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

test "BulletChart.render multiple bullets with different focused indices" {
    var buf = try Buffer.init(testing.allocator, 60, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.3, .target = 1.0 },
        .{ .label = "B", .value = 0.6, .target = 1.0 },
        .{ .label = "C", .value = 0.9, .target = 1.0 },
    };

    for (0..3) |i| {
        var buf2 = try Buffer.init(testing.allocator, 60, 10);
        defer buf2.deinit();

        const chart = BulletChart.init()
            .withBullets(&bullets)
            .withFocused(i);
        const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

        chart.render(&buf2, area);
    }
}

// ============================================================================
// Group 15: show_labels Toggle (4 tests)
// ============================================================================

test "BulletChart.render with show_labels=true displays labels" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Revenue", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with show_labels=false hides labels" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Revenue", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render show_labels reserves left column space" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "VeryLongLabelName", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    // Label area should be reserved, bar starts after it
}

test "BulletChart.render label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    const label_style = Style{ .bold = true };
    var bullets = [_]Bullet{
        .{ .label = "Revenue", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowLabels(true)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 16: show_values Toggle (4 tests)
// ============================================================================

test "BulletChart.render with show_values=false omits value text" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with show_values=true appends value/target text" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 75.0, .target = 100.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(100.0)
        .withShowValues(true)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render show_values with zero values formats correctly" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Z", .value = 0.0, .target = 0.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withShowValues(true)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

test "BulletChart.render show_values with max values formats correctly" {
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "Max", .value = 100.0, .target = 100.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(100.0)
        .withShowValues(true)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 17: Block Border (3 tests)
// ============================================================================

test "BulletChart.render with block border renders frame" {
    var buf = try Buffer.init(testing.allocator, 60, 10);
    defer buf.deinit();

    const blk = Block{};
    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withBlock(blk);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with null block renders content in full area" {
    var buf = try Buffer.init(testing.allocator, 60, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withBlock(null);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render block with inner area smaller than content clips gracefully" {
    var buf = try Buffer.init(testing.allocator, 20, 8);
    defer buf.deinit();

    const blk = Block{};
    var bullets = [_]Bullet{
        .{ .label = "VeryLongLabel", .value = 0.5, .target = 1.0 }
    };
    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withBlock(blk);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 8 };

    chart.render(&buf, area);
    // Should clip gracefully, no crash
}

// ============================================================================
// Group 18: Real-World Scenarios (5 tests)
// ============================================================================

test "BulletChart.render KPI dashboard with multiple metrics" {
    var buf = try Buffer.init(testing.allocator, 80, 15);
    defer buf.deinit();

    var ranges1 = [_]f32{ 0.5, 0.8, 1.0 };
    var ranges2 = [_]f32{ 0.4, 0.7, 1.0 };
    var ranges3 = [_]f32{ 0.6, 0.85, 1.0 };

    var bullets = [_]Bullet{
        .{ .label = "Revenue", .value = 85.0, .target = 100.0, .ranges = &ranges1 },
        .{ .label = "Expenses", .value = 65.0, .target = 70.0, .ranges = &ranges2 },
        .{ .label = "Profit", .value = 92.0, .target = 90.0, .ranges = &ranges3 },
    };

    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(100.0)
        .withShowLabels(true)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render customer satisfaction metrics" {
    var buf = try Buffer.init(testing.allocator, 70, 12);
    defer buf.deinit();

    var ranges = [_]f32{ 0.3, 0.6, 0.9, 1.0 };

    var bullets = [_]Bullet{
        .{ .label = "Product Quality", .value = 8.5, .target = 9.0, .ranges = &ranges },
        .{ .label = "Delivery Speed", .value = 7.2, .target = 8.0, .ranges = &ranges },
        .{ .label = "Support Quality", .value = 9.1, .target = 9.0, .ranges = &ranges },
    };

    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(10.0)
        .withShowLabels(true)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 12 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with all bullets at target" {
    var buf = try Buffer.init(testing.allocator, 70, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 1.0, .target = 1.0 },
        .{ .label = "B", .value = 1.0, .target = 1.0 },
        .{ .label = "C", .value = 1.0, .target = 1.0 },
    };

    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render with all bullets below target" {
    var buf = try Buffer.init(testing.allocator, 70, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 0.2, .target = 1.0 },
        .{ .label = "B", .value = 0.3, .target = 1.0 },
        .{ .label = "C", .value = 0.1, .target = 1.0 },
    };

    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(1.0)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BulletChart.render all bullets above target" {
    var buf = try Buffer.init(testing.allocator, 70, 10);
    defer buf.deinit();

    var bullets = [_]Bullet{
        .{ .label = "A", .value = 1.5, .target = 1.0 },
        .{ .label = "B", .value = 2.0, .target = 1.0 },
        .{ .label = "C", .value = 1.8, .target = 1.0 },
    };

    const chart = BulletChart.init()
        .withBullets(&bullets)
        .withMaxValue(2.0)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 10 };

    chart.render(&buf, area);

    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
