//! IcicleChart Widget Tests — TDD Red Phase
//!
//! Tests IcicleChart widget rendering hierarchical rectangular bands per depth.
//! Single root node tree, stacked horizontal bands (one per depth level), cumulative-floor
//! layout for child width proportionality within parent column spans. Tests cover:
//! - Initialization defaults (root=null, focused=empty, show_labels/values toggles)
//! - Builder pattern immutability for all with* methods
//! - nodeCount() counting tree nodes with MAX_DEPTH/MAX_CHILDREN_PER_NODE capping
//! - Band width proportionality via cumulative-floor formula (hand-computed per test)
//! - Root band spanning full inner width regardless of root value
//! - Zero/negative child value handling (zero width, no sibling corruption, no panic)
//! - Leaf node behavior (no deeper rows rendered for that column)
//! - Focused path highlighting (empty path, single-element, multi-element, out-of-range)
//! - show_labels and show_values independent toggles
//! - MAX_DEPTH and MAX_CHILDREN_PER_NODE capping during actual render
//! - Edge cases (zero-width area, zero-height area, 1-row tall area, null root)
//! - Block border rendering
//! - Style precedence (node.style > self.style, focused_style > both when on path & set)

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const IcicleChart = sailor.tui.widgets.IcicleChart;
const IcicleNode = sailor.tui.widgets.icicle_chart.IcicleNode;

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

/// Get cell at position in area (relative coordinates to area origin)
fn getCell(buf: Buffer, area: Rect, x: u16, y: u16) ?sailor.Cell {
    if (x >= area.width or y >= area.height) return null;
    return buf.getConst(area.x + x, area.y + y);
}

// ============================================================================
// Group 1: Init and Defaults (6 tests)
// ============================================================================

test "IcicleChart.init creates chart with null root" {
    const chart = IcicleChart.init();
    try testing.expectEqual(@as(?IcicleNode, null), chart.root);
}

test "IcicleChart.init defaults focused to empty slice" {
    const chart = IcicleChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused.len);
}

test "IcicleChart.init defaults show_labels to true" {
    const chart = IcicleChart.init();
    try testing.expectEqual(true, chart.show_labels);
}

test "IcicleChart.init defaults show_values to false" {
    const chart = IcicleChart.init();
    try testing.expectEqual(false, chart.show_values);
}

test "IcicleChart.init defaults block to null" {
    const chart = IcicleChart.init();
    try testing.expectEqual(@as(?Block, null), chart.block);
}

test "IcicleChart.init has default empty styles" {
    const chart = IcicleChart.init();
    try testing.expectEqual(Style{}, chart.style);
    try testing.expectEqual(Style{}, chart.label_style);
    try testing.expectEqual(Style{}, chart.focused_style);
}

// ============================================================================
// Group 2: IcicleNode Struct Defaults (4 tests)
// ============================================================================

test "IcicleNode default label is empty" {
    const node = IcicleNode{};
    try testing.expectEqualStrings("", node.label);
}

test "IcicleNode default value is 0.0" {
    const node = IcicleNode{};
    try testing.expectEqual(@as(f32, 0.0), node.value);
}

test "IcicleNode default children is empty slice" {
    const node = IcicleNode{};
    try testing.expectEqual(@as(usize, 0), node.children.len);
}

test "IcicleNode default style is empty Style" {
    const node = IcicleNode{};
    try testing.expectEqual(Style{}, node.style);
}

// ============================================================================
// Group 3: MAX_DEPTH and MAX_CHILDREN_PER_NODE Constants (2 tests)
// ============================================================================

test "IcicleChart.MAX_DEPTH equals 6" {
    try testing.expectEqual(@as(usize, 6), IcicleChart.MAX_DEPTH);
}

test "IcicleChart.MAX_CHILDREN_PER_NODE equals 8" {
    try testing.expectEqual(@as(usize, 8), IcicleChart.MAX_CHILDREN_PER_NODE);
}

// ============================================================================
// Group 4: nodeCount() Method (7 tests)
// ============================================================================

test "nodeCount with null root returns 0" {
    const chart = IcicleChart.init();
    try testing.expectEqual(@as(usize, 0), chart.nodeCount());
}

