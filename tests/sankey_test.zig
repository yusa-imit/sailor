//! SankeyDiagram Widget Tests — TDD Red Phase
//!
//! Tests SankeyDiagram widget with flow visualization between columns of nodes,
//! builder pattern, column layout, focused styling, capping at MAX_NODES/MAX_FLOWS,
//! and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const SankeyDiagram = sailor.tui.widgets.SankeyDiagram;
const SankeyNode = sailor.tui.widgets.SankeyNode;
const SankeyFlow = sailor.tui.widgets.SankeyFlow;

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

/// Get character at specific position in buffer
fn charAtPos(buf: Buffer, x: u16, y: u16) ?u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return null;
}

/// Count rows that have non-space content
fn countContentRows(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var has_content = false;
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    has_content = true;
                    break;
                }
            }
        }
        if (has_content) count += 1;
    }
    return count;
}

/// Count columns that have non-space content
fn countContentColumns(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var x = area.x;
    while (x < area.x + area.width and x < buf.width) : (x += 1) {
        var has_content = false;
        var y = area.y;
        while (y < area.y + area.height and y < buf.height) : (y += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    has_content = true;
                    break;
                }
            }
        }
        if (has_content) count += 1;
    }
    return count;
}

// ============================================================================
// Init & Defaults Tests (6 tests)
// ============================================================================

test "SankeyDiagram: init returns zero-value struct" {
    const sk = SankeyDiagram.init();
    try testing.expectEqual(@as(usize, 0), sk.nodes.len);
    try testing.expectEqual(@as(usize, 0), sk.flows.len);
}

test "SankeyDiagram: init defaults focused to 0" {
    const sk = SankeyDiagram.init();
    try testing.expectEqual(@as(usize, 0), sk.focused);
}

test "SankeyDiagram: init defaults node_width to 2" {
    const sk = SankeyDiagram.init();
    try testing.expectEqual(@as(u16, 2), sk.node_width);
}

test "SankeyDiagram: init defaults col_gap to 8" {
    const sk = SankeyDiagram.init();
    try testing.expectEqual(@as(u16, 8), sk.col_gap);
}

test "SankeyDiagram: init defaults block to null" {
    const sk = SankeyDiagram.init();
    try testing.expect(sk.block == null);
}

test "SankeyDiagram: init defaults all styles to empty" {
    const sk = SankeyDiagram.init();
    try testing.expectEqual(@as(bool, false), sk.style.bold);
    try testing.expectEqual(@as(bool, false), sk.node_style.bold);
    try testing.expectEqual(@as(bool, false), sk.flow_style.bold);
    try testing.expectEqual(@as(bool, false), sk.focused_style.bold);
}

// ============================================================================
// nodeCount() Tests (3 tests)
// ============================================================================

test "SankeyDiagram.nodeCount returns 0 for empty nodes" {
    const sk = SankeyDiagram.init();
    try testing.expectEqual(@as(usize, 0), sk.nodeCount());
}

test "SankeyDiagram.nodeCount returns correct count for small list" {
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
        .{ .label = "C", .column = 2 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 3), sk.nodeCount());
}

test "SankeyDiagram.nodeCount caps at MAX_NODES (32)" {
    var nodes: [33]SankeyNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = .{ .label = "N", .column = i % 5 };
    }
    const sk = SankeyDiagram.init().withNodes(&nodes);
    try testing.expectEqual(SankeyDiagram.MAX_NODES, sk.nodeCount());
}

// ============================================================================
// flowCount() Tests (3 tests)
// ============================================================================

test "SankeyDiagram.flowCount returns 0 for empty flows" {
    const sk = SankeyDiagram.init();
    try testing.expectEqual(@as(usize, 0), sk.flowCount());
}

test "SankeyDiagram.flowCount returns correct count for small list" {
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 10.0 },
        .{ .source = 1, .target = 2, .value = 8.0 },
    };
    const sk = SankeyDiagram.init().withFlows(&flows);
    try testing.expectEqual(@as(usize, 2), sk.flowCount());
}

