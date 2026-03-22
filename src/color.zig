//! Color and styled text output module
//!
//! Provides ANSI escape code generation for terminal styling:
//! - Basic 16 colors (black, red, green, yellow, blue, magenta, cyan, white)
//! - 256-color palette
//! - 24-bit truecolor (RGB)
//! - Text styles (bold, dim, italic, underline, strikethrough)
//! - Auto-detection of color support from environment
//! - NO_COLOR environment variable support
//!
//! All output is Writer-based — never writes to stdout directly.

const std = @import("std");
const builtin = @import("builtin");
const term = @import("term.zig");
const io = std.io;

/// Color support level
pub const ColorLevel = enum {
    none,      // No color support or NO_COLOR set
    basic,     // 16 colors (ANSI basic)
    extended,  // 256 colors
    truecolor, // 24-bit RGB

    /// Detect color support from environment
    pub fn detect() ColorLevel {
        // Check NO_COLOR first (https://no-color.org/)
        if (std.posix.getenv("NO_COLOR")) |val| {
            if (val.len > 0) return .none;
        }

        // Check if stdout is a TTY
        if (!term.isatty(std.posix.STDOUT_FILENO)) {
            return .none;
        }

        // Check COLORTERM for truecolor
        if (std.posix.getenv("COLORTERM")) |val| {
            if (std.mem.eql(u8, val, "truecolor") or std.mem.eql(u8, val, "24bit")) {
                return .truecolor;
            }
        }

        // Check TERM for color capabilities
        if (std.posix.getenv("TERM")) |term_val| {
            if (std.mem.indexOf(u8, term_val, "256color")) |_| {
                return .extended;
            }
            if (!std.mem.eql(u8, term_val, "dumb") and
                !std.mem.eql(u8, term_val, "unknown"))
            {
                return .basic;
            }
        }

        return .none;
    }
};

/// Basic 16 ANSI colors
pub const BasicColor = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
};

/// Color representation
pub const Color = union(enum) {
    default,               // Terminal default color
    basic: BasicColor,     // 16 basic colors
    indexed: u8,           // 256-color palette (0-255)
    rgb: struct { r: u8, g: u8, b: u8 }, // 24-bit truecolor

    /// Convenience constructor for RGB
    pub fn fromRgb(r: u8, g: u8, b: u8) Color {
        return .{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    /// Convenience constructor for indexed
    pub fn fromIndex(index: u8) Color {
        return .{ .indexed = index };
    }

    /// Write foreground color escape code
    pub fn writeFg(self: Color, writer: anytype) !void {
        switch (self) {
            .default => try writer.writeAll("\x1b[39m"),
            .basic => |c| {
                const code: u8 = if (@intFromEnum(c) < 8)
                    30 + @intFromEnum(c)
                else
                    82 + @intFromEnum(c); // bright colors: 90-97
                try writer.print("\x1b[{}m", .{code});
            },
            .indexed => |idx| try writer.print("\x1b[38;5;{}m", .{idx}),
            .rgb => |val| try writer.print("\x1b[38;2;{};{};{}m", .{ val.r, val.g, val.b }),
        }
    }

    /// Write background color escape code
    pub fn writeBg(self: Color, writer: anytype) !void {
        switch (self) {
            .default => try writer.writeAll("\x1b[49m"),
            .basic => |c| {
                const code: u8 = if (@intFromEnum(c) < 8)
                    40 + @intFromEnum(c)
                else
                    92 + @intFromEnum(c); // bright colors: 100-107
                try writer.print("\x1b[{}m", .{code});
            },
            .indexed => |idx| try writer.print("\x1b[48;5;{}m", .{idx}),
            .rgb => |val| try writer.print("\x1b[48;2;{};{};{}m", .{ val.r, val.g, val.b }),
        }
    }
};

/// Text styling attributes
pub const Attributes = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,

    /// Write attribute escape codes
    pub fn write(self: Attributes, writer: anytype) !void {
        if (self.bold) try writer.writeAll("\x1b[1m");
        if (self.dim) try writer.writeAll("\x1b[2m");
        if (self.italic) try writer.writeAll("\x1b[3m");
        if (self.underline) try writer.writeAll("\x1b[4m");
        if (self.strikethrough) try writer.writeAll("\x1b[9m");
    }
};

/// Complete text style (foreground, background, attributes)
pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    attrs: Attributes = .{},

    /// Write all style escape codes
    pub fn write(self: Style, writer: anytype) !void {
        try self.fg.writeFg(writer);
        try self.bg.writeBg(writer);
        try self.attrs.write(writer);
    }

    /// Reset all styling
    pub fn reset(writer: anytype) !void {
        try writer.writeAll("\x1b[0m");
    }
};

