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

    /// Create an RGB truecolor from individual components.
    ///
    /// Equivalent to: `Color{ .rgb = .{ .r = r, .g = g, .b = b } }`
    ///
    /// Example:
    /// ```zig
    /// const red = Color.fromRgb(255, 0, 0);
    /// const custom = Color.fromRgb(128, 200, 64);
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate for RGB colors.
    pub fn fromRgb(r: u8, g: u8, b: u8) Color {
        return .{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    /// Create an indexed color from the 256-color palette.
    ///
    /// Equivalent to: `Color{ .indexed = idx }`
    ///
    /// Example:
    /// ```zig
    /// const gray = Color.fromIndexed(237);  // xterm color 237 (dark gray)
    /// const red = Color.fromIndexed(196);   // xterm color 196 (bright red)
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate for indexed colors.
    pub fn fromIndexed(idx: u8) Color {
        return .{ .indexed = idx };
    }

    /// Create an RGB color from a 24-bit hex value (0xRRGGBB format).
    ///
    /// Extracts RGB components from hex value:
    /// - Red: (hex >> 16) & 0xFF
    /// - Green: (hex >> 8) & 0xFF
    /// - Blue: hex & 0xFF
    ///
    /// Example:
    /// ```zig
    /// const red = Color.fromHex(0xFF0000);
    /// const green = Color.fromHex(0x00FF00);
    /// const blue = Color.fromHex(0x0000FF);
    /// const orange = Color.fromHex(0xFFA500);
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor for web-style hex colors.
    pub fn fromHex(hex: u24) Color {
        return .{ .rgb = .{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        } };
    }

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

    // v2.0.0 Style Inference Helpers
    // These methods make it easier to create styles with common patterns.

    /// Create style with foreground color (v2.0.0 helper)
    ///
    /// ## Example
    /// ```zig
    /// const s = Style.withForeground(.red);
    /// // equivalent to: Style{ .fg = .red }
    /// ```
    pub fn withForeground(color: Color) Style {
        return .{ .fg = color };
    }

    /// Create style with background color (v2.0.0 helper)
    ///
    /// ## Example
    /// ```zig
    /// const s = Style.withBackground(.blue);
    /// // equivalent to: Style{ .bg = .blue }
    /// ```
    pub fn withBackground(color: Color) Style {
        return .{ .bg = color };
    }

    /// Create style with foreground and background (v2.0.0 helper)
    ///
    /// ## Example
    /// ```zig
    /// const s = Style.withColors(.white, .blue);
    /// // equivalent to: Style{ .fg = .white, .bg = .blue }
    /// ```
    pub fn withColors(fg_color: Color, bg_color: Color) Style {
        return .{ .fg = fg_color, .bg = bg_color };
    }

    /// Create bold style (v2.0.0 helper)
    pub fn makeBold() Style {
        return .{ .bold = true };
    }

    /// Create italic style (v2.0.0 helper)
    pub fn makeItalic() Style {
        return .{ .italic = true };
    }

    /// Create underlined style (v2.0.0 helper)
    pub fn makeUnderline() Style {
        return .{ .underline = true };
    }

    /// Create dim style (v2.0.0 helper)
    pub fn makeDim() Style {
        return .{ .dim = true };
    }

    /// Create style with foreground and modifiers (v2.0.0 helper)
    ///
    /// ## Example
    /// ```zig
    /// const s = Style.fg(.red).withBold();
    /// // equivalent to: Style{ .fg = .red, .bold = true }
    /// ```
    pub fn withBold(self: Style) Style {
        var result = self;
        result.bold = true;
        return result;
    }

    /// Add italic to existing style (v2.0.0 helper)
    pub fn withItalic(self: Style) Style {
        var result = self;
        result.italic = true;
        return result;
    }

    /// Add underline to existing style (v2.0.0 helper)
    pub fn withUnderline(self: Style) Style {
        var result = self;
        result.underline = true;
        return result;
    }

    /// Add dim to existing style (v2.0.0 helper)
    pub fn withDim(self: Style) Style {
        var result = self;
        result.dim = true;
        return result;
    }

    /// Set background color on existing style (v2.0.0 helper)
    pub fn withBg(self: Style, color: Color) Style {
        var result = self;
        result.bg = color;
        return result;
    }

    /// Set foreground color on existing style (v2.0.0 helper)
    pub fn withFg(self: Style, color: Color) Style {
        var result = self;
        result.fg = color;
        return result;
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

    /// Create span with foreground color.
    ///
    /// Equivalent to: `Span{ .content = content, .style = .{ .fg = color } }`
    ///
    /// Example:
    /// ```zig
    /// const red_text = Span.colored("Error", .red);
    /// const custom = Span.colored("Info", Color.fromRgb(100, 150, 200));
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate for colored text.
    pub fn colored(content: []const u8, color: Color) Span {
        return .{ .content = content, .style = .{ .fg = color } };
    }

    /// Create bold span.
    ///
    /// Equivalent to: `Span{ .content = content, .style = .{ .bold = true } }`
    ///
    /// Example:
    /// ```zig
    /// const title = Span.bold("Important");
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor for bold text.
    pub fn bold(content: []const u8) Span {
        return .{ .content = content, .style = .{ .bold = true } };
    }

    /// Create italic span.
    ///
    /// Equivalent to: `Span{ .content = content, .style = .{ .italic = true } }`
    ///
    /// Example:
    /// ```zig
    /// const emphasis = Span.italic("Note:");
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor for italic text.
    pub fn italic(content: []const u8) Span {
        return .{ .content = content, .style = .{ .italic = true } };
    }

    /// Create underlined span.
    ///
    /// Equivalent to: `Span{ .content = content, .style = .{ .underline = true } }`
    ///
    /// Example:
    /// ```zig
    /// const link = Span.underline("https://example.com");
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor for underlined text.
    pub fn underline(content: []const u8) Span {
        return .{ .content = content, .style = .{ .underline = true } };
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

    /// Helper struct that owns a single-span Line and its backing array.
    ///
    /// This struct bundles a Line with its span array to ensure proper lifetime management.
    /// Use `.asLine()` to get a Line reference when needed.
    pub const SingleLine = struct {
        spans: [1]Span,

        pub fn asLine(self: *const SingleLine) Line {
            return .{ .spans = &self.spans };
        }
    };

    /// Create a SingleLine with a single raw (unstyled) span.
    ///
    /// This is a convenience method for the common case of creating a line
    /// with just plain text. The returned struct owns both the Line and its backing span array.
    ///
    /// Example:
    /// ```zig
    /// const single_line = Line.single("Hello, world!");
    /// const line = single_line.asLine();
    /// // Instead of:
    /// // const spans = [_]Span{Span.raw("Hello, world!")};
    /// // const line = Line{ .spans = &spans };
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor to reduce boilerplate for simple lines.
    pub fn single(content: []const u8) SingleLine {
        return .{ .spans = [1]Span{Span.raw(content)} };
    }

    /// Create a SingleLine with a single styled span.
    ///
    /// Example:
    /// ```zig
    /// const single_line = Line.singleStyled("Error!", .{ .fg = .red, .bold = true });
    /// const line = single_line.asLine();
    /// ```
    ///
    /// **v2.1.0**: Convenience constructor for single-span styled lines.
    pub fn singleStyled(content: []const u8, style: Style) SingleLine {
        return .{ .spans = [1]Span{Span.styled(content, style)} };
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
            .spans = .{},
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

// v2.0.0 Style Inference Helper Tests

test "Style.withForeground - foreground color helper" {
    const s = Style.withForeground(.red);
    try std.testing.expectEqual(Color.red, s.fg.?);
    try std.testing.expectEqual(null, s.bg);
    try std.testing.expectEqual(false, s.bold);
}

test "Style.withBackground - background color helper" {
    const s = Style.withBackground(.blue);
    try std.testing.expectEqual(Color.blue, s.bg.?);
    try std.testing.expectEqual(null, s.fg);
}

test "Style.withColors - foreground and background" {
    const s = Style.withColors(.white, .black);
    try std.testing.expectEqual(Color.white, s.fg.?);
    try std.testing.expectEqual(Color.black, s.bg.?);
}

test "Style.makeBold - bold modifier helper" {
    const s = Style.makeBold();
    try std.testing.expectEqual(true, s.bold);
    try std.testing.expectEqual(false, s.italic);
}

test "Style.makeItalic - italic modifier helper" {
    const s = Style.makeItalic();
    try std.testing.expectEqual(true, s.italic);
    try std.testing.expectEqual(false, s.bold);
}

test "Style.makeUnderline - underline modifier helper" {
    const s = Style.makeUnderline();
    try std.testing.expectEqual(true, s.underline);
}

test "Style.makeDim - dim modifier helper" {
    const s = Style.makeDim();
    try std.testing.expectEqual(true, s.dim);
}

test "Style.withBold - add bold to existing style" {
    const s = Style.withForeground(.red).withBold();
    try std.testing.expectEqual(Color.red, s.fg.?);
    try std.testing.expectEqual(true, s.bold);
}

test "Style.withItalic - add italic to existing style" {
    const s = Style.withBackground(.blue).withItalic();
    try std.testing.expectEqual(Color.blue, s.bg.?);
    try std.testing.expectEqual(true, s.italic);
}

test "Style.withUnderline - add underline to existing style" {
    const s = Style.withForeground(.green).withUnderline();
    try std.testing.expectEqual(Color.green, s.fg.?);
    try std.testing.expectEqual(true, s.underline);
}

test "Style.withDim - add dim to existing style" {
    const s = Style.withForeground(.yellow).withDim();
    try std.testing.expectEqual(Color.yellow, s.fg.?);
    try std.testing.expectEqual(true, s.dim);
}

test "Style.withBg - set background on existing style" {
    const s = Style.withForeground(.red).withBg(.blue);
    try std.testing.expectEqual(Color.red, s.fg.?);
    try std.testing.expectEqual(Color.blue, s.bg.?);
}

test "Style.withFg - set foreground on existing style" {
    const s = Style.withBackground(.blue).withFg(.red);
    try std.testing.expectEqual(Color.red, s.fg.?);
    try std.testing.expectEqual(Color.blue, s.bg.?);
}

test "Style helpers - chaining multiple modifiers" {
    const s = Style.withForeground(.red).withBold().withItalic().withUnderline();
    try std.testing.expectEqual(Color.red, s.fg.?);
    try std.testing.expectEqual(true, s.bold);
    try std.testing.expectEqual(true, s.italic);
    try std.testing.expectEqual(true, s.underline);
}

test "Style helpers - complex chaining with colors and modifiers" {
    const s = Style.withForeground(.white).withBg(.blue).withBold().withDim();
    try std.testing.expectEqual(Color.white, s.fg.?);
    try std.testing.expectEqual(Color.blue, s.bg.?);
    try std.testing.expectEqual(true, s.bold);
    try std.testing.expectEqual(true, s.dim);
}

// Color Convenience Constructor Tests

test "Color.fromRgb - basic construction" {
    const c = Color.fromRgb(255, 128, 64);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 128), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 64), c.rgb.b);
}

test "Color.fromRgb - equivalence to verbose syntax" {
    const c1 = Color.fromRgb(100, 150, 200);
    const c2 = Color{ .rgb = .{ .r = 100, .g = 150, .b = 200 } };
    try std.testing.expectEqual(c2.rgb.r, c1.rgb.r);
    try std.testing.expectEqual(c2.rgb.g, c1.rgb.g);
    try std.testing.expectEqual(c2.rgb.b, c1.rgb.b);
}

test "Color.fromRgb - edge case zero values" {
    const c = Color.fromRgb(0, 0, 0);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "Color.fromRgb - edge case max values" {
    const c = Color.fromRgb(255, 255, 255);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.b);
}

test "Color.fromRgb - boundary values individual channels" {
    const c1 = Color.fromRgb(255, 0, 128);
    try std.testing.expectEqual(@as(u8, 255), c1.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), c1.rgb.g);
    try std.testing.expectEqual(@as(u8, 128), c1.rgb.b);

    const c2 = Color.fromRgb(0, 255, 64);
    try std.testing.expectEqual(@as(u8, 0), c2.rgb.r);
    try std.testing.expectEqual(@as(u8, 255), c2.rgb.g);
    try std.testing.expectEqual(@as(u8, 64), c2.rgb.b);
}

test "Color.fromRgb - renders correctly to ANSI foreground" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const c = Color.fromRgb(255, 128, 0);
    try c.toFg(writer);
    try std.testing.expectEqualStrings("\x1b[38;2;255;128;0m", fbs.getWritten());
}

