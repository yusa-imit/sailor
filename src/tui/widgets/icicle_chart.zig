//! IcicleChart Widget — Rectangular hierarchical chart
//!
//! The IcicleChart widget displays hierarchical tree data as stacked horizontal
//! bands arranged from top to bottom. Each row (depth level) contains bands for
//! nodes at that tree depth. Within a parent's column span, children divide the
//! width proportionally to their values using a cumulative-floor formula.
//!
//! ## Features
//! - Up to MAX_DEPTH=6 rows (tree levels)
//! - Up to MAX_CHILDREN_PER_NODE=8 children per node
//! - Single root node tree (unlike SunburstChart's multiple nodes)
//! - Rectangular band layout (alternative to radial SunburstChart)
//! - Hierarchical tree rendering with automatic depth capping
//! - Focused path highlighting
//! - Optional labels and values
//! - Per-node styling
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! var children = [_]IcicleNode{
//!     .{ .label = "A", .value = 10.0 },
//!     .{ .label = "B", .value = 20.0 },
//! };
//! var root = IcicleNode{ .label = "Root", .value = 30.0, .children = &children };
//!
//! const chart = IcicleChart.init()
//!     .withRoot(root)
//!     .withShowLabels(true)
//!     .withShowValues(false);
//!
//! chart.render(&buf, area);
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

/// A node in the icicle tree hierarchy
pub const IcicleNode = struct {
    /// Label for the node
    label: []const u8 = "",
    /// Value (hierarchical weight; positive values contribute to span proportion)
    value: f32 = 0.0,
    /// Child nodes (empty for leaf nodes)
    children: []const IcicleNode = &.{},
    /// Optional custom style for this node
    style: Style = .{},
};

pub const IcicleChart = struct {
    /// Maximum tree depth (number of rows)
    pub const MAX_DEPTH: usize = 6;
    /// Maximum children per node
    pub const MAX_CHILDREN_PER_NODE: usize = 8;

    /// Single root node of the hierarchy (null for empty chart)
    root: ?IcicleNode = null,
    /// Path to focused node as root-relative child indices (e.g., &.{0, 2})
    /// Empty slice means nothing focused
    focused: []const usize = &.{},
    /// Whether to render node labels
    show_labels: bool = true,
    /// Whether to render node values (as percentages of parent's total)
    show_values: bool = false,
    /// Base style applied to widget
    style: Style = .{},
    /// Style for the focused node's branch
    focused_style: Style = .{},
    /// Style for labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize an IcicleChart with all defaults
    pub fn init() IcicleChart {
        return .{};
    }

    /// Count total nodes in the tree, respecting MAX_DEPTH and MAX_CHILDREN_PER_NODE caps
    pub fn nodeCount(self: IcicleChart) usize {
        if (self.root == null) return 0;
        return 1 + countChildrenRecursive(self.root.?, 1);
    }

    /// Builder: set root node
    pub fn withRoot(self: IcicleChart, root: IcicleNode) IcicleChart {
        var result = self;
        result.root = root;
        return result;
    }

    /// Builder: set focused path
    pub fn withFocused(self: IcicleChart, path: []const usize) IcicleChart {
        var result = self;
        result.focused = path;
        return result;
    }

    /// Builder: set show_labels flag
    pub fn withShowLabels(self: IcicleChart, show: bool) IcicleChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Builder: set show_values flag
    pub fn withShowValues(self: IcicleChart, show: bool) IcicleChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Builder: set base style
    pub fn withStyle(self: IcicleChart, style: Style) IcicleChart {
        var result = self;
        result.style = style;
        return result;
    }

    /// Builder: set focused style
    pub fn withFocusedStyle(self: IcicleChart, style: Style) IcicleChart {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Builder: set label style
    pub fn withLabelStyle(self: IcicleChart, style: Style) IcicleChart {
        var result = self;
        result.label_style = style;
        return result;
    }

    /// Builder: set block border
    pub fn withBlock(self: IcicleChart, block: ?Block) IcicleChart {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render the icicle chart
    pub fn render(self: IcicleChart, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        if (self.root == null) return;

        var inner = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            inner = block.inner(area);
            if (inner.width == 0 or inner.height == 0) return;
        }

        // Render the tree structure. The root has no siblings, so it is
        // always shown as 100% of itself.
        renderTree(buf, self, self.root.?, inner, 0, 0, inner.width, self.focused.len > 0, 100.0);
    }
};

/// Count children of a node recursively, respecting depth and width caps
fn countChildrenRecursive(node: IcicleNode, depth: usize) usize {
    if (depth >= IcicleChart.MAX_DEPTH) return 0;

    var count: usize = 0;
    const child_count = @min(node.children.len, IcicleChart.MAX_CHILDREN_PER_NODE);
    for (0..child_count) |i| {
        count += 1 + countChildrenRecursive(node.children[i], depth + 1);
    }
    return count;
}

/// Compute the total of positive-value children for a node
fn childrenTotal(node: IcicleNode) f32 {
    var total: f32 = 0.0;
    const child_count = @min(node.children.len, IcicleChart.MAX_CHILDREN_PER_NODE);
    for (0..child_count) |i| {
        if (node.children[i].value > 0) {
            total += node.children[i].value;
        }
    }
    return total;
}

/// Check if a style has any field set (non-default values)
fn isStyleSet(style: Style) bool {
    return style.bold or style.dim or style.italic or style.underline or
        style.blink or style.reverse or style.strikethrough or
        style.fg != null or style.bg != null;
}

/// Determine the effective style for a node
fn getNodeStyle(
    node: IcicleNode,
    chart: IcicleChart,
    on_focused_path: bool,
) Style {
    // If on focused path and focused_style is set, use it
    if (on_focused_path and isStyleSet(chart.focused_style)) {
        return chart.focused_style;
    }

    // Otherwise, node.style (if set) > chart.style
    if (isStyleSet(node.style)) {
        return node.style;
    }

    return chart.style;
}

/// Render the tree structure recursively
fn renderTree(
    buf: *Buffer,
    chart: IcicleChart,
    node: IcicleNode,
    inner: Rect,
    depth: usize,
    col_x0: u16,
    col_width: u16,
    path_valid: bool,
    percent_of_siblings: f32,
) void {
    if (depth >= IcicleChart.MAX_DEPTH) return;
    if (depth >= inner.height) return; // No more rows available
    if (col_width == 0) return;

    // The root (depth 0) is never itself considered "on" the focused path —
    // focused[] selects children of each level, not the root. A node at
    // depth > 0 is on the focused path if the chain of child indices taken
    // to reach it matches focused[0..depth), or the path was exhausted
    // (depth >= focused.len) after matching all the way down.
    const on_focused_path = depth > 0 and path_valid;

    // Get the effective style for this node
    const node_style = getNodeStyle(node, chart, on_focused_path);

    // Calculate row position
    const row_y = inner.y + @as(u16, @intCast(depth));
    if (row_y >= buf.height) return;

    // Render the node's band
    var x = col_x0;
    while (x < col_x0 + col_width and x < buf.width) : (x += 1) {
        buf.set(x, row_y, Cell.init('█', node_style));
    }

    // Render label if enabled and band width >= 1
    if (chart.show_labels and col_width >= 1 and node.label.len > 0) {
        const label_len = @min(node.label.len, col_width);
        if (col_x0 < buf.width) {
            buf.setString(col_x0, row_y, node.label[0..label_len], chart.label_style);
        }
    } else if (chart.show_values and col_width >= 1) {
        // If not showing labels but showing values, render the percentage
        // this node represents of its parent's positive-value children sum
        // (the same denominator used for band-width proportions).
        var percent_str: [6]u8 = undefined;
        const clamped_percent = @max(0.0, @min(100.0, percent_of_siblings));
        const percent = @as(u32, @intFromFloat(clamped_percent));
        var str_len: usize = 0;

        if (percent >= 100) {
            percent_str[0] = '1';
            percent_str[1] = '0';
            percent_str[2] = '0';
            percent_str[3] = '%';
            str_len = 4;
        } else {
            const tens = percent / 10;
            const ones = percent % 10;
            percent_str[0] = @as(u8, @intCast(tens)) + 48;
            percent_str[1] = @as(u8, @intCast(ones)) + 48;
            percent_str[2] = '%';
            str_len = 3;
        }

        if (col_x0 < buf.width) {
            buf.setString(col_x0, row_y, percent_str[0..str_len], chart.label_style);
        }
    }

    // Render children
    const total = childrenTotal(node);
    if (total <= 0) return; // Leaf behavior: no deeper rows

    const child_count = @min(node.children.len, IcicleChart.MAX_CHILDREN_PER_NODE);

    var cumulative: f32 = 0.0;
    var positive_idx: usize = 0; // Index among positive-value children

    for (0..child_count) |i| {
        const child = node.children[i];

        // Skip non-positive children
        if (child.value <= 0) continue;

        // Calculate child's column span using cumulative-floor formula
        const child_x0 = col_x0 + @as(u16, @intFromFloat(
            @floor(cumulative / total * @as(f32, @floatFromInt(col_width)))
        ));

        cumulative += child.value;

        var child_x1 = col_x0 + @as(u16, @intFromFloat(
            @floor(cumulative / total * @as(f32, @floatFromInt(col_width)))
        ));

        // Ensure last positive child reaches the right edge
        // This needs to check if all remaining children are non-positive
        var is_last_positive = true;
        for (i + 1..child_count) |j| {
            if (node.children[j].value > 0) {
                is_last_positive = false;
                break;
            }
        }

        if (is_last_positive) {
            child_x1 = col_x0 + col_width;
        }

        const child_width = if (child_x1 > child_x0) child_x1 - child_x0 else 0;
        if (child_width == 0) {
            positive_idx += 1;
            continue;
        }

        // focused[depth] selects which child of this node continues the path.
        // If the path is already exhausted (depth >= focused.len), an
        // already-valid path stays valid for all descendants.
        const child_path_valid = if (depth < chart.focused.len)
            path_valid and chart.focused[depth] == i
        else
            path_valid;

        const child_percent = (child.value / total) * 100.0;

        renderTree(buf, chart, child, inner, depth + 1, child_x0, child_width, child_path_valid, child_percent);
        positive_idx += 1;
    }
}
