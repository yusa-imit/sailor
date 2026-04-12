//! Table widget — structured data display with headers, rows, and column alignment.
//!
//! Table renders tabular data with automatic column width calculation, headers,
//! row selection, and flexible alignment. It's ideal for displaying structured
//! data like logs, database results, or configuration lists.
//!
//! ## Features
//! - Column width constraints (fixed, percentage, min, max)
//! - Header row with optional styling
//! - Row selection highlighting
//! - Column alignment (left, center, right)
//! - Optional Block wrapper for borders and title
//! - Vertical scrolling for large datasets
//! - Automatic width distribution algorithm
//!
//! ## Usage
//! ```zig
//! const table = Table{
//!     .headers = &[_][]const u8{ "Name", "Age", "City" },
//!     .rows = &[_][]const []const u8{
//!         &[_][]const u8{ "Alice", "30", "NYC" },
//!         &[_][]const u8{ "Bob", "25", "LA" },
//!     },
//!     .widths = &[_]ColumnWidth{
//!         .{ .percentage = 40 },
//!         .{ .fixed = 10 },
//!         .{ .min = 15 },
//!     },
//! };
//! table.render(buf, area);
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

/// Column alignment
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Column width constraint
pub const ColumnWidth = union(enum) {
    /// Fixed width in characters
    fixed: u16,
    /// Percentage of available width (0-100)
    percentage: u8,
    /// Minimum width, grows to fill available space
    min: u16,
    /// Maximum width, shrinks if space limited
    max: u16,

    /// Create a fixed width column
    pub fn ofFixed(width: u16) ColumnWidth {
        return .{ .fixed = width };
    }

    /// Create a percentage width column
    pub fn ofPercentage(pct: u8) ColumnWidth {
        return .{ .percentage = @min(pct, 100) };
    }

    /// Create a minimum width column
    pub fn ofMin(width: u16) ColumnWidth {
        return .{ .min = width };
    }

    /// Create a maximum width column
    pub fn ofMax(width: u16) ColumnWidth {
        return .{ .max = width };
    }
};

/// Column definition
pub const Column = struct {
    title: []const u8,
    width: ColumnWidth = .{ .percentage = 100 },
    alignment: Alignment = .left,
};

/// Row data (array of strings)
pub const Row = []const []const u8;

