const std = @import("std");
const tui = @import("../tui.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const syntax = @import("../syntax.zig");
const Lexer = syntax.Lexer;
const Language = syntax.Language;
const TokenType = syntax.TokenType;

/// Text selection in the editor
pub const Selection = struct {
    start: Position,
    end: Position,

    /// Returns true if the selection is empty (start equals end).
    pub fn isEmpty(self: Selection) bool {
        return self.start.line == self.end.line and self.start.col == self.end.col;
    }

    /// Returns the selection with start guaranteed to be before or equal to end.
    pub fn normalized(self: Selection) Selection {
        if (self.start.line < self.end.line or
            (self.start.line == self.end.line and self.start.col < self.end.col))
        {
            return self;
        }
        return .{ .start = self.end, .end = self.start };
    }

    /// Returns true if the given position is within the normalized selection bounds.
    pub fn contains(self: Selection, pos: Position) bool {
        const norm = self.normalized();
        if (pos.line < norm.start.line or pos.line > norm.end.line) return false;
        if (pos.line == norm.start.line and pos.col < norm.start.col) return false;
        if (pos.line == norm.end.line and pos.col >= norm.end.col) return false;
        return true;
    }
};

/// Cursor position in the editor
pub const Position = struct {
    line: usize,
    col: usize,
};

/// Edit operation for undo/redo
pub const Edit = struct {
    type: enum { insert, delete },
    pos: Position,
    text: []const u8,
    allocator: std.mem.Allocator,

    /// Frees the text memory owned by this edit operation.
    pub fn deinit(self: *Edit) void {
        self.allocator.free(self.text);
    }
};

/// Code editor widget with line numbers, selection, undo/redo, and syntax highlighting
pub const Editor = struct {
    /// Lines of text in the editor
    lines: std.ArrayList([]const u8),
    /// Current cursor position
    cursor: Position,
    /// Current selection (if any)
    selection: ?Selection,
    /// Undo stack
    undo_stack: std.ArrayList(Edit),
    /// Redo stack
    redo_stack: std.ArrayList(Edit),
    /// Scroll offset (top visible line)
    scroll_offset: usize,
    /// Language for syntax highlighting
    language: Language,
    /// Optional block border
    block: ?Block,
    /// Show line numbers
    show_line_numbers: bool,
    /// Line number style
    line_number_style: Style,
    /// Selection style
    selection_style: Style,
    /// Cursor style
    cursor_style: Style,
    /// Allocator for internal memory
    allocator: std.mem.Allocator,

    /// Initializes a new editor with a single empty line.
    /// The returned instance must be freed with `.deinit()`.
    pub fn init(allocator: std.mem.Allocator) Editor {
        var lines = std.ArrayList([]const u8){};
        // Start with one empty line
        lines.append(allocator, "") catch unreachable;

        return .{
            .lines = lines,
            .cursor = .{ .line = 0, .col = 0 },
            .selection = null,
            .undo_stack = std.ArrayList(Edit){},
            .redo_stack = std.ArrayList(Edit){},
            .scroll_offset = 0,
            .language = .none,
            .block = null,
            .show_line_numbers = true,
            .line_number_style = Style{ .fg = Color{ .indexed = 8 } }, // gray
            .selection_style = Style{ .bg = Color{ .indexed = 237 } }, // dark gray bg
            .cursor_style = Style{ .bg = Color.white, .fg = Color.black },
            .allocator = allocator,
        };
    }

    /// Frees all resources owned by this editor including lines and undo/redo stacks.
    pub fn deinit(self: *Editor) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);

        for (self.undo_stack.items) |*edit| {
            edit.deinit();
        }
        self.undo_stack.deinit(self.allocator);

        for (self.redo_stack.items) |*edit| {
            edit.deinit();
        }
        self.redo_stack.deinit(self.allocator);
    }

    /// Replaces the entire editor content with the given text.
    /// Clears undo/redo history and resets cursor to the beginning.
    pub fn setText(self: *Editor, text: []const u8) !void {
        // Clear existing lines
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();

        // Split text into lines
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            const owned = try self.allocator.dupe(u8, line);
            errdefer self.allocator.free(owned);
            try self.lines.append(self.allocator, owned);
        }

        // Ensure at least one line
        if (self.lines.items.len == 0) {
            try self.lines.append(self.allocator, try self.allocator.dupe(u8, ""));
        }

        // Reset cursor and clear undo/redo
        self.cursor = .{ .line = 0, .col = 0 };
        self.selection = null;
        self.scroll_offset = 0;

        for (self.undo_stack.items) |*edit| edit.deinit();
        self.undo_stack.clearRetainingCapacity();
        for (self.redo_stack.items) |*edit| edit.deinit();
        self.redo_stack.clearRetainingCapacity();
    }

    /// Returns the entire editor content as a single string with newline separators.
    /// Caller owns the returned memory.
    pub fn getText(self: *const Editor, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8){};
        defer result.deinit(allocator);

        for (self.lines.items, 0..) |line, i| {
            try result.appendSlice(allocator, line);
            if (i < self.lines.items.len - 1) {
                try result.append(allocator, '\n');
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Sets the syntax highlighting language.
    /// Returns `self` for method chaining.
    pub fn setLanguage(self: *Editor, lang: Language) *Editor {
        self.language = lang;
        return self;
    }

    /// Sets the optional border block around the editor.
    /// Returns `self` for method chaining.
    pub fn setBlock(self: *Editor, block: Block) *Editor {
        self.block = block;
        return self;
    }

    /// Sets whether to display line numbers in the left gutter.
    /// Returns `self` for method chaining.
    pub fn setShowLineNumbers(self: *Editor, show: bool) *Editor {
        self.show_line_numbers = show;
        return self;
    }

    /// Inserts a character at the current cursor position.
    /// Pushes the operation onto the undo stack and clears the redo stack.
    pub fn insertChar(self: *Editor, ch: u8) !void {
        const line_idx = self.cursor.line;
        if (line_idx >= self.lines.items.len) return;

        const old_line = self.lines.items[line_idx];
        var new_line = try self.allocator.alloc(u8, old_line.len + 1);

        // Copy before cursor
        @memcpy(new_line[0..self.cursor.col], old_line[0..self.cursor.col]);
        // Insert character
        new_line[self.cursor.col] = ch;
        // Copy after cursor
        @memcpy(new_line[self.cursor.col + 1..], old_line[self.cursor.col..]);

        // Record edit for undo
        const edit_text = try self.allocator.dupe(u8, &[_]u8{ch});
        errdefer self.allocator.free(edit_text);
        try self.undo_stack.append(self.allocator, .{
            .type = .insert,
            .pos = self.cursor,
            .text = edit_text,
            .allocator = self.allocator,
        });

        // Clear redo stack
        for (self.redo_stack.items) |*edit| edit.deinit();
        self.redo_stack.clearRetainingCapacity();

        self.allocator.free(old_line);
        self.lines.items[line_idx] = new_line;
        self.cursor.col += 1;
    }

    /// Deletes the character before the cursor (backspace).
    /// Pushes the operation onto the undo stack and clears the redo stack.
    pub fn deleteChar(self: *Editor) !void {
        const line_idx = self.cursor.line;
        if (line_idx >= self.lines.items.len or self.cursor.col == 0) return;

        const old_line = self.lines.items[line_idx];
        var new_line = try self.allocator.alloc(u8, old_line.len - 1);

        // Copy before cursor-1
        @memcpy(new_line[0..self.cursor.col - 1], old_line[0..self.cursor.col - 1]);
        // Copy after cursor
        @memcpy(new_line[self.cursor.col - 1..], old_line[self.cursor.col..]);

        // Record edit for undo
        const edit_text = try self.allocator.dupe(u8, old_line[self.cursor.col - 1 .. self.cursor.col]);
        errdefer self.allocator.free(edit_text);
        try self.undo_stack.append(self.allocator, .{
            .type = .delete,
            .pos = .{ .line = line_idx, .col = self.cursor.col - 1 },
            .text = edit_text,
            .allocator = self.allocator,
        });

        // Clear redo stack
        for (self.redo_stack.items) |*edit| edit.deinit();
        self.redo_stack.clearRetainingCapacity();

        self.allocator.free(old_line);
        self.lines.items[line_idx] = new_line;
        self.cursor.col -= 1;
    }

    /// Inserts a newline at the current cursor position, splitting the line.
    /// Moves cursor to the beginning of the new line.
    pub fn insertNewline(self: *Editor) !void {
        const line_idx = self.cursor.line;
        if (line_idx >= self.lines.items.len) return;

        const old_line = self.lines.items[line_idx];
        const left = try self.allocator.dupe(u8, old_line[0..self.cursor.col]);
        errdefer self.allocator.free(left);
        const right = try self.allocator.dupe(u8, old_line[self.cursor.col..]);
        errdefer self.allocator.free(right);

        self.allocator.free(old_line);
        self.lines.items[line_idx] = left;
        try self.lines.insert(self.allocator, line_idx + 1, right);

        self.cursor.line += 1;
        self.cursor.col = 0;
    }

    /// Undoes the last edit operation.
    /// Moves the operation from the undo stack to the redo stack.
    pub fn undo(self: *Editor) !void {
        if (self.undo_stack.items.len == 0) return;

        var edit = self.undo_stack.pop();
        defer edit.deinit();

        switch (edit.type) {
            .insert => {
                // Remove inserted text
                const line_idx = edit.pos.line;
                if (line_idx >= self.lines.items.len) return;

                const old_line = self.lines.items[line_idx];
                const new_line = try self.allocator.alloc(u8, old_line.len - edit.text.len);
                @memcpy(new_line[0..edit.pos.col], old_line[0..edit.pos.col]);
                @memcpy(new_line[edit.pos.col..], old_line[edit.pos.col + edit.text.len..]);

                self.allocator.free(old_line);
                self.lines.items[line_idx] = new_line;
                self.cursor = edit.pos;
            },
            .delete => {
                // Re-insert deleted text
                const line_idx = edit.pos.line;
                if (line_idx >= self.lines.items.len) return;

                const old_line = self.lines.items[line_idx];
                const new_line = try self.allocator.alloc(u8, old_line.len + edit.text.len);
                @memcpy(new_line[0..edit.pos.col], old_line[0..edit.pos.col]);
                @memcpy(new_line[edit.pos.col..edit.pos.col + edit.text.len], edit.text);
                @memcpy(new_line[edit.pos.col + edit.text.len..], old_line[edit.pos.col..]);

                self.allocator.free(old_line);
                self.lines.items[line_idx] = new_line;
                self.cursor = .{ .line = edit.pos.line, .col = edit.pos.col + edit.text.len };
            },
        }

        // Move to redo stack
        try self.redo_stack.append(self.allocator, edit);
    }

    /// Redoes the last undone edit operation.
    /// Moves the operation from the redo stack back to the undo stack.
    pub fn redo(self: *Editor) !void {
        if (self.redo_stack.items.len == 0) return;

        var edit = self.redo_stack.pop();
        defer edit.deinit();

        switch (edit.type) {
            .insert => {
                // Re-insert text
                const line_idx = edit.pos.line;
                if (line_idx >= self.lines.items.len) return;

                const old_line = self.lines.items[line_idx];
                const new_line = try self.allocator.alloc(u8, old_line.len + edit.text.len);
                @memcpy(new_line[0..edit.pos.col], old_line[0..edit.pos.col]);
                @memcpy(new_line[edit.pos.col..edit.pos.col + edit.text.len], edit.text);
                @memcpy(new_line[edit.pos.col + edit.text.len..], old_line[edit.pos.col..]);

                self.allocator.free(old_line);
                self.lines.items[line_idx] = new_line;
                self.cursor = .{ .line = edit.pos.line, .col = edit.pos.col + edit.text.len };
            },
            .delete => {
                // Re-delete text
                const line_idx = edit.pos.line;
                if (line_idx >= self.lines.items.len) return;

                const old_line = self.lines.items[line_idx];
                const new_line = try self.allocator.alloc(u8, old_line.len - edit.text.len);
                @memcpy(new_line[0..edit.pos.col], old_line[0..edit.pos.col]);
                @memcpy(new_line[edit.pos.col..], old_line[edit.pos.col + edit.text.len..]);

                self.allocator.free(old_line);
                self.lines.items[line_idx] = new_line;
                self.cursor = edit.pos;
            },
        }

        // Move back to undo stack
        try self.undo_stack.append(self.allocator, edit);
    }

    /// Moves the cursor to the specified line and column.
    /// Clamps the position to valid bounds within the document.
    pub fn moveCursor(self: *Editor, line: usize, col: usize) void {
        self.cursor.line = @min(line, self.lines.items.len - 1);
        const max_col = if (self.cursor.line < self.lines.items.len)
            self.lines.items[self.cursor.line].len
        else
            0;
        self.cursor.col = @min(col, max_col);
    }

    /// Sets the current text selection between two positions.
    pub fn setSelection(self: *Editor, start: Position, end: Position) void {
        self.selection = Selection{ .start = start, .end = end };
    }

    /// Clears the current text selection.
    pub fn clearSelection(self: *Editor) void {
        self.selection = null;
    }

    /// Renders the editor to the buffer within the specified area.
    /// Displays line numbers, syntax highlighting, selection, and cursor.
    pub fn render(self: *const Editor, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |blk| {
            blk.render(buf, area);
            render_area = blk.inner(area);
        }

        if (render_area.width < 2 or render_area.height < 1) return;

        // Calculate line number width
        const line_num_width: u16 = if (self.show_line_numbers) blk: {
            const max_line = self.lines.items.len;
            var width: u16 = 1;
            var n = max_line;
            while (n >= 10) {
                width += 1;
                n /= 10;
            }
            break :blk width + 2; // +1 for space after, +1 for padding
        } else 0;

        const text_start_x = render_area.x + line_num_width;
        const text_width = if (render_area.width > line_num_width)
            render_area.width - line_num_width
        else
            0;

        if (text_width == 0) return;

        // Tokenize all visible lines if language is set
        var tokens_by_line = std.ArrayList([]syntax.Token){};
        defer {
            for (tokens_by_line.items) |tokens| {
                self.allocator.free(tokens);
            }
            tokens_by_line.deinit(self.allocator);
        }

        if (self.language != .none) {
            for (0..render_area.height) |dy| {
                const line_idx = self.scroll_offset + dy;
                if (line_idx >= self.lines.items.len) break;

                const line_text = self.lines.items[line_idx];
                var lexer = Lexer.init(self.language, line_text);
                const tokens = lexer.tokenize(self.allocator) catch &[_]syntax.Token{};
                tokens_by_line.append(self.allocator, tokens) catch {};
            }
        }

        // Render visible lines
        for (0..render_area.height) |dy| {
            const line_idx = self.scroll_offset + dy;
            const y = @as(u16, @intCast(render_area.y + dy));

            if (line_idx >= self.lines.items.len) break;

            // Render line number
            if (self.show_line_numbers) {
                const line_num_str = std.fmt.allocPrint(
                    self.allocator,
                    "{d: >[1]}",
                    .{ line_idx + 1, line_num_width - 1 },
                ) catch break;
                defer self.allocator.free(line_num_str);

                for (line_num_str, 0..) |ch, i| {
                    const x = @as(u16, @intCast(render_area.x + i));
                    buf.setChar(x, y, ch, self.line_number_style);
                }
            }

            // Render text with syntax highlighting
            const line_text = self.lines.items[line_idx];
            var x_offset: u16 = 0;

            if (self.language != .none and dy < tokens_by_line.items.len) {
                const tokens = tokens_by_line.items[dy];
                for (tokens) |token| {
                    const token_text = token.text(line_text);
                    const token_style = token.type.defaultStyle();

                    for (token_text) |ch| {
                        if (x_offset >= text_width) break;

                        var final_style = token_style;

                        // Apply selection style
                        if (self.selection) |sel| {
                            const pos = Position{ .line = line_idx, .col = x_offset };
                            if (sel.contains(pos)) {
                                final_style.bg = self.selection_style.bg;
                            }
                        }

                        // Apply cursor style
                        if (line_idx == self.cursor.line and x_offset == self.cursor.col) {
                            final_style.bg = self.cursor_style.bg;
                            final_style.fg = self.cursor_style.fg;
                        }

                        buf.setChar(text_start_x + x_offset, y, ch, final_style);
                        x_offset += 1;
                    }
                }
            } else {
                // No syntax highlighting
                for (line_text, 0..) |ch, i| {
                    if (i >= text_width) break;

                    var final_style = Style{};

                    // Apply selection style
                    if (self.selection) |sel| {
                        const pos = Position{ .line = line_idx, .col = i };
                        if (sel.contains(pos)) {
                            final_style.bg = self.selection_style.bg;
                        }
                    }

                    // Apply cursor style
                    if (line_idx == self.cursor.line and i == self.cursor.col) {
                        final_style.bg = self.cursor_style.bg;
                        final_style.fg = self.cursor_style.fg;
                    }

                    buf.setChar(text_start_x + @as(u16, @intCast(i)), y, ch, final_style);
                }
            }

            // Render cursor at end of line if applicable
            if (line_idx == self.cursor.line and self.cursor.col == line_text.len and self.cursor.col < text_width) {
                buf.setChar(text_start_x + @as(u16, @intCast(self.cursor.col)), y, ' ', self.cursor_style);
            }
        }
    }
};

// Tests
const testing = std.testing;

test "editor init and deinit" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try testing.expect(editor.lines.items.len == 1);
    try testing.expect(editor.cursor.line == 0);
    try testing.expect(editor.cursor.col == 0);
}

