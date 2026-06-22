//! DagWidget tests — v2.15.0
//!
//! Tests the DagWidget's node rendering, edge drawing, and layout functionality.
//! DagWidget visualizes a directed acyclic graph (dependency graph) with nodes as boxes
//! and edges as connecting lines.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

// These will be defined when the widgets are implemented
const DagWidget = sailor.tui.widgets.DagWidget;
const Node = DagWidget.Node;
const Edge = DagWidget.Edge;

// ============================================================================
// Node Construction Tests
// ============================================================================

test "Node creation with default values" {
    const node = Node{
        .id = 0,
        .label = "test",
        .x = 5,
        .y = 3,
    };

    try testing.expectEqual(@as(usize, 0), node.id);
    try testing.expectEqualStrings("test", node.label);
    try testing.expectEqual(@as(u16, 5), node.x);
    try testing.expectEqual(@as(u16, 3), node.y);
    try testing.expectEqual(@as(u16, 0), node.width); // auto
    try testing.expectEqual(@as(u16, 3), node.height); // default
    try testing.expect(!node.selected);
}

test "Node creation with custom dimensions" {
    const node = Node{
        .id = 1,
        .label = "custom",
        .x = 10,
        .y = 5,
        .width = 15,
        .height = 5,
    };

    try testing.expectEqual(@as(u16, 15), node.width);
    try testing.expectEqual(@as(u16, 5), node.height);
}

test "Node with selected flag" {
    const node = Node{
        .id = 0,
        .label = "selected",
        .x = 0,
        .y = 0,
        .selected = true,
    };

    try testing.expect(node.selected);
}

// ============================================================================
// Edge Construction Tests
// ============================================================================

test "Edge creation with required fields" {
    const edge = Edge{
        .from_id = 0,
        .to_id = 1,
    };

    try testing.expectEqual(@as(usize, 0), edge.from_id);
    try testing.expectEqual(@as(usize, 1), edge.to_id);
    try testing.expect(edge.label == null);
}

test "Edge creation with label" {
    const edge = Edge{
        .from_id = 0,
        .to_id = 1,
        .label = "depends on",
    };

    try testing.expectEqualStrings("depends on", edge.label.?);
}

// ============================================================================
// DagWidget Initialization Tests
// ============================================================================

test "DagWidget with empty nodes renders without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{};
    const edges = [_]Edge{};

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Buffer should remain empty (all spaces) when there are no nodes
    const cell_at_origin = buffer.getConst(0, 0);
    try testing.expect(cell_at_origin == null or cell_at_origin.?.char == ' ');
}

test "DagWidget with empty edges renders nodes only" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "task",
            .x = 5,
            .y = 2,
        },
    };
    const edges = [_]Edge{};

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Expect node top-left corner (┌) at node position
    const cell_at_label = buffer.getConst(5, 2);
    try testing.expect(cell_at_label != null);
    try testing.expectEqual(@as(u21, '┌'), cell_at_label.?.char);
}

// ============================================================================
// nodeAt() Tests
// ============================================================================

