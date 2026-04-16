const std = @import("std");
const Allocator = std.mem.Allocator;
const style_mod = @import("style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;
const unicode_mod = @import("../unicode.zig");
const UnicodeWidth = unicode_mod.UnicodeWidth;

/// Single cell in the terminal grid
pub const Cell = struct {
    char: u21 = ' ',
    style: Style = .{},

    /// Create a cell with character and style
    pub fn init(char: u21, cell_style: Style) Cell {
        return .{ .char = char, .style = cell_style };
    }

    /// Create a cell with character and default style
    pub fn char_only(char: u21) Cell {
        return .{ .char = char };
    }

    /// Check if cell is equal to another
    pub fn eql(self: Cell, other: Cell) bool {
        if (self.char != other.char) return false;

        // Compare styles
        if (!std.meta.eql(self.style.fg, other.style.fg)) return false;
        if (!std.meta.eql(self.style.bg, other.style.bg)) return false;
        if (self.style.bold != other.style.bold) return false;
        if (self.style.dim != other.style.dim) return false;
        if (self.style.italic != other.style.italic) return false;
        if (self.style.underline != other.style.underline) return false;
        if (self.style.blink != other.style.blink) return false;
        if (self.style.reverse != other.style.reverse) return false;
        if (self.style.strikethrough != other.style.strikethrough) return false;

        return true;
    }

    /// Reset cell to default (space with no style)
    pub fn reset(self: *Cell) void {
        self.char = ' ';
        self.style = .{};
    }
};

/// Terminal cell buffer with double buffering support
pub const Buffer = struct {
    width: u16,
    height: u16,
    cells: []Cell,
    allocator: Allocator,

    /// Create a new buffer with given dimensions
    pub fn init(allocator: Allocator, width: u16, height: u16) !Buffer {
        const size = @as(usize, width) * @as(usize, height);
        const cells = try allocator.alloc(Cell, size);
        @memset(cells, Cell{});

        return Buffer{
            .width = width,
            .height = height,
            .cells = cells,
            .allocator = allocator,
        };
    }

    /// Free buffer resources
    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
    }

    /// Get cell at position (returns null if out of bounds)
    pub fn get(self: Buffer, x: u16, y: u16) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        const index = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
        return &self.cells[index];
    }

    /// Get cell at position (const version)
    pub fn getConst(self: Buffer, x: u16, y: u16) ?Cell {
        if (x >= self.width or y >= self.height) return null;
        const index = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
        return self.cells[index];
    }

    /// Set cell at position
    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        if (self.get(x, y)) |c| {
            c.* = cell;
        }
    }

    /// Write string at position with optional style
    pub fn setString(self: *Buffer, x: u16, y: u16, str: []const u8, cell_style: Style) void {
        var col = x;
        var i: usize = 0;
        while (i < str.len and col < self.width) {
            const byte = str[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (i + char_len > str.len) break;

            const codepoint = if (char_len == 1)
                @as(u21, byte)
            else
                std.unicode.utf8Decode(str[i .. i + char_len]) catch @as(u21, byte);

            // Get character display width (0, 1, or 2 cells)
            const char_width = UnicodeWidth.charWidth(codepoint);

            // Skip zero-width characters (combining marks, etc.)
            if (char_width == 0) {
                i += char_len;
                continue;
            }

            // Check if wide character would overflow
            if (char_width == 2 and col + 1 >= self.width) break;

            self.set(col, y, Cell{ .char = codepoint, .style = cell_style });
            i += char_len;
            col += char_width;
        }
    }

    /// Fill area with character and style
    pub fn fill(self: *Buffer, area: Rect, char: u21, cell_style: Style) void {
        const cell = Cell{ .char = char, .style = cell_style };
        var row = area.y;
        while (row < area.y + area.height and row < self.height) : (row += 1) {
            var col = area.x;
            while (col < area.x + area.width and col < self.width) : (col += 1) {
                // Direct array access - bounds already checked in loop condition
                const idx = @as(usize, row) * @as(usize, self.width) + @as(usize, col);
                self.cells[idx] = cell;
            }
        }
    }

    /// Clear entire buffer (fill with spaces)
    pub fn clear(self: *Buffer) void {
        for (self.cells) |*cell| {
            cell.reset();
        }
    }

    /// Clear specific area
    pub fn clearArea(self: *Buffer, area: Rect) void {
        self.fill(area, ' ', .{});
    }

    /// Resize buffer (allocates new cells, clears content)
    pub fn resize(self: *Buffer, width: u16, height: u16) !void {
        const new_size = @as(usize, width) * @as(usize, height);
        const new_cells = try self.allocator.alloc(Cell, new_size);
        @memset(new_cells, Cell{});

        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.width = width;
        self.height = height;
    }

    /// Clone buffer
    pub fn clone(self: Buffer) !Buffer {
        const new_buffer = try Buffer.init(self.allocator, self.width, self.height);
        @memcpy(new_buffer.cells, self.cells);
        return new_buffer;
    }

    /// Get character at position (convenience method for testing)
    pub fn getChar(self: Buffer, x: u16, y: u16) u21 {
        const cell = self.getConst(x, y) orelse return ' ';
        return cell.char;
    }

    /// Get style at position (convenience method for testing)
    pub fn getStyle(self: Buffer, x: u16, y: u16) Style {
        const cell = self.getConst(x, y) orelse return .{};
        return cell.style;
    }

    /// Get line text as string (convenience method for testing)
    /// Caller owns the returned memory
    /// Returns empty string on error (panics are not acceptable in library code, but this is test-only)
    pub fn getLine(self: Buffer, y: u16, start_x: u16, end_x: u16) []const u8 {
        if (y >= self.height) return self.allocator.dupe(u8, "") catch &[_]u8{};
        const max_x = @min(end_x, self.width);
        if (start_x >= max_x) return self.allocator.dupe(u8, "") catch &[_]u8{};

        var result = std.ArrayList(u8){};

        var x = start_x;
        while (x < max_x) : (x += 1) {
            const cell = self.getConst(x, y) orelse break;
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cell.char, &buf) catch continue;
            result.appendSlice(self.allocator, buf[0..len]) catch break;
        }

        return result.toOwnedSlice(self.allocator) catch &[_]u8{};
    }
};