test "Color.fromRgb - renders correctly to ANSI background" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const c = Color.fromRgb(50, 100, 150);
    try c.toBg(writer);
    try std.testing.expectEqualStrings("\x1b[48;2;50;100;150m", fbs.getWritten());
}

test "Color.fromIndexed - basic construction" {
    const c = Color.fromIndexed(42);
    try std.testing.expectEqual(@as(u8, 42), c.indexed);
}

test "Color.fromIndexed - equivalence to verbose syntax" {
    const c1 = Color.fromIndexed(208);
    const c2 = Color{ .indexed = 208 };
    try std.testing.expectEqual(c2.indexed, c1.indexed);
}

test "Color.fromIndexed - edge case zero" {
    const c = Color.fromIndexed(0);
    try std.testing.expectEqual(@as(u8, 0), c.indexed);
}

test "Color.fromIndexed - edge case max (255)" {
    const c = Color.fromIndexed(255);
    try std.testing.expectEqual(@as(u8, 255), c.indexed);
}

test "Color.fromIndexed - common xterm colors" {
    const c16 = Color.fromIndexed(16); // black (256-color mode)
    const c196 = Color.fromIndexed(196); // red
    const c231 = Color.fromIndexed(231); // white
    try std.testing.expectEqual(@as(u8, 16), c16.indexed);
    try std.testing.expectEqual(@as(u8, 196), c196.indexed);
    try std.testing.expectEqual(@as(u8, 231), c231.indexed);
}

