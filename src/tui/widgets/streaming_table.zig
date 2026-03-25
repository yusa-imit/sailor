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

/// Streaming Table widget - efficient table rendering for massive row counts
/// Only renders visible rows, uses callbacks for lazy row loading
pub const StreamingTable = struct {
    /// Column definitions
    columns: []const Column,
    /// Total number of rows (can be massive, e.g., 1M+)
    total_rows: usize,
    /// Selected row index
    selected: ?usize = null,
    /// Scroll offset (index of first visible row)
    offset: usize = 0,
    /// Optional block (border)
    block: ?Block = null,
    /// Style for header row
    header_style: Style = .{},
    /// Style for unselected rows
    row_style: Style = .{},
    /// Style for selected row
    selected_style: Style = .{},
    /// Column spacing (spaces between columns)
    column_spacing: u16 = 1,

    /// Callback type for fetching row cells
    /// Takes row index, column index, and writer
    /// Should write cell text to writer
    pub const CellCallback = *const fn (row_index: usize, col_index: usize, writer: anytype) anyerror!void;

    /// Create a streaming table with columns and total row count
    pub fn init(columns: []const Column, total: usize) StreamingTable {
        return .{ .columns = columns, .total_rows = total };
    }

    /// Set selected row
    pub fn withSelected(self: StreamingTable, index: ?usize) StreamingTable {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set scroll offset
    pub fn withOffset(self: StreamingTable, new_offset: usize) StreamingTable {
        var result = self;
        result.offset = new_offset;
        return result;
    }

    /// Set block
    pub fn withBlock(self: StreamingTable, new_block: Block) StreamingTable {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set header style
    pub fn withHeaderStyle(self: StreamingTable, new_style: Style) StreamingTable {
        var result = self;
        result.header_style = new_style;
        return result;
    }

    /// Set row style
    pub fn withRowStyle(self: StreamingTable, new_style: Style) StreamingTable {
        var result = self;
        result.row_style = new_style;
        return result;
    }

    /// Set selected style
    pub fn withSelectedStyle(self: StreamingTable, new_style: Style) StreamingTable {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set column spacing
    pub fn withColumnSpacing(self: StreamingTable, spacing: u16) StreamingTable {
        var result = self;
        result.column_spacing = spacing;
        return result;
    }

    /// Calculate visible row range based on viewport height
    fn visibleRange(self: StreamingTable, height: u16, has_header: bool) struct { start: usize, end: usize } {
        const header_rows: u16 = if (has_header) 1 else 0;
        const available_height = if (height > header_rows) height - header_rows else 0;
        const max_rows = @min(self.total_rows, available_height);

        // Auto-scroll to keep selected row visible
        if (self.selected) |sel| {
            var start = self.offset;
            var end = start + max_rows;

            // Selected is below viewport - scroll down
            if (sel >= end) {
                start = sel - max_rows + 1;
                end = sel + 1;
            }
            // Selected is above viewport - scroll up
            else if (sel < start) {
                start = sel;
                end = sel + max_rows;
            }

            // Clamp to bounds
            if (end > self.total_rows) {
                end = self.total_rows;
                start = if (self.total_rows >= max_rows) self.total_rows - max_rows else 0;
            }

            return .{ .start = start, .end = end };
        }

        // No selection - use offset
        const start = @min(self.offset, self.total_rows);
        const end = @min(start + max_rows, self.total_rows);
        return .{ .start = start, .end = end };
    }

    /// Calculate column widths based on available space
    fn calculateColumnWidths(self: StreamingTable, available_width: u16, widths_buf: []u16) void {
        if (widths_buf.len < self.columns.len) return;

        const spacing_total = if (self.columns.len > 0) (self.columns.len - 1) * self.column_spacing else 0;
        var remaining_width = available_width -| @as(u16, @intCast(spacing_total));

        // First pass: fixed and percentage widths
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

        // Second pass: distribute remaining width to flex columns
        if (flex_columns > 0 and remaining_width > 0) {
            const extra_per_col = remaining_width / @as(u16, @intCast(flex_columns));
            for (self.columns, 0..) |col, i| {
                switch (col.width) {
                    .min, .max => {
                        widths_buf[i] += extra_per_col;
                    },
                    else => {},
                }
            }
        }
    }

    /// Render header row
    fn renderHeader(self: StreamingTable, buf: *Buffer, render_area: Rect, widths: []const u16) void {
        var x: u16 = render_area.x;
        for (self.columns, 0..) |col, i| {
            if (i >= widths.len) break;
            const col_width = widths[i];
            if (x >= render_area.x + render_area.width) break;

            // Truncate or pad header text
            var header_buf: [256]u8 = undefined;
            const header_text = if (col.title.len > col_width)
                col.title[0..col_width]
            else blk: {
                @memcpy(header_buf[0..col.title.len], col.title);
                if (col.title.len < col_width) {
                    @memset(header_buf[col.title.len..col_width], ' ');
                }
                break :blk header_buf[0..col_width];
            };

            buf.setString(x, render_area.y, header_text, self.header_style) catch {};
            x += col_width;
            if (i < self.columns.len - 1) {
                x += self.column_spacing;
            }
        }
    }

    /// Render a single row using callback
    fn renderRow(
        self: StreamingTable,
        buf: *Buffer,
        render_area: Rect,
        y: u16,
        row_index: usize,
        widths: []const u16,
        comptime callback: CellCallback,
        allocator: std.mem.Allocator,
    ) !void {
        const is_selected = if (self.selected) |sel| sel == row_index else false;
        const style = if (is_selected) self.selected_style else self.row_style;

        var x: u16 = render_area.x;
        for (0..self.columns.len) |col_idx| {
            if (col_idx >= widths.len) break;
            const col_width = widths[col_idx];
            if (x >= render_area.x + render_area.width) break;

            // Fetch cell text via callback
            var cell_buf = std.ArrayList(u8).init(allocator);
            defer cell_buf.deinit();

            try callback(row_index, col_idx, cell_buf.writer());

            // Apply column alignment
            const col = self.columns[col_idx];
            const cell_text = blk: {
                if (cell_buf.items.len > col_width) {
                    // Truncate if too long
                    break :blk cell_buf.items[0..col_width];
                } else if (cell_buf.items.len < col_width) {
                    // Pad to column width based on alignment
                    const padding_needed = col_width - cell_buf.items.len;
                    switch (col.alignment) {
                        .left => {
                            try cell_buf.appendNTimes(' ', padding_needed);
                        },
                        .right => {
                            try cell_buf.insertSlice(0, &[_]u8{' '} ** 1);
                            for (1..padding_needed) |_| {
                                try cell_buf.insert(0, ' ');
                            }
                        },
                        .center => {
                            const left_pad = padding_needed / 2;
                            const right_pad = padding_needed - left_pad;
                            for (0..left_pad) |_| {
                                try cell_buf.insert(0, ' ');
                            }
                            try cell_buf.appendNTimes(' ', right_pad);
                        },
                    }
                    break :blk cell_buf.items;
                } else {
                    break :blk cell_buf.items;
                }
            };

            buf.setString(x, y, cell_text, style) catch {};
            x += col_width;
            if (col_idx < self.columns.len - 1) {
                x += self.column_spacing;
            }
        }
    }

    /// Render streaming table using callback to fetch cells on-demand
    pub fn render(
        self: StreamingTable,
        buf: *Buffer,
        area: Rect,
        comptime callback: CellCallback,
        allocator: std.mem.Allocator,
    ) !void {
        var render_area = area;

        // Render block if present
        if (self.block) |b| {
            b.render(buf, area);
            render_area = b.inner(area);
        }

        if (render_area.height == 0 or render_area.width == 0) return;

        // Calculate column widths
        var widths_buf: [32]u16 = undefined;
        if (self.columns.len > widths_buf.len) return error.TooManyColumns;
        const widths = widths_buf[0..self.columns.len];
        self.calculateColumnWidths(render_area.width, widths);

        // Render header
        self.renderHeader(buf, render_area, widths);

        // Calculate visible row range
        const range = self.visibleRange(render_area.height, true);

        // Render visible rows
        var y: u16 = 1; // Start after header
        for (range.start..range.end) |row_idx| {
            if (y >= render_area.height) break;
            try self.renderRow(
                buf,
                render_area,
                render_area.y + y,
                row_idx,
                widths,
                callback,
                allocator,
            );
            y += 1;
        }
    }

    /// Convenience render for slice-based rows (wraps callback)
    pub fn renderSlice(
        self: StreamingTable,
        buf: *Buffer,
        area: Rect,
        rows: []const []const []const u8,
        allocator: std.mem.Allocator,
    ) !void {
        const Ctx = struct {
            rows_ptr: []const []const []const u8,
            fn cb(row_index: usize, col_index: usize, writer: anytype) !void {
                if (row_index < @This().rows_ptr.len) {
                    const row = @This().rows_ptr[row_index];
                    if (col_index < row.len) {
                        try writer.writeAll(row[col_index]);
                    }
                }
            }
        };
        Ctx.rows_ptr = rows;
        try self.render(buf, area, Ctx.cb, allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "StreamingTable.init creates table with columns and row count" {
    const cols = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 10 } },
        .{ .title = "Name", .width = .{ .percentage = 50 } },
    };
    const table = StreamingTable.init(&cols, 1_000_000);

    try testing.expectEqual(@as(usize, 1_000_000), table.total_rows);
    try testing.expectEqual(@as(usize, 2), table.columns.len);
    try testing.expectEqual(@as(?usize, null), table.selected);
}

test "StreamingTable.visibleRange calculates viewport slice" {
    const cols = [_]Column{.{ .title = "Col1" }};
    const table = StreamingTable.init(&cols, 100).withOffset(10);
    const range = table.visibleRange(20, true); // 20 height, with header

    try testing.expectEqual(@as(usize, 10), range.start);
    try testing.expectEqual(@as(usize, 29), range.end); // 19 rows (20 - 1 header)
}

test "StreamingTable.visibleRange auto-scrolls to selected" {
    const cols = [_]Column{.{ .title = "Col1" }};
    const table = StreamingTable.init(&cols, 100).withOffset(0).withSelected(50);
    const range = table.visibleRange(20, true);

    try testing.expect(range.start <= 50);
    try testing.expect(range.end > 50);
}

test "StreamingTable.calculateColumnWidths handles fixed width" {
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .fixed = 10 } },
        .{ .title = "B", .width = .{ .fixed = 20 } },
    };
    const table = StreamingTable.init(&cols, 10);
    var widths: [2]u16 = undefined;

    table.calculateColumnWidths(100, &widths);

    try testing.expectEqual(@as(u16, 10), widths[0]);
    try testing.expectEqual(@as(u16, 20), widths[1]);
}

