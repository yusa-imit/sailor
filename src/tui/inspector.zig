//! Widget Inspector Module
//!
//! Provides runtime introspection, layout debugging, and event tracing for TUI applications.
//! All operations use writer-based output (no stdout) and follow sailor library principles.
//!
//! **v2.9.0**: Live Widget Inspector with hierarchical tree view and real-time property inspection

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const layout_mod = @import("layout.zig");
pub const Rect = layout_mod.Rect;
pub const Constraint = layout_mod.Constraint;
pub const Direction = layout_mod.Direction;

const style_mod = @import("style.zig");
pub const Style = style_mod.Style;

// ============================================================================
// v2.9.0 Live Widget Inspector API
// ============================================================================

/// Widget node in the hierarchical tree
pub const WidgetNode = struct {
    name: []const u8,           // Widget type name (e.g. "Block", "List")
    bounds: Rect,               // Current widget bounds
    style: Style,               // Current widget style
    focused: bool,              // Is this widget focused?
    memory_bytes: usize,        // Memory allocated by widget
    render_ns: u64,             // Last render time in nanoseconds
    children: []const *WidgetNode, // Child widgets
    parent: ?*WidgetNode,       // Parent widget (null for root)

    /// Calculate depth in the tree (root = 0)
    pub fn depth(self: *const WidgetNode) usize {
        var d: usize = 0;
        var current = self.parent;
        while (current) |p| {
            d += 1;
            current = p.parent;
        }
        return d;
    }

    /// Check if this is a leaf node (no children)
    pub fn isLeaf(self: *const WidgetNode) bool {
        return self.children.len == 0;
    }

    /// Find a child widget by name (first match)
    pub fn findChild(self: *const WidgetNode, name: []const u8) ?*WidgetNode {
        for (self.children) |child| {
            if (std.mem.eql(u8, child.name, name)) {
                return child;
            }
        }
        return null;
    }
};

// Internal node structure with dynamic children list
const InternalNode = struct {
    node: WidgetNode,
    children_list: ArrayList(*InternalNode),
    owned_name: []u8,
};

