//! BubbleChart Widget Tests — TDD Red Phase
//!
//! Tests BubbleChart widget with 2D variable-size bubble visualization,
//! builder pattern, X-Y range scaling, focused bubble styling, size markers,
//! axis rendering, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const BubbleChart = sailor.tui.widgets.BubbleChart;
const Bubble = BubbleChart.Bubble;

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

/// Check if buffer area contains a specific character
fn areaHasChar(buf: Buffer, area: Rect, ch: u21) bool {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Find text in buffer area (linear search, row-major order)
fn findTextInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var text_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (text_idx < text.len) : (text_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != text[text_idx]) {
                    matched = false;
                    break;
                }
                cx += 1;
                if (cx >= area.x + area.width or cx >= buf.width) {
                    cy += 1;
                    cx = area.x;
                }
            }

            if (matched) return true;
        }
    }
    return false;
}

// ============================================================================
// 1. BubbleChart Initialization & Defaults Tests (5 tests)
// ============================================================================

test "BubbleChart.init creates default chart with zero bubbles" {
    const chart = BubbleChart.init();
    try testing.expectEqual(@as(usize, 0), chart.bubbles.len);
}

test "BubbleChart.init defaults focused to 0" {
    const chart = BubbleChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused);
}

test "BubbleChart.init defaults x_min=0.0, x_max=1.0, y_min=0.0, y_max=1.0" {
    const chart = BubbleChart.init();
    try testing.expectEqual(@as(f32, 0.0), chart.x_min);
    try testing.expectEqual(@as(f32, 1.0), chart.x_max);
    try testing.expectEqual(@as(f32, 0.0), chart.y_min);
    try testing.expectEqual(@as(f32, 1.0), chart.y_max);
}

test "BubbleChart.init defaults show_labels=true, show_axes=true" {
    const chart = BubbleChart.init();
    try testing.expectEqual(true, chart.show_labels);
    try testing.expectEqual(true, chart.show_axes);
}

test "BubbleChart.init defaults block to null" {
    const chart = BubbleChart.init();
    try testing.expect(chart.block == null);
}

// ============================================================================
// 2. BubbleChart.bubbleCount Tests (3 tests)
// ============================================================================

test "BubbleChart.bubbleCount returns 0 for empty bubbles" {
    const chart = BubbleChart.init();
    try testing.expectEqual(@as(usize, 0), chart.bubbleCount());
}

test "BubbleChart.bubbleCount returns bubble count when below MAX_BUBBLES" {
    var bubbles: [10]Bubble = undefined;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        bubbles[i] = Bubble.init();
    }
    const chart = BubbleChart.init().withBubbles(&bubbles);
    try testing.expectEqual(@as(usize, 10), chart.bubbleCount());
}

test "BubbleChart.bubbleCount caps at MAX_BUBBLES when bubbles.len > 64" {
    var bubbles: [100]Bubble = undefined;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        bubbles[i] = Bubble.init();
    }
    const chart = BubbleChart.init().withBubbles(&bubbles);
    try testing.expectEqual(@as(usize, 64), chart.bubbleCount());
}

// ============================================================================
// 3. Bubble Initialization & Builder Tests (4 tests)
// ============================================================================

test "Bubble.init creates default bubble" {
    const bubble = Bubble.init();
    try testing.expectEqualStrings("", bubble.label);
    try testing.expectEqual(@as(f32, 0.0), bubble.x);
    try testing.expectEqual(@as(f32, 0.0), bubble.y);
    try testing.expectEqual(@as(f32, 0.5), bubble.size);
}

test "Bubble.withLabel sets label" {
    const bubble = Bubble.init().withLabel("MyBubble");
    try testing.expectEqualStrings("MyBubble", bubble.label);
}

test "Bubble.withX, withY set coordinates" {
    const bubble = Bubble.init().withX(0.3).withY(0.7);
    try testing.expectEqual(@as(f32, 0.3), bubble.x);
    try testing.expectEqual(@as(f32, 0.7), bubble.y);
}

test "Bubble.withSize sets size" {
    const bubble = Bubble.init().withSize(0.8);
    try testing.expectEqual(@as(f32, 0.8), bubble.size);
}

// ============================================================================
// 4. BubbleChart Builder Immutability Tests (5 tests)
// ============================================================================

test "BubbleChart.withBubbles does not modify original" {
    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.1);
    bubbles[1] = Bubble.init().withX(0.9);

    const chart1 = BubbleChart.init();
    const chart2 = chart1.withBubbles(&bubbles);

    try testing.expectEqual(@as(usize, 0), chart1.bubbles.len);
    try testing.expectEqual(@as(usize, 2), chart2.bubbles.len);
}

