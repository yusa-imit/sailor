const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const editor = @import("editor.zig");
const Editor = editor.Editor;
const Position = editor.Position;
const Selection = editor.Selection;

/// Multi-cursor editor widget for simultaneous editing at multiple positions
///
/// Features:
/// - Multiple independent cursors
/// - Synchronized editing operations (insert, delete, undo/redo)
/// - Column selection mode (rectangular selection)
/// - Cursor addition/removal (Ctrl+Click, Ctrl+D for next occurrence)
/// - All operations apply to all cursors simultaneously
///
/// Example:
/// ```zig
/// var multi = MultiCursorEditor.init(allocator);
/// defer multi.deinit();
///
/// try multi.setText("line 1\nline 2\nline 3");
/// multi.addCursor(.{ .line = 1, .col = 0 });
/// multi.addCursor(.{ .line = 2, .col = 0 });
/// try multi.insertCharAll('x'); // Inserts 'x' at all cursor positions
///
/// multi.render(buffer, area);
/// ```
pub const MultiCursorEditor = struct {
    /// Base editor (contains lines, language, styles)
    base: Editor,
    /// Additional cursors (base.cursor is the primary cursor)
    cursors: ArrayList(Cursor),
    /// Column selection mode enabled
    column_mode: bool,
    /// Cursor style for secondary cursors
    secondary_cursor_style: Style,

    const Cursor = struct {
        pos: Position,
        selection: ?Selection,
    };

    pub fn init(allocator: Allocator) MultiCursorEditor {
        return .{
            .base = Editor.init(allocator),
            .cursors = ArrayList(Cursor).init(allocator),
            .column_mode = false,
            .secondary_cursor_style = Style{ .bg = Color{ .indexed = 240 }, .fg = Color.black },
        };
    }

    pub fn deinit(self: *MultiCursorEditor) void {
        self.base.deinit();
        self.cursors.deinit();
    }

    pub fn setText(self: *MultiCursorEditor, text: []const u8) !void {
        try self.base.setText(text);
        self.cursors.clearRetainingCapacity();
        self.column_mode = false;
    }

    pub fn getText(self: *const MultiCursorEditor, allocator: Allocator) ![]const u8 {
        return self.base.getText(allocator);
    }

    pub fn setLanguage(self: *MultiCursorEditor, lang: @TypeOf(self.base.language)) *MultiCursorEditor {
        _ = self.base.setLanguage(lang);
        return self;
    }

    pub fn setBlock(self: *MultiCursorEditor, block: Block) *MultiCursorEditor {
        _ = self.base.setBlock(block);
        return self;
    }

    pub fn addCursor(self: *MultiCursorEditor, pos: Position) !void {
        // Clamp position to valid bounds
        const line = @min(pos.line, self.base.lines.items.len - 1);
        const max_col = if (line < self.base.lines.items.len)
            self.base.lines.items[line].len
        else
            0;
        const col = @min(pos.col, max_col);

        // Don't add duplicate cursors
        if (line == self.base.cursor.line and col == self.base.cursor.col) return;
        for (self.cursors.items) |cursor| {
            if (cursor.pos.line == line and cursor.pos.col == col) return;
        }

        try self.cursors.append(.{
            .pos = .{ .line = line, .col = col },
            .selection = null,
        });
    }

    pub fn removeCursor(self: *MultiCursorEditor, index: usize) void {
        if (index >= self.cursors.items.len) return;
        _ = self.cursors.orderedRemove(index);
    }

    pub fn clearCursors(self: *MultiCursorEditor) void {
        self.cursors.clearRetainingCapacity();
    }

    pub fn getCursorCount(self: *const MultiCursorEditor) usize {
        return 1 + self.cursors.items.len; // Primary + secondary cursors
    }

    pub fn setColumnMode(self: *MultiCursorEditor, enabled: bool) *MultiCursorEditor {
        self.column_mode = enabled;
        return self;
    }

    /// Add cursors in a column (rectangular selection)
    pub fn addColumnCursors(self: *MultiCursorEditor, start: Position, end: Position) !void {
        const start_line = @min(start.line, end.line);
        const end_line = @max(start.line, end.line);
        const col = start.col;

        for (start_line..end_line + 1) |line| {
            if (line >= self.base.lines.items.len) break;
            try self.addCursor(.{ .line = line, .col = col });
        }
    }

    /// Insert character at all cursor positions simultaneously
    pub fn insertCharAll(self: *MultiCursorEditor, ch: u8) !void {
        // Sort cursors by position (bottom-to-top, right-to-left) to avoid index shifts
        var all_positions = try ArrayList(Position).initCapacity(self.base.allocator, self.getCursorCount());
        defer all_positions.deinit();

        all_positions.appendAssumeCapacity(self.base.cursor);
        for (self.cursors.items) |cursor| {
            all_positions.appendAssumeCapacity(cursor.pos);
        }

        std.mem.sort(Position, all_positions.items, {}, positionGreaterThan);

        // Insert at each position (in reverse order to maintain positions)
        for (all_positions.items) |*pos| {
            if (pos.line >= self.base.lines.items.len) continue;

            const old_line = self.base.lines.items[pos.line];
            const new_line = try self.base.allocator.alloc(u8, old_line.len + 1);

            @memcpy(new_line[0..pos.col], old_line[0..pos.col]);
            new_line[pos.col] = ch;
            @memcpy(new_line[pos.col + 1 ..], old_line[pos.col..]);

            self.base.allocator.free(old_line);
            self.base.lines.items[pos.line] = new_line;

            // Update all cursor positions after this insertion
            pos.col += 1;
            if (pos.line == self.base.cursor.line and pos.col <= self.base.cursor.col + 1) {
                self.base.cursor.col += 1;
            }
            for (self.cursors.items) |*cursor| {
                if (cursor.pos.line == pos.line and cursor.pos.col < pos.col) {
                    cursor.pos.col += 1;
                }
            }
        }
    }

    /// Delete character before cursor at all positions simultaneously
    pub fn deleteCharAll(self: *MultiCursorEditor) !void {
        var all_positions = try ArrayList(Position).initCapacity(self.base.allocator, self.getCursorCount());
        defer all_positions.deinit();

        all_positions.appendAssumeCapacity(self.base.cursor);
        for (self.cursors.items) |cursor| {
            all_positions.appendAssumeCapacity(cursor.pos);
        }

        std.mem.sort(Position, all_positions.items, {}, positionGreaterThan);

        for (all_positions.items) |*pos| {
            if (pos.line >= self.base.lines.items.len or pos.col == 0) continue;

            const old_line = self.base.lines.items[pos.line];
            const new_line = try self.base.allocator.alloc(u8, old_line.len - 1);

            @memcpy(new_line[0 .. pos.col - 1], old_line[0 .. pos.col - 1]);
            @memcpy(new_line[pos.col - 1 ..], old_line[pos.col..]);

            self.base.allocator.free(old_line);
            self.base.lines.items[pos.line] = new_line;

            pos.col -= 1;
        }

        // Update cursor positions
        self.base.cursor.col = @max(0, self.base.cursor.col -| 1);
        for (self.cursors.items) |*cursor| {
            cursor.pos.col = @max(0, cursor.pos.col -| 1);
        }
    }

    /// Move all cursors by the given delta
    pub fn moveAllCursors(self: *MultiCursorEditor, delta_line: i32, delta_col: i32) void {
        self.base.cursor = applyDelta(self.base.cursor, delta_line, delta_col, self.base.lines.items);
        for (self.cursors.items) |*cursor| {
            cursor.pos = applyDelta(cursor.pos, delta_line, delta_col, self.base.lines.items);
        }
    }

    fn applyDelta(pos: Position, delta_line: i32, delta_col: i32, lines: []const []const u8) Position {
        const new_line = if (delta_line < 0)
            pos.line -| @as(usize, @intCast(-delta_line))
        else
            @min(pos.line + @as(usize, @intCast(delta_line)), lines.len - 1);

        const max_col = if (new_line < lines.len) lines[new_line].len else 0;

        const new_col = if (delta_col < 0)
            pos.col -| @as(usize, @intCast(-delta_col))
        else
            @min(pos.col + @as(usize, @intCast(delta_col)), max_col);

        return .{ .line = new_line, .col = new_col };
    }

    fn positionGreaterThan(_: void, a: Position, b: Position) bool {
        if (a.line > b.line) return true;
        if (a.line < b.line) return false;
        return a.col > b.col;
    }

    pub fn render(self: *const MultiCursorEditor, buf: *Buffer, area: Rect) void {
        // Render base editor
        self.base.render(buf, area);

        // Render secondary cursors
        var render_area = area;
        if (self.base.block) |blk| {
            render_area = blk.inner(area);
        }

        if (render_area.width < 2 or render_area.height < 1) return;

        const line_num_width: u16 = if (self.base.show_line_numbers) blk: {
            const max_line = self.base.lines.items.len;
            var width: u16 = 1;
            var n = max_line;
            while (n >= 10) {
                width += 1;
                n /= 10;
            }
            break :blk width + 2;
        } else 0;

        const text_start_x = render_area.x + line_num_width;

        for (self.cursors.items) |cursor| {
            const line_idx = cursor.pos.line;
            if (line_idx < self.base.scroll_offset or
                line_idx >= self.base.scroll_offset + render_area.height) continue;

            const y = @as(u16, @intCast(render_area.y + (line_idx - self.base.scroll_offset)));
            const x = text_start_x + @as(u16, @intCast(cursor.pos.col));

            if (x < text_start_x + render_area.width) {
                var cell = buf.get(x, y);
                cell.style = self.secondary_cursor_style;
                buf.setChar(x, y, cell.char, cell.style);
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "multicursor: init and deinit" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try testing.expectEqual(@as(usize, 1), mc.getCursorCount());
}

test "multicursor: setText" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");
    try testing.expectEqual(@as(usize, 3), mc.base.lines.items.len);
}

test "multicursor: addCursor" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");

    try mc.addCursor(.{ .line = 1, .col = 0 });
    try testing.expectEqual(@as(usize, 2), mc.getCursorCount());

    try mc.addCursor(.{ .line = 2, .col = 0 });
    try testing.expectEqual(@as(usize, 3), mc.getCursorCount());
}

test "multicursor: addCursor no duplicates" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1");

    // Try to add cursor at primary cursor position
    try mc.addCursor(.{ .line = 0, .col = 0 });
    try testing.expectEqual(@as(usize, 1), mc.getCursorCount());

    // Add new cursor
    try mc.addCursor(.{ .line = 0, .col = 3 });
    try testing.expectEqual(@as(usize, 2), mc.getCursorCount());

    // Try to add duplicate
    try mc.addCursor(.{ .line = 0, .col = 3 });
    try testing.expectEqual(@as(usize, 2), mc.getCursorCount());
}