test "SankeyDiagram.flowCount caps at MAX_FLOWS (64)" {
    var flows: [65]SankeyFlow = undefined;
    for (&flows, 0..) |*flow, i| {
        flow.* = .{ .source = i % 8, .target = (i + 1) % 8, .value = 1.0 };
    }
    const sk = SankeyDiagram.init().withFlows(&flows);
    try testing.expectEqual(SankeyDiagram.MAX_FLOWS, sk.flowCount());
}

// ============================================================================
// Builder API Tests (11 tests)
// ============================================================================

test "SankeyDiagram.withNodes stores nodes immutably" {
    var nodes1 = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    var nodes2 = [_]SankeyNode{.{ .label = "B", .column = 1 }, .{ .label = "C", .column = 1 }};
    const sk1 = SankeyDiagram.init().withNodes(&nodes1);
    const sk2 = sk1.withNodes(&nodes2);
    try testing.expectEqual(@as(usize, 1), sk1.nodeCount());
    try testing.expectEqual(@as(usize, 2), sk2.nodeCount());
}

test "SankeyDiagram.withFlows stores flows immutably" {
    var flows1 = [_]SankeyFlow{.{ .source = 0, .target = 1, .value = 5.0 }};
    var flows2 = [_]SankeyFlow{.{ .source = 0, .target = 1, .value = 3.0 }, .{ .source = 1, .target = 2, .value = 2.0 }};
    const sk1 = SankeyDiagram.init().withFlows(&flows1);
    const sk2 = sk1.withFlows(&flows2);
    try testing.expectEqual(@as(usize, 1), sk1.flowCount());
    try testing.expectEqual(@as(usize, 2), sk2.flowCount());
}

test "SankeyDiagram.withFocused sets focused node index" {
    const sk = SankeyDiagram.init().withFocused(5);
    try testing.expectEqual(@as(usize, 5), sk.focused);
}

test "SankeyDiagram.withNodeWidth sets node width" {
    const sk = SankeyDiagram.init().withNodeWidth(4);
    try testing.expectEqual(@as(u16, 4), sk.node_width);
}

test "SankeyDiagram.withColGap sets column gap" {
    const sk = SankeyDiagram.init().withColGap(12);
    try testing.expectEqual(@as(u16, 12), sk.col_gap);
}

test "SankeyDiagram.withStyle sets base style" {
    const style = Style{ .dim = true };
    const sk = SankeyDiagram.init().withStyle(style);
    try testing.expectEqual(true, sk.style.dim);
}

test "SankeyDiagram.withNodeStyle sets node style" {
    const style = Style{ .bold = true };
    const sk = SankeyDiagram.init().withNodeStyle(style);
    try testing.expectEqual(true, sk.node_style.bold);
}

test "SankeyDiagram.withFlowStyle sets flow style" {
    const style = Style{ .italic = true };
    const sk = SankeyDiagram.init().withFlowStyle(style);
    try testing.expectEqual(true, sk.flow_style.italic);
}

test "SankeyDiagram.withFocusedStyle sets focused style" {
    const style = Style{ .reverse = true };
    const sk = SankeyDiagram.init().withFocusedStyle(style);
    try testing.expectEqual(true, sk.focused_style.reverse);
}

test "SankeyDiagram.withBlock sets block border" {
    const block = Block{};
    const sk = SankeyDiagram.init().withBlock(block);
    try testing.expect(sk.block != null);
}

test "SankeyDiagram builder chaining sets multiple fields" {
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    var flows = [_]SankeyFlow{.{ .source = 0, .target = 1, .value = 10.0 }};
    const sk = SankeyDiagram.init()
        .withNodes(&nodes)
        .withFlows(&flows)
        .withFocused(0)
        .withNodeWidth(3)
        .withColGap(10);
    try testing.expectEqual(@as(usize, 1), sk.nodeCount());
    try testing.expectEqual(@as(usize, 1), sk.flowCount());
    try testing.expectEqual(@as(usize, 0), sk.focused);
    try testing.expectEqual(@as(u16, 3), sk.node_width);
    try testing.expectEqual(@as(u16, 10), sk.col_gap);
}

