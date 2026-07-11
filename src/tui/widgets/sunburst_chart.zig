//! SunburstChart Widget — Hierarchical radial chart
//!
//! The SunburstChart widget displays hierarchical tree data as concentric rings
//! of arcs arranged in a circular pattern. Each ring represents a level of the tree,
//! with the outermost ring being the deepest leaf level and the innermost ring being
//! the root level. Angular position represents the node's position among siblings,
//! proportional to its value.
//!
//! ## Features
//! - Up to MAX_DEPTH=4 concentric rings (tree levels)
//! - Up to MAX_NODES=8 top-level (root) nodes
//! - Hierarchical tree rendering with automatic depth capping
//! - Clockwise rendering from 12 o'clock
//! - Focused branch highlighting
//! - Optional labels and values
//! - Per-node styling
//! - Block border support
//! - Terminal aspect ratio compensation (cells are ~2x taller than wide)
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! var child = [_]SunburstNode{
//!     .{ .label = "SubA", .value = 10.0 },
//! };
//! var nodes = [_]SunburstNode{
//!     .{ .label = "Root", .value = 30.0, .children = &child },
//! };
//!
//! const chart = SunburstChart.init()
//!     .withNodes(&nodes)
//!     .withShowLabels(true)
//!     .withShowValues(true);
//!
//! chart.render(&buf, area);
//! ```

const std = @import("std");
const math = std.math;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// A node in the sunburst tree hierarchy
pub const SunburstNode = struct {
    /// Label for the node
    label: []const u8 = "",
    /// Value (hierarchical weight; positive values contribute to span proportion)
    value: f32 = 0.0,
    /// Child nodes (empty for leaf nodes)
    children: []const SunburstNode = &.{},
    /// Optional custom style for this node
    style: Style = .{},
};

pub const SunburstChart = struct {
    /// Maximum number of concentric rings (tree depth)
    pub const MAX_DEPTH: usize = 4;
    /// Maximum number of top-level nodes
    pub const MAX_NODES: usize = 8;

    /// Array of top-level (root) nodes
    nodes: []const SunburstNode = &.{},
    /// Index of the focused top-level node; whole radial branch (all depths) gets focused_style
    focused: usize = 0,
    /// Whether to render node labels
    show_labels: bool = true,
    /// Whether to render node values (as percentages of sibling sum)
    show_values: bool = true,
    /// Base style applied to widget
    style: Style = .{},
    /// Style for node arcs (fallback when node.style has no bold/dim/italic/underline)
    arc_style: Style = .{},
    /// Style for the focused node's branch
    focused_style: Style = .{},
    /// Style for labels
    label_style: Style = .{},
    /// Style for empty ring portions (no node covering that angle/depth)
    empty_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a SunburstChart with all defaults
    pub fn init() SunburstChart {
        return .{};
    }

    /// Count of top-level nodes to render (capped at MAX_NODES)
    pub fn nodeCount(self: SunburstChart) usize {
        return @min(self.nodes.len, MAX_NODES);
    }

    /// Sum of positive-value top-level nodes
    pub fn totalValue(self: SunburstChart) f32 {
        var total: f32 = 0.0;
        for (0..self.nodeCount()) |i| {
            const v = self.nodes[i].value;
            if (v > 0) total += v;
        }
        return total;
    }

    /// Set nodes array
    pub fn withNodes(self: SunburstChart, nodes: []const SunburstNode) SunburstChart {
        var result = self;
        result.nodes = nodes;
        return result;
    }

    /// Set focused node index
    pub fn withFocused(self: SunburstChart, idx: usize) SunburstChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: SunburstChart, show: bool) SunburstChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: SunburstChart, show: bool) SunburstChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: SunburstChart, s: Style) SunburstChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set arc style
    pub fn withArcStyle(self: SunburstChart, s: Style) SunburstChart {
        var result = self;
        result.arc_style = s;
        return result;
    }

    /// Set focused style
    pub fn withFocusedStyle(self: SunburstChart, s: Style) SunburstChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: SunburstChart, s: Style) SunburstChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set empty style
    pub fn withEmptyStyle(self: SunburstChart, s: Style) SunburstChart {
        var result = self;
        result.empty_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: SunburstChart, b: ?Block) SunburstChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the sunburst chart to the buffer
    pub fn render(self: SunburstChart, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need at least 3x3 for circle rendering
        if (inner.width < 3 or inner.height < 3) return;

        const n = self.nodeCount();
        if (n == 0) return;

        // Determine circle area vs label area
        const circle_width = @min(inner.width, inner.height);
        const circle_height = inner.height;

        // Label area starts after circle
        const label_col_start = inner.x + circle_width;
        const label_col_width = if (inner.width > circle_width) inner.width - circle_width else 0;

        // Circle center
        const cx = inner.x + @as(i32, @intCast(circle_width / 2));
        const cy = inner.y + @as(i32, @intCast(circle_height / 2));
        const max_radius = @as(f32, @floatFromInt(circle_width / 2));

        // Render the tree
        renderTree(buf, self, cx, cy, max_radius, inner);

        // Render labels if space available
        if ((self.show_labels or self.show_values) and label_col_width > 0) {
            for (0..n) |i| {
                const node = self.nodes[i];
                const label_y = inner.y + @as(u16, @intCast(i));
                if (label_y >= buf.height) break;

                var label_x = label_col_start;

                // Render label if enabled
                if (self.show_labels and node.label.len > 0) {
                    const label_len = @min(node.label.len, label_col_width);
                    if (label_x < buf.width) {
                        buf.setString(label_x, label_y, node.label[0..label_len], self.label_style);
                        label_x += @as(u16, @intCast(label_len)) + 1;
                    }
                }

                // Render value if enabled
                if (self.show_values and label_x < buf.width) {
                    const total = self.totalValue();
                    const raw_percent = if (total > 0) (node.value / total) * 100.0 else 0.0;
                    const clamped_percent = @max(0.0, @min(100.0, raw_percent));
                    const percent = @as(u32, @intFromFloat(clamped_percent));
                    drawPercentage(buf, label_x, label_y, percent, self.label_style);
                }
            }
        }
    }
};

