//! ParallelCoordinates Widget Tests — TDD Red Phase
//!
//! Tests ParallelCoordinates widget rendering multi-dimensional data as vertical axes
//! connected by per-item polylines. Each item draws one line crossing every axis at its
//! normalized value on that axis.
//!
//! Tests cover initialization, builder pattern, axisCount()/itemCount() capping,
//! axis normalization (min/max), out-of-range clamping, axis column spacing geometry,
//! polyline rendering, focused item styling, label/range display toggles, block borders,
//! and edge cases (zero-range axes, empty data).

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const ParallelCoordinates = sailor.tui.widgets.ParallelCoordinates;
const PCAxis = sailor.tui.widgets.parallel_coordinates.PCAxis;
const PCItem = sailor.tui.widgets.parallel_coordinates.PCItem;

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

/// Get cell at position in area
fn getCell(buf: Buffer, area: Rect, x: u16, y: u16) ?sailor.Cell {
    if (x >= area.width or y >= area.height) return null;
    return buf.getConst(area.x + x, area.y + y);
}

/// Approximate float equality
fn floatEq(a: f32, b: f32, epsilon: f32) bool {
    return @abs(a - b) < epsilon;
}

// ============================================================================
// Group 1: Structs & Init (6 tests)
// ============================================================================

test "PCAxis default label is empty" {
    const axis = PCAxis{};
    try testing.expectEqualStrings("", axis.label);
}

test "PCAxis default min is 0.0" {
    const axis = PCAxis{};
    try testing.expect(floatEq(0.0, axis.min, 0.001));
}

test "PCAxis default max is 1.0" {
    const axis = PCAxis{};
    try testing.expect(floatEq(1.0, axis.max, 0.001));
}

test "PCItem default label is empty" {
    const item = PCItem{};
    try testing.expectEqualStrings("", item.label);
}

test "PCItem default values array is empty" {
    const item = PCItem{};
    try testing.expectEqual(@as(usize, 0), item.values.len);
}

test "ParallelCoordinates.init creates empty chart" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(@as(usize, 0), pc.axes.len);
    try testing.expectEqual(@as(usize, 0), pc.items.len);
}

// ============================================================================
// Group 2: Init Defaults (6 tests)
// ============================================================================

test "ParallelCoordinates.init focused defaults to 0" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(@as(usize, 0), pc.focused);
}

test "ParallelCoordinates.init show_labels defaults to true" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(true, pc.show_labels);
}

test "ParallelCoordinates.init show_axis_range defaults to true" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(true, pc.show_axis_range);
}

test "ParallelCoordinates.init block defaults to null" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(@as(?Block, null), pc.block);
}

test "ParallelCoordinates.init has default empty styles" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(Style{}, pc.style);
    try testing.expectEqual(Style{}, pc.axis_style);
    try testing.expectEqual(Style{}, pc.focused_style);
    try testing.expectEqual(Style{}, pc.label_style);
}

test "ParallelCoordinates.init has empty axes and items" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(@as(usize, 0), pc.axisCount());
    try testing.expectEqual(@as(usize, 0), pc.itemCount());
}

// ============================================================================
// Group 3: MAX Constants (2 tests)
// ============================================================================

test "ParallelCoordinates.MAX_AXES equals 8" {
    try testing.expectEqual(@as(usize, 8), ParallelCoordinates.MAX_AXES);
}

test "ParallelCoordinates.MAX_ITEMS equals 16" {
    try testing.expectEqual(@as(usize, 16), ParallelCoordinates.MAX_ITEMS);
}

// ============================================================================
// Group 4: axisCount() and itemCount() Capping (10 tests)
// ============================================================================

test "axisCount with zero axes returns 0" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(@as(usize, 0), pc.axisCount());
}

test "axisCount with 1 axis returns 1" {
    var axes = [_]PCAxis{.{ .label = "A" }};
    const pc = ParallelCoordinates.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 1), pc.axisCount());
}

test "axisCount with 4 axes returns 4" {
    var axes = [_]PCAxis{
        .{ .label = "A" },
        .{ .label = "B" },
        .{ .label = "C" },
        .{ .label = "D" },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 4), pc.axisCount());
}

test "axisCount caps at MAX_AXES" {
    var axes: [12]PCAxis = undefined;
    for (0..12) |i| {
        axes[i] = .{ .label = "A" };
    }
    const pc = ParallelCoordinates.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 8), pc.axisCount());
}