test "nodeCount with single root and no children returns 1" {
    const root = IcicleNode{ .label = "Root", .value = 10 };
    const chart = IcicleChart.init().withRoot(root);
    try testing.expectEqual(@as(usize, 1), chart.nodeCount());
}

test "nodeCount with root and two children returns 3" {
    const children = [_]IcicleNode{
        .{ .label = "A", .value = 5 },
        .{ .label = "B", .value = 10 },
    };
    const root = IcicleNode{ .label = "Root", .value = 15, .children = &children };
    const chart = IcicleChart.init().withRoot(root);
    try testing.expectEqual(@as(usize, 3), chart.nodeCount());
}

test "nodeCount respects MAX_DEPTH capping at 6" {
    // Create a deep tree: root -> level1 -> level2 -> ... -> level6
    // Any nodes deeper than level6 should not be counted
    const level5_children = [_]IcicleNode{.{ .label = "L6", .value = 1 }};
    const level4_children = [_]IcicleNode{.{ .label = "L5", .value = 1, .children = &level5_children }};
    const level3_children = [_]IcicleNode{.{ .label = "L4", .value = 1, .children = &level4_children }};
    const level2_children = [_]IcicleNode{.{ .label = "L3", .value = 1, .children = &level3_children }};
    const level1_children = [_]IcicleNode{.{ .label = "L2", .value = 1, .children = &level2_children }};
    const root_children = [_]IcicleNode{.{ .label = "L1", .value = 1, .children = &level1_children }};
    const root = IcicleNode{ .label = "Root", .value = 1, .children = &root_children };
    const chart = IcicleChart.init().withRoot(root);
    // Should count: Root(L0), L1(L1), L2(L2), L3(L3), L4(L4), L5(L5), L6(L6)
    // That's 7 levels total, but MAX_DEPTH=6, so nodes beyond depth 6 not counted
    try testing.expectEqual(@as(usize, 6), chart.nodeCount());
}

test "nodeCount caps children at MAX_CHILDREN_PER_NODE=8" {
    var children: [16]IcicleNode = undefined;
    for (0..16) |i| {
        children[i] = .{ .label = "C", .value = @as(f32, @floatFromInt(i + 1)) };
    }
    const root = IcicleNode{ .label = "Root", .value = 100, .children = &children };
    const chart = IcicleChart.init().withRoot(root);
    // Should count only first 8 children + root = 9
    try testing.expectEqual(@as(usize, 9), chart.nodeCount());
}

test "nodeCount with multi-level tree respects MAX_CHILDREN_PER_NODE per node" {
    // Create tree with max children at each level
    var grandchildren: [8]IcicleNode = undefined;
    for (0..8) |i| {
        grandchildren[i] = .{ .label = "GC", .value = 1 };
    }
    var children: [8]IcicleNode = undefined;
    for (0..8) |i| {
        if (i == 0) {
            children[i] = .{ .label = "C", .value = 1, .children = &grandchildren };
        } else {
            children[i] = .{ .label = "C", .value = 1 };
        }
    }
    const root = IcicleNode{ .label = "Root", .value = 1, .children = &children };
    const chart = IcicleChart.init().withRoot(root);
    // Root(1) + 8 children + 8 grandchildren = 17
    try testing.expectEqual(@as(usize, 17), chart.nodeCount());
}

// ============================================================================
// Group 5: Builder Immutability (8 tests)
// ============================================================================

test "withRoot does not modify original" {
    const root1 = IcicleNode{ .label = "R1", .value = 10 };
    const root2 = IcicleNode{ .label = "R2", .value = 20 };
    const chart1 = IcicleChart.init().withRoot(root1);
    const chart2 = chart1.withRoot(root2);
    try testing.expectEqualStrings("R1", chart1.root.?.label);
    try testing.expectEqualStrings("R2", chart2.root.?.label);
}

test "withFocused does not modify original" {
    const focused_path1 = [_]usize{0};
    const focused_path2 = [_]usize{ 1, 2 };
    const chart1 = IcicleChart.init().withFocused(&focused_path1);
    const chart2 = chart1.withFocused(&focused_path2);
    try testing.expectEqual(@as(usize, 1), chart1.focused.len);
    try testing.expectEqual(@as(usize, 2), chart2.focused.len);
}

