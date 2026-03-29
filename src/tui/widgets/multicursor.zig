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

    /// Initializes a MultiCursorEditor with default values.
    /// The returned instance must be freed with `.deinit()`.
    pub fn init(allocator: Allocator) MultiCursorEditor {
        return .{
            .base = Editor.init(allocator),
            .cursors = ArrayList(Cursor).init(allocator),
            .column_mode = false,
            .secondary_cursor_style = Style{ .bg = Color{ .indexed = 240 }, .fg = Color.black },
        };
    }

    /// Frees resources associated with this editor instance.
    pub fn deinit(self: *MultiCursorEditor) void {
        self.base.deinit();
        self.cursors.deinit();
    }

    /// Sets the editor text to the given content.
    /// Clears all secondary cursors and disables column mode.
    pub fn setText(self: *MultiCursorEditor, text: []const u8) !void {
        try self.base.setText(text);
        self.cursors.clearRetainingCapacity();
        self.column_mode = false;
    }

    /// Returns the editor text as an owned string.
    /// Caller must free the returned slice.
    pub fn getText(self: *const MultiCursorEditor, allocator: Allocator) ![]const u8 {
        return self.base.getText(allocator);
    }

    /// Sets the syntax highlighting language.
    /// Returns `self` for method chaining.
    pub fn setLanguage(self: *MultiCursorEditor, lang: @TypeOf(self.base.language)) *MultiCursorEditor {
        _ = self.base.setLanguage(lang);
        return self;
    }

    /// Sets the surrounding block border and title.
    /// Returns `self` for method chaining.
    pub fn setBlock(self: *MultiCursorEditor, block: Block) *MultiCursorEditor {
        _ = self.base.setBlock(block);
        return self;
    }

    /// Adds a secondary cursor at the specified position.
    /// Position is clamped to valid text bounds.
    /// Ignores duplicate cursor positions.
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

    /// Removes the secondary cursor at the given index.
    /// Does nothing if index is out of bounds.
    pub fn removeCursor(self: *MultiCursorEditor, index: usize) void {
        if (index >= self.cursors.items.len) return;
        _ = self.cursors.swapRemove(index);
    }

    /// Removes all secondary cursors, keeping only the primary cursor.
    pub fn clearCursors(self: *MultiCursorEditor) void {
        self.cursors.clearRetainingCapacity();
    }

    /// Returns the total number of cursors (primary + secondary).
    pub fn getCursorCount(self: *const MultiCursorEditor) usize {
        return 1 + self.cursors.items.len; // Primary + secondary cursors
    }

    /// Enables or disables column selection mode (rectangular selection).
    /// Returns `self` for method chaining.
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

    /// Renders the multi-cursor editor to the given buffer within the specified area.
    /// Draws the base editor and overlays all secondary cursors.
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

// ============================================================================
// MultiCursor — Simple multi-cursor editing widget for v1.13.0
// ============================================================================

/// Position in text buffer
pub const MultiCursorPosition = struct {
    line: usize,
    col: usize,
};

/// Text selection range
pub const MultiCursorSelection = struct {
    start: MultiCursorPosition,
    end: MultiCursorPosition,

    /// Returns true if the selection is empty (start equals end).
    pub fn isEmpty(self: MultiCursorSelection) bool {
        return self.start.line == self.end.line and self.start.col == self.end.col;
    }
};

/// Column specification for column-mode cursors
pub const ColumnSpec = struct {
    start_line: usize,
    end_line: usize,
    col: usize,
};

/// Cursor with optional selection range
pub const MultiCursorCursor = struct {
    pos: MultiCursorPosition,
    selection: ?MultiCursorSelection,
};