/// Live widget inspector with tree building and traversal
pub const WidgetInspector = struct {
    allocator: std.mem.Allocator,
    root: ?*WidgetNode,
    root_internal: ?*InternalNode, // Internal root for memory management
    current_stack: ArrayList(*InternalNode), // Stack for tree building
    focus_path_cache: ArrayList(*WidgetNode), // Cached focus path

    /// Initialize a new widget inspector
    pub fn init(allocator: std.mem.Allocator) WidgetInspector {
        return .{
            .allocator = allocator,
            .root = null,
            .root_internal = null,
            .current_stack = .{},
            .focus_path_cache = .{},
        };
    }

    /// Free all resources
    pub fn deinit(self: *WidgetInspector) void {
        if (self.root_internal) |root| {
            freeInternalNode(root, self.allocator);
        }
        self.current_stack.deinit(self.allocator);
        self.focus_path_cache.deinit(self.allocator);
    }

    // Tree building

    /// Begin recording a widget (returns node for property updates)
    pub fn beginWidget(self: *WidgetInspector, name: []const u8, bounds: Rect, style: Style) !*WidgetNode {
        // If this is a new root (stack is empty), clear the old tree first
        if (self.current_stack.items.len == 0 and self.root_internal != null) {
            freeInternalNode(self.root_internal.?, self.allocator);
            self.root = null;
            self.root_internal = null;
        }

        const internal = try self.allocator.create(InternalNode);
        errdefer self.allocator.destroy(internal);

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        internal.* = .{
            .node = .{
                .name = owned_name,
                .bounds = bounds,
                .style = style,
                .focused = false,
                .memory_bytes = 0,
                .render_ns = 0,
                .children = &[_]*WidgetNode{},
                .parent = null,
            },
            .children_list = .{},
            .owned_name = owned_name,
        };

        // If we have a current parent, add this node as a child
        if (self.current_stack.items.len > 0) {
            const parent = self.current_stack.items[self.current_stack.items.len - 1];
            internal.node.parent = &parent.node;
            try parent.children_list.append(self.allocator, internal);

            // Update parent's children slice
            const child_nodes = try self.allocator.alloc(*WidgetNode, parent.children_list.items.len);
            for (parent.children_list.items, 0..) |child, i| {
                child_nodes[i] = &child.node;
            }
            // Free old slice if it exists
            if (parent.node.children.len > 0) {
                self.allocator.free(parent.node.children);
            }
            parent.node.children = child_nodes;
        } else {
            // This is the root
            self.root = &internal.node;
            self.root_internal = internal;
        }

        // Push to stack
        try self.current_stack.append(self.allocator, internal);

        return &internal.node;
    }

    /// End the current widget (pop from stack)
    pub fn endWidget(self: *WidgetInspector) void {
        if (self.current_stack.items.len > 0) {
            _ = self.current_stack.pop();
        }
    }

    // Tree traversal

    /// Traverse the tree depth-first, calling visitor on each node
    pub fn traverse(self: *const WidgetInspector, visitor: anytype) void {
        if (self.root) |root| {
            traverseNode(root, visitor);
        }
    }

    /// Find a widget by name (first match)
    pub fn find(self: *const WidgetInspector, name: []const u8) ?*WidgetNode {
        if (self.root) |root| {
            return findInNode(root, name);
        }
        return null;
    }

    /// Get the focus path from root to focused widget
    pub fn focusPath(self: *const WidgetInspector) []const *WidgetNode {
        // Clear cache (we need mutable self but the signature is const, so we cast)
        const mutable_self = @constCast(self);
        mutable_self.focus_path_cache.clearRetainingCapacity();

        if (self.root) |root| {
            // Find the deepest focused node
            if (findFocusedNode(root)) |focused| {
                // Build path from focused to root
                var path_reversed: ArrayList(*WidgetNode) = .{};
                defer path_reversed.deinit(self.allocator);

                var current: ?*WidgetNode = focused;
                while (current) |node| {
                    path_reversed.append(self.allocator, node) catch return &[_]*WidgetNode{};
                    current = node.parent;
                }

                // Reverse to get root -> focused order
                var i: usize = path_reversed.items.len;
                while (i > 0) {
                    i -= 1;
                    mutable_self.focus_path_cache.append(self.allocator, path_reversed.items[i]) catch return &[_]*WidgetNode{};
                }
            }
        }

        return mutable_self.focus_path_cache.items;
    }

    // Statistics

    /// Calculate total memory usage of all widgets
    pub fn totalMemory(self: *const WidgetInspector) usize {
        if (self.root) |root| {
            return nodeMemory(root);
        }
        return 0;
    }

    /// Calculate total render time of all widgets
    pub fn totalRenderTime(self: *const WidgetInspector) u64 {
        if (self.root) |root| {
            return nodeRenderTime(root);
        }
        return 0;
    }

    /// Count total number of widgets (including root)
    pub fn widgetCount(self: *const WidgetInspector) usize {
        if (self.root) |root| {
            return countNodes(root);
        }
        return 0;
    }
};

// ============================================================================
// Private Helper Functions
// ============================================================================

/// Recursively free an internal node and all its children
fn freeInternalNode(internal: *InternalNode, allocator: Allocator) void {
    // Free children first
    for (internal.children_list.items) |child| {
        freeInternalNode(child, allocator);
    }

    // Free children list
    internal.children_list.deinit(allocator);

    // Free children slice
    if (internal.node.children.len > 0) {
        allocator.free(internal.node.children);
    }

    // Free owned name
    allocator.free(internal.owned_name);

    // Free node itself
    allocator.destroy(internal);
}

/// Traverse a node and its children depth-first
fn traverseNode(node: *const WidgetNode, visitor: anytype) void {
    visitor.visit(node);
    for (node.children) |child| {
        traverseNode(child, visitor);
    }
}

/// Find a node by name (depth-first search)
fn findInNode(node: *WidgetNode, name: []const u8) ?*WidgetNode {
    if (std.mem.eql(u8, node.name, name)) {
        return node;
    }
    for (node.children) |child| {
        if (findInNode(child, name)) |found| {
            return found;
        }
    }
    return null;
}

/// Find the deepest focused node (depth-first search)
fn findFocusedNode(node: *WidgetNode) ?*WidgetNode {
    // Check children first (depth-first = deeper nodes win)
    for (node.children) |child| {
        if (findFocusedNode(child)) |focused| {
            return focused;
        }
    }

    // Then check self
    if (node.focused) {
        return node;
    }

    return null;
}

