const std = @import("std");
const Allocator = std.mem.Allocator;
const style_mod = @import("style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;

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

    /// Set character at position with optional style
    pub fn setChar(self: *Buffer, x: u16, y: u16, char: u21, cell_style: Style) void {
        if (self.get(x, y)) |cell| {
            cell.char = char;
            cell.style = cell_style;
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

            self.setChar(col, y, codepoint, cell_style);
            i += char_len;
            col += 1;
        }
    }

    /// Fill area with character and style
    pub fn fill(self: *Buffer, area: Rect, char: u21, cell_style: Style) void {
        var row = area.y;
        while (row < area.y + area.height and row < self.height) : (row += 1) {
            var col = area.x;
            while (col < area.x + area.width and col < self.width) : (col += 1) {
                self.setChar(col, row, char, cell_style);
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
};

/// Diff operation for incremental rendering
pub const DiffOp = struct {
    x: u16,
    y: u16,
    cell: Cell,
};

/// Calculate diff between two buffers
pub fn diff(allocator: Allocator, old: Buffer, new: Buffer) ![]DiffOp {
    if (old.width != new.width or old.height != new.height) {
        return error.BufferSizeMismatch;
    }

    var ops = try std.ArrayList(DiffOp).initCapacity(allocator, 0);
    defer ops.deinit(allocator);

    var y: u16 = 0;
    while (y < new.height) : (y += 1) {
        var x: u16 = 0;
        while (x < new.width) : (x += 1) {
            const old_cell = old.getConst(x, y).?;
            const new_cell = new.getConst(x, y).?;

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

test "Buffer.setChar" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.setChar(3, 1, 'A', .{ .fg = .red });
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

    const area = Rect.new(2, 1, 3, 2);
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

    buffer.setChar(3, 2, 'X', .{ .fg = .red });
    buffer.clear();

    for (buffer.cells) |cell| {
        try std.testing.expectEqual(' ', cell.char);
        try std.testing.expectEqual(Style.default, cell.style);
    }
}

test "Buffer.clearArea" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 5);
    defer buffer.deinit();

    buffer.fill(Rect.new(0, 0, 10, 5), 'X', .{});
    buffer.clearArea(Rect.new(2, 1, 3, 2));

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

    original.setChar(3, 2, 'Z', .{ .fg = .magenta });

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

    buf2.setChar(2, 1, 'X', .{ .fg = .red });

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

    buf2.setChar(0, 0, 'A', .{});
    buf2.setChar(5, 2, 'B', .{});
    buf2.setChar(9, 4, 'C', .{});

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

    // Test emoji (multi-byte UTF-8)
    buffer.setString(0, 0, "Hello 👋 World", .{});
    try std.testing.expectEqual(@as(u21, 'H'), buffer.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, '👋'), buffer.get(6, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'W'), buffer.get(8, 0).?.char);
}

test "Buffer.setString - CJK characters" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    // Test Chinese characters
    buffer.setString(0, 0, "你好世界", .{});
    try std.testing.expectEqual(@as(u21, '你'), buffer.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, '好'), buffer.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, '世'), buffer.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, '界'), buffer.get(3, 0).?.char);
}

test "Buffer.setChar - zero-width characters" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    // Test null character
    buffer.setChar(0, 0, 0, .{});
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
    const area = Rect.new(8, 3, 5, 3);
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
    const area = Rect.new(0, 0, 0, 0);
    buffer.clearArea(area);

    try std.testing.expectEqual(@as(u21, 't'), buffer.get(0, 0).?.char);
}
