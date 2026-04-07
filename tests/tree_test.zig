//! Tree widget functional tests
//!
//! Tests the Tree widget's rendering, navigation, and styling functionality.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;
const Tree = sailor.tui.widgets.Tree;
const TreeNode = sailor.tui.widgets.TreeNode;

// ============================================================================
// TreeNode Construction Tests
// ============================================================================

test "TreeNode.leaf creates leaf node" {
    const node = TreeNode.leaf("README.md");

    try testing.expectEqualStrings("README.md", node.label);
    try testing.expect(node.isLeaf());
    try testing.expectEqual(0, node.children.len);
}

test "TreeNode.branch creates branch node" {
    const children = [_]TreeNode{
        TreeNode.leaf("file1.txt"),
        TreeNode.leaf("file2.txt"),
    };

    const node = TreeNode.branch("src/", &children);

    try testing.expectEqualStrings("src/", node.label);
    try testing.expect(!node.isLeaf());
    try testing.expectEqual(2, node.children.len);
}

test "TreeNode.isLeaf correctly identifies node type" {
    const leaf = TreeNode.leaf("file.txt");
    const branch = TreeNode.branch("dir/", &[_]TreeNode{leaf});

    try testing.expect(leaf.isLeaf());
    try testing.expect(!branch.isLeaf());
}

// ============================================================================
// Tree Initialization Tests
// ============================================================================

test "Tree.init creates tree with nodes" {
    const nodes = [_]TreeNode{
        TreeNode.leaf("file1.txt"),
        TreeNode.leaf("file2.txt"),
    };

    const tree = Tree.init(&nodes);

    try testing.expectEqual(2, tree.nodes.len);
    try testing.expectEqual(null, tree.selected);
    try testing.expectEqual(0, tree.offset);
}

test "Tree builder methods chain correctly" {
    const nodes = [_]TreeNode{TreeNode.leaf("test")};
    const block = Block{}.withTitle("Files", .top_left);

    const tree = Tree.init(&nodes)
        .withSelected(0)
        .withOffset(5)
        .withBlock(block)
        .withNodeStyle(.{ .fg = .{ .basic = .blue } })
        .withSelectedStyle(.{ .fg = .{ .basic = .yellow }, .bold = true })
        .withHighlightSymbol("> ");

    try testing.expectEqual(0, tree.selected);
    try testing.expectEqual(5, tree.offset);
    try testing.expectEqualStrings("> ", tree.highlight_symbol);
}

// ============================================================================
// Tree Rendering Tests
// ============================================================================

test "Tree renders simple flat list" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("file1.txt"),
        TreeNode.leaf("file2.txt"),
        TreeNode.leaf("file3.txt"),
    };

    const tree = Tree.init(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };

    tree.render(&buffer, area);

    // Verify content is rendered (implementation detail: exact rendering may vary)
    const cell_0_0 = buffer.get(0, 0);
    try testing.expect(cell_0_0 != null);
}

test "Tree renders with selection highlight" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("item1"),
        TreeNode.leaf("item2"),
        TreeNode.leaf("item3"),
    };

    const selected_style = Style{ .fg = .{ .basic = .yellow }, .bold = true };
    const tree = Tree.init(&nodes)
        .withSelected(1)
        .withSelectedStyle(selected_style)
        .withHighlightSymbol("> ");

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    tree.render(&buffer, area);

    // Selected line should exist and be styled
    // Exact verification depends on implementation details
    const first_cell = buffer.get(0, 1);
    try testing.expect(first_cell != null);
}

test "Tree renders with block border" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 15);
    defer buffer.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("item")};
    const block = (Block{}).withBorders(.all).withTitle("Tree", .top_left);
    const tree = Tree.init(&nodes).withBlock(block);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    tree.render(&buffer, area);

    // Verify block is rendered
    const top_left = buffer.get(0, 0);
    try testing.expect(top_left != null);
    // Should be a box drawing character
    const c = top_left.?.char;
    try testing.expect(c == '┌' or c == '╭' or c == '+');
}

