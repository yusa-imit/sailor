//! MatrixView Widget — 2D Matrix Heatmap Visualization
//!
//! MatrixView displays a 2D matrix of floating-point values as a heatmap,
//! with optional row and column headers, configurable cell width, and
//! focused cell highlighting.
//!
//! ## Features
//! - 2D matrix visualization (up to 32x32 cells)
//! - Row and column headers with custom styling
//! - Focused cell highlighting
//! - Customizable value display and normalization
//! - Optional block borders
//! - Builder pattern for easy configuration
//!
//! ## Usage
//! ```zig
//! var data = [_][3]f32{
//!     .{ 0.1, 0.5, 0.9 },
//!     .{ 0.2, 0.6, 0.8 },
//! };
//! var data_ptrs = [_][]const f32{ &data[0], &data[1] };
//!
//! const mv = MatrixView.init()
//!     .withData(&data_ptrs)
//!     .withMinVal(0.0)
//!     .withMaxVal(1.0)
//!     .withCellWidth(6)
//!     .withShowValues(true);
//!
//! mv.render(&buf, area);
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

pub const MatrixView = struct {
    pub const MAX_ROWS: usize = 32;
    pub const MAX_COLS: usize = 32;

    data: []const []const f32 = &.{},
    row_headers: []const []const u8 = &.{},
    col_headers: []const []const u8 = &.{},
    focused_row: usize = 0,
    focused_col: usize = 0,
    min_val: f32 = 0.0,
    max_val: f32 = 1.0,
    cell_width: u16 = 6,
    show_values: bool = true,
    style: Style = .{},
    header_style: Style = .{},
    focused_style: Style = .{},
    block: ?Block = null,

    /// Initialize a new MatrixView with default values
    pub fn init() MatrixView {
        return .{};
    }

    /// Return the number of rows to render (capped at MAX_ROWS)
    pub fn rowCount(self: MatrixView) usize {
        return @min(self.data.len, MAX_ROWS);
    }

    /// Return the maximum column count across all rows (capped at MAX_COLS)
    pub fn colCount(self: MatrixView) usize {
        var max_cols: usize = 0;
        const rows = self.rowCount();
        for (0..rows) |i| {
            max_cols = @max(max_cols, self.data[i].len);
        }
        return @min(max_cols, MAX_COLS);
    }

    /// Set data (builder pattern)
    pub fn withData(self: MatrixView, data: []const []const f32) MatrixView {
        var result = self;
        result.data = data;
        return result;
    }

    /// Set row headers (builder pattern)
    pub fn withRowHeaders(self: MatrixView, headers: []const []const u8) MatrixView {
        var result = self;
        result.row_headers = headers;
        return result;
    }

    /// Set column headers (builder pattern)
    pub fn withColHeaders(self: MatrixView, headers: []const []const u8) MatrixView {
        var result = self;
        result.col_headers = headers;
        return result;
    }

    /// Set focused row index (builder pattern)
    pub fn withFocusedRow(self: MatrixView, row: usize) MatrixView {
        var result = self;
        result.focused_row = row;
        return result;
    }

    /// Set focused column index (builder pattern)
    pub fn withFocusedCol(self: MatrixView, col: usize) MatrixView {
        var result = self;
        result.focused_col = col;
        return result;
    }

    /// Set minimum value for normalization (builder pattern)
    pub fn withMinVal(self: MatrixView, min_val: f32) MatrixView {
        var result = self;
        result.min_val = min_val;
        return result;
    }

    /// Set maximum value for normalization (builder pattern)
    pub fn withMaxVal(self: MatrixView, max_val: f32) MatrixView {
        var result = self;
        result.max_val = max_val;
        return result;
    }

    /// Set cell width in characters (builder pattern)
    pub fn withCellWidth(self: MatrixView, cell_width: u16) MatrixView {
        var result = self;
        result.cell_width = cell_width;
        return result;
    }

    /// Set whether to show numeric values (builder pattern)
    pub fn withShowValues(self: MatrixView, show_values: bool) MatrixView {
        var result = self;
        result.show_values = show_values;
        return result;
    }

    /// Set base style (builder pattern)
    pub fn withStyle(self: MatrixView, style: Style) MatrixView {
        var result = self;
        result.style = style;
        return result;
    }

    /// Set header style (builder pattern)
    pub fn withHeaderStyle(self: MatrixView, header_style: Style) MatrixView {
        var result = self;
        result.header_style = header_style;
        return result;
    }

    /// Set focused cell style (builder pattern)
    pub fn withFocusedStyle(self: MatrixView, focused_style: Style) MatrixView {
        var result = self;
        result.focused_style = focused_style;
        return result;
    }

    /// Set optional block border (builder pattern)
    pub fn withBlock(self: MatrixView, block: ?Block) MatrixView {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render the matrix view to the buffer
    pub fn render(self: MatrixView, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block border if present
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner_area = block.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Determine header sizes
        const has_row_headers = self.row_headers.len > 0;
        const row_header_width: u16 = if (has_row_headers) 8 else 0;
        const has_col_headers = self.col_headers.len > 0;
        const col_header_height: u16 = if (has_col_headers) 1 else 0;

        // Fill background with base style
        buf.fill(inner_area, ' ', self.style);

        // Draw column headers if present
        if (has_col_headers) {
            var j: usize = 0;
            while (j < self.colCount()) : (j += 1) {
                const x = inner_area.x + row_header_width + @as(u16, @intCast(j)) * self.cell_width;
                if (x + self.cell_width > inner_area.x + inner_area.width) break;

                const header_text = if (j < self.col_headers.len) self.col_headers[j] else "";
                centerText(header_text, self.cell_width, buf, x, inner_area.y, self.header_style);
            }
        }

        // Draw row headers if present
        if (has_row_headers) {
            var i: usize = 0;
            while (i < self.rowCount()) : (i += 1) {
                const y = inner_area.y + col_header_height + @as(u16, @intCast(i));
                if (y >= inner_area.y + inner_area.height) break;

                const header_text = if (i < self.row_headers.len) self.row_headers[i] else "";
                // Left-align row headers and truncate to row_header_width
                const text_len = @min(header_text.len, @as(usize, row_header_width));
                if (text_len > 0) {
                    buf.setString(inner_area.x, y, header_text[0..text_len], self.header_style);
                }
            }
        }

        // Draw cells
        var i: usize = 0;
        while (i < self.rowCount()) : (i += 1) {
            const y = inner_area.y + col_header_height + @as(u16, @intCast(i));
            if (y >= inner_area.y + inner_area.height) break;

            const row_data = self.data[i];
            var j: usize = 0;
            while (j < self.colCount()) : (j += 1) {
                const x = inner_area.x + row_header_width + @as(u16, @intCast(j)) * self.cell_width;
                if (x + self.cell_width > inner_area.x + inner_area.width) break;

                const val = if (j < row_data.len) row_data[j] else 0.0;
                const is_focused = (i == self.focused_row and j == self.focused_col);
                const cell_style = if (is_focused) self.focused_style else self.style;

                // Fill cell area with background
                var cy = y;
                while (cy < @min(y + 1, inner_area.y + inner_area.height)) : (cy += 1) {
                    var cx = x;
                    while (cx < @min(x + self.cell_width, inner_area.x + inner_area.width)) : (cx += 1) {
                        buf.set(cx, cy, Cell{ .char = ' ', .style = cell_style });
                    }
                }

                // Draw value if show_values is enabled
                if (self.show_values) {
                    var val_buf: [16]u8 = undefined;
                    const val_str = std.fmt.bufPrint(&val_buf, "{d:.3}", .{val}) catch "?";
                    centerText(val_str, self.cell_width, buf, x, y, cell_style);
                }
            }
        }
    }
};

/// Helper function to center text within a width
fn centerText(text: []const u8, width: u16, buf: *Buffer, x: u16, y: u16, cell_style: Style) void {
    if (text.len == 0 or width == 0) return;

    const text_len = @min(text.len, @as(usize, width));
    const trimmed = text[0..text_len];
    const padding = if (@as(usize, width) > text_len) (@as(usize, width) - text_len) / 2 else 0;
    const draw_x = x + @as(u16, @intCast(padding));

    buf.setString(draw_x, y, trimmed, cell_style);
}

// ============================================================================
// Tests
// ============================================================================

test "MatrixView: init returns zero-value struct" {
    const std_test = @import("std").testing;
    const mv = MatrixView.init();
    try std_test.expectEqual(@as(usize, 0), mv.data.len);
    try std_test.expectEqual(@as(usize, 0), mv.row_headers.len);
    try std_test.expectEqual(@as(usize, 0), mv.col_headers.len);
}

test "MatrixView: init defaults focused_row and focused_col to 0" {
    const std_test = @import("std").testing;
    const mv = MatrixView.init();
    try std_test.expectEqual(@as(usize, 0), mv.focused_row);
    try std_test.expectEqual(@as(usize, 0), mv.focused_col);
}

test "MatrixView: init defaults min_val to 0.0 and max_val to 1.0" {
    const std_test = @import("std").testing;
    const mv = MatrixView.init();
    try std_test.expectApproxEqAbs(@as(f32, 0.0), mv.min_val, 0.001);
    try std_test.expectApproxEqAbs(@as(f32, 1.0), mv.max_val, 0.001);
}

test "MatrixView: init defaults cell_width to 6" {
    const std_test = @import("std").testing;
    const mv = MatrixView.init();
    try std_test.expectEqual(@as(u16, 6), mv.cell_width);
}

test "MatrixView: init defaults show_values to true and block to null" {
    const std_test = @import("std").testing;
    const mv = MatrixView.init();
    try std_test.expectEqual(true, mv.show_values);
    try std_test.expect(mv.block == null);
}

test "MatrixView.rowCount returns 0 for empty data" {
    const std_test = @import("std").testing;
    const mv = MatrixView.init();
    try std_test.expectEqual(@as(usize, 0), mv.rowCount());
}

test "MatrixView.rowCount returns 1 for single row" {
    const std_test = @import("std").testing;
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    try std_test.expectEqual(@as(usize, 1), mv.rowCount());
}

test "MatrixView.rowCount returns correct count for multiple rows" {
    const std_test = @import("std").testing;
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9 };
    var row3 = [_]f32{ 0.1, 0.2 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data);
    try std_test.expectEqual(@as(usize, 3), mv.rowCount());
}