/// Table widget - column-aligned data table with header and row selection
pub const Table = struct {
    columns: []const Column,
    rows: []const Row,
    selected: ?usize = null,
    offset: usize = 0,
    block: ?Block = null,
    header_style: Style = .{},
    row_style: Style = .{},
    selected_style: Style = .{},
    column_spacing: u16 = 1,

    /// Create a table with columns and rows
    pub fn init(columns: []const Column, rows: []const Row) Table {
        return .{ .columns = columns, .rows = rows };
    }

    /// Set the selected row index
    pub fn withSelected(self: Table, index: ?usize) Table {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set scroll offset
    pub fn withOffset(self: Table, new_offset: usize) Table {
        var result = self;
        result.offset = new_offset;
        return result;
    }

    /// Set the block (border) for this table
    pub fn withBlock(self: Table, new_block: Block) Table {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set header style
    pub fn withHeaderStyle(self: Table, new_style: Style) Table {
        var result = self;
        result.header_style = new_style;
        return result;
    }

    /// Set row style
    pub fn withRowStyle(self: Table, new_style: Style) Table {
        var result = self;
        result.row_style = new_style;
        return result;
    }

    /// Set selected row style
    pub fn withSelectedStyle(self: Table, new_style: Style) Table {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set column spacing (spaces between columns)
    pub fn withColumnSpacing(self: Table, spacing: u16) Table {
        var result = self;
        result.column_spacing = spacing;
        return result;
    }

    /// Calculate column widths based on available space into provided buffer
    fn calculateColumnWidths(self: Table, available_width: u16, widths_buf: []u16) void {
        // widths_buf must be at least self.columns.len long
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

    /// Render the table widget
    pub fn render(self: Table, buf: *Buffer, area: Rect) void {
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
        if (y < inner_area.y + inner_area.height) {
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

// ============================================================================
// Tests
// ============================================================================

test "ColumnWidth.ofFixed creates fixed width" {
    const width = ColumnWidth.ofFixed(20);
    try std.testing.expectEqual(@as(u16, 20), width.fixed);
}

test "ColumnWidth.ofPercentage creates percentage width" {
    const width = ColumnWidth.ofPercentage(50);
    try std.testing.expectEqual(@as(u8, 50), width.percentage);
}

test "ColumnWidth.ofPercentage clamps to 100" {
    const width = ColumnWidth.ofPercentage(150);
    try std.testing.expectEqual(@as(u8, 100), width.percentage);
}

test "ColumnWidth.ofMin creates min width" {
    const width = ColumnWidth.ofMin(10);
    try std.testing.expectEqual(@as(u16, 10), width.min);
}

test "ColumnWidth.ofMax creates max width" {
    const width = ColumnWidth.ofMax(30);
    try std.testing.expectEqual(@as(u16, 30), width.max);
}

test "Table.init creates table with columns and rows" {
    const columns = &[_]Column{
        .{ .title = "Name" },
        .{ .title = "Age" },
    };
    const rows = &[_]Row{
        &[_][]const u8{ "Alice", "30" },
        &[_][]const u8{ "Bob", "25" },
    };

    const table = Table.init(columns, rows);
    try std.testing.expectEqual(2, table.columns.len);
    try std.testing.expectEqual(2, table.rows.len);
    try std.testing.expectEqual(@as(?usize, null), table.selected);
}

test "Table.withSelected sets selected row" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const table = Table.init(columns, rows).withSelected(0);

    try std.testing.expectEqual(@as(?usize, 0), table.selected);
}

test "Table.withOffset sets scroll offset" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const table = Table.init(columns, rows).withOffset(1);

    try std.testing.expectEqual(@as(usize, 1), table.offset);
}

test "Table.withBlock sets block" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const block = (Block{});
    const table = Table.init(columns, rows).withBlock(block);

    try std.testing.expect(table.block != null);
}

test "Table.withHeaderStyle sets header style" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const style = Style{ .bold = true };
    const table = Table.init(columns, rows).withHeaderStyle(style);

    try std.testing.expectEqual(true, table.header_style.bold);
}

test "Table.withRowStyle sets row style" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const style = Style{ .italic = true };
    const table = Table.init(columns, rows).withRowStyle(style);

    try std.testing.expectEqual(true, table.row_style.italic);
}

test "Table.withSelectedStyle sets selected style" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const style = Style{ .underline = true };
    const table = Table.init(columns, rows).withSelectedStyle(style);

    try std.testing.expectEqual(true, table.selected_style.underline);
}

test "Table.withColumnSpacing sets spacing" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const table = Table.init(columns, rows).withColumnSpacing(3);

    try std.testing.expectEqual(@as(u16, 3), table.column_spacing);
}

test "Table.calculateColumnWidths with fixed widths" {
    const columns = &[_]Column{
        .{ .title = "A", .width = ColumnWidth.ofFixed(10) },
        .{ .title = "B", .width = ColumnWidth.ofFixed(15) },
    };
    const rows = &[_]Row{};
    const table = Table.init(columns, rows).withColumnSpacing(1);

    var widths: [2]u16 = undefined;
    table.calculateColumnWidths(30, &widths);
    try std.testing.expectEqual(@as(u16, 10), widths[0]);
    try std.testing.expectEqual(@as(u16, 15), widths[1]);
}

test "Table.calculateColumnWidths with percentage" {
    const columns = &[_]Column{
        .{ .title = "A", .width = ColumnWidth.ofPercentage(50) },
        .{ .title = "B", .width = ColumnWidth.ofPercentage(50) },
    };
    const rows = &[_]Row{};
    const table = Table.init(columns, rows).withColumnSpacing(0);

    var widths: [2]u16 = undefined;
    table.calculateColumnWidths(100, &widths);
    try std.testing.expectEqual(@as(u16, 50), widths[0]);
    try std.testing.expectEqual(@as(u16, 50), widths[1]);
}