/// Calculate total memory for a node and its subtree
fn nodeMemory(node: *const WidgetNode) usize {
    var total: usize = node.memory_bytes;
    for (node.children) |child| {
        total += nodeMemory(child);
    }
    return total;
}

/// Calculate total render time for a node and its subtree
fn nodeRenderTime(node: *const WidgetNode) u64 {
    var total: u64 = node.render_ns;
    for (node.children) |child| {
        total +%= nodeRenderTime(child); // Use wrapping add to handle overflow
    }
    return total;
}

/// Count nodes in a subtree (including the node itself)
fn countNodes(node: *const WidgetNode) usize {
    var count: usize = 1; // Count self
    for (node.children) |child| {
        count += countNodes(child);
    }
    return count;
}

// ============================================================================
// TESTS - v2.9.0 Live Widget Inspector
// ============================================================================

// ---------------------------------------------------------------------------
// WidgetNode Tests (~10 tests)
// ---------------------------------------------------------------------------

test "WidgetNode depth returns 0 for root node" {
    const node = WidgetNode{
        .name = "Root",
        .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    try std.testing.expectEqual(@as(usize, 0), node.depth());
}

test "WidgetNode depth returns 1 for direct child" {
    var root = WidgetNode{
        .name = "Root",
        .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    const child = WidgetNode{
        .name = "Child",
        .bounds = .{ .x = 0, .y = 0, .width = 40, .height = 12 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = &root,
    };

    try std.testing.expectEqual(@as(usize, 1), child.depth());
}

test "WidgetNode depth returns 2 for grandchild" {
    var root = WidgetNode{
        .name = "Root",
        .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    var child = WidgetNode{
        .name = "Child",
        .bounds = .{ .x = 0, .y = 0, .width = 40, .height = 12 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = &root,
    };

    const grandchild = WidgetNode{
        .name = "Grandchild",
        .bounds = .{ .x = 0, .y = 0, .width = 20, .height = 6 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = &child,
    };

    try std.testing.expectEqual(@as(usize, 2), grandchild.depth());
}

test "WidgetNode isLeaf returns true for node with no children" {
    const node = WidgetNode{
        .name = "Leaf",
        .bounds = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    try std.testing.expect(node.isLeaf());
}

test "WidgetNode isLeaf returns false for node with children" {
    var child = WidgetNode{
        .name = "Child",
        .bounds = .{ .x = 0, .y = 0, .width = 5, .height = 2 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    const child_ptr = &child;
    const node = WidgetNode{
        .name = "Parent",
        .bounds = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{child_ptr},
        .parent = null,
    };

    try std.testing.expect(!node.isLeaf());
}

test "WidgetNode findChild returns child when name matches" {
    var child1 = WidgetNode{
        .name = "Block",
        .bounds = .{ .x = 0, .y = 0, .width = 5, .height = 2 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    var child2 = WidgetNode{
        .name = "List",
        .bounds = .{ .x = 5, .y = 0, .width = 5, .height = 2 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    const child1_ptr = &child1;
    const child2_ptr = &child2;
    const parent = WidgetNode{
        .name = "Root",
        .bounds = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{child1_ptr, child2_ptr},
        .parent = null,
    };

    const found = parent.findChild("List");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("List", found.?.name);
}

test "WidgetNode findChild returns null when name not found" {
    var child = WidgetNode{
        .name = "Block",
        .bounds = .{ .x = 0, .y = 0, .width = 5, .height = 2 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    const child_ptr = &child;
    const parent = WidgetNode{
        .name = "Root",
        .bounds = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{child_ptr},
        .parent = null,
    };

    const found = parent.findChild("NotFound");
    try std.testing.expectEqual(@as(?*WidgetNode, null), found);
}

test "WidgetNode findChild returns null for node with no children" {
    const node = WidgetNode{
        .name = "Leaf",
        .bounds = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    const found = node.findChild("Any");
    try std.testing.expectEqual(@as(?*WidgetNode, null), found);
}

test "WidgetNode findChild returns first match when multiple children have same name" {
    var child1 = WidgetNode{
        .name = "Block",
        .bounds = .{ .x = 0, .y = 0, .width = 5, .height = 2 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 100,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    var child2 = WidgetNode{
        .name = "Block",
        .bounds = .{ .x = 5, .y = 0, .width = 5, .height = 2 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 200,
        .render_ns = 0,
        .children = &[_]*WidgetNode{},
        .parent = null,
    };

    const child1_ptr = &child1;
    const child2_ptr = &child2;
    const parent = WidgetNode{
        .name = "Root",
        .bounds = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = Style{},
        .focused = false,
        .memory_bytes = 0,
        .render_ns = 0,
        .children = &[_]*WidgetNode{child1_ptr, child2_ptr},
        .parent = null,
    };

    const found = parent.findChild("Block");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 100), found.?.memory_bytes);
}

// ---------------------------------------------------------------------------
// Tree Building Tests (~15 tests)
// ---------------------------------------------------------------------------

test "WidgetInspector init creates empty inspector" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    try std.testing.expectEqual(@as(?*WidgetNode, null), inspector.root);
}

test "WidgetInspector beginWidget creates root node" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const node = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});

    try std.testing.expectEqualStrings("Root", node.name);
    try std.testing.expectEqual(@as(u16, 80), node.bounds.width);
    try std.testing.expectEqual(@as(u16, 24), node.bounds.height);
}

test "WidgetInspector beginWidget sets inspector root" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});

    try std.testing.expect(inspector.root != null);
    try std.testing.expectEqualStrings("Root", inspector.root.?.name);
}

test "WidgetInspector beginWidget and endWidget basic flow" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    try std.testing.expect(inspector.root != null);
}

test "WidgetInspector nested widgets create parent-child relationship" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    try std.testing.expect(inspector.root != null);
    try std.testing.expectEqual(@as(usize, 1), inspector.root.?.children.len);
    try std.testing.expectEqualStrings("Child", inspector.root.?.children[0].name);
}

test "WidgetInspector three-level nesting" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    _ = try inspector.beginWidget("Grandchild", .{ .x = 0, .y = 0, .width = 20, .height = 6 }, Style{});
    inspector.endWidget();
    inspector.endWidget();
    inspector.endWidget();

    try std.testing.expect(inspector.root != null);
    const child = inspector.root.?.children[0];
    try std.testing.expectEqual(@as(usize, 1), child.children.len);
    try std.testing.expectEqualStrings("Grandchild", child.children[0].name);
}

test "WidgetInspector multiple children under same parent" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    _ = try inspector.beginWidget("Child2", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    _ = try inspector.beginWidget("Child3", .{ .x = 0, .y = 12, .width = 80, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 3), inspector.root.?.children.len);
    try std.testing.expectEqualStrings("Child1", inspector.root.?.children[0].name);
    try std.testing.expectEqualStrings("Child2", inspector.root.?.children[1].name);
    try std.testing.expectEqualStrings("Child3", inspector.root.?.children[2].name);
}

test "WidgetInspector endWidget without beginWidget returns error" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    // This should panic or be a no-op, but we expect it not to crash
    inspector.endWidget();

    try std.testing.expectEqual(@as(?*WidgetNode, null), inspector.root);
}

test "WidgetInspector memory tracking per widget" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const node = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    node.memory_bytes = 1024;
    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 1024), inspector.root.?.memory_bytes);
}

test "WidgetInspector render timing recording" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const node = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    node.render_ns = 1_500_000; // 1.5ms
    inspector.endWidget();

    try std.testing.expectEqual(@as(u64, 1_500_000), inspector.root.?.render_ns);
}

test "WidgetInspector focus tracking single widget" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const node = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    node.focused = true;
    inspector.endWidget();

    try std.testing.expect(inspector.root.?.focused);
}

test "WidgetInspector focus tracking nested widgets" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    const child = try inspector.beginWidget("Child", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    child.focused = true;
    inspector.endWidget();
    inspector.endWidget();

    try std.testing.expect(!inspector.root.?.focused);
    try std.testing.expect(inspector.root.?.children[0].focused);
}

test "WidgetInspector style tracking" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    var style = Style{};
    style.bold = true;
    const node = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, style);
    inspector.endWidget();

    try std.testing.expect(node.style.bold);
}

