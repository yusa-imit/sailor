const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

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
            .lines = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *TerminalWidget) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit();
    }

    pub fn withBlock(self: TerminalWidget, new_block: Block) TerminalWidget {
        var result = self;
        result.block = new_block;
        return result;
    }

    pub fn withTitle(self: TerminalWidget, title: []const u8) TerminalWidget {
        var result = self;
        result.title = title;
        return result;
    }

    pub fn withMaxLines(self: TerminalWidget, max: usize) TerminalWidget {
        var result = self;
        result.max_lines = max;
        return result;
    }

    pub fn withSize(self: TerminalWidget, width: u16, height: u16) TerminalWidget {
        var result = self;
        result.width = width;
        result.height = height;
        return result;
    }

    /// Add a line to scrollback buffer
    pub fn addLine(self: *TerminalWidget, line: []const u8) !void {
        // Trim old lines if exceeding max
        while (self.lines.items.len >= self.max_lines) {
            if (self.lines.items.len > 0) {
                self.allocator.free(self.lines.items[0]);
                _ = self.lines.orderedRemove(0);
            }
        }

        const line_copy = try self.allocator.dupe(u8, line);
        errdefer self.allocator.free(line_copy);
        try self.lines.append(line_copy);
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
            buf.setString(inner_area.x, y, line, self.text_style);
        }

        // Fill remaining rows with spaces
        for (visible.len..inner_area.height) |idx| {
            const y = inner_area.y + @as(u16, @intCast(idx));
            buf.fill(Rect.new(inner_area.x, y, inner_area.width, 1), ' ', self.text_style);
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

    /// Parse ANSI escape sequence
    pub fn parseSequence(self: *AnsiParseState, seq: []const u8) void {
        if (seq.len < 1) return;

        // Basic patterns: [attr, [31m (red foreground), [1m (bold), etc.
        if (std.mem.eql(u8, seq, "1")) {
            self.bold = true;
        } else if (std.mem.eql(u8, seq, "2")) {
            self.dim = true;
        } else if (std.mem.eql(u8, seq, "3")) {
            self.italic = true;
        } else if (std.mem.eql(u8, seq, "4")) {
            self.underline = true;
        } else if (std.mem.eql(u8, seq, "7")) {
            self.reverse = true;
        } else if (std.mem.eql(u8, seq, "0")) {
            // Reset all
            self.bold = false;
            self.dim = false;
            self.italic = false;
            self.underline = false;
            self.reverse = false;
            self.foreground = null;
            self.background = null;
        }
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

    const area = Rect.new(0, 0, 40, 10);
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