test "editor setText and getText" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    const text = "line 1\nline 2\nline 3";
    try editor.setText(text);

    try testing.expect(editor.lines.items.len == 3);
    try testing.expectEqualStrings("line 1", editor.lines.items[0]);
    try testing.expectEqualStrings("line 2", editor.lines.items[1]);
    try testing.expectEqualStrings("line 3", editor.lines.items[2]);

    const result = try editor.getText(allocator);
    defer allocator.free(result);
    try testing.expectEqualStrings(text, result);
}

test "editor insertChar" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello");
    editor.cursor = .{ .line = 0, .col = 5 };

    try editor.insertChar('!');
    try testing.expectEqualStrings("hello!", editor.lines.items[0]);
    try testing.expect(editor.cursor.col == 6);
    try testing.expect(editor.undo_stack.items.len == 1);
}

test "editor deleteChar" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello!");
    editor.cursor = .{ .line = 0, .col = 6 };

    try editor.deleteChar();
    try testing.expectEqualStrings("hello", editor.lines.items[0]);
    try testing.expect(editor.cursor.col == 5);
    try testing.expect(editor.undo_stack.items.len == 1);
}

test "editor insertNewline" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello world");
    editor.cursor = .{ .line = 0, .col = 5 };

    try editor.insertNewline();
    try testing.expect(editor.lines.items.len == 2);
    try testing.expectEqualStrings("hello", editor.lines.items[0]);
    try testing.expectEqualStrings(" world", editor.lines.items[1]);
    try testing.expect(editor.cursor.line == 1);
    try testing.expect(editor.cursor.col == 0);
}

