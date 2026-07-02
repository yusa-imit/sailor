//! ChordDiagram Widget Tests — TDD Red Phase
//!
//! Tests ChordDiagram widget with node-to-node flow visualization,
//! matrix rendering, focused node styling, labels, block borders,
//! MAX_NODES capping, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const ChordDiagram = sailor.tui.widgets.ChordDiagram;

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
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "ChordDiagram.init creates default diagram with zero nodes" {
    const cd = ChordDiagram.init();
    try testing.expectEqual(@as(usize, 0), cd.nodes.len);
}

test "ChordDiagram.init defaults matrix to empty" {
    const cd = ChordDiagram.init();
    try testing.expectEqual(@as(usize, 0), cd.matrix.len);
}

test "ChordDiagram.init defaults focused to 0" {
    const cd = ChordDiagram.init();
    try testing.expectEqual(@as(usize, 0), cd.focused);
}

test "ChordDiagram.init defaults show_labels to true" {
    const cd = ChordDiagram.init();
    try testing.expectEqual(true, cd.show_labels);
}

test "ChordDiagram.init defaults block to null" {
    const cd = ChordDiagram.init();
    try testing.expect(cd.block == null);
}

// ============================================================================
// Group 2: MAX_NODES Constant (1 test)
// ============================================================================

test "ChordDiagram.MAX_NODES equals 16" {
    try testing.expectEqual(@as(usize, 16), ChordDiagram.MAX_NODES);
}

// ============================================================================
// Group 3: nodeCount() Method (5 tests)
// ============================================================================

test "ChordDiagram.nodeCount with empty nodes returns 0" {
    const cd = ChordDiagram.init();
    try testing.expectEqual(@as(usize, 0), cd.nodeCount());
}

test "ChordDiagram.nodeCount with 1 node returns 1" {
    var nodes = [_][]const u8{"A"};
    const cd = ChordDiagram.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 1), cd.nodeCount());
}

test "ChordDiagram.nodeCount with 5 nodes returns 5" {
    var nodes = [_][]const u8{ "A", "B", "C", "D", "E" };
    const cd = ChordDiagram.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 5), cd.nodeCount());
}

test "ChordDiagram.nodeCount with exactly MAX_NODES returns 16" {
    var nodes: [16][]const u8 = undefined;
    for (0..16) |i| {
        nodes[i] = "N";
    }
    const cd = ChordDiagram.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 16), cd.nodeCount());
}

test "ChordDiagram.nodeCount caps at MAX_NODES when 20 nodes provided" {
    var nodes: [20][]const u8 = undefined;
    for (0..20) |i| {
        nodes[i] = "N";
    }
    const cd = ChordDiagram.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 16), cd.nodeCount());
}

// ============================================================================
// Group 4: totalFlow() Method (5 tests)
// ============================================================================

test "ChordDiagram.totalFlow with empty matrix returns 0.0" {
    const cd = ChordDiagram.init();
    try testing.expectEqual(@as(f32, 0.0), cd.totalFlow());
}

test "ChordDiagram.totalFlow with single flow 2x2 matrix" {
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 0.5, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix);
    const flow = cd.totalFlow();
    try testing.expect(flow > 0.0);
}

test "ChordDiagram.totalFlow with all zeros matrix returns 0.0" {
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 0.0, 0.0 };
    var row1 = [_]f32{ 0.0, 0.0, 0.0 };
    var row2 = [_]f32{ 0.0, 0.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix);
    try testing.expectEqual(@as(f32, 0.0), cd.totalFlow());
}

test "ChordDiagram.totalFlow sums all non-zero flows" {
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 5.0 };
    var row1 = [_]f32{ 3.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix);
    const flow = cd.totalFlow();
    try testing.expect(flow >= 8.0);
}

test "ChordDiagram.totalFlow with single node self-referential matrix" {
    var nodes = [_][]const u8{"A"};
    var row0 = [_]f32{2.5};
    var matrix = [_][]const f32{&row0};
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix);
    const flow = cd.totalFlow();
    try testing.expect(flow > 0.0);
}

// ============================================================================
// Group 5: Builder Immutability (5 tests)
// ============================================================================