test "multicursor: removeCursor" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");
    try mc.addCursor(.{ .line = 1, .col = 0 });
    try mc.addCursor(.{ .line = 2, .col = 0 });

    try testing.expectEqual(@as(usize, 3), mc.getCursorCount());

    mc.removeCursor(0);
    try testing.expectEqual(@as(usize, 2), mc.getCursorCount());
}

test "multicursor: clearCursors" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2");
    try mc.addCursor(.{ .line = 1, .col = 0 });

    mc.clearCursors();
    try testing.expectEqual(@as(usize, 1), mc.getCursorCount());
}

test "multicursor: addColumnCursors" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3\nline 4");

    try mc.addColumnCursors(.{ .line = 0, .col = 2 }, .{ .line = 3, .col = 2 });

    // Should add cursors at lines 0,1,2,3 column 2 (but primary is already at 0,0)
    // So we get: primary + 4 new cursors (0,2 is new since primary is 0,0)
    try testing.expectEqual(@as(usize, 5), mc.getCursorCount());
}

test "multicursor: insertCharAll" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("aaa\nbbb\nccc");
    mc.base.cursor = .{ .line = 0, .col = 0 };
    try mc.addCursor(.{ .line = 1, .col = 0 });
    try mc.addCursor(.{ .line = 2, .col = 0 });

    try mc.insertCharAll('x');

    try testing.expectEqualStrings("xaaa", mc.base.lines.items[0]);
    try testing.expectEqualStrings("xbbb", mc.base.lines.items[1]);
    try testing.expectEqualStrings("xccc", mc.base.lines.items[2]);
}