test "Color.fromIndexed - renders correctly to ANSI foreground" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const c = Color.fromIndexed(208);
    try c.toFg(writer);
    try std.testing.expectEqualStrings("\x1b[38;5;208m", fbs.getWritten());
}

test "Color.fromIndexed - renders correctly to ANSI background" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const c = Color.fromIndexed(42);
    try c.toBg(writer);
    try std.testing.expectEqualStrings("\x1b[48;5;42m", fbs.getWritten());
}

test "Color.fromHex - basic construction" {
    const c = Color.fromHex(0xFF8040);
    try std.testing.expectEqual(@as(u8, 0xFF), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 0x80), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0x40), c.rgb.b);
}

test "Color.fromHex - red (0xFF0000)" {
    const c = Color.fromHex(0xFF0000);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "Color.fromHex - green (0x00FF00)" {
    const c = Color.fromHex(0x00FF00);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "Color.fromHex - blue (0x0000FF)" {
    const c = Color.fromHex(0x0000FF);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.b);
}

test "Color.fromHex - white (0xFFFFFF)" {
    const c = Color.fromHex(0xFFFFFF);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.b);
}

test "Color.fromHex - black (0x000000)" {
    const c = Color.fromHex(0x000000);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "Color.fromHex - common web colors" {
    // Orange (#FFA500)
    const orange = Color.fromHex(0xFFA500);
    try std.testing.expectEqual(@as(u8, 0xFF), orange.rgb.r);
    try std.testing.expectEqual(@as(u8, 0xA5), orange.rgb.g);
    try std.testing.expectEqual(@as(u8, 0x00), orange.rgb.b);

    // Purple (#800080)
    const purple = Color.fromHex(0x800080);
    try std.testing.expectEqual(@as(u8, 0x80), purple.rgb.r);
    try std.testing.expectEqual(@as(u8, 0x00), purple.rgb.g);
    try std.testing.expectEqual(@as(u8, 0x80), purple.rgb.b);

    // Teal (#008080)
    const teal = Color.fromHex(0x008080);
    try std.testing.expectEqual(@as(u8, 0x00), teal.rgb.r);
    try std.testing.expectEqual(@as(u8, 0x80), teal.rgb.g);
    try std.testing.expectEqual(@as(u8, 0x80), teal.rgb.b);
}

test "Color.fromHex - edge case minimum value" {
    const c = Color.fromHex(0x000000);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "Color.fromHex - edge case maximum value" {
    const c = Color.fromHex(0xFFFFFF);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.b);
}

test "Color.fromHex - equivalence to fromRgb" {
    const c1 = Color.fromHex(0xABCDEF);
    const c2 = Color.fromRgb(0xAB, 0xCD, 0xEF);
    try std.testing.expectEqual(c2.rgb.r, c1.rgb.r);
    try std.testing.expectEqual(c2.rgb.g, c1.rgb.g);
    try std.testing.expectEqual(c2.rgb.b, c1.rgb.b);
}

test "Color.fromHex - renders correctly to ANSI foreground" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const c = Color.fromHex(0xFF8000);
    try c.toFg(writer);
    try std.testing.expectEqualStrings("\x1b[38;2;255;128;0m", fbs.getWritten());
}

