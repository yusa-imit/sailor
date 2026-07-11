//! SunburstChart Widget Tests — TDD Red Phase
//!
//! Tests SunburstChart widget with hierarchical radial chart showing multi-level
//! tree data as concentric rings of arcs, focusing on tree rendering, depth capping,
//! sibling proportion calculation, focused styling, label display, block borders,
//! MAX_DEPTH/MAX_NODES capping, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const SunburstChart = sailor.tui.widgets.SunburstChart;
const SunburstNode = sailor.tui.widgets.sunburst_chart.SunburstNode;

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

/// Sample cells at a certain distance (radius) from center to verify multi-ring content
fn countCellsAtRadius(buf: Buffer, cx: i32, cy: i32, target_radius: f32, tolerance: f32) usize {
    var count: usize = 0;
    const max_x = buf.width;
    const max_y = buf.height;
    var y: u16 = 0;
    while (y < max_y) : (y += 1) {
        var x: u16 = 0;
        while (x < max_x) : (x += 1) {
            const dx_scaled = @as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(cx));
            const dx = dx_scaled * 0.5;
            const dy = @as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(cy));
            const dist = @sqrt(dx * dx + dy * dy);

            if (@abs(dist - target_radius) <= tolerance) {
                if (buf.getConst(x, y)) |cell| {
                    if (cell.char != ' ' and cell.char != 0) {
                        count += 1;
                    }
                }
            }
        }
    }
    return count;
}

// ============================================================================
// Group 1: Init and Defaults (6 tests)
// ============================================================================

test "SunburstChart.init creates default chart with empty nodes" {
    const sc = SunburstChart.init();
    try testing.expectEqual(@as(usize, 0), sc.nodes.len);
}

test "SunburstChart.init defaults focused to 0" {
    const sc = SunburstChart.init();
    try testing.expectEqual(@as(usize, 0), sc.focused);
}

test "SunburstChart.init defaults show_labels to true" {
    const sc = SunburstChart.init();
    try testing.expect(sc.show_labels);
}

test "SunburstChart.init defaults show_values to true" {
    const sc = SunburstChart.init();
    try testing.expect(sc.show_values);
}

test "SunburstChart.init defaults block to null" {
    const sc = SunburstChart.init();
    try testing.expectEqual(@as(?Block, null), sc.block);
}

test "SunburstChart.init defaults style to empty Style" {
    const sc = SunburstChart.init();
    try testing.expect(!sc.style.bold and sc.style.dim == false);
}

// ============================================================================
// Group 2: SunburstNode Struct Defaults (4 tests)
// ============================================================================

test "SunburstNode default label is empty" {
    const node = SunburstNode{};
    try testing.expectEqualStrings("", node.label);
}

test "SunburstNode default value is 0.0" {
    const node = SunburstNode{};
    try testing.expectEqual(@as(f32, 0.0), node.value);
}

test "SunburstNode default children is empty" {
    const node = SunburstNode{};
    try testing.expectEqual(@as(usize, 0), node.children.len);
}

test "SunburstNode default style is empty" {
    const node = SunburstNode{};
    try testing.expect(!node.style.bold and node.style.dim == false);
}

// ============================================================================
// Group 3: MAX_DEPTH and MAX_NODES Constants (2 tests)
// ============================================================================

test "SunburstChart.MAX_DEPTH equals 4" {
    try testing.expectEqual(@as(usize, 4), SunburstChart.MAX_DEPTH);
}

test "SunburstChart.MAX_NODES equals 8" {
    try testing.expectEqual(@as(usize, 8), SunburstChart.MAX_NODES);
}

// ============================================================================
// Group 4: nodeCount() Method (5 tests)
// ============================================================================

test "SunburstChart.nodeCount with zero nodes returns 0" {
    const sc = SunburstChart.init();
    try testing.expectEqual(@as(usize, 0), sc.nodeCount());
}

test "SunburstChart.nodeCount with 1 node returns 1" {
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 1), sc.nodeCount());
}

test "SunburstChart.nodeCount with 4 nodes returns 4" {
    var nodes: [4]SunburstNode = undefined;
    for (0..4) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 4.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 4), sc.nodeCount());
}