test "WidgetInspector complex tree with multiple branches" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
        _ = try inspector.beginWidget("Left", .{ .x = 0, .y = 0, .width = 40, .height = 24 }, Style{});
            _ = try inspector.beginWidget("LeftChild1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
            inspector.endWidget();
            _ = try inspector.beginWidget("LeftChild2", .{ .x = 0, .y = 12, .width = 40, .height = 12 }, Style{});
            inspector.endWidget();
        inspector.endWidget();
        _ = try inspector.beginWidget("Right", .{ .x = 40, .y = 0, .width = 40, .height = 24 }, Style{});
            _ = try inspector.beginWidget("RightChild1", .{ .x = 40, .y = 0, .width = 40, .height = 24 }, Style{});
            inspector.endWidget();
        inspector.endWidget();
    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 2), inspector.root.?.children.len);
    try std.testing.expectEqual(@as(usize, 2), inspector.root.?.children[0].children.len);
    try std.testing.expectEqual(@as(usize, 1), inspector.root.?.children[1].children.len);
}

test "WidgetInspector bounds propagation" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 10, .y = 5, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    try std.testing.expectEqual(@as(u16, 10), inspector.root.?.bounds.x);
    try std.testing.expectEqual(@as(u16, 5), inspector.root.?.bounds.y);
}