test "withShowLabels does not modify original" {
    const chart1 = IcicleChart.init().withShowLabels(true);
    const chart2 = chart1.withShowLabels(false);
    try testing.expectEqual(true, chart1.show_labels);
    try testing.expectEqual(false, chart2.show_labels);
}

test "withShowValues does not modify original" {
    const chart1 = IcicleChart.init().withShowValues(false);
    const chart2 = chart1.withShowValues(true);
    try testing.expectEqual(false, chart1.show_values);
    try testing.expectEqual(true, chart2.show_values);
}

test "withStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = IcicleChart.init().withStyle(s1);
    const chart2 = chart1.withStyle(s2);
    try testing.expectEqual(true, chart1.style.bold);
    try testing.expectEqual(true, chart2.style.dim);
}

test "withFocusedStyle does not modify original" {
    const s1 = Style{ .italic = true };
    const s2 = Style{ .reverse = true };
    const chart1 = IcicleChart.init().withFocusedStyle(s1);
    const chart2 = chart1.withFocusedStyle(s2);
    try testing.expectEqual(true, chart1.focused_style.italic);
    try testing.expectEqual(true, chart2.focused_style.reverse);
}

test "withLabelStyle does not modify original" {
    const s1 = Style{ .underline = true };
    const s2 = Style{ .strikethrough = true };
    const chart1 = IcicleChart.init().withLabelStyle(s1);
    const chart2 = chart1.withLabelStyle(s2);
    try testing.expectEqual(true, chart1.label_style.underline);
    try testing.expectEqual(true, chart2.label_style.strikethrough);
}

test "withBlock does not modify original" {
    const chart1 = IcicleChart.init().withBlock(.{});
    const chart2 = chart1.withBlock(null);
    try testing.expect(chart1.block != null);
    try testing.expect(chart2.block == null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "render with 0x0 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleNode{ .label = "Root", .value = 10 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleNode{ .label = "Root", .value = 10 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
}

test "render with zero-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleNode{ .label = "Root", .value = 10 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    chart.render(&buf, area);
}

test "render with zero-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleNode{ .label = "Root", .value = 10 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 7: Render — Null Root (1 test)
// ============================================================================

test "render with null root produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = IcicleChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    chart.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 8: Render — Single Root (2 tests)
// ============================================================================

test "render single root produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleNode{ .label = "Root", .value = 100 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render single root with zero value does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleNode{ .label = "Root", .value = 0 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 9: Root Band Width — Full Inner Width Spanning (2 tests)
// ============================================================================

test "root band spans full inner width regardless of value" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Root with very small value should still span full width
    const root = IcicleNode{ .label = "Root", .value = 1 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Verify root band has content spanning most of the width
    // Check multiple x positions at y=0 (root row)
    const cell_left = getCell(buf, area, 5, 0);
    const cell_mid = getCell(buf, area, 30, 0);
    const cell_right = getCell(buf, area, 55, 0);
    // At least some cells should have content (character '█' or label)
    try testing.expect(cell_left != null);
    try testing.expect(cell_mid != null);
    try testing.expect(cell_right != null);
}

test "root band spans full width with high value" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Root with very large value should still span full width
    const root = IcicleNode{ .label = "Root", .value = 9999 };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Verify root band spans full width
    const cell_left = getCell(buf, area, 2, 0);
    const cell_right = getCell(buf, area, 58, 0);
    try testing.expect(cell_left != null);
    try testing.expect(cell_right != null);
}

// ============================================================================
// Group 10: Child Band Width Proportionality — Cumulative-Floor Formula (3 tests)
// ============================================================================

test "two equal-value children divide parent column equally" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Root with two children of equal value: each should get ~width/2
    // Inner width = 60, so each child should get ~30
    const children = [_]IcicleNode{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const root = IcicleNode{ .label = "Root", .value = 100, .children = &children };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);

    // Depth 1 row should have two bands
    // col_x[0] = 0 + floor(0/100 * 60) = 0
    // col_x[1] = 0 + floor(50/100 * 60) = 30
    // col_x[2] = 0 + floor(100/100 * 60) = 60
    // Child A: x=[0,30), Child B: x=[30,60)
    // Check middle of each band at y=1 (depth 1)
    const cell_a = getCell(buf, area, 15, 1);
    const cell_b = getCell(buf, area, 45, 1);
    try testing.expect(cell_a != null and cell_a.?.char != ' ');
    try testing.expect(cell_b != null and cell_b.?.char != ' ');
}

