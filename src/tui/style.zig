const std = @import("std");
const Allocator = std.mem.Allocator;

/// Color representation supporting multiple palettes
pub const Color = union(enum) {
    reset,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    indexed: u8, // 256-color palette
    rgb: struct { r: u8, g: u8, b: u8 }, // truecolor

    /// Convert color to ANSI foreground escape code
    pub fn toFg(self: Color, writer: anytype) !void {
        switch (self) {
            .reset => try writer.writeAll("\x1b[39m"),
            .black => try writer.writeAll("\x1b[30m"),
            .red => try writer.writeAll("\x1b[31m"),
            .green => try writer.writeAll("\x1b[32m"),
            .yellow => try writer.writeAll("\x1b[33m"),
            .blue => try writer.writeAll("\x1b[34m"),
            .magenta => try writer.writeAll("\x1b[35m"),
            .cyan => try writer.writeAll("\x1b[36m"),
            .white => try writer.writeAll("\x1b[37m"),
            .bright_black => try writer.writeAll("\x1b[90m"),
            .bright_red => try writer.writeAll("\x1b[91m"),
            .bright_green => try writer.writeAll("\x1b[92m"),
            .bright_yellow => try writer.writeAll("\x1b[93m"),
            .bright_blue => try writer.writeAll("\x1b[94m"),
            .bright_magenta => try writer.writeAll("\x1b[95m"),
            .bright_cyan => try writer.writeAll("\x1b[96m"),
            .bright_white => try writer.writeAll("\x1b[97m"),
            .indexed => |idx| try writer.print("\x1b[38;5;{d}m", .{idx}),
            .rgb => |c| try writer.print("\x1b[38;2;{d};{d};{d}m", .{ c.r, c.g, c.b }),
        }
    }

    /// Convert color to ANSI background escape code
    pub fn toBg(self: Color, writer: anytype) !void {
        switch (self) {
            .reset => try writer.writeAll("\x1b[49m"),
            .black => try writer.writeAll("\x1b[40m"),
            .red => try writer.writeAll("\x1b[41m"),
            .green => try writer.writeAll("\x1b[42m"),
            .yellow => try writer.writeAll("\x1b[43m"),
            .blue => try writer.writeAll("\x1b[44m"),
            .magenta => try writer.writeAll("\x1b[45m"),
            .cyan => try writer.writeAll("\x1b[46m"),
            .white => try writer.writeAll("\x1b[47m"),
            .bright_black => try writer.writeAll("\x1b[100m"),
            .bright_red => try writer.writeAll("\x1b[101m"),
            .bright_green => try writer.writeAll("\x1b[102m"),
            .bright_yellow => try writer.writeAll("\x1b[103m"),
            .bright_blue => try writer.writeAll("\x1b[104m"),
            .bright_magenta => try writer.writeAll("\x1b[105m"),
            .bright_cyan => try writer.writeAll("\x1b[106m"),
            .bright_white => try writer.writeAll("\x1b[107m"),
            .indexed => |idx| try writer.print("\x1b[48;5;{d}m", .{idx}),
            .rgb => |c| try writer.print("\x1b[48;2;{d};{d};{d}m", .{ c.r, c.g, c.b }),
        }
    }
};