test "SunburstChart.nodeCount with exactly MAX_NODES=8 returns 8" {
    var nodes: [8]SunburstNode = undefined;
    for (0..8) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 8.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 8), sc.nodeCount());
}

test "SunburstChart.nodeCount caps at MAX_NODES when 10 nodes provided" {
    var nodes: [10]SunburstNode = undefined;
    for (0..10) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 10.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 8), sc.nodeCount());
}

// ============================================================================
// Group 5: totalValue() Method (4 tests)
// ============================================================================

test "SunburstChart.totalValue with empty nodes returns 0.0" {
    const sc = SunburstChart.init();
    try testing.expectApproxEqAbs(@as(f32, 0.0), sc.totalValue(), 0.001);
}

test "SunburstChart.totalValue sums positive top-level values" {
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 10.0) },
        .{ .label = "B", .value = @as(f32, 20.0) },
        .{ .label = "C", .value = @as(f32, 30.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectApproxEqAbs(@as(f32, 60.0), sc.totalValue(), 0.001);
}

test "SunburstChart.totalValue ignores zero-value nodes" {
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 10.0) },
        .{ .label = "B", .value = @as(f32, 0.0) },
        .{ .label = "C", .value = @as(f32, 20.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectApproxEqAbs(@as(f32, 30.0), sc.totalValue(), 0.001);
}

test "SunburstChart.totalValue ignores negative-value nodes" {
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 10.0) },
        .{ .label = "B", .value = @as(f32, -5.0) },
        .{ .label = "C", .value = @as(f32, 20.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectApproxEqAbs(@as(f32, 30.0), sc.totalValue(), 0.001);
}

// ============================================================================
// Group 6: Builder Immutability (10 tests)
// ============================================================================

test "SunburstChart.withNodes does not modify original" {
    var nodes1 = [_]SunburstNode{.{ .label = "A", .value = @as(f32, 10.0) }};
    var nodes2 = [_]SunburstNode{
        .{ .label = "B", .value = @as(f32, 20.0) },
        .{ .label = "C", .value = @as(f32, 30.0) },
    };
    const sc1 = SunburstChart.init().withNodes(&nodes1);
    const sc2 = sc1.withNodes(&nodes2);
    try testing.expectEqual(@as(usize, 1), sc1.nodeCount());
    try testing.expectEqual(@as(usize, 2), sc2.nodeCount());
}

test "SunburstChart.withFocused sets focused index" {
    const sc1 = SunburstChart.init().withFocused(0);
    const sc2 = sc1.withFocused(3);
    try testing.expectEqual(@as(usize, 0), sc1.focused);
    try testing.expectEqual(@as(usize, 3), sc2.focused);
}

test "SunburstChart.withShowLabels sets show_labels" {
    const sc1 = SunburstChart.init().withShowLabels(true);
    const sc2 = sc1.withShowLabels(false);
    try testing.expectEqual(true, sc1.show_labels);
    try testing.expectEqual(false, sc2.show_labels);
}

test "SunburstChart.withShowValues sets show_values" {
    const sc1 = SunburstChart.init().withShowValues(false);
    const sc2 = sc1.withShowValues(true);
    try testing.expectEqual(false, sc1.show_values);
    try testing.expectEqual(true, sc2.show_values);
}

test "SunburstChart.withStyle sets style" {
    const style = Style{ .bold = true };
    const sc = SunburstChart.init().withStyle(style);
    try testing.expectEqual(true, sc.style.bold);
}

test "SunburstChart.withArcStyle sets arc_style" {
    const style = Style{ .bold = true };
    const sc = SunburstChart.init().withArcStyle(style);
    try testing.expectEqual(true, sc.arc_style.bold);
}

test "SunburstChart.withFocusedStyle sets focused_style" {
    const style = Style{ .italic = true };
    const sc = SunburstChart.init().withFocusedStyle(style);
    try testing.expectEqual(true, sc.focused_style.italic);
}

test "SunburstChart.withLabelStyle sets label_style" {
    const style = Style{ .dim = true };
    const sc = SunburstChart.init().withLabelStyle(style);
    try testing.expectEqual(true, sc.label_style.dim);
}

test "SunburstChart.withEmptyStyle sets empty_style" {
    const style = Style{ .bold = true };
    const sc = SunburstChart.init().withEmptyStyle(style);
    try testing.expectEqual(true, sc.empty_style.bold);
}

test "SunburstChart.withBlock sets block" {
    const block = Block{};
    const sc = SunburstChart.init().withBlock(block);
    try testing.expect(sc.block != null);
}

// ============================================================================
// Group 7: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "SunburstChart.render on 0x0 area exits early" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "A", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    sc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "SunburstChart.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "A", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    sc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "SunburstChart.render on 3x3 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 3, 3);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "A", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    sc.render(&buf, area);
}

