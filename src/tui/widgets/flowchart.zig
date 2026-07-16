//! FlowChart Widget — flowchart visualization with nodes and connectors
//!
//! The FlowChart widget displays a directed graph of nodes connected by edges.
//! Nodes can be rendered in different shapes (process, decision, terminal, io),
//! and edges can have labels. The widget uses a grid-based layout with customizable
//! spacing and supports focused node highlighting.
//!
//! ## Features
//! - Grid-based node positioning with configurable cell dimensions
//! - Four node shapes: process (box), decision (diamond), terminal (rounded), io (parallelogram)
//! - Labeled edges with directional arrows
//! - Focused node highlighting
//! - Customizable spacing and styling
//! - Block border support
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var nodes = [_]FlowNode{
//!     .{ .label = "Start", .kind = .terminal, .col = 0, .row = 0 },
//!     .{ .label = "Process", .kind = .process, .col = 0, .row = 1 },
//! };
//! var edges = [_]FlowEdge{
//!     .{ .from = 0, .to = 1, .label = "Yes" },
//! };
//! var chart = FlowChart.init()
//!     .withNodes(&nodes)
//!     .withEdges(&edges);
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

/// Node shape enumeration
pub const NodeKind = enum {
    process,
    decision,
    terminal,
    io,
};

/// A single node in the flowchart
pub const FlowNode = struct {
    label: []const u8 = "",
    kind: NodeKind = .process,
    col: u16 = 0,
    row: u16 = 0,
    style: Style = .{},
};

/// A directed edge between two nodes
pub const FlowEdge = struct {
    from: usize = 0,
    to: usize = 0,
    label: []const u8 = "",
    style: Style = .{},
};

/// FlowChart widget for displaying directed graphs with nodes and edges
pub const FlowChart = struct {
    /// Maximum number of nodes to display
    pub const MAX_NODES: usize = 32;

    /// Maximum number of edges to display
    pub const MAX_EDGES: usize = 64;

    /// Array of nodes to display
    nodes: []const FlowNode = &.{},

    /// Array of edges to display
    edges: []const FlowEdge = &.{},

    /// Index of the focused node
    focused: usize = 0,

    /// Base style for the entire widget
    style: Style = .{},

    /// Style for focused node
    focused_style: Style = .{},

    /// Width of each node in characters
    node_width: u16 = 12,

    /// Height of each node in lines
    node_height: u16 = 3,

    /// Horizontal spacing between nodes in the grid
    h_spacing: u16 = 4,

    /// Vertical spacing between nodes in the grid
    v_spacing: u16 = 2,

    /// Optional border block
    block: ?Block = null,

    /// Initialize a new FlowChart with defaults
    pub fn init() FlowChart {
        return .{};
    }

    /// Create a copy with different nodes
    pub fn withNodes(self: FlowChart, nodes: []const FlowNode) FlowChart {
        var result = self;
        result.nodes = nodes;
        return result;
    }

    /// Create a copy with different edges
    pub fn withEdges(self: FlowChart, edges: []const FlowEdge) FlowChart {
        var result = self;
        result.edges = edges;
        return result;
    }

    /// Create a copy with different focused index
    pub fn withFocused(self: FlowChart, focused: usize) FlowChart {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: FlowChart, style: Style) FlowChart {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different focused style
    pub fn withFocusedStyle(self: FlowChart, style: Style) FlowChart {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Create a copy with different node width
    pub fn withNodeWidth(self: FlowChart, w: u16) FlowChart {
        var result = self;
        result.node_width = w;
        return result;
    }

    /// Create a copy with different node height
    pub fn withNodeHeight(self: FlowChart, h: u16) FlowChart {
        var result = self;
        result.node_height = h;
        return result;
    }

    /// Create a copy with different horizontal spacing
    pub fn withHSpacing(self: FlowChart, spacing: u16) FlowChart {
        var result = self;
        result.h_spacing = spacing;
        return result;
    }

    /// Create a copy with different vertical spacing
    pub fn withVSpacing(self: FlowChart, spacing: u16) FlowChart {
        var result = self;
        result.v_spacing = spacing;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: FlowChart, block: Block) FlowChart {
        var result = self;
        result.block = block;
        return result;
    }

    /// Get the number of nodes (clamped to MAX_NODES)
    pub fn nodeCount(self: FlowChart) usize {
        return @min(self.nodes.len, MAX_NODES);
    }

    /// Get the number of edges (clamped to MAX_EDGES)
    pub fn edgeCount(self: FlowChart) usize {
        return @min(self.edges.len, MAX_EDGES);
    }

    /// Render the flowchart to the buffer
    pub fn render(self: FlowChart, buf: *Buffer, area: Rect) void {
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

        // Get count of nodes and edges to render
        const node_cnt = self.nodeCount();
        const edge_cnt = self.edgeCount();

        // Render nodes first
        var node_idx: usize = 0;
        while (node_idx < node_cnt) : (node_idx += 1) {
            const node = self.nodes[node_idx];
            renderNode(self, buf, inner, node, node_idx);
        }

        // Render edges on top (including arrows and labels)
        var edge_idx: usize = 0;
        while (edge_idx < edge_cnt) : (edge_idx += 1) {
            const edge = self.edges[edge_idx];
            if (edge.from >= node_cnt or edge.to >= node_cnt) {
                continue;
            }
            renderEdge(self, buf, inner, edge);
        }
    }
};

/// Compute pixel position from grid position
fn gridToPixel(self: FlowChart, inner: Rect, col: u16, row: u16) struct { px: u16, py: u16 } {
    const cell_width = self.node_width + self.h_spacing;
    const cell_height = self.node_height + self.v_spacing;
    return .{
        .px = inner.x +| col *| cell_width,
        .py = inner.y +| row *| cell_height,
    };
}

/// Render a single node
fn renderNode(self: FlowChart, buf: *Buffer, inner: Rect, node: FlowNode, node_idx: usize) void {
    const pos = gridToPixel(self, inner, node.col, node.row);
    const px = pos.px;
    const py = pos.py;

    // Bounds check
    if (px >= inner.x + inner.width or py >= inner.y + inner.height) {
        return;
    }

    // Determine style
    const is_focused = (node_idx == self.focused and node_idx < self.nodeCount());
    const node_style = if (is_focused) self.focused_style else (if (!std.meta.eql(node.style, Style{})) node.style else self.style);

    // Render based on node kind
    switch (node.kind) {
        .process => renderProcessNode(buf, px, py, self.node_width, self.node_height, node.label, node_style, inner),
        .terminal => renderTerminalNode(buf, px, py, self.node_width, self.node_height, node.label, node_style, inner),
        .decision => renderDecisionNode(buf, px, py, self.node_width, self.node_height, node.label, node_style, inner),
        .io => renderIoNode(buf, px, py, self.node_width, self.node_height, node.label, node_style, inner),
    }
}

/// Render a process node (rectangle with corners)
fn renderProcessNode(buf: *Buffer, px: u16, py: u16, width: u16, height: u16, label: []const u8, style: Style, inner: Rect) void {
    if (width < 2 or height < 1) return;

    // Top-left corner
    if (px < inner.x + inner.width and py < inner.y + inner.height) {
        buf.set(px, py, Cell.init(@as(u21, 0x250C), style)); // ┌
    }

    // Top border
    var x: u16 = 1;
    while (x < width - 1 and px + x < inner.x + inner.width) : (x += 1) {
        if (py < inner.y + inner.height) {
            buf.set(px + x, py, Cell.init(@as(u21, 0x2500), style)); // ─
        }
    }

    // Top-right corner
    if (px + width - 1 < inner.x + inner.width and py < inner.y + inner.height) {
        buf.set(px + width - 1, py, Cell.init(@as(u21, 0x2510), style)); // ┐
    }

    // Middle rows with label
    var row: u16 = 1;
    while (row < height and py + row < inner.y + inner.height) : (row += 1) {
        // Left border
        if (px < inner.x + inner.width) {
            buf.set(px, py + row, Cell.init(@as(u21, 0x2502), style)); // │
        }

        // Label on middle row
        if (row == height / 2) {
            renderLabelCentered(buf, px + 1, py + row, width - 2, label, style, inner);
        }

        // Right border
        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py + row, Cell.init(@as(u21, 0x2502), style)); // │
        }
    }

    // Bottom border
    var bx: u16 = 1;
    while (bx < width - 1 and px + bx < inner.x + inner.width) : (bx += 1) {
        if (py + height - 1 < inner.y + inner.height) {
            buf.set(px + bx, py + height - 1, Cell.init(@as(u21, 0x2500), style)); // ─
        }
    }

    // Bottom-left corner
    if (px < inner.x + inner.width and py + height - 1 < inner.y + inner.height) {
        buf.set(px, py + height - 1, Cell.init(@as(u21, 0x2514), style)); // └
    }

    // Bottom-right corner
    if (px + width - 1 < inner.x + inner.width and py + height - 1 < inner.y + inner.height) {
        buf.set(px + width - 1, py + height - 1, Cell.init(@as(u21, 0x2518), style)); // ┘
    }
}

/// Render a terminal node (rounded corners)
fn renderTerminalNode(buf: *Buffer, px: u16, py: u16, width: u16, height: u16, label: []const u8, style: Style, inner: Rect) void {
    if (width < 2 or height < 1) return;

    // Top-left corner (rounded)
    if (px < inner.x + inner.width and py < inner.y + inner.height) {
        buf.set(px, py, Cell.init(@as(u21, 0x256D), style)); // ╭
    }

    // Top border
    var x: u16 = 1;
    while (x < width - 1 and px + x < inner.x + inner.width) : (x += 1) {
        if (py < inner.y + inner.height) {
            buf.set(px + x, py, Cell.init(@as(u21, 0x2500), style)); // ─
        }
    }

    // Top-right corner (rounded)
    if (px + width - 1 < inner.x + inner.width and py < inner.y + inner.height) {
        buf.set(px + width - 1, py, Cell.init(@as(u21, 0x256E), style)); // ╮
    }

    // Middle rows with label
    var row: u16 = 1;
    while (row < height and py + row < inner.y + inner.height) : (row += 1) {
        // Left border
        if (px < inner.x + inner.width) {
            buf.set(px, py + row, Cell.init(@as(u21, 0x2502), style)); // │
        }

        // Label on middle row
        if (row == height / 2) {
            renderLabelCentered(buf, px + 1, py + row, width - 2, label, style, inner);
        }

        // Right border
        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py + row, Cell.init(@as(u21, 0x2502), style)); // │
        }
    }

    // Bottom border
    var bx: u16 = 1;
    while (bx < width - 1 and px + bx < inner.x + inner.width) : (bx += 1) {
        if (py + height - 1 < inner.y + inner.height) {
            buf.set(px + bx, py + height - 1, Cell.init(@as(u21, 0x2500), style)); // ─
        }
    }

    // Bottom-left corner (rounded)
    if (px < inner.x + inner.width and py + height - 1 < inner.y + inner.height) {
        buf.set(px, py + height - 1, Cell.init(@as(u21, 0x2570), style)); // ╰
    }

    // Bottom-right corner (rounded)
    if (px + width - 1 < inner.x + inner.width and py + height - 1 < inner.y + inner.height) {
        buf.set(px + width - 1, py + height - 1, Cell.init(@as(u21, 0x256F), style)); // ╯
    }
}