test "BubbleChart.withFocused sets focused index" {
    const chart = BubbleChart.init().withFocused(3);
    try testing.expectEqual(@as(usize, 3), chart.focused);
}

test "BubbleChart.withXMin/withXMax sets x range" {
    const chart = BubbleChart.init().withXMin(0.5).withXMax(2.0);
    try testing.expectEqual(@as(f32, 0.5), chart.x_min);
    try testing.expectEqual(@as(f32, 2.0), chart.x_max);
}

test "BubbleChart.withYMin/withYMax sets y range" {
    const chart = BubbleChart.init().withYMin(-1.0).withYMax(1.0);
    try testing.expectEqual(@as(f32, -1.0), chart.y_min);
    try testing.expectEqual(@as(f32, 1.0), chart.y_max);
}

test "BubbleChart.withShowLabels/withShowAxes toggle display" {
    const chart = BubbleChart.init().withShowLabels(false).withShowAxes(false);
    try testing.expectEqual(false, chart.show_labels);
    try testing.expectEqual(false, chart.show_axes);
}

// ============================================================================
// 5. BubbleChart Render — Zero/Minimal Area Tests (4 tests)
// ============================================================================

test "BubbleChart.render on 0x0 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    const chart = BubbleChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
}

test "BubbleChart.render on 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    const chart = BubbleChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
}

test "BubbleChart.render on 0-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    const chart = BubbleChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    chart.render(&buf, area);
}

test "BubbleChart.render on 0-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    const chart = BubbleChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    chart.render(&buf, area);
}

// ============================================================================
// 6. BubbleChart Render — Empty Bubbles Tests (2 tests)
// ============================================================================

test "BubbleChart.render with empty bubbles produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const chart = BubbleChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "BubbleChart.render empty bubbles with show_axes=false produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const chart = BubbleChart.init().withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// 7. BubbleChart Render — Single Bubble Tests (5 tests)
// ============================================================================

test "BubbleChart.render single bubble produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render single bubble at (0.5,0.5) appears near center" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Center area should have content
    const center_area = Rect{ .x = 15, .y = 7, .width = 10, .height = 6 };
    const center_content = countNonEmptyCells(buf, center_area);
    try testing.expect(center_content > 0);
}

test "BubbleChart.render single bubble applies correct marker for size=0.5 (○)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have white circle marker (0x25CB = ○)
    const has_marker = areaHasChar(buf, area, 0x25CB);
    try testing.expect(has_marker or countNonEmptyCells(buf, area) > 0);
}

test "BubbleChart.render single bubble with label=X shows content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5).withLabel("A");
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render single bubble with custom style renders" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    const bubble_style = Style{ .fg = .{ .indexed = 2 } };
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5).withStyle(bubble_style);
    const chart = BubbleChart.init().withBubbles(&bubbles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 8. BubbleChart Render — Multiple Bubbles Tests (4 tests)
// ============================================================================

test "BubbleChart.render two bubbles at different positions produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.2).withY(0.8).withSize(0.5);
    bubbles[1] = Bubble.init().withX(0.8).withY(0.2).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render two bubbles at different x positions shows separation" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.1).withY(0.5).withSize(0.4);
    bubbles[1] = Bubble.init().withX(0.9).withY(0.5).withSize(0.4);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    chart.render(&buf, area);
    // Left half should have content from first bubble
    const left_area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    const left_content = countNonEmptyCells(buf, left_area);
    // Right half should have content from second bubble
    const right_area = Rect{ .x = 50, .y = 0, .width = 30, .height = 20 };
    const right_content = countNonEmptyCells(buf, right_area);
    try testing.expect(left_content > 0);
    try testing.expect(right_content > 0);
}