/// Text styling with colors and modifiers
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,

    /// Default style (no formatting)
    pub const default: Style = .{};

    /// Apply style to writer (emit ANSI codes)
    pub fn apply(self: Style, writer: anytype) !void {
        // Foreground color
        if (self.fg) |fg| {
            try fg.toFg(writer);
        }

        // Background color
        if (self.bg) |bg| {
            try bg.toBg(writer);
        }

        // Text modifiers
        if (self.bold) try writer.writeAll("\x1b[1m");
        if (self.dim) try writer.writeAll("\x1b[2m");
        if (self.italic) try writer.writeAll("\x1b[3m");
        if (self.underline) try writer.writeAll("\x1b[4m");
        if (self.reverse) try writer.writeAll("\x1b[7m");
        if (self.blink) try writer.writeAll("\x1b[5m");
        if (self.strikethrough) try writer.writeAll("\x1b[9m");
    }

    /// Reset all styling
    pub fn reset(writer: anytype) !void {
        try writer.writeAll("\x1b[0m");
    }

    /// Merge two styles (other overrides self where non-null/true)
    pub fn merge(self: Style, other: Style) Style {
        return .{
            .fg = other.fg orelse self.fg,
            .bg = other.bg orelse self.bg,
            .bold = other.bold or self.bold,
            .dim = other.dim or self.dim,
            .italic = other.italic or self.italic,
            .underline = other.underline or self.underline,
            .blink = other.blink or self.blink,
            .reverse = other.reverse or self.reverse,
            .strikethrough = other.strikethrough or self.strikethrough,
        };
    }
};

/// Styled text span
pub const Span = struct {
    content: []const u8,
    style: Style = .{},

    /// Create span with default style
    pub fn raw(content: []const u8) Span {
        return .{ .content = content };
    }

    /// Create span with style
    pub fn styled(content: []const u8, style: Style) Span {
        return .{ .content = content, .style = style };
    }

    /// Render span to writer
    pub fn render(self: Span, writer: anytype) !void {
        // Only apply styling if style has non-default attributes
        const has_style = self.style.fg != null or
            self.style.bg != null or
            self.style.bold or
            self.style.dim or
            self.style.italic or
            self.style.underline or
            self.style.blink or
            self.style.reverse or
            self.style.strikethrough;

        if (has_style) {
            try self.style.apply(writer);
        }
        try writer.writeAll(self.content);
        if (has_style) {
            try Style.reset(writer);
        }
    }
};

/// Line of styled spans
pub const Line = struct {
    spans: []const Span,

    /// Render line to writer
    pub fn render(self: Line, writer: anytype) !void {
        for (self.spans) |span| {
            try span.render(writer);
        }
    }

    /// Calculate display width (sum of all span content lengths)
    /// Note: This is a simple implementation that doesn't account for
    /// multi-byte UTF-8 or wide characters. For TUI use, buffer.zig
    /// will handle proper Unicode width calculation.
    pub fn width(self: Line) usize {
        var w: usize = 0;
        for (self.spans) |span| {
            w += span.content.len;
        }
        return w;
    }
};

/// Fluent builder for creating styled spans
/// Uses pointer semantics — methods return *SpanBuilder for chaining
pub const SpanBuilder = struct {
    content: []const u8 = "",
    current_style: Style = .{},

    /// Initialize a new SpanBuilder
    pub fn init() SpanBuilder {
        return .{
            .content = "",
            .current_style = .{},
        };
    }

    /// Set the text content
    pub fn text(self: *SpanBuilder, new_content: []const u8) *SpanBuilder {
        self.content = new_content;
        return self;
    }

    /// Apply bold modifier
    pub fn bold(self: *SpanBuilder) *SpanBuilder {
        self.current_style.bold = true;
        return self;
    }

    /// Apply italic modifier
    pub fn italic(self: *SpanBuilder) *SpanBuilder {
        self.current_style.italic = true;
        return self;
    }

    /// Apply underline modifier
    pub fn underline(self: *SpanBuilder) *SpanBuilder {
        self.current_style.underline = true;
        return self;
    }

    /// Apply dim modifier
    pub fn dim(self: *SpanBuilder) *SpanBuilder {
        self.current_style.dim = true;
        return self;
    }

    /// Apply strikethrough modifier
    pub fn strikethrough(self: *SpanBuilder) *SpanBuilder {
        self.current_style.strikethrough = true;
        return self;
    }

    /// Apply reverse modifier
    pub fn reverse(self: *SpanBuilder) *SpanBuilder {
        self.current_style.reverse = true;
        return self;
    }

    /// Apply blink modifier
    pub fn blink(self: *SpanBuilder) *SpanBuilder {
        self.current_style.blink = true;
        return self;
    }

    /// Set foreground color
    pub fn fg(self: *SpanBuilder, color: Color) *SpanBuilder {
        self.current_style.fg = color;
        return self;
    }

    /// Set background color
    pub fn bg(self: *SpanBuilder, color: Color) *SpanBuilder {
        self.current_style.bg = color;
        return self;
    }

    /// Merge a complete style using Style.merge
    pub fn style(self: *SpanBuilder, s: Style) *SpanBuilder {
        self.current_style = self.current_style.merge(s);
        return self;
    }

    /// Build the final Span
    pub fn build(self: SpanBuilder) Span {
        return .{
            .content = self.content,
            .style = self.current_style,
        };
    }
};

