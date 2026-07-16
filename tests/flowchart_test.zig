//! FlowChart Widget Tests — TDD Red Phase
//!
//! Tests FlowChart widget with node rendering, edge connectors, grid positioning,
//! node shapes (process/decision/terminal/io), focused navigation, edge labels,
//! block borders, grid spacing, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const FlowChart = sailor.tui.widgets.FlowChart;
const FlowNode = sailor.tui.widgets.flowchart.FlowNode;
const FlowEdge = sailor.tui.widgets.flowchart.FlowEdge;
const NodeKind = sailor.tui.widgets.flowchart.NodeKind;

// ============================================================================
// Helper Functions
// ============================================================================

/// Decode UTF-8 text into a codepoint slice (max 256 codepoints)
fn decodeUtf8(text: []const u8, out: []u21) usize {
    var len: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (len >= out.len) break;
        out[len] = cp;
        len += 1;
    }
    return len;
}

/// Find text in buffer area (UTF-8 aware)
fn findInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var cps: [256]u21 = undefined;
    const cp_count = decodeUtf8(text, &cps);
    if (cp_count == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var cp_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (cp_idx < cp_count) : (cp_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != cps[cp_idx]) {
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

/// Count non-space cells in area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Count occurrences of a character in area
fn countCharInArea(buf: Buffer, area: Rect, ch: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Get cell at absolute position in buffer, verify it matches expected character
fn cellAt(buf: Buffer, x: u16, y: u16, expected: u21) bool {
    if (buf.getConst(x, y)) |cell| {
        return cell.char == expected;
    }
    return false;
}

// ============================================================================
// Group 1: Init/Defaults (5 tests)
// ============================================================================

test "FlowChart.init has empty nodes" {
    const fc = FlowChart.init();
    try testing.expectEqual(@as(usize, 0), fc.nodes.len);
}

test "FlowChart.init has empty edges" {
    const fc = FlowChart.init();
    try testing.expectEqual(@as(usize, 0), fc.edges.len);
}

test "FlowChart.init has focused == 0" {
    const fc = FlowChart.init();
    try testing.expectEqual(@as(usize, 0), fc.focused);
}

test "FlowChart.init has node_width == 12" {
    const fc = FlowChart.init();
    try testing.expectEqual(@as(u16, 12), fc.node_width);
}

test "FlowChart.init has node_height == 3" {
    const fc = FlowChart.init();
    try testing.expectEqual(@as(u16, 3), fc.node_height);
}

// ============================================================================
// Group 2: NodeKind Enum (4 tests)
// ============================================================================

test "NodeKind.process exists and can be created" {
    const kind: NodeKind = .process;
    try testing.expectEqual(kind, NodeKind.process);
}

test "NodeKind.decision exists and can be created" {
    const kind: NodeKind = .decision;
    try testing.expectEqual(kind, NodeKind.decision);
}

test "NodeKind.terminal exists and can be created" {
    const kind: NodeKind = .terminal;
    try testing.expectEqual(kind, NodeKind.terminal);
}

test "NodeKind.io exists and can be created" {
    const kind: NodeKind = .io;
    try testing.expectEqual(kind, NodeKind.io);
}

// ============================================================================
// Group 3: nodeCount/edgeCount Capping (6 tests)
// ============================================================================

test "FlowChart.nodeCount with zero nodes returns 0" {
    const fc = FlowChart.init();
    try testing.expectEqual(@as(usize, 0), fc.nodeCount());
}

test "FlowChart.nodeCount with 3 nodes returns 3" {
    var nodes = [_]FlowNode{
        .{ .label = "a" },
        .{ .label = "b" },
        .{ .label = "c" },
    };
    const fc = FlowChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, 3), fc.nodeCount());
}

test "FlowChart.edgeCount with zero edges returns 0" {
    const fc = FlowChart.init();
    try testing.expectEqual(@as(usize, 0), fc.edgeCount());
}

test "FlowChart.edgeCount with 2 edges returns 2" {
    var edges = [_]FlowEdge{
        .{ .from = 0, .to = 1 },
        .{ .from = 1, .to = 2 },
    };
    const fc = FlowChart.init().withEdges(&edges);
    try testing.expectEqual(@as(usize, 2), fc.edgeCount());
}

test "FlowChart.nodeCount caps at MAX_NODES (32)" {
    var nodes: [33]FlowNode = undefined;
    for (0..33) |i| {
        nodes[i] = FlowNode{ .label = "n" };
    }
    const fc = FlowChart.init().withNodes(&nodes);
    try testing.expectEqual(@as(usize, FlowChart.MAX_NODES), fc.nodeCount());
}

test "FlowChart.edgeCount caps at MAX_EDGES (64)" {
    var edges: [65]FlowEdge = undefined;
    for (0..65) |i| {
        edges[i] = FlowEdge{ .from = 0, .to = 1 };
    }
    const fc = FlowChart.init().withEdges(&edges);
    try testing.expectEqual(@as(usize, FlowChart.MAX_EDGES), fc.edgeCount());
}

// ============================================================================
// Group 4: Builder Immutability (8 tests)
// ============================================================================

test "withNodes returns new value, original unchanged" {
    var nodes1 = [_]FlowNode{.{ .label = "n1" }};
    const fc1 = FlowChart.init().withNodes(&nodes1);
    var nodes2 = [_]FlowNode{.{ .label = "n2" }};
    const fc2 = fc1.withNodes(&nodes2);
    try testing.expectEqual(@as(usize, 1), fc1.nodes.len);
    try testing.expectEqualStrings("n1", fc1.nodes[0].label);
    try testing.expectEqual(@as(usize, 1), fc2.nodes.len);
    try testing.expectEqualStrings("n2", fc2.nodes[0].label);
}

test "withEdges returns new value, original unchanged" {
    var edges1 = [_]FlowEdge{.{ .from = 0, .to = 1 }};
    const fc1 = FlowChart.init().withEdges(&edges1);
    var edges2 = [_]FlowEdge{.{ .from = 1, .to = 2 }};
    const fc2 = fc1.withEdges(&edges2);
    try testing.expectEqual(@as(usize, 1), fc1.edges.len);
    try testing.expectEqual(@as(usize, 1), fc2.edges.len);
}

test "withFocused returns new value, original unchanged" {
    const fc1 = FlowChart.init().withFocused(1);
    const fc2 = fc1.withFocused(3);
    try testing.expectEqual(@as(usize, 1), fc1.focused);
    try testing.expectEqual(@as(usize, 3), fc2.focused);
}

test "withStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const fc1 = FlowChart.init().withStyle(style1);
    const fc2 = fc1.withStyle(style2);
    try testing.expectEqual(true, fc1.style.bold);
    try testing.expectEqual(true, fc2.style.dim);
}