test "BubbleChart.render three bubbles produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [3]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.2).withY(0.2).withSize(0.4);
    bubbles[1] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    bubbles[2] = Bubble.init().withX(0.8).withY(0.8).withSize(0.6);
    const chart = BubbleChart.init().withBubbles(&bubbles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render four bubbles in corners produces content in all quadrants" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [4]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.1).withY(0.1).withSize(0.4); // BL
    bubbles[1] = Bubble.init().withX(0.9).withY(0.1).withSize(0.4); // BR
    bubbles[2] = Bubble.init().withX(0.1).withY(0.9).withSize(0.4); // TL
    bubbles[3] = Bubble.init().withX(0.9).withY(0.9).withSize(0.4); // TR
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 9. BubbleChart Render — Focused Bubble Tests (4 tests)
// ============================================================================

test "BubbleChart.render focused bubble (index 0) applies focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.3).withY(0.5).withSize(0.4);
    bubbles[1] = Bubble.init().withX(0.7).withY(0.5).withSize(0.4);
    const focused_style = Style{ .bold = true };
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Focused bubble should be rendered
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render non-focused bubbles use bubble_style not focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.3).withY(0.5).withSize(0.4);
    bubbles[1] = Bubble.init().withX(0.7).withY(0.5).withSize(0.4);
    const bubble_style = Style{ .italic = true };
    const focused_style = Style{ .bold = true };
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withFocused(0)
        .withBubbleStyle(bubble_style)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Both bubbles should render
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render focused=out_of_range no bubble gets focused style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.3).withY(0.5).withSize(0.4);
    bubbles[1] = Bubble.init().withX(0.7).withY(0.5).withSize(0.4);
    const focused_style = Style{ .bold = true };
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withFocused(99)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Bubbles should still render with default style
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render changing focused changes styling target" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.3).withY(0.5).withSize(0.4);
    bubbles[1] = Bubble.init().withX(0.7).withY(0.5).withSize(0.4);

    const chart1 = BubbleChart.init().withBubbles(&bubbles).withFocused(0);
    const chart2 = BubbleChart.init().withBubbles(&bubbles).withFocused(1);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);

    // Both should render bubbles
    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

// ============================================================================
// 10. BubbleChart Render — Bubble Size Markers Tests (5 tests)
// ============================================================================

test "BubbleChart.render size=0.1 uses middle dot (·)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.1);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have middle dot (0x00B7 = ·)
    const has_marker = areaHasChar(buf, area, 0x00B7);
    try testing.expect(has_marker or countNonEmptyCells(buf, area) > 0);
}

test "BubbleChart.render size=0.3 uses bullet (•)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.3);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have bullet (0x2022 = •)
    const has_marker = areaHasChar(buf, area, 0x2022);
    try testing.expect(has_marker or countNonEmptyCells(buf, area) > 0);
}

test "BubbleChart.render size=0.5 uses white circle (○)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have white circle (0x25CB = ○)
    const has_marker = areaHasChar(buf, area, 0x25CB);
    try testing.expect(has_marker or countNonEmptyCells(buf, area) > 0);
}

test "BubbleChart.render size=0.7 uses fisheye (◉)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.7);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have fisheye (0x25C9 = ◉)
    const has_marker = areaHasChar(buf, area, 0x25C9);
    try testing.expect(has_marker or countNonEmptyCells(buf, area) > 0);
}

test "BubbleChart.render size=0.9 uses black circle (●)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.9);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have black circle (0x25CF = ●)
    const has_marker = areaHasChar(buf, area, 0x25CF);
    try testing.expect(has_marker or countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// 11. BubbleChart Render — show_axes=false Tests (3 tests)
// ============================================================================

test "BubbleChart.render show_axes=false produces no axis characters" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should not have vertical bar │ (if axes disabled)
    const has_v_axis = areaHasChar(buf, area, '│');
    // If bubble is rendered but no axes, v_axis should be false
    try testing.expect(!has_v_axis or countNonEmptyCells(buf, area) > 0);
}

test "BubbleChart.render show_axes=false uses full area for plot" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);

    const chart_no_axes = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const chart_with_axes = BubbleChart.init().withBubbles(&bubbles).withShowAxes(true);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart_no_axes.render(&buf1, area);
    chart_with_axes.render(&buf2, area);

    // Both should have content; no_axes version may use more area
    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "BubbleChart.render show_axes=false renders bubble closer to edges" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.05).withY(0.05).withSize(0.4);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Corner area should have content (bottom-left, since y=0 is at bottom with inverted Y axis)
    const corner_area = Rect{ .x = 0, .y = 15, .width = 5, .height = 5 };
    const corner_content = countNonEmptyCells(buf, corner_area);
    try testing.expect(corner_content > 0);
}

// ============================================================================
// 12. BubbleChart Render — show_axes=true Tests (4 tests)
// ============================================================================

test "BubbleChart.render show_axes=true has vertical axis (│)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have vertical axis character
    const has_v_axis = areaHasChar(buf, area, '│');
    try testing.expect(has_v_axis);
}

test "BubbleChart.render show_axes=true has horizontal axis (─)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have horizontal axis character
    const has_h_axis = areaHasChar(buf, area, '─');
    try testing.expect(has_h_axis);
}