/// Fluent builder for creating lines with multiple spans
/// Uses pointer semantics — methods return *LineBuilder for chaining
pub const LineBuilder = struct {
    allocator: Allocator,
    spans: std.ArrayList(Span),

    /// Initialize a new LineBuilder
    pub fn init(allocator: Allocator) LineBuilder {
        return .{
            .allocator = allocator,
            .spans = std.ArrayList(Span){},
        };
    }

    /// Clean up the ArrayList (but not the Line slice — caller owns it)
    pub fn deinit(self: *LineBuilder) void {
        self.spans.deinit(self.allocator);
    }

    /// Add a pre-built span
    pub fn span(self: *LineBuilder, s: Span) *LineBuilder {
        self.spans.append(self.allocator, s) catch @panic("LineBuilder.span: allocation failed");
        return self;
    }

    /// Add a raw (unstyled) span
    pub fn raw(self: *LineBuilder, content: []const u8) *LineBuilder {
        self.spans.append(self.allocator, .{
            .content = content,
            .style = .{},
        }) catch @panic("LineBuilder.raw: allocation failed");
        return self;
    }

    /// Add a styled span
    pub fn text(self: *LineBuilder, content: []const u8, s: Style) *LineBuilder {
        self.spans.append(self.allocator, .{
            .content = content,
            .style = s,
        }) catch @panic("LineBuilder.text: allocation failed");
        return self;
    }

    /// Build a Line with unowned slice (caller must keep spans alive)
    pub fn build(self: LineBuilder) Line {
        return .{
            .spans = self.spans.items,
        };
    }

    /// Build a Line with owned slice (allocates, caller must free)
    pub fn buildOwned(self: *LineBuilder) !Line {
        const owned_spans = try self.allocator.dupe(Span, self.spans.items);
        return .{
            .spans = owned_spans,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Color.toFg - basic colors" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const red: Color = .red;
    try red.toFg(writer);
    try std.testing.expectEqualStrings("\x1b[31m", fbs.getWritten());

    fbs.reset();
    const cyan: Color = .bright_cyan;
    try cyan.toFg(writer);
    try std.testing.expectEqualStrings("\x1b[96m", fbs.getWritten());
}

test "Color.toFg - indexed" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const col = Color{ .indexed = 208 };
    try col.toFg(writer);
    try std.testing.expectEqualStrings("\x1b[38;5;208m", fbs.getWritten());
}

test "Color.toFg - rgb" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const col = Color{ .rgb = .{ .r = 255, .g = 128, .b = 0 } };
    try col.toFg(writer);
    try std.testing.expectEqualStrings("\x1b[38;2;255;128;0m", fbs.getWritten());
}

test "Color.toBg - basic colors" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const blue: Color = .blue;
    try blue.toBg(writer);
    try std.testing.expectEqualStrings("\x1b[44m", fbs.getWritten());

    fbs.reset();
    const yellow: Color = .bright_yellow;
    try yellow.toBg(writer);
    try std.testing.expectEqualStrings("\x1b[103m", fbs.getWritten());
}

test "Color.toBg - indexed" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const col = Color{ .indexed = 42 };
    try col.toBg(writer);
    try std.testing.expectEqualStrings("\x1b[48;5;42m", fbs.getWritten());
}

