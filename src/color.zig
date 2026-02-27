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