test "editor undo insert" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello");
    editor.cursor = .{ .line = 0, .col = 5 };

    try editor.insertChar('!');
    try testing.expectEqualStrings("hello!", editor.lines.items[0]);

    try editor.undo();
    try testing.expectEqualStrings("hello", editor.lines.items[0]);
    try testing.expect(editor.cursor.col == 5);
}

test "editor undo delete" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello!");
    editor.cursor = .{ .line = 0, .col = 6 };

    try editor.deleteChar();
    try testing.expectEqualStrings("hello", editor.lines.items[0]);

    try editor.undo();
    try testing.expectEqualStrings("hello!", editor.lines.items[0]);
    try testing.expect(editor.cursor.col == 6);
}

test "editor redo" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello");
    editor.cursor = .{ .line = 0, .col = 5 };

    try editor.insertChar('!');
    try editor.undo();
    try editor.redo();

    try testing.expectEqualStrings("hello!", editor.lines.items[0]);
    try testing.expect(editor.cursor.col == 6);
}

test "editor moveCursor" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("line 1\nline 2");

    editor.moveCursor(1, 3);
    try testing.expect(editor.cursor.line == 1);
    try testing.expect(editor.cursor.col == 3);

    // Clamp to max line
    editor.moveCursor(10, 0);
    try testing.expect(editor.cursor.line == 1);

    // Clamp to max col
    editor.moveCursor(0, 100);
    try testing.expect(editor.cursor.col == 6);
}