test "Color.toBg - rgb" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const col = Color{ .rgb = .{ .r = 0, .g = 255, .b = 127 } };
    try col.toBg(writer);
    try std.testing.expectEqualStrings("\x1b[48;2;0;255;127m", fbs.getWritten());
}

test "Style.apply - colors only" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const s = Style{
        .fg = .green,
        .bg = .black,
    };
    try s.apply(writer);
    try std.testing.expectEqualStrings("\x1b[32m\x1b[40m", fbs.getWritten());
}

test "Style.apply - modifiers only" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const s = Style{
        .bold = true,
        .italic = true,
        .underline = true,
    };
    try s.apply(writer);
    try std.testing.expectEqualStrings("\x1b[1m\x1b[3m\x1b[4m", fbs.getWritten());
}

test "Style.apply - all features" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const s = Style{
        .fg = .red,
        .bg = .white,
        .bold = true,
        .dim = true,
        .italic = true,
        .underline = true,
        .blink = true,
        .reverse = true,
        .strikethrough = true,
    };
    try s.apply(writer);
    const expected = "\x1b[31m\x1b[47m\x1b[1m\x1b[2m\x1b[3m\x1b[4m\x1b[7m\x1b[5m\x1b[9m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Style.reset" {
    var buf: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try Style.reset(writer);
    try std.testing.expectEqualStrings("\x1b[0m", fbs.getWritten());
}

test "Style.merge - colors" {
    const base = Style{
        .fg = .red,
        .bg = .black,
    };
    const overlay = Style{
        .fg = .blue,
    };
    const merged = base.merge(overlay);

    const expected_fg: Color = .blue;
    const expected_bg: Color = .black;
    try std.testing.expectEqual(expected_fg, merged.fg.?);
    try std.testing.expectEqual(expected_bg, merged.bg.?);
}

test "Style.merge - modifiers" {
    const base = Style{
        .bold = true,
        .italic = false,
    };
    const overlay = Style{
        .italic = true,
    };
    const merged = base.merge(overlay);

    try std.testing.expect(merged.bold);
    try std.testing.expect(merged.italic);
}

test "Span.raw" {
    const span = Span.raw("hello");
    try std.testing.expectEqualStrings("hello", span.content);
    try std.testing.expectEqual(Style.default, span.style);
}

test "Span.styled" {
    const style = Style{ .fg = .green, .bold = true };
    const span = Span.styled("world", style);
    try std.testing.expectEqualStrings("world", span.content);
    const expected_fg: Color = .green;
    try std.testing.expectEqual(expected_fg, span.style.fg.?);
    try std.testing.expect(span.style.bold);
}

test "Span.render" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const span = Span.styled("test", .{ .fg = .red, .bold = true });
    try span.render(writer);
    try std.testing.expectEqualStrings("\x1b[31m\x1b[1mtest\x1b[0m", fbs.getWritten());
}

test "Line - single span" {
    const span = Span.raw("hello");
    const spans = [_]Span{span};
    const line = Line{ .spans = &spans };
    try std.testing.expectEqual(1, line.spans.len);
    try std.testing.expectEqualStrings("hello", line.spans[0].content);
}

test "Line.render - single span" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const span = Span.raw("hello");
    const spans = [_]Span{span};
    const line = Line{ .spans = &spans };
    try line.render(writer);
    try std.testing.expectEqualStrings("hello", fbs.getWritten());
}

test "Line.render - multiple spans" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const spans = [_]Span{
        Span.styled("Hello", .{ .fg = .red }),
        Span.raw(" "),
        Span.styled("world", .{ .fg = .blue, .bold = true }),
    };
    const line = Line{ .spans = &spans };
    try line.render(writer);

    const expected = "\x1b[31mHello\x1b[0m \x1b[34m\x1b[1mworld\x1b[0m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Line.width" {
    const spans = [_]Span{
        Span.raw("Hello"),
        Span.raw(" "),
        Span.raw("world"),
    };
    const line = Line{ .spans = &spans };
    try std.testing.expectEqual(11, line.width());
}
