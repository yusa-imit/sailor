//! ChordDiagram Widget — circular relationship/flow visualization
//!
//! The ChordDiagram widget displays pairwise relationships between entities
//! arranged around a circle. Each node sits on the circle perimeter, and
//! chord lines connect nodes with non-zero flow values.
//!
//! ## Features
//! - Up to 16 nodes arranged around a circle
//! - NxN flow matrix for directional or bidirectional connections
//! - Focused node highlighting
//! - Optional node labels at the circle perimeter
//! - Builder API for fluent configuration
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const nodes = [_][]const u8{ "A", "B", "C" };
//! const row0 = [_]f32{ 0.0, 1.0, 0.5 };
//! const row1 = [_]f32{ 1.0, 0.0, 0.3 };
//! const row2 = [_]f32{ 0.5, 0.3, 0.0 };
//! const mat  = [_][]const f32{ &row0, &row1, &row2 };
//!
//! const diagram = ChordDiagram.init()
//!     .withNodes(&nodes)
//!     .withMatrix(&mat)
//!     .withShowLabels(true);
//!
//! diagram.render(&buf, area);
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

pub const ChordDiagram = struct {
    /// Maximum number of nodes
    pub const MAX_NODES: usize = 16;

    /// Node labels
    nodes: []const []const u8 = &.{},
    /// NxN flow matrix; matrix[i][j] is the flow from node i to node j
    matrix: []const []const f32 = &.{},
    /// Index of the focused node
    focused: usize = 0,
    /// Base style
    style: Style = .{},
    /// Style for chord (arc) lines
    arc_style: Style = .{},
    /// Style applied to the focused node marker and its chords
    focused_style: Style = .{},
    /// Whether to render node labels
    show_labels: bool = true,
    /// Optional block border
    block: ?Block = null,

    /// Initialize a ChordDiagram with all defaults
    pub fn init() ChordDiagram {
        return .{};
    }

    /// Effective node count (capped at MAX_NODES)
    pub fn nodeCount(self: ChordDiagram) usize {
        return @min(self.nodes.len, MAX_NODES);
    }

    /// Sum of all flows in the matrix (for valid node indices only)
    pub fn totalFlow(self: ChordDiagram) f32 {
        const n = self.nodeCount();
        var total: f32 = 0.0;
        for (0..n) |i| {
            if (i >= self.matrix.len) break;
            const row = self.matrix[i];
            for (0..n) |j| {
                if (j < row.len) {
                    total += row[j];
                }
            }
        }
        return total;
    }

    pub fn withNodes(self: ChordDiagram, nodes: []const []const u8) ChordDiagram {
        var result = self;
        result.nodes = nodes;
        return result;
    }

    pub fn withMatrix(self: ChordDiagram, matrix: []const []const f32) ChordDiagram {
        var result = self;
        result.matrix = matrix;
        return result;
    }

    pub fn withFocused(self: ChordDiagram, focused: usize) ChordDiagram {
        var result = self;
        result.focused = focused;
        return result;
    }

    pub fn withStyle(self: ChordDiagram, style: Style) ChordDiagram {
        var result = self;
        result.style = style;
        return result;
    }

    pub fn withArcStyle(self: ChordDiagram, arc_style: Style) ChordDiagram {
        var result = self;
        result.arc_style = arc_style;
        return result;
    }

    pub fn withFocusedStyle(self: ChordDiagram, focused_style: Style) ChordDiagram {
        var result = self;
        result.focused_style = focused_style;
        return result;
    }

    pub fn withShowLabels(self: ChordDiagram, show_labels: bool) ChordDiagram {
        var result = self;
        result.show_labels = show_labels;
        return result;
    }

    pub fn withBlock(self: ChordDiagram, blk: ?Block) ChordDiagram {
        var result = self;
        result.block = blk;
        return result;
    }

    /// Render the chord diagram to the buffer
    pub fn render(self: ChordDiagram, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (inner.width < 5 or inner.height < 5) return;

        const n = self.nodeCount();
        if (n == 0) return;

        // Geometry
        const cx = inner.x + inner.width / 2;
        const cy = inner.y + inner.height / 2;
        // Leave 2 cols/rows margin for labels
        const raw_rx = if (inner.width / 2 > 3) inner.width / 2 - 3 else 1;
        const raw_ry = if (inner.height / 2 > 2) inner.height / 2 - 2 else 1;
        const radius_x: u16 = raw_rx;
        const radius_y: u16 = raw_ry;

        // Pre-compute node positions on the ellipse
        var nx: [MAX_NODES]i32 = undefined;
        var ny: [MAX_NODES]i32 = undefined;
        for (0..n) |i| {
            const angle = 2.0 * math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) - math.pi / 2.0;
            nx[i] = @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(cx)) + @as(f32, @floatFromInt(radius_x)) * math.cos(angle))));
            ny[i] = @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(cy)) + @as(f32, @floatFromInt(radius_y)) * math.sin(angle))));
        }

        // Draw chords for non-zero flows
        for (0..n) |i| {
            if (i >= self.matrix.len) continue;
            const row = self.matrix[i];
            for (0..n) |j| {
                if (i == j) continue;
                if (j >= row.len) continue;
                if (row[j] <= 0.0) continue;

                const is_focused_chord = (i == self.focused or j == self.focused);
                const chord_style = if (is_focused_chord) self.focused_style else self.arc_style;
                drawLine(buf, inner, nx[i], ny[i], nx[j], ny[j], chord_style);
            }
        }

        // Draw node markers and labels on top of chords
        for (0..n) |i| {
            const is_focused = (i == self.focused);
            const node_style = if (is_focused) self.focused_style else self.style;
            const marker: u21 = if (is_focused) '◉' else '●';

            if (nx[i] >= 0 and ny[i] >= 0) {
                const px: u16 = @intCast(nx[i]);
                const py: u16 = @intCast(ny[i]);
                if (px >= inner.x and px < inner.x + inner.width and
                    py >= inner.y and py < inner.y + inner.height)
                {
                    buf.set(px, py, Cell.init(marker, node_style));
                }
            }

            // Draw label if enabled
            if (self.show_labels and i < self.nodes.len) {
                const label = self.nodes[i];
                if (label.len == 0) continue;

                const angle = 2.0 * math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) - math.pi / 2.0;
                const cos_a = math.cos(angle);
                const sin_a = math.sin(angle);

                var lx: i32 = nx[i];
                var ly: i32 = ny[i];

                // Offset label outward from the node marker
                if (cos_a > 0.3) {
                    lx += 2;
                } else if (cos_a < -0.3) {
                    lx -= @as(i32, @intCast(@min(label.len, 8))) + 1;
                } else {
                    lx -= @divTrunc(@as(i32, @intCast(@min(label.len, 8))), 2);
                }
                if (sin_a < -0.2) {
                    ly -= 1;
                } else if (sin_a > 0.2) {
                    ly += 1;
                }

                if (lx >= 0 and ly >= 0) {
                    const ulx: u16 = @intCast(lx);
                    const uly: u16 = @intCast(ly);
                    if (ulx < inner.x + inner.width and uly >= inner.y and uly < inner.y + inner.height) {
                        const max_len = @as(usize, inner.x + inner.width) -| @as(usize, ulx);
                        const display = label[0..@min(label.len, max_len)];
                        buf.setString(ulx, uly, display, node_style);
                    }
                }
            }
        }
    }

    /// Bresenham line drawing
    fn drawLine(buf: *Buffer, area: Rect, x0: i32, y0: i32, x1: i32, y1: i32, s: Style) void {
        const dx = @abs(x1 - x0);
        const dy = @abs(y1 - y0);
        const sx: i32 = if (x1 > x0) 1 else -1;
        const sy: i32 = if (y1 > y0) 1 else -1;
        var err: i32 = @as(i32, @intCast(dx)) - @as(i32, @intCast(dy));
        var x = x0;
        var y = y0;
        while (true) {
            if (x >= 0 and y >= 0) {
                const px: u16 = @intCast(x);
                const py: u16 = @intCast(y);
                if (px >= area.x and px < area.x + area.width and
                    py >= area.y and py < area.y + area.height)
                {
                    buf.set(px, py, Cell.init('·', s));
                }
            }
            if (x == x1 and y == y1) break;
            const e2 = 2 * err;
            if (e2 > -@as(i32, @intCast(dy))) {
                err -= @as(i32, @intCast(dy));
                x += sx;
            }
            if (e2 < @as(i32, @intCast(dx))) {
                err += @as(i32, @intCast(dx));
                y += sy;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ChordDiagram.init has empty nodes" {
    const cd = ChordDiagram.init();
    try std.testing.expectEqual(@as(usize, 0), cd.nodes.len);
}

test "ChordDiagram.init has empty matrix" {
    const cd = ChordDiagram.init();
    try std.testing.expectEqual(@as(usize, 0), cd.matrix.len);
}

test "ChordDiagram.init focused is 0" {
    const cd = ChordDiagram.init();
    try std.testing.expectEqual(@as(usize, 0), cd.focused);
}

test "ChordDiagram.init show_labels is true" {
    const cd = ChordDiagram.init();
    try std.testing.expectEqual(true, cd.show_labels);
}

test "ChordDiagram.init has no block" {
    const cd = ChordDiagram.init();
    try std.testing.expectEqual(@as(?Block, null), cd.block);
}

test "ChordDiagram.MAX_NODES is 16" {
    try std.testing.expectEqual(@as(usize, 16), ChordDiagram.MAX_NODES);
}

test "ChordDiagram.nodeCount empty nodes is 0" {
    const cd = ChordDiagram.init();
    try std.testing.expectEqual(@as(usize, 0), cd.nodeCount());
}

test "ChordDiagram.nodeCount with 2 nodes" {
    const nodes = [_][]const u8{ "A", "B" };
    const cd = ChordDiagram.init().withNodes(&nodes);
    try std.testing.expectEqual(@as(usize, 2), cd.nodeCount());
}

test "ChordDiagram.nodeCount caps at MAX_NODES" {
    var nodes: [20][]const u8 = undefined;
    for (0..20) |i| nodes[i] = "X";
    const cd = ChordDiagram.init().withNodes(&nodes);
    try std.testing.expectEqual(@as(usize, 16), cd.nodeCount());
}

test "ChordDiagram.totalFlow empty matrix is 0" {
    const cd = ChordDiagram.init();
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cd.totalFlow(), 0.001);
}

test "ChordDiagram.totalFlow 2x2 matrix" {
    const nodes = [_][]const u8{ "A", "B" };
    const row0 = [_]f32{ 0.0, 1.0 };
    const row1 = [_]f32{ 0.5, 0.0 };
    const mat = [_][]const f32{ &row0, &row1 };
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&mat);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), cd.totalFlow(), 0.001);
}

