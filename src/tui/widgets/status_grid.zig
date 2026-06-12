//! StatusGrid Widget — Status Grid with Navigation & Selection
//!
//! A widget that displays an N×M grid of status cells with:
//! - Status-based color coding (ok, warn, error_, unknown)
//! - Cursor-based navigation (moveUp/Down/Left/Right)
//! - Selection highlighting with reverse style
//! - Optional value display below labels
//! - Customizable styling for each status level
//! - Optional block border

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Status level for a cell — determines color and styling
pub const StatusLevel = enum {
    ok,
    warn,
    error_,
    unknown,

    /// Get the default color for this status level
    pub fn color(self: StatusLevel) Color {
        return switch (self) {
            .ok => .green,
            .warn => .yellow,
            .error_ => .red,
            .unknown => .bright_black,
        };
    }
};

/// A single cell in the status grid
pub const StatusCell = struct {
    label: []const u8,
    value: []const u8 = "",
    status: StatusLevel = .unknown,
};

/// StatusGrid widget — displays N×M grid of status cells
pub const StatusGrid = struct {
    cells: []StatusCell,
    rows: usize,
    cols: usize,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    show_values: bool = false,
    block: ?Block = null,
    cell_style: Style = .{},
    ok_style: Style = .{ .fg = .green },
    warn_style: Style = .{ .fg = .yellow },
    error_style: Style = .{ .fg = .red },
    unknown_style: Style = .{ .fg = .bright_black },

    /// Initialize a new status grid with cells, rows, and columns
    pub fn init(cells: []StatusCell, rows: usize, cols: usize) StatusGrid {
        return StatusGrid{
            .cells = cells,
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .show_values = false,
            .block = null,
            .cell_style = .{},
            .ok_style = .{ .fg = .green },
            .warn_style = .{ .fg = .yellow },
            .error_style = .{ .fg = .red },
            .unknown_style = .{ .fg = .bright_black },
        };
    }

    /// Move cursor up one row (clamped to 0)
    pub fn moveUp(self: *StatusGrid) void {
        if (self.rows == 0) return;
        if (self.cursor_row > 0) {
            self.cursor_row -= 1;
        }
    }

    /// Move cursor down one row (clamped to rows-1)
    pub fn moveDown(self: *StatusGrid) void {
        if (self.rows == 0) return;
        if (self.cursor_row < self.rows - 1) {
            self.cursor_row += 1;
        }
    }

    /// Move cursor left one column (clamped to 0)
    pub fn moveLeft(self: *StatusGrid) void {
        if (self.cols == 0) return;
        if (self.cursor_col > 0) {
            self.cursor_col -= 1;
        }
    }

    /// Move cursor right one column (clamped to cols-1)
    pub fn moveRight(self: *StatusGrid) void {
        if (self.cols == 0) return;
        if (self.cursor_col < self.cols - 1) {
            self.cursor_col += 1;
        }
    }

    /// Get pointer to the selected cell (null if empty or out of bounds)
    pub fn selectedCell(self: *StatusGrid) ?*StatusCell {
        // Check bounds
        if (self.cursor_row >= self.rows or self.cursor_col >= self.cols) return null;
        if (self.cells.len == 0) return null;

        // Calculate linear index: row * cols + col
        const index = self.cursor_row * self.cols + self.cursor_col;
        if (index >= self.cells.len) return null;

        return &self.cells[index];
    }

    /// Builder: set block border
    pub fn withBlock(self: StatusGrid, block: Block) StatusGrid {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set cell style
    pub fn withCellStyle(self: StatusGrid, style: Style) StatusGrid {
        var result = self;
        result.cell_style = style;
        return result;
    }

    /// Builder: set ok status style
    pub fn withOkStyle(self: StatusGrid, style: Style) StatusGrid {
        var result = self;
        result.ok_style = style;
        return result;
    }

    /// Builder: set warn status style
    pub fn withWarnStyle(self: StatusGrid, style: Style) StatusGrid {
        var result = self;
        result.warn_style = style;
        return result;
    }

    /// Builder: set error status style
    pub fn withErrorStyle(self: StatusGrid, style: Style) StatusGrid {
        var result = self;
        result.error_style = style;
        return result;
    }

    /// Builder: set unknown status style
    pub fn withUnknownStyle(self: StatusGrid, style: Style) StatusGrid {
        var result = self;
        result.unknown_style = style;
        return result;
    }

    /// Builder: enable/disable value display
    pub fn withShowValues(self: StatusGrid, show: bool) StatusGrid {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Render the status grid to the buffer
    pub fn render(self: *StatusGrid, buf: *Buffer, area: Rect) void {
        // Early return for zero-area
        if (area.width == 0 or area.height == 0) return;

        var content_area = area;

        // Handle block border if present
        if (self.block) |block| {
            block.render(buf, area);
            // Shrink content area by 1 each side
            if (content_area.x + 1 >= content_area.x + content_area.width or
                content_area.y + 1 >= content_area.y + content_area.height)
            {
                return; // Content area too small
            }
            content_area.x += 1;
            content_area.y += 1;
            if (content_area.width >= 2) content_area.width -= 2;
            if (content_area.height >= 2) content_area.height -= 2;
            if (content_area.width == 0 or content_area.height == 0) return;
        }

        // Early return if grid is empty
        if (self.rows == 0 or self.cols == 0) return;

        // Calculate cell dimensions
        const cell_width = content_area.width / @as(u16, @intCast(self.cols));
        const cell_height = content_area.height / @as(u16, @intCast(self.rows));

        // Early return if cells are too small
        if (cell_width == 0 or cell_height == 0) return;

        // Render each cell
        var row: usize = 0;
        while (row < self.rows) : (row += 1) {
            var col: usize = 0;
            while (col < self.cols) : (col += 1) {
                const cell_index = row * self.cols + col;
                if (cell_index >= self.cells.len) continue;

                // Calculate cell position
                const cell_x = content_area.x + @as(u16, @intCast(col)) * cell_width;
                const cell_y = content_area.y + @as(u16, @intCast(row)) * cell_height;

                // Get cell data
                const cell_data = &self.cells[cell_index];

                // Determine style based on status
                var style = self.statusStyle(cell_data.status);

                // Merge with cell_style if provided
                if (self.cell_style.bold) style.bold = true;
                if (self.cell_style.dim) style.dim = true;
                if (self.cell_style.italic) style.italic = true;
                if (self.cell_style.underline) style.underline = true;
                if (self.cell_style.blink) style.blink = true;
                if (self.cell_style.strikethrough) style.strikethrough = true;
                if (self.cell_style.fg != null and std.meta.activeTag(self.cell_style.fg.?) == .reset) {
                    style.fg = self.cell_style.fg;
                }

                // Check if this is the selected cell
                const is_selected = (row == self.cursor_row and col == self.cursor_col);
                if (is_selected) {
                    style.reverse = true;
                }

                // Render label on first row of cell
                if (cell_height > 0 and cell_data.label.len > 0) {
                    buf.setString(cell_x, cell_y, cell_data.label, style);
                }

                // Render value on second row if enabled
                if (self.show_values and cell_height >= 2 and cell_data.value.len > 0) {
                    buf.setString(cell_x, cell_y + 1, cell_data.value, style);
                }
            }
        }
    }

    // ========== Private Helpers ==========

    /// Get the style for a given status level
    fn statusStyle(self: *StatusGrid, level: StatusLevel) Style {
        return switch (level) {
            .ok => self.ok_style,
            .warn => self.warn_style,
            .error_ => self.error_style,
            .unknown => self.unknown_style,
        };
    }
};