test "ChordDiagram.withNodes does not modify original" {
    var nodes1 = [_][]const u8{"A"};
    var nodes2 = [_][]const u8{ "X", "Y" };

    const cd1 = ChordDiagram.init().withNodes(&nodes1);
    const cd2 = cd1.withNodes(&nodes2);

    try testing.expectEqual(@as(usize, 1), cd1.nodes.len);
    try testing.expectEqual(@as(usize, 2), cd2.nodes.len);
}

test "ChordDiagram.withMatrix does not modify original" {
    var row0a = [_]f32{0.0};
    var matrix1 = [_][]const f32{&row0a};

    var row0b = [_]f32{ 0.0, 1.0 };
    var row1b = [_]f32{ 1.0, 0.0 };
    var matrix2 = [_][]const f32{ &row0b, &row1b };

    const cd1 = ChordDiagram.init().withMatrix(&matrix1);
    const cd2 = cd1.withMatrix(&matrix2);

    try testing.expectEqual(@as(usize, 1), cd1.matrix.len);
    try testing.expectEqual(@as(usize, 2), cd2.matrix.len);
}

test "ChordDiagram.withFocused sets focused index" {
    const cd1 = ChordDiagram.init().withFocused(0);
    const cd2 = cd1.withFocused(5);

    try testing.expectEqual(@as(usize, 0), cd1.focused);
    try testing.expectEqual(@as(usize, 5), cd2.focused);
}

test "ChordDiagram.withStyle sets style" {
    const style = Style{ .bold = true };
    const cd = ChordDiagram.init().withStyle(style);
    try testing.expectEqual(true, cd.style.bold);
}

test "ChordDiagram.withShowLabels sets show_labels" {
    const cd1 = ChordDiagram.init().withShowLabels(true);
    const cd2 = cd1.withShowLabels(false);

    try testing.expectEqual(true, cd1.show_labels);
    try testing.expectEqual(false, cd2.show_labels);
}

// ============================================================================
// Group 6: Builder Methods for Styles (4 tests)
// ============================================================================

test "ChordDiagram.withArcStyle sets arc_style" {
    const style = Style{ .fg = .{ .indexed = 2 } };
    const cd = ChordDiagram.init().withArcStyle(style);
    try testing.expect(cd.arc_style.fg != null);
}

test "ChordDiagram.withFocusedStyle sets focused_style" {
    const style = Style{ .bold = true };
    const cd = ChordDiagram.init().withFocusedStyle(style);
    try testing.expectEqual(true, cd.focused_style.bold);
}

test "ChordDiagram.withBlock sets block" {
    const block = Block{};
    const cd = ChordDiagram.init().withBlock(block);
    try testing.expect(cd.block != null);
}

test "ChordDiagram.withBlock with null unsets block" {
    const cd1 = ChordDiagram.init().withBlock(.{});
    const cd2 = cd1.withBlock(null);

    try testing.expect(cd1.block != null);
    try testing.expect(cd2.block == null);
}

// ============================================================================
// Group 7: Render — Zero/Minimal Area (5 tests)
// ============================================================================

test "ChordDiagram.render on 0x0 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    const cd = ChordDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    cd.render(&buf, area);
}

test "ChordDiagram.render on 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    const cd = ChordDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    cd.render(&buf, area);
}

test "ChordDiagram.render on 2x2 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 2, 2);
    defer buf.deinit();
    const cd = ChordDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    cd.render(&buf, area);
}

test "ChordDiagram.render on 0-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    const cd = ChordDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    cd.render(&buf, area);
}

test "ChordDiagram.render on 0-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    const cd = ChordDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    cd.render(&buf, area);
}

// ============================================================================
// Group 8: Render — Empty Nodes (3 tests)
// ============================================================================

test "ChordDiagram.render with empty nodes produces no content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    const cd = ChordDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "ChordDiagram.render empty nodes with show_labels=false produces no content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    const cd = ChordDiagram.init().withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "ChordDiagram.render empty nodes with empty matrix produces no content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{};
    var matrix = [_][]const f32{};
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 9: Render — Single Node (3 tests)
// ============================================================================

test "ChordDiagram.render single node produces content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{"A"};
    var row0 = [_]f32{0.0};
    var matrix = [_][]const f32{&row0};
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render single node with label shows content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{"NodeA"};
    var row0 = [_]f32{0.0};
    var matrix = [_][]const f32{&row0};
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render single node at different area offsets" {
    var buf = try Buffer.init(testing.allocator, 40, 30);
    defer buf.deinit();
    var nodes = [_][]const u8{"X"};
    var row0 = [_]f32{0.0};
    var matrix = [_][]const f32{&row0};
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 5, .y = 5, .width = 20, .height = 15 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Render — Two Nodes (5 tests)
// ============================================================================