test "ChordDiagram.totalFlow only counts valid node rows" {
    const nodes = [_][]const u8{"A"};
    const row0 = [_]f32{ 0.0, 5.0 }; // row has more cols than nodes
    const row1 = [_]f32{ 3.0, 0.0 }; // this row exceeds node count
    const mat = [_][]const f32{ &row0, &row1 };
    // nodeCount=1, so only matrix[0][0..1] is considered, i.e. row0[0] = 0.0
    const cd = ChordDiagram.init().withNodes(&nodes).withMatrix(&mat);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cd.totalFlow(), 0.001);
}

test "ChordDiagram.withNodes is immutable" {
    const original = ChordDiagram.init();
    const nodes = [_][]const u8{ "A", "B" };
    const modified = original.withNodes(&nodes);
    try std.testing.expectEqual(@as(usize, 0), original.nodes.len);
    try std.testing.expectEqual(@as(usize, 2), modified.nodes.len);
}

test "ChordDiagram.withFocused is immutable" {
    const original = ChordDiagram.init();
    const modified = original.withFocused(3);
    try std.testing.expectEqual(@as(usize, 0), original.focused);
    try std.testing.expectEqual(@as(usize, 3), modified.focused);
}

test "ChordDiagram.withShowLabels is immutable" {
    const original = ChordDiagram.init();
    const modified = original.withShowLabels(false);
    try std.testing.expectEqual(true, original.show_labels);
    try std.testing.expectEqual(false, modified.show_labels);
}