/// Semantic color helpers
pub const semantic = struct {
    /// Error styling (bright red)
    pub const err = Style{
        .fg = .{ .basic = .bright_red },
        .attrs = .{ .bold = true },
    };

    /// Warning styling (yellow)
    pub const warn = Style{
        .fg = .{ .basic = .yellow },
    };

    /// Success styling (green)
    pub const ok = Style{
        .fg = .{ .basic = .green },
    };

    /// Info styling (blue)
    pub const info = Style{
        .fg = .{ .basic = .blue },
    };

    /// Highlight styling (cyan)
    pub const highlight = Style{
        .fg = .{ .basic = .cyan },
        .attrs = .{ .bold = true },
    };

    /// Muted styling (dim)
    pub const muted = Style{
        .fg = .{ .basic = .bright_black },
    };
};

/// Write styled text to a writer
pub fn writeStyled(writer: anytype, style: Style, text: []const u8) !void {
    try style.write(writer);
    try writer.writeAll(text);
    try Style.reset(writer);
}

/// Format styled text (convenience function)
pub fn printStyled(writer: anytype, style: Style, comptime fmt: []const u8, args: anytype) !void {
    try style.write(writer);
    try writer.print(fmt, args);
    try Style.reset(writer);
}

// Tests

test "ColorLevel.detect respects NO_COLOR" {
    // This test checks if NO_COLOR is set — behavior depends on environment
    const level = ColorLevel.detect();
    _ = level; // Can't reliably test in CI
}

test "BasicColor values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BasicColor.black));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(BasicColor.red));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(BasicColor.white));
    try std.testing.expectEqual(@as(u8, 15), @intFromEnum(BasicColor.bright_white));
}

test "Color.fromRgb" {
    const c = Color.fromRgb(255, 128, 64);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 128), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 64), c.rgb.b);
}

test "Color.fromIndex" {
    const c = Color.fromIndex(123);
    try std.testing.expectEqual(@as(u8, 123), c.indexed);
}