test "nodeAt returns correct node by id" {
    const nodes = [_]Node{
        Node{ .id = 0, .label = "first", .x = 0, .y = 0 },
        Node{ .id = 1, .label = "second", .x = 10, .y = 0 },
        Node{ .id = 2, .label = "third", .x = 20, .y = 0 },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const found = dag.nodeAt(1);
    try testing.expect(found != null);
    try testing.expectEqualStrings("second", found.?.label);
}

test "nodeAt returns null for unknown id" {
    const nodes = [_]Node{
        Node{ .id = 0, .label = "first", .x = 0, .y = 0 },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const found = dag.nodeAt(99);
    try testing.expect(found == null);
}

test "nodeAt on empty nodes returns null" {
    const dag = DagWidget{
        .nodes = &[_]Node{},
        .edges = &[_]Edge{},
    };

    const found = dag.nodeAt(0);
    try testing.expect(found == null);
}

// ============================================================================
// nodeBox() Tests
// ============================================================================

test "nodeBox returns correct position and auto width" {
    const node = Node{
        .id = 0,
        .label = "task",
        .x = 5,
        .y = 3,
        .width = 0, // auto
    };

    const box = DagWidget.nodeBox(node);

    try testing.expectEqual(@as(u16, 5), box.x);
    try testing.expectEqual(@as(u16, 3), box.y);
    // Width should be label.len + 2 (for borders)
    try testing.expectEqual(@as(u16, 6), box.width);
    try testing.expectEqual(@as(u16, 3), box.height);
}

test "nodeBox returns explicit dimensions when set" {
    const node = Node{
        .id = 0,
        .label = "task",
        .x = 10,
        .y = 5,
        .width = 20,
        .height = 7,
    };

    const box = DagWidget.nodeBox(node);

    try testing.expectEqual(@as(u16, 10), box.x);
    try testing.expectEqual(@as(u16, 5), box.y);
    try testing.expectEqual(@as(u16, 20), box.width);
    try testing.expectEqual(@as(u16, 7), box.height);
}

test "nodeBox with empty label has minimum width" {
    const node = Node{
        .id = 0,
        .label = "",
        .x = 0,
        .y = 0,
        .width = 0, // auto
    };

    const box = DagWidget.nodeBox(node);

    // Minimum width should be at least 2 (for borders)
    try testing.expect(box.width >= 2);
}

// ============================================================================
// Single Node Rendering Tests
// ============================================================================

test "single node renders label visible in buffer" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Build",
            .x = 5,
            .y = 2,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Check that the label is present somewhere in the box
    var found_label = false;
    var y: u16 = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 5;
        while (x < 15) : (x += 1) {
            if (buffer.getConst(x, y)) |cell| {
                if (cell.char == 'B' or cell.char == 'u' or cell.char == 'i') {
                    found_label = true;
                }
            }
        }
    }

    try testing.expect(found_label);
}

// ============================================================================
// Multiple Node Rendering Tests
// ============================================================================

test "multiple nodes render all labels without overlap" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "A",
            .x = 0,
            .y = 0,
        },
        Node{
            .id = 1,
            .label = "B",
            .x = 10,
            .y = 0,
        },
        Node{
            .id = 2,
            .label = "C",
            .x = 20,
            .y = 0,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // All three nodes should render at their positions: top-left corners (┌)
    const cell_0 = buffer.getConst(0, 0);
    const cell_1 = buffer.getConst(10, 0);
    const cell_2 = buffer.getConst(20, 0);
    try testing.expectEqual(@as(u21, '┌'), cell_0.?.char);
    try testing.expectEqual(@as(u21, '┌'), cell_1.?.char);
    try testing.expectEqual(@as(u21, '┌'), cell_2.?.char);
}

// ============================================================================
// Edge Rendering Tests
// ============================================================================

test "edge between two nodes renders without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Start",
            .x = 5,
            .y = 3,
        },
        Node{
            .id = 1,
            .label = "End",
            .x = 25,
            .y = 3,
        },
    };

    const edges = [_]Edge{
        Edge{
            .from_id = 0,
            .to_id = 1,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Edge should be drawn between nodes; check for dash or arrow char on the edge line
    // From node ends at x=5+5=10, to node starts at x=25. Edge should be at mid-height (y=3 + height/2 = 3 + 1 = 4)
    const edge_cell = buffer.getConst(15, 4);
    try testing.expect(edge_cell != null and (edge_cell.?.char == '-' or edge_cell.?.char == '>'));
}

test "multiple edges from same source render without overlap" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Source",
            .x = 5,
            .y = 5,
        },
        Node{
            .id = 1,
            .label = "Target1",
            .x = 20,
            .y = 2,
        },
        Node{
            .id = 2,
            .label = "Target2",
            .x = 20,
            .y = 8,
        },
    };

    const edges = [_]Edge{
        Edge{ .from_id = 0, .to_id = 1 },
        Edge{ .from_id = 0, .to_id = 2 },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node 0 ends at x=5+8=13, nodes 1&2 start at x=20.
    // Edges drawn from x=13 to x=19 at their respective heights
    // Edge to node 1: at y = 2+1 = 3
    // Edge to node 2: at y = 8+1 = 9
    // Check both edges have some content
    var found_edge = false;
    var y: u16 = 0;
    while (y < 24) : (y += 1) {
        var x: u16 = 13;
        while (x < 20) : (x += 1) {
            if (buffer.getConst(x, y)) |cell| {
                if (cell.char == '-' or cell.char == '>' or cell.char == '|') {
                    found_edge = true;
                }
            }
        }
    }
    try testing.expect(found_edge);
}