// ---------------------------------------------------------------------------
// Focus Tracking Tests (~7 tests)
// ---------------------------------------------------------------------------

test "WidgetInspector focus path with single widget" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const node = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    node.focused = true;
    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 1), path.len);
    try std.testing.expectEqualStrings("Root", path[0].name);
}

test "WidgetInspector focus path with nested focused widget" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Container", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    const leaf = try inspector.beginWidget("Input", .{ .x = 0, .y = 0, .width = 20, .height = 1 }, Style{});
    leaf.focused = true;
    inspector.endWidget();
    inspector.endWidget();
    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 3), path.len);
    try std.testing.expectEqualStrings("Root", path[0].name);
    try std.testing.expectEqualStrings("Container", path[1].name);
    try std.testing.expectEqualStrings("Input", path[2].name);
}

test "WidgetInspector focus path returns empty array when no focus" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    _ = try inspector.beginWidget("Child2", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 0), path.len);
}

test "WidgetInspector multiple focused widgets returns deepest path" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.focused = true;

    const child1 = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    child1.focused = true;

    const grandchild = try inspector.beginWidget("Grandchild", .{ .x = 0, .y = 0, .width = 20, .height = 6 }, Style{});
    grandchild.focused = true;
    inspector.endWidget();

    inspector.endWidget();

    _ = try inspector.beginWidget("Child2", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();

    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 3), path.len);
    try std.testing.expectEqualStrings("Grandchild", path[path.len - 1].name);
}

test "WidgetInspector focus tracking updates between builds" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.focused = true;
    inspector.endWidget();

    const path1 = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 1), path1.len);

    // Now focus is lost
    const root2 = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root2.focused = false;
    inspector.endWidget();

    const path2 = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 0), path2.len);
}

test "WidgetInspector focus tracking across sibling branches" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});

    _ = try inspector.beginWidget("LeftPanel", .{ .x = 0, .y = 0, .width = 40, .height = 24 }, Style{});
    _ = try inspector.beginWidget("LeftChild", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    _ = try inspector.beginWidget("RightPanel", .{ .x = 40, .y = 0, .width = 40, .height = 24 }, Style{});
    const focused = try inspector.beginWidget("RightChild", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    focused.focused = true;
    inspector.endWidget();
    inspector.endWidget();

    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 3), path.len);
    try std.testing.expectEqualStrings("Root", path[0].name);
    try std.testing.expectEqualStrings("RightPanel", path[1].name);
    try std.testing.expectEqualStrings("RightChild", path[2].name);
}

test "WidgetInspector focus tracking with dynamic tree changes" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    const old_focus = try inspector.beginWidget("OldFocus", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    old_focus.focused = true;
    inspector.endWidget();
    inspector.endWidget();

    const old_path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 2), old_path.len);
    try std.testing.expectEqualStrings("OldFocus", old_path[1].name);
}

// ---------------------------------------------------------------------------
// Tree Traversal Tests (~10 tests)
// ---------------------------------------------------------------------------