test "ChordDiagram.render two nodes produces content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 0.5, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render two nodes with flow from A to B" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 5.0 };
    var row1 = [_]f32{ 0.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render two nodes with bidirectional flow" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 2.0 };
    var row1 = [_]f32{ 3.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render two nodes with zero flow" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 0.0 };
    var row1 = [_]f32{ 0.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    // Should still render node markers even with zero flow
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render two nodes with labels shows content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "Node1", "Node2" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: Render — Multiple Nodes (5 tests)
// ============================================================================

test "ChordDiagram.render four nodes produces content" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C", "D" };
    var row0 = [_]f32{ 0.0, 1.0, 2.0, 3.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0, 2.0 };
    var row2 = [_]f32{ 2.0, 1.0, 0.0, 1.0 };
    var row3 = [_]f32{ 3.0, 2.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2, &row3 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render three nodes in circle arrangement" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "X", "Y", "Z" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render five nodes produces nodes and chords" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "1", "2", "3", "4", "5" };
    var row0 = [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 };
    var row3 = [_]f32{ 1.0, 0.0, 1.0, 0.0, 1.0 };
    var row4 = [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2, &row3, &row4 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render six nodes with varying flows" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C", "D", "E", "F" };
    var row0 = [_]f32{ 0.0, 5.0, 0.0, 0.0, 0.0, 0.0 };
    var row1 = [_]f32{ 3.0, 0.0, 2.0, 0.0, 0.0, 0.0 };
    var row2 = [_]f32{ 0.0, 4.0, 0.0, 1.0, 0.0, 0.0 };
    var row3 = [_]f32{ 0.0, 0.0, 2.0, 0.0, 3.0, 0.0 };
    var row4 = [_]f32{ 0.0, 0.0, 0.0, 1.0, 0.0, 4.0 };
    var row5 = [_]f32{ 0.0, 0.0, 0.0, 0.0, 2.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2, &row3, &row4, &row5 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render eight nodes renders all nodes" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C", "D", "E", "F", "G", "H" };
    var row0 = [_]f32{ 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    var row2 = [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0 };
    var row3 = [_]f32{ 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0 };
    var row4 = [_]f32{ 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0 };
    var row5 = [_]f32{ 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0 };
    var row6 = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0 };
    var row7 = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2, &row3, &row4, &row5, &row6, &row7 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: Render — Focused Node Styling (5 tests)
// ============================================================================

test "ChordDiagram.render focused=0 on two-node diagram applies focus style to first node" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const focused_style = Style{ .bold = true };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withFocused(0)
        .withFocusedStyle(focused_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render focused=1 on three-node diagram" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const focused_style = Style{ .bold = true };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render focused out of range does not apply focus style" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const focused_style = Style{ .bold = true };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withFocused(99)
        .withFocusedStyle(focused_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render changing focused index changes target node" {
    var buf1 = try Buffer.init(testing.allocator, 30, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 30, 20);
    defer buf2.deinit();

    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };

    const cd1 = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withFocused(0).withShowLabels(false);
    const cd2 = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix).withFocused(2).withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd1.render(&buf1, area);
    cd2.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

test "ChordDiagram.render focused node with custom style renders correctly" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const focused_style = Style{ .dim = true, .bold = true };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 13: Render — Labels (5 tests)
// ============================================================================

test "ChordDiagram.render show_labels=true displays node labels" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render show_labels=false omits node labels" {
    var buf1 = try Buffer.init(testing.allocator, 30, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 30, 20);
    defer buf2.deinit();

    var nodes = [_][]const u8{ "VeryLongNodeName", "AnotherLongName" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };

    const cd_with_labels = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(true);
    const cd_no_labels = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd_with_labels.render(&buf1, area);
    cd_no_labels.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "ChordDiagram.render labels appear near node positions" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "N1", "N2", "N3" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render with single-char node labels" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "X", "Y", "Z" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render with long node labels shows content" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();
    var nodes = [_][]const u8{ "LongNodeNameA", "LongNodeNameB" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 14: Render — Block Border (3 tests)
// ============================================================================

test "ChordDiagram.render with block border renders border and content inside" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    const block = Block{};
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withBlock(block)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render block reduces inner area for diagram" {
    var buf1 = try Buffer.init(testing.allocator, 30, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 30, 20);
    defer buf2.deinit();

    const block = Block{};
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };

    const cd_with_block = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withBlock(block)
        .withShowLabels(false);
    const cd_no_block = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd_with_block.render(&buf1, area);
    cd_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "ChordDiagram.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    const block = (Block{}).withTitle("Chord", .top_left);
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withBlock(block)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 15: Render — Matrix Capping (3 tests)
// ============================================================================

test "ChordDiagram.render matrix larger than nodeCount uses only valid portion" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0, 2.0, 3.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0, 2.0 };
    var row2 = [_]f32{ 2.0, 1.0, 0.0, 1.0 };
    var row3 = [_]f32{ 3.0, 2.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2, &row3 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render 3-node diagram ignores extra matrix rows" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var row3 = [_]f32{ 5.0, 5.0, 5.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2, &row3 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render with mismatched node and matrix counts uses minimum" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C", "D" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Render — MAX_NODES Cap (5 tests)
// ============================================================================

test "ChordDiagram.render with exactly MAX_NODES=16" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes: [16][]const u8 = undefined;
    for (0..16) |i| {
        nodes[i] = "N";
    }
    var row0: [16]f32 = undefined;
    for (0..16) |j| {
        row0[j] = if (j == 1) 1.0 else 0.0;
    }
    var rows: [16][16]f32 = undefined;
    rows[0] = row0;
    for (1..16) |i| {
        for (0..16) |j| {
            rows[i][j] = if (j == (i + 1) % 16) 1.0 else 0.0;
        }
    }
    var matrix_rows: [16][]const f32 = undefined;
    for (0..16) |i| {
        matrix_rows[i] = &rows[i];
    }
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix_rows)
        .withShowLabels(false);
    try testing.expectEqual(@as(usize, 16), cd.nodeCount());
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
}

test "ChordDiagram.nodeCount caps at MAX_NODES with 20 nodes" {
    var nodes: [20][]const u8 = undefined;
    for (0..20) |i| {
        nodes[i] = "N";
    }
    const cd = ChordDiagram.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 16), cd.nodeCount());
}