test "editor selection" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello world");

    editor.setSelection(
        .{ .line = 0, .col = 0 },
        .{ .line = 0, .col = 5 },
    );

    try testing.expect(editor.selection != null);
    try testing.expect(!editor.selection.?.isEmpty());

    const pos = Position{ .line = 0, .col = 2 };
    try testing.expect(editor.selection.?.contains(pos));

    editor.clearSelection();
    try testing.expect(editor.selection == null);
}

test "editor setLanguage" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    _ = editor.setLanguage(.zig);
    try testing.expect(editor.language == .zig);
}

test "editor setBlock" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    const block = (Block{}).setTitle("Editor");
    _ = editor.setBlock(block);
    try testing.expect(editor.block != null);
}

test "editor setShowLineNumbers" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    _ = editor.setShowLineNumbers(false);
    try testing.expect(editor.show_line_numbers == false);
}

test "editor render basic" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello\nworld");

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    editor.render(&buffer, area);

    // Check line numbers are rendered
    const first_line_num = buffer.getChar(0, 0);
    try testing.expect(first_line_num == '1');
}

test "editor render with syntax highlighting" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("const x = 42;");
    _ = editor.setLanguage(.zig);

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    editor.render(&buffer, area);

    // Syntax highlighting should be applied (keyword "const" should have special style)
    // This test just verifies no crashes occur
}

