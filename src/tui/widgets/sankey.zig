//! SankeyDiagram Widget — Flow Visualization
//!
//! SankeyDiagram displays quantitative flows between source and target nodes,
//! with each flow proportional to its value. Nodes are arranged in columns
//! from left to right, with heights proportional to their flow magnitude.
//!
//! ## Features
//! - Column-based node layout (left to right)
//! - Node height proportional to flow magnitude
//! - Flow lines connecting source and target nodes
//! - Focused node highlighting with custom styles
//! - Capping at MAX_NODES (32) and MAX_FLOWS (64)
//! - Optional block borders
//! - Builder pattern for configuration
//!
//! ## Usage
//! ```zig
//! var nodes = [_]SankeyNode{
//!     .{ .label = "A", .column = 0 },
//!     .{ .label = "B", .column = 1 },
//! };
//! var flows = [_]SankeyFlow{
//!     .{ .source = 0, .target = 1, .value = 10.0 },
//! };
//!
//! const sk = SankeyDiagram.init()
//!     .withNodes(&nodes)
//!     .withFlows(&flows)
//!     .withNodeWidth(3)
//!     .withColGap(8);
//!
//! sk.render(&buf, area);
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

pub const SankeyNode = struct {
    label: []const u8 = "",
    column: usize = 0,
    style: Style = .{},
};

pub const SankeyFlow = struct {
    source: usize = 0,
    target: usize = 0,
    value: f32 = 0.0,
    style: Style = .{},
};