test "WidgetInspector traverse visits all nodes in depth-first order" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    _ = try inspector.beginWidget("Child2", .{ .x = 0, .y = 12, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    var visited: std.ArrayList([]const u8) = .{};
    defer visited.deinit(std.testing.allocator);

    const Visitor = struct {
        list: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        pub fn visit(self: *@This(), node: *const WidgetNode) void {
            self.list.append(self.allocator, node.name) catch unreachable;
        }
    };

    var visitor = Visitor{ .list = &visited, .allocator = std.testing.allocator };
    inspector.traverse(&visitor);

    try std.testing.expectEqual(@as(usize, 3), visited.items.len);
    try std.testing.expectEqualStrings("Root", visited.items[0]);
    try std.testing.expectEqualStrings("Child1", visited.items[1]);
    try std.testing.expectEqualStrings("Child2", visited.items[2]);
}

test "WidgetInspector traverse on empty tree does nothing" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    var visited: std.ArrayList([]const u8) = .{};
    defer visited.deinit(std.testing.allocator);

    const Visitor = struct {
        list: *std.ArrayList([]const u8),
        allocator: std.mem.Allocator,

        pub fn visit(self: *@This(), node: *const WidgetNode) void {
            self.list.append(self.allocator, node.name) catch unreachable;
        }
    };

    var visitor = Visitor{ .list = &visited, .allocator = std.testing.allocator };
    inspector.traverse(&visitor);

    try std.testing.expectEqual(@as(usize, 0), visited.items.len);
}

test "WidgetInspector find returns node when name matches" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Target", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    const found = inspector.find("Target");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("Target", found.?.name);
}

test "WidgetInspector find returns null when name not found" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    const found = inspector.find("NotFound");
    try std.testing.expectEqual(@as(?*WidgetNode, null), found);
}

test "WidgetInspector find returns null on empty tree" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const found = inspector.find("Any");
    try std.testing.expectEqual(@as(?*WidgetNode, null), found);
}

test "WidgetInspector find returns first match when multiple nodes have same name" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    const first = try inspector.beginWidget("Block", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    first.memory_bytes = 100;
    inspector.endWidget();
    const second = try inspector.beginWidget("Block", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    second.memory_bytes = 200;
    inspector.endWidget();
    inspector.endWidget();

    const found = inspector.find("Block");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 100), found.?.memory_bytes);
}

test "WidgetInspector focusPath returns path from root to focused widget" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    const grandchild = try inspector.beginWidget("Grandchild", .{ .x = 0, .y = 0, .width = 20, .height = 6 }, Style{});
    grandchild.focused = true;
    inspector.endWidget();
    inspector.endWidget();
    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 3), path.len);
    try std.testing.expectEqualStrings("Root", path[0].name);
    try std.testing.expectEqualStrings("Child", path[1].name);
    try std.testing.expectEqualStrings("Grandchild", path[2].name);
}

test "WidgetInspector focusPath returns empty when no widget is focused" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 0), path.len);
}

test "WidgetInspector focusPath returns single node when root is focused" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.focused = true;
    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 1), path.len);
    try std.testing.expectEqualStrings("Root", path[0].name);
}

test "WidgetInspector focusPath with multiple focused widgets returns last one" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.focused = true;
    const child = try inspector.beginWidget("Child", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    child.focused = true;
    inspector.endWidget();
    inspector.endWidget();

    const path = inspector.focusPath();
    try std.testing.expectEqual(@as(usize, 2), path.len);
    try std.testing.expectEqualStrings("Child", path[path.len - 1].name);
}

// ---------------------------------------------------------------------------
// Statistics Tests (~8 tests)
// ---------------------------------------------------------------------------

test "WidgetInspector totalMemory sums all widget memory" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.memory_bytes = 1024;
    const child1 = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    child1.memory_bytes = 512;
    inspector.endWidget();
    const child2 = try inspector.beginWidget("Child2", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    child2.memory_bytes = 256;
    inspector.endWidget();
    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 1792), inspector.totalMemory());
}

test "WidgetInspector totalMemory returns 0 for empty tree" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    try std.testing.expectEqual(@as(usize, 0), inspector.totalMemory());
}

test "WidgetInspector totalRenderTime sums all widget render times" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.render_ns = 1_000_000;
    const child1 = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    child1.render_ns = 500_000;
    inspector.endWidget();
    const child2 = try inspector.beginWidget("Child2", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    child2.render_ns = 250_000;
    inspector.endWidget();
    inspector.endWidget();

    try std.testing.expectEqual(@as(u64, 1_750_000), inspector.totalRenderTime());
}