/// Render a decision node (diamond shape approximation)
fn renderDecisionNode(buf: *Buffer, px: u16, py: u16, width: u16, height: u16, label: []const u8, style: Style, inner: Rect) void {
    if (width < 3 or height < 3) return;

    // Use a box-like rendering for simplicity, but with slanted corners
    // Top row: space + / + ─ chars + \ + space
    if (py < inner.y + inner.height) {
        if (px < inner.x + inner.width) {
            buf.set(px, py, Cell.init(@as(u21, ' '), style));
        }
        if (px + 1 < inner.x + inner.width) {
            buf.set(px + 1, py, Cell.init(@as(u21, '/'), style));
        }
        var x: u16 = 2;
        while (x < width - 2 and px + x < inner.x + inner.width) : (x += 1) {
            buf.set(px + x, py, Cell.init(@as(u21, 0x2500), style)); // ─
        }
        if (px + width - 2 < inner.x + inner.width) {
            buf.set(px + width - 2, py, Cell.init(@as(u21, '\\'), style));
        }
        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py, Cell.init(@as(u21, ' '), style));
        }
    }

    // Middle rows: / + label + \
    var row: u16 = 1;
    while (row < height and py + row < inner.y + inner.height) : (row += 1) {
        if (px < inner.x + inner.width) {
            buf.set(px, py + row, Cell.init(@as(u21, '/'), style));
        }

        if (row == height / 2) {
            renderLabelCentered(buf, px + 1, py + row, width - 2, label, style, inner);
        }

        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py + row, Cell.init(@as(u21, '\\'), style));
        }
    }

    // Bottom row: space + \ + ─ chars + / + space
    if (py + height - 1 < inner.y + inner.height) {
        if (px < inner.x + inner.width) {
            buf.set(px, py + height - 1, Cell.init(@as(u21, ' '), style));
        }
        if (px + 1 < inner.x + inner.width) {
            buf.set(px + 1, py + height - 1, Cell.init(@as(u21, '\\'), style));
        }
        var x: u16 = 2;
        while (x < width - 2 and px + x < inner.x + inner.width) : (x += 1) {
            buf.set(px + x, py + height - 1, Cell.init(@as(u21, 0x2500), style)); // ─
        }
        if (px + width - 2 < inner.x + inner.width) {
            buf.set(px + width - 2, py + height - 1, Cell.init(@as(u21, '/'), style));
        }
        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py + height - 1, Cell.init(@as(u21, ' '), style));
        }
    }
}