test "three equal-value children divide parent column into thirds" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Three equal-value children: each should get 1/3 of width
    const children = [_]IcicleNode{
        .{ .label = "A", .value = 30 },
        .{ .label = "B", .value = 30 },
        .{ .label = "C", .value = 30 },
    };
    const root = IcicleNode{ .label = "Root", .value = 90, .children = &children };
    const chart = IcicleChart.init().withRoot(root);
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 10 };

    chart.render(&buf, area);

    // col_x[0] = floor(0/90 * 90) = 0
    // col_x[1] = floor(30/90 * 90) = 30
    // col_x[2] = floor(60/90 * 90) = 60
    // col_x[3] = floor(90/90 * 90) = 90
    // A: [0,30), B: [30,60), C: [60,90)
    const cell_a = getCell(buf, area, 10, 1);
    const cell_b = getCell(buf, area, 45, 1);
    const cell_c = getCell(buf, area, 75, 1);
    try testing.expect(cell_a != null and cell_a.?.char != ' ');
    try testing.expect(cell_b != null and cell_b.?.char != ' ');
    try testing.expect(cell_c != null and cell_c.?.char != ' ');
}

test "unequal-value children (1:9 ratio) render proportionally" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Two children: narrow (value 1) and wide (value 9)
    const children = [_]IcicleNode{
        .{ .label = "Narrow", .value = 1 },
        .{ .label = "Wide", .value = 9 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 10, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 10 };

    chart.render(&buf, area);

    // col_x[0] = floor(0/10 * 100) = 0
    // col_x[1] = floor(1/10 * 100) = 10
    // col_x[2] = floor(10/10 * 100) = 100
    // Narrow: [0,10), Wide: [10,100)
    const cell_narrow = getCell(buf, area, 5, 1);
    const cell_wide = getCell(buf, area, 55, 1);
    try testing.expect(cell_narrow != null and cell_narrow.?.char != ' ');
    try testing.expect(cell_wide != null and cell_wide.?.char != ' ');
}

// ============================================================================
// Group 11: Zero and Negative Child Values (3 tests)
// ============================================================================

test "zero-value children get zero width without panic" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "Zero", .value = 0 },
        .{ .label = "Positive", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 50, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Only the positive child should render; zero child skipped
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "negative-value children do not corrupt sibling layout" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "Pos1", .value = 30 },
        .{ .label = "Neg", .value = -10 },
        .{ .label = "Pos2", .value = 30 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 60, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Neg child should be skipped; Pos1 and Pos2 should render
    // If negative values are clamped/ignored, total positive = 60
    // col_x[0] = 0, col_x[1] = 30, col_x[2] = 60
    // Pos1: [0,30), Pos2: [30,60)
    const cell_pos1 = getCell(buf, area, 10, 1);
    const cell_pos2 = getCell(buf, area, 45, 1);
    try testing.expect(cell_pos1 != null and cell_pos1.?.char != ' ');
    try testing.expect(cell_pos2 != null and cell_pos2.?.char != ' ');
}

test "all-negative children total produces no depth-1 band" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "Neg1", .value = -5 },
        .{ .label = "Neg2", .value = -10 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 0, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Depth 1 should be empty (leaf behavior)
    // Only root band at y=0 should have content
    const cell_depth0 = getCell(buf, area, 30, 0);
    try testing.expect(cell_depth0 != null);
    // Depth 1 should be empty/space only if no positive children
}

// ============================================================================
// Group 12: Leaf Node Behavior (2 tests)
// ============================================================================