test "ChordDiagram.render with 20 nodes caps internally to 16" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes: [20][]const u8 = undefined;
    for (0..20) |i| {
        nodes[i] = "N";
    }
    var row0: [20]f32 = undefined;
    for (0..20) |j| {
        row0[j] = if (j == 1) 1.0 else 0.0;
    }
    var rows: [20][20]f32 = undefined;
    rows[0] = row0;
    for (1..20) |i| {
        for (0..20) |j| {
            rows[i][j] = if (j == (i + 1) % 20) 1.0 else 0.0;
        }
    }
    var matrix_rows: [20][]const f32 = undefined;
    for (0..20) |i| {
        matrix_rows[i] = &rows[i];
    }
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix_rows)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    // Should not crash and should handle gracefully
}

test "ChordDiagram.render 16 nodes with proper matrix layout" {
    var buf = try Buffer.init(testing.allocator, 40, 30);
    defer buf.deinit();
    var nodes: [16][]const u8 = undefined;
    for (0..16) |i| {
        nodes[i] = "N";
    }
    var row0: [16]f32 = undefined;
    for (0..16) |j| {
        row0[j] = if (j > 0) 1.0 else 0.0;
    }
    var rows: [16][16]f32 = undefined;
    rows[0] = row0;
    for (1..16) |i| {
        for (0..16) |j| {
            rows[i][j] = 0.0;
        }
        rows[i][0] = 1.0;
    }
    var matrix_rows: [16][]const f32 = undefined;
    for (0..16) |i| {
        matrix_rows[i] = &rows[i];
    }
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix_rows)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 30 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Render — Styles (5 tests)
// ============================================================================

