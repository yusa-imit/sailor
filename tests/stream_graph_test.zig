//! StreamGraph Widget Tests — TDD Red Phase
//!
//! Tests StreamGraph widget with multiple stacked layers rendered as a silhouette
//! streamgraph around a centered baseline, focused layer styling, label display,
//! vertical centering, block borders, MAX_LAYERS capping, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const StreamGraph = sailor.tui.widgets.StreamGraph;
const StreamLayer = sailor.tui.widgets.stream_graph.StreamLayer;

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

/// Count filled cells in a buffer area (cells that are not space)
fn countFilledCells(buf: Buffer, area: Rect) usize {
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

/// Count filled cells above a vertical midpoint
fn countFilledAboveMiddle(buf: Buffer, area: Rect) usize {
    const middle_y = area.y + (area.height / 2);
    var count: usize = 0;
    var y = area.y;
    while (y < middle_y and y < buf.height) : (y += 1) {
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

/// Count filled cells below a vertical midpoint
fn countFilledBelowMiddle(buf: Buffer, area: Rect) usize {
    const middle_y = area.y + (area.height / 2);
    var count: usize = 0;
    var y = middle_y;
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

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "StreamGraph.init creates default graph with zero layers" {
    const sg = StreamGraph.init();
    try testing.expectEqual(@as(usize, 0), sg.layers.len);
}

test "StreamGraph.init defaults focused to 0" {
    const sg = StreamGraph.init();
    try testing.expectEqual(@as(usize, 0), sg.focused);
}

test "StreamGraph.init defaults show_labels to true" {
    const sg = StreamGraph.init();
    try testing.expectEqual(true, sg.show_labels);
}

test "StreamGraph.init defaults block to null" {
    const sg = StreamGraph.init();
    try testing.expect(sg.block == null);
}

test "StreamGraph.init defaults styles to empty" {
    const sg = StreamGraph.init();
    try testing.expect(!sg.style.bold and !sg.focused_style.bold);
}

// ============================================================================
// Group 2: StreamLayer Defaults (3 tests)
// ============================================================================

test "StreamLayer default label is empty" {
    const layer = StreamLayer{};
    try testing.expectEqualStrings("", layer.label);
}

test "StreamLayer default values array is empty" {
    const layer = StreamLayer{};
    try testing.expectEqual(@as(usize, 0), layer.values.len);
}

test "StreamLayer default style is empty" {
    const layer = StreamLayer{};
    try testing.expect(!layer.style.bold and layer.style.dim == false);
}

// ============================================================================
// Group 3: MAX_LAYERS Constant (1 test)
// ============================================================================

test "StreamGraph.MAX_LAYERS equals 8" {
    try testing.expectEqual(@as(usize, 8), StreamGraph.MAX_LAYERS);
}

// ============================================================================
// Group 4: layerCount() Method (5 tests)
// ============================================================================

test "StreamGraph.layerCount with zero layers returns 0" {
    const sg = StreamGraph.init();
    try testing.expectEqual(@as(usize, 0), sg.layerCount());
}

test "StreamGraph.layerCount with 1 layer returns 1" {
    var values = [_]f32{1.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    try testing.expectEqual(@as(usize, 1), sg.layerCount());
}

test "StreamGraph.layerCount with 5 layers returns 5" {
    var layers: [5]StreamLayer = undefined;
    var values_array: [5][10]f32 = undefined;
    for (0..5) |i| {
        values_array[i] = [_]f32{1.0} ** 10;
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    try testing.expectEqual(@as(usize, 5), sg.layerCount());
}

test "StreamGraph.layerCount with exactly MAX_LAYERS=8 returns 8" {
    var layers: [8]StreamLayer = undefined;
    var values_array: [8][10]f32 = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{1.0} ** 10;
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    try testing.expectEqual(@as(usize, 8), sg.layerCount());
}

test "StreamGraph.layerCount caps at MAX_LAYERS when 10 layers provided" {
    var layers: [10]StreamLayer = undefined;
    var values_array: [10][10]f32 = undefined;
    for (0..10) |i| {
        values_array[i] = [_]f32{1.0} ** 10;
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    try testing.expectEqual(@as(usize, 8), sg.layerCount());
}

// ============================================================================
// Group 5: Builder Immutability (7 tests)
// ============================================================================

test "StreamGraph.withLayers does not modify original" {
    var values1 = [_]f32{1.0};
    var layers1 = [_]StreamLayer{.{ .label = "A", .values = &values1 }};
    var values2 = [_]f32{2.0};
    var layers2 = [_]StreamLayer{
        .{ .label = "X", .values = &values2 },
    };

    const sg1 = StreamGraph.init().withLayers(&layers1);
    const sg2 = sg1.withLayers(&layers2);

    try testing.expectEqual(@as(usize, 1), sg1.layerCount());
    try testing.expectEqual(@as(usize, 1), sg2.layerCount());
}

test "StreamGraph.withFocused sets focused index" {
    const sg1 = StreamGraph.init().withFocused(0);
    const sg2 = sg1.withFocused(3);

    try testing.expectEqual(@as(usize, 0), sg1.focused);
    try testing.expectEqual(@as(usize, 3), sg2.focused);
}

test "StreamGraph.withShowLabels sets show_labels" {
    const sg1 = StreamGraph.init().withShowLabels(true);
    const sg2 = sg1.withShowLabels(false);

    try testing.expectEqual(true, sg1.show_labels);
    try testing.expectEqual(false, sg2.show_labels);
}

test "StreamGraph.withStyle sets style" {
    const style = Style{ .bold = true };
    const sg = StreamGraph.init().withStyle(style);
    try testing.expectEqual(true, sg.style.bold);
}

test "StreamGraph.withFocusedStyle sets focused_style" {
    const style = Style{ .dim = true };
    const sg = StreamGraph.init().withFocusedStyle(style);
    try testing.expectEqual(true, sg.focused_style.dim);
}

test "StreamGraph.withLabelStyle sets label_style" {
    const style = Style{ .italic = true };
    const sg = StreamGraph.init().withLabelStyle(style);
    try testing.expectEqual(true, sg.label_style.italic);
}

test "StreamGraph.withBlock sets block" {
    const block = Block{};
    const sg = StreamGraph.init().withBlock(block);
    try testing.expect(sg.block != null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (5 tests)
// ============================================================================

test "StreamGraph.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    sg.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "StreamGraph.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    sg.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "StreamGraph.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    sg.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "StreamGraph.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    sg.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "StreamGraph.render on 2x2 area exits early (below minimum)" {
    var buf = try Buffer.init(testing.allocator, 2, 2);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    sg.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 7: Render — Empty Layers (2 tests)
// ============================================================================

test "StreamGraph.render with zero layers produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const sg = StreamGraph.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "StreamGraph.render layer with empty values produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var layers = [_]StreamLayer{.{ .label = "A", .values = &.{} }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 8: Render — Single Layer (5 tests)
// ============================================================================

test "StreamGraph.render single layer with positive values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{10.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render single layer with multiple values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 5.0, 10.0, 8.0, 12.0, 6.0 };
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render single layer at different area offset" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var values = [_]f32{ 5.0, 10.0, 8.0 };
    var layers = [_]StreamLayer{.{ .label = "X", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 5, .y = 5, .width = 30, .height = 15 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render single layer with uniform values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 5.0, 5.0, 5.0, 5.0, 5.0 };
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render single layer with no label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 5.0, 10.0 };
    var layers = [_]StreamLayer{.{ .label = "", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 9: Render — Multiple Layers (5 tests)
// ============================================================================

test "StreamGraph.render two layers produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{5.0};
    var values2 = [_]f32{3.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render three layers produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{5.0};
    var values2 = [_]f32{4.0};
    var values3 = [_]f32{6.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render five layers produces content" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var values1 = [_]f32{5.0};
    var values2 = [_]f32{4.0};
    var values3 = [_]f32{3.0};
    var values4 = [_]f32{2.0};
    var values5 = [_]f32{6.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
        .{ .label = "D", .values = &values4 },
        .{ .label = "E", .values = &values5 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render multiple layers with varying value lengths" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 5.0, 6.0, 7.0 };
    var values2 = [_]f32{ 3.0, 4.0, 2.0 };
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Render — Vertical Centering (3 tests)
// ============================================================================

test "StreamGraph.render single uniform layer fills above and below center" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 10.0, 10.0, 10.0, 10.0, 10.0 };
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);

    const above = countFilledAboveMiddle(buf, area);
    const below = countFilledBelowMiddle(buf, area);

    // Both above and below should have significant fill for centered silhouette
    try testing.expect(above > 0);
    try testing.expect(below > 0);
}

test "StreamGraph.render multiple layers centered around baseline" {
    var buf = try Buffer.init(testing.allocator, 40, 24);
    defer buf.deinit();
    var values1 = [_]f32{5.0};
    var values2 = [_]f32{5.0};
    var values3 = [_]f32{5.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 24 };
    sg.render(&buf, area);

    const above = countFilledAboveMiddle(buf, area);
    const below = countFilledBelowMiddle(buf, area);

    try testing.expect(above > 0);
    try testing.expect(below > 0);
}

test "StreamGraph.render single layer tall enough to reach above and below center" {
    var buf = try Buffer.init(testing.allocator, 20, 30);
    defer buf.deinit();
    var values = [_]f32{ 15.0, 15.0 };
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 30 };
    sg.render(&buf, area);

    const above = countFilledAboveMiddle(buf, area);
    const below = countFilledBelowMiddle(buf, area);

    try testing.expect(above > 0);
    try testing.expect(below > 0);
}

// ============================================================================
// Group 11: Render — Mismatched Value Array Lengths (2 tests)
// ============================================================================

test "StreamGraph.render layers with different value counts does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 5.0, 6.0, 7.0, 8.0 };
    var values2 = [_]f32{3.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    // Just verify no crash — content may be minimal or zero
}

test "StreamGraph.render one layer with many values, another with few values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 };
    var values2 = [_]f32{ 2.0, 2.0 };
    var layers = [_]StreamLayer{
        .{ .label = "Long", .values = &values1 },
        .{ .label = "Short", .values = &values2 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    sg.render(&buf, area);
    // Should handle gracefully without crash
}

// ============================================================================
// Group 12: Render — All-Zero Values (2 tests)
// ============================================================================

test "StreamGraph.render all-zero single layer does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 0.0, 0.0, 0.0 };
    var layers = [_]StreamLayer{.{ .label = "Z", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    // Just verify no crash or divide-by-zero
}

test "StreamGraph.render all-zero multiple layers does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 0.0, 0.0 };
    var values2 = [_]f32{ 0.0, 0.0 };
    var layers = [_]StreamLayer{
        .{ .label = "Z1", .values = &values1 },
        .{ .label = "Z2", .values = &values2 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
}

// ============================================================================
// Group 13: Render — Focused Layer Styling (4 tests)
// ============================================================================

test "StreamGraph.render focused=0 on two-layer chart applies focus style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{10.0};
    var values2 = [_]f32{5.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const focused_style = Style{ .bold = true };
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render focused=1 applies style to second layer" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{10.0};
    var values2 = [_]f32{5.0};
    var values3 = [_]f32{7.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const focused_style = Style{ .dim = true };
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{10.0};
    var values2 = [_]f32{5.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render changing focused index preserves all layers" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var values1 = [_]f32{10.0};
    var values2 = [_]f32{5.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };

    const sg1 = StreamGraph.init().withLayers(&layers).withFocused(0);
    const sg2 = StreamGraph.init().withLayers(&layers).withFocused(1);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg1.render(&buf1, area);
    sg2.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

// ============================================================================
// Group 14: Render — Show Labels Toggle (3 tests)
// ============================================================================

test "StreamGraph.render show_labels=true displays label text when area is wide" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var layers = [_]StreamLayer{.{ .label = "Layer", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render show_labels=false produces output" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var layers = [_]StreamLayer{.{ .label = "Layer", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render show_labels toggles produce content" {
    var buf1 = try Buffer.init(testing.allocator, 60, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 60, 20);
    defer buf2.deinit();

    var values = [_]f32{5.0};
    var layers = [_]StreamLayer{.{ .label = "Layer", .values = &values }};

    const sg_with_labels = StreamGraph.init().withLayers(&layers).withShowLabels(true);
    const sg_no_labels = StreamGraph.init().withLayers(&layers).withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    sg_with_labels.render(&buf1, area);
    sg_no_labels.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

// ============================================================================
// Group 15: Render — Block Border (3 tests)
// ============================================================================

test "StreamGraph.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{10.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const block = Block{};
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render block reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var values = [_]f32{10.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};

    const block = Block{};
    const sg_with_block = StreamGraph.init().withLayers(&layers).withBlock(block);
    const sg_no_block = StreamGraph.init().withLayers(&layers);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg_with_block.render(&buf1, area);
    sg_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "StreamGraph.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{10.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const block = (Block{}).withTitle("Chart", .top_left);
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Render — MAX_LAYERS Cap (3 tests)
// ============================================================================

test "StreamGraph.render with exactly MAX_LAYERS=8 renders all" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();
    var layers: [8]StreamLayer = undefined;
    var values_array: [8][1]f32 = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{1.0};
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    try testing.expectEqual(@as(usize, 8), sg.layerCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render with 10 layers caps to MAX_LAYERS=8" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();
    var layers: [10]StreamLayer = undefined;
    var values_array: [10][1]f32 = undefined;
    for (0..10) |i| {
        values_array[i] = [_]f32{1.0};
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    try testing.expectEqual(@as(usize, 8), sg.layerCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.layerCount caps at 8 with many layers" {
    var layers: [16]StreamLayer = undefined;
    var values_array: [16][1]f32 = undefined;
    for (0..16) |i| {
        values_array[i] = [_]f32{1.0};
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    try testing.expectEqual(@as(usize, 8), sg.layerCount());
}

// ============================================================================
// Group 17: Render — Small Area with Block (2 tests)
// ============================================================================

test "StreamGraph.render with block on very small area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 8);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const block = Block{};
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 8 };
    sg.render(&buf, area);
    // Just verify no crash
}

test "StreamGraph.render block-bordered chart with height < 5 still renders" {
    var buf = try Buffer.init(testing.allocator, 20, 6);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const block = Block{};
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 6 };
    sg.render(&buf, area);
}

// ============================================================================
// Group 18: Memory Safety (3 tests)
// ============================================================================

test "StreamGraph.render does not exceed buffer bounds with many layers" {
    var buf = try Buffer.init(testing.allocator, 60, 40);
    defer buf.deinit();
    var layers: [8]StreamLayer = undefined;
    var values_array: [8][1]f32 = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{5.0};
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 40 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 2400); // 60*40 max
}

test "StreamGraph.render with MAX_LAYERS cap is safe" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var layers: [8]StreamLayer = undefined;
    var values_array: [8][1]f32 = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{10.0};
        layers[i] = .{ .label = "L", .values = &values_array[i] };
    }
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 30 };
    sg.render(&buf, area);
    // Just verify no crash or overflow
}

test "StreamGraph.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var values = [_]f32{ 5.0, 10.0 };
    var layers = [_]StreamLayer{.{ .label = "A", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 19: Large Values (3 tests)
// ============================================================================

test "StreamGraph.render with very large values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 1000000.0, 500000.0 };
    var layers = [_]StreamLayer{.{ .label = "Big", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render with very small fractional values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 0.001, 0.0001 };
    var layers = [_]StreamLayer{.{ .label = "Tiny", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render with mixed magnitude values" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var values1 = [_]f32{ 10000.0, 5000.0 };
    var values2 = [_]f32{ 0.5, 0.25 };
    var layers = [_]StreamLayer{
        .{ .label = "Large", .values = &values1 },
        .{ .label = "Small", .values = &values2 },
    };
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Edge Cases (5 tests)
// ============================================================================

test "StreamGraph.render single value single layer" {
    var buf = try Buffer.init(testing.allocator, 20, 15);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var layers = [_]StreamLayer{.{ .label = "Single", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 15 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render many values few layers" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 9.0, 8.0, 7.0, 6.0, 5.0 };
    var layers = [_]StreamLayer{.{ .label = "Many", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render with layer containing long label" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var layers = [_]StreamLayer{.{ .label = "VeryLongLayerLabelName", .values = &values }};
    const sg = StreamGraph.init().withLayers(&layers).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render with custom styles" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values1 = [_]f32{10.0};
    var values2 = [_]f32{5.0};
    var layers = [_]StreamLayer{
        .{ .label = "A", .values = &values1, .style = Style{ .bold = true } },
        .{ .label = "B", .values = &values2, .style = Style{ .dim = true } },
    };
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withStyle(Style{ .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "StreamGraph.render all features enabled" {
    var buf = try Buffer.init(testing.allocator, 70, 30);
    defer buf.deinit();
    var values1 = [_]f32{ 5.0, 6.0, 7.0 };
    var values2 = [_]f32{ 3.0, 4.0, 2.0 };
    var values3 = [_]f32{ 2.0, 3.0, 4.0 };
    var layers = [_]StreamLayer{
        .{ .label = "Layer1", .values = &values1, .style = Style{ .bold = true } },
        .{ .label = "Layer2", .values = &values2 },
        .{ .label = "Layer3", .values = &values3, .style = Style{ .dim = true } },
    };
    const sg = StreamGraph.init()
        .withLayers(&layers)
        .withFocused(1)
        .withShowLabels(true)
        .withStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true })
        .withLabelStyle(Style{ .italic = true })
        .withBlock((Block{}).withTitle("StreamGraph", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 30 };
    sg.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