test "Table.alignText left alignment" {
    const offset = Table.alignText("Hello", 10, .left);
    try std.testing.expectEqual(@as(u16, 0), offset);
}

test "Table.alignText center alignment" {
    const offset = Table.alignText("Hi", 10, .center);
    try std.testing.expectEqual(@as(u16, 4), offset); // (10 - 2) / 2
}

test "Table.alignText right alignment" {
    const offset = Table.alignText("Hi", 10, .right);
    try std.testing.expectEqual(@as(u16, 8), offset); // 10 - 2
}

test "Table.render empty area does nothing" {
    const columns = &[_]Column{.{ .title = "A" }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const table = Table.init(columns, rows);

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "Table.render with header only" {
    const columns = &[_]Column{
        .{ .title = "Name", .width = ColumnWidth.ofFixed(10) },
        .{ .title = "Age", .width = ColumnWidth.ofFixed(5) },
    };
    const rows = &[_]Row{};
    const table = Table.init(columns, rows).withColumnSpacing(1);

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    table.render(&buf, area);

    // Check header is rendered
    try std.testing.expectEqual(@as(u21, 'N'), buf.get(0, 0).?.char); // "Name"
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(11, 0).?.char); // "Age" (after spacing)
}

test "Table.render with data rows" {
    const columns = &[_]Column{
        .{ .title = "Name", .width = ColumnWidth.ofFixed(10) },
        .{ .title = "Age", .width = ColumnWidth.ofFixed(5) },
    };
    const rows = &[_]Row{
        &[_][]const u8{ "Alice", "30" },
        &[_][]const u8{ "Bob", "25" },
    };
    const table = Table.init(columns, rows).withColumnSpacing(1);

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    table.render(&buf, area);

    // Check first row
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 1).?.char); // "Alice"
    try std.testing.expectEqual(@as(u21, '3'), buf.get(11, 1).?.char); // "30"

    // Check second row
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(0, 2).?.char); // "Bob"
    try std.testing.expectEqual(@as(u21, '2'), buf.get(11, 2).?.char); // "25"
}