test "StreamingTable.calculateColumnWidths handles percentage" {
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .percentage = 30 } },
        .{ .title = "B", .width = .{ .percentage = 70 } },
    };
    const table = StreamingTable.init(&cols, 10);
    var widths: [2]u16 = undefined;

    table.calculateColumnWidths(100, &widths);

    try testing.expectEqual(@as(u16, 30), widths[0]);
    try testing.expectEqual(@as(u16, 70), widths[1]);
}

test "StreamingTable.render calls callback only for visible rows" {
    const cols = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 10 } },
        .{ .title = "Name", .width = .{ .percentage = 100 } },
    };
    var table = StreamingTable.init(&cols, 1000).withOffset(100);
    var buf = try Buffer.init(testing.allocator, 80, 12);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 12 };

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn cb(row_index: usize, col_index: usize, writer: anytype) !void {
            _ = col_index;
            count.* += 1;
            try writer.print("Row {}", .{row_index});
        }
    };
    Ctx.count = &call_count;

    try table.render(&buf, area, Ctx.cb, testing.allocator);

    // Should call callback for visible rows only (12 height - 1 header = 11 rows) * 2 columns = 22 calls
    try testing.expectEqual(@as(usize, 22), call_count);
}

test "StreamingTable.render handles huge row counts efficiently" {
    const cols = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 15 } },
        .{ .title = "Value", .width = .{ .percentage = 100 } },
    };
    var table = StreamingTable.init(&cols, 10_000_000)
        .withOffset(5_000_000)
        .withSelected(5_000_005);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const Ctx = struct {
        fn cb(row_index: usize, col_index: usize, writer: anytype) !void {
            if (col_index == 0) {
                try writer.print("{d:10}", .{row_index});
            } else {
                try writer.print("Data-{d}", .{row_index});
            }
        }
    };

    // Should complete without memory issues
    try table.render(&buf, area, Ctx.cb, testing.allocator);

    // Verify header is present
    const header_line = buf.getLine(0, 0, 80);
    defer testing.allocator.free(header_line);
    try testing.expect(std.mem.indexOf(u8, header_line, "ID") != null);
}

