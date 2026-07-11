//! RadialBar Widget Tests — TDD Red Phase
//!
//! Tests RadialBar widget with concentric arc rings showing progress values
//! as filled arcs, focusing on ring rendering, value clamping, focused styling,
//! label display, block borders, MAX_ARCS capping, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const RadialBar = sailor.tui.widgets.RadialBar;
const RadialArc = sailor.tui.widgets.radial_bar.RadialArc;

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

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "RadialBar.init creates default bar with zero arcs" {
    const rb = RadialBar.init();
    try testing.expectEqual(@as(usize, 0), rb.arcs.len);
}

test "RadialBar.init defaults focused to 0" {
    const rb = RadialBar.init();
    try testing.expectEqual(@as(usize, 0), rb.focused);
}

test "RadialBar.init defaults show_labels to true" {
    const rb = RadialBar.init();
    try testing.expect(rb.show_labels);
}

test "RadialBar.init defaults show_values to true" {
    const rb = RadialBar.init();
    try testing.expect(rb.show_values);
}

test "RadialBar.init defaults block to null" {
    const rb = RadialBar.init();
    try testing.expectEqual(@as(?Block, null), rb.block);
}

// ============================================================================
// Group 2: RadialArc Struct Defaults (3 tests)
// ============================================================================

test "RadialArc default label is empty" {
    const arc = RadialArc{};
    try testing.expectEqualStrings("", arc.label);
}

test "RadialArc default value is 0.0" {
    const arc = RadialArc{};
    try testing.expectEqual(@as(f32, 0.0), arc.value);
}

test "RadialArc default style is empty" {
    const arc = RadialArc{};
    try testing.expect(!arc.style.bold and arc.style.dim == false);
}

// ============================================================================
// Group 3: MAX_ARCS Constant (1 test)
// ============================================================================

test "RadialBar.MAX_ARCS equals 8" {
    try testing.expectEqual(@as(usize, 8), RadialBar.MAX_ARCS);
}

// ============================================================================
// Group 4: arcCount() Method (5 tests)
// ============================================================================

test "RadialBar.arcCount with zero arcs returns 0" {
    const rb = RadialBar.init();
    try testing.expectEqual(@as(usize, 0), rb.arcCount());
}

test "RadialBar.arcCount with 1 arc returns 1" {
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    try testing.expectEqual(@as(usize, 1), rb.arcCount());
}

test "RadialBar.arcCount with 4 arcs returns 4" {
    var arcs: [4]RadialArc = undefined;
    for (0..4) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 4.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    try testing.expectEqual(@as(usize, 4), rb.arcCount());
}

test "RadialBar.arcCount with exactly MAX_ARCS=8 returns 8" {
    var arcs: [8]RadialArc = undefined;
    for (0..8) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 8.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    try testing.expectEqual(@as(usize, 8), rb.arcCount());
}

test "RadialBar.arcCount caps at MAX_ARCS when 10 arcs provided" {
    var arcs: [10]RadialArc = undefined;
    for (0..10) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 10.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    try testing.expectEqual(@as(usize, 8), rb.arcCount());
}

// ============================================================================
// Group 5: Builder Immutability (10 tests)
// ============================================================================

test "RadialBar.withArcs does not modify original" {
    var arcs1 = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    var arcs2 = [_]RadialArc{
        .{ .label = "MEM", .value = @as(f32, 0.3) },
        .{ .label = "DISK", .value = @as(f32, 0.7) },
    };

    const rb1 = RadialBar.init().withArcs(&arcs1);
    const rb2 = rb1.withArcs(&arcs2);

    try testing.expectEqual(@as(usize, 1), rb1.arcCount());
    try testing.expectEqual(@as(usize, 2), rb2.arcCount());
}

test "RadialBar.withFocused sets focused index" {
    const rb1 = RadialBar.init().withFocused(0);
    const rb2 = rb1.withFocused(3);

    try testing.expectEqual(@as(usize, 0), rb1.focused);
    try testing.expectEqual(@as(usize, 3), rb2.focused);
}

test "RadialBar.withShowLabels sets show_labels" {
    const rb1 = RadialBar.init().withShowLabels(true);
    const rb2 = rb1.withShowLabels(false);

    try testing.expectEqual(true, rb1.show_labels);
    try testing.expectEqual(false, rb2.show_labels);
}

test "RadialBar.withShowValues sets show_values" {
    const rb1 = RadialBar.init().withShowValues(false);
    const rb2 = rb1.withShowValues(true);

    try testing.expectEqual(false, rb1.show_values);
    try testing.expectEqual(true, rb2.show_values);
}