test "WidgetInspector totalRenderTime returns 0 for empty tree" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    try std.testing.expectEqual(@as(u64, 0), inspector.totalRenderTime());
}

test "WidgetInspector widgetCount counts all widgets including root" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    _ = try inspector.beginWidget("Child2", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    _ = try inspector.beginWidget("Grandchild", .{ .x = 40, .y = 0, .width = 20, .height = 6 }, Style{});
    inspector.endWidget();
    inspector.endWidget();
    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 4), inspector.widgetCount());
}

test "WidgetInspector widgetCount returns 0 for empty tree" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    try std.testing.expectEqual(@as(usize, 0), inspector.widgetCount());
}

test "WidgetInspector widgetCount returns 1 for single root node" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 1), inspector.widgetCount());
}

test "WidgetInspector statistics on complex tree" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.memory_bytes = 1000;
    root.render_ns = 1_000_000;

    const child1 = try inspector.beginWidget("Child1", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    child1.memory_bytes = 500;
    child1.render_ns = 500_000;

    const gc1 = try inspector.beginWidget("Grandchild1", .{ .x = 0, .y = 0, .width = 20, .height = 6 }, Style{});
    gc1.memory_bytes = 250;
    gc1.render_ns = 250_000;
    inspector.endWidget();

    inspector.endWidget();

    const child2 = try inspector.beginWidget("Child2", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    child2.memory_bytes = 300;
    child2.render_ns = 300_000;
    inspector.endWidget();

    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 2050), inspector.totalMemory());
    try std.testing.expectEqual(@as(u64, 2_050_000), inspector.totalRenderTime());
    try std.testing.expectEqual(@as(usize, 4), inspector.widgetCount());
}

// ---------------------------------------------------------------------------
// Edge Cases (~5 tests)
// ---------------------------------------------------------------------------

test "WidgetInspector large widget tree (100+ widgets)" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});

    // Create 100 child widgets
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Child{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 1, .height = 1 }, Style{});
        inspector.endWidget();
    }

    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 101), inspector.widgetCount());
}

test "WidgetInspector Unicode widget names" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("루트", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("子ども", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    _ = try inspector.beginWidget("🎨", .{ .x = 40, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    const found1 = inspector.find("루트");
    try std.testing.expect(found1 != null);

    const found2 = inspector.find("子ども");
    try std.testing.expect(found2 != null);

    const found3 = inspector.find("🎨");
    try std.testing.expect(found3 != null);
}

test "WidgetInspector zero-size bounds" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 0, .height = 0 }, Style{});
    inspector.endWidget();

    try std.testing.expectEqual(@as(u16, 0), inspector.root.?.bounds.width);
    try std.testing.expectEqual(@as(u16, 0), inspector.root.?.bounds.height);
}

test "WidgetInspector very large render times (overflow handling)" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.render_ns = std.math.maxInt(u64) - 1000;

    const child = try inspector.beginWidget("Child", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    child.render_ns = 500;
    inspector.endWidget();
    inspector.endWidget();

    // Should not overflow
    const total = inspector.totalRenderTime();
    try std.testing.expect(total >= root.render_ns);
}

test "WidgetInspector rapid begin/end sequences" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Widget{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 10, .height = 2 }, Style{});
        inspector.endWidget();
    }

    inspector.endWidget();

    try std.testing.expectEqual(@as(usize, 11), inspector.widgetCount());
    try std.testing.expectEqual(@as(usize, 10), inspector.root.?.children.len);
}

test "WidgetInspector memory allocation tracking is accurate" {
    var inspector = WidgetInspector.init(std.testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.memory_bytes = 0; // Root has no allocation overhead

    const child = try inspector.beginWidget("Buffer", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    // Simulating a 80x24 cell buffer: 80 * 24 * sizeof(Cell) where Cell ~= 8 bytes
    child.memory_bytes = 80 * 24 * 8;
    inspector.endWidget();

    inspector.endWidget();

    const total = inspector.totalMemory();
    try std.testing.expectEqual(@as(usize, 15360), total); // 80 * 24 * 8 = 15360
}