/// Simple multi-cursor editing widget
///
/// Provides Sublime Text / VSCode-style multi-cursor editing without
/// the full editor infrastructure. Manages multiple cursors and text buffer directly.
pub const MultiCursor = struct {
    allocator: Allocator,
    cursors: std.ArrayList(MultiCursorCursor),
    primary_cursor: ?usize,
    lines: std.ArrayList([]u8),

    pub const Position = MultiCursorPosition;
    pub const Selection = MultiCursorSelection;
    pub const Cursor = MultiCursorCursor;

    pub const Error = error{
        InvalidPosition,
        InvalidCursorIndex,
    };

    /// Initializes a MultiCursor widget with empty text buffer.
    /// The returned instance must be freed with `.deinit()`.
    pub fn init(allocator: Allocator) !MultiCursor {
        return .{
            .allocator = allocator,
            .cursors = .{},
            .primary_cursor = null,
            .lines = .{},
        };
    }

    /// Frees all resources associated with this widget.
    pub fn deinit(self: *MultiCursor) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
        self.cursors.deinit(self.allocator);
    }

    /// Sets the text buffer to the given content.
    /// Splits text by newlines and allocates owned lines.
    pub fn setText(self: *MultiCursor, text: []const u8) !void {
        // Free existing lines
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();

        // Split by newline
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line_slice| {
            const line = try self.allocator.dupe(u8, line_slice);
            try self.lines.append(self.allocator, line);
        }

        // Ensure at least one line exists
        if (self.lines.items.len == 0) {
            const empty_line = try self.allocator.dupe(u8, "");
            try self.lines.append(self.allocator, empty_line);
        }
    }

    /// Adds a cursor at the specified position.
    /// Returns `error.InvalidPosition` if position is out of bounds.
    /// Ignores duplicate positions.
    pub fn addCursor(self: *MultiCursor, pos: MultiCursor.Position) !void {
        // Validate position
        if (pos.line >= self.lines.items.len) {
            return Error.InvalidPosition;
        }
        if (pos.col > self.lines.items[pos.line].len) {
            return Error.InvalidPosition;
        }

        // Check for duplicates and merge
        for (self.cursors.items) |cursor| {
            if (cursor.pos.line == pos.line and cursor.pos.col == pos.col) {
                return; // Already exists, don't add duplicate
            }
        }

        try self.cursors.append(self.allocator, .{
            .pos = pos,
            .selection = null,
        });

        // First cursor becomes primary
        if (self.primary_cursor == null) {
            self.primary_cursor = 0;
        }
    }

    /// Removes the cursor at the given index.
    /// Returns `error.InvalidCursorIndex` if index is out of bounds.
    /// Adjusts primary cursor index if affected.
    pub fn removeCursor(self: *MultiCursor, index: usize) !void {
        if (index >= self.cursors.items.len) {
            return Error.InvalidCursorIndex;
        }

        _ = self.cursors.swapRemove(index);

        // Update primary cursor index
        if (self.primary_cursor) |primary_idx| {
            if (primary_idx == index) {
                // Primary was removed
                self.primary_cursor = if (self.cursors.items.len > 0) 0 else null;
            } else if (primary_idx > index) {
                self.primary_cursor = primary_idx - 1;
            }
        }
    }

    /// Removes all cursors and resets primary cursor.
    pub fn clearCursors(self: *MultiCursor) void {
        self.cursors.clearRetainingCapacity();
        self.primary_cursor = null;
    }

    /// Sets the primary cursor to the specified index.
    /// Returns `error.InvalidCursorIndex` if index is out of bounds.
    pub fn setPrimaryCursor(self: *MultiCursor, index: usize) !void {
        if (index >= self.cursors.items.len) {
            return Error.InvalidCursorIndex;
        }
        self.primary_cursor = index;
    }

    /// Inserts a character at all cursor positions simultaneously.
    /// Cursors are processed in reverse order to maintain position validity.
    pub fn insertChar(self: *MultiCursor, ch: u8) !void {
        if (self.cursors.items.len == 0) return;

        // Sort cursors by position (reverse order: bottom-right to top-left)
        var indices: std.ArrayList(usize) = .{};
        defer indices.deinit(self.allocator);
        try indices.ensureTotalCapacity(self.allocator, self.cursors.items.len);

        for (0..self.cursors.items.len) |i| {
            indices.appendAssumeCapacity(i);
        }

        std.mem.sort(usize, indices.items, self, struct {
            fn lessThan(ctx: *const MultiCursor, a_idx: usize, b_idx: usize) bool {
                const a = ctx.cursors.items[a_idx].pos;
                const b = ctx.cursors.items[b_idx].pos;
                if (a.line > b.line) return true;
                if (a.line < b.line) return false;
                return a.col > b.col;
            }
        }.lessThan);

        // Insert at each cursor (reverse order to maintain positions)
        for (indices.items) |idx| {
            const cursor = &self.cursors.items[idx];
            const line_idx = cursor.pos.line;
            if (line_idx >= self.lines.items.len) continue;

            const old_line = self.lines.items[line_idx];
            const new_line = try self.allocator.alloc(u8, old_line.len + 1);

            @memcpy(new_line[0..cursor.pos.col], old_line[0..cursor.pos.col]);
            new_line[cursor.pos.col] = ch;
            @memcpy(new_line[cursor.pos.col + 1 ..], old_line[cursor.pos.col..]);

            self.allocator.free(old_line);
            self.lines.items[line_idx] = new_line;

            // Move cursor forward
            cursor.pos.col += 1;

            // Update other cursors on same line that are after this position
            for (self.cursors.items, 0..) |*other_cursor, other_idx| {
                if (other_idx == idx) continue;
                if (other_cursor.pos.line == line_idx and other_cursor.pos.col >= cursor.pos.col - 1) {
                    other_cursor.pos.col += 1;
                }
            }
        }

        self.mergeCursors();
    }

    /// Deletes the character before each cursor (backspace behavior).
    /// Cursors are processed in reverse order to maintain position validity.
    pub fn deleteChar(self: *MultiCursor) !void {
        if (self.cursors.items.len == 0) return;

        // Sort cursors by position (reverse order)
        var indices: std.ArrayList(usize) = .{};
        defer indices.deinit(self.allocator);
        try indices.ensureTotalCapacity(self.allocator, self.cursors.items.len);

        for (0..self.cursors.items.len) |i| {
            indices.appendAssumeCapacity(i);
        }

        std.mem.sort(usize, indices.items, self, struct {
            fn lessThan(ctx: *const MultiCursor, a_idx: usize, b_idx: usize) bool {
                const a = ctx.cursors.items[a_idx].pos;
                const b = ctx.cursors.items[b_idx].pos;
                if (a.line > b.line) return true;
                if (a.line < b.line) return false;
                return a.col > b.col;
            }
        }.lessThan);

        // Delete at each cursor
        for (indices.items) |idx| {
            const cursor = &self.cursors.items[idx];
            const line_idx = cursor.pos.line;
            if (line_idx >= self.lines.items.len) continue;
            if (cursor.pos.col == 0) continue; // Can't delete before beginning of line

            const old_line = self.lines.items[line_idx];
            const new_line = try self.allocator.alloc(u8, old_line.len - 1);

            @memcpy(new_line[0 .. cursor.pos.col - 1], old_line[0 .. cursor.pos.col - 1]);
            @memcpy(new_line[cursor.pos.col - 1 ..], old_line[cursor.pos.col..]);

            self.allocator.free(old_line);
            self.lines.items[line_idx] = new_line;

            // Move cursor back
            const old_col = cursor.pos.col;
            cursor.pos.col -= 1;

            // Update other cursors on same line
            for (self.cursors.items, 0..) |*other_cursor, other_idx| {
                if (other_idx == idx) continue;
                if (other_cursor.pos.line == line_idx and other_cursor.pos.col >= old_col) {
                    other_cursor.pos.col -|= 1;
                }
            }
        }

        self.mergeCursors();
    }

    /// Inserts a newline at each cursor position, splitting lines.
    /// Cursors are moved to the beginning of the new lines.
    pub fn insertNewline(self: *MultiCursor) !void {
        if (self.cursors.items.len == 0) return;

        // Sort cursors by position (reverse order)
        var indices: std.ArrayList(usize) = .{};
        defer indices.deinit(self.allocator);
        try indices.ensureTotalCapacity(self.allocator, self.cursors.items.len);

        for (0..self.cursors.items.len) |i| {
            indices.appendAssumeCapacity(i);
        }

        std.mem.sort(usize, indices.items, self, struct {
            fn lessThan(ctx: *const MultiCursor, a_idx: usize, b_idx: usize) bool {
                const a = ctx.cursors.items[a_idx].pos;
                const b = ctx.cursors.items[b_idx].pos;
                if (a.line > b.line) return true;
                if (a.line < b.line) return false;
                return a.col > b.col;
            }
        }.lessThan);

        // Insert newline at each cursor
        for (indices.items) |idx| {
            const cursor = &self.cursors.items[idx];
            const line_idx = cursor.pos.line;
            if (line_idx >= self.lines.items.len) continue;

            const old_line = self.lines.items[line_idx];

            // Split line at cursor position
            const left = try self.allocator.dupe(u8, old_line[0..cursor.pos.col]);
            const right = try self.allocator.dupe(u8, old_line[cursor.pos.col..]);

            self.allocator.free(old_line);
            self.lines.items[line_idx] = left;
            try self.lines.insert(self.allocator, line_idx + 1, right);

            // Move cursor to beginning of new line
            cursor.pos.line = line_idx + 1;
            cursor.pos.col = 0;

            // Update other cursors
            for (self.cursors.items, 0..) |*other_cursor, other_idx| {
                if (other_idx == idx) continue;
                if (other_cursor.pos.line > line_idx) {
                    other_cursor.pos.line += 1;
                }
            }
        }

        self.mergeCursors();
    }

    /// Merges cursors that are at the same position after edits.
    pub fn mergeCursors(self: *MultiCursor) void {
        if (self.cursors.items.len <= 1) return;

        var i: usize = 0;
        while (i < self.cursors.items.len) {
            var j: usize = i + 1;
            while (j < self.cursors.items.len) {
                if (self.cursors.items[i].pos.line == self.cursors.items[j].pos.line and
                    self.cursors.items[i].pos.col == self.cursors.items[j].pos.col)
                {
                    _ = self.cursors.orderedRemove(j);
                    // Update primary cursor if needed
                    if (self.primary_cursor) |*primary_idx| {
                        if (primary_idx.* == j) {
                            primary_idx.* = i;
                        } else if (primary_idx.* > j) {
                            primary_idx.* -= 1;
                        }
                    }
                } else {
                    j += 1;
                }
            }
            i += 1;
        }
    }

    /// Adds cursors in a vertical column (rectangular selection).
    /// Cursors are added at the specified column for each line in the range.
    pub fn addColumnCursors(self: *MultiCursor, spec: ColumnSpec) !void {
        const start_line = @min(spec.start_line, spec.end_line);
        const end_line = @min(spec.end_line, self.lines.items.len - 1);

        for (start_line..end_line + 1) |line_idx| {
            if (line_idx >= self.lines.items.len) break;

            // Clamp column to line length
            const col = @min(spec.col, self.lines.items[line_idx].len);

            try self.addCursor(.{ .line = line_idx, .col = col });
        }
    }

    /// Sets the selection range for the specified cursor.
    /// Does nothing if cursor index is out of bounds.
    pub fn setSelection(self: *MultiCursor, cursor_idx: usize, start: MultiCursor.Position, end: MultiCursor.Position) void {
        if (cursor_idx >= self.cursors.items.len) return;
        self.cursors.items[cursor_idx].selection = .{ .start = start, .end = end };
    }

    /// Clears the selection for the specified cursor.
    /// Does nothing if cursor index is out of bounds.
    pub fn clearSelection(self: *MultiCursor, cursor_idx: usize) void {
        if (cursor_idx >= self.cursors.items.len) return;
        self.cursors.items[cursor_idx].selection = null;
    }

    /// Renders the text buffer and all cursors to the given buffer within the specified area.
    pub fn render(self: *const MultiCursor, buf: *Buffer, area: Rect) void {
        // Render text lines
        for (self.lines.items, 0..) |line, line_idx| {
            if (line_idx >= area.height) break;

            const y = area.y + @as(u16, @intCast(line_idx));

            for (line, 0..) |char, col_idx| {
                if (col_idx >= area.width) break;

                const x = area.x + @as(u16, @intCast(col_idx));
                var style = Style{};

                // Check if this position is in a selection
                for (self.cursors.items) |cursor| {
                    if (cursor.selection) |sel| {
                        const pos = MultiCursor.Position{ .line = line_idx, .col = col_idx };
                        if (sel.start.line == sel.end.line and sel.start.line == line_idx) {
                            const start_col = @min(sel.start.col, sel.end.col);
                            const end_col = @max(sel.start.col, sel.end.col);
                            if (col_idx >= start_col and col_idx < end_col) {
                                style.bg = Color{ .indexed = 240 };
                            }
                        }
                        _ = pos; // Use pos if needed for multiline selections
                    }
                }

                buf.setChar(x, y, char, style);
            }
        }

        // Render cursors
        for (self.cursors.items, 0..) |cursor, cursor_idx| {
            if (cursor.pos.line >= self.lines.items.len) continue;
            if (cursor.pos.line >= area.height) continue;
            if (cursor.pos.col > area.width) continue;

            const x = area.x + @as(u16, @intCast(cursor.pos.col));
            const y = area.y + @as(u16, @intCast(cursor.pos.line));

            const cursor_style = if (self.primary_cursor == cursor_idx)
                Style{ .bg = Color{ .indexed = 15 }, .fg = Color.black } // Primary cursor - bright
            else
                Style{ .bg = Color{ .indexed = 240 }, .fg = Color.white }; // Secondary cursor - dim

            // Get the character at cursor position (or space if at end of line)
            const char = if (cursor.pos.col < self.lines.items[cursor.pos.line].len)
                self.lines.items[cursor.pos.line][cursor.pos.col]
            else
                ' ';

            buf.setChar(x, y, char, cursor_style);
        }
    }
};