test "RadialBar.withStyle sets style" {
    const style = Style{ .bold = true };
    const rb = RadialBar.init().withStyle(style);
    try testing.expectEqual(true, rb.style.bold);
}

test "RadialBar.withArcStyle sets arc_style" {
    const style = Style{ .bold = true };
    const rb = RadialBar.init().withArcStyle(style);
    try testing.expectEqual(true, rb.arc_style.bold);
}

test "RadialBar.withFocusedStyle sets focused_style" {
    const style = Style{ .italic = true };
    const rb = RadialBar.init().withFocusedStyle(style);
    try testing.expectEqual(true, rb.focused_style.italic);
}

test "RadialBar.withLabelStyle sets label_style" {
    const style = Style{ .dim = true };
    const rb = RadialBar.init().withLabelStyle(style);
    try testing.expectEqual(true, rb.label_style.dim);
}

test "RadialBar.withEmptyStyle sets empty_style" {
    const style = Style{ .bold = true };
    const rb = RadialBar.init().withEmptyStyle(style);
    try testing.expectEqual(true, rb.empty_style.bold);
}

test "RadialBar.withBlock sets block" {
    const block = Block{};
    const rb = RadialBar.init().withBlock(block);
    try testing.expect(rb.block != null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "RadialBar.render on 0x0 area exits early" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rb.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "RadialBar.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    rb.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "RadialBar.render on 3x3 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 3, 3);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    rb.render(&buf, area);
}

test "RadialBar.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    rb.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 7: Render — Empty Arcs (2 tests)
// ============================================================================

test "RadialBar.render with zero arcs produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const rb = RadialBar.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "RadialBar.render with show_labels=false and no arcs produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const rb = RadialBar.init().withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 8: Render — Single Arc (5 tests)
// ============================================================================

test "RadialBar.render single arc produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render single arc value=0.0 produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.0) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render single arc value=1.0 produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 1.0) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render single arc value=0.5 produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render single arc with empty label produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 9: Render — Multiple Arcs (5 tests)
// ============================================================================

test "RadialBar.render two arcs produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render three arcs produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.2) },
        .{ .label = "MEM", .value = @as(f32, 0.5) },
        .{ .label = "DSK", .value = @as(f32, 0.9) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render four arcs produces content" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.25) },
        .{ .label = "B", .value = @as(f32, 0.5) },
        .{ .label = "C", .value = @as(f32, 0.75) },
        .{ .label = "D", .value = @as(f32, 1.0) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render arcs with different values produces content" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "Low", .value = @as(f32, 0.1) },
        .{ .label = "Mid", .value = @as(f32, 0.5) },
        .{ .label = "High", .value = @as(f32, 0.95) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render all arcs with same value produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.5) },
        .{ .label = "B", .value = @as(f32, 0.5) },
        .{ .label = "C", .value = @as(f32, 0.5) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Value Clamping (4 tests)
// ============================================================================

test "RadialBar.render arc with value > 1.0 treated as full" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 1.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render arc with value < 0.0 treated as empty" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, -0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render arc with value=2.0 clamped to 1.0" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 2.0) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render arc with value=-1.0 clamped to 0.0" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, -1.0) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: MAX_ARCS Capping (3 tests)
// ============================================================================

test "RadialBar.render with exactly MAX_ARCS=8" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var arcs: [8]RadialArc = undefined;
    for (0..8) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 8.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    try testing.expectEqual(@as(usize, 8), rb.arcCount());
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with 10 arcs caps to MAX_ARCS=8" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var arcs: [10]RadialArc = undefined;
    for (0..10) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 10.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    try testing.expectEqual(@as(usize, 8), rb.arcCount());
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render 5 arcs renders all visible arcs" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var arcs: [5]RadialArc = undefined;
    for (0..5) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 5.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: Focused Styling (4 tests)
// ============================================================================

test "RadialBar.render focused=0 on three-arc bar applies focus style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.2) },
        .{ .label = "B", .value = @as(f32, 0.5) },
        .{ .label = "C", .value = @as(f32, 0.8) },
    };
    const focused_style = Style{ .bold = true };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render focused=1 applies style to middle arc" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.2) },
        .{ .label = "B", .value = @as(f32, 0.5) },
        .{ .label = "C", .value = @as(f32, 0.8) },
    };
    const focused_style = Style{ .dim = true };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.3) },
        .{ .label = "B", .value = @as(f32, 0.7) },
    };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render changing focused index produces output" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.2) },
        .{ .label = "B", .value = @as(f32, 0.5) },
        .{ .label = "C", .value = @as(f32, 0.8) },
    };

    const rb1 = RadialBar.init().withArcs(&arcs).withFocused(0);
    const rb2 = RadialBar.init().withArcs(&arcs).withFocused(2);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb1.render(&buf1, area);
    rb2.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