/// Render an I/O node (parallelogram)
fn renderIoNode(buf: *Buffer, px: u16, py: u16, width: u16, height: u16, label: []const u8, style: Style, inner: Rect) void {
    if (width < 3 or height < 1) return;

    // Top row: / + ─ chars + \
    if (py < inner.y + inner.height) {
        if (px < inner.x + inner.width) {
            buf.set(px, py, Cell.init(@as(u21, '/'), style));
        }
        var x: u16 = 1;
        while (x < width - 1 and px + x < inner.x + inner.width) : (x += 1) {
            buf.set(px + x, py, Cell.init(@as(u21, 0x2500), style)); // ─
        }
        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py, Cell.init(@as(u21, '\\'), style));
        }
    }

    // Middle rows: │ + label + │
    var row: u16 = 1;
    while (row < height and py + row < inner.y + inner.height) : (row += 1) {
        if (px < inner.x + inner.width) {
            buf.set(px, py + row, Cell.init(@as(u21, 0x2502), style)); // │
        }

        if (row == height / 2) {
            renderLabelCentered(buf, px + 1, py + row, width - 2, label, style, inner);
        }

        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py + row, Cell.init(@as(u21, 0x2502), style)); // │
        }
    }

    // Bottom row: \ + ─ chars + /
    if (py + height - 1 < inner.y + inner.height) {
        if (px < inner.x + inner.width) {
            buf.set(px, py + height - 1, Cell.init(@as(u21, '\\'), style));
        }
        var x: u16 = 1;
        while (x < width - 1 and px + x < inner.x + inner.width) : (x += 1) {
            buf.set(px + x, py + height - 1, Cell.init(@as(u21, 0x2500), style)); // ─
        }
        if (px + width - 1 < inner.x + inner.width) {
            buf.set(px + width - 1, py + height - 1, Cell.init(@as(u21, '/'), style));
        }
    }
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
    while (x < left_padding and start_x + x < inner.x + inner.width) : (x += 1) {
        buf.set(start_x + x, y, Cell.char_only(' '));
    }

    // Render label
    var idx: u16 = 0;
    while (idx < label_len and start_x + x < inner.x + inner.width) : ({
        x += 1;
        idx += 1;
    }) {
        buf.set(start_x + x, y, Cell.init(label[idx], style));
    }

    // Render spaces after label
    while (x < available_width and start_x + x < inner.x + inner.width) : (x += 1) {
        buf.set(start_x + x, y, Cell.char_only(' '));
    }
}