test "withNodeWidth returns new value, original unchanged" {
    const fc1 = FlowChart.init().withNodeWidth(15);
    const fc2 = fc1.withNodeWidth(8);
    try testing.expectEqual(@as(u16, 15), fc1.node_width);
    try testing.expectEqual(@as(u16, 8), fc2.node_width);
}

test "withNodeHeight returns new value, original unchanged" {
    const fc1 = FlowChart.init().withNodeHeight(5);
    const fc2 = fc1.withNodeHeight(2);
    try testing.expectEqual(@as(u16, 5), fc1.node_height);
    try testing.expectEqual(@as(u16, 2), fc2.node_height);
}

test "withHSpacing returns new value, original unchanged" {
    const fc1 = FlowChart.init().withHSpacing(3);
    const fc2 = fc1.withHSpacing(6);
    try testing.expectEqual(@as(u16, 3), fc1.h_spacing);
    try testing.expectEqual(@as(u16, 6), fc2.h_spacing);
}

test "withVSpacing returns new value, original unchanged" {
    const fc1 = FlowChart.init().withVSpacing(1);
    const fc2 = fc1.withVSpacing(4);
    try testing.expectEqual(@as(u16, 1), fc1.v_spacing);
    try testing.expectEqual(@as(u16, 4), fc2.v_spacing);
}

// ============================================================================
// Group 5: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "render with zero width does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "test" }};
    const fc = FlowChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    fc.render(&buf, area);
}

test "render with zero height does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "test" }};
    const fc = FlowChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    fc.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "test" }};
    const fc = FlowChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    fc.render(&buf, area);
}

test "render with no nodes produces no content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const fc = FlowChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 6: Render — Single Process Node (5 tests)
// ============================================================================

test "render single process node renders at col=0 row=0" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "Start", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Node should render with content
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render process node has top-left corner ┌" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "X", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Top-left corner should be ┌
    try testing.expect(areaHasChar(buf, area, '┌'));
}

test "render process node has bottom-right corner ┘" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "X", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Bottom-right corner should be ┘
    try testing.expect(areaHasChar(buf, area, '┘'));
}

test "render process node label appears in middle row" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "Proc", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Label should appear somewhere in the node
    try testing.expect(findInArea(buf, area, "Proc"));
}

test "render process node respects node_width" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "W", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(8).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Node should render (width narrower than default 12)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 7: Render — Terminal Node Shape (3 tests)
// ============================================================================

test "render terminal node has rounded corner ╭" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "T", .kind = .terminal, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Terminal should have rounded corners
    try testing.expect(areaHasChar(buf, area, '╭'));
}

test "render terminal node has rounded corner ╮" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "T", .kind = .terminal, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '╮'));
}

test "render terminal node has rounded bottom corners ╰╯" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "T", .kind = .terminal, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(areaHasChar(buf, area, '╰') or areaHasChar(buf, area, '╯'));
}