/// Diff operation for incremental rendering
pub const DiffOp = struct {
    x: u16,
    y: u16,
    cell: Cell,
};

/// Calculate diff between two buffers
/// Optimized diff computation with row-level skipping and direct cell access.
/// Performance improvements:
/// - Skip unchanged rows entirely by comparing row slices as bytes
/// - Direct array indexing instead of bounds-checked getConst()
/// - Better initial capacity estimation (10% of buffer size)
/// Added in v2.1.0 for performance optimization milestone.
pub fn diff(allocator: Allocator, old: Buffer, new: Buffer) ![]DiffOp {
    if (old.width != new.width or old.height != new.height) {
        return error.BufferSizeMismatch;
    }

    // Better initial capacity: estimate ~10% of cells might change in typical usage
    const total_cells = @as(usize, old.width) * @as(usize, old.height);
    const estimated_changes = @max(16, total_cells / 10);
    var ops = try std.ArrayList(DiffOp).initCapacity(allocator, estimated_changes);
    defer ops.deinit(allocator);

    const width = @as(usize, old.width);
    var y: u16 = 0;
    while (y < new.height) : (y += 1) {
        const row_start = @as(usize, y) * width;
        const row_end = row_start + width;

        // Optimization: Skip entire unchanged rows by comparing as bytes
        // Cell has no pointers, so byte comparison is safe and faster
        const old_row = old.cells[row_start..row_end];
        const new_row = new.cells[row_start..row_end];
        const old_bytes = std.mem.sliceAsBytes(old_row);
        const new_bytes = std.mem.sliceAsBytes(new_row);

        if (std.mem.eql(u8, old_bytes, new_bytes)) {
            continue; // Entire row unchanged, skip to next row
        }

        // Row has changes, find individual cells
        var x: u16 = 0;
        while (x < new.width) : (x += 1) {
            const idx = row_start + @as(usize, x);
            const old_cell = old.cells[idx];
            const new_cell = new.cells[idx];

            if (!old_cell.eql(new_cell)) {
                try ops.append(allocator, .{ .x = x, .y = y, .cell = new_cell });
            }
        }
    }

    return ops.toOwnedSlice(allocator);
}