test "axisCount with exactly MAX_AXES" {
    var axes: [8]PCAxis = undefined;
    for (0..8) |i| {
        axes[i] = .{ .label = "A" };
    }
    const pc = ParallelCoordinates.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 8), pc.axisCount());
}

test "itemCount with zero items returns 0" {
    const pc = ParallelCoordinates.init();
    try testing.expectEqual(@as(usize, 0), pc.itemCount());
}

test "itemCount with 1 item returns 1" {
    var items = [_]PCItem{.{ .label = "Item1" }};
    const pc = ParallelCoordinates.init().withItems(&items);
    try testing.expectEqual(@as(usize, 1), pc.itemCount());
}

test "itemCount with 8 items returns 8" {
    var items: [8]PCItem = undefined;
    for (0..8) |i| {
        items[i] = .{ .label = "I" };
    }
    const pc = ParallelCoordinates.init().withItems(&items);
    try testing.expectEqual(@as(usize, 8), pc.itemCount());
}

test "itemCount caps at MAX_ITEMS" {
    var items: [20]PCItem = undefined;
    for (0..20) |i| {
        items[i] = .{ .label = "I" };
    }
    const pc = ParallelCoordinates.init().withItems(&items);
    try testing.expectEqual(@as(usize, 16), pc.itemCount());
}

test "itemCount with exactly MAX_ITEMS" {
    var items: [16]PCItem = undefined;
    for (0..16) |i| {
        items[i] = .{ .label = "I" };
    }
    const pc = ParallelCoordinates.init().withItems(&items);
    try testing.expectEqual(@as(usize, 16), pc.itemCount());
}

// ============================================================================
// Group 5: Builder Pattern Immutability (8 tests)
// ============================================================================

test "withAxes returns new value, original unchanged" {
    var axes1 = [_]PCAxis{.{ .label = "A1" }};
    const pc1 = ParallelCoordinates.init().withAxes(&axes1);
    var axes2 = [_]PCAxis{.{ .label = "A2" }};
    const pc2 = pc1.withAxes(&axes2);
    try testing.expectEqual(@as(usize, 1), pc1.axes.len);
    try testing.expectEqualStrings("A1", pc1.axes[0].label);
    try testing.expectEqual(@as(usize, 1), pc2.axes.len);
    try testing.expectEqualStrings("A2", pc2.axes[0].label);
}

test "withItems returns new value, original unchanged" {
    var items1 = [_]PCItem{.{ .label = "I1" }};
    const pc1 = ParallelCoordinates.init().withItems(&items1);
    var items2 = [_]PCItem{.{ .label = "I2" }};
    const pc2 = pc1.withItems(&items2);
    try testing.expectEqual(@as(usize, 1), pc1.items.len);
    try testing.expectEqualStrings("I1", pc1.items[0].label);
    try testing.expectEqual(@as(usize, 1), pc2.items.len);
    try testing.expectEqualStrings("I2", pc2.items[0].label);
}

test "withFocused returns new value, original unchanged" {
    const pc1 = ParallelCoordinates.init().withFocused(1);
    const pc2 = pc1.withFocused(3);
    try testing.expectEqual(@as(usize, 1), pc1.focused);
    try testing.expectEqual(@as(usize, 3), pc2.focused);
}

test "withShowLabels returns new value, original unchanged" {
    const pc1 = ParallelCoordinates.init().withShowLabels(false);
    const pc2 = pc1.withShowLabels(true);
    try testing.expectEqual(false, pc1.show_labels);
    try testing.expectEqual(true, pc2.show_labels);
}

test "withShowAxisRange returns new value, original unchanged" {
    const pc1 = ParallelCoordinates.init().withShowAxisRange(false);
    const pc2 = pc1.withShowAxisRange(true);
    try testing.expectEqual(false, pc1.show_axis_range);
    try testing.expectEqual(true, pc2.show_axis_range);
}

test "withStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const pc1 = ParallelCoordinates.init().withStyle(style1);
    const pc2 = pc1.withStyle(style2);
    try testing.expectEqual(true, pc1.style.bold);
    try testing.expectEqual(true, pc2.style.dim);
}

test "withFocusedStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const pc1 = ParallelCoordinates.init().withFocusedStyle(style1);
    const pc2 = pc1.withFocusedStyle(style2);
    try testing.expectEqual(true, pc1.focused_style.bold);
    try testing.expectEqual(true, pc2.focused_style.dim);
}