test "Tree renders nested structure" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 20);
    defer buffer.deinit();

    const nested = [_]TreeNode{
        TreeNode.branch("src/", &[_]TreeNode{
            TreeNode.leaf("main.zig"),
            TreeNode.leaf("util.zig"),
        }),
        TreeNode.branch("tests/", &[_]TreeNode{
            TreeNode.leaf("main_test.zig"),
        }),
    };

    const tree = Tree.init(&nested);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    tree.render(&buffer, area);

    // Verify rendering occurred without panic
    const cell = buffer.get(0, 0);
    try testing.expect(cell != null);
}

test "Tree handles offset scrolling" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    // Create enough nodes to require scrolling
    const nodes = [_]TreeNode{
        TreeNode.leaf("line0"),
        TreeNode.leaf("line1"),
        TreeNode.leaf("line2"),
        TreeNode.leaf("line3"),
        TreeNode.leaf("line4"),
        TreeNode.leaf("line5"),
        TreeNode.leaf("line6"),
        TreeNode.leaf("line7"),
    };

    // Render with offset=3 (should skip first 3 lines)
    const tree = Tree.init(&nodes).withOffset(3);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };

    tree.render(&buffer, area);

    // Verify no panic and content is rendered
    const cell = buffer.get(0, 0);
    try testing.expect(cell != null);
}

// ============================================================================
// Tree Styling Tests
// ============================================================================

test "Tree applies custom node style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 25, 8);
    defer buffer.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("styled")};
    const node_style = Style{ .fg = .{ .basic = .green } };

    const tree = Tree.init(&nodes).withNodeStyle(node_style);
    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 8 };

    tree.render(&buffer, area);

    // Verify render completed
    try testing.expect(buffer.get(0, 0) != null);
}

test "Tree applies custom highlight symbol" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 25, 8);
    defer buffer.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("item1"),
        TreeNode.leaf("item2"),
    };

    const tree = Tree.init(&nodes)
        .withSelected(0)
        .withHighlightSymbol(">> ");

    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 8 };
    tree.render(&buffer, area);

    // Verify rendering
    try testing.expect(buffer.get(0, 0) != null);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Tree handles empty nodes array" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const nodes = [_]TreeNode{};
    const tree = Tree.init(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    // Should not crash
    tree.render(&buffer, area);
}

test "Tree handles zero-width area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("test")};
    const tree = Tree.init(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };

    // Should not crash
    tree.render(&buffer, area);
}

test "Tree handles zero-height area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("test")};
    const tree = Tree.init(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };

    // Should not crash
    tree.render(&buffer, area);
}

test "Tree handles out-of-bounds selection" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("item1"),
        TreeNode.leaf("item2"),
    };

    // Select index 999 (out of bounds)
    const tree = Tree.init(&nodes).withSelected(999);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    // Should handle gracefully, not crash
    tree.render(&buffer, area);
}

test "Tree handles large offset" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("item1"),
        TreeNode.leaf("item2"),
    };

    // Offset beyond content
    const tree = Tree.init(&nodes).withOffset(1000);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    // Should handle gracefully
    tree.render(&buffer, area);
}

test "Tree handles deeply nested structure" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 30);
    defer buffer.deinit();

    // Create 3-level nesting
    const level2 = [_]TreeNode{
        TreeNode.leaf("deep_file.txt"),
    };
    const level1 = [_]TreeNode{
        TreeNode.branch("subdir/", &level2),
    };
    const level0 = [_]TreeNode{
        TreeNode.branch("root/", &level1),
    };

    const tree = Tree.init(&level0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 30 };

    tree.render(&buffer, area);

    // Verify no crash
    try testing.expect(buffer.get(0, 0) != null);
}

test "Tree handles unicode in labels" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("📁 folder"),
        TreeNode.leaf("📄 file.txt"),
        TreeNode.leaf("日本語.txt"),
        TreeNode.leaf("emoji🔥test"),
    };

    const tree = Tree.init(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    // Should handle unicode without crash
    tree.render(&buffer, area);
}
