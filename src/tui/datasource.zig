const std = @import("std");

/// DataSource abstraction - unified interface for sync/async data providers
/// Used by streaming widgets (VirtualList, StreamingTable, ChunkedBuffer)
/// Provides a consistent API for lazy loading, pagination, and data access

/// Generic DataSource interface for items (1D data)
/// Used by VirtualList and similar widgets
pub fn ItemDataSource(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Fetch a single item by index
        /// Returns null if index is out of bounds
        fetchFn: *const fn (ctx: *anyopaque, index: usize, allocator: std.mem.Allocator) anyerror!?T,

        /// Get total number of items
        /// Returns null if count is unknown (e.g., infinite stream)
        countFn: *const fn (ctx: *anyopaque) ?usize,

        /// Optional: prefetch a range of items for better performance
        prefetchFn: ?*const fn (ctx: *anyopaque, start: usize, count: usize, allocator: std.mem.Allocator) anyerror!void = null,

        /// Optional: invalidate cached items in range
        invalidateFn: ?*const fn (ctx: *anyopaque, start: usize, count: usize) void = null,

        /// Context pointer (opaque to DataSource, interpreted by implementation)
        ctx: *anyopaque,

        /// Fetch item by index
        pub fn fetch(self: Self, index: usize, allocator: std.mem.Allocator) !?T {
            return self.fetchFn(self.ctx, index, allocator);
        }

        /// Get total item count
        pub fn count(self: Self) ?usize {
            return self.countFn(self.ctx);
        }

        /// Prefetch range of items (if supported)
        pub fn prefetch(self: Self, start: usize, item_count: usize, allocator: std.mem.Allocator) !void {
            if (self.prefetchFn) |prefetchFn| {
                try prefetchFn(self.ctx, start, item_count, allocator);
            }
        }

        /// Invalidate cached items in range (if supported)
        pub fn invalidate(self: Self, start: usize, item_count: usize) void {
            if (self.invalidateFn) |invalidateFn| {
                invalidateFn(self.ctx, start, item_count);
            }
        }
    };
}

/// Table DataSource interface for 2D data
/// Used by StreamingTable and similar widgets
pub fn TableDataSource(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Fetch a single cell by row and column index
        /// Returns null if indices are out of bounds
        fetchCellFn: *const fn (ctx: *anyopaque, row: usize, col: usize, allocator: std.mem.Allocator) anyerror!?T,

        /// Get total number of rows
        /// Returns null if count is unknown
        rowCountFn: *const fn (ctx: *anyopaque) ?usize,

        /// Get number of columns
        colCountFn: *const fn (ctx: *anyopaque) usize,

        /// Optional: fetch entire row at once for better performance
        fetchRowFn: ?*const fn (ctx: *anyopaque, row: usize, allocator: std.mem.Allocator) anyerror!?[]const T = null,

        /// Optional: prefetch a range of rows
        prefetchFn: ?*const fn (ctx: *anyopaque, start_row: usize, row_count: usize, allocator: std.mem.Allocator) anyerror!void = null,

        /// Context pointer
        ctx: *anyopaque,

        /// Fetch cell by row and column
        pub fn fetchCell(self: Self, row: usize, col: usize, allocator: std.mem.Allocator) !?T {
            return self.fetchCellFn(self.ctx, row, col, allocator);
        }

        /// Get row count
        pub fn rowCount(self: Self) ?usize {
            return self.rowCountFn(self.ctx);
        }

        /// Get column count
        pub fn colCount(self: Self) usize {
            return self.colCountFn(self.ctx);
        }

        /// Fetch entire row (if supported)
        pub fn fetchRow(self: Self, row: usize, allocator: std.mem.Allocator) !?[]const T {
            if (self.fetchRowFn) |fetchRowFn| {
                return fetchRowFn(self.ctx, row, allocator);
            }
            // Fallback: fetch cells one by one
            const cols = self.colCount();
            const row_data = try allocator.alloc(T, cols);
            errdefer allocator.free(row_data);

            for (0..cols) |col| {
                const cell = try self.fetchCell(row, col, allocator) orelse return null;
                row_data[col] = cell;
            }
            return row_data;
        }

        /// Prefetch range of rows (if supported)
        pub fn prefetch(self: Self, start_row: usize, row_count_val: usize, allocator: std.mem.Allocator) !void {
            if (self.prefetchFn) |prefetchFn| {
                try prefetchFn(self.ctx, start_row, row_count_val, allocator);
            }
        }
    };
}

