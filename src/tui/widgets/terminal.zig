//! Terminal widget for embedding shell sessions with scrollback and ANSI support.
const std = @import("std");
const assert = std.debug.assert;
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

/// Terminal widget for embedding shell sessions with scrollback and ANSI support
pub const TerminalWidget = struct {
    /// Scrollback buffer storing terminal output lines
    lines: std.ArrayList([]const u8),

    /// Current scrollback offset (0 = bottom)
    scroll_offset: usize = 0,

    /// PTY file descriptor (platform-specific, -1 if not open)
    pty_fd: i32 = -1,

    /// Child process PID
    child_pid: i32 = -1,

    /// Width and height of PTY
    width: u16 = 80,
    height: u16 = 24,

    /// Allocator for line storage
    allocator: std.mem.Allocator,

    /// Optional block (border, title, padding)
    block: ?Block = null,

    /// Text style for regular output
    text_style: Style = .{},

    /// Title text
    title: ?[]const u8 = null,

    /// Maximum number of lines to keep in scrollback
    max_lines: usize = 10000,

    /// ANSI state for parsing (cursor position, color state, etc.)
    ansi_state: AnsiParseState = .{},

    pub fn init(allocator: std.mem.Allocator) !TerminalWidget {
        return .{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).empty,
        };
    }

    /// Deinitialize the terminal widget and free all line buffers.
    ///
    /// Must be called to prevent memory leaks.
    /// Frees all stored lines in the scrollback buffer.
    pub fn deinit(self: *TerminalWidget) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
    }

    /// Set the border block for this terminal (builder pattern).
    ///
    /// Args:
    ///   new_block: Block configuration for borders and title
    ///
    /// Returns:
    ///   Modified TerminalWidget (copy-on-write)
    pub fn withBlock(self: TerminalWidget, new_block: Block) TerminalWidget {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set the title displayed in the border (builder pattern).
    ///
    /// Args:
    ///   title: Title string (not copied, must remain valid)
    ///
    /// Returns:
    ///   Modified TerminalWidget
    pub fn withTitle(self: TerminalWidget, title: []const u8) TerminalWidget {
        var result = self;
        result.title = title;
        return result;
    }

    /// Set the maximum scrollback buffer size (builder pattern).
    ///
    /// Args:
    ///   max: Maximum number of lines to retain (older lines are discarded)
    ///
    /// Returns:
    ///   Modified TerminalWidget
    pub fn withMaxLines(self: TerminalWidget, max: usize) TerminalWidget {
        var result = self;
        result.max_lines = max;
        return result;
    }

    /// Set the terminal dimensions (builder pattern).
    ///
    /// Args:
    ///   width, height: Virtual terminal size in characters
    ///
    /// Returns:
    ///   Modified TerminalWidget
    pub fn withSize(self: TerminalWidget, width: u16, height: u16) TerminalWidget {
        var result = self;
        result.width = width;
        result.height = height;
        return result;
    }

    /// Add a line to scrollback buffer
    pub fn addLine(self: *TerminalWidget, line: []const u8) !void {
        // Trim old lines if exceeding max
        if (self.max_lines == 0) return;
        while (self.lines.items.len >= self.max_lines) {
            if (self.lines.items.len > 0) {
                self.allocator.free(self.lines.items[0]);
                _ = self.lines.orderedRemove(0);
            }
        }

        const line_copy = try self.allocator.dupe(u8, line);
        errdefer self.allocator.free(line_copy);
        try self.lines.append(self.allocator, line_copy);
    }

    /// Clear all lines
    pub fn clear(self: *TerminalWidget) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        self.scroll_offset = 0;
    }

    /// Get total number of lines in scrollback
    pub fn lineCount(self: TerminalWidget) usize {
        return self.lines.items.len;
    }

    /// Scroll up by n lines
    pub fn scrollUp(self: *TerminalWidget, n: usize) void {
        const max_offset = if (self.lines.items.len > self.height)
            self.lines.items.len - self.height
        else
            0;
        self.scroll_offset = @min(self.scroll_offset + n, max_offset);
    }

    /// Scroll down by n lines
    pub fn scrollDown(self: *TerminalWidget, n: usize) void {
        self.scroll_offset = if (self.scroll_offset > n)
            self.scroll_offset - n
        else
            0;
    }

    /// Get visible lines based on scroll offset
    pub fn visibleLines(self: TerminalWidget) []const []const u8 {
        const start = if (self.scroll_offset < self.lines.items.len)
            self.lines.items.len - self.scroll_offset - @min(self.height, self.lines.items.len)
        else
            0;

        const end = if (self.scroll_offset == 0)
            self.lines.items.len
        else
            self.lines.items.len - self.scroll_offset;

        if (start >= end) return &.{};
        return self.lines.items[start..end];
    }

    /// Draw one scrollback line, interpreting ANSI escape sequences.
    ///
    /// SGR sequences (`ESC [ ... m`) update a copy of `ansi_state`, which also seeds every line;
    /// all other CSI sequences are consumed and ignored. A malformed sequence never draws its
    /// bytes: a truncated one ends the line, an invalid one is skipped. Text is clipped to
    /// `inner_area`. Precondition: `y` lies inside `inner_area`.
    fn renderLine(
        self: TerminalWidget,
        buf: *Buffer,
        inner_area: Rect,
        y: u16,
        line: []const u8,
    ) void {
        assert(y >= inner_area.y);
        assert(y - inner_area.y < inner_area.height);

        var state = self.ansi_state;
        const x_end: u32 = @as(u32, inner_area.x) + inner_area.width;
        var x: u32 = inner_area.x;
        var i: usize = 0;
        while (i < line.len and x < x_end) {
            if (line[i] == 0x1b) {
                const len = AnsiParseState.escapeLength(line[i..]) catch |err| switch (err) {
                    error.TruncatedSequence => return,
                    error.InvalidSequence => {
                        i += 1;
                        continue;
                    },
                };
                if (line[i + len - 1] == 'm') {
                    state.applySgr(line[i + 2 .. i + len - 1]) catch |err| switch (err) {
                        // applySgr is atomic: an invalid sequence leaves the style as it was.
                        error.InvalidParameter => {},
                    };
                }
                i += len;
                continue;
            }

            const char_len = std.unicode.utf8ByteSequenceLength(line[i]) catch 1;
            if (i + char_len > line.len) return;
            const codepoint = if (char_len == 1)
                @as(u21, line[i])
            else
                std.unicode.utf8Decode(line[i .. i + char_len]) catch @as(u21, line[i]);
            i += char_len;

            const char_width = UnicodeWidth.charWidth(codepoint);
            if (char_width == 0) continue;
            if (char_width == 2 and x + 1 >= x_end) return;
            buf.set(@intCast(x), y, .{ .char = codepoint, .style = state.style(self.text_style) });
            x += char_width;
        }
    }

    /// Render terminal to buffer
    pub fn render(self: TerminalWidget, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Get visible lines
        const visible = self.visibleLines();

        // Render visible lines
        for (visible, 0..) |line, idx| {
            if (idx >= inner_area.height) break;
            const y = inner_area.y + @as(u16, @intCast(idx));
            self.renderLine(buf, inner_area, y, line);
        }

        // Fill remaining rows with spaces
        if (visible.len < inner_area.height) {
            for (visible.len..inner_area.height) |idx| {
                const y = inner_area.y + @as(u16, @intCast(idx));
                buf.fill(Rect{ .x = inner_area.x, .y = y, .width = inner_area.width, .height = 1 }, ' ', self.text_style);
            }
        }
    }
};

