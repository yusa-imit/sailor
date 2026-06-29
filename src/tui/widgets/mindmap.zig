//! MindMap Widget — hub-and-spoke hierarchical visualization
//!
//! The MindMap widget displays a tree structure in a hub-and-spoke layout with:
//! - Root node at center
//! - Even-indexed children to the right, odd-indexed to the left
//! - Grandchildren extending further in the same direction as their parent branch
//! - Connection lines between nodes
//! - Customizable node sizing, spacing, and styling
//!
//! ## Features
//! - Hub-and-spoke layout (root center, children left/right, grandchildren further out)
//! - Alternating sides for siblings (even=right, odd=left)
//! - Connection lines with box-drawing characters
//! - Focused node highlighting
//! - Per-node styling
//! - Block border support
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var nodes = [_]MindNode{
//!     .{ .label = "Root" },
//!     .{ .label = "Right", .parent = 0 },
//!     .{ .label = "Left", .parent = 0 },
//!     .{ .label = "Grandchild", .parent = 1 },
//! };
//! var map = MindMap.init()
//!     .withNodes(&nodes)
//!     .withNodeWidth(14)
//!     .withNodeHeight(3);
//! map.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// A single node in the mind map
pub const MindNode = struct {
    label: []const u8 = "",
    parent: usize = 0, // root (idx 0): parent=0 is self-ref; others: index of parent node
    style: Style = .{},
};

/// MindMap widget for displaying hierarchical trees in hub-and-spoke layout
pub const MindMap = struct {
    /// Maximum number of nodes to display
    pub const MAX_NODES: usize = 32;

    /// Array of nodes to display
    nodes: []const MindNode = &.{},

    /// Index of the focused node
    focused: usize = 0,

    /// Base style for nodes
    style: Style = .{},

    /// Style for root node
    root_style: Style = .{},

    /// Style for focused node
    focused_style: Style = .{},

    /// Width of each node in characters
    node_width: u16 = 14,

    /// Height of each node in lines
    node_height: u16 = 3,

    /// Horizontal gap between branches
    h_gap: u16 = 2,

    /// Optional border block
    block: ?Block = null,

    /// Initialize a new MindMap with defaults
    pub fn init() MindMap {
        return .{};
    }

    /// Create a copy with different nodes
    pub fn withNodes(self: MindMap, nodes: []const MindNode) MindMap {
        var result = self;
        result.nodes = nodes;
        return result;
    }

    /// Create a copy with different focused index
    pub fn withFocused(self: MindMap, focused: usize) MindMap {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: MindMap, style: Style) MindMap {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different root style
    pub fn withRootStyle(self: MindMap, style: Style) MindMap {
        var result = self;
        result.root_style = style;
        return result;
    }

    /// Create a copy with different focused style
    pub fn withFocusedStyle(self: MindMap, style: Style) MindMap {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Create a copy with different node width
    pub fn withNodeWidth(self: MindMap, w: u16) MindMap {
        var result = self;
        result.node_width = w;
        return result;
    }

    /// Create a copy with different node height
    pub fn withNodeHeight(self: MindMap, h: u16) MindMap {
        var result = self;
        result.node_height = h;
        return result;
    }

    /// Create a copy with different horizontal gap
    pub fn withHGap(self: MindMap, gap: u16) MindMap {
        var result = self;
        result.h_gap = gap;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: MindMap, block: Block) MindMap {
        var result = self;
        result.block = block;
        return result;
    }

    /// Get the number of nodes (clamped to MAX_NODES)
    pub fn nodeCount(self: MindMap) usize {
        return @min(self.nodes.len, MAX_NODES);
    }

    /// Count children of a node (excluding self-ref for root)
    pub fn childCount(self: MindMap, parent_idx: usize) usize {
        var count: usize = 0;
        const n_count = self.nodeCount();
        var i: usize = 0;
        while (i < n_count) : (i += 1) {
            // Skip root node counting itself as a child
            if (parent_idx == 0 and i == 0) {
                continue;
            }
            if (self.nodes[i].parent == parent_idx) {
                count += 1;
            }
        }
        return count;
    }

    /// Render the mind map to the buffer
    pub fn render(self: MindMap, buf: *Buffer, area: Rect) void {
        // Early exit for zero-area
        if (area.width == 0 or area.height == 0) {
            return;
        }

        // Determine the render area (handle block border if present)
        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        // Early exit if inner area is zero
        if (inner.width == 0 or inner.height == 0) {
            return;
        }

        const node_cnt = self.nodeCount();
        if (node_cnt == 0) {
            return;
        }

        // Render root node
        renderRootNode(self, buf, inner);

        // Render branches (children of root)
        renderBranches(self, buf, inner);
    }
};

/// Render the root node centered in the inner area
fn renderRootNode(self: MindMap, buf: *Buffer, inner: Rect) void {
    const node_cnt = self.nodeCount();
    if (node_cnt == 0) return;

    const root = self.nodes[0];

    // Calculate root position (centered horizontally and vertically)
    const root_col = inner.x + (inner.width -| self.node_width) / 2;
    const root_row = inner.y + (inner.height -| self.node_height) / 2;

    // Determine style
    const is_focused = (self.focused == 0);
    const node_style = if (is_focused) self.focused_style else (if (!std.meta.eql(root.style, Style{})) root.style else self.root_style);

    // Render root node box
    renderNodeBox(buf, root_col, root_row, self.node_width, self.node_height, root.label, node_style, inner);
}

/// Render all branches (children of root and their descendants)
fn renderBranches(self: MindMap, buf: *Buffer, inner: Rect) void {
    const node_cnt = self.nodeCount();
    if (node_cnt <= 1) return;

    // Separate root children into left and right branches
    var right_children: [MindMap.MAX_NODES]usize = undefined;
    var right_count: usize = 0;
    var left_children: [MindMap.MAX_NODES]usize = undefined;
    var left_count: usize = 0;

    var i: usize = 1; // Skip root (idx 0)
    while (i < node_cnt) : (i += 1) {
        if (self.nodes[i].parent == 0) {
            // This is a child of root
            // Even index (0, 2, 4, ...) = right; Odd (1, 3, 5, ...) = left
            const child_order = if (i == 1) 0 else if (i == 2) 1 else if (i == 3) 2 else if (i == 4) 3 else (i - 1);
            if (child_order % 2 == 0) {
                right_children[right_count] = i;
                right_count += 1;
            } else {
                left_children[left_count] = i;
                left_count += 1;
            }
        }
    }

    // Get root position for reference
    const root_col = inner.x + (inner.width -| self.node_width) / 2;
    const root_row = inner.y + (inner.height -| self.node_height) / 2;

    // Render right branches
    renderBranchSide(self, buf, inner, right_children[0..right_count], root_col, root_row, true);

    // Render left branches
    renderBranchSide(self, buf, inner, left_children[0..left_count], root_col, root_row, false);
}

/// Render one side of branches (either right or left)
fn renderBranchSide(self: MindMap, buf: *Buffer, inner: Rect, branches: []usize, root_col: u16, root_row: u16, is_right: bool) void {
    if (branches.len == 0) return;

    // Calculate branch column position
    const branch_col = if (is_right)
        root_col +| self.node_width +| self.h_gap
    else if (root_col > self.h_gap + self.node_width)
        root_col -| self.h_gap -| self.node_width
    else
        0;

    // Calculate total height needed for all branches
    const branch_count = @as(u16, @intCast(branches.len));
    const total_h = branch_count * self.node_height + @max(0, (branch_count -| 1)) * 1; // 1 row gap between nodes

    // Calculate starting row (centered around root row)
    const start_row: u16 = if (total_h > 0 and root_row > total_h / 2)
        root_row +| self.node_height / 2 -| total_h / 2
    else
        root_row;

    // Render each branch and its children
    for (branches, 0..) |branch_idx, order| {
        const branch_row: u16 = start_row + @as(u16, @intCast(order)) * (self.node_height + 1);
        const branch = self.nodes[branch_idx];

        // Draw connection line from root to branch
        drawConnectionLine(buf, root_col, root_row, branch_col, branch_row, self.node_width, self.node_height, is_right, inner);

        // Determine style
        const is_focused = (self.focused == branch_idx);
        const node_style = if (is_focused) self.focused_style else (if (!std.meta.eql(branch.style, Style{})) branch.style else self.style);

        // Render branch node box
        renderNodeBox(buf, branch_col, branch_row, self.node_width, self.node_height, branch.label, node_style, inner);

        // Render grandchildren of this branch
        renderGrandchildren(self, buf, inner, branch_idx, branch_col, branch_row, is_right);
    }
}

/// Render grandchildren of a branch node
fn renderGrandchildren(self: MindMap, buf: *Buffer, inner: Rect, parent_idx: usize, parent_col: u16, parent_row: u16, is_right: bool) void {
    const node_cnt = self.nodeCount();

    // Find all grandchildren of this parent
    var grandchildren: [MindMap.MAX_NODES]usize = undefined;
    var gc_count: usize = 0;

    var i: usize = 0;
    while (i < node_cnt) : (i += 1) {
        if (self.nodes[i].parent == parent_idx) {
            grandchildren[gc_count] = i;
            gc_count += 1;
        }
    }

    if (gc_count == 0) return;

    // Calculate grandchild column (further out in same direction as parent)
    const gc_col = if (is_right)
        parent_col +| self.node_width +| self.h_gap
    else if (parent_col > self.h_gap + self.node_width)
        parent_col -| self.h_gap -| self.node_width
    else
        0;

    // Calculate total height needed for grandchildren
    const gc_count_u16 = @as(u16, @intCast(gc_count));
    const total_h = gc_count_u16 * self.node_height + @max(0, (gc_count_u16 -| 1)) * 1;

    // Calculate starting row (centered around parent row)
    const start_row: u16 = if (total_h > 0 and parent_row > total_h / 2)
        parent_row +| self.node_height / 2 -| total_h / 2
    else
        parent_row;

    // Render each grandchild
    for (grandchildren[0..gc_count], 0..) |gc_idx, order| {
        const gc_row: u16 = start_row + @as(u16, @intCast(order)) * (self.node_height + 1);
        const gc_node = self.nodes[gc_idx];

        // Draw connection line from parent to grandchild
        drawConnectionLine(buf, parent_col, parent_row, gc_col, gc_row, self.node_width, self.node_height, is_right, inner);

        // Determine style
        const is_focused = (self.focused == gc_idx);
        const node_style = if (is_focused) self.focused_style else (if (!std.meta.eql(gc_node.style, Style{})) gc_node.style else self.style);

        // Render grandchild node box
        renderNodeBox(buf, gc_col, gc_row, self.node_width, self.node_height, gc_node.label, node_style, inner);

        // Recursively render great-grandchildren
        renderGrandchildren(self, buf, inner, gc_idx, gc_col, gc_row, is_right);
    }
}

/// Draw a connection line between two nodes
fn drawConnectionLine(buf: *Buffer, from_col: u16, from_row: u16, to_col: u16, to_row: u16, node_width: u16, node_height: u16, is_right: bool, inner: Rect) void {
    const from_center_y = from_row +| node_height / 2;
    _ = to_row; // Not used in current implementation

    if (is_right) {
        // Right connection: from right edge of 'from' to left edge of 'to'
        const line_start_x = from_col +| node_width;
        const line_end_x = to_col;

        if (line_start_x < line_end_x) {
            // Draw horizontal line
            var x = line_start_x;
            while (x <= line_end_x and x < inner.x + inner.width) : (x += 1) {
                setCell(buf, inner, x, from_center_y, 0x2500, .{}); // ─
            }
        }
    } else {
        // Left connection: from left edge of 'from' to right edge of 'to'
        const line_start_x = from_col;
        const line_end_x = to_col +| node_width;

        if (line_end_x < line_start_x) {
            // Draw horizontal line
            var x = line_end_x;
            while (x <= line_start_x and x < inner.x + inner.width) : (x += 1) {
                setCell(buf, inner, x, from_center_y, 0x2500, .{}); // ─
            }
        }
    }
}

/// Render a single node box with border and label
fn renderNodeBox(buf: *Buffer, col: u16, row: u16, width: u16, height: u16, label: []const u8, style: Style, inner: Rect) void {
    if (width < 2 or height < 1) return;

    // Top-left corner
    setCell(buf, inner, col, row, 0x250C, style); // ┌

    // Top border
    var x: u16 = 1;
    while (x < width - 1) : (x += 1) {
        setCell(buf, inner, col +| x, row, 0x2500, style); // ─
    }

    // Top-right corner
    setCell(buf, inner, col +| width - 1, row, 0x2510, style); // ┐

    // Middle rows with label
    var y: u16 = 1;
    while (y < height) : (y += 1) {
        // Left border
        setCell(buf, inner, col, row +| y, 0x2502, style); // │

        // Label on middle row
        if (y == height / 2) {
            renderLabelCentered(buf, col +| 1, row +| y, width - 2, label, style, inner);
        }

        // Right border
        setCell(buf, inner, col +| width - 1, row +| y, 0x2502, style); // │
    }

    // Bottom border
    var bx: u16 = 1;
    while (bx < width - 1) : (bx += 1) {
        setCell(buf, inner, col +| bx, row +| height - 1, 0x2500, style); // ─
    }

    // Bottom-left corner
    setCell(buf, inner, col, row +| height - 1, 0x2514, style); // └

    // Bottom-right corner
    setCell(buf, inner, col +| width - 1, row +| height - 1, 0x2518, style); // ┘
}

/// Render label centered in a region
fn renderLabelCentered(buf: *Buffer, start_x: u16, y: u16, available_width: u16, label: []const u8, style: Style, inner: Rect) void {
    if (available_width == 0 or label.len == 0) return;

    // Truncate label if too long
    var label_len = label.len;
    if (label_len > available_width) {
        label_len = available_width;
    }

    // Calculate padding to center
    const total_padding = available_width -| label_len;
    const left_padding = total_padding / 2;

    // Render spaces before label
    var x: u16 = 0;
    while (x < left_padding) : (x += 1) {
        setCell(buf, inner, start_x +| x, y, ' ', style);
    }

    // Render label
    var idx: u16 = 0;
    while (idx < label_len) : ({
        x += 1;
        idx += 1;
    }) {
        setCell(buf, inner, start_x +| x, y, label[idx], style);
    }

    // Render spaces after label
    while (x < available_width) : (x += 1) {
        setCell(buf, inner, start_x +| x, y, ' ', style);
    }
}

/// Helper to set a cell with bounds checking
fn setCell(buf: *Buffer, area: Rect, x: u16, y: u16, char: u21, style: Style) void {
    if (x < area.x or y < area.y or x >= area.x + area.width or y >= area.y + area.height) return;
    buf.set(x, y, Cell.init(char, style));
}