pub const SankeyDiagram = struct {
    pub const MAX_NODES: usize = 32;
    pub const MAX_FLOWS: usize = 64;

    nodes: []const SankeyNode = &.{},
    flows: []const SankeyFlow = &.{},
    focused: usize = 0,
    node_width: u16 = 2,
    col_gap: u16 = 8,
    style: Style = .{},
    node_style: Style = .{},
    flow_style: Style = .{},
    focused_style: Style = .{},
    block: ?Block = null,

    /// Initialize a new SankeyDiagram with default values
    pub fn init() SankeyDiagram {
        return .{};
    }

    /// Return the number of nodes to render (capped at MAX_NODES)
    pub fn nodeCount(self: SankeyDiagram) usize {
        return @min(self.nodes.len, MAX_NODES);
    }

    /// Return the number of flows to render (capped at MAX_FLOWS)
    pub fn flowCount(self: SankeyDiagram) usize {
        return @min(self.flows.len, MAX_FLOWS);
    }

    /// Set nodes (builder pattern)
    pub fn withNodes(self: SankeyDiagram, nodes: []const SankeyNode) SankeyDiagram {
        var result = self;
        result.nodes = nodes;
        return result;
    }

    /// Set flows (builder pattern)
    pub fn withFlows(self: SankeyDiagram, flows: []const SankeyFlow) SankeyDiagram {
        var result = self;
        result.flows = flows;
        return result;
    }

    /// Set focused node index (builder pattern)
    pub fn withFocused(self: SankeyDiagram, idx: usize) SankeyDiagram {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set node width (builder pattern)
    pub fn withNodeWidth(self: SankeyDiagram, w: u16) SankeyDiagram {
        var result = self;
        result.node_width = w;
        return result;
    }

    /// Set column gap (builder pattern)
    pub fn withColGap(self: SankeyDiagram, g: u16) SankeyDiagram {
        var result = self;
        result.col_gap = g;
        return result;
    }

    /// Set base style (builder pattern)
    pub fn withStyle(self: SankeyDiagram, s: Style) SankeyDiagram {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set node style (builder pattern)
    pub fn withNodeStyle(self: SankeyDiagram, s: Style) SankeyDiagram {
        var result = self;
        result.node_style = s;
        return result;
    }

    /// Set flow style (builder pattern)
    pub fn withFlowStyle(self: SankeyDiagram, s: Style) SankeyDiagram {
        var result = self;
        result.flow_style = s;
        return result;
    }

    /// Set focused style (builder pattern)
    pub fn withFocusedStyle(self: SankeyDiagram, s: Style) SankeyDiagram {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set optional block border (builder pattern)
    pub fn withBlock(self: SankeyDiagram, b: Block) SankeyDiagram {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the sankey diagram to the buffer
    pub fn render(self: *const SankeyDiagram, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block border if present
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner_area = block.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Get actual counts (capped)
        const node_count = self.nodeCount();
        const flow_count = self.flowCount();

        if (node_count == 0) return;

        // Fill background with base style
        buf.fill(inner_area, ' ', self.style);

        // Find all unique columns and sort them
        var columns: [MAX_NODES]usize = undefined;
        var col_count: usize = 0;

        for (0..node_count) |i| {
            const node = self.nodes[i];
            var found = false;
            for (0..col_count) |j| {
                if (columns[j] == node.column) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                columns[col_count] = node.column;
                col_count += 1;
            }
        }

        // Sort columns in ascending order
        for (0..col_count) |i| {
            for (i + 1..col_count) |j| {
                if (columns[j] < columns[i]) {
                    const tmp = columns[i];
                    columns[i] = columns[j];
                    columns[j] = tmp;
                }
            }
        }

        // Calculate node heights based on flow values
        var node_heights: [MAX_NODES]u16 = undefined;
        var max_flow: f32 = 0.0;

        // First pass: calculate total flow for each node
        for (0..node_count) |i| {
            var total_flow: f32 = 0.0;
            for (0..flow_count) |f| {
                const flow = self.flows[f];
                if (flow.source == i or flow.target == i) {
                    const abs_val = if (flow.value < 0.0) -flow.value else flow.value;
                    total_flow += abs_val;
                }
            }
            if (total_flow > max_flow) {
                max_flow = total_flow;
            }
        }

        // Second pass: convert total flow to height
        if (max_flow <= 0.0) max_flow = 1.0;
        for (0..node_count) |i| {
            var total_flow: f32 = 0.0;
            for (0..flow_count) |f| {
                const flow = self.flows[f];
                if (flow.source == i or flow.target == i) {
                    const abs_val = if (flow.value < 0.0) -flow.value else flow.value;
                    total_flow += abs_val;
                }
            }
            const height = @max(1, @as(u16, @intFromFloat(total_flow * @as(f32, @floatFromInt(inner_area.height)) / max_flow)));
            node_heights[i] = @min(height, inner_area.height);
        }

        // Render nodes by column, stacking vertically within each column
        for (0..col_count) |col_idx| {
            const col = columns[col_idx];
            const col_x = inner_area.x + @as(u16, @intCast(col_idx)) * (self.node_width + self.col_gap);

            if (col_x >= inner_area.x + inner_area.width) break;

            var col_y = inner_area.y;
            for (0..node_count) |node_idx| {
                const node = self.nodes[node_idx];
                if (node.column != col) continue;

                const height = node_heights[node_idx];
                if (col_y + height > inner_area.y + inner_area.height) break;

                // Determine node style — merge base style so self.style acts as background
                const actual_style = self.style.merge(if (node_idx == self.focused)
                    self.focused_style
                else
                    self.node_style);

                // Render node bar
                var y = col_y;
                while (y < col_y + height and y < inner_area.y + inner_area.height) : (y += 1) {
                    var x = col_x;
                    while (x < col_x + self.node_width and x < inner_area.x + inner_area.width) : (x += 1) {
                        buf.set(x, y, Cell{ .char = '█', .style = actual_style });
                    }
                }

                col_y += height;
            }
        }

        // Render flows as connecting lines
        for (0..flow_count) |flow_idx| {
            const flow = self.flows[flow_idx];
            if (flow.source >= node_count or flow.target >= node_count) continue;

            const source_node = self.nodes[flow.source];
            const target_node = self.nodes[flow.target];

            // Find column indices
            var source_col_idx: usize = 0;
            var target_col_idx: usize = 0;
            for (0..col_count) |i| {
                if (columns[i] == source_node.column) source_col_idx = i;
                if (columns[i] == target_node.column) target_col_idx = i;
            }

            // Skip if same column or invalid
            if (source_col_idx >= target_col_idx) continue;

            // Calculate source node y position and midpoint
            var source_y = inner_area.y;
            for (0..flow.source) |i| {
                if (self.nodes[i].column == source_node.column) {
                    source_y += node_heights[i];
                }
            }
            source_y += node_heights[flow.source] / 2;

            // Calculate target node y position and midpoint
            var target_y = inner_area.y;
            for (0..flow.target) |i| {
                if (self.nodes[i].column == target_node.column) {
                    target_y += node_heights[i];
                }
            }
            target_y += node_heights[flow.target] / 2;

            // Draw flow line from source to target
            const source_x = inner_area.x + @as(u16, @intCast(source_col_idx)) * (self.node_width + self.col_gap) + self.node_width;
            const target_x = inner_area.x + @as(u16, @intCast(target_col_idx)) * (self.node_width + self.col_gap);

            if (source_x < inner_area.x + inner_area.width and target_x > inner_area.x) {
                var x = source_x;
                while (x < target_x and x < inner_area.x + inner_area.width) : (x += 1) {
                    if (source_y >= inner_area.y and source_y < inner_area.y + inner_area.height) {
                        buf.set(x, source_y, Cell{ .char = '─', .style = self.flow_style });
                    }
                }
            }
        }
    }
};