test "StreamingTable.renderSlice convenience method" {
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .percentage = 50 } },
        .{ .title = "Age", .width = .{ .percentage = 50 } },
    };

    const rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
        &[_][]const u8{ "Bob", "25" },
        &[_][]const u8{ "Charlie", "35" },
    };

    var table = StreamingTable.init(&cols, rows.len).withSelected(1);
    var buf = try Buffer.init(testing.allocator, 60, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 5 };

    try table.renderSlice(&buf, area, &rows, testing.allocator);

    // Check header
    const header = buf.getLine(0, 0, 60);
    defer testing.allocator.free(header);
    try testing.expect(std.mem.indexOf(u8, header, "Name") != null);
    try testing.expect(std.mem.indexOf(u8, header, "Age") != null);

    // Check data row
    const row1 = buf.getLine(1, 0, 60);
    defer testing.allocator.free(row1);
    try testing.expect(std.mem.indexOf(u8, row1, "Alice") != null);
}

test "StreamingTable.render with alignment left" {
    const cols = [_]Column{
        .{ .title = "Left", .width = .{ .fixed = 10 }, .alignment = .left },
    };

    var table = StreamingTable.init(&cols, 1);
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };

    const Ctx = struct {
        fn cb(_: usize, _: usize, writer: anytype) !void {
            try writer.writeAll("Hi");
        }
    };

    try table.render(&buf, area, Ctx.cb, testing.allocator);

    const row = buf.getLine(1, 0, 20);
    defer testing.allocator.free(row);
    // "Hi" should be left-aligned with padding on the right
    try testing.expect(std.mem.startsWith(u8, std.mem.trimRight(u8, row, " "), "Hi"));
}

test "StreamingTable.render respects column spacing" {
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .fixed = 5 } },
        .{ .title = "B", .width = .{ .fixed = 5 } },
    };

    var table = StreamingTable.init(&cols, 1).withColumnSpacing(3);
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };

    const Ctx = struct {
        fn cb(_: usize, col_idx: usize, writer: anytype) !void {
            if (col_idx == 0) {
                try writer.writeAll("AAA");
            } else {
                try writer.writeAll("BBB");
            }
        }
    };

    try table.render(&buf, area, Ctx.cb, testing.allocator);

    const row = buf.getLine(1, 0, 20);
    defer testing.allocator.free(row);
    // Should have spacing between columns
    try testing.expect(std.mem.indexOf(u8, row, "AAA") != null);
    try testing.expect(std.mem.indexOf(u8, row, "BBB") != null);
}