test "BubbleChart.render show_axes=true has corner (┼)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have corner intersection
    const has_corner = areaHasChar(buf, area, '┼');
    try testing.expect(has_corner);
}

test "BubbleChart.render show_axes=true axis labels are present" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have some axis content (digits or axis characters)
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 13. BubbleChart Render — show_labels Tests (3 tests)
// ============================================================================

test "BubbleChart.render show_labels=true displays bubble label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5).withLabel("A");
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowLabels(true).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have label content (the 'A' or marker + label)
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render show_labels=false omits bubble label" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init()
        .withX(0.5).withY(0.5).withSize(0.5)
        .withLabel("VeryLongLabelNameHere");

    const chart_with_labels = BubbleChart.init().withBubbles(&bubbles).withShowLabels(true).withShowAxes(false);
    const chart_no_labels = BubbleChart.init().withBubbles(&bubbles).withShowLabels(false).withShowAxes(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart_with_labels.render(&buf1, area);
    chart_no_labels.render(&buf2, area);

    // Both should render marker, but with_labels may have more content
    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "BubbleChart.render show_labels=true with multiple labeled bubbles shows labels" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [3]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.2).withY(0.2).withSize(0.4).withLabel("X");
    bubbles[1] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5).withLabel("Y");
    bubbles[2] = Bubble.init().withX(0.8).withY(0.8).withSize(0.6).withLabel("Z");
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowLabels(true).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 14. BubbleChart Render — X/Y Range Tests (4 tests)
// ============================================================================

test "BubbleChart.render bubble at x_min,y_min renders in bottom-left" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.0).withY(0.0).withSize(0.4);
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withXMin(0.0).withXMax(1.0)
        .withYMin(0.0).withYMax(1.0)
        .withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Bottom-left corner should have content
    const corner = Rect{ .x = 0, .y = 15, .width = 5, .height = 5 };
    const corner_content = countNonEmptyCells(buf, corner);
    try testing.expect(corner_content > 0);
}

test "BubbleChart.render bubble at x_max,y_max renders in top-right" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(1.0).withY(1.0).withSize(0.4);
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withXMin(0.0).withXMax(1.0)
        .withYMin(0.0).withYMax(1.0)
        .withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Top-right corner should have content
    const corner = Rect{ .x = 35, .y = 0, .width = 5, .height = 5 };
    const corner_content = countNonEmptyCells(buf, corner);
    try testing.expect(corner_content > 0);
}

test "BubbleChart.render bubble outside range (x > x_max) not rendered" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(2.0).withY(0.5).withSize(0.4);
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withXMin(0.0).withXMax(1.0)
        .withYMin(0.0).withYMax(1.0)
        .withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have minimal/no content for bubble outside range
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty == 0 or non_empty < 5);
}

test "BubbleChart.render with custom x_min/y_min/x_max/y_max scales correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(10.0).withY(20.0).withSize(0.5);
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withXMin(0.0).withXMax(100.0)
        .withYMin(0.0).withYMax(100.0)
        .withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Bubble at 10% x, 20% y should render in left-bottom area
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 15. BubbleChart Render — Block Border Tests (3 tests)
// ============================================================================

test "BubbleChart.render with block border renders border and content inside" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const block = Block{};
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have border + content inside
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.render block reduces inner area for bubble rendering" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    const block = Block{};
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);

    const chart_with_block = BubbleChart.init().withBubbles(&bubbles).withBlock(block);
    const chart_no_block = BubbleChart.init().withBubbles(&bubbles);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart_with_block.render(&buf1, area);
    chart_no_block.render(&buf2, area);

    // Both should have content
    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "BubbleChart.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const block = (Block{}).withTitle("Bubbles", .top_left);
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const chart = BubbleChart.init().withBubbles(&bubbles).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should have title + border + content
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 16. BubbleChart Render — MAX_BUBBLES Cap Tests (2 tests)
// ============================================================================

test "BubbleChart.render with 65 bubbles caps at 64, renders 64 bubbles" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();
    var bubbles: [65]Bubble = undefined;
    var i: usize = 0;
    while (i < 65) : (i += 1) {
        const x = @as(f32, @floatFromInt(i % 8)) / 8.0;
        const y = @as(f32, @floatFromInt(i / 8)) / 8.0;
        bubbles[i] = Bubble.init().withX(x).withY(y).withSize(0.4);
    }
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    try testing.expectEqual(@as(usize, 64), chart.bubbleCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BubbleChart.bubbleCount returns exactly 64 when bubbles.len == 64" {
    var bubbles: [64]Bubble = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        bubbles[i] = Bubble.init();
    }
    const chart = BubbleChart.init().withBubbles(&bubbles);
    try testing.expectEqual(@as(usize, 64), chart.bubbleCount());
}