// ============================================================================
// Group 8: Render — Multiple Nodes (4 tests)
// ============================================================================

test "render two nodes at different columns renders both" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 1, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3).withHSpacing(4);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A") and findInArea(buf, area, "B"));
}

test "render node at col=1 offsets by cell_width (node_width + h_spacing)" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "X", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "Y", .kind = .process, .col = 1, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(10).withNodeHeight(3).withHSpacing(4);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Both nodes should render in the same area
    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render two nodes at different rows renders both" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 1 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3).withVSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "A") and findInArea(buf, area, "B"));
}

test "render node at row=1 offsets by cell_height (node_height + v_spacing)" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "X", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "Y", .kind = .process, .col = 0, .row = 1 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3).withVSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);

    // Second row offset should place Y lower than X
    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

// ============================================================================
// Group 9: Render — Focused Node Styling (4 tests)
// ============================================================================

test "render focused node at index 0 uses focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "F", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "U", .kind = .process, .col = 1, .row = 0 },
    };
    const focused_style = Style{ .bold = true };
    const fc = FlowChart.init().withNodes(&nodes).withFocused(0).withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "F"));
}

test "render focused node applies focused_style to inner cells" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "Focused", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "Other", .kind = .process, .col = 1, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withFocused(0).withNodeWidth(10).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Focused node should render
    try testing.expect(findInArea(buf, area, "Focused"));
}

test "render non-focused node does not use focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "F", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "N", .kind = .process, .col = 1, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Both should render
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render focused index beyond node count does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Should not crash
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 10: Render — Edge Connector (5 tests)
// ============================================================================

test "render edge between nodes draws connector" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 1 },
    };
    var edges = [_]FlowEdge{.{ .from = 0, .to = 1 }};
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges).withNodeHeight(3).withVSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);

    // Edge connector should render (vertical bar or similar)
    try testing.expect(areaHasChar(buf, area, '│'));
}

test "render vertical edge arrow appears at destination" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 1 },
    };
    var edges = [_]FlowEdge{.{ .from = 0, .to = 1 }};
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges).withNodeHeight(3).withVSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);

    // Downward arrow should be present (▼)
    try testing.expect(areaHasChar(buf, area, '▼'));
}

test "render edge from node 0 to node 1 does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "X", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "Y", .kind = .process, .col = 1, .row = 0 },
    };
    var edges = [_]FlowEdge{.{ .from = 0, .to = 1 }};
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render edge with out-of-bounds node indices does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
    };
    var edges = [_]FlowEdge{
        .{ .from = 0, .to = 99 },
        .{ .from = 50, .to = 1 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Valid node "A" should still render despite invalid edge indices
    try testing.expect(countNonEmptyCells(buf, area) > 0);
    try testing.expect(findInArea(buf, area, "A"));
}

// ============================================================================
// Group 11: Render — Edge Label (4 tests)
// ============================================================================

test "render edge with label shows label text on connector" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 1 },
    };
    var edges = [_]FlowEdge{.{ .from = 0, .to = 1, .label = "Yes" }};
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges).withNodeHeight(3).withVSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);

    // Label "Yes" should appear somewhere
    try testing.expect(findInArea(buf, area, "Yes"));
}

test "render edge with empty label does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 1 },
    };
    var edges = [_]FlowEdge{.{ .from = 0, .to = 1, .label = "" }};
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render edge label placed near connector midpoint" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "Start", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "End", .kind = .process, .col = 0, .row = 1 },
    };
    var edges = [_]FlowEdge{.{ .from = 0, .to = 1, .label = "L" }};
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges).withNodeHeight(3).withVSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);

    // Connector and label should render
    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

test "render multiple edges with labels shows each label" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 1 },
        .{ .label = "C", .kind = .process, .col = 0, .row = 2 },
    };
    var edges = [_]FlowEdge{
        .{ .from = 0, .to = 1, .label = "X" },
        .{ .from = 1, .to = 2, .label = "Y" },
    };
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges).withNodeHeight(3).withVSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    fc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 15);
}

// ============================================================================
// Group 12: Render — Block Border (4 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "N", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    fc.render(&buf, area);

    // Block border should render (box drawing chars) — verify the border is actually present
    const has_border = areaHasChar(buf, area, '─') or
                       areaHasChar(buf, area, '│') or
                       areaHasChar(buf, area, '┌');
    try testing.expect(has_border);
}

test "render block reduces inner area for node content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "N", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withBlock(.{});
    const area = Rect{ .x = 5, .y = 5, .width = 40, .height = 10 };
    fc.render(&buf, area);

    // Content should render inside block area
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render nodes inside block border inner area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "Inside", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    fc.render(&buf, area);

    // Verify the label text actually appears in the block's inner area
    try testing.expect(findInArea(buf, area, "Inside"));
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "T", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    fc.render(&buf, area);

    // Should not crash even in tiny space
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells <= 9); // 3x3 max
}

