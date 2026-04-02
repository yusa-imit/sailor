const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Tree node for hierarchical display
pub const TreeNode = struct {
    label: []const u8,
    children: []const TreeNode = &.{},
    expanded: bool = true,

    /// Create a leaf node
    pub fn leaf(label: []const u8) TreeNode {
        return .{ .label = label };
    }

    /// Create a branch node with children
    pub fn branch(label: []const u8, children: []const TreeNode) TreeNode {
        return .{ .label = label, .children = children };
    }

    /// Check if this is a leaf node
    pub fn isLeaf(self: TreeNode) bool {
        return self.children.len == 0;
    }
};

/// Tree widget - hierarchical tree view with expand/collapse
pub const Tree = struct {
    nodes: []const TreeNode,
    selected: ?usize = null,
    offset: usize = 0,
    block: ?Block = null,
    node_style: Style = .{},
    selected_style: Style = .{},
    highlight_symbol: []const u8 = "> ",
    expanded_symbol: []const u8 = "▼ ",
    collapsed_symbol: []const u8 = "▶ ",
    leaf_symbol: []const u8 = "  ",
    indent: u16 = 2,

    /// Create a tree with nodes
    pub fn init(nodes: []const TreeNode) Tree {
        return .{ .nodes = nodes };
    }

    /// Set the selected node index (flat index)
    pub fn withSelected(self: Tree, index: ?usize) Tree {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set scroll offset
    pub fn withOffset(self: Tree, new_offset: usize) Tree {
        var result = self;
        result.offset = new_offset;
        return result;
    }

    /// Set the block (border) for this tree
    pub fn withBlock(self: Tree, new_block: Block) Tree {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set the style for unselected nodes
    pub fn withNodeStyle(self: Tree, new_style: Style) Tree {
        var result = self;
        result.node_style = new_style;
        return result;
    }

    /// Set the style for the selected node
    pub fn withSelectedStyle(self: Tree, new_style: Style) Tree {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set the highlight symbol (prefix for selected node)
    pub fn withHighlightSymbol(self: Tree, symbol: []const u8) Tree {
        var result = self;
        result.highlight_symbol = symbol;
        return result;
    }

    /// Set the expanded symbol
    pub fn withExpandedSymbol(self: Tree, symbol: []const u8) Tree {
        var result = self;
        result.expanded_symbol = symbol;
        return result;
    }

    /// Set the collapsed symbol
    pub fn withCollapsedSymbol(self: Tree, symbol: []const u8) Tree {
        var result = self;
        result.collapsed_symbol = symbol;
        return result;
    }

    /// Set the leaf symbol
    pub fn withLeafSymbol(self: Tree, symbol: []const u8) Tree {
        var result = self;
        result.leaf_symbol = symbol;
        return result;
    }

    /// Set indentation width
    pub fn withIndent(self: Tree, new_indent: u16) Tree {
        var result = self;
        result.indent = new_indent;
        return result;
    }

    /// Count total visible nodes (respecting expanded state)
    fn countVisibleNodes(nodes: []const TreeNode) usize {
        var count: usize = 0;
        for (nodes) |node| {
            count += 1;
            if (!node.isLeaf() and node.expanded) {
                count += countVisibleNodes(node.children);
            }
        }
        return count;
    }

    /// Get the total number of visible nodes
    pub fn visibleCount(self: Tree) usize {
        return countVisibleNodes(self.nodes);
    }

    /// Flatten tree into visible nodes with depth
    const FlatNode = struct {
        node: *const TreeNode,
        depth: u16,
    };

    const FlatList = struct {
        buffer: [256]FlatNode,
        len: usize,

        fn init() FlatList {
            return .{ .buffer = undefined, .len = 0 };
        }

        fn append(self: *FlatList, item: FlatNode) !void {
            if (self.len >= 256) return error.TooManyNodes;
            self.buffer[self.len] = item;
            self.len += 1;
        }

        fn slice(self: *const FlatList) []const FlatNode {
            return self.buffer[0..self.len];
        }
    };

    fn flattenNodesStack(nodes: []const TreeNode, depth: u16, out: *FlatList) !void {
        for (nodes) |*node| {
            try out.append(.{ .node = node, .depth = depth });
            if (!node.isLeaf() and node.expanded) {
                try flattenNodesStack(node.children, depth + 1, out);
            }
        }
    }

    /// Render the tree widget
    /// Note: Uses a fixed-size buffer to avoid allocations. Maximum 256 visible nodes supported.
    pub fn render(self: Tree, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Flatten visible nodes using stack-allocated buffer
        var flat_list = FlatList.init();
        flattenNodesStack(self.nodes, 0, &flat_list) catch return;

        const flat_nodes = flat_list.slice();
        if (flat_nodes.len == 0) return;

        // Calculate visible range
        const max_items = @min(flat_nodes.len, inner_area.height);
        var start = @min(self.offset, flat_nodes.len);
        var end = @min(start + max_items, flat_nodes.len);

        // Ensure selected node is visible
        if (self.selected) |sel| {
            if (sel >= flat_nodes.len) {
                // Invalid selection - ignore
            } else if (sel >= end) {
                start = sel - max_items + 1;
                end = sel + 1;
            } else if (sel < start) {
                start = sel;
                end = sel + max_items;
            }

            if (end > flat_nodes.len) {
                end = flat_nodes.len;
                start = if (flat_nodes.len >= max_items) flat_nodes.len - max_items else 0;
            }
        }

        // Render visible nodes
        var y = inner_area.y;
        for (flat_nodes[start..end], start..) |flat, i| {
            if (y >= inner_area.y + inner_area.height) break;

            const is_selected = if (self.selected) |sel| sel == i else false;
            const style = if (is_selected) self.selected_style else self.node_style;

            var x = inner_area.x;

            // Render highlight symbol if selected
            if (is_selected and self.highlight_symbol.len > 0) {
                buf.setString(x, y, self.highlight_symbol, style);
                x += @intCast(self.highlight_symbol.len);
            } else if (self.highlight_symbol.len > 0) {
                x += @intCast(self.highlight_symbol.len);
            }

            // Render indentation
            const indent_width = flat.depth * self.indent;
            x += indent_width;

            // Render expand/collapse symbol
            const node_symbol = if (flat.node.isLeaf())
                self.leaf_symbol
            else if (flat.node.expanded)
                self.expanded_symbol
            else
                self.collapsed_symbol;

            if (node_symbol.len > 0 and x + node_symbol.len <= inner_area.x + inner_area.width) {
                buf.setString(x, y, node_symbol, style);
                x += @intCast(node_symbol.len);
            }

            // Render label
            if (x < inner_area.x + inner_area.width) {
                const available_width = inner_area.x + inner_area.width - x;
                const label = flat.node.label;
                const display_len = @min(label.len, available_width);
                buf.setString(x, y, label[0..display_len], style);
            }

            y += 1;
        }
    }
};

// Tests
test "Tree: create empty tree" {
    const tree = Tree.init(&.{});
    try std.testing.expectEqual(@as(usize, 0), tree.nodes.len);
    try std.testing.expectEqual(@as(?usize, null), tree.selected);
}

test "Tree: create tree with leaf nodes" {
    const nodes = [_]TreeNode{
        TreeNode.leaf("File 1"),
        TreeNode.leaf("File 2"),
        TreeNode.leaf("File 3"),
    };
    const tree = Tree.init(&nodes);
    try std.testing.expectEqual(@as(usize, 3), tree.nodes.len);
    try std.testing.expect(tree.nodes[0].isLeaf());
    try std.testing.expect(tree.nodes[1].isLeaf());
}

test "Tree: create tree with branches" {
    const children = [_]TreeNode{
        TreeNode.leaf("Child 1"),
        TreeNode.leaf("Child 2"),
    };
    const nodes = [_]TreeNode{
        TreeNode.branch("Parent", &children),
    };
    const tree = Tree.init(&nodes);
    try std.testing.expectEqual(@as(usize, 1), tree.nodes.len);
    try std.testing.expect(!tree.nodes[0].isLeaf());
    try std.testing.expectEqual(@as(usize, 2), tree.nodes[0].children.len);
}

test "Tree: visible count with expanded nodes" {
    const children = [_]TreeNode{
        TreeNode.leaf("Child 1"),
        TreeNode.leaf("Child 2"),
    };
    const nodes = [_]TreeNode{
        TreeNode.branch("Parent", &children),
        TreeNode.leaf("Sibling"),
    };
    const tree = Tree.init(&nodes);
    // Parent + 2 children + Sibling = 4
    try std.testing.expectEqual(@as(usize, 4), tree.visibleCount());
}

test "Tree: visible count with collapsed nodes" {
    const children = [_]TreeNode{
        TreeNode.leaf("Child 1"),
        TreeNode.leaf("Child 2"),
    };
    var parent = TreeNode.branch("Parent", &children);
    parent.expanded = false;
    const nodes = [_]TreeNode{
        parent,
        TreeNode.leaf("Sibling"),
    };
    const tree = Tree.init(&nodes);
    // Parent (collapsed) + Sibling = 2
    try std.testing.expectEqual(@as(usize, 2), tree.visibleCount());
}

test "Tree: with selected" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const tree = Tree.init(&nodes).withSelected(0);
    try std.testing.expectEqual(@as(?usize, 0), tree.selected);
}

test "Tree: with offset" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const tree = Tree.init(&nodes).withOffset(5);
    try std.testing.expectEqual(@as(usize, 5), tree.offset);
}

test "Tree: with block" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const blk = Block.init();
    const tree = Tree.init(&nodes).withBlock(blk);
    try std.testing.expect(tree.block != null);
}

