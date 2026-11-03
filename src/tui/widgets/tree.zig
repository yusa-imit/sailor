//! Tree widget for hierarchical, expandable/collapsible node display.
const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
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

    /// Deepest nesting level walked; nodes below it are treated as not expanded.
    const depth_max: usize = 64;

    /// Flatten tree into visible nodes with depth
    const FlatNode = struct {
        node: *const TreeNode,
        depth: u16,
    };

    const nodes_max: usize = 256;

    const FlatList = struct {
        buffer: [nodes_max]FlatNode,
        len: usize,

        fn init() FlatList {
            return .{ .buffer = undefined, .len = 0 };
        }

        /// Appends while there is room; returns false when full.
        fn append(self: *FlatList, item: FlatNode) bool {
            if (self.len >= nodes_max) return false;
            self.buffer[self.len] = item;
            self.len += 1;
            return true;
        }

        fn slice(self: *const FlatList) []const FlatNode {
            return self.buffer[0..self.len];
        }
    };

    /// Pre-order walk of the visible nodes with an explicit bounded stack (no recursion).
    /// Returns the number of visible nodes; copies the first `nodes_max` into `out` if given.
    fn walkVisible(nodes: []const TreeNode, out: ?*FlatList) usize {
        const Frame = struct { nodes: []const TreeNode, next: usize };
        var stack: [depth_max]Frame = undefined;
        var sp: usize = 1;
        stack[0] = .{ .nodes = nodes, .next = 0 };
        var count: usize = 0;
        while (sp > 0) {
            const frame = &stack[sp - 1];
            if (frame.next >= frame.nodes.len) {
                sp -= 1;
                continue;
            }
            const node = &frame.nodes[frame.next];
            frame.next += 1;
            count += 1;
            if (out) |list| _ = list.append(.{ .node = node, .depth = @intCast(sp - 1) });
            if (!node.isLeaf() and node.expanded and sp < depth_max) {
                stack[sp] = .{ .nodes = node.children, .next = 0 };
                sp += 1;
            }
        }
        std.debug.assert(sp == 0);
        std.debug.assert(out == null or out.?.len <= count);
        return count;
    }

    /// Get the total number of visible nodes
    pub fn visibleCount(self: Tree) usize {
        return walkVisible(self.nodes, null);
    }

    /// Draws `text` at (x, y), clipped to the cells left of `x_end`; returns the next column.
    fn putText(buf: *Buffer, x: u16, y: u16, x_end: u16, text: []const u8, style: Style) u16 {
        const limit: usize = x_end -| x;
        const len = UnicodeWidth.truncate(text, limit);
        const width = UnicodeWidth.stringWidth(text[0..len]);
        std.debug.assert(width <= limit);
        std.debug.assert(len <= text.len);
        buf.setString(x, y, text[0..len], style);
        return x +| @as(u16, @intCast(width));
    }

    /// Render the tree widget
    /// Note: Uses a fixed-size buffer to avoid allocations. At most 256 visible nodes are shown.
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
        _ = walkVisible(self.nodes, &flat_list);

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
        const x_end = inner_area.x +| inner_area.width;
        var y = inner_area.y;
        for (flat_nodes[start..end], start..) |flat, i| {
            if (y >= inner_area.y +| inner_area.height) break;

            const is_selected = if (self.selected) |sel| sel == i else false;
            const style = if (is_selected) self.selected_style else self.node_style;

            var x = inner_area.x;

            // Highlight symbol column is reserved on every row; drawn only when selected
            const hl_width: u16 = @intCast(@min(
                UnicodeWidth.stringWidth(self.highlight_symbol),
                std.math.maxInt(u16),
            ));
            if (is_selected) {
                x = putText(buf, x, y, x_end, self.highlight_symbol, style);
            } else {
                x +|= hl_width;
            }

            // Render indentation
            x +|= flat.depth *| self.indent;

            // Render expand/collapse symbol
            const node_symbol = if (flat.node.isLeaf())
                self.leaf_symbol
            else if (flat.node.expanded)
                self.expanded_symbol
            else
                self.collapsed_symbol;

            if (UnicodeWidth.stringWidth(node_symbol) <= x_end -| x) {
                x = putText(buf, x, y, x_end, node_symbol, style);
            }

            // Render label
            _ = putText(buf, x, y, x_end, flat.node.label, style);

            y +|= 1;
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
    const blk = (Block{});
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

fn expectRow(buf: Buffer, y: u16, expected: []const u8) !void {
    var x: u16 = 0;
    var it = (try std.unicode.Utf8View.init(expected)).iterator();
    while (it.nextCodepoint()) |cp| : (x += 1) {
        try std.testing.expectEqual(cp, buf.getChar(x, y));
    }
}

fn fillHash(buf: *Buffer) void {
    buf.fill(Rect{ .x = 0, .y = 0, .width = buf.width, .height = buf.height }, '#', .{});
}

test "Tree: render empty tree leaves buffer untouched" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    fillHash(&buf);

    const tree = Tree.init(&.{});
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });

    try expectRow(buf, 0, "##########");
    try expectRow(buf, 4, "##########");
}

test "Tree: render single leaf" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("File.txt")};
    const tree = Tree.init(&nodes);
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 3 });

    // highlight column (2) + leaf symbol (2) + label
    try expectRow(buf, 0, "    File.txt");
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(12, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
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

    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });

    try expectRow(buf, 0, "    File 1");
    try expectRow(buf, 1, ">   File 2");
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
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 10 });

    try expectRow(buf, 0, "  ▼ Parent");
    try expectRow(buf, 1, "      Child 1");
    try expectRow(buf, 2, "      Child 2");
    try expectRow(buf, 3, "    Sibling");
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 4));
}