test "Color.fromHex - renders correctly to ANSI background" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const c = Color.fromHex(0x326496);
    try c.toBg(writer);
    try std.testing.expectEqualStrings("\x1b[48;2;50;100;150m", fbs.getWritten());
}

test "Color.fromHex - bit extraction correctness" {
    // Test that bit shifting/masking works correctly
    const c = Color.fromHex(0x123456);
    try std.testing.expectEqual(@as(u8, 0x12), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 0x34), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0x56), c.rgb.b);
}

// Integration tests: using convenience constructors with Style

test "Color convenience constructors - integration with Style.withForeground using fromRgb" {
    const s = Style.withForeground(Color.fromRgb(255, 100, 50));
    try std.testing.expectEqual(@as(u8, 255), s.fg.?.rgb.r);
    try std.testing.expectEqual(@as(u8, 100), s.fg.?.rgb.g);
    try std.testing.expectEqual(@as(u8, 50), s.fg.?.rgb.b);
}

test "Color convenience constructors - integration with Style.withForeground using fromIndexed" {
    const s = Style.withForeground(Color.fromIndexed(196));
    try std.testing.expectEqual(@as(u8, 196), s.fg.?.indexed);
}

test "Color convenience constructors - integration with Style.withForeground using fromHex" {
    const s = Style.withForeground(Color.fromHex(0xFF6347)); // Tomato
    try std.testing.expectEqual(@as(u8, 0xFF), s.fg.?.rgb.r);
    try std.testing.expectEqual(@as(u8, 0x63), s.fg.?.rgb.g);
    try std.testing.expectEqual(@as(u8, 0x47), s.fg.?.rgb.b);
}

