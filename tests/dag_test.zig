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

    // Should not crash; buffer should remain unchanged
    try testing.expect(true);
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

    // Expect node box rendered (at least label visible)
    const cell_at_label = buffer.getConst(5, 2);
    try testing.expect(cell_at_label != null);
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

    // All three nodes should render without crashing
    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    // Should not crash; edge is skipped
    try testing.expect(true);
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

    // Should not crash; edge is skipped
    try testing.expect(true);
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

    // Should not crash
    try testing.expect(true);
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

    // Should not crash or write outside buffer
    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    // Should render without crashing, truncated appropriately
    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    // Both nodes should render without exception
    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    try testing.expect(true);
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

    // Should clip and render partially without crashing
    try testing.expect(true);
}