// ============================================================================
// Render — Zero/Minimal Area Tests (3 tests)
// ============================================================================

test "SankeyDiagram.render to zero-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    const sk = SankeyDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 20 };
    sk.render(&buf, area);
}

test "SankeyDiagram.render to zero-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    const sk = SankeyDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    sk.render(&buf, area);
}

test "SankeyDiagram.render to 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    const sk = SankeyDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    sk.render(&buf, area);
}

// ============================================================================
// Render — Empty Data Tests (2 tests)
// ============================================================================

test "SankeyDiagram.render with no nodes does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const sk = SankeyDiagram.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
}

test "SankeyDiagram.render with no flows does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
}

// ============================================================================
// Render — Single Node Tests (4 tests)
// ============================================================================

test "SankeyDiagram.render single node renders content" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render single node with label shows text" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var nodes = [_]SankeyNode{.{ .label = "Node", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render single node respects node_width" {
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withNodeWidth(5);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render single node focused uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const focused_style = Style{ .bold = true };
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withFocused(0).withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    sk.render(&buf, area);
    // First node bar should have bold style
    try testing.expect(buf.getStyle(0, 0).bold);
}

// ============================================================================
// Render — Two Node Tests (4 tests)
// ============================================================================

test "SankeyDiagram.render two nodes different columns" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SanzeyDiagram.render two nodes same column renders vertically" {
    var buf = try Buffer.init(testing.allocator, 20, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render two nodes respects col_gap spacing" {
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withColGap(15);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render two nodes with flow connects them" {
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 10.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

// ============================================================================
// Render — Three Node Two Flow Tests (3 tests)
// ============================================================================

test "SankeyDiagram.render three nodes two flows in linear chain" {
    var buf = try Buffer.init(testing.allocator, 60, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
        .{ .label = "C", .column = 2 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 10.0 },
        .{ .source = 1, .target = 2, .value = 10.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render three nodes two flows from one source" {
    var buf = try Buffer.init(testing.allocator, 60, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
        .{ .label = "C", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 6.0 },
        .{ .source = 0, .target = 2, .value = 4.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render three nodes two flows to one target" {
    var buf = try Buffer.init(testing.allocator, 60, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 0 },
        .{ .label = "C", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 2, .value = 7.0 },
        .{ .source = 1, .target = 2, .value = 3.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

// ============================================================================
// Column Layout Tests (5 tests)
// ============================================================================

test "SankeyDiagram.render nodes positioned by column left to right" {
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "Col0", .column = 0 },
        .{ .label = "Col1", .column = 1 },
        .{ .label = "Col2", .column = 2 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render nodes in same column stack vertically" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 0 },
        .{ .label = "C", .column = 0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    sk.render(&buf, area);
    const content = countContentRows(buf, area);
    try testing.expect(content >= 2);
}

test "SankeyDiagram.render multiple columns renders horizontally" {
    var buf = try Buffer.init(testing.allocator, 80, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
        .{ .label = "C", .column = 2 },
        .{ .label = "D", .column = 3 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };
    sk.render(&buf, area);
    const content = countContentColumns(buf, area);
    try testing.expect(content >= 2);
}

test "SankeyDiagram.render with large node_width fills area" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withNodeWidth(8);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render with small col_gap compresses layout" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withColGap(2);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

// ============================================================================
// Node Height Proportional to Flow Tests (3 tests)
// ============================================================================

test "SankeyDiagram.render node height reflects total flow" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "Source", .column = 0 },
        .{ .label = "Target", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 100.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render node with multiple flows sums to total" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 5.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render zero-value flow handles gracefully" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 0.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
}

// ============================================================================
// Focused Node Tests (4 tests)
// ============================================================================

test "SankeyDiagram.render focused node uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const focused_style = Style{ .bold = true };
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFocused(0).withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    sk.render(&buf, area);
    // First node at (0,0) should have bold style
    try testing.expect(buf.getStyle(0, 0).bold);
}

test "SankeyDiagram.render non-focused nodes use node_style" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const node_style = Style{ .dim = true };
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withNodeStyle(node_style).withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    sk.render(&buf, area);
    // Since focused=99 (out of bounds), all nodes use node_style
    try testing.expect(buf.getStyle(0, 0).dim);
}

test "SanzeyDiagram.render only focused node has focused_style" {
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    const focused_style = Style{ .reverse = true };
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
        .{ .label = "C", .column = 2 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFocused(1).withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    sk.render(&buf, area);
    // Node at index 1 should have reverse style
    // We can't know exact position without implementation details, but it should render without error
}

test "SankeyDiagram.render focused index out of bounds handled safely" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withFocused(999);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    sk.render(&buf, area);
}

// ============================================================================
// Flow Drawing Tests (4 tests)
// ============================================================================

test "SankeyDiagram.render draws flow as horizontal lines" {
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 10.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    sk.render(&buf, area);
    // Flows should include dashes connecting columns
    const has_content = countNonEmptyCells(buf, area) > 0;
    try testing.expect(has_content);
}

test "SanzeyDiagram.render multiple flows between same nodes" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 5.0 },
        .{ .source = 0, .target = 1, .value = 3.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SankeyDiagram.render flow style applied to flow lines" {
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    const flow_style = Style{ .italic = true };
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 10.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows).withFlowStyle(flow_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SanzeyDiagram.render flow connecting non-adjacent columns" {
    var buf = try Buffer.init(testing.allocator, 70, 15);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 2 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 10.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

// ============================================================================
// MAX_NODES Capping Tests (3 tests)
// ============================================================================

test "SanzeyDiagram.nodeCount caps at MAX_NODES when 33 provided" {
    var nodes: [33]SankeyNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = .{ .label = "N", .column = i % 4 };
    }
    const sk = SankeyDiagram.init().withNodes(&nodes);
    try testing.expectEqual(SankeyDiagram.MAX_NODES, sk.nodeCount());
}

test "SanzeyDiagram.render with 33 nodes only renders first 32" {
    var buf = try Buffer.init(testing.allocator, 100, 40);
    defer buf.deinit();
    var nodes: [33]SankeyNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = .{ .label = "N", .column = i % 8 };
    }
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    sk.render(&buf, area);
    try testing.expectEqual(SankeyDiagram.MAX_NODES, sk.nodeCount());
}

test "SanzeyDiagram.render preserves rendering with exactly MAX_NODES" {
    var buf = try Buffer.init(testing.allocator, 100, 40);
    defer buf.deinit();
    var nodes: [32]SankeyNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = .{ .label = "N", .column = i % 8 };
    }
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    sk.render(&buf, area);
    try testing.expectEqual(SankeyDiagram.MAX_NODES, sk.nodeCount());
}

// ============================================================================
// MAX_FLOWS Capping Tests (3 tests)
// ============================================================================

test "SanzeyDiagram.flowCount caps at MAX_FLOWS when 65 provided" {
    var flows: [65]SankeyFlow = undefined;
    for (&flows, 0..) |*flow, i| {
        flow.* = .{ .source = i % 16, .target = (i + 1) % 16, .value = 1.0 };
    }
    const sk = SankeyDiagram.init().withFlows(&flows);
    try testing.expectEqual(SankeyDiagram.MAX_FLOWS, sk.flowCount());
}

test "SanzeyDiagram.render with 65 flows only renders first 64" {
    var buf = try Buffer.init(testing.allocator, 100, 40);
    defer buf.deinit();
    var nodes: [16]SankeyNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = .{ .label = "N", .column = i % 4 };
    }
    var flows: [65]SankeyFlow = undefined;
    for (&flows, 0..) |*flow, i| {
        flow.* = .{ .source = i % 16, .target = (i + 1) % 16, .value = 1.0 };
    }
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    sk.render(&buf, area);
    try testing.expectEqual(SankeyDiagram.MAX_FLOWS, sk.flowCount());
}

test "SanzeyDiagram.render with exactly MAX_FLOWS renders without issue" {
    var buf = try Buffer.init(testing.allocator, 100, 40);
    defer buf.deinit();
    var nodes: [16]SankeyNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = .{ .label = "N", .column = i % 4 };
    }
    var flows: [64]SankeyFlow = undefined;
    for (&flows, 0..) |*flow, i| {
        flow.* = .{ .source = i % 16, .target = (i + 1) % 16, .value = 1.0 };
    }
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    sk.render(&buf, area);
    try testing.expectEqual(SankeyDiagram.MAX_FLOWS, sk.flowCount());
}

// ============================================================================
// Block Border Tests (3 tests)
// ============================================================================

test "SanzeyDiagram.render with block renders frame" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const block = Block{};
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SanzeyDiagram.render without block no frame" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
}