/// Render an edge between two nodes
fn renderEdge(self: FlowChart, buf: *Buffer, inner: Rect, edge: FlowEdge) void {
    const src_node = self.nodes[edge.from];
    const dst_node = self.nodes[edge.to];

    const src_pos = gridToPixel(self, inner, src_node.col, src_node.row);
    const dst_pos = gridToPixel(self, inner, dst_node.col, dst_node.row);

    const src_px = src_pos.px;
    const src_py = src_pos.py;
    const dst_px = dst_pos.px;
    const dst_py = dst_pos.py;

    const src_center_x = src_px +| (self.node_width / 2);
    const src_center_y = src_py +| (self.node_height / 2);
    const dst_center_x = dst_px +| (self.node_width / 2);
    const dst_center_y = dst_py +| (self.node_height / 2);

    const edge_style = edge.style;

    // Determine direction and draw connector
    if (dst_py > src_py) {
        // Downward connection
        var y: u16 = src_py + self.node_height;
        while (y < dst_py and y < inner.y + inner.height) : (y += 1) {
            if (src_center_x < inner.x + inner.width) {
                buf.set(src_center_x, y, Cell.init(@as(u21, 0x2502), edge_style)); // │
            }
        }
        // Arrow at destination
        if (dst_py < inner.y + inner.height and dst_center_x < inner.x + inner.width) {
            buf.set(dst_center_x, dst_py, Cell.init(@as(u21, 0x25BC), edge_style)); // ▼
        }

        // Edge label at midpoint
        if (edge.label.len > 0) {
            const mid_y = (src_py + dst_py) / 2;
            if (mid_y < inner.y + inner.height) {
                renderLabelCentered(buf, src_center_x, mid_y, @min(edge.label.len, 10), edge.label, edge_style, inner);
            }
        }
    } else if (dst_py < src_py) {
        // Upward connection
        var y: u16 = src_py;
        while (y > dst_py and y > 0 and y < inner.y + inner.height) : (y -= 1) {
            if (src_center_x < inner.x + inner.width) {
                buf.set(src_center_x, y, Cell.init(@as(u21, 0x2502), edge_style)); // │
            }
        }
        // Arrow at destination
        if (dst_py + self.node_height < inner.y + inner.height and dst_center_x < inner.x + inner.width) {
            buf.set(dst_center_x, dst_py + self.node_height, Cell.init(@as(u21, 0x25B2), edge_style)); // ▲
        }

        // Edge label
        if (edge.label.len > 0) {
            const mid_y = (src_py + dst_py) / 2;
            if (mid_y < inner.y + inner.height) {
                renderLabelCentered(buf, src_center_x, mid_y, @min(edge.label.len, 10), edge.label, edge_style, inner);
            }
        }
    } else if (dst_px > src_px) {
        // Rightward connection
        var x: u16 = src_px + self.node_width;
        while (x < dst_px and x < inner.x + inner.width) : (x += 1) {
            buf.set(x, src_center_y, Cell.init(@as(u21, 0x2500), edge_style)); // ─
        }
        // Arrow at destination
        if (dst_center_x < inner.x + inner.width) {
            buf.set(dst_px, dst_center_y, Cell.init(@as(u21, 0x25B6), edge_style)); // ▶
        }

        // Edge label
        if (edge.label.len > 0) {
            const mid_x = (src_px + dst_px) / 2;
            if (mid_x < inner.x + inner.width) {
                renderLabelCentered(buf, mid_x, src_center_y, @min(edge.label.len, 10), edge.label, edge_style, inner);
            }
        }
    } else if (dst_px < src_px) {
        // Leftward connection
        var x: u16 = src_px;
        while (x > dst_px and x > 0 and x < inner.x + inner.width) : (x -= 1) {
            buf.set(x, src_center_y, Cell.init(@as(u21, 0x2500), edge_style)); // ─
        }
        // Arrow at destination
        if (dst_px + self.node_width < inner.x + inner.width) {
            buf.set(dst_px + self.node_width, dst_center_y, Cell.init(@as(u21, 0x25C0), edge_style)); // ◀
        }

        // Edge label
        if (edge.label.len > 0) {
            const mid_x = (src_px + dst_px) / 2;
            if (mid_x < inner.x + inner.width) {
                renderLabelCentered(buf, mid_x, src_center_y, @min(edge.label.len, 10), edge.label, edge_style, inner);
            }
        }
    }
}