// ============================================================================
// Group 13: show_labels Toggle (3 tests)
// ============================================================================

test "RadialBar.render show_labels=true displays label text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render show_labels=false omits label text" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};

    const rb_with_labels = RadialBar.init().withArcs(&arcs).withShowLabels(true).withShowValues(false);
    const rb_no_labels = RadialBar.init().withArcs(&arcs).withShowLabels(false).withShowValues(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb_with_labels.render(&buf1, area);
    rb_no_labels.render(&buf2, area);

    // Count label text: expect 'C', 'P', 'U' characters in buf1
    var label_chars_with: usize = 0;
    var label_chars_without: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf1.getConst(x, y)) |cell| {
                // Check for label characters: C, P, U
                if (cell.char == 'C' or cell.char == 'P' or cell.char == 'U') {
                    label_chars_with += 1;
                }
            }
            if (buf2.getConst(x, y)) |cell| {
                if (cell.char == 'C' or cell.char == 'P' or cell.char == 'U') {
                    label_chars_without += 1;
                }
            }
        }
    }

    // With show_labels=true, should have at least some label characters
    try testing.expect(label_chars_with > 0);
    // With show_labels=false, should have no label characters
    try testing.expectEqual(@as(usize, 0), label_chars_without);
}

test "RadialBar.render show_labels=false still renders arcs" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };
    const rb = RadialBar.init().withArcs(&arcs).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 14: show_values Toggle (3 tests)
// ============================================================================

test "RadialBar.render show_values=true displays value text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render show_values=false is default behavior" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render show_values=true differs from show_values=false" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};

    const rb_with_values = RadialBar.init().withArcs(&arcs).withShowValues(true);
    const rb_no_values = RadialBar.init().withArcs(&arcs).withShowValues(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb_with_values.render(&buf1, area);
    rb_no_values.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 >= content2);
}

// ============================================================================
// Group 15: Block Border (3 tests)
// ============================================================================

test "RadialBar.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };
    const block = Block{};
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render block reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };

    const block = Block{};
    const rb_with_block = RadialBar.init().withArcs(&arcs).withBlock(block);
    const rb_no_block = RadialBar.init().withArcs(&arcs);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb_with_block.render(&buf1, area);
    rb_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "RadialBar.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };
    const block = (Block{}).withTitle("RadialBar", .top_left);
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Per-Arc Styling (4 tests)
// ============================================================================