test "Color convenience constructors - integration with Style.withColors" {
    const s = Style.withColors(Color.fromHex(0xFFFFFF), Color.fromHex(0x000000));
    try std.testing.expectEqual(@as(u8, 255), s.fg.?.rgb.r);
    try std.testing.expectEqual(@as(u8, 255), s.fg.?.rgb.g);
    try std.testing.expectEqual(@as(u8, 255), s.fg.?.rgb.b);
    try std.testing.expectEqual(@as(u8, 0), s.bg.?.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), s.bg.?.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), s.bg.?.rgb.b);
}

test "Color convenience constructors - integration with Style rendering" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const s = Style.withForeground(Color.fromRgb(255, 128, 0));
    try s.apply(writer);
    try std.testing.expectEqualStrings("\x1b[38;2;255;128;0m", fbs.getWritten());
}

test "Color convenience constructors - integration with Span rendering using fromHex" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const span = Span.styled("test", Style.withForeground(Color.fromHex(0xFF0000)));
    try span.render(writer);
    try std.testing.expectEqualStrings("\x1b[38;2;255;0;0mtest\x1b[0m", fbs.getWritten());
}

test "Color convenience constructors - all three methods produce valid Color unions" {
    const c1 = Color.fromRgb(100, 150, 200);
    const c2 = Color.fromIndexed(42);
    const c3 = Color.fromHex(0xABCDEF);

    // Test that they can be used in switch (valid Color union variants)
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try c1.toFg(writer);
    fbs.reset();
    try c2.toFg(writer);
    fbs.reset();
    try c3.toFg(writer);
}

// ============================================================================
// Span & Line Convenience Constructor Tests (v2.1.0)
// ============================================================================

// Span.colored() tests

test "Span.colored - basic construction with foreground color" {
    const span = Span.colored("hello", .red);
    try std.testing.expectEqualStrings("hello", span.content);
    try std.testing.expectEqual(Color.red, span.style.fg.?);
}

test "Span.colored - equivalence to manual construction" {
    const s1 = Span.colored("test", .blue);
    const s2 = Span{ .content = "test", .style = .{ .fg = .blue } };
    try std.testing.expectEqualStrings(s2.content, s1.content);
    try std.testing.expectEqual(s2.style.fg.?, s1.style.fg.?);
}

test "Span.colored - with basic colors" {
    const red = Span.colored("red", .red);
    const green = Span.colored("green", .green);
    const blue = Span.colored("blue", .blue);

    try std.testing.expectEqual(Color.red, red.style.fg.?);
    try std.testing.expectEqual(Color.green, green.style.fg.?);
    try std.testing.expectEqual(Color.blue, blue.style.fg.?);
}

test "Span.colored - with bright colors" {
    const span = Span.colored("bright", .bright_cyan);
    try std.testing.expectEqual(Color.bright_cyan, span.style.fg.?);
}

test "Span.colored - with indexed color" {
    const span = Span.colored("indexed", Color.fromIndexed(208));
    try std.testing.expectEqual(@as(u8, 208), span.style.fg.?.indexed);
}

test "Span.colored - with RGB color" {
    const span = Span.colored("rgb", Color.fromRgb(255, 128, 64));
    try std.testing.expectEqual(@as(u8, 255), span.style.fg.?.rgb.r);
    try std.testing.expectEqual(@as(u8, 128), span.style.fg.?.rgb.g);
    try std.testing.expectEqual(@as(u8, 64), span.style.fg.?.rgb.b);
}

test "Span.colored - with hex color" {
    const span = Span.colored("hex", Color.fromHex(0xFF6347));
    try std.testing.expectEqual(@as(u8, 0xFF), span.style.fg.?.rgb.r);
    try std.testing.expectEqual(@as(u8, 0x63), span.style.fg.?.rgb.g);
    try std.testing.expectEqual(@as(u8, 0x47), span.style.fg.?.rgb.b);
}