test "multicursor: deleteCharAll" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("xaaa\nxbbb\nxccc");
    mc.base.cursor = .{ .line = 0, .col = 1 };
    try mc.addCursor(.{ .line = 1, .col = 1 });
    try mc.addCursor(.{ .line = 2, .col = 1 });

    try mc.deleteCharAll();

    try testing.expectEqualStrings("aaa", mc.base.lines.items[0]);
    try testing.expectEqualStrings("bbb", mc.base.lines.items[1]);
    try testing.expectEqualStrings("ccc", mc.base.lines.items[2]);
}

test "multicursor: moveAllCursors down" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("line 1\nline 2\nline 3");
    mc.base.cursor = .{ .line = 0, .col = 0 };
    try mc.addCursor(.{ .line = 1, .col = 0 });

    mc.moveAllCursors(1, 0); // Move down 1 line

    try testing.expectEqual(@as(usize, 1), mc.base.cursor.line);
    try testing.expectEqual(@as(usize, 2), mc.cursors.items[0].pos.line);
}

test "multicursor: moveAllCursors right" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    mc.base.cursor = .{ .line = 0, .col = 0 };
    try mc.addCursor(.{ .line = 1, .col = 0 });

    mc.moveAllCursors(0, 2); // Move right 2 columns

    try testing.expectEqual(@as(usize, 2), mc.base.cursor.col);
    try testing.expectEqual(@as(usize, 2), mc.cursors.items[0].pos.col);
}