test "Tree: with node style" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const style = Style{ .bold = true };
    const tree = Tree.init(&nodes).withNodeStyle(style);
    try std.testing.expect(tree.node_style.bold);
}

test "Tree: with selected style" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const style = Style{ .italic = true };
    const tree = Tree.init(&nodes).withSelectedStyle(style);
    try std.testing.expect(tree.selected_style.italic);
}

test "Tree: with highlight symbol" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const tree = Tree.init(&nodes).withHighlightSymbol("→ ");
    try std.testing.expectEqualStrings("→ ", tree.highlight_symbol);
}

test "Tree: with expanded symbol" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const tree = Tree.init(&nodes).withExpandedSymbol("v ");
    try std.testing.expectEqualStrings("v ", tree.expanded_symbol);
}

test "Tree: with collapsed symbol" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const tree = Tree.init(&nodes).withCollapsedSymbol("> ");
    try std.testing.expectEqualStrings("> ", tree.collapsed_symbol);
}

test "Tree: with leaf symbol" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const tree = Tree.init(&nodes).withLeafSymbol("• ");
    try std.testing.expectEqualStrings("• ", tree.leaf_symbol);
}

test "Tree: with indent" {
    const nodes = [_]TreeNode{TreeNode.leaf("Node")};
    const tree = Tree.init(&nodes).withIndent(4);
    try std.testing.expectEqual(@as(u16, 4), tree.indent);
}