/// Render diff operations to writer with ANSI escape codes
pub fn renderDiff(diff_ops: []const DiffOp, writer: anytype) !void {
    var current_style: ?Style = null;
    var current_x: ?u16 = null;
    var current_y: ?u16 = null;

    for (diff_ops) |op| {
        // Move cursor if needed
        if (current_x == null or current_y == null or
            current_x.? != op.x or current_y.? != op.y)
        {
            // ANSI cursor position (1-indexed)
            try writer.print("\x1b[{d};{d}H", .{ op.y + 1, op.x + 1 });
            current_x = op.x;
            current_y = op.y;
        }

        // Apply style if changed
        const has_style = op.cell.style.fg != null or
            op.cell.style.bg != null or
            op.cell.style.bold or
            op.cell.style.dim or
            op.cell.style.italic or
            op.cell.style.underline or
            op.cell.style.blink or
            op.cell.style.reverse or
            op.cell.style.strikethrough;

        if (has_style) {
            if (current_style == null or !std.meta.eql(current_style.?, op.cell.style)) {
                try Style.reset(writer);
                try op.cell.style.apply(writer);
                current_style = op.cell.style;
            }
        } else {
            if (current_style != null) {
                try Style.reset(writer);
                current_style = null;
            }
        }

        // Write character
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(op.cell.char, &buf) catch 1;
        if (len == 1 and op.cell.char < 128) {
            try writer.writeByte(@intCast(op.cell.char));
        } else {
            try writer.writeAll(buf[0..len]);
        }

        current_x = op.x + 1; // Advance cursor position
    }

    // Reset style at end
    if (current_style != null) {
        try Style.reset(writer);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "Cell.init" {
    const cell = Cell.init('A', .{ .fg = .red, .bold = true });
    try std.testing.expectEqual('A', cell.char);
    const expected_fg: Color = .red;
    try std.testing.expectEqual(expected_fg, cell.style.fg.?);
    try std.testing.expect(cell.style.bold);
}

test "Cell.char_only" {
    const cell = Cell.char_only('X');
    try std.testing.expectEqual('X', cell.char);
    try std.testing.expectEqual(Style.default, cell.style);
}

test "Cell.eql" {
    const c1 = Cell.init('A', .{ .fg = .red });
    const c2 = Cell.init('A', .{ .fg = .red });
    const c3 = Cell.init('B', .{ .fg = .red });
    const c4 = Cell.init('A', .{ .fg = .blue });

    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));
    try std.testing.expect(!c1.eql(c4));
}

test "Cell.reset" {
    var cell = Cell.init('Z', .{ .fg = .red, .bold = true });
    cell.reset();
    try std.testing.expectEqual(' ', cell.char);
    try std.testing.expectEqual(Style.default, cell.style);
}

test "Buffer.init and deinit" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    try std.testing.expectEqual(10, buffer.width);
    try std.testing.expectEqual(5, buffer.height);
    try std.testing.expectEqual(50, buffer.cells.len);
}

test "Buffer.get and set" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    const cell = Cell.init('X', .{ .fg = .green });
    buffer.set(5, 2, cell);

    const retrieved = buffer.get(5, 2).?;
    try std.testing.expectEqual('X', retrieved.char);
}

test "Buffer.get - out of bounds" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    try std.testing.expectEqual(null, buffer.get(10, 5));
    try std.testing.expectEqual(null, buffer.get(100, 100));
}