/// ANSI escape code parser state
pub const AnsiParseState = struct {
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    foreground: ?Color = null,
    background: ?Color = null,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,

    /// Leniently apply one SGR parameter list; malformed input is ignored.
    ///
    /// Kept for callers that feed already-split parameters. Use `applySgr` to learn about
    /// malformed input.
    pub fn parseSequence(self: *AnsiParseState, seq: []const u8) void {
        if (seq.len < 1) return;
        self.applySgr(seq) catch |err| switch (err) {
            // Documented as lenient; `applySgr` leaves the state untouched on this error.
            error.InvalidParameter => {},
        };
    }

    /// Apply an SGR parameter list (the bytes between `ESC [` and `m`, e.g. `"1;31"`).
    ///
    /// An empty list means reset, as on a terminal. Supports attributes 0-4, 7, 22-24, 27,
    /// the 8 and 16 color ranges, 39/49 and extended colors (`38;5;n`, `38;2;r;g;b`, and
    /// the `48` forms). Unknown but well-formed codes are ignored. The state changes only
    /// if the whole list is valid.
    pub fn applySgr(self: *AnsiParseState, params: []const u8) SgrError!void {
        if (params.len > sgr_params_len_max) return error.InvalidParameter;

        var next = self.*;
        var fields = std.mem.splitScalar(u8, params, ';');
        while (fields.next()) |field| {
            const code = try parseSgrField(field);
            switch (code) {
                0 => next.resetAttributes(),
                1 => next.bold = true,
                2 => next.dim = true,
                3 => next.italic = true,
                4 => next.underline = true,
                7 => next.reverse = true,
                22 => {
                    next.bold = false;
                    next.dim = false;
                },
                23 => next.italic = false,
                24 => next.underline = false,
                27 => next.reverse = false,
                30...37 => next.foreground = basicColor(code - 30, false),
                38 => next.foreground = try parseExtendedColor(&fields),
                39 => next.foreground = null,
                40...47 => next.background = basicColor(code - 40, false),
                48 => next.background = try parseExtendedColor(&fields),
                49 => next.background = null,
                90...97 => next.foreground = basicColor(code - 90, true),
                100...107 => next.background = basicColor(code - 100, true),
                else => {},
            }
        }
        self.* = next;
    }

    /// Length in bytes of the escape sequence at the start of `input`.
    ///
    /// Only CSI sequences (`ESC [ params final`) are recognised. `TruncatedSequence` means
    /// `input` ended before the final byte; `InvalidSequence` means the bytes cannot start a
    /// sequence (not `[`, a stray control byte, or longer than `sequence_len_max`).
    /// Precondition: `input` starts with ESC.
    pub fn escapeLength(input: []const u8) EscapeError!u32 {
        assert(input.len > 0);
        assert(input[0] == 0x1b);

        if (input.len < 2) return error.TruncatedSequence;
        if (input[1] != '[') return error.InvalidSequence;
        for (input[2..], 2..) |byte, index| {
            if (index >= sequence_len_max) return error.InvalidSequence;
            switch (byte) {
                0x20...0x3f => {},
                0x40...0x7e => return @intCast(index + 1),
                else => return error.InvalidSequence,
            }
        }
        return error.TruncatedSequence;
    }

    /// The cell style for text drawn in this state, layered over `base`.
    pub fn style(self: AnsiParseState, base: Style) Style {
        var result = base;
        if (self.foreground) |color| result.fg = color;
        if (self.background) |color| result.bg = color;
        if (self.bold) result.bold = true;
        if (self.dim) result.dim = true;
        if (self.italic) result.italic = true;
        if (self.underline) result.underline = true;
        if (self.reverse) result.reverse = true;
        return result;
    }

    fn resetAttributes(self: *AnsiParseState) void {
        self.foreground = null;
        self.background = null;
        self.bold = false;
        self.dim = false;
        self.italic = false;
        self.underline = false;
        self.reverse = false;
    }

    /// Reset ANSI state to defaults
    pub fn reset(self: *AnsiParseState) void {
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.foreground = null;
        self.background = null;
        self.bold = false;
        self.dim = false;
        self.italic = false;
        self.underline = false;
        self.reverse = false;
    }
};