/// Information about which node was resolved for a cell
const ResolvedNode = struct {
    found: bool = false,
    node: ?*const SunburstNode = null,
    top_level_ancestor_idx: usize = 0,
};

/// Resolve which node (if any) occupies the cell at the given angle and ring
/// depth: current tree depth (0 = root ring, 1 = second ring, etc.)
/// ring_index: ring level (0 = innermost/root, MAX_DEPTH-1 = outermost)
/// angle: angle in [0, 2π) from 12 o'clock, clockwise
/// span_start: start angle of current node's span
/// span_end: end angle of current node's span
fn resolveNode(
    depth: usize,
    ring_index: usize,
    angle: f32,
    nodes: []const SunburstNode,
    span_start: f32,
    span_end: f32,
    top_level_idx: usize,
) ResolvedNode {
    // If depth exceeds MAX_DEPTH, we've gone too deep (shouldn't happen in normal recursion)
    if (depth >= SunburstChart.MAX_DEPTH) return .{ .found = false };

    // Compute total positive value among siblings at this level
    var total: f32 = 0.0;
    for (nodes) |node| {
        if (node.value > 0) total += node.value;
    }

    // If no positive values, this cell is "not found"
    if (total <= 0) return .{ .found = false };

    // Partition span among siblings based on their positive values
    var cursor = span_start;
    for (nodes) |*node| {
        const node_span_size = if (node.value > 0) (node.value / total) * (span_end - span_start) else 0.0;
        const node_span_end = cursor + node_span_size;

        // Check if angle falls within this node's span
        const in_span = if (cursor < node_span_end)
            angle >= cursor and angle < node_span_end
        else
            false;

        if (in_span) {
            // Found the node at this level
            if (depth == ring_index) {
                // This is the depth we're looking for
                return .{
                    .found = true,
                    .node = node,
                    .top_level_ancestor_idx = top_level_idx,
                };
            } else if (node.children.len == 0) {
                // Tree doesn't extend to the desired depth
                return .{ .found = false };
            } else {
                // Recurse deeper
                return resolveNode(
                    depth + 1,
                    ring_index,
                    angle,
                    node.children,
                    cursor,
                    node_span_end,
                    top_level_idx,
                );
            }
        }

        cursor = node_span_end;
    }

    return .{ .found = false };
}

/// Render the tree structure
fn renderTree(buf: *Buffer, chart: SunburstChart, cx: i32, cy: i32, max_radius: f32, inner: Rect) void {
    if (max_radius <= 0) return;

    const radius_per_level = max_radius / @as(f32, @floatFromInt(SunburstChart.MAX_DEPTH));

    // Iterate over all cells in the inner area
    var y = inner.y;
    while (y < inner.y + inner.height and y < buf.height) : (y += 1) {
        var x = inner.x;
        while (x < inner.x + inner.width and x < buf.width) : (x += 1) {
            // Compute distance from center, accounting for aspect ratio
            const dx_scaled = @as(f32, @floatFromInt(x)) - @as(f32, @floatFromInt(cx));
            const dx = dx_scaled * 0.5; // Compensate for aspect ratio
            const dy = @as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(cy));
            const dist = @sqrt(dx * dx + dy * dy);

            // Check if outside maximum radius
            if (dist > max_radius) continue;

            // Compute ring index for this distance
            const ring_index = @as(usize, @intFromFloat(@floor(dist / radius_per_level)));
            if (ring_index >= SunburstChart.MAX_DEPTH) continue;

            // Compute angle from top (12 o'clock), clockwise
            var angle = math.atan2(dy, dx) + math.pi / 2.0;
            if (angle < 0) angle += 2.0 * math.pi;

            // Resolve which node (if any) covers this cell
            const resolved = resolveNode(0, ring_index, angle, chart.nodes[0..chart.nodeCount()], 0, 2.0 * math.pi, 0);

            if (resolved.found) {
                // Cell is covered by a node
                const node = resolved.node.?;
                var node_style = chart.arc_style;

                // Style resolution: focused_style > node.style > arc_style
                if (resolved.top_level_ancestor_idx == chart.focused) {
                    node_style = chart.focused_style;
                } else if (node.style.bold or node.style.dim or node.style.italic or node.style.underline) {
                    node_style = node.style;
                }

                buf.set(x, y, Cell.init('█', node_style));
            } else {
                // Cell is empty (within circle/depth but no node covers it)
                buf.set(x, y, Cell.init('░', chart.empty_style));
            }
        }
    }
}