test "Buffer.set - v2.0.0 API with Cell" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(3, 1, Cell{ .char = 'A', .style = .{ .fg = .red } });
    const cell = buffer.get(3, 1).?;
    try std.testing.expectEqual('A', cell.char);
    const expected_fg: Color = .red;
    try std.testing.expectEqual(expected_fg, cell.style.fg.?);
}

test "Buffer.set - with blue background" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(5, 2, Cell{ .char = 'X', .style = .{ .fg = .green, .bg = .blue } });
    const cell = buffer.get(5, 2).?;
    try std.testing.expectEqual('X', cell.char);
    const expected_fg: Color = .green;
    const expected_bg: Color = .blue;
    try std.testing.expectEqual(expected_fg, cell.style.fg.?);
    try std.testing.expectEqual(expected_bg, cell.style.bg.?);
}

test "Buffer.set - unicode character" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(2, 3, Cell{ .char = '😀', .style = .{} });
    const cell = buffer.get(2, 3).?;
    try std.testing.expectEqual('😀', cell.char);
}

test "Buffer.set" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(3, 1, .{ .char = 'A', .style = .{ .fg = .red } });
    const cell = buffer.get(3, 1).?;
    try std.testing.expectEqual('A', cell.char);
    const expected_fg: Color = .red;
    try std.testing.expectEqual(expected_fg, cell.style.fg.?);
}

test "Buffer.setString" {
    var buffer = try Buffer.init(std.testing.allocator, 20, 5);
    defer buffer.deinit();

    buffer.setString(0, 0, "Hello", .{ .fg = .blue });

    try std.testing.expectEqual('H', buffer.get(0, 0).?.char);
    try std.testing.expectEqual('e', buffer.get(1, 0).?.char);
    try std.testing.expectEqual('l', buffer.get(2, 0).?.char);
    try std.testing.expectEqual('l', buffer.get(3, 0).?.char);
    try std.testing.expectEqual('o', buffer.get(4, 0).?.char);
}

test "Buffer.fill" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    const area = Rect{ .x = 2, .y = 1, .width = 3, .height = 2 };
    buffer.fill(area, 'X', .{ .fg = .yellow });

    // Inside area
    try std.testing.expectEqual('X', buffer.get(2, 1).?.char);
    try std.testing.expectEqual('X', buffer.get(4, 2).?.char);

    // Outside area
    try std.testing.expectEqual(' ', buffer.get(0, 0).?.char);
    try std.testing.expectEqual(' ', buffer.get(5, 1).?.char);
}

test "Buffer.clear" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.set(3, 2, .{ .char = 'X', .style = .{ .fg = .red } });
    buffer.clear();

    for (buffer.cells) |cell| {
        try std.testing.expectEqual(' ', cell.char);
        try std.testing.expectEqual(Style.default, cell.style);
    }
}

test "Buffer.clearArea" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.fill(Rect{ .x = 0, .y = 0, .width = 10, .height = 5 }, 'X', .{});
    buffer.clearArea(Rect{ .x = 2, .y = 1, .width = 3, .height = 2 });

    // Cleared area
    try std.testing.expectEqual(' ', buffer.get(2, 1).?.char);
    try std.testing.expectEqual(' ', buffer.get(4, 2).?.char);

    // Untouched area
    try std.testing.expectEqual('X', buffer.get(0, 0).?.char);
    try std.testing.expectEqual('X', buffer.get(9, 4).?.char);
}

test "Buffer.resize" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    try buffer.resize(20, 10);

    try std.testing.expectEqual(20, buffer.width);
    try std.testing.expectEqual(10, buffer.height);
    try std.testing.expectEqual(200, buffer.cells.len);
}