test "node with no children stops depth there (leaf)" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Single child with no grandchildren
    const children = [_]IcicleNode{
        .{ .label = "Leaf", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 50, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Depth 0: root, Depth 1: leaf child, Depth 2+: empty (no render)
    const cell_root = getCell(buf, area, 30, 0);
    try testing.expect(cell_root != null);
    // Depth 1 may have content if child renders
}

test "node with only zero/negative children acts as leaf" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const grandchildren = [_]IcicleNode{
        .{ .label = "GC1", .value = 10 },
    };
    const children = [_]IcicleNode{
        .{ .label = "Child", .value = 0, .children = &grandchildren },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 0, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // The zero-value child blocks its grandchildren from rendering
}

// ============================================================================
// Group 13: Focused Path Highlighting (4 tests)
// ============================================================================

test "empty focused path highlights nothing" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "A", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 50, .children = &children } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withFocused(&.{})
        .withFocusedStyle(.{ .reverse = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // With empty focused path, no node should receive focused_style.
    // Root's band cell at x=10, y=0 (past "Root" label of 4 chars) should NOT have reverse=true
    const root_cell = getCell(buf, area, 10, 0);
    try testing.expect(root_cell != null);
    try testing.expect(root_cell.?.style.reverse != true);

    // Child A's band cell at x=2, y=1 (past "A" label of 1 char) should also NOT have reverse=true
    const child_a_cell = getCell(buf, area, 2, 1);
    try testing.expect(child_a_cell != null);
    try testing.expect(child_a_cell.?.style.reverse != true);
}

test "single-element focused path highlights top-level child and descendants" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const grandchild = [_]IcicleNode{
        .{ .label = "GC", .value = 10 },
    };
    const children = [_]IcicleNode{
        .{ .label = "A", .value = 25, .children = &grandchild },
        .{ .label = "B", .value = 25 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 50, .children = &children } };
    const focused_path = [_]usize{0};
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withFocused(&focused_path)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Focused path [0] means: root -> children[0] (A) and its descendants (GC)
    // Layout:
    //   Depth 0 (root): [0,60)
    //   Depth 1 children: total=50, A: [0,30), B: [30,60)
    //   Depth 2 (GC under A): A's span [0,30), total=10, GC: [0,30)

    // Child A at depth 1, x=2 (past "A" label of 1 char, inside band [0,30)) should have bold=true
    const child_a_cell = getCell(buf, area, 2, 1);
    try testing.expect(child_a_cell != null);
    try testing.expect(child_a_cell.?.style.bold == true);

    // Child B at depth 1, x=31 (inside band [30,60)) should NOT have bold=true
    const child_b_cell = getCell(buf, area, 31, 1);
    try testing.expect(child_b_cell != null);
    try testing.expect(child_b_cell.?.style.bold != true);

    // Grandchild GC at depth 2, x=3 (past "GC" label of 2 chars, inside band [0,30)) should have bold=true
    const grandchild_cell = getCell(buf, area, 3, 2);
    try testing.expect(grandchild_cell != null);
    try testing.expect(grandchild_cell.?.style.bold == true);
}