test "MatrixView.rowCount caps at MAX_ROWS (32)" {
    const std_test = @import("std").testing;
    var rows: [33][5]f32 = undefined;
    var data_ptrs: [33][]const f32 = undefined;
    for (&data_ptrs, &rows) |*ptr, *row| {
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    try std_test.expectEqual(MatrixView.MAX_ROWS, mv.rowCount());
}

test "MatrixView.colCount returns 0 for empty data" {
    const std_test = @import("std").testing;
    const mv = MatrixView.init();
    try std_test.expectEqual(@as(usize, 0), mv.colCount());
}

test "MatrixView.colCount returns 1 for single column" {
    const std_test = @import("std").testing;
    var row1 = [_]f32{0.5};
    var row2 = [_]f32{0.75};
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init().withData(&data);
    try std_test.expectEqual(@as(usize, 1), mv.colCount());
}

test "MatrixView.colCount returns max column count across rows" {
    const std_test = @import("std").testing;
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9, 0.1 };
    var row3 = [_]f32{ 0.2 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data);
    try std_test.expectEqual(@as(usize, 3), mv.colCount());
}

test "MatrixView.colCount caps at MAX_COLS (32)" {
    const std_test = @import("std").testing;
    var large_row: [33]f32 = undefined;
    @memset(&large_row, 0.5);
    var data = [_][]const f32{&large_row};
    const mv = MatrixView.init().withData(&data);
    try std_test.expectEqual(MatrixView.MAX_COLS, mv.colCount());
}