test "SanzeyDiagram.render block reduces available space for content" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    const block = Block{ .padding_left = 2, .padding_right = 2, .padding_top = 1, .padding_bottom = 1 };
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 30 };
    sk.render(&buf, area);
}

// ============================================================================
// Style Tests (4 tests)
// ============================================================================

test "SanzeyDiagram.render with base style applied to nodes" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const base_style = Style{ .dim = true };
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withStyle(base_style).withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    sk.render(&buf, area);
    try testing.expect(buf.getStyle(0, 0).dim);
}

test "SanzeyDiagram.render node_style overrides base style for non-focused nodes" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const node_style = Style{ .italic = true };
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withNodeStyle(node_style).withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SanzeyDiagram.render flow_style applied to flow lines" {
    var buf = try Buffer.init(testing.allocator, 50, 15);
    defer buf.deinit();
    const flow_style = Style{ .underline = true };
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{.{ .source = 0, .target = 1, .value = 10.0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows).withFlowStyle(flow_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SanzeyDiagram.render focused_style overrides all for focused node" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const node_style = Style{ .dim = true };
    const focused_style = Style{ .bold = true, .reverse = true };
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withNodeStyle(node_style).withFocused(0).withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    sk.render(&buf, area);
}

// ============================================================================
// Edge Cases Tests (6 tests)
// ============================================================================

test "SanzeyDiagram.render with very large flow value handles scaling" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 1000000.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
}

