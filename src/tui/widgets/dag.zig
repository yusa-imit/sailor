//! DagWidget — directed acyclic graph visualization widget (v2.15.0)
//!
//! Renders a directed acyclic graph as nodes (boxes) with edges (lines + arrows).
//! All positions are in terminal cell coordinates. No allocator required.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;

/// A node in the directed graph
pub const DagWidget = struct {
    pub const Node = struct {
        id: usize,
        label: []const u8,
        x: u16,
        y: u16,
        /// 0 = auto (label.len + 2 for side borders)
        width: u16 = 0,
        height: u16 = 3,
        style: Style = .{},
        selected: bool = false,
    };

    pub const Edge = struct {
        from_id: usize,
        to_id: usize,
        label: ?[]const u8 = null,
        style: Style = .{},
    };

    nodes: []const Node,
    edges: []const Edge,
    node_style: Style = .{},
    selected_style: Style = .{},
    /// Character used to draw horizontal edge lines
    edge_char: u21 = '-',
    /// Character used at the end of an edge (arrow)
    arrow_char: u21 = '>',

    /// Returns the bounding box (Rect) of a node.
    /// Width is auto-computed from label if node.width == 0.
    pub fn nodeBox(node: Node) Rect {
        const w: u16 = if (node.width > 0)
            node.width
        else
            @intCast(@max(2, node.label.len + 2));
        return Rect{
            .x = node.x,
            .y = node.y,
            .width = w,
            .height = node.height,
        };
    }

    /// Finds a node by id. Returns null if not found.
    pub fn nodeAt(self: DagWidget, node_id: usize) ?Node {
        for (self.nodes) |n| {
            if (n.id == node_id) return n;
        }
        return null;
    }

    /// Renders the graph into the buffer, clipped to area.
    pub fn render(self: DagWidget, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Draw edges first (behind nodes)
        for (self.edges) |edge| {
            self.renderEdge(buf, area, edge);
        }

        // Draw nodes on top
        for (self.nodes) |node| {
            self.renderNode(buf, area, node);
        }
    }

    fn renderNode(self: DagWidget, buf: *Buffer, area: Rect, node: Node) void {
        const box = nodeBox(node);

        // Clip: skip node entirely if it starts beyond area
        if (node.x >= area.x + area.width) return;
        if (node.y >= area.y + area.height) return;

        const node_style = if (node.selected) self.selected_style else self.node_style;

        // Top border row
        renderBoxRow(buf, area, box, 0, node_style, node.label, .top);

        // Middle rows (content)
        var row: u16 = 1;
        while (row + 1 < box.height) : (row += 1) {
            renderBoxRow(buf, area, box, row, node_style, null, .middle);
        }

        // Bottom border row (only if height > 1)
        if (box.height > 1) {
            renderBoxRow(buf, area, box, box.height - 1, node_style, null, .bottom);
        }
    }

    const RowKind = enum { top, middle, bottom };

    fn renderBoxRow(
        buf: *Buffer,
        area: Rect,
        box: Rect,
        row_offset: u16,
        node_style: Style,
        label: ?[]const u8,
        kind: RowKind,
    ) void {
        const abs_y = box.y + row_offset;
        if (abs_y < area.y or abs_y >= area.y + area.height) return;

        const buf_y = abs_y;

        switch (kind) {
            .top => {
                // ┌─ label ─┐
                renderCell(buf, area, box.x, buf_y, '┌', node_style);
                renderCell(buf, area, box.x + box.width -| 1, buf_y, '┐', node_style);
                // Fill interior with '─', overlay label in center
                const inner_start = box.x + 1;
                const inner_width = box.width -| 2;
                var col: u16 = 0;
                while (col < inner_width) : (col += 1) {
                    renderCell(buf, area, inner_start + col, buf_y, '─', node_style);
                }
                // Render label starting at inner_start
                if (label) |lbl| {
                    var lx: u16 = 0;
                    for (lbl) |ch| {
                        if (lx >= inner_width) break;
                        renderCell(buf, area, inner_start + lx, buf_y, ch, node_style);
                        lx += 1;
                    }
                }
            },
            .middle => {
                renderCell(buf, area, box.x, buf_y, '│', node_style);
                renderCell(buf, area, box.x + box.width -| 1, buf_y, '│', node_style);
            },
            .bottom => {
                renderCell(buf, area, box.x, buf_y, '└', node_style);
                renderCell(buf, area, box.x + box.width -| 1, buf_y, '┘', node_style);
                const inner_start = box.x + 1;
                const inner_width = box.width -| 2;
                var col: u16 = 0;
                while (col < inner_width) : (col += 1) {
                    renderCell(buf, area, inner_start + col, buf_y, '─', node_style);
                }
            },
        }
    }

    fn renderEdge(self: DagWidget, buf: *Buffer, area: Rect, edge: Edge) void {
        // Skip self-loops
        if (edge.from_id == edge.to_id) return;

        const from_node = self.nodeAt(edge.from_id) orelse return;
        const to_node = self.nodeAt(edge.to_id) orelse return;

        const from_box = nodeBox(from_node);
        const to_box = nodeBox(to_node);

        // Compute edge source: right edge of from_box, at mid-height
        const from_mid_y = from_box.y + from_box.height / 2;
        const from_right_x = from_box.x + from_box.width;

        // Compute edge target: left edge of to_box, at mid-height
        const to_mid_y = to_box.y + to_box.height / 2;
        const to_left_x = to_box.x;

        // Only draw simple horizontal edge when nodes are on approximately same row
        // For vertical edges, draw a simple stub
        const edge_y = from_mid_y;

        if (from_right_x >= to_left_x) return; // Overlapping or reversed, skip

        // Draw horizontal line from from_right_x to to_left_x - 1 at edge_y
        var x = from_right_x;
        while (x < to_left_x) : (x += 1) {
            const ch: u21 = if (x + 1 == to_left_x) self.arrow_char else self.edge_char;
            renderCell(buf, area, x, edge_y, ch, edge.style);
        }

        // If there's a vertical offset, draw a simple vertical line on the target side
        if (from_mid_y != to_mid_y) {
            const start_y = @min(from_mid_y, to_mid_y);
            const end_y = @max(from_mid_y, to_mid_y);
            var y = start_y;
            while (y <= end_y) : (y += 1) {
                renderCell(buf, area, to_left_x -| 1, y, '|', edge.style);
            }
        }

        // Render edge label if present (midpoint of edge)
        if (edge.label) |lbl| {
            if (to_left_x > from_right_x + 2) {
                const mid_x = from_right_x + (to_left_x - from_right_x) / 2;
                var lx: u16 = 0;
                for (lbl) |ch| {
                    if (mid_x + lx >= to_left_x) break;
                    renderCell(buf, area, mid_x + lx, edge_y -| 1, ch, edge.style);
                    lx += 1;
                }
            }
        }

    }

    fn renderCell(buf: *Buffer, area: Rect, abs_x: u16, abs_y: u16, char: u21, s: Style) void {
        if (abs_x < area.x or abs_x >= area.x + area.width) return;
        if (abs_y < area.y or abs_y >= area.y + area.height) return;
        buf.set(abs_x, abs_y, .{ .char = char, .style = s });
    }
};