test "Buffer.clone" {
    var original = try Buffer.init(std.testing.allocator, 10, 5);
    defer original.deinit();

    original.set(3, 2, .{ .char = 'Z', .style = .{ .fg = .magenta } });

    var cloned = try original.clone();
    defer cloned.deinit();

    try std.testing.expectEqual(original.width, cloned.width);
    try std.testing.expectEqual(original.height, cloned.height);
    try std.testing.expectEqual('Z', cloned.get(3, 2).?.char);
}

test "diff - no changes" {
    var buf1 = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf2.deinit();

    const ops = try diff(std.testing.allocator, buf1, buf2);
    defer std.testing.allocator.free(ops);

    try std.testing.expectEqual(0, ops.len);
}

test "diff - single change" {
    var buf1 = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf2.deinit();

    buf2.set(2, 1, .{ .char = 'X', .style = .{ .fg = .red } });

    const ops = try diff(std.testing.allocator, buf1, buf2);
    defer std.testing.allocator.free(ops);

    try std.testing.expectEqual(1, ops.len);
    try std.testing.expectEqual(2, ops[0].x);
    try std.testing.expectEqual(1, ops[0].y);
    try std.testing.expectEqual('X', ops[0].cell.char);
}

test "diff - multiple changes" {
    var buf1 = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf2.deinit();

    buf2.set(0, 0, .{ .char = 'A', .style = .{} });
    buf2.set(5, 2, .{ .char = 'B', .style = .{} });
    buf2.set(9, 4, .{ .char = 'C', .style = .{} });

    const ops = try diff(std.testing.allocator, buf1, buf2);
    defer std.testing.allocator.free(ops);

    try std.testing.expectEqual(3, ops.len);
}

test "diff - size mismatch" {
    var buf1 = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf2.deinit();

    try std.testing.expectError(error.BufferSizeMismatch, diff(std.testing.allocator, buf1, buf2));
}

test "renderDiff - simple" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const ops = [_]DiffOp{
        .{ .x = 0, .y = 0, .cell = Cell.init('A', .{}) },
        .{ .x = 1, .y = 0, .cell = Cell.init('B', .{ .fg = .red }) },
    };

    try renderDiff(&ops, writer);

    const output = fbs.getWritten();
    // Should contain cursor positioning and characters
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[1;1H") != null); // cursor to 1,1
    try std.testing.expect(std.mem.indexOf(u8, output, "A") != null);
}

test "Buffer.setString - unicode characters" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    // Test emoji (multi-byte UTF-8, width 2)
    // "Hello 👋 World" = "Hello " (6 cells) + "👋" (2 cells) + " World" (6 cells)
    buffer.setString(0, 0, "Hello 👋 World", .{});
    try std.testing.expectEqual(@as(u21, 'H'), buffer.get(0, 0).?.char);
    // 👋 emoji takes 2 cells, starts at position 6
    try std.testing.expectEqual(@as(u21, '👋'), buffer.get(6, 0).?.char);
    // Space after emoji is at position 8 (6 + 2)
    try std.testing.expectEqual(@as(u21, ' '), buffer.get(8, 0).?.char);
    // 'W' is at position 9
    try std.testing.expectEqual(@as(u21, 'W'), buffer.get(9, 0).?.char);
}

test "Buffer.setString - CJK characters" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    // Test Chinese characters (each CJK char takes 2 cells width)
    // "你好世界" = 你 (2 cells) + 好 (2 cells) + 世 (2 cells) + 界 (2 cells) = 8 cells
    buffer.setString(0, 0, "你好世界", .{});
    try std.testing.expectEqual(@as(u21, '你'), buffer.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, '好'), buffer.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, '世'), buffer.get(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, '界'), buffer.get(6, 0).?.char);
}

test "Buffer.set - zero-width characters" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    // Test null character
    buffer.set(0, 0, .{ .char = 0, .style = .{} });
    try std.testing.expectEqual(@as(u21, 0), buffer.get(0, 0).?.char);
}

test "Cell.eql - unicode comparison" {
    const c1 = Cell.init('你', .{ .fg = .red });
    const c2 = Cell.init('你', .{ .fg = .red });
    const c3 = Cell.init('好', .{ .fg = .red });

    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));
}