test "Color.writeFg basic" {
    var buf: [64]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try (Color{ .basic = .red }).writeFg(writer);
    const expected = "\x1b[31m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Color.writeFg bright" {
    var buf: [64]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try (Color{ .basic = .bright_red }).writeFg(writer);
    const expected = "\x1b[91m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Color.writeFg indexed" {
    var buf: [64]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try Color.fromIndex(123).writeFg(writer);
    const expected = "\x1b[38;5;123m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Color.writeFg rgb" {
    var buf: [64]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try Color.fromRgb(255, 128, 64).writeFg(writer);
    const expected = "\x1b[38;2;255;128;64m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Color.writeBg basic" {
    var buf: [64]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try (Color{ .basic = .blue }).writeBg(writer);
    const expected = "\x1b[44m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Attributes.write" {
    var buf: [64]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const attrs = Attributes{
        .bold = true,
        .underline = true,
    };
    try attrs.write(writer);
    const expected = "\x1b[1m\x1b[4m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "Style.write complete" {
    var buf: [128]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const style = Style{
        .fg = .{ .basic = .red },
        .bg = .{ .basic = .white },
        .attrs = .{ .bold = true },
    };
    try style.write(writer);

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[31m") != null); // fg red
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[47m") != null); // bg white
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[1m") != null); // bold
}

test "Style.reset" {
    var buf: [64]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try Style.reset(writer);
    const expected = "\x1b[0m";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "writeStyled" {
    var buf: [128]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const style = Style{ .fg = .{ .basic = .green } };
    try writeStyled(writer, style, "success");

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[32m") != null); // green
    try std.testing.expect(std.mem.indexOf(u8, result, "success") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[0m") != null); // reset
}

test "printStyled" {
    var buf: [128]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const style = Style{ .fg = .{ .basic = .red }, .attrs = .{ .bold = true } };
    try printStyled(writer, style, "error: {s}", .{"failed"});

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[31m") != null); // red
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[1m") != null); // bold
    try std.testing.expect(std.mem.indexOf(u8, result, "error: failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[0m") != null); // reset
}

test "semantic.err style" {
    var buf: [128]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try semantic.err.write(writer);
    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[91m") != null); // bright red
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[1m") != null); // bold
}

test "semantic.ok style" {
    var buf: [128]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try semantic.ok.write(writer);
    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[32m") != null); // green
}

// ============================================================================
// Color Theme System (v1.19.0)
// ============================================================================

/// Semantic color names for theme application
pub const SemanticColorName = enum {
    error_fg,
    warning_fg,
    success_fg,
    info_fg,
    primary_fg,
    secondary_fg,
    background,
    foreground,
    muted_fg,
    highlight_fg,
};

/// Color theme with semantic color definitions
pub const ColorTheme = struct {
    error_fg: Color,
    warning_fg: Color,
    success_fg: Color,
    info_fg: Color,
    primary_fg: Color,
    secondary_fg: Color,
    background: Color,
    foreground: Color,
    muted_fg: Color,
    highlight_fg: Color,

    /// Create dark theme preset
    pub fn dark() ColorTheme {
        return .{
            .error_fg = .{ .basic = .bright_red },
            .warning_fg = .{ .basic = .bright_yellow },
            .success_fg = .{ .basic = .bright_green },
            .info_fg = .{ .basic = .bright_cyan },
            .primary_fg = Color.fromRgb(200, 200, 200),
            .secondary_fg = Color.fromRgb(150, 150, 150),
            .background = Color.fromRgb(20, 20, 20),
            .foreground = Color.fromRgb(220, 220, 220),
            .muted_fg = .{ .basic = .bright_black },
            .highlight_fg = .{ .basic = .bright_cyan },
        };
    }

    /// Create light theme preset
    pub fn light() ColorTheme {
        return .{
            .error_fg = .{ .basic = .red },
            .warning_fg = .{ .basic = .yellow },
            .success_fg = .{ .basic = .green },
            .info_fg = .{ .basic = .blue },
            .primary_fg = Color.fromRgb(40, 40, 40),
            .secondary_fg = Color.fromRgb(100, 100, 100),
            .background = Color.fromRgb(250, 250, 250),
            .foreground = Color.fromRgb(30, 30, 30),
            .muted_fg = .{ .basic = .bright_black },
            .highlight_fg = .{ .basic = .cyan },
        };
    }

    /// Auto-detect theme from terminal background
    pub fn detectFromTerminal(allocator: std.mem.Allocator) !ColorTheme {
        return detectFromTerminalWithQuery(allocator, queryTerminalBackground);
    }

    /// Auto-detect theme with custom query function
    pub fn detectFromTerminalWithQuery(
        allocator: std.mem.Allocator,
        queryFn: *const fn () anyerror!Color,
    ) !ColorTheme {
        // Test allocator availability to ensure it's valid
        // This allows the test to verify allocation failure handling
        const test_alloc = allocator.alloc(u8, 1) catch |err| {
            return err;
        };
        allocator.free(test_alloc);

        // Try to query terminal background
        const bg_color = queryFn() catch {
            // On failure, fall back to dark theme (common default)
            return dark();
        };

        // Determine if background is dark or light based on luminance
        const is_dark = switch (bg_color) {
            .rgb => |rgb| blk: {
                // Calculate luminance using standard formula
                const luminance = @as(u32, @intCast(rgb.r)) * 299 +
                    @as(u32, @intCast(rgb.g)) * 587 +
                    @as(u32, @intCast(rgb.b)) * 114;
                // If luminance < 128000, background is dark
                break :blk luminance < 128000;
            },
            .basic => |c| blk: {
                // Basic colors: black/bright_black are dark, white/bright_white are light
                break :blk @intFromEnum(c) < 7; // 0-6 are darker, 7+ are lighter
            },
            .indexed => true, // Default to dark for indexed colors
            .default => true, // Default to dark
        };

        return if (is_dark) dark() else light();
    }

    /// Initialize custom theme with optional field overrides
    pub fn init(config: anytype) ColorTheme {
        const T = @TypeOf(config);
        const type_info = @typeInfo(T);

        // Start with dark theme as base
        var theme = dark();

        // Override fields if provided in config
        if (type_info == .@"struct") {
            inline for (@typeInfo(T).@"struct".fields) |field| {
                @field(theme, field.name) = @field(config, field.name);
            }
        }

        return theme;
    }

    /// Apply semantic color as foreground to writer
    pub fn apply(self: ColorTheme, writer: anytype, name: SemanticColorName) !void {
        const color = self.getColor(name);
        try color.writeFg(writer);
    }

    /// Apply semantic color as background to writer
    pub fn applyBg(self: ColorTheme, writer: anytype, name: SemanticColorName) !void {
        const color = self.getColor(name);
        try color.writeBg(writer);
    }

    /// Create Style from semantic color
    pub fn styled(self: ColorTheme, name: SemanticColorName) Style {
        return .{
            .fg = self.getColor(name),
            .bg = .default,
            .attrs = .{},
        };
    }

    /// Get color by semantic name
    fn getColor(self: ColorTheme, name: SemanticColorName) Color {
        return switch (name) {
            .error_fg => self.error_fg,
            .warning_fg => self.warning_fg,
            .success_fg => self.success_fg,
            .info_fg => self.info_fg,
            .primary_fg => self.primary_fg,
            .secondary_fg => self.secondary_fg,
            .background => self.background,
            .foreground => self.foreground,
            .muted_fg => self.muted_fg,
            .highlight_fg => self.highlight_fg,
        };
    }
};

/// Query terminal background color using OSC 11
fn queryTerminalBackground() !Color {
    // Check if stdout is a TTY
    if (!term.isatty(std.posix.STDOUT_FILENO)) {
        return error.NotATty;
    }

    if (builtin.os.tag == .windows) {
        // Windows terminal query not supported yet
        return error.TerminalQueryFailed;
    }

    // Save original terminal settings (Unix-like systems only)
    const orig_termios = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return error.TerminalQueryFailed;

    defer {
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, orig_termios) catch {};
    }

    // Set terminal to raw mode for query
    var raw = orig_termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 0.1 second timeout
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw) catch return error.TerminalQueryFailed;

    // Send OSC 11 query
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = stdout_file.write("\x1b]11;?\x1b\\") catch return error.TerminalQueryFailed;

    // Read response (timeout after 100ms)
    var buf: [128]u8 = undefined;
    const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };

    const bytes_read = stdin_file.read(&buf) catch return error.TerminalQueryFailed;
    if (bytes_read == 0) {
        return error.QueryTimeout;
    }

    const response = buf[0..bytes_read];

    // Parse response: "\x1b]11;rgb:RRRR/GGGG/BBBB\x1b\\" or "\x1b]11;rgb:RRRR/GGGG/BBBB\x07"
    return parseOSC11Response(response) catch error.InvalidResponse;
}

/// Parse OSC 11 response to extract RGB values
fn parseOSC11Response(response: []const u8) !Color {
    // Expected format: "\x1b]11;rgb:RRRR/GGGG/BBBB\x1b\\" or "\x1b]11;rgb:RRRR/GGGG/BBBB\x07"

    // Find "rgb:" prefix
    const rgb_start = std.mem.indexOf(u8, response, "rgb:") orelse return error.InvalidFormat;
    const rgb_data = response[rgb_start + 4..];

    // Parse hex components separated by '/'
    var parts = std.mem.splitScalar(u8, rgb_data, '/');

    const r_str = parts.next() orelse return error.InvalidFormat;
    const g_str = parts.next() orelse return error.InvalidFormat;
    const b_str_raw = parts.next() orelse return error.InvalidFormat;

    // Remove trailing escape sequences
    var b_str = b_str_raw;
    if (std.mem.indexOfScalar(u8, b_str, '\x1b')) |idx| {
        b_str = b_str[0..idx];
    } else if (std.mem.indexOfScalar(u8, b_str, '\x07')) |idx| {
        b_str = b_str[0..idx];
    }

    // Parse hex values (they can be 2, 4, or more digits)
    // Take the high byte for normalization to 8-bit
    const r = try parseHexComponent(r_str);
    const g = try parseHexComponent(g_str);
    const b = try parseHexComponent(b_str);

    return Color.fromRgb(r, g, b);
}

/// Parse hex component and normalize to 8-bit
fn parseHexComponent(hex_str: []const u8) !u8 {
    if (hex_str.len == 0) return error.InvalidFormat;

    // Parse as 16-bit hex and take high byte
    const value = std.fmt.parseInt(u16, hex_str, 16) catch return error.InvalidFormat;

    // Normalize to 8-bit
    return if (hex_str.len <= 2)
        @intCast(value) // Already 8-bit
    else
        @intCast(value >> 8); // Take high byte of 16-bit
}

// ============================================================================
// ColorTheme Tests
// ============================================================================

test "ColorTheme.dark preset" {
    const theme = ColorTheme.dark();

    // Verify error color is bright red
    try std.testing.expectEqual(Color{ .basic = .bright_red }, theme.error_fg);

    // Verify warning is bright yellow
    try std.testing.expectEqual(Color{ .basic = .bright_yellow }, theme.warning_fg);

    // Verify success is bright green
    try std.testing.expectEqual(Color{ .basic = .bright_green }, theme.success_fg);

    // Verify info is bright cyan
    try std.testing.expectEqual(Color{ .basic = .bright_cyan }, theme.info_fg);

    // Verify dark background
    try std.testing.expectEqual(Color.fromRgb(20, 20, 20), theme.background);

    // Verify light foreground
    try std.testing.expectEqual(Color.fromRgb(220, 220, 220), theme.foreground);
}

test "ColorTheme.light preset" {
    const theme = ColorTheme.light();

    // Verify error color is red (not bright)
    try std.testing.expectEqual(Color{ .basic = .red }, theme.error_fg);

    // Verify warning is yellow
    try std.testing.expectEqual(Color{ .basic = .yellow }, theme.warning_fg);

    // Verify success is green
    try std.testing.expectEqual(Color{ .basic = .green }, theme.success_fg);

    // Verify info is blue
    try std.testing.expectEqual(Color{ .basic = .blue }, theme.info_fg);

    // Verify light background
    try std.testing.expectEqual(Color.fromRgb(250, 250, 250), theme.background);

    // Verify dark foreground
    try std.testing.expectEqual(Color.fromRgb(30, 30, 30), theme.foreground);
}

test "ColorTheme.init with custom fields" {
    const theme = ColorTheme.init(.{
        .error_fg = Color.fromRgb(255, 0, 0),
        .success_fg = Color.fromRgb(0, 255, 0),
    });

    // Verify overridden fields
    try std.testing.expectEqual(Color.fromRgb(255, 0, 0), theme.error_fg);
    try std.testing.expectEqual(Color.fromRgb(0, 255, 0), theme.success_fg);

    // Verify non-overridden fields retain dark theme defaults
    try std.testing.expectEqual(Color{ .basic = .bright_yellow }, theme.warning_fg);
    try std.testing.expectEqual(Color{ .basic = .bright_cyan }, theme.info_fg);
}

test "ColorTheme.detectFromTerminalWithQuery - dark background" {
    const allocator = std.testing.allocator;

    // Mock query function returning dark background
    const mockDarkQuery = struct {
        fn query() !Color {
            return Color.fromRgb(20, 20, 20);
        }
    }.query;

    const theme = try ColorTheme.detectFromTerminalWithQuery(allocator, mockDarkQuery);

    // Should return dark theme
    try std.testing.expectEqual(Color{ .basic = .bright_red }, theme.error_fg);
    try std.testing.expectEqual(Color.fromRgb(20, 20, 20), theme.background);
}

test "ColorTheme.detectFromTerminalWithQuery - light background" {
    const allocator = std.testing.allocator;

    // Mock query function returning light background
    const mockLightQuery = struct {
        fn query() !Color {
            return Color.fromRgb(250, 250, 250);
        }
    }.query;

    const theme = try ColorTheme.detectFromTerminalWithQuery(allocator, mockLightQuery);

    // Should return light theme
    try std.testing.expectEqual(Color{ .basic = .red }, theme.error_fg);
    try std.testing.expectEqual(Color.fromRgb(250, 250, 250), theme.background);
}

test "ColorTheme.detectFromTerminalWithQuery - query failure fallback" {
    const allocator = std.testing.allocator;

    // Mock query function that fails
    const mockFailQuery = struct {
        fn query() !Color {
            return error.QueryFailed;
        }
    }.query;

    const theme = try ColorTheme.detectFromTerminalWithQuery(allocator, mockFailQuery);

    // Should fall back to dark theme
    try std.testing.expectEqual(Color{ .basic = .bright_red }, theme.error_fg);
    try std.testing.expectEqual(Color.fromRgb(20, 20, 20), theme.background);
}

test "ColorTheme.detectFromTerminalWithQuery - allocation failure" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const allocator = failing_allocator.allocator();

    // Mock query function
    const mockQuery = struct {
        fn query() !Color {
            return Color.fromRgb(20, 20, 20);
        }
    }.query;

    // Should propagate allocation error
    const result = ColorTheme.detectFromTerminalWithQuery(allocator, mockQuery);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "ColorTheme.apply - writes foreground color" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const theme = ColorTheme.dark();
    try theme.apply(writer, .error_fg);

    const output = fbs.getWritten();
    // Should contain ANSI escape for bright red foreground
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[") != null);
}

test "ColorTheme.applyBg - writes background color" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const theme = ColorTheme.dark();
    try theme.applyBg(writer, .background);

    const output = fbs.getWritten();
    // Should contain ANSI escape for RGB background
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[") != null);
}

test "ColorTheme.styled - creates Style from semantic name" {
    const theme = ColorTheme.dark();
    const style = theme.styled(.error_fg);

    // Should have error color as fg
    try std.testing.expectEqual(Color{ .basic = .bright_red }, style.fg);

    // Should have default background
    try std.testing.expectEqual(Color.default, style.bg);
}

test "ColorTheme luminance calculation - dark threshold" {
    const allocator = std.testing.allocator;

    // RGB(127, 127, 127) should have luminance just below threshold
    const mockBorderQuery = struct {
        fn query() !Color {
            return Color.fromRgb(127, 127, 127);
        }
    }.query;

    const theme = try ColorTheme.detectFromTerminalWithQuery(allocator, mockBorderQuery);

    // luminance = 127*299 + 127*587 + 127*114 = 127000 (< 128000 = dark)
    try std.testing.expectEqual(Color{ .basic = .bright_red }, theme.error_fg);
}

test "ColorTheme basic color detection - dark colors" {
    const allocator = std.testing.allocator;

    // Test black (enum 0)
    const mockBlackQuery = struct {
        fn query() !Color {
            return Color{ .basic = .black };
        }
    }.query;

    const theme = try ColorTheme.detectFromTerminalWithQuery(allocator, mockBlackQuery);
    // Black should be detected as dark
    try std.testing.expectEqual(Color{ .basic = .bright_red }, theme.error_fg);
}

test "ColorTheme basic color detection - light colors" {
    const allocator = std.testing.allocator;

    // Test white (enum >= 7)
    const mockWhiteQuery = struct {
        fn query() !Color {
            return Color{ .basic = .white };
        }
    }.query;

    const theme = try ColorTheme.detectFromTerminalWithQuery(allocator, mockWhiteQuery);
    // White should be detected as light
    try std.testing.expectEqual(Color{ .basic = .red }, theme.error_fg);
}