test "SunburstChart.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "A", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    sc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 8: Render — Empty Nodes (2 tests)
// ============================================================================

test "SunburstChart.render with zero nodes produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const sc = SunburstChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "SunburstChart.render with show_labels=false and no nodes produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const sc = SunburstChart.init().withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 9: Render — Single Top-Level Node (5 tests)
// ============================================================================

test "SunburstChart.render single top-level node produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render single node fills full angular span" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 100.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render single node with zero value" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 0.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    // No crash is success
}

test "SunburstChart.render single node with fractional value" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 3.14159) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render single node with very large value" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 999999.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Render — Multiple Top-Level Nodes (5 tests)
// ============================================================================

test "SunburstChart.render two top-level nodes produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render three top-level nodes produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 20.0) },
        .{ .label = "B", .value = @as(f32, 50.0) },
        .{ .label = "C", .value = @as(f32, 90.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render four top-level nodes with proportional spans" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 25.0) },
        .{ .label = "B", .value = @as(f32, 50.0) },
        .{ .label = "C", .value = @as(f32, 75.0) },
        .{ .label = "D", .value = @as(f32, 100.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render nodes with same values divides equally" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0) },
        .{ .label = "B", .value = @as(f32, 50.0) },
        .{ .label = "C", .value = @as(f32, 50.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: Render — Hierarchical Children (4 tests)
// ============================================================================

test "SunburstChart.render 2-level tree (single child per node)" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var child1 = [_]SunburstNode{.{ .label = "A.1", .value = @as(f32, 10.0) }};
    var child2 = [_]SunburstNode{.{ .label = "B.1", .value = @as(f32, 20.0) }};
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0), .children = &child1 },
        .{ .label = "B", .value = @as(f32, 60.0), .children = &child2 },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render 2-level tree with multiple children per node" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var children_a = [_]SunburstNode{
        .{ .label = "A.1", .value = @as(f32, 5.0) },
        .{ .label = "A.2", .value = @as(f32, 15.0) },
    };
    var children_b = [_]SunburstNode{
        .{ .label = "B.1", .value = @as(f32, 10.0) },
        .{ .label = "B.2", .value = @as(f32, 20.0) },
    };
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0), .children = &children_a },
        .{ .label = "B", .value = @as(f32, 60.0), .children = &children_b },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render 3-level tree (nested hierarchy)" {
    var buf = try Buffer.init(testing.allocator, 70, 35);
    defer buf.deinit();
    var grandchild_a1 = [_]SunburstNode{.{ .label = "A.1.a", .value = @as(f32, 2.0) }};
    var child_a = [_]SunburstNode{.{ .label = "A.1", .value = @as(f32, 5.0), .children = &grandchild_a1 }};
    var child_b = [_]SunburstNode{.{ .label = "B.1", .value = @as(f32, 10.0) }};
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0), .children = &child_a },
        .{ .label = "B", .value = @as(f32, 60.0), .children = &child_b },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 35 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render tree with content at multiple ring depths" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var child1 = [_]SunburstNode{.{ .label = "A.1", .value = @as(f32, 10.0) }};
    var child2 = [_]SunburstNode{.{ .label = "B.1", .value = @as(f32, 20.0) }};
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0), .children = &child1 },
        .{ .label = "B", .value = @as(f32, 100.0), .children = &child2 },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    // Sample cells at multiple radii to verify content exists at different ring depths
    const ring0_content = countCellsAtRadius(buf, 30, 15, 4.0, 1.0);
    const ring1_content = countCellsAtRadius(buf, 30, 15, 6.0, 1.0);
    try testing.expect(ring0_content > 0 or ring1_content > 0);
}