test "Table.render with selection" {
    const columns = &[_]Column{.{ .title = "Item", .width = ColumnWidth.ofFixed(10) }};
    const rows = &[_]Row{
        &[_][]const u8{"A"},
        &[_][]const u8{"B"},
    };
    const selected_style = Style{ .bold = true };
    const table = Table.init(columns, rows).withSelected(1).withSelectedStyle(selected_style);

    var buf = try Buffer.init(std.testing.allocator, 15, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    table.render(&buf, area);

    // Selected row should have bold style
    try std.testing.expectEqual(true, buf.get(0, 2).?.style.bold); // Row 1 (second data row)
}

test "Table.render with center alignment" {
    const columns = &[_]Column{
        .{ .title = "ID", .width = ColumnWidth.ofFixed(10), .alignment = .center },
    };
    const rows = &[_]Row{
        &[_][]const u8{"42"},
    };
    const table = Table.init(columns, rows);

    var buf = try Buffer.init(std.testing.allocator, 15, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    table.render(&buf, area);

    // "42" should be centered in 10-char column: offset = (10-2)/2 = 4
    try std.testing.expectEqual(@as(u21, '4'), buf.get(4, 1).?.char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(5, 1).?.char);
}

test "Table.render with right alignment" {
    const columns = &[_]Column{
        .{ .title = "Value", .width = ColumnWidth.ofFixed(10), .alignment = .right },
    };
    const rows = &[_]Row{
        &[_][]const u8{"99"},
    };
    const table = Table.init(columns, rows);

    var buf = try Buffer.init(std.testing.allocator, 15, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    table.render(&buf, area);

    // "99" should be right-aligned in 10-char column: offset = 10-2 = 8
    try std.testing.expectEqual(@as(u21, '9'), buf.get(8, 1).?.char);
    try std.testing.expectEqual(@as(u21, '9'), buf.get(9, 1).?.char);
}

test "Table.render with scrolling" {
    const columns = &[_]Column{.{ .title = "Item", .width = ColumnWidth.ofFixed(10) }};
    const rows = &[_]Row{
        &[_][]const u8{"A"},
        &[_][]const u8{"B"},
        &[_][]const u8{"C"},
        &[_][]const u8{"D"},
    };
    const table = Table.init(columns, rows).withOffset(2);

    var buf = try Buffer.init(std.testing.allocator, 15, 3);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 3 };
    table.render(&buf, area);

    // Should show header + row C (offset 2)
    try std.testing.expectEqual(@as(u21, 'I'), buf.get(0, 0).?.char); // Header
    try std.testing.expectEqual(@as(u21, 'C'), buf.get(0, 1).?.char); // Row 2
}

test "Table.render with block border" {
    const columns = &[_]Column{.{ .title = "A", .width = ColumnWidth.ofFixed(5) }};
    const rows = &[_]Row{&[_][]const u8{"1"}};
    const block = (Block{});
    const table = Table.init(columns, rows).withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    table.render(&buf, area);

    // Check border is rendered
    try std.testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Check header is inside border
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(1, 1).?.char);
}

test "Table.render with missing cells" {
    const columns = &[_]Column{
        .{ .title = "A", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "B", .width = ColumnWidth.ofFixed(5) },
    };
    const rows = &[_]Row{
        &[_][]const u8{"1"}, // Missing second column
    };
    const table = Table.init(columns, rows).withColumnSpacing(1);

    var buf = try Buffer.init(std.testing.allocator, 15, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    table.render(&buf, area);

    // Should handle missing cell gracefully (render as empty)
    try std.testing.expectEqual(@as(u21, '1'), buf.get(0, 1).?.char);
    // Second column should be spaces
    try std.testing.expectEqual(@as(u21, ' '), buf.get(6, 1).?.char);
}

// Memory Leak Tests

test "Table: render does not leak memory" {
    const columns = &[_]Column{
        .{ .title = "Name", .width = ColumnWidth.ofFixed(10) },
        .{ .title = "Age", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "City", .width = ColumnWidth.ofPercentage(30) },
    };
    const rows = &[_]Row{
        &[_][]const u8{ "Alice", "30", "NYC" },
        &[_][]const u8{ "Bob", "25", "LA" },
        &[_][]const u8{ "Charlie", "35", "SF" },
    };

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const table = Table.init(columns, rows);

    // Render multiple times - should not leak (all stack allocations)
    for (0..100) |_| {
        table.render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 10 });
    }
}

test "Table: render with many columns does not leak" {
    const columns = &[_]Column{
        .{ .title = "C1", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "C2", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "C3", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "C4", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "C5", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "C6", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "C7", .width = ColumnWidth.ofFixed(5) },
        .{ .title = "C8", .width = ColumnWidth.ofFixed(5) },
    };
    const rows = &[_]Row{
        &[_][]const u8{ "A", "B", "C", "D", "E", "F", "G", "H" },
    };

    var buf = try Buffer.init(std.testing.allocator, 50, 5);
    defer buf.deinit();

    const table = Table.init(columns, rows);

    // Render multiple times
    for (0..100) |_| {
        table.render(&buf, Rect{ .x = 0, .y = 0, .width = 50, .height = 5 });
    }
}

test "Table: render with large dataset does not leak" {
    const columns = &[_]Column{
        .{ .title = "ID", .width = ColumnWidth.ofFixed(8) },
        .{ .title = "Data", .width = ColumnWidth.ofPercentage(50) },
    };

    // Create 100 rows
    var rows_storage: [100]Row = undefined;
    var row_data: [100][2][]const u8 = undefined;
    for (0..100) |i| {
        row_data[i][0] = "ID";
        row_data[i][1] = "Data";
        rows_storage[i] = &row_data[i];
    }

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const table = Table.init(columns, &rows_storage);

    // Render with scrolling
    for (0..100) |offset| {
        table.withOffset(offset).render(&buf, Rect{ .x = 0, .y = 0, .width = 40, .height = 10 });
    }
}