test "Span.colored - empty content" {
    const span = Span.colored("", .yellow);
    try std.testing.expectEqualStrings("", span.content);
    try std.testing.expectEqual(Color.yellow, span.style.fg.?);
}

test "Span.colored - other style fields remain default" {
    const span = Span.colored("test", .red);
    try std.testing.expectEqual(null, span.style.bg);
    try std.testing.expectEqual(false, span.style.bold);
    try std.testing.expectEqual(false, span.style.italic);
    try std.testing.expectEqual(false, span.style.underline);
}

test "Span.colored - renders correctly to ANSI" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const span = Span.colored("test", .red);
    try span.render(writer);
    try std.testing.expectEqualStrings("\x1b[31mtest\x1b[0m", fbs.getWritten());
}

test "Span.colored - multiple colors render correctly" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const red_span = Span.colored("red", .red);
    try red_span.render(writer);
    try std.testing.expectEqualStrings("\x1b[31mred\x1b[0m", fbs.getWritten());

    fbs.reset();
    const blue_span = Span.colored("blue", .blue);
    try blue_span.render(writer);
    try std.testing.expectEqualStrings("\x1b[34mblue\x1b[0m", fbs.getWritten());
}

// Span.bold() tests

test "Span.bold - basic construction" {
    const span = Span.bold("bold text");
    try std.testing.expectEqualStrings("bold text", span.content);
    try std.testing.expectEqual(true, span.style.bold);
}

test "Span.bold - equivalence to manual construction" {
    const s1 = Span.bold("test");
    const s2 = Span{ .content = "test", .style = .{ .bold = true } };
    try std.testing.expectEqualStrings(s2.content, s1.content);
    try std.testing.expectEqual(s2.style.bold, s1.style.bold);
}

test "Span.bold - empty content" {
    const span = Span.bold("");
    try std.testing.expectEqualStrings("", span.content);
    try std.testing.expectEqual(true, span.style.bold);
}

test "Span.bold - other style fields remain default" {
    const span = Span.bold("test");
    try std.testing.expectEqual(null, span.style.fg);
    try std.testing.expectEqual(null, span.style.bg);
    try std.testing.expectEqual(false, span.style.italic);
    try std.testing.expectEqual(false, span.style.underline);
}

test "Span.bold - renders correctly to ANSI" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const span = Span.bold("test");
    try span.render(writer);
    try std.testing.expectEqualStrings("\x1b[1mtest\x1b[0m", fbs.getWritten());
}

// Span.italic() tests

test "Span.italic - basic construction" {
    const span = Span.italic("italic text");
    try std.testing.expectEqualStrings("italic text", span.content);
    try std.testing.expectEqual(true, span.style.italic);
}

test "Span.italic - equivalence to manual construction" {
    const s1 = Span.italic("test");
    const s2 = Span{ .content = "test", .style = .{ .italic = true } };
    try std.testing.expectEqualStrings(s2.content, s1.content);
    try std.testing.expectEqual(s2.style.italic, s1.style.italic);
}

test "Span.italic - empty content" {
    const span = Span.italic("");
    try std.testing.expectEqualStrings("", span.content);
    try std.testing.expectEqual(true, span.style.italic);
}

test "Span.italic - other style fields remain default" {
    const span = Span.italic("test");
    try std.testing.expectEqual(null, span.style.fg);
    try std.testing.expectEqual(null, span.style.bg);
    try std.testing.expectEqual(false, span.style.bold);
    try std.testing.expectEqual(false, span.style.underline);
}

test "Span.italic - renders correctly to ANSI" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const span = Span.italic("test");
    try span.render(writer);
    try std.testing.expectEqualStrings("\x1b[3mtest\x1b[0m", fbs.getWritten());
}

// Span.underline() tests

test "Span.underline - basic construction" {
    const span = Span.underline("underlined text");
    try std.testing.expectEqualStrings("underlined text", span.content);
    try std.testing.expectEqual(true, span.style.underline);
}

test "Span.underline - equivalence to manual construction" {
    const s1 = Span.underline("test");
    const s2 = Span{ .content = "test", .style = .{ .underline = true } };
    try std.testing.expectEqualStrings(s2.content, s1.content);
    try std.testing.expectEqual(s2.style.underline, s1.style.underline);
}

test "Span.underline - empty content" {
    const span = Span.underline("");
    try std.testing.expectEqualStrings("", span.content);
    try std.testing.expectEqual(true, span.style.underline);
}