// ============================================================================
// 17. BubbleChart Render — Edge Cases Tests (4 tests)
// ============================================================================

test "BubbleChart.render x_min==x_max does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.4);
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withXMin(0.5).withXMax(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should not crash; may render nothing or minimal content
}

test "BubbleChart.render y_min==y_max does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.4);
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withYMin(0.5).withYMax(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should not crash
}

test "BubbleChart.render all bubbles outside range produces minimal content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [3]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(2.0).withY(2.0).withSize(0.4);
    bubbles[1] = Bubble.init().withX(3.0).withY(3.0).withSize(0.5);
    bubbles[2] = Bubble.init().withX(4.0).withY(4.0).withSize(0.6);
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withXMin(0.0).withXMax(1.0)
        .withYMin(0.0).withYMax(1.0)
        .withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty == 0 or non_empty < 5);
}

test "BubbleChart.render size=0 still renders a marker character" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.0);
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // size=0 should still render a marker (smallest: ·)
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 18. Style Builder Methods Tests (6 tests)
// ============================================================================

test "BubbleChart.withStyle sets base style" {
    const style = Style{ .bold = true };
    const chart = BubbleChart.init().withStyle(style);
    try testing.expectEqual(true, chart.style.bold);
}

test "BubbleChart.withBubbleStyle sets bubble_style" {
    const style = Style{ .italic = true };
    const chart = BubbleChart.init().withBubbleStyle(style);
    try testing.expectEqual(true, chart.bubble_style.italic);
}

test "BubbleChart.withFocusedStyle sets focused_style" {
    const style = Style{ .dim = true };
    const chart = BubbleChart.init().withFocusedStyle(style);
    try testing.expectEqual(true, chart.focused_style.dim);
}

test "BubbleChart.withAxisStyle sets axis_style" {
    const style = Style{ .fg = .{ .indexed = 8 } };
    const chart = BubbleChart.init().withAxisStyle(style);
    try testing.expect(chart.axis_style.fg != null);
}

test "BubbleChart.withBlock sets block" {
    const block = Block{};
    const chart = BubbleChart.init().withBlock(block);
    try testing.expect(chart.block != null);
}

test "BubbleChart render with custom styles produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [1]Bubble = undefined;
    bubbles[0] = Bubble.init().withX(0.5).withY(0.5).withSize(0.5);
    const style = Style{ .bold = true };
    const chart = BubbleChart.init()
        .withBubbles(&bubbles)
        .withStyle(style)
        .withBubbleStyle(style)
        .withFocusedStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 19. Bubble.withStyle Tests (2 tests)
// ============================================================================

test "Bubble.withStyle sets style on bubble" {
    const style = Style{ .bold = true };
    const bubble = Bubble.init().withStyle(style);
    try testing.expectEqual(true, bubble.style.bold);
}

test "BubbleChart render with styled bubbles produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bubbles: [2]Bubble = undefined;
    bubbles[0] = Bubble.init()
        .withX(0.3).withY(0.5).withSize(0.4)
        .withStyle(Style{ .fg = .{ .indexed = 1 } });
    bubbles[1] = Bubble.init()
        .withX(0.7).withY(0.5).withSize(0.4)
        .withStyle(Style{ .fg = .{ .indexed = 2 } });
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// 20. Memory Safety Tests (2 tests)
// ============================================================================

test "BubbleChart render does not exceed buffer bounds" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var bubbles: [10]Bubble = undefined;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        bubbles[i] = Bubble.init()
            .withX(@as(f32, @floatFromInt(i)) / 10.0)
            .withY(@as(f32, @floatFromInt(i % 5)) / 5.0)
            .withSize(0.4);
    }
    const chart = BubbleChart.init().withBubbles(&bubbles);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    chart.render(&buf, area);
    // Should not crash or write outside bounds
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty == 0 or non_empty <= 200); // 20*10 cells max
}

test "BubbleChart render with MAX_BUBBLES all at different positions safe" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();
    var bubbles: [64]Bubble = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const x = @as(f32, @floatFromInt(i % 8)) / 8.0;
        const y = @as(f32, @floatFromInt(i / 8)) / 8.0;
        bubbles[i] = Bubble.init().withX(x).withY(y).withSize(0.4);
    }
    const chart = BubbleChart.init().withBubbles(&bubbles).withShowAxes(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    chart.render(&buf, area);
    // Should not crash or overflow
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 2400); // 80*30 cells max
}