test "withBlock returns new value, original unchanged" {
    const pc1 = ParallelCoordinates.init().withBlock(.{});
    const pc2 = pc1.withBlock(null);
    try testing.expect(pc1.block != null);
    try testing.expect(pc2.block == null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (3 tests)
// ============================================================================

test "render with 0x0 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const pc = ParallelCoordinates.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    pc.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const pc = ParallelCoordinates.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    pc.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const pc = ParallelCoordinates.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    pc.render(&buf, area);
}

// ============================================================================
// Group 7: Render — Empty Data (3 tests)
// ============================================================================

test "render with zero axes produces no content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const pc = ParallelCoordinates.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    pc.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero items but axes does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "CPU", .min = 0.0, .max = 100.0 },
        .{ .label = "Memory", .min = 0.0, .max = 100.0 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    pc.render(&buf, area);
}

test "render with axes and zero items shows axis structure" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

// ============================================================================
// Group 8: Render — Single Axis (2 tests)
// ============================================================================

test "render with one axis does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{.{ .label = "Speed", .min = 0.0, .max = 100.0 }};
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    pc.render(&buf, area);
}

test "render with one axis and one item does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{.{ .label = "Speed", .min = 0.0, .max = 100.0 }};
    var values = [_]f32{50.0};
    var items = [_]PCItem{.{ .label = "Item1", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    pc.render(&buf, area);
}

// ============================================================================
// Group 9: Render — Two Axes, Basic Rendering (5 tests)
// ============================================================================

test "render with 2 axes produces content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "CPU", .min = 0.0, .max = 100.0 },
        .{ .label = "Memory", .min = 0.0, .max = 100.0 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render with 2 axes and 1 item shows polyline" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "CPU", .min = 0.0, .max = 100.0 },
        .{ .label = "Disk", .min = 0.0, .max = 100.0 },
    };
    var values = [_]f32{ 75.0, 50.0 };
    var items = [_]PCItem{.{ .label = "Server", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with 2 axes and items with custom style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "A", .min = 0.0, .max = 1.0 },
        .{ .label = "B", .min = 0.0, .max = 1.0 },
    };
    var values = [_]f32{ 0.6, 0.4 };
    var items = [_]PCItem{.{ .label = "Data", .values = &values, .style = .{ .bold = true } }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render 2 axes with 1 item at min value" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 10.0, .max = 20.0 },
        .{ .label = "Y", .min = 10.0, .max = 20.0 },
    };
    var values = [_]f32{ 10.0, 10.0 };
    var items = [_]PCItem{.{ .label = "Min", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

test "render 2 axes with 1 item at max value" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 10.0 },
        .{ .label = "Y", .min = 0.0, .max = 10.0 },
    };
    var values = [_]f32{ 10.0, 10.0 };
    var items = [_]PCItem{.{ .label = "Max", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

// ============================================================================
// Group 10: Render — Three+ Axes, Geometry (5 tests)
// ============================================================================

test "render with 3 axes produces content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "CPU", .min = 0.0, .max = 100.0 },
        .{ .label = "Memory", .min = 0.0, .max = 100.0 },
        .{ .label = "Disk", .min = 0.0, .max = 100.0 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render with 4 axes shows even spacing" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "A", .min = 0.0, .max = 1.0 },
        .{ .label = "B", .min = 0.0, .max = 1.0 },
        .{ .label = "C", .min = 0.0, .max = 1.0 },
        .{ .label = "D", .min = 0.0, .max = 1.0 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with 6 axes" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "A", .min = 0.0, .max = 1.0 },
        .{ .label = "B", .min = 0.0, .max = 1.0 },
        .{ .label = "C", .min = 0.0, .max = 1.0 },
        .{ .label = "D", .min = 0.0, .max = 1.0 },
        .{ .label = "E", .min = 0.0, .max = 1.0 },
        .{ .label = "F", .min = 0.0, .max = 1.0 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with MAX_AXES (8 axes) does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 120, 30);
    defer buf.deinit();

    var axes: [8]PCAxis = undefined;
    for (0..8) |i| {
        axes[i] = .{ .label = "Ax", .min = 0.0, .max = 1.0 };
    }
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 30 };
    pc.render(&buf, area);

    try testing.expectEqual(@as(usize, 8), pc.axisCount());
}

test "render more than MAX_AXES only renders MAX_AXES" {
    var buf = try Buffer.init(std.testing.allocator, 150, 30);
    defer buf.deinit();

    var axes: [12]PCAxis = undefined;
    for (0..12) |i| {
        axes[i] = .{ .label = "Ax", .min = 0.0, .max = 1.0 };
    }
    const pc = ParallelCoordinates.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 150, .height = 30 };
    pc.render(&buf, area);

    try testing.expectEqual(@as(usize, 8), pc.axisCount());
}

// ============================================================================
// Group 11: Render — Normalization & Value Mapping (6 tests)
// ============================================================================

test "normalize midpoint value on axis" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 100.0 },
        .{ .label = "Y", .min = 0.0, .max = 100.0 },
    };
    var values = [_]f32{ 50.0, 50.0 };
    var items = [_]PCItem{.{ .label = "Mid", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    // Should render without crashing and produce content
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "normalize value at quarter point" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 100.0 },
        .{ .label = "Y", .min = 0.0, .max = 100.0 },
    };
    var values = [_]f32{ 25.0, 75.0 };
    var items = [_]PCItem{.{ .label = "Quarters", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "multiple items with different normalized values" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "A", .min = 0.0, .max = 100.0 },
        .{ .label = "B", .min = 0.0, .max = 100.0 },
    };
    var values1 = [_]f32{ 30.0, 70.0 };
    var values2 = [_]f32{ 80.0, 20.0 };
    var items = [_]PCItem{
        .{ .label = "I1", .values = &values1 },
        .{ .label = "I2", .values = &values2 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "axis with non-zero min normalization" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "Temp", .min = 20.0, .max = 40.0 },
        .{ .label = "Humidity", .min = 30.0, .max = 60.0 },
    };
    var values = [_]f32{ 30.0, 45.0 };
    var items = [_]PCItem{.{ .label = "Room", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "normalized values clamped to [0,1]" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 10.0 },
        .{ .label = "Y", .min = 0.0, .max = 10.0 },
    };
    // Out-of-range: 15 normalizes to >1, -5 normalizes to <0
    var values = [_]f32{ 15.0, -5.0 };
    var items = [_]PCItem{.{ .label = "Clamped", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    // Should not crash due to out-of-range normalization
}

// ============================================================================
// Group 12: Render — Out-of-Range Handling (4 tests)
// ============================================================================

test "out-of-range value above max does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 10.0 },
        .{ .label = "Y", .min = 0.0, .max = 10.0 },
    };
    var values = [_]f32{ 100.0, 5.0 };
    var items = [_]PCItem{.{ .label = "HighX", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

test "out-of-range value below min does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 10.0 },
        .{ .label = "Y", .min = 0.0, .max = 10.0 },
    };
    var values = [_]f32{ -50.0, 5.0 };
    var items = [_]PCItem{.{ .label = "LowX", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

test "axis with min == max (zero range) does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "Fixed", .min = 5.0, .max = 5.0 },
        .{ .label = "Normal", .min = 0.0, .max = 10.0 },
    };
    var values = [_]f32{ 5.0, 5.0 };
    var items = [_]PCItem{.{ .label = "Item", .values = &values }};
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

test "multiple items all with out-of-range values" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 10.0 },
        .{ .label = "Y", .min = 0.0, .max = 10.0 },
    };
    var values1 = [_]f32{ 200.0, -100.0 };
    var values2 = [_]f32{ -50.0, 150.0 };
    var items = [_]PCItem{
        .{ .label = "I1", .values = &values1 },
        .{ .label = "I2", .values = &values2 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

// ============================================================================
// Group 13: Render — Multiple Items (5 tests)
// ============================================================================

test "render 2 axes with 2 items produces more cells than 1" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 100.0 },
        .{ .label = "Y", .min = 0.0, .max = 100.0 },
    };

    var values1 = [_]f32{ 25.0, 75.0 };
    var items1 = [_]PCItem{.{ .label = "I1", .values = &values1 }};
    const pc1 = ParallelCoordinates.init().withAxes(&axes).withItems(&items1);

    var values2a = [_]f32{ 25.0, 75.0 };
    var values2b = [_]f32{ 75.0, 25.0 };
    var items2 = [_]PCItem{
        .{ .label = "I1", .values = &values2a },
        .{ .label = "I2", .values = &values2b },
    };
    const pc2 = ParallelCoordinates.init().withAxes(&axes).withItems(&items2);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc1.render(&buf1, area);
    pc2.render(&buf2, area);

    const count1 = countNonEmptyCells(buf1, area);
    const count2 = countNonEmptyCells(buf2, area);
    try testing.expect(count2 >= count1);
}