// ============================================================================
// Edge Error Path Tests
// ============================================================================

test "edge with unknown from_id is ignored safely" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Node",
            .x = 5,
            .y = 3,
        },
    };

    const edges = [_]Edge{
        Edge{
            .from_id = 99,
            .to_id = 0,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node should still render, but no edge line (from_id doesn't exist)
    const node_cell = buffer.getConst(5, 3);
    try testing.expectEqual(@as(u21, '┌'), node_cell.?.char);
    // No edge should be drawn (from_id=99 doesn't exist)
}

test "edge with unknown to_id is ignored safely" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Node",
            .x = 5,
            .y = 3,
        },
    };

    const edges = [_]Edge{
        Edge{
            .from_id = 0,
            .to_id = 99,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node should still render, but no edge line (to_id doesn't exist)
    const node_cell = buffer.getConst(5, 3);
    try testing.expectEqual(@as(u21, '┌'), node_cell.?.char);
    // No edge should be drawn (to_id=99 doesn't exist)
}

test "edge to self does not crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Node",
            .x = 5,
            .y = 3,
        },
    };

    const edges = [_]Edge{
        Edge{
            .from_id = 0,
            .to_id = 0,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node should render, self-loop is skipped (renderEdge returns early for self-edges)
    const node_cell = buffer.getConst(5, 3);
    try testing.expectEqual(@as(u21, '┌'), node_cell.?.char);
}

// ============================================================================
// Area Boundary Tests
// ============================================================================

test "node outside render area is clipped safely" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "OffScreen",
            .x = 100,
            .y = 50,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node is completely outside area (x=100 > area.width=80), so nothing should be rendered
    const cell_at_area_edge = buffer.getConst(79, 23);
    try testing.expect(cell_at_area_edge == null or cell_at_area_edge.?.char == ' ');
}

test "zero width area does not panic" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Node",
            .x = 5,
            .y = 3,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 10, .y = 0, .width = 0, .height = 24 };
    dag.render(&buffer, area);

    // Render should return early (area.width == 0); nothing should be drawn in buffer
    const cell_at_10_3 = buffer.getConst(10, 3);
    try testing.expect(cell_at_10_3 == null or cell_at_10_3.?.char == ' ');
}

test "zero height area does not panic" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Node",
            .x = 5,
            .y = 3,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 10, .width = 80, .height = 0 };
    dag.render(&buffer, area);

    // Render should return early (area.height == 0); nothing should be drawn
    const cell_at_5_3 = buffer.getConst(5, 3);
    try testing.expect(cell_at_5_3 == null or cell_at_5_3.?.char == ' ');
}

// ============================================================================
// Node Label Tests
// ============================================================================

test "node with empty label renders box correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "",
            .x = 5,
            .y = 3,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Empty label should still render box borders (minimum width = 2)
    const top_left = buffer.getConst(5, 3);
    try testing.expectEqual(@as(u21, '┌'), top_left.?.char);
    const top_right = buffer.getConst(6, 3); // width = max(2, 0 + 2) = 2, so right border at 5+2-1 = 6
    try testing.expectEqual(@as(u21, '┐'), top_right.?.char);
}