/// Line DataSource interface for text data
/// Used by ChunkedBuffer and text viewers
pub fn LineDataSource(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        /// Fetch a single line by index, writing to writer
        /// Returns error if line doesn't exist or I/O error
        fetchLineFn: *const fn (ctx: *anyopaque, line_index: usize, writer: WriterType) anyerror!void,

        /// Get total number of lines
        /// Returns null if count is unknown
        lineCountFn: *const fn (ctx: *anyopaque) ?usize,

        /// Optional: prefetch a range of lines
        prefetchFn: ?*const fn (ctx: *anyopaque, start: usize, count: usize) anyerror!void = null,

        /// Context pointer
        ctx: *anyopaque,

        /// Fetch line by index, writing to writer
        pub fn fetchLine(self: Self, line_index: usize, writer: WriterType) !void {
            return self.fetchLineFn(self.ctx, line_index, writer);
        }

        /// Get total line count
        pub fn lineCount(self: Self) ?usize {
            return self.lineCountFn(self.ctx);
        }

        /// Prefetch range of lines (if supported)
        pub fn prefetch(self: Self, start: usize, count: usize) !void {
            if (self.prefetchFn) |prefetchFn| {
                try prefetchFn(self.ctx, start, count);
            }
        }
    };
}

/// Slice-backed ItemDataSource implementation
/// Wraps a slice for simple in-memory data
pub fn SliceItemDataSource(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []const T,

        /// Initializes a slice-backed item data source.
        pub fn init(items: []const T) Self {
            return .{ .items = items };
        }

        /// Returns the ItemDataSource interface for this slice.
        pub fn dataSource(self: *Self) ItemDataSource(T) {
            return .{
                .fetchFn = fetchFn,
                .countFn = countFn,
                .ctx = @ptrCast(self),
            };
        }

        fn fetchFn(ctx: *anyopaque, index: usize, _: std.mem.Allocator) !?T {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (index >= self.items.len) return null;
            return self.items[index];
        }

        fn countFn(ctx: *anyopaque) ?usize {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.items.len;
        }
    };
}

/// Slice-backed TableDataSource implementation
/// Wraps a 2D slice for simple in-memory tabular data
pub fn SliceTableDataSource(comptime T: type) type {
    return struct {
        const Self = @This();

        rows: []const []const T,

        /// Initializes a slice-backed table data source.
        pub fn init(rows: []const []const T) Self {
            return .{ .rows = rows };
        }

        /// Returns the TableDataSource interface for this 2D slice.
        pub fn dataSource(self: *Self) TableDataSource(T) {
            return .{
                .fetchCellFn = fetchCellFn,
                .rowCountFn = rowCountFn,
                .colCountFn = colCountFn,
                .fetchRowFn = fetchRowFn,
                .ctx = @ptrCast(self),
            };
        }

        fn fetchCellFn(ctx: *anyopaque, row: usize, col: usize, _: std.mem.Allocator) !?T {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (row >= self.rows.len) return null;
            if (col >= self.rows[row].len) return null;
            return self.rows[row][col];
        }

        fn rowCountFn(ctx: *anyopaque) ?usize {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.rows.len;
        }

        fn colCountFn(ctx: *anyopaque) usize {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self.rows.len == 0) return 0;
            return self.rows[0].len;
        }

        fn fetchRowFn(ctx: *anyopaque, row: usize, _: std.mem.Allocator) !?[]const T {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (row >= self.rows.len) return null;
            return self.rows[row];
        }
    };
}

/// Simple slice-backed LineDataSource implementation
/// Wraps a slice of strings for in-memory text data
pub fn SliceLineDataSource(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        lines: []const []const u8,

        /// Initializes a slice-backed line data source.
        pub fn init(lines: []const []const u8) Self {
            return .{ .lines = lines };
        }

        /// Returns the LineDataSource interface for this slice of strings.
        pub fn dataSource(self: *Self) LineDataSource(WriterType) {
            return .{
                .fetchLineFn = fetchLineFn,
                .lineCountFn = lineCountFn,
                .ctx = @ptrCast(self),
            };
        }

        fn fetchLineFn(ctx: *anyopaque, line_index: usize, writer: WriterType) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (line_index >= self.lines.len) return error.IndexOutOfBounds;
            try writer.writeAll(self.lines[line_index]);
        }

        fn lineCountFn(ctx: *anyopaque) ?usize {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.lines.len;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ItemDataSource - slice backed" {
    const items = [_]u32{ 10, 20, 30, 40, 50 };
    var slice_ds = SliceItemDataSource(u32).init(&items);
    const ds = slice_ds.dataSource();

    // Test count
    try std.testing.expectEqual(@as(?usize, 5), ds.count());

    // Test fetch
    try std.testing.expectEqual(@as(?u32, 10), try ds.fetch(0, std.testing.allocator));
    try std.testing.expectEqual(@as(?u32, 30), try ds.fetch(2, std.testing.allocator));
    try std.testing.expectEqual(@as(?u32, 50), try ds.fetch(4, std.testing.allocator));

    // Test out of bounds
    try std.testing.expectEqual(@as(?u32, null), try ds.fetch(5, std.testing.allocator));
    try std.testing.expectEqual(@as(?u32, null), try ds.fetch(100, std.testing.allocator));
}