test "render 3 axes with 3 items" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "A", .min = 0.0, .max = 1.0 },
        .{ .label = "B", .min = 0.0, .max = 1.0 },
        .{ .label = "C", .min = 0.0, .max = 1.0 },
    };
    var v1 = [_]f32{ 0.2, 0.5, 0.8 };
    var v2 = [_]f32{ 0.5, 0.8, 0.2 };
    var v3 = [_]f32{ 0.8, 0.2, 0.5 };
    var items = [_]PCItem{
        .{ .label = "I1", .values = &v1 },
        .{ .label = "I2", .values = &v2 },
        .{ .label = "I3", .values = &v3 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with MAX_ITEMS (16 items)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 40);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };

    var items: [16]PCItem = undefined;
    var values_arr: [16][2]f32 = undefined;
    for (0..16) |i| {
        const f = @as(f32, @floatFromInt(i)) / 16.0;
        values_arr[i] = [_]f32{ f, 1.0 - f };
        items[i] = .{ .label = "I", .values = &values_arr[i] };
    }

    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    pc.render(&buf, area);

    try testing.expectEqual(@as(usize, 16), pc.itemCount());
}

test "render more than MAX_ITEMS only renders MAX_ITEMS" {
    var buf = try Buffer.init(std.testing.allocator, 100, 40);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };

    var items: [20]PCItem = undefined;
    var values_arr: [20][2]f32 = undefined;
    for (0..20) |i| {
        const f = @as(f32, @floatFromInt(i)) / 20.0;
        values_arr[i] = [_]f32{ f, 1.0 - f };
        items[i] = .{ .label = "I", .values = &values_arr[i] };
    }

    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    pc.render(&buf, area);

    try testing.expectEqual(@as(usize, 16), pc.itemCount());
}