test "Span.underline - other style fields remain default" {
    const span = Span.underline("test");
    try std.testing.expectEqual(null, span.style.fg);
    try std.testing.expectEqual(null, span.style.bg);
    try std.testing.expectEqual(false, span.style.bold);
    try std.testing.expectEqual(false, span.style.italic);
}

test "Span.underline - renders correctly to ANSI" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const span = Span.underline("test");
    try span.render(writer);
    try std.testing.expectEqualStrings("\x1b[4mtest\x1b[0m", fbs.getWritten());
}

// Line.single() tests

test "Line.single - basic construction with plain text" {
    const single_line = Line.single("hello");
    const line = single_line.asLine();
    try std.testing.expectEqual(1, line.spans.len);
    try std.testing.expectEqualStrings("hello", line.spans[0].content);
    try std.testing.expectEqual(Style.default, line.spans[0].style);
}

test "Line.single - equivalence to manual construction" {
    const single_l1 = Line.single("test");
    const l1 = single_l1.asLine();
    const spans = [_]Span{Span.raw("test")};
    const l2 = Line{ .spans = &spans };
    try std.testing.expectEqual(l2.spans.len, l1.spans.len);
    try std.testing.expectEqualStrings(l2.spans[0].content, l1.spans[0].content);
}

test "Line.single - empty content" {
    const single_line = Line.single("");
    const line = single_line.asLine();
    try std.testing.expectEqual(1, line.spans.len);
    try std.testing.expectEqualStrings("", line.spans[0].content);
}

test "Line.single - renders correctly" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const single_line = Line.single("hello world");
    const line = single_line.asLine();
    try line.render(writer);
    try std.testing.expectEqualStrings("hello world", fbs.getWritten());
}

test "Line.single - width calculation" {
    const single_line = Line.single("hello");
    const line = single_line.asLine();
    try std.testing.expectEqual(5, line.width());
}

test "Line.single - multiple lines do not share spans" {
    const single_line1 = Line.single("first");
    const line1 = single_line1.asLine();
    const single_line2 = Line.single("second");
    const line2 = single_line2.asLine();

    try std.testing.expectEqualStrings("first", line1.spans[0].content);
    try std.testing.expectEqualStrings("second", line2.spans[0].content);
}

// Line.singleStyled() tests

test "Line.singleStyled - basic construction with foreground color" {
    const single_line = Line.singleStyled("styled", .{ .fg = .red });
    const line = single_line.asLine();
    try std.testing.expectEqual(1, line.spans.len);
    try std.testing.expectEqualStrings("styled", line.spans[0].content);
    try std.testing.expectEqual(Color.red, line.spans[0].style.fg.?);
}

test "Line.singleStyled - equivalence to manual construction" {
    const style = Style{ .fg = .blue, .bold = true };
    const single_l1 = Line.singleStyled("test", style);
    const l1 = single_l1.asLine();
    const spans = [_]Span{Span.styled("test", style)};
    const l2 = Line{ .spans = &spans };

    try std.testing.expectEqual(l2.spans.len, l1.spans.len);
    try std.testing.expectEqualStrings(l2.spans[0].content, l1.spans[0].content);
    try std.testing.expectEqual(l2.spans[0].style.fg.?, l1.spans[0].style.fg.?);
    try std.testing.expectEqual(l2.spans[0].style.bold, l1.spans[0].style.bold);
}

test "Line.singleStyled - with bold style" {
    const single_line = Line.singleStyled("bold", .{ .bold = true });
    const line = single_line.asLine();
    try std.testing.expectEqual(true, line.spans[0].style.bold);
}

test "Line.singleStyled - with multiple modifiers" {
    const single_line = Line.singleStyled("multi", .{
        .fg = .cyan,
        .bold = true,
        .italic = true,
    });
    const line = single_line.asLine();
    try std.testing.expectEqual(Color.cyan, line.spans[0].style.fg.?);
    try std.testing.expectEqual(true, line.spans[0].style.bold);
    try std.testing.expectEqual(true, line.spans[0].style.italic);
}

test "Line.singleStyled - empty content" {
    const single_line = Line.singleStyled("", .{ .fg = .green });
    const line = single_line.asLine();
    try std.testing.expectEqual(1, line.spans.len);
    try std.testing.expectEqualStrings("", line.spans[0].content);
    try std.testing.expectEqual(Color.green, line.spans[0].style.fg.?);
}

test "Line.singleStyled - renders correctly with color" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const single_line = Line.singleStyled("test", .{ .fg = .red });
    const line = single_line.asLine();
    try line.render(writer);
    try std.testing.expectEqualStrings("\x1b[31mtest\x1b[0m", fbs.getWritten());
}