test "RadialBar.render arc with custom style differs from arc_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.5), .style = Style{ .bold = true } }
    };
    const rb = RadialBar.init().withArcs(&arcs).withArcStyle(Style{ .dim = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render multiple arcs with different per-arc styles" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.3), .style = Style{ .bold = true } },
        .{ .label = "B", .value = @as(f32, 0.5), .style = Style{ .dim = true } },
        .{ .label = "C", .value = @as(f32, 0.7), .style = Style{ .italic = true } },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render arc with custom style applies correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.5), .style = Style{ .italic = true } }
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render arc with empty custom style uses arc_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.5), .style = Style{} }
    };
    const rb = RadialBar.init().withArcs(&arcs).withArcStyle(Style{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Edge Case Values (4 tests)
// ============================================================================

test "RadialBar.render arc value exactly at boundary 0.0" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.0) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render arc value exactly at boundary 1.0" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 1.0) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render mixed zero and full arcs" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.0) },
        .{ .label = "B", .value = @as(f32, 1.0) },
        .{ .label = "C", .value = @as(f32, 0.0) },
        .{ .label = "D", .value = @as(f32, 1.0) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render very small non-zero values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "T1", .value = @as(f32, 0.01) },
        .{ .label = "T2", .value = @as(f32, 0.001) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 18: Large and Minimal Areas (4 tests)
// ============================================================================

test "RadialBar.render large area (60x40)" {
    var buf = try Buffer.init(testing.allocator, 60, 40);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 40 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render very wide area" {
    var buf = try Buffer.init(testing.allocator, 100, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render very tall area" {
    var buf = try Buffer.init(testing.allocator, 20, 80);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 80 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 19: Style Application (5 tests)
// ============================================================================

test "RadialBar.render with style applies to bar" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const style = Style{ .bold = true };
    const rb = RadialBar.init().withArcs(&arcs).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const label_style = Style{ .italic = true };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with arc_style applies to arcs" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const arc_style = Style{ .dim = true };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withArcStyle(arc_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with empty_style applies to empty ring portions" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "CPU", .value = @as(f32, 0.5) }};
    const empty_style = Style{ .dim = true };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withEmptyStyle(empty_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with multiple styles applied" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.3) },
        .{ .label = "MEM", .value = @as(f32, 0.7) },
    };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withStyle(Style{ .dim = true })
        .withLabelStyle(Style{ .bold = true })
        .withArcStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true, .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Complex Real-World Scenarios (5 tests)
// ============================================================================

test "RadialBar.render system metrics visualization" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.65) },
        .{ .label = "MEM", .value = @as(f32, 0.45) },
        .{ .label = "DISK", .value = @as(f32, 0.82) },
    };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withShowValues(true)
        .withShowLabels(true)
        .withBlock((Block{}).withTitle("System Metrics", .top_center));
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render network usage visualization" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "RX", .value = @as(f32, 0.35) },
        .{ .label = "TX", .value = @as(f32, 0.75) },
    };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withShowValues(true)
        .withShowLabels(true)
        .withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with all features enabled" {
    var buf = try Buffer.init(testing.allocator, 70, 35);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.25), .style = Style{ .bold = true } },
        .{ .label = "B", .value = @as(f32, 0.50) },
        .{ .label = "C", .value = @as(f32, 0.75), .style = Style{ .dim = true } },
        .{ .label = "D", .value = @as(f32, 0.40) },
    };
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withShowValues(true)
        .withShowLabels(true)
        .withFocused(2)
        .withStyle(Style{ .italic = true })
        .withLabelStyle(Style{ .bold = true })
        .withArcStyle(Style{ .dim = false })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withBlock((Block{}).withTitle("Complete RadialBar", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 35 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render single-arc visualization edge case" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{.{ .label = "OnlyOne", .value = @as(f32, 0.50) }};
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withShowValues(true)
        .withShowLabels(true)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render maximum arcs (8) with varied values" {
    var buf = try Buffer.init(testing.allocator, 70, 40);
    defer buf.deinit();
    var arcs: [8]RadialArc = undefined;
    const values = [_]f32{ 0.1, 0.3, 0.5, 0.7, 0.2, 0.6, 0.9, 0.4 };
    for (0..8) |i| {
        arcs[i] = .{
            .label = "M",
            .value = values[i],
        };
    }
    const rb = RadialBar.init()
        .withArcs(&arcs)
        .withShowLabels(true)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 40 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 21: Bounds Checking and Clipping (3 tests)
// ============================================================================

test "RadialBar.render does not exceed buffer bounds with many arcs" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var arcs: [8]RadialArc = undefined;
    for (0..8) |i| {
        arcs[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 8.0 };
    }
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 30 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 1500); // 50*30 max
}

test "RadialBar.render with offset area stays within bounds" {
    var buf = try Buffer.init(testing.allocator, 100, 60);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "CPU", .value = @as(f32, 0.5) },
        .{ .label = "MEM", .value = @as(f32, 0.75) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 30, .y = 15, .width = 40, .height = 25 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render small area with multiple arcs" {
    var buf = try Buffer.init(testing.allocator, 15, 12);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.3) },
        .{ .label = "B", .value = @as(f32, 0.6) },
        .{ .label = "C", .value = @as(f32, 0.9) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 12 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 22: Fractional and Extreme Values (3 tests)
// ============================================================================

test "RadialBar.render with fractional values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "A", .value = @as(f32, 0.125) },
        .{ .label = "B", .value = @as(f32, 0.333) },
        .{ .label = "C", .value = @as(f32, 0.777) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with very large clamped values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "Huge1", .value = @as(f32, 999.99) },
        .{ .label = "Huge2", .value = @as(f32, 1234567.0) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "RadialBar.render with very small positive values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var arcs = [_]RadialArc{
        .{ .label = "Tiny", .value = @as(f32, 0.00001) },
        .{ .label = "Small", .value = @as(f32, 0.0001) },
    };
    const rb = RadialBar.init().withArcs(&arcs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rb.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