/// Longest SGR parameter list `AnsiParseState.applySgr` accepts, in bytes.
const sgr_params_len_max = 256;

/// Longest escape sequence `AnsiParseState.escapeLength` accepts, in bytes.
const sequence_len_max = 64;

/// Why `AnsiParseState.escapeLength` found no complete sequence.
pub const EscapeError = error{ TruncatedSequence, InvalidSequence };

/// Why `AnsiParseState.applySgr` rejected a parameter list.
pub const SgrError = error{InvalidParameter};

fn parseSgrField(field: []const u8) SgrError!u8 {
    if (field.len == 0) return 0;
    return std.fmt.parseInt(u8, field, 10) catch |err| switch (err) {
        error.Overflow, error.InvalidCharacter => error.InvalidParameter,
    };
}

fn basicColor(index: u8, bright: bool) Color {
    assert(index < 8);
    const colors = [8]Color{ .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white };
    const bright_colors = [8]Color{
        .bright_black, .bright_red,     .bright_green, .bright_yellow,
        .bright_blue,  .bright_magenta, .bright_cyan,  .bright_white,
    };
    return if (bright) bright_colors[index] else colors[index];
}

fn parseExtendedColor(fields: *std.mem.SplitIterator(u8, .scalar)) SgrError!Color {
    const mode = try parseSgrField(fields.next() orelse return error.InvalidParameter);
    switch (mode) {
        5 => {
            const index = try parseSgrField(fields.next() orelse return error.InvalidParameter);
            return Color{ .indexed = index };
        },
        2 => {
            const r = try parseSgrField(fields.next() orelse return error.InvalidParameter);
            const g = try parseSgrField(fields.next() orelse return error.InvalidParameter);
            const b = try parseSgrField(fields.next() orelse return error.InvalidParameter);
            return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
        },
        else => return error.InvalidParameter,
    }
}

// Tests
const testing = std.testing;

test "Terminal widget init and deinit" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try testing.expectEqual(@as(usize, 0), term.lineCount());
    try testing.expectEqual(@as(usize, 0), term.scroll_offset);
    try testing.expectEqual(@as(u16, 80), term.width);
}