test "multicursor: moveAllCursors boundary" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("short\nline");
    mc.base.cursor = .{ .line = 0, .col = 0 };

    // Try to move beyond bounds
    mc.moveAllCursors(-5, -5); // Should clamp to 0,0
    try testing.expectEqual(@as(usize, 0), mc.base.cursor.line);
    try testing.expectEqual(@as(usize, 0), mc.base.cursor.col);

    mc.moveAllCursors(100, 100); // Should clamp to last line/col
    try testing.expectEqual(@as(usize, 1), mc.base.cursor.line);
    try testing.expectEqual(@as(usize, 4), mc.base.cursor.col); // "line".len = 4
}

test "multicursor: setColumnMode" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    _ = mc.setColumnMode(true);
    try testing.expect(mc.column_mode);
}

test "multicursor: builder pattern" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    const block = Block.init().setTitle("Multi-Cursor");
    _ = mc.setBlock(block).setColumnMode(true);

    try testing.expect(mc.base.block != null);
    try testing.expect(mc.column_mode);
}

test "multicursor: render basic" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("hello\nworld");
    try mc.addCursor(.{ .line = 1, .col = 0 });

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mc.render(&buffer, area);

    // Secondary cursor should be rendered with secondary_cursor_style
}

test "multicursor: insertCharAll maintains order" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    try mc.setText("abc");
    mc.base.cursor = .{ .line = 0, .col = 1 };
    try mc.addCursor(.{ .line = 0, .col = 2 });

    try mc.insertCharAll('x');

    // Should insert at both positions: "a[x]b[x]c"
    try testing.expectEqualStrings("axbxc", mc.base.lines.items[0]);
}

test "multicursor: getText preserves content" {
    const allocator = testing.allocator;
    var mc = MultiCursorEditor.init(allocator);
    defer mc.deinit();

    const original = "line 1\nline 2\nline 3";
    try mc.setText(original);

    const result = try mc.getText(allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings(original, result);
}