/// Draw percentage value at position
fn drawPercentage(buf: *Buffer, x: u16, y: u16, percent: u32, style: Style) void {
    var percent_str: [6]u8 = undefined;
    var str_len: usize = 0;

    if (percent == 0) {
        percent_str[0] = '0';
        percent_str[1] = '%';
        str_len = 2;
    } else if (percent >= 100) {
        percent_str[0] = '1';
        percent_str[1] = '0';
        percent_str[2] = '0';
        percent_str[3] = '%';
        str_len = 4;
    } else {
        // 2-digit percent
        const tens = percent / 10;
        const ones = percent % 10;
        percent_str[0] = @as(u8, @intCast(tens)) + 48;
        percent_str[1] = @as(u8, @intCast(ones)) + 48;
        percent_str[2] = '%';
        str_len = 3;
    }

    if (x < buf.width and y < buf.height) {
        buf.setString(x, y, percent_str[0..str_len], style);
    }
}

// ============================================================================
// Tests (minimal validation in library code)
// ============================================================================

test "SunburstChart.init creates default chart with empty nodes" {
    const sc = SunburstChart.init();
    try std.testing.expectEqual(@as(usize, 0), sc.nodes.len);
}

test "SunburstChart.init defaults focused to 0" {
    const sc = SunburstChart.init();
    try std.testing.expectEqual(@as(usize, 0), sc.focused);
}

test "SunburstChart.init defaults show_labels to true" {
    const sc = SunburstChart.init();
    try std.testing.expect(sc.show_labels);
}

test "SunburstChart.MAX_DEPTH equals 4" {
    try std.testing.expectEqual(@as(usize, 4), SunburstChart.MAX_DEPTH);
}

test "SunburstChart.MAX_NODES equals 8" {
    try std.testing.expectEqual(@as(usize, 8), SunburstChart.MAX_NODES);
}

test "SunburstChart.nodeCount caps at MAX_NODES" {
    var nodes: [10]SunburstNode = undefined;
    for (0..10) |i| {
        nodes[i] = .{ .label = "A", .value = @as(f32, @floatFromInt(i)) / 10.0 };
    }
    const sc = SunburstChart.init().withNodes(&nodes);
    try std.testing.expectEqual(@as(usize, 8), sc.nodeCount());
}

test "SunburstChart.totalValue ignores zero and negative values" {
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 10.0) },
        .{ .label = "B", .value = @as(f32, 0.0) },
        .{ .label = "C", .value = @as(f32, -5.0) },
        .{ .label = "D", .value = @as(f32, 20.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), sc.totalValue(), 0.001);
}

test "SunburstChart.withNodes does not modify original" {
    var nodes1 = [_]SunburstNode{.{ .label = "A", .value = @as(f32, 10.0) }};
    var nodes2 = [_]SunburstNode{
        .{ .label = "B", .value = @as(f32, 20.0) },
        .{ .label = "C", .value = @as(f32, 30.0) },
    };
    const sc1 = SunburstChart.init().withNodes(&nodes1);
    const sc2 = sc1.withNodes(&nodes2);
    try std.testing.expectEqual(@as(usize, 1), sc1.nodeCount());
    try std.testing.expectEqual(@as(usize, 2), sc2.nodeCount());
}

test "SunburstChart.withFocused sets focused index" {
    const sc1 = SunburstChart.init().withFocused(0);
    const sc2 = sc1.withFocused(3);
    try std.testing.expectEqual(@as(usize, 0), sc1.focused);
    try std.testing.expectEqual(@as(usize, 3), sc2.focused);
}

test "SunburstChart.render on 3x3 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 3, 3);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "A", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    sc.render(&buf, area);
}

test "SunburstChart.render with zero nodes produces no content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();
    const sc = SunburstChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
}

test "SunburstChart.render single node produces content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();
    var nodes = [_]SunburstNode{.{ .label = "Root", .value = @as(f32, 10.0) }};
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    sc.render(&buf, area);
}

test "SunburstChart.render hierarchical tree" {
    var buf = try Buffer.init(std.testing.allocator, 50, 25);
    defer buf.deinit();
    var child1 = [_]SunburstNode{.{ .label = "A.1", .value = @as(f32, 10.0) }};
    var nodes = [_]SunburstNode{
        .{ .label = "A", .value = @as(f32, 30.0), .children = &child1 },
        .{ .label = "B", .value = @as(f32, 60.0) },
    };
    const sc = SunburstChart.init().withNodes(&nodes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    sc.render(&buf, area);
}