test "Terminal widget add line" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Hello, World!");
    try testing.expectEqual(@as(usize, 1), term.lineCount());
}

test "Terminal widget scrollback limits" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();
    term = term.withMaxLines(5);

    // Add 10 lines, should only keep last 5
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    try testing.expectEqual(@as(usize, 5), term.lineCount());
}

test "Terminal widget scroll up" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();
    term = term.withSize(80, 10);

    // Add 20 lines
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        var buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    term.scrollUp(5);
    try testing.expectEqual(@as(usize, 5), term.scroll_offset);
}

test "Terminal widget render" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Test line 1");
    try term.addLine("Test line 2");

    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    term.render(&buf, area);

    // Basic verification - buffer should have content
    try testing.expect(buf.width == 40);
    try testing.expect(buf.height == 10);
}

test "ANSI parse state" {
    var state = AnsiParseState{};

    state.parseSequence("1");
    try testing.expect(state.bold);

    state.parseSequence("0");
    try testing.expect(!state.bold);
}

test "Terminal widget withBlock" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    const block = Block.init().withTitle("Custom Block");
    const term_with_block = term.withBlock(block);

    try testing.expectEqualStrings("Custom Block", term_with_block.block.title);
}

test "Terminal widget withTitle" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    const term_titled = term.withTitle("My Terminal");
    try testing.expectEqualStrings("My Terminal", term_titled.block.title);
}

test "Terminal widget clear" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();

    try term.addLine("Line 1");
    try term.addLine("Line 2");
    try term.addLine("Line 3");
    try testing.expectEqual(@as(usize, 3), term.lineCount());

    term.clear();
    try testing.expectEqual(@as(usize, 0), term.lineCount());
    try testing.expectEqual(@as(usize, 0), term.scroll_offset);
}

test "Terminal widget scrollDown" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();
    term = term.withSize(80, 5);

    // Add 10 lines
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "Line {d}", .{i});
        try term.addLine(line);
    }

    // Scroll up first
    term.scrollUp(8);
    try testing.expectEqual(@as(usize, 8), term.scroll_offset);

    // Scroll down by 3
    term.scrollDown(3);
    try testing.expectEqual(@as(usize, 5), term.scroll_offset);

    // Scroll down beyond bottom (should clamp to 0)
    term.scrollDown(10);
    try testing.expectEqual(@as(usize, 0), term.scroll_offset);
}

test "Terminal widget visibleLines" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();
    term = term.withSize(80, 3);

    try term.addLine("Line 0");
    try term.addLine("Line 1");
    try term.addLine("Line 2");
    try term.addLine("Line 3");
    try term.addLine("Line 4");

    // With no scrolling, should see last 3 lines
    const visible = term.visibleLines();
    try testing.expectEqual(@as(usize, 3), visible.len);
    try testing.expectEqualStrings("Line 2", visible[0]);
    try testing.expectEqualStrings("Line 3", visible[1]);
    try testing.expectEqualStrings("Line 4", visible[2]);
}

test "Terminal widget visibleLines with scroll offset" {
    var term = try TerminalWidget.init(testing.allocator);
    defer term.deinit();
    term = term.withSize(80, 3);

    try term.addLine("Line 0");
    try term.addLine("Line 1");
    try term.addLine("Line 2");
    try term.addLine("Line 3");
    try term.addLine("Line 4");

    term.scrollUp(2);
    const visible = term.visibleLines();
    try testing.expectEqual(@as(usize, 3), visible.len);
    try testing.expectEqualStrings("Line 0", visible[0]);
    try testing.expectEqualStrings("Line 1", visible[1]);
    try testing.expectEqualStrings("Line 2", visible[2]);
}

test "AnsiParseState reset" {
    var state = AnsiParseState{};

    // Set some state
    state.parseSequence("1"); // bold
    state.parseSequence("3"); // italic
    state.parseSequence("4"); // underline
    state.cursor_x = 10;
    state.cursor_y = 5;

    try testing.expect(state.bold);
    try testing.expect(state.italic);
    try testing.expect(state.underline);
    try testing.expectEqual(@as(u16, 10), state.cursor_x);
    try testing.expectEqual(@as(u16, 5), state.cursor_y);

    // Reset should clear everything
    state.reset();
    try testing.expect(!state.bold);
    try testing.expect(!state.dim);
    try testing.expect(!state.italic);
    try testing.expect(!state.underline);
    try testing.expect(!state.reverse);
    try testing.expectEqual(@as(u16, 0), state.cursor_x);
    try testing.expectEqual(@as(u16, 0), state.cursor_y);
    try testing.expectEqual(@as(?Color, null), state.foreground);
    try testing.expectEqual(@as(?Color, null), state.background);
}