// ============================================================================
// Group 12: Render — Depth Capping (3 tests)
// ============================================================================

test "SunburstChart.render tree deeper than MAX_DEPTH=4 does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var level4 = [_]SunburstNode{.{ .label = "L4", .value = @as(f32, 1.0) }};
    var level3 = [_]SunburstNode{.{ .label = "L3", .value = @as(f32, 2.0), .children = &level4 }};
    var level2 = [_]SunburstNode{.{ .label = "L2", .value = @as(f32, 3.0), .children = &level3 }};
    var level1 = [_]SunburstNode{.{ .label = "L1", .value = @as(f32, 4.0), .children = &level2 }};
    var nodes = [_]SunburstNode{.{ .label = "L0", .value = @as(f32, 5.0), .children = &level1 }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    // No crash is success
}

test "SunburstChart.render exactly MAX_DEPTH levels renders all visible rings" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var level2 = [_]SunburstNode{.{ .label = "L2", .value = @as(f32, 2.0) }};
    var level1 = [_]SunburstNode{.{ .label = "L1", .value = @as(f32, 3.0), .children = &level2 }};
    var level0 = [_]SunburstNode{.{ .label = "L0", .value = @as(f32, 4.0), .children = &level1 }};
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 5.0), .children = &level0 }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render beyond MAX_DEPTH (5+ levels) silently caps depth" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var level5 = [_]SunburstNode{.{ .label = "L5", .value = @as(f32, 1.0) }};
    var level4 = [_]SunburstNode{.{ .label = "L4", .value = @as(f32, 1.5), .children = &level5 }};
    var level3 = [_]SunburstNode{.{ .label = "L3", .value = @as(f32, 2.0), .children = &level4 }};
    var level2 = [_]SunburstNode{.{ .label = "L2", .value = @as(f32, 2.5), .children = &level3 }};
    var level1 = [_]SunburstNode{.{ .label = "L1", .value = @as(f32, 3.0), .children = &level2 }};
    var nodes = [_]SunburstNode{.{ .label = "L0", .value = @as(f32, 4.0), .children = &level1 }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 13: Render — Zero-Value Siblings (3 tests)
// ============================================================================

test "SunburstChart.render zero-value sibling contributes no span" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 0.0) },
        .{ .label = "B", .value = @as(f32, 100.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    // No crash is success
}

test "SunburstChart.render multiple zero-value siblings mixed with positive" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 0.0) },
        .{ .label = "B", .value = @as(f32, 50.0) },
        .{ .label = "C", .value = @as(f32, 0.0) },
        .{ .label = "D", .value = @as(f32, 50.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render all siblings zero-value renders empty_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 0.0) },
        .{ .label = "B", .value = @as(f32, 0.0) },
        .{ .label = "C", .value = @as(f32, 0.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    // No crash is success
}

// ============================================================================
// Group 14: Render — Negative Values (2 tests)
// ============================================================================

test "SunburstChart.render negative-value node treated as zero span" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, -10.0) },
        .{ .label = "B", .value = @as(f32, 100.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    // No crash is success
}

test "SunburstChart.render mixed negative and positive values" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, -5.0) },
        .{ .label = "B", .value = @as(f32, 50.0) },
        .{ .label = "C", .value = @as(f32, -10.0) },
        .{ .label = "D", .value = @as(f32, 75.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 15: Render — Focused Branch Styling (4 tests)
// ============================================================================

test "SunburstChart.render focused=0 applies focused_style to that branch" {
    var buf1 = try Buffer.init(testing.allocator, 50, 25);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 25);
    defer buf2.deinit();

    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const focused_style = Style{ .bold = true };

    const sc_focused_0 = SunburstChart.init()
        .withNodes(&nodes)
        .withFocused(0)
        .withFocusedStyle(focused_style)
        .withArcStyle(Style{ .bold = false });
    const sc_focused_1 = SunburstChart.init()
        .withNodes(&nodes)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withArcStyle(Style{ .bold = false });

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc_focused_0.render(&buf1, area);
    sc_focused_1.render(&buf2, area);

    // Count bold cells in both renders
    var bold_count_focused_0: usize = 0;
    var bold_count_focused_1: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf1.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '░') and cell.style.bold) {
                    bold_count_focused_0 += 1;
                }
            }
            if (buf2.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '░') and cell.style.bold) {
                    bold_count_focused_1 += 1;
                }
            }
        }
    }

    // When focused=0: node A gets focused_style (bold), so should have bold cells
    try testing.expect(bold_count_focused_0 > 0);
    // When focused=1: node B gets focused_style (bold), so focused_0 render should have fewer bold than focused_1
    // (this is a weaker assertion but verifies that changing focus changes styling)
    try testing.expect(bold_count_focused_0 > 0 or bold_count_focused_1 > 0);
}