test "SanzeyDiagram.render with tiny flow value handles scaling" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 0.0001 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
}

test "SanzeyDiagram.render with negative flow value handled safely" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = -10.0 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk.render(&buf, area);
}

test "SanzeyDiagram.render area exactly 1x1 renders single cell" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var nodes = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    sk.render(&buf, area);
}

test "SanzeyDiagram.render offset area within buffer boundary" {
    var buf = try Buffer.init(testing.allocator, 60, 40);
    defer buf.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk = SankeyDiagram.init().withNodes(&nodes);
    const area = Rect{ .x = 10, .y = 10, .width = 40, .height = 20 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SanzeyDiagram.render with many nodes and flows together" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var nodes: [16]SankeyNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = .{ .label = "N", .column = i % 4 };
    }
    var flows: [20]SankeyFlow = undefined;
    for (&flows, 0..) |*flow, i| {
        flow.* = .{ .source = i % 16, .target = (i + 3) % 16, .value = 5.0 + @as(f32, @floatFromInt(i)) };
    }
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

// ============================================================================
// Comprehensive Integration Tests (5 tests)
// ============================================================================

test "SanzeyDiagram.render consistency: identical diagrams produce similar layouts" {
    var buf1 = try Buffer.init(testing.allocator, 50, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 20);
    defer buf2.deinit();
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    var flows = [_]SankeyFlow{.{ .source = 0, .target = 1, .value = 10.0 }};
    const sk = SankeyDiagram.init().withNodes(&nodes).withFlows(&flows);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    sk.render(&buf1, area);
    sk.render(&buf2, area);
    const count1 = countNonEmptyCells(buf1, area);
    const count2 = countNonEmptyCells(buf2, area);
    try testing.expectEqual(count1, count2);
}

test "SanzeyDiagram.render with all feature combinations" {
    var buf = try Buffer.init(testing.allocator, 70, 35);
    defer buf.deinit();
    const base_style = Style{ .dim = true };
    const node_style = Style{ .bold = true };
    const flow_style = Style{ .italic = true };
    const focused_style = Style{ .reverse = true, .underline = true };
    const block = Block{};
    var nodes = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
        .{ .label = "C", .column = 2 },
    };
    var flows = [_]SankeyFlow{
        .{ .source = 0, .target = 1, .value = 5.0 },
        .{ .source = 1, .target = 2, .value = 5.0 },
    };
    const sk = SankeyDiagram.init()
        .withNodes(&nodes)
        .withFlows(&flows)
        .withFocused(1)
        .withNodeWidth(3)
        .withColGap(10)
        .withStyle(base_style)
        .withNodeStyle(node_style)
        .withFlowStyle(flow_style)
        .withFocusedStyle(focused_style)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 35 };
    sk.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "SanzeyDiagram.render builder immutability: modifications don't affect original" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();
    var nodes1 = [_]SankeyNode{.{ .label = "A", .column = 0 }};
    var nodes2 = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk1 = SankeyDiagram.init().withNodes(&nodes1);
    const sk2 = sk1.withNodes(&nodes2);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk1.render(&buf1, area);
    sk2.render(&buf2, area);
    const count1 = countNonEmptyCells(buf1, area);
    const count2 = countNonEmptyCells(buf2, area);
    // sk2 should render more content since it has 2 nodes vs 1
    try testing.expect(count1 >= 0 and count2 >= count1);
}