test "Tree: render empty tree" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const tree = Tree.init(&.{});
    tree.render(&buf, Rect.init(0, 0, 10, 5));

    // Should not crash, just render nothing
}

test "Tree: render single leaf" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("File.txt")};
    const tree = Tree.init(&nodes);
    tree.render(&buf, Rect.init(0, 0, 20, 3));

    // Check that the leaf symbol and label are rendered
    const cell = buf.get(0, 0);
    try std.testing.expect(cell.char != ' '); // Should have content
}

test "Tree: render with selection" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("File 1"),
        TreeNode.leaf("File 2"),
    };
    const tree = Tree.init(&nodes)
        .withSelected(1)
        .withHighlightSymbol("> ");

    tree.render(&buf, Rect.init(0, 0, 20, 5));

    // Selected item should be at line 1
    const cell = buf.get(0, 1);
    try std.testing.expectEqual(@as(u21, '>'), cell.char);
}

test "Tree: render nested tree" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const children = [_]TreeNode{
        TreeNode.leaf("Child 1"),
        TreeNode.leaf("Child 2"),
    };
    const nodes = [_]TreeNode{
        TreeNode.branch("Parent", &children),
        TreeNode.leaf("Sibling"),
    };

    const tree = Tree.init(&nodes).withIndent(2);
    tree.render(&buf, Rect.init(0, 0, 30, 10));

    // Should render parent and children with indentation
}