test "node with very long label is truncated to area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "This is a very very very very long label that should be truncated",
            .x = 0,
            .y = 0,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    dag.render(&buffer, area);

    // Box should render with top-left corner, truncated to area.width=20
    const top_left = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, '┌'), top_left.?.char);
    // Label should be truncated; at most 20 chars total including borders
    const label_first_char = buffer.getConst(1, 0); // Label starts at x=1 (after left border)
    try testing.expect(label_first_char != null);
}

test "node with single character label" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "X",
            .x = 5,
            .y = 5,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Box width = max(2, 1 + 2) = 3. Top-left at (5,5), label 'X' should appear at inner position
    const top_left = buffer.getConst(5, 5);
    try testing.expectEqual(@as(u21, '┌'), top_left.?.char);
    const label_cell = buffer.getConst(6, 5); // Label at x = 5 + 1 = 6
    try testing.expectEqual(@as(u21, 'X'), label_cell.?.char);
}

// ============================================================================
// Style Tests
// ============================================================================

test "selected node uses selected_style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const selected_style = Style{
        .fg = Color.reset,
        .bg = Color.reset,
        .bold = true,
    };

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Selected",
            .x = 5,
            .y = 3,
            .selected = true,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
        .selected_style = selected_style,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node should render with selected_style applied (bold = true)
    const top_left = buffer.getConst(5, 3);
    try testing.expectEqual(@as(u21, '┌'), top_left.?.char);
    // The style should be applied to the cell
    try testing.expectEqual(true, top_left.?.style.bold);
}

test "default styles are zero-value" {
    const dag = DagWidget{
        .nodes = &[_]Node{},
        .edges = &[_]Edge{},
    };

    // node_style and selected_style should use default Style{}
    const default_style = Style{};
    try testing.expectEqual(dag.node_style.bold, default_style.bold);
}

// ============================================================================
// Large Graph Tests
// ============================================================================

test "large graph with 10 nodes renders without panic" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    var nodes: [10]Node = undefined;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        nodes[i] = Node{
            .id = i,
            .label = "N",
            .x = @intCast(i % 4 * 15),
            .y = @intCast(i / 4 * 5),
        };
    }

    var edges: [20]Edge = undefined;
    var j: usize = 0;
    while (j < 9) : (j += 1) {
        edges[j] = Edge{
            .from_id = j,
            .to_id = j + 1,
        };
    }

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = edges[0..9],
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // First node at (0, 0), second at (15, 0), etc. All should render their top-left corners
    const node0_cell = buffer.getConst(0, 0);
    const node1_cell = buffer.getConst(15, 0);
    try testing.expectEqual(@as(u21, '┌'), node0_cell.?.char);
    try testing.expectEqual(@as(u21, '┌'), node1_cell.?.char);
}

// ============================================================================
// Edge Positioning Tests
// ============================================================================

test "edge at mid-height of source node renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "A",
            .x = 5,
            .y = 3,
            .height = 5,
        },
        Node{
            .id = 1,
            .label = "B",
            .x = 25,
            .y = 3,
        },
    };

    const edges = [_]Edge{
        Edge{ .from_id = 0, .to_id = 1 },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // From node: height=5, so mid_y = 3 + 5/2 = 3 + 2 = 5
    // To node: height=3, so mid_y = 3 + 3/2 = 3 + 1 = 4
    // Edge from (5+3, 5) to (25, 4) should have horizontal and vertical segments
    // Vertical connector at to_node's left should be at x=24, with vertical line from y=4 to y=5
    const edge_vertical = buffer.getConst(24, 5); // Vertical line going down from edge_y=5 to to_y=4
    try testing.expect(edge_vertical != null and (edge_vertical.?.char == '|' or edge_vertical.?.char == '-' or edge_vertical.?.char == '>'));
}

// ============================================================================
// Adjacent Node Tests
// ============================================================================