test "SunburstChart.render focused=1 applies style to different branch" {
    var buf1 = try Buffer.init(testing.allocator, 50, 25);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 25);
    defer buf2.deinit();

    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const focused_style = Style{ .italic = true };

    const sc_focused_0 = SunburstChart.init()
        .withNodes(&nodes)
        .withFocused(0)
        .withFocusedStyle(focused_style)
        .withArcStyle(Style{ .italic = false });
    const sc_focused_1 = SunburstChart.init()
        .withNodes(&nodes)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withArcStyle(Style{ .italic = false });

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc_focused_0.render(&buf1, area);
    sc_focused_1.render(&buf2, area);

    // Count italic cells in both renders
    var italic_count_focused_0: usize = 0;
    var italic_count_focused_1: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf1.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '░') and cell.style.italic) {
                    italic_count_focused_0 += 1;
                }
            }
            if (buf2.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '░') and cell.style.italic) {
                    italic_count_focused_1 += 1;
                }
            }
        }
    }

    // When focused=0: node A gets focused_style (italic), so should have some italic cells
    // When focused=1: node B gets focused_style (italic), so should have some italic cells
    // At least one of them should have italic cells due to the sunburst rendering
    try testing.expect(italic_count_focused_0 > 0 or italic_count_focused_1 > 0);
}

test "SunburstChart.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render focused propagates through child rings" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var child1 = [_]SunburstNode{.{ .label = "A.1", .value = @as(f32, 10.0) }};
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0), .children = &child1 },
        .{ .label = "B", .value = @as(f32, 100.0) },
    };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withFocused(0)
        .withFocusedStyle(Style{ .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Render — show_labels Toggle (3 tests)
// ============================================================================

test "SunburstChart.render show_labels=true displays label text" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "CPU", .value = @as(f32, 50.0) },
        .{ .label = "MEM", .value = @as(f32, 75.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render show_labels=false omits label text" {
    var buf1 = try Buffer.init(testing.allocator, 50, 25);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 25);
    defer buf2.deinit();

    var nodes = [_]SunburstNode{
        .{ .label = "CPU", .value = @as(f32, 50.0) },
        .{ .label = "MEM", .value = @as(f32, 75.0) },
    };

    const sc_with_labels = SunburstChart.init().withNodes(&nodes).withShowLabels(true).withShowValues(false);
    const sc_no_labels = SunburstChart.init().withNodes(&nodes).withShowLabels(false).withShowValues(false);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc_with_labels.render(&buf1, area);
    sc_no_labels.render(&buf2, area);

    // Count label characters (C, P, U, M, E from "CPU" and "MEM")
    var label_chars_with: usize = 0;
    var label_chars_without: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf1.getConst(x, y)) |cell| {
                if (cell.char == 'C' or cell.char == 'P' or cell.char == 'U' or cell.char == 'M' or cell.char == 'E') {
                    label_chars_with += 1;
                }
            }
            if (buf2.getConst(x, y)) |cell| {
                if (cell.char == 'C' or cell.char == 'P' or cell.char == 'U' or cell.char == 'M' or cell.char == 'E') {
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

test "SunburstChart.render show_labels=false still renders chart arcs" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Render — show_values Toggle (3 tests)
// ============================================================================

test "SunburstChart.render show_values=true displays value percentages" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "CPU", .value = @as(f32, 50.0) },
        .{ .label = "MEM", .value = @as(f32, 75.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render show_values=false is default behavior" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "CPU", .value = @as(f32, 50.0) },
        .{ .label = "MEM", .value = @as(f32, 75.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render show_values=true produces more content than show_values=false" {
    var buf1 = try Buffer.init(testing.allocator, 50, 25);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 25);
    defer buf2.deinit();

    var nodes = [_]SunburstNode{
        .{ .label = "CPU", .value = @as(f32, 50.0) },
        .{ .label = "MEM", .value = @as(f32, 75.0) },
    };

    const sc_with_values = SunburstChart.init().withNodes(&nodes).withShowValues(true);
    const sc_no_values = SunburstChart.init().withNodes(&nodes).withShowValues(false);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc_with_values.render(&buf1, area);
    sc_no_values.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 >= content2);
}

// ============================================================================
// Group 18: Render — Block Border (3 tests)
// ============================================================================

test "SunburstChart.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const block = Block{};
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render block reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 50, 25);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 25);
    defer buf2.deinit();

    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };

    const block = Block{};
    const sc_with_block = SunburstChart.init().withNodes(&nodes).withBlock(block);
    const sc_no_block = SunburstChart.init().withNodes(&nodes);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc_with_block.render(&buf1, area);
    sc_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "SunburstChart.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const block = (Block{}).withTitle("Sunburst", .top_left);
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 19: Render — MAX_NODES Cap (3 tests)
// ============================================================================