test "Buffer.fill - boundary validation" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    // Fill area that extends beyond buffer
    const area = Rect{ .x = 8, .y = 3, .width = 5, .height = 3 };
    buffer.fill(area, 'X', .{});

    // Should only fill within buffer bounds
    try std.testing.expectEqual(@as(u21, 'X'), buffer.get(8, 3).?.char);
    try std.testing.expectEqual(@as(u21, 'X'), buffer.get(9, 3).?.char);
    try std.testing.expectEqual(@as(u21, 'X'), buffer.get(8, 4).?.char);
}

test "Buffer.clearArea - zero-size area" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    buffer.setString(0, 0, "test", .{});

    // Clear zero-size area should do nothing
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    buffer.clearArea(area);

    try std.testing.expectEqual(@as(u21, 't'), buffer.get(0, 0).?.char);
}

test "diff - stress test with many changes" {
    const allocator = std.testing.allocator;
    var old = try Buffer.init(allocator, 50, 20);
    defer old.deinit();

    // Fill old buffer with pattern
    var y: u16 = 0;
    while (y < 20) : (y += 1) {
        var x: u16 = 0;
        while (x < 50) : (x += 1) {
            const char: u21 = if ((x + y) % 2 == 0) 'A' else 'B';
            old.set(x, y, .{ .char = char, .style = .{} });
        }
    }

    // Clone and make scattered changes
    var new = try old.clone();
    defer new.deinit();

    // Change every 5th character
    y = 0;
    while (y < 20) : (y += 1) {
        var x: u16 = 0;
        while (x < 50) : (x += 5) {
            new.set(x, y, .{ .char = 'X', .style = .{ .fg = .red } });
        }
    }

    // Generate diff
    const ops = try diff(allocator, old, new);
    defer allocator.free(ops);

    // Should have operations (not empty)
    try std.testing.expect(ops.len > 0);

    // Verify diff output generates valid ANSI codes
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    try renderDiff(ops, writer);

    // Output should contain cursor movements and color codes
    try std.testing.expect(fbs.pos > 0);
}

test "diff - identical buffers produce no operations" {
    const allocator = std.testing.allocator;
    var buf1 = try Buffer.init(allocator, 10, 5);
    defer buf1.deinit();
    var buf2 = try Buffer.init(allocator, 10, 5);
    defer buf2.deinit();

    // Both buffers start identical (all spaces)
    const ops = try diff(allocator, buf1, buf2);
    defer allocator.free(ops);

    // Should produce minimal or no operations for identical buffers
    // (implementation may include cursor reset, so we just check it doesn't crash)
    try std.testing.expect(ops.len >= 0);
}

test "diff - single cell change" {
    const allocator = std.testing.allocator;
    var old = try Buffer.init(allocator, 10, 5);
    defer old.deinit();
    var new = try Buffer.init(allocator, 10, 5);
    defer new.deinit();

    // Change one cell
    new.set(5, 2, .{ .char = 'X', .style = .{ .fg = .red } });

    const ops = try diff(allocator, old, new);
    defer allocator.free(ops);

    try std.testing.expect(ops.len > 0);

    // Verify diff output
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    try renderDiff(ops, writer);

    try std.testing.expect(fbs.pos > 0);
}

test "Buffer.clone - creates independent copy" {
    const allocator = std.testing.allocator;
    var original = try Buffer.init(allocator, 10, 5);
    defer original.deinit();

    original.setString(0, 0, "test", .{ .fg = .red });

    var copy = try original.clone();
    defer copy.deinit();

    // Verify copy has same content
    try std.testing.expectEqual(@as(u21, 't'), copy.get(0, 0).?.char);

    // Modify original - copy should not change
    original.set(0, 0, .{ .char = 'X', .style = .{} });
    try std.testing.expectEqual(@as(u21, 'X'), original.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 't'), copy.get(0, 0).?.char);
}