test "two adjacent nodes do not overwrite each other's borders" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "A",
            .x = 0,
            .y = 0,
            .width = 8,
        },
        Node{
            .id = 1,
            .label = "B",
            .x = 8,
            .y = 0,
            .width = 8,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node 0: x=0, width=8, right border at x=7 (┐)
    // Node 1: x=8, width=8, left border at x=8 (┌)
    const node0_right = buffer.getConst(7, 0);
    const node1_left = buffer.getConst(8, 0);
    try testing.expectEqual(@as(u21, '┐'), node0_right.?.char);
    try testing.expectEqual(@as(u21, '┌'), node1_left.?.char);
}

// ============================================================================
// Node Height Tests
// ============================================================================

test "nodeBox height matches node.height" {
    const node = Node{
        .id = 0,
        .label = "task",
        .x = 0,
        .y = 0,
        .height = 7,
    };

    const box = DagWidget.nodeBox(node);

    try testing.expectEqual(@as(u16, 7), box.height);
}

test "node with custom height renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Tall",
            .x = 5,
            .y = 2,
            .height = 10,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node top at y=2, bottom at y=2+10-1=11
    const top_row = buffer.getConst(5, 2);
    const middle_row = buffer.getConst(5, 5); // Middle row should have '│'
    const bottom_row = buffer.getConst(5, 11);
    try testing.expectEqual(@as(u21, '┌'), top_row.?.char);
    try testing.expectEqual(@as(u21, '│'), middle_row.?.char);
    try testing.expectEqual(@as(u21, '└'), bottom_row.?.char);
}

// ============================================================================
// Edge Label Tests
// ============================================================================

test "edge with label renders without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "A",
            .x = 5,
            .y = 5,
        },
        Node{
            .id = 1,
            .label = "B",
            .x = 25,
            .y = 5,
        },
    };

    const edges = [_]Edge{
        Edge{
            .from_id = 0,
            .to_id = 1,
            .label = "depends",
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Edge should render with label. Edge at y=6 (5 + 3/2 = 5 + 1 = 6), label at y=5 (edge_y - 1)
    // Label starts at mid_x = (5+3) + (25-8)/2 ≈ 8 + 8.5 ≈ 16
    const label_cell = buffer.getConst(16, 5);
    try testing.expect(label_cell != null and label_cell.?.char == 'd'); // First char of "depends"
}

// ============================================================================
// Custom Characters Tests
// ============================================================================

test "DagWidget with custom edge_char renders edges" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{ .id = 0, .label = "A", .x = 5, .y = 3 },
        Node{ .id = 1, .label = "B", .x = 25, .y = 3 },
    };

    const edges = [_]Edge{
        Edge{ .from_id = 0, .to_id = 1 },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &edges,
        .edge_char = '=',
        .arrow_char = '>',
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Edge should use '=' for horizontal line and '>' for arrow
    const edge_mid = buffer.getConst(15, 4); // Middle of edge
    const edge_end = buffer.getConst(24, 4); // Near end of edge (arrow position at to_left_x - 1 = 24)
    try testing.expect(edge_mid != null and edge_mid.?.char == '=');
    try testing.expect(edge_end != null and edge_end.?.char == '>');
}

// ============================================================================
// Node at Boundary Tests
// ============================================================================

test "node at render area boundary renders partially without panic" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const nodes = [_]Node{
        Node{
            .id = 0,
            .label = "Edge",
            .x = 75,
            .y = 20,
            .width = 10,
            .height = 10,
        },
    };

    const dag = DagWidget{
        .nodes = &nodes,
        .edges = &[_]Edge{},
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    dag.render(&buffer, area);

    // Node partially overlaps boundary (x starts at 75, area ends at 80). Should render what fits.
    // Top-left should be at x=75, y=20
    const top_left = buffer.getConst(75, 20);
    try testing.expect(top_left != null and top_left.?.char == '┌');
}