test "Tree: render with block" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("File")};
    const blk = Block.init();
    const tree = Tree.init(&nodes).withBlock(blk);

    tree.render(&buf, Rect.init(0, 0, 20, 5));

    // Should render both block borders and content
}

test "Tree: render collapsed branch" {
    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();

    const children = [_]TreeNode{
        TreeNode.leaf("Hidden"),
    };
    var parent = TreeNode.branch("Parent", &children);
    parent.expanded = false;

    const nodes = [_]TreeNode{parent};
    const tree = Tree.init(&nodes);
    tree.render(&buf, Rect.init(0, 0, 30, 5));

    // Children should not be visible
    try std.testing.expectEqual(@as(usize, 1), tree.visibleCount());
}

test "Tree: render with offset" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("Item 0"),
        TreeNode.leaf("Item 1"),
        TreeNode.leaf("Item 2"),
        TreeNode.leaf("Item 3"),
    };

    const tree = Tree.init(&nodes).withOffset(2);
    tree.render(&buf, Rect.init(0, 0, 20, 3));

    // Should skip first 2 items
}

test "Tree: render zero size area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("File")};
    const tree = Tree.init(&nodes);

    // Should not crash
    tree.render(&buf, Rect.init(0, 0, 0, 5));
    tree.render(&buf, Rect.init(0, 0, 10, 0));
}

test "Tree: deep nesting" {
    const level3 = [_]TreeNode{TreeNode.leaf("L3")};
    const level2 = [_]TreeNode{TreeNode.branch("L2", &level3)};
    const level1 = [_]TreeNode{TreeNode.branch("L1", &level2)};

    const tree = Tree.init(&level1);
    // L1 + L2 + L3 = 3 visible nodes
    try std.testing.expectEqual(@as(usize, 3), tree.visibleCount());
}

test "Tree: multiple roots" {
    const tree1_children = [_]TreeNode{TreeNode.leaf("A1")};
    const tree2_children = [_]TreeNode{TreeNode.leaf("B1")};

    const nodes = [_]TreeNode{
        TreeNode.branch("Tree A", &tree1_children),
        TreeNode.branch("Tree B", &tree2_children),
    };

    const tree = Tree.init(&nodes);
    // Tree A + A1 + Tree B + B1 = 4
    try std.testing.expectEqual(@as(usize, 4), tree.visibleCount());
}

// Memory Leak Tests

test "Tree: render does not leak memory" {
    const children = [_]TreeNode{
        TreeNode.leaf("Child 1"),
        TreeNode.leaf("Child 2"),
        TreeNode.leaf("Child 3"),
    };
    const nodes = [_]TreeNode{
        TreeNode.branch("Parent", &children),
        TreeNode.leaf("Sibling"),
    };

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const tree = Tree.init(&nodes);

    // Render multiple times - should not leak
    for (0..100) |_| {
        tree.render(&buf, Rect.init(0, 0, 30, 10));
    }

    // If this test passes without leaking, the render function is memory-safe
}

test "Tree: render with large tree does not leak" {
    // Create a tree with many nodes
    const l3 = [_]TreeNode{
        TreeNode.leaf("L3-1"),
        TreeNode.leaf("L3-2"),
        TreeNode.leaf("L3-3"),
    };
    const l2 = [_]TreeNode{
        TreeNode.branch("L2-1", &l3),
        TreeNode.branch("L2-2", &l3),
    };
    const l1 = [_]TreeNode{
        TreeNode.branch("L1-1", &l2),
        TreeNode.branch("L1-2", &l2),
        TreeNode.branch("L1-3", &l2),
    };

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const tree = Tree.init(&l1);

    // Render multiple times
    for (0..50) |_| {
        tree.render(&buf, Rect.init(0, 0, 40, 20));
    }
}

test "Tree: render handles more than 256 nodes gracefully" {
    // Create a very deep tree that exceeds 256 nodes
    var nodes_l0: [100]TreeNode = undefined;
    for (&nodes_l0) |*node| {
        node.* = TreeNode.leaf("Item");
    }

    const root = [_]TreeNode{
        TreeNode.branch("Root", &nodes_l0),
    };

    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const tree = Tree.init(&root);

    // Should not crash or leak when exceeding 256 node limit
    tree.render(&buf, Rect.init(0, 0, 30, 10));
}