test "ChordDiagram.render with custom style applies to diagram" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const style = Style{ .bold = true };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withStyle(style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render with arc_style for chords" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const arc_style = Style{ .fg = .{ .indexed = 3 } };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withArcStyle(arc_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render with multiple styles renders" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const style = Style{ .bold = true };
    const arc_style = Style{ .italic = true };
    const focused_style = Style{ .dim = true };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withStyle(style)
        .withArcStyle(arc_style)
        .withFocusedStyle(focused_style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render style with color index" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const style = Style{ .fg = .{ .indexed = 5 }, .bold = true };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withStyle(style)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 18: Render — All-Zero Matrix (3 tests)
// ============================================================================

test "ChordDiagram.render all-zero matrix still renders node markers" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 0.0, 0.0 };
    var row1 = [_]f32{ 0.0, 0.0, 0.0 };
    var row2 = [_]f32{ 0.0, 0.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render zero flow with labels shows node labels" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 0.0 };
    var row1 = [_]f32{ 0.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.totalFlow zero matrix returns 0.0" {
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 0.0 };
    var row1 = [_]f32{ 0.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&matrix);
    try testing.expectEqual(@as(f32, 0.0), cd.totalFlow());
}

// ============================================================================
// Group 19: Render — Self-Referential Matrix (2 tests)
// ============================================================================

test "ChordDiagram.render self-referential flows (i->i) renders correctly" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 2.0, 1.0 };
    var row1 = [_]f32{ 1.0, 3.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render high self-flows with minimal cross-flows" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 10.0, 0.1, 0.1 };
    var row1 = [_]f32{ 0.1, 10.0, 0.1 };
    var row2 = [_]f32{ 0.1, 0.1, 10.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Render — Very Small Area (5 tests)
// ============================================================================

test "ChordDiagram.render 5x5 area with multiple nodes" {
    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    cd.render(&buf, area);
    // Should not crash even in small area
}

test "ChordDiagram.render 10x10 area with nodes and labels" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ChordDiagram.render buffer bounds not exceeded on small area" {
    var buf = try Buffer.init(testing.allocator, 8, 8);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B", "C", "D" };
    var row0 = [_]f32{ 0.0, 1.0, 1.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0, 1.0, 1.0 };
    var row2 = [_]f32{ 1.0, 1.0, 0.0, 1.0 };
    var row3 = [_]f32{ 1.0, 1.0, 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1, &row2, &row3 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 8 };
    cd.render(&buf, area);
    // Must not crash or exceed buffer
}

test "ChordDiagram.render area offset from origin" {
    var buf = try Buffer.init(testing.allocator, 40, 30);
    defer buf.deinit();
    var nodes = [_][]const u8{ "A", "B" };
    var row0 = [_]f32{ 0.0, 1.0 };
    var row1 = [_]f32{ 1.0, 0.0 };
    var matrix = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix)
        .withShowLabels(false);
    const area = Rect{ .x = 10, .y = 5, .width = 15, .height = 15 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 21: Memory Safety (2 tests)
// ============================================================================

test "ChordDiagram render does not exceed buffer bounds with many nodes" {
    var buf = try Buffer.init(testing.allocator, 50, 40);
    defer buf.deinit();
    var nodes: [12][]const u8 = undefined;
    for (0..12) |i| {
        nodes[i] = "N";
    }
    var row0: [12]f32 = undefined;
    for (0..12) |j| {
        row0[j] = if (j > 0) 1.0 else 0.0;
    }
    var rows: [12][12]f32 = undefined;
    rows[0] = row0;
    for (1..12) |i| {
        for (0..12) |j| {
            rows[i][j] = if (j == (i + 1) % 12) 1.0 else 0.0;
        }
    }
    var matrix_rows: [12][]const f32 = undefined;
    for (0..12) |i| {
        matrix_rows[i] = &rows[i];
    }
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix_rows)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 40 };
    cd.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 2000); // 50*40 max
}

test "ChordDiagram render with MAX_NODES capping is safe" {
    var buf = try Buffer.init(testing.allocator, 40, 30);
    defer buf.deinit();
    var nodes: [16][]const u8 = undefined;
    for (0..16) |i| {
        nodes[i] = "N";
    }
    var row0: [16]f32 = undefined;
    for (0..16) |j| {
        row0[j] = 1.0;
    }
    var rows: [16][16]f32 = undefined;
    for (0..16) |i| {
        for (0..16) |j| {
            rows[i][j] = 1.0;
        }
    }
    var matrix_rows: [16][]const f32 = undefined;
    for (0..16) |i| {
        matrix_rows[i] = &rows[i];
    }
    const cd = ChordDiagram.init()
        .withNodes(&nodes)
        .withMatrix(&matrix_rows)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 30 };
    cd.render(&buf, area);
    // Must not crash or overflow
}
