//! StreamGraph Widget — theme river–style stacked area chart
//!
//! The StreamGraph widget displays multiple layers of data stacked around a
//! centered baseline (silhouette shape), commonly used to visualize flow or
//! composition over time. Layers are rendered symmetrically around a vertical
//! center line, filling both above and below the baseline.
//!
//! ## Features
//! - Up to 8 stacked layers (MAX_LAYERS)
//! - Vertical centering for silhouette effect
//! - Focused layer highlighting
//! - Optional label column on the right
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const layers = [_]StreamLayer{
//!     .{ .label = "A", .values = &values_a },
//!     .{ .label = "B", .values = &values_b },
//! };
//!
//! const chart = StreamGraph.init()
//!     .withLayers(&layers)
//!     .withShowLabels(true)
//!     .withFocused(0);
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

/// Single layer in a stream graph
pub const StreamLayer = struct {
    /// Label for the layer
    label: []const u8 = "",
    /// Data values (non-negative)
    values: []const f32 = &.{},
    /// Optional custom style for this layer
    style: Style = .{},
};

pub const StreamGraph = struct {
    /// Maximum number of layers (capped at 8 for rendering)
    pub const MAX_LAYERS: usize = 8;

    /// Array of layers to display
    layers: []const StreamLayer = &.{},
    /// Index of the focused layer for highlighting
    focused: usize = 0,
    /// Whether to render layer labels
    show_labels: bool = true,
    /// Base style applied to all layers
    style: Style = .{},
    /// Style for the focused layer
    focused_style: Style = .{},
    /// Style for layer labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a StreamGraph with all defaults
    pub fn init() StreamGraph {
        return .{};
    }

    /// Count of layers to render (capped at MAX_LAYERS)
    pub fn layerCount(self: StreamGraph) usize {
        return @min(self.layers.len, MAX_LAYERS);
    }

    /// Set layers array
    pub fn withLayers(self: StreamGraph, layers: []const StreamLayer) StreamGraph {
        var result = self;
        result.layers = layers;
        return result;
    }

    /// Set focused layer index
    pub fn withFocused(self: StreamGraph, idx: usize) StreamGraph {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: StreamGraph, show: bool) StreamGraph {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: StreamGraph, s: Style) StreamGraph {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: StreamGraph, s: Style) StreamGraph {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: StreamGraph, s: Style) StreamGraph {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: StreamGraph, b: ?Block) StreamGraph {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the stream graph to the buffer
    pub fn render(self: StreamGraph, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need minimum area to render
        if (inner.width == 0 or inner.height < 3) return;

        const n = self.layerCount();
        if (n == 0) return;

        // Find max number of data points across all layers
        var num_points: usize = 0;
        for (0..n) |i| {
            if (self.layers[i].values.len > num_points) {
                num_points = self.layers[i].values.len;
            }
        }
        if (num_points == 0) return;

        // Reserve label column if needed
        var chart_width = inner.width;
        var label_col_start: u16 = inner.x + inner.width;
        if (self.show_labels and inner.width >= 4) {
            chart_width = inner.width - 1;
            label_col_start = inner.x + chart_width;
        }

        if (chart_width == 0) return;

        // ========== Pass 1: Calculate max total across all columns ==========
        var max_total: f32 = 0.0;

        for (0..chart_width) |col_idx| {
            // Sample data point for this column
            const sample_idx = (col_idx * num_points) / chart_width;
            const sample_idx_clamped = @min(sample_idx, num_points - 1);

            // Sum all layer values at this sample index
            var col_total: f32 = 0.0;
            for (0..n) |layer_idx| {
                const value = if (sample_idx_clamped < self.layers[layer_idx].values.len)
                    self.layers[layer_idx].values[sample_idx_clamped]
                else
                    0.0;
                const clamped_value = @max(value, 0.0);
                col_total += clamped_value;
            }

            if (col_total > max_total) {
                max_total = col_total;
            }
        }

        // If all values are 0, no-op
        if (max_total <= 0.0) return;

        const center_row_f32: f32 = @as(f32, @floatFromInt(inner.y)) + @as(f32, @floatFromInt(inner.height)) / 2.0;
        const chart_height_f32: f32 = @floatFromInt(inner.height);
        const scale_factor: f32 = (chart_height_f32 - 1.0) / max_total;
        const inner_top: i32 = @intCast(inner.y);
        const inner_bottom: i32 = @intCast(inner.y + inner.height);

        // ========== Pass 2: Render columns ==========
        for (0..chart_width) |col_idx| {
            const x: u16 = @intCast(inner.x + col_idx);

            // Sample data point for this column
            const sample_idx = (col_idx * num_points) / chart_width;
            const sample_idx_clamped = @min(sample_idx, num_points - 1);

            // Collect layer values and compute stack heights
            var layer_heights: [MAX_LAYERS]f32 = undefined;
            var col_total: f32 = 0.0;

            for (0..n) |layer_idx| {
                const value = if (sample_idx_clamped < self.layers[layer_idx].values.len)
                    self.layers[layer_idx].values[sample_idx_clamped]
                else
                    0.0;
                const clamped_value = @max(value, 0.0);
                layer_heights[layer_idx] = clamped_value;
                col_total += clamped_value;
            }

            if (col_total <= 0.0) continue;

            // Silhouette stacking: the whole stack (sum of all layer bands) is
            // centered on center_row, with layers stacked in order from the
            // top of the stack downward. This keeps a single layer genuinely
            // centered (half above, half below), not anchored to one side.
            const total_rows_f32 = col_total * scale_factor;
            var row_cursor_f32: f32 = center_row_f32 - total_rows_f32 / 2.0;

            for (0..n) |layer_idx| {
                const layer_value = layer_heights[layer_idx];
                if (layer_value <= 0.0) continue;

                const layer_rows_f32: f32 = layer_value * scale_factor;
                const row_start: i32 = @intFromFloat(@round(row_cursor_f32));
                const row_end: i32 = @intFromFloat(@round(row_cursor_f32 + layer_rows_f32));
                row_cursor_f32 += layer_rows_f32;

                if (row_end <= row_start) continue;

                // Determine style
                var cell_style = self.layers[layer_idx].style;
                if (layer_idx == self.focused) {
                    cell_style = self.focused_style;
                }

                var y = row_start;
                while (y < row_end) : (y += 1) {
                    if (y >= inner_top and y < inner_bottom and y < @as(i32, @intCast(buf.height))) {
                        buf.set(x, @as(u16, @intCast(y)), Cell.init('█', cell_style));
                    }
                }
            }
        }

        // ========== Pass 3: Render labels if enabled ==========
        if (self.show_labels and chart_width < inner.width) {
            const max_label_rows = inner.height;
            const available_rows = @min(n, max_label_rows);

            for (0..available_rows) |layer_idx| {
                const label = self.layers[layer_idx].label;
                if (label.len == 0) continue;

                const label_row: u16 = @intCast(inner.y + layer_idx);

                // Determine label style
                var lbl_style = self.label_style;
                if (layer_idx == self.focused) {
                    lbl_style = self.focused_style;
                }

                // Write label
                const available_width = if (label_col_start < inner.x + inner.width)
                    inner.x + inner.width - label_col_start
                else
                    0;
                const label_len = @min(label.len, available_width);
                if (label_len > 0 and label_col_start < buf.width) {
                    buf.setString(label_col_start, label_row, label[0..label_len], lbl_style);
                }
            }
        }
    }
};