test "editor render with selection" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello world");
    editor.setSelection(
        .{ .line = 0, .col = 0 },
        .{ .line = 0, .col = 5 },
    );

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    editor.render(&buffer, area);

    // Selection should be rendered with selection_style
}

test "editor render with cursor" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("hello");
    editor.cursor = .{ .line = 0, .col = 2 };

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    editor.render(&buffer, area);

    // Cursor should be rendered at position (2 + line_num_width, 0)
}

test "selection normalized" {
    const sel1 = Selection{
        .start = .{ .line = 0, .col = 5 },
        .end = .{ .line = 0, .col = 0 },
    };
    const norm1 = sel1.normalized();
    try testing.expect(norm1.start.col == 0);
    try testing.expect(norm1.end.col == 5);

    const sel2 = Selection{
        .start = .{ .line = 0, .col = 0 },
        .end = .{ .line = 1, .col = 0 },
    };
    const norm2 = sel2.normalized();
    try testing.expect(norm2.start.line == 0);
    try testing.expect(norm2.end.line == 1);
}

test "selection contains" {
    const sel = Selection{
        .start = .{ .line = 0, .col = 2 },
        .end = .{ .line = 0, .col = 7 },
    };

    try testing.expect(sel.contains(.{ .line = 0, .col = 3 }));
    try testing.expect(sel.contains(.{ .line = 0, .col = 2 }));
    try testing.expect(!sel.contains(.{ .line = 0, .col = 7 }));
    try testing.expect(!sel.contains(.{ .line = 0, .col = 0 }));
    try testing.expect(!sel.contains(.{ .line = 1, .col = 0 }));
}

test "selection isEmpty" {
    const empty = Selection{
        .start = .{ .line = 0, .col = 5 },
        .end = .{ .line = 0, .col = 5 },
    };
    try testing.expect(empty.isEmpty());

    const not_empty = Selection{
        .start = .{ .line = 0, .col = 5 },
        .end = .{ .line = 0, .col = 6 },
    };
    try testing.expect(!not_empty.isEmpty());
}