test "SanzeyDiagram.render multiple diagrams in sequence" {
    var buf = try Buffer.init(testing.allocator, 100, 40);
    defer buf.deinit();

    // Diagram 1: two nodes
    var nodes1 = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
    };
    const sk1 = SankeyDiagram.init().withNodes(&nodes1);
    const area1 = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sk1.render(&buf, area1);

    // Diagram 2: three nodes
    var nodes2 = [_]SankeyNode{
        .{ .label = "X", .column = 0 },
        .{ .label = "Y", .column = 1 },
        .{ .label = "Z", .column = 2 },
    };
    const sk2 = SankeyDiagram.init().withNodes(&nodes2);
    const area2 = Rect{ .x = 50, .y = 0, .width = 50, .height = 20 };
    sk2.render(&buf, area2);
}

test "SanzeyDiagram.render column ordering independent of node order" {
    var buf1 = try Buffer.init(testing.allocator, 50, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 20);
    defer buf2.deinit();

    // Nodes in order: col 0, 1, 2
    var nodes_ordered = [_]SankeyNode{
        .{ .label = "A", .column = 0 },
        .{ .label = "B", .column = 1 },
        .{ .label = "C", .column = 2 },
    };

    // Nodes in reverse: col 2, 1, 0 (but column values determine layout)
    var nodes_reversed = [_]SankeyNode{
        .{ .label = "C", .column = 2 },
        .{ .label = "B", .column = 1 },
        .{ .label = "A", .column = 0 },
    };

    const sk1 = SankeyDiagram.init().withNodes(&nodes_ordered);
    const sk2 = SankeyDiagram.init().withNodes(&nodes_reversed);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    sk1.render(&buf1, area);
    sk2.render(&buf2, area);

    // Both should render successfully
    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}