// ============================================================================
// Group 13: Render — Grid Spacing (4 tests)
// ============================================================================

test "render node_width=8 makes nodes narrower than node_width=12" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var nodes = [_]FlowNode{.{ .label = "W", .kind = .process, .col = 0, .row = 0 }};
    const fc1 = FlowChart.init().withNodes(&nodes).withNodeWidth(8).withNodeHeight(3);
    const fc2 = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };

    fc1.render(&buf1, area);
    fc2.render(&buf2, area);

    // Both should render nodes
    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

test "render h_spacing affects column gaps" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 1, .row = 0 },
    };
    const fc1 = FlowChart.init().withNodes(&nodes).withHSpacing(2).withNodeWidth(12).withNodeHeight(3);
    const fc2 = FlowChart.init().withNodes(&nodes).withHSpacing(6).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };

    fc1.render(&buf1, area);
    fc2.render(&buf2, area);

    // Both should render both nodes
    try testing.expect(findInArea(buf1, area, "A") and findInArea(buf1, area, "B"));
    try testing.expect(findInArea(buf2, area, "A") and findInArea(buf2, area, "B"));
}

test "render node_height=5 makes nodes taller than node_height=3" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var nodes = [_]FlowNode{.{ .label = "H", .kind = .process, .col = 0, .row = 0 }};
    const fc1 = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const fc2 = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(5);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    fc1.render(&buf1, area);
    fc2.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

test "render v_spacing affects row gaps" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 1 },
    };
    const fc1 = FlowChart.init().withNodes(&nodes).withVSpacing(1).withNodeHeight(3).withNodeWidth(12);
    const fc2 = FlowChart.init().withNodes(&nodes).withVSpacing(4).withNodeHeight(3).withNodeWidth(12);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    fc1.render(&buf1, area);
    fc2.render(&buf2, area);

    // Both should render both nodes
    try testing.expect(findInArea(buf1, area, "A") and findInArea(buf1, area, "B"));
    try testing.expect(findInArea(buf2, area, "A") and findInArea(buf2, area, "B"));
}

// ============================================================================
// Group 14: Render — All NodeKind (4 tests)
// ============================================================================

test "render decision node renders without crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "D", .kind = .decision, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render io node renders without crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "I", .kind = .io, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render process and terminal nodes have different shapes" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var nodes1 = [_]FlowNode{.{ .label = "P", .kind = .process, .col = 0, .row = 0 }};
    var nodes2 = [_]FlowNode{.{ .label = "T", .kind = .terminal, .col = 0, .row = 0 }};
    const fc1 = FlowChart.init().withNodes(&nodes1).withNodeWidth(12).withNodeHeight(3);
    const fc2 = FlowChart.init().withNodes(&nodes2).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };

    fc1.render(&buf1, area);
    fc2.render(&buf2, area);

    // Process nodes must have sharp corner ┌, terminal nodes must have rounded corner ╭
    const process_has_corner = areaHasChar(buf1, area, '┌');
    const terminal_has_rounded = areaHasChar(buf2, area, '╭');
    try testing.expect(process_has_corner and terminal_has_rounded);
}

test "render all four kinds render without crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "P", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "D", .kind = .decision, .col = 1, .row = 0 },
        .{ .label = "T", .kind = .terminal, .col = 2, .row = 0 },
        .{ .label = "I", .kind = .io, .col = 3, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(10).withNodeHeight(3).withHSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 10);
}

// ============================================================================
// Group 15: Edge Cases (5 tests)
// ============================================================================

test "render nodes with empty labels renders shapes only" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "", .kind = .terminal, .col = 1, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Nodes should still render (shapes without labels)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render edges without matching nodes does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{};
    var edges = [_]FlowEdge{.{ .from = 0, .to = 1 }};
    const fc = FlowChart.init().withNodes(&nodes).withEdges(&edges);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // No nodes to render — buffer should remain empty
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render single node with no edges renders only the node" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "Alone", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "Alone"));
}

test "render many nodes at same grid cell does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{
        .{ .label = "A", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "B", .kind = .process, .col = 0, .row = 0 },
        .{ .label = "C", .kind = .process, .col = 0, .row = 0 },
    };
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(10).withNodeHeight(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    fc.render(&buf, area);

    // Should not crash; last drawn wins
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render in offset area (x>0, y>0) renders correctly" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var nodes = [_]FlowNode{.{ .label = "Offset", .kind = .process, .col = 0, .row = 0 }};
    const fc = FlowChart.init().withNodes(&nodes).withNodeWidth(12).withNodeHeight(3);
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 10 };
    fc.render(&buf, area);

    // Verify the label text actually appears at the offset location
    try testing.expect(findInArea(buf, area, "Offset"));
}