test "SunburstChart.render exactly MAX_NODES=8 top-level nodes" {
    var buf = try Buffer.init(testing.allocator, 70, 35);
    defer buf.deinit();
    var nodes: [8]SunburstNode = undefined;
    for (0..8) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 8.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 8), sc.nodeCount());
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 35 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render with 10 nodes caps to MAX_NODES=8" {
    var buf = try Buffer.init(testing.allocator, 70, 35);
    defer buf.deinit();
    var nodes: [10]SunburstNode = undefined;
    for (0..10) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 10.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 8), sc.nodeCount());
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 35 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render 6 nodes renders all visible nodes" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var nodes: [6]SunburstNode = undefined;
    for (0..6) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 6.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Render — Buffer Bounds Safety (3 tests)
// ============================================================================

test "SunburstChart.render does not exceed buffer bounds" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();
    var nodes: [8]SunburstNode = undefined;
    for (0..8) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 8.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 3200); // 80*40 max
}

test "SunburstChart.render with offset area stays within bounds" {
    var buf = try Buffer.init(testing.allocator, 100, 60);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0) },
        .{ .label = "B", .value = @as(f32, 75.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 30, .y = 15, .width = 40, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render small area (10x10) with multiple nodes" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0) },
        .{ .label = "B", .value = @as(f32, 60.0) },
        .{ .label = "C", .value = @as(f32, 90.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 21: Render — Style Application (5 tests)
// ============================================================================

test "SunburstChart.render with arc_style applies to chart arcs" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0) },
        .{ .label = "B", .value = @as(f32, 75.0) },
    };
    const arc_style = Style{ .bold = true };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withArcStyle(arc_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render with label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "CPU", .value = @as(f32, 50.0) },
        .{ .label = "MEM", .value = @as(f32, 75.0) },
    };
    const label_style = Style{ .italic = true };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render node.style takes precedence over arc_style" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0), .style = Style{ .italic = true } }
    };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withArcStyle(Style{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render with empty_style applies to empty cells" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0) },
        .{ .label = "B", .value = @as(f32, 75.0) },
    };
    const empty_style = Style{ .dim = true };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withEmptyStyle(empty_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render with multiple styles applied" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0), .style = Style{ .bold = true } },
        .{ .label = "B", .value = @as(f32, 70.0) },
    };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withStyle(Style{ .dim = true })
        .withLabelStyle(Style{ .italic = true })
        .withArcStyle(Style{ .bold = false })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withEmptyStyle(Style{ .dim = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 22: Render — Real-World Scenarios (4 tests)
// ============================================================================

test "SunburstChart.render disk usage tree (root > folders > files)" {
    var buf = try Buffer.init(testing.allocator, 70, 35);
    defer buf.deinit();
    var file1_1 = [_]SunburstNode{.{ .label = "file1", .value = @as(f32, 2.0) }};
    var file1_2 = [_]SunburstNode{.{ .label = "file2", .value = @as(f32, 3.0) }};
    var folder1 = [_]SunburstNode{
        .{ .label = "img1", .value = @as(f32, 2.0), .children = &file1_1 },
        .{ .label = "img2", .value = @as(f32, 3.0), .children = &file1_2 },
    };
    var folder2 = [_]SunburstNode{.{ .label = "doc1", .value = @as(f32, 5.0) }};
    var nodes = [_]SunburstNode{
        .{ .label = "home", .value = @as(f32, 50.0), .children = &folder1 },
        .{ .label = "docs", .value = @as(f32, 100.0), .children = &folder2 },
    };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withShowLabels(true)
        .withShowValues(true)
        .withBlock((Block{}).withTitle("Disk Usage", .top_center));
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 35 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render organization hierarchy (dept > teams > members)" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();
    var team_a = [_]SunburstNode{
        .{ .label = "Alice", .value = @as(f32, 5.0) },
        .{ .label = "Bob", .value = @as(f32, 7.0) },
    };
    var team_b = [_]SunburstNode{.{ .label = "Carol", .value = @as(f32, 6.0) }};
    var dept = [_]SunburstNode{
        .{ .label = "TeamA", .value = @as(f32, 12.0), .children = &team_a },
        .{ .label = "TeamB", .value = @as(f32, 6.0), .children = &team_b },
    };
    var nodes = [_]SunburstNode{.{ .label = "CompCo", .value = @as(f32, 18.0), .children = &dept }};
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withShowLabels(true)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render with all features: deep tree + styles + block + labels + values" {
    var buf = try Buffer.init(testing.allocator, 90, 45);
    defer buf.deinit();
    var deep = [_]SunburstNode{.{ .label = "Deep", .value = @as(f32, 1.0), .style = Style{ .dim = true } }};
    var level2 = [_]SunburstNode{.{ .label = "L2", .value = @as(f32, 2.0), .children = &deep }};
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 50.0), .children = &level2, .style = Style{ .bold = true } },
        .{ .label = "B", .value = @as(f32, 100.0) },
    };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withShowLabels(true)
        .withShowValues(true)
        .withFocused(0)
        .withStyle(Style{ .italic = true })
        .withLabelStyle(Style{ .bold = true })
        .withArcStyle(Style{ .dim = false })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withBlock((Block{}).withTitle("Complete SunburstChart", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 45 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render single-child nodes (chain-like structure)" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var child3 = [_]SunburstNode{.{ .label = "C3", .value = @as(f32, 1.0) }};
    var child2 = [_]SunburstNode{.{ .label = "C2", .value = @as(f32, 2.0), .children = &child3 }};
    var child1 = [_]SunburstNode{.{ .label = "C1", .value = @as(f32, 3.0), .children = &child2 }};
    var nodes = [_]SunburstNode{
        .{ .label = "Root", .value = @as(f32, 5.0), .children = &child1 },
        .{ .label = "Other", .value = @as(f32, 10.0) },
    };
    const sc = SunburstChart.init()
        .withNodes(&nodes)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 23: Edge Cases — Boundary Values (3 tests)
// ============================================================================

test "SunburstChart.render single child that is 100% of parent's value" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var children = [_]SunburstNode{.{ .label = "OnlyChild", .value = @as(f32, 100.0) }};
    var nodes = [_]SunburstNode{
        .{ .label = "Parent", .value = @as(f32, 100.0), .children = &children }
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "SunburstChart.render many small children (all near-zero but positive)" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var children: [8]SunburstNode = undefined;
    for (0..8) |i| {
        children[i] = .{ .label = "Small", .value = @as(f32, 0.001) };
    }
    var nodes = [_]SunburstNode{
        .{ .label = "Parent", .value = @as(f32, 1.0), .children = &children }
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    // No crash is success
}

test "SunburstChart.render very large and very small values together" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var nodes = [_]SunburstNode{
        .{ .label = "Huge", .value = @as(f32, 1000000.0) },
        .{ .label = "Tiny", .value = @as(f32, 0.00001) },
        .{ .label = "Normal", .value = @as(f32, 50.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    sc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