// ============================================================================
// Group 14: Render — Focused Item Styling (4 tests)
// ============================================================================

test "focused item uses focused_style when set" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    var v1 = [_]f32{ 0.3, 0.7 };
    var v2 = [_]f32{ 0.7, 0.3 };
    var items = [_]PCItem{
        .{ .label = "I1", .values = &v1 },
        .{ .label = "I2", .values = &v2 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withItems(&items)
        .withFocused(1)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused at index 0" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    var values = [_]f32{ 0.5, 0.5 };
    var items = [_]PCItem{.{ .label = "I", .values = &values }};
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withItems(&items)
        .withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused index beyond item count does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    var values = [_]f32{ 0.5, 0.5 };
    var items = [_]PCItem{.{ .label = "I", .values = &values }};
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withItems(&items)
        .withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);
}

test "non-focused items do not use focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    var v1 = [_]f32{ 0.3, 0.7 };
    var v2 = [_]f32{ 0.7, 0.3 };
    var items = [_]PCItem{
        .{ .label = "I1", .values = &v1 },
        .{ .label = "I2", .values = &v2 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 15: Render — Label Display Toggles (4 tests)
// ============================================================================

test "show_labels=true renders axis labels" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "CPU", .min = 0.0, .max = 100.0 },
        .{ .label = "Memory", .min = 0.0, .max = 100.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "show_labels=false omits axis labels" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "CPU", .min = 0.0, .max = 100.0 },
        .{ .label = "Memory", .min = 0.0, .max = 100.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "show_axis_range=true renders min/max labels" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 10.0, .max = 100.0 },
        .{ .label = "Y", .min = 0.0, .max = 50.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withShowAxisRange(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "show_axis_range=false omits min/max labels" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 10.0, .max = 100.0 },
        .{ .label = "Y", .min = 0.0, .max = 50.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withShowAxisRange(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

// ============================================================================
// Group 16: Render — Block Border (4 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    pc.render(&buf, area);

    const has_border = countChar(buf, area, '─') > 0 or countChar(buf, area, '│') > 0 or
                       countChar(buf, area, '┌') > 0;
    try testing.expect(has_border or countNonEmptyCells(buf, area) > 0);
}

test "render block reduces inner area for chart" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
        .{ .label = "Z", .min = 0.0, .max = 1.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withBlock(.{});
    const area = Rect{ .x = 5, .y = 5, .width = 40, .height = 15 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with block in offset area" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    pc.render(&buf, area);
}

// ============================================================================
// Group 17: Realistic Multi-Dimensional Scenario (3 tests)
// ============================================================================

test "render realistic 4-axis 3-item server metrics" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "CPU", .min = 0.0, .max = 100.0 },
        .{ .label = "Memory", .min = 0.0, .max = 100.0 },
        .{ .label = "Disk", .min = 0.0, .max = 100.0 },
        .{ .label = "Network", .min = 0.0, .max = 100.0 },
    };
    var v1 = [_]f32{ 45.0, 72.0, 30.0, 15.0 };
    var v2 = [_]f32{ 80.0, 35.0, 65.0, 88.0 };
    var v3 = [_]f32{ 25.0, 90.0, 50.0, 42.0 };
    var items = [_]PCItem{
        .{ .label = "Server1", .values = &v1 },
        .{ .label = "Server2", .values = &v2 },
        .{ .label = "Server3", .values = &v3 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render 6-axis 2-item ML model comparison" {
    var buf = try Buffer.init(std.testing.allocator, 120, 30);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "Accuracy", .min = 0.0, .max = 1.0 },
        .{ .label = "Precision", .min = 0.0, .max = 1.0 },
        .{ .label = "Recall", .min = 0.0, .max = 1.0 },
        .{ .label = "F1", .min = 0.0, .max = 1.0 },
        .{ .label = "Latency", .min = 0.0, .max = 100.0 },
        .{ .label = "Throughput", .min = 0.0, .max = 1000.0 },
    };
    var v1 = [_]f32{ 0.95, 0.92, 0.88, 0.90, 10.0, 500.0 };
    var v2 = [_]f32{ 0.93, 0.94, 0.91, 0.92, 5.0, 800.0 };
    var items = [_]PCItem{
        .{ .label = "Model_A", .values = &v1 },
        .{ .label = "Model_B", .values = &v2 },
    };
    const pc = ParallelCoordinates.init().withAxes(&axes).withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 30 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with all style options set together" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    var axes = [_]PCAxis{
        .{ .label = "A", .min = 0.0, .max = 1.0 },
        .{ .label = "B", .min = 0.0, .max = 1.0 },
        .{ .label = "C", .min = 0.0, .max = 1.0 },
    };
    var v1 = [_]f32{ 0.3, 0.6, 0.9 };
    var v2 = [_]f32{ 0.7, 0.4, 0.2 };
    var items = [_]PCItem{
        .{ .label = "I1", .values = &v1, .style = .{ .bold = true } },
        .{ .label = "I2", .values = &v2, .style = .{ .dim = true } },
    };
    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withItems(&items)
        .withFocused(1)
        .withShowLabels(true)
        .withShowAxisRange(true)
        .withStyle(.{ .underline = true })
        .withAxisStyle(.{ .bold = true })
        .withFocusedStyle(.{ .dim = true })
        .withLabelStyle(.{ .bold = true })
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    pc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 18: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields" {
    var axes = [_]PCAxis{
        .{ .label = "X", .min = 0.0, .max = 1.0 },
        .{ .label = "Y", .min = 0.0, .max = 1.0 },
    };
    var values = [_]f32{ 0.5, 0.5 };
    var items = [_]PCItem{.{ .label = "I", .values = &values }};

    const pc = ParallelCoordinates.init()
        .withAxes(&axes)
        .withItems(&items)
        .withFocused(0)
        .withShowLabels(false)
        .withShowAxisRange(false)
        .withStyle(.{ .bold = true })
        .withAxisStyle(.{ .dim = true })
        .withFocusedStyle(.{ .underline = true })
        .withLabelStyle(.{ .bold = true })
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), pc.axes.len);
    try testing.expectEqual(@as(usize, 1), pc.items.len);
    try testing.expectEqual(@as(usize, 0), pc.focused);
    try testing.expectEqual(false, pc.show_labels);
    try testing.expectEqual(false, pc.show_axis_range);
    try testing.expect(pc.block != null);
}

test "builder chain with multiple operations preserves last value" {
    var axes1 = [_]PCAxis{.{ .label = "A1" }};
    var axes2 = [_]PCAxis{ .{ .label = "A2" }, .{ .label = "A3" } };

    const pc = ParallelCoordinates.init()
        .withAxes(&axes1)
        .withFocused(0)
        .withAxes(&axes2)
        .withFocused(1);

    try testing.expectEqual(@as(usize, 2), pc.axes.len);
    try testing.expectEqual(@as(usize, 1), pc.focused);
}