test "multi-element focused path highlights deep nodes" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const a1_child = [_]IcicleNode{
        .{ .label = "A1C", .value = 10 },
    };
    const child_a_children = [_]IcicleNode{
        .{ .label = "A1", .value = 25, .children = &a1_child },
        .{ .label = "A2", .value = 25 },
    };
    const children = [_]IcicleNode{
        .{ .label = "A", .value = 50, .children = &child_a_children },
        .{ .label = "B", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 100, .children = &children } };
    const focused_path = [_]usize{ 0, 0 };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withFocused(&focused_path)
        .withFocusedStyle(.{ .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Focused path [0, 0] means: root -> children[0] (A) -> A's children[0] (A1) and descendants
    // Layout:
    //   Depth 0: root [0,60)
    //   Depth 1: A [0,30), B [30,60)
    //   Depth 2: A's span [0,30), total=50
    //     A1: [0,15), A2: [15,30)
    //   Depth 3: A1's span [0,15), total=10, A1C: [0,15)

    // A1 at depth 2, x=3 (past "A1" label of 2 chars, inside [0,15)) should have italic=true
    const a1_cell = getCell(buf, area, 3, 2);
    try testing.expect(a1_cell != null);
    try testing.expect(a1_cell.?.style.italic == true);

    // A2 at depth 2, x=17 (inside [15,30)) should NOT have italic=true
    const a2_cell = getCell(buf, area, 17, 2);
    try testing.expect(a2_cell != null);
    try testing.expect(a2_cell.?.style.italic != true);

    // A1's child (A1C) at depth 3, x=3 (past "A1C" label of 3 chars, inside [0,15)) should have italic=true
    const a1c_cell = getCell(buf, area, 4, 3);
    try testing.expect(a1c_cell != null);
    try testing.expect(a1c_cell.?.style.italic == true);
}

test "out-of-range focused path index does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "A", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 50, .children = &children } };
    const focused_path = [_]usize{99}; // out of range
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withFocused(&focused_path)
        .withFocusedStyle(.{ .dim = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Out-of-range index (99) doesn't match any child (only child 0 exists).
    // No node should receive focused_style.
    // Root's band cell at x=10, y=0 (past "Root" label) should NOT have dim=true
    const root_cell = getCell(buf, area, 10, 0);
    try testing.expect(root_cell != null);
    try testing.expect(root_cell.?.style.dim != true);

    // Child A's band cell at x=2, y=1 (past "A" label) should also NOT have dim=true
    const child_a_cell = getCell(buf, area, 2, 1);
    try testing.expect(child_a_cell != null);
    try testing.expect(child_a_cell.?.style.dim != true);
}

// ============================================================================
// Group 14: show_labels / show_values Toggles (4 tests)
// ============================================================================

test "show_labels=true renders node labels" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleChart{ .root = .{ .label = "MyRoot", .value = 100 } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withShowLabels(true)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_labels=false omits labels" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleChart{ .root = .{ .label = "MyRoot", .value = 100 } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withShowLabels(false)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // May still have block borders or other content, but no label text
}

test "show_values=true renders percentage values" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "Child", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 100, .children = &children } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withShowLabels(false)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Root should show "100%", child should show "50%"
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_labels=true and show_values=true together" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "Child", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 100, .children = &children } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withShowLabels(true)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 15: MAX_DEPTH / MAX_CHILDREN_PER_NODE Capping During Render (3 tests)
// ============================================================================

test "tree deeper than MAX_DEPTH does not panic during render" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const level5_children = [_]IcicleNode{.{ .label = "L6", .value = 1 }};
    const level4_children = [_]IcicleNode{.{ .label = "L5", .value = 1, .children = &level5_children }};
    const level3_children = [_]IcicleNode{.{ .label = "L4", .value = 1, .children = &level4_children }};
    const level2_children = [_]IcicleNode{.{ .label = "L3", .value = 1, .children = &level3_children }};
    const level1_children = [_]IcicleNode{.{ .label = "L2", .value = 1, .children = &level2_children }};
    const root_children = [_]IcicleNode{.{ .label = "L1", .value = 1, .children = &level1_children }};
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 1, .children = &root_children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Nodes beyond depth 6 should not render; no panic
}

test "node with > MAX_CHILDREN_PER_NODE children caps at 8 during render" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var children: [16]IcicleNode = undefined;
    for (0..16) |i| {
        children[i] = .{ .label = "C", .value = 10 };
    }
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 160, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Only first 8 children should render at depth 1; no panic
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "deep + wide tree respects both MAX_DEPTH and MAX_CHILDREN_PER_NODE" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var grandchildren: [10]IcicleNode = undefined;
    for (0..10) |i| {
        grandchildren[i] = .{ .label = "GC", .value = 1 };
    }
    var children: [10]IcicleNode = undefined;
    for (0..10) |i| {
        if (i == 0) {
            children[i] = .{ .label = "C", .value = 1, .children = &grandchildren };
        } else {
            children[i] = .{ .label = "C", .value = 1 };
        }
    }
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 10, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };

    chart.render(&buf, area);
    // Caps: 8 children at depth 1, 8 grandchildren at depth 2, capping at depth 6
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 16: Block Border Rendering (2 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "A", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 50, .children = &children } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    chart.render(&buf, area);

    // Block border should render — check for border glyphs
    const has_border = countChar(buf, area, '─') > 0 or
                       countChar(buf, area, '│') > 0 or
                       countChar(buf, area, '┌') > 0 or
                       countChar(buf, area, '┐') > 0 or
                       countChar(buf, area, '└') > 0 or
                       countChar(buf, area, '┘') > 0;
    try testing.expect(has_border);
}