test "Tree: render with block" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const nodes = [_]TreeNode{TreeNode.leaf("File")};
    const blk = (Block{});
    const tree = Tree.init(&nodes).withBlock(blk);

    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });

    try std.testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, '┘'), buf.getChar(19, 4));
    try std.testing.expectEqual(@as(u21, 'F'), buf.getChar(5, 1));
    try std.testing.expectEqual(@as(u21, 'e'), buf.getChar(8, 1));
    try std.testing.expectEqual(@as(u21, '│'), buf.getChar(0, 1));
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
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });

    try std.testing.expectEqual(@as(usize, 1), tree.visibleCount());
    try expectRow(buf, 0, "  ▶ Parent");
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(6, 1));
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
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 3 });

    try expectRow(buf, 0, "    Item 2");
    try expectRow(buf, 1, "    Item 3");
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(4, 2));
}

test "Tree: render zero size area leaves buffer untouched" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    fillHash(&buf);

    const nodes = [_]TreeNode{TreeNode.leaf("File")};
    const tree = Tree.init(&nodes);

    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 5 });
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 0 });

    for (0..5) |row| try expectRow(buf, @intCast(row), "##########");
}

test "Tree: label wider than area is clipped by cells (regression: byte-wise)" {
    var buf = try Buffer.init(std.testing.allocator, 12, 1);
    defer buf.deinit();
    fillHash(&buf);

    const nodes = [_]TreeNode{TreeNode.leaf("你好世界")};
    const tree = Tree.init(&nodes);
    // Area width 9: 4 cells of prefix leave 5 cells -> two wide chars, never a split one.
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 9, .height = 1 });

    try std.testing.expectEqual(@as(u21, '你'), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, '好'), buf.getChar(6, 0));
    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(8, 0));
    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(9, 0));
}

test "Tree: label clipped at area edge does not spill (regression)" {
    var buf = try Buffer.init(std.testing.allocator, 12, 1);
    defer buf.deinit();
    fillHash(&buf);

    const nodes = [_]TreeNode{TreeNode.leaf("abcdefgh")};
    Tree.init(&nodes).render(&buf, Rect{ .x = 0, .y = 0, .width = 7, .height = 1 });

    try expectRow(buf, 0, "##  abc#####");
}

test "Tree: huge indent and depth saturate (regression: u16 overflow panic)" {
    var buf = try Buffer.init(std.testing.allocator, 12, 3);
    defer buf.deinit();
    fillHash(&buf);

    const l2 = [_]TreeNode{TreeNode.leaf("c")};
    const l1 = [_]TreeNode{TreeNode.branch("b", &l2)};
    const nodes = [_]TreeNode{TreeNode.branch("a", &l1)};
    const tree = Tree.init(&nodes).withIndent(std.math.maxInt(u16));
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 12, .height = 3 });

    try expectRow(buf, 0, "##▼ a#######");
    try expectRow(buf, 1, "############");
    try expectRow(buf, 2, "############");
}

test "Tree: area at u16 max does not overflow (regression)" {
    var buf = try Buffer.init(std.testing.allocator, 6, 3);
    defer buf.deinit();
    fillHash(&buf);

    const nodes = [_]TreeNode{ TreeNode.leaf("a"), TreeNode.leaf("b") };
    const max = std.math.maxInt(u16);
    Tree.init(&nodes).render(&buf, Rect{ .x = max - 2, .y = max - 1, .width = 2, .height = 1 });

    try expectRow(buf, 0, "######");
    try expectRow(buf, 2, "######");
}

test "Tree: selection scrolls window to keep selected row visible" {
    var buf = try Buffer.init(std.testing.allocator, 12, 2);
    defer buf.deinit();

    const nodes = [_]TreeNode{
        TreeNode.leaf("n0"), TreeNode.leaf("n1"), TreeNode.leaf("n2"), TreeNode.leaf("n3"),
    };
    const tree = Tree.init(&nodes).withSelected(2);
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 12, .height = 2 });

    try expectRow(buf, 0, "    n1");
    try expectRow(buf, 1, ">   n2");
}

test "Tree: over 256 visible nodes renders first 256 (regression: rendered nothing)" {
    var items: [300]TreeNode = undefined;
    for (&items) |*node| node.* = TreeNode.leaf("Item");
    var buf = try Buffer.init(std.testing.allocator, 12, 2);
    defer buf.deinit();

    const tree = Tree.init(&items);
    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 12, .height = 2 });

    try std.testing.expectEqual(@as(usize, 300), tree.visibleCount());
    try expectRow(buf, 0, "    Item");
    try expectRow(buf, 1, "    Item");
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
        tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 10 });
    }

    try expectRow(buf, 0, "  ▼ Parent");
    try expectRow(buf, 4, "    Sibling");
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
        tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 20 });
    }
    try expectRow(buf, 0, "  ▼ L1-1");
    try expectRow(buf, 1, "    ▼ L2-1");
    try expectRow(buf, 2, "        L3-1");
    try expectRow(buf, 3, "        L3-2");
}

test "Tree: render wide branch fills the area" {
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

    tree.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 10 });
    try expectRow(buf, 0, "  ▼ Root");
    try expectRow(buf, 1, "      Item");
    try expectRow(buf, 9, "      Item");
    try std.testing.expectEqual(@as(usize, 101), tree.visibleCount());
}
