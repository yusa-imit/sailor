//! VirtualTable Widget — virtual-scrolling table for large datasets.
//!
//! VirtualTable renders tabular data with efficient scrolling for large datasets
//! by only rendering visible rows. It supports column width constraints, row
//! selection, and optional borders.
//!
//! ## Features
//! - Virtual scrolling (only visible rows rendered)
//! - Column width constraints (fixed, percentage, min, max)
//! - Header row with optional styling
//! - Row selection highlighting
//! - Column alignment (left, center, right)
//! - Optional Block wrapper for borders
//! - Efficient pagination methods (pageDown, pageUp)
//!
//! ## Usage
//! ```zig
//! const vt = VirtualTable.init(&columns)
//!     .withRows(&rows)
//!     .withSelected(0);
//! vt.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const table_mod = @import("table.zig");
const Alignment = table_mod.Alignment;
const ColumnWidth = table_mod.ColumnWidth;
const Column = table_mod.Column;

/// VirtualTable widget — virtual-scrolling table for large datasets
pub const VirtualTable = struct {
    columns: []const Column,
    rows: []const []const []const u8,
    selected: ?usize = null,
    offset: usize = 0,
    header_style: Style = .{},
    row_style: Style = .{},
    selected_style: Style = .{},
    column_spacing: u16 = 1,
    block: ?Block = null,

    /// Create a VirtualTable with columns (no rows initially)
    pub fn init(columns: []const Column) VirtualTable {
        return .{
            .columns = columns,
            .rows = &.{},
        };
    }

    /// Get the number of rows
    pub fn rowCount(self: VirtualTable) usize {
        return self.rows.len;
    }

    /// Get the currently selected row, or null if no selection
    pub fn selectedRow(self: VirtualTable) ?[]const []const u8 {
        if (self.selected) |sel| {
            if (sel < self.rows.len) {
                return self.rows[sel];
            }
        }
        return null;
    }

    /// Move selection to the next row
    pub fn selectNext(self: *VirtualTable) void {
        if (self.rows.len == 0) return;

        if (self.selected) |sel| {
            if (sel < self.rows.len - 1) {
                self.selected = sel + 1;
            }
            // else: stay at last row (clamped)
        } else {
            self.selected = 0;
        }

        // Ensure offset <= selected
        if (self.selected) |sel| {
            if (self.offset > sel) {
                self.offset = sel;
            }
        }
    }

    /// Move selection to the previous row
    pub fn selectPrev(self: *VirtualTable) void {
        if (self.rows.len == 0) return;

        if (self.selected) |sel| {
            if (sel > 0) {
                self.selected = sel - 1;
                if (self.offset > sel - 1) {
                    self.offset = sel - 1;
                }
            }
            // else: stay at 0
        }
        // if null: stay null
    }

    /// Scroll down by page_size rows
    pub fn pageDown(self: *VirtualTable, page_size: usize) void {
        if (page_size == 0) return;
        if (self.rows.len == 0) {
            self.offset = 0;
            return;
        }

        self.offset += page_size;
        self.offset = @min(self.offset, self.rows.len - 1);
    }

    /// Scroll up by page_size rows
    pub fn pageUp(self: *VirtualTable, page_size: usize) void {
        if (page_size == 0) return;
        self.offset = self.offset -| page_size;
    }

    /// Adjust offset so that selected row is visible within visible_rows
    pub fn scrollToSelected(self: *VirtualTable, visible_rows: usize) void {
        if (self.selected == null) return;

        const sel = self.selected.?;

        if (sel < self.offset) {
            self.offset = sel;
        } else if (visible_rows > 0 and sel >= self.offset + visible_rows) {
            self.offset = sel -| (visible_rows - 1);
        }
    }

    // ========================================================================
    // Builder API (immutable pattern)
    // ========================================================================

    /// Set rows (returns new VirtualTable)
    pub fn withRows(self: VirtualTable, rows: []const []const []const u8) VirtualTable {
        var result = self;
        result.rows = rows;
        return result;
    }

    /// Set columns (returns new VirtualTable)
    pub fn withColumns(self: VirtualTable, columns: []const Column) VirtualTable {
        var result = self;
        result.columns = columns;
        return result;
    }

    /// Set selected row index (returns new VirtualTable)
    pub fn withSelected(self: VirtualTable, selected: ?usize) VirtualTable {
        var result = self;
        result.selected = selected;
        return result;
    }

    /// Set scroll offset (returns new VirtualTable)
    pub fn withOffset(self: VirtualTable, offset: usize) VirtualTable {
        var result = self;
        result.offset = offset;
        return result;
    }

    /// Set header style (returns new VirtualTable)
    pub fn withHeaderStyle(self: VirtualTable, style: Style) VirtualTable {
        var result = self;
        result.header_style = style;
        return result;
    }

    /// Set row style (returns new VirtualTable)
    pub fn withRowStyle(self: VirtualTable, style: Style) VirtualTable {
        var result = self;
        result.row_style = style;
        return result;
    }

    /// Set selected row style (returns new VirtualTable)
    pub fn withSelectedStyle(self: VirtualTable, style: Style) VirtualTable {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Set column spacing (returns new VirtualTable)
    pub fn withColumnSpacing(self: VirtualTable, spacing: u16) VirtualTable {
        var result = self;
        result.column_spacing = spacing;
        return result;
    }

    /// Set block border (returns new VirtualTable)
    pub fn withBlock(self: VirtualTable, block: Block) VirtualTable {
        var result = self;
        result.block = block;
        return result;
    }

    // ========================================================================
    // Rendering
    // ========================================================================

    /// Calculate column widths based on available space
    fn calculateColumnWidths(self: VirtualTable, available_width: u16, widths_buf: []u16) void {
        if (widths_buf.len < self.columns.len) return;

        const spacing_total = if (self.columns.len > 0) (self.columns.len - 1) * self.column_spacing else 0;
        var remaining_width = available_width -| @as(u16, @intCast(spacing_total));

        // First pass: assign fixed and percentage widths
        var flex_columns: usize = 0;
        for (self.columns, 0..) |col, i| {
            switch (col.width) {
                .fixed => |w| {
                    widths_buf[i] = @min(w, remaining_width);
                    remaining_width -|= widths_buf[i];
                },
                .percentage => |pct| {
                    const w = (available_width * @as(u16, pct)) / 100;
                    widths_buf[i] = @min(w, remaining_width);
                    remaining_width -|= widths_buf[i];
                },
                .min => |min_w| {
                    widths_buf[i] = @min(min_w, remaining_width);
                    remaining_width -|= widths_buf[i];
                    flex_columns += 1;
                },
                .max => |max_w| {
                    widths_buf[i] = @min(max_w, remaining_width);
                    remaining_width -|= widths_buf[i];
                    flex_columns += 1;
                },
            }
        }

        // Second pass: distribute remaining space to flex columns
        if (flex_columns > 0 and remaining_width > 0) {
            const extra_per_col = remaining_width / @as(u16, @intCast(flex_columns));
            for (self.columns, 0..) |col, i| {
                switch (col.width) {
                    .min => widths_buf[i] += extra_per_col,
                    .max => |max_w| widths_buf[i] = @min(widths_buf[i] + extra_per_col, max_w),
                    else => {},
                }
            }
        }
    }

    /// Calculate x offset for text based on alignment
    fn alignText(text: []const u8, width: u16, alignment: Alignment) u16 {
        const text_len = @min(text.len, width);
        return switch (alignment) {
            .left => 0,
            .center => (width -| @as(u16, @intCast(text_len))) / 2,
            .right => width -| @as(u16, @intCast(text_len)),
        };
    }

    /// Render a cell at the given position
    fn renderCell(buf: *Buffer, x: u16, y: u16, text: []const u8, width: u16, alignment: Alignment, cell_style: Style) void {
        if (width == 0) return;

        const offset = alignText(text, width, alignment);
        var col: u16 = 0;

        // Fill with spaces before text (for center/right alignment)
        while (col < offset) : (col += 1) {
            buf.set(x + col, y, .{ .char = ' ', .style = cell_style });
        }

        // Render text
        var text_idx: usize = 0;
        while (col < width and text_idx < text.len) : (col += 1) {
            buf.set(x + col, y, .{ .char = text[text_idx], .style = cell_style });
            text_idx += 1;
        }

        // Fill remaining width with spaces
        while (col < width) : (col += 1) {
            buf.set(x + col, y, .{ .char = ' ', .style = cell_style });
        }
    }

    /// Render the VirtualTable widget
    pub fn render(self: VirtualTable, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Calculate column widths (max 16 columns supported)
        var widths: [16]u16 = undefined;
        if (self.columns.len > 16) return; // Too many columns
        self.calculateColumnWidths(inner_area.width, widths[0..self.columns.len]);

        var y = inner_area.y;

        // Render header
        if (self.columns.len > 0 and y < inner_area.y + inner_area.height) {
            var x = inner_area.x;
            for (self.columns, 0..) |col, i| {
                if (x >= inner_area.x + inner_area.width) break;
                renderCell(buf, x, y, col.title, widths[i], col.alignment, self.header_style);
                x += widths[i];
                if (i < self.columns.len - 1) x += self.column_spacing;
            }
            y += 1;
        }

        // Calculate visible rows
        const max_rows = inner_area.height -| 1; // Subtract header row
        if (max_rows == 0) return;

        const start_row = @min(self.offset, self.rows.len);
        const end_row = @min(start_row + max_rows, self.rows.len);

        // Render rows
        for (start_row..end_row) |row_idx| {
            if (y >= inner_area.y + inner_area.height) break;

            const is_selected = if (self.selected) |sel| row_idx == sel else false;
            const cell_style = if (is_selected) self.selected_style else self.row_style;

            const row = self.rows[row_idx];
            var x = inner_area.x;

            for (self.columns, 0..) |col, col_idx| {
                if (x >= inner_area.x + inner_area.width) break;

                const cell_text = if (col_idx < row.len) row[col_idx] else "";
                renderCell(buf, x, y, cell_text, widths[col_idx], col.alignment, cell_style);

                x += widths[col_idx];
                if (col_idx < self.columns.len - 1) x += self.column_spacing;
            }

            y += 1;
        }
    }
};