test "TableDataSource - slice backed" {
    const row1 = [_][]const u8{ "a", "b", "c" };
    const row2 = [_][]const u8{ "d", "e", "f" };
    const row3 = [_][]const u8{ "g", "h", "i" };
    const rows = [_][]const []const u8{ &row1, &row2, &row3 };

    var slice_ds = SliceTableDataSource([]const u8).init(&rows);
    const ds = slice_ds.dataSource();

    // Test dimensions
    try std.testing.expectEqual(@as(?usize, 3), ds.rowCount());
    try std.testing.expectEqual(@as(usize, 3), ds.colCount());

    // Test fetch cell
    try std.testing.expectEqualStrings("a", (try ds.fetchCell(0, 0, std.testing.allocator)).?);
    try std.testing.expectEqualStrings("e", (try ds.fetchCell(1, 1, std.testing.allocator)).?);
    try std.testing.expectEqualStrings("i", (try ds.fetchCell(2, 2, std.testing.allocator)).?);

    // Test out of bounds
    try std.testing.expectEqual(@as(?[]const u8, null), try ds.fetchCell(3, 0, std.testing.allocator));
    try std.testing.expectEqual(@as(?[]const u8, null), try ds.fetchCell(0, 3, std.testing.allocator));

    // Test fetch row
    const fetched_row = (try ds.fetchRow(1, std.testing.allocator)).?;
    try std.testing.expectEqualStrings("d", fetched_row[0]);
    try std.testing.expectEqualStrings("e", fetched_row[1]);
    try std.testing.expectEqualStrings("f", fetched_row[2]);
}

test "LineDataSource - slice backed" {
    const lines = [_][]const u8{ "Line 0", "Line 1", "Line 2" };

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const WriterType = @TypeOf(fbs.writer());

    var slice_ds = SliceLineDataSource(WriterType).init(&lines);
    const ds = slice_ds.dataSource();

    // Test count
    try std.testing.expectEqual(@as(?usize, 3), ds.lineCount());

    // Test fetch line
    try ds.fetchLine(0, fbs.writer());
    try std.testing.expectEqualStrings("Line 0", fbs.getWritten());

    fbs.reset();
    try ds.fetchLine(2, fbs.writer());
    try std.testing.expectEqualStrings("Line 2", fbs.getWritten());

    // Test out of bounds
    fbs.reset();
    try std.testing.expectError(error.IndexOutOfBounds, ds.fetchLine(3, fbs.writer()));
}

test "ItemDataSource - prefetch no-op" {
    const items = [_]u32{ 1, 2, 3 };
    var slice_ds = SliceItemDataSource(u32).init(&items);
    const ds = slice_ds.dataSource();

    // Prefetch should be no-op for slice-backed source
    try ds.prefetch(0, 3, std.testing.allocator);
}

test "ItemDataSource - invalidate no-op" {
    const items = [_]u32{ 1, 2, 3 };
    var slice_ds = SliceItemDataSource(u32).init(&items);
    const ds = slice_ds.dataSource();

    // Invalidate should be no-op for slice-backed source
    ds.invalidate(0, 3);
}

test "TableDataSource - empty table" {
    const empty: []const []const []const u8 = &[_][]const []const u8{};
    var slice_ds = SliceTableDataSource([]const u8).init(empty);
    const ds = slice_ds.dataSource();

    try std.testing.expectEqual(@as(?usize, 0), ds.rowCount());
    try std.testing.expectEqual(@as(usize, 0), ds.colCount());
}

test "LineDataSource - prefetch no-op" {
    const lines = [_][]const u8{ "Line 0", "Line 1" };

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const WriterType = @TypeOf(fbs.writer());

    var slice_ds = SliceLineDataSource(WriterType).init(&lines);
    const ds = slice_ds.dataSource();

    // Prefetch should be no-op for slice-backed source
    try ds.prefetch(0, 2);
}