test "Line.singleStyled - renders correctly with bold" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const single_line = Line.singleStyled("test", .{ .bold = true });
    const line = single_line.asLine();
    try line.render(writer);
    try std.testing.expectEqualStrings("\x1b[1mtest\x1b[0m", fbs.getWritten());
}

test "Line.singleStyled - renders correctly with multiple styles" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const single_line = Line.singleStyled("test", .{ .fg = .blue, .bold = true, .underline = true });
    const line = single_line.asLine();
    try line.render(writer);
    try std.testing.expectEqualStrings("\x1b[34m\x1b[1m\x1b[4mtest\x1b[0m", fbs.getWritten());
}

test "Line.singleStyled - width calculation" {
    const single_line = Line.singleStyled("hello", .{ .fg = .red });
    const line = single_line.asLine();
    try std.testing.expectEqual(5, line.width());
}

test "Line.singleStyled - with Style helper constructors" {
    const single_line = Line.singleStyled("test", Style.withForeground(.magenta));
    const line = single_line.asLine();
    try std.testing.expectEqual(Color.magenta, line.spans[0].style.fg.?);
}

// Integration tests: combining convenience constructors

test "Integration - Span.colored in multi-span Line" {
    const spans = [_]Span{
        Span.colored("Hello", .red),
        Span.raw(" "),
        Span.colored("world", .blue),
    };
    const line = Line{ .spans = &spans };

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try line.render(writer);
    const expected = "\x1b[31mHello\x1b[0m \x1b[34mworld\x1b[0m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Integration - Span.bold and Span.italic in same Line" {
    const spans = [_]Span{
        Span.bold("Bold"),
        Span.raw(" and "),
        Span.italic("Italic"),
    };
    const line = Line{ .spans = &spans };

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try line.render(writer);
    const expected = "\x1b[1mBold\x1b[0m and \x1b[3mItalic\x1b[0m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Integration - Line.single vs Line.singleStyled comparison" {
    const plain = Line.single("text");
    const styled = Line.singleStyled("text", .{ .fg = .red });

    try std.testing.expectEqualStrings(plain.spans[0].content, styled.spans[0].content);
    try std.testing.expectEqual(null, plain.spans[0].style.fg);
    try std.testing.expectEqual(Color.red, styled.spans[0].style.fg.?);
}

test "Integration - all Span helpers produce valid spans" {
    const spans = [_]Span{
        Span.colored("red", .red),
        Span.bold("bold"),
        Span.italic("italic"),
        Span.underline("underline"),
    };

    try std.testing.expectEqual(Color.red, spans[0].style.fg.?);
    try std.testing.expectEqual(true, spans[1].style.bold);
    try std.testing.expectEqual(true, spans[2].style.italic);
    try std.testing.expectEqual(true, spans[3].style.underline);
}

test "Integration - Line helpers reduce boilerplate" {
    // Verbose way
    const span1 = Span.raw("verbose");
    const spans1 = [_]Span{span1};
    const line1 = Line{ .spans = &spans1 };

    // Concise way
    const single_line2 = Line.single("verbose");
    const line2 = single_line2.asLine();

    try std.testing.expectEqualStrings(line1.spans[0].content, line2.spans[0].content);
}

test "Documentation - Span.colored usage example" {
    // Example from proposed API:
    // const error_msg = Span.colored("Error", .red);
    const error_msg = Span.colored("Error", .red);
    try std.testing.expectEqualStrings("Error", error_msg.content);
    try std.testing.expectEqual(Color.red, error_msg.style.fg.?);
}

test "Documentation - Span.bold usage example" {
    // Example from proposed API:
    // const header = Span.bold("Important");
    const header = Span.bold("Important");
    try std.testing.expectEqual(true, header.style.bold);
}

test "Documentation - Line.single usage example" {
    // Example from proposed API:
    // const single_line = Line.single("Hello, world!");
    // const line = single_line.asLine();
    const single_line = Line.single("Hello, world!");
    const line = single_line.asLine();
    try std.testing.expectEqual(1, line.spans.len);
    try std.testing.expectEqualStrings("Hello, world!", line.spans[0].content);
}

test "Documentation - Line.singleStyled usage example" {
    // Example from proposed API:
    // const warning = Line.singleStyled("Warning", .{ .fg = .yellow, .bold = true });
    const warning = Line.singleStyled("Warning", .{ .fg = .yellow, .bold = true });
    try std.testing.expectEqual(Color.yellow, warning.spans[0].style.fg.?);
    try std.testing.expectEqual(true, warning.spans[0].style.bold);
}