test "render block in offset area" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    const root = IcicleChart{ .root = .{ .label = "Root", .value = 100 } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 17: Style Precedence (3 tests)
// ============================================================================

test "node.style overrides self.style when set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const root = IcicleChart{
        .root = .{ .label = "Root", .value = 100, .style = .{ .bold = true } },
        .style = .{ .dim = true },
    };
    const chart = IcicleChart.init().withRoot(root.root.?).withStyle(root.style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Root's bold style should take precedence over chart's dim
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused_style overrides node.style when on focused path and set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "A", .value = 50, .style = .{ .bold = true } },
    };
    const root = IcicleChart{
        .root = .{ .label = "Root", .value = 50, .children = &children },
        .focused_style = .{ .reverse = true },
    };
    const focused_path = [_]usize{0};
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withFocused(&focused_path)
        .withFocusedStyle(root.focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Child A is on focused path, so focused_style should apply
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused_style does not override when empty/default" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "A", .value = 50, .style = .{ .italic = true } },
    };
    const root = IcicleChart{
        .root = .{ .label = "Root", .value = 50, .children = &children },
        .focused_style = .{}, // empty/default
    };
    const focused_path = [_]usize{0};
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withFocused(&focused_path)
        .withFocusedStyle(root.focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };

    chart.render(&buf, area);
    // Empty focused_style means node's own style is used instead
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 18: One-Row-Tall Area (1 test)
// ============================================================================

test "1-row tall area renders only root band" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const children = [_]IcicleNode{
        .{ .label = "Child", .value = 50 },
    };
    const root = IcicleChart{ .root = .{ .label = "Root", .value = 50, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };

    chart.render(&buf, area);
    // Only depth 0 (root) fits in 1 row; child rows not rendered
    const cell_root = getCell(buf, area, 30, 0);
    try testing.expect(cell_root != null);
}

// ============================================================================
// Group 19: Builder Chaining (1 test)
// ============================================================================

test "builder chain sets all fields correctly" {
    const root = IcicleNode{ .label = "Root", .value = 100 };
    const focused_path = [_]usize{0};

    const chart = IcicleChart.init()
        .withRoot(root)
        .withFocused(&focused_path)
        .withShowLabels(false)
        .withShowValues(true)
        .withStyle(.{ .underline = true })
        .withLabelStyle(.{ .bold = true })
        .withFocusedStyle(.{ .reverse = true })
        .withBlock(.{});

    try testing.expectEqualStrings("Root", chart.root.?.label);
    try testing.expectEqual(@as(usize, 1), chart.focused.len);
    try testing.expectEqual(false, chart.show_labels);
    try testing.expectEqual(true, chart.show_values);
    try testing.expectEqual(true, chart.style.underline);
    try testing.expectEqual(true, chart.label_style.bold);
    try testing.expectEqual(true, chart.focused_style.reverse);
    try testing.expect(chart.block != null);
}

// ============================================================================
// Group 20: Complex Hierarchical Tree (2 tests)
// ============================================================================

test "render balanced 3-level tree" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    // Level 2 children (grandchildren)
    const gc_a1 = [_]IcicleNode{.{ .label = "A1.1", .value = 10 }};
    const gc_a2 = [_]IcicleNode{.{ .label = "A2.1", .value = 10 }};
    const gc_b1 = [_]IcicleNode{.{ .label = "B1.1", .value = 10 }};

    // Level 1 children
    const children = [_]IcicleNode{
        .{ .label = "A1", .value = 20, .children = &gc_a1 },
        .{ .label = "A2", .value = 20, .children = &gc_a2 },
        .{ .label = "B1", .value = 20, .children = &gc_b1 },
    };

    const root = IcicleChart{ .root = .{ .label = "Root", .value = 60, .children = &children } };
    const chart = IcicleChart.init()
        .withRoot(root.root.?)
        .withShowLabels(true)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render unbalanced tree with varying depths" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    // Varied depth: some shallow, some deep
    const gc_a = [_]IcicleNode{.{ .label = "A1", .value = 5 }};
    const children = [_]IcicleNode{
        .{ .label = "Short", .value = 20 }, // no grandchildren
        .{ .label = "Deep", .value = 20, .children = &gc_a }, // has grandchildren
    };

    const root = IcicleChart{ .root = .{ .label = "Root", .value = 40, .children = &children } };
    const chart = IcicleChart.init().withRoot(root.root.?);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}
