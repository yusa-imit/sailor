const std = @import("std");
const theme = @import("theme.zig");
const Theme = theme.Theme;
const Color = @import("style.zig").Color;

/// ThemeLoader provides functionality to load themes from JSON files
pub const ThemeLoader = struct {
    /// Parse a theme from a JSON string
    pub fn fromString(allocator: std.mem.Allocator, json_string: []const u8) !Theme {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_string, .{}) catch {
            return error.InvalidJson;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidJson;

        const obj = root.object;

        // Helper to get required field
        const getRequiredField = struct {
            fn call(object: std.json.ObjectMap, field_name: []const u8) !std.json.Value {
                return object.get(field_name) orelse return error.MissingField;
            }
        }.call;

        // Parse all required fields
        const background = try parseColor(try getRequiredField(obj, "background"));
        const foreground = try parseColor(try getRequiredField(obj, "foreground"));
        const primary = try parseColor(try getRequiredField(obj, "primary"));
        const secondary = try parseColor(try getRequiredField(obj, "secondary"));
        const success = try parseColor(try getRequiredField(obj, "success"));
        const warning = try parseColor(try getRequiredField(obj, "warning"));
        const error_color = try parseColor(try getRequiredField(obj, "error_color"));
        const info = try parseColor(try getRequiredField(obj, "info"));
        const muted = try parseColor(try getRequiredField(obj, "muted"));
        const border = try parseColor(try getRequiredField(obj, "border"));
        const selection_bg = try parseColor(try getRequiredField(obj, "selection_bg"));
        const selection_fg = try parseColor(try getRequiredField(obj, "selection_fg"));

        return Theme{
            .background = background,
            .foreground = foreground,
            .primary = primary,
            .secondary = secondary,
            .success = success,
            .warning = warning,
            .error_color = error_color,
            .info = info,
            .muted = muted,
            .border = border,
            .selection_bg = selection_bg,
            .selection_fg = selection_fg,
        };
    }

    /// Load a theme from a JSON file
    pub fn fromFile(allocator: std.mem.Allocator, file_path: []const u8) !Theme {
        // Check if path exists and is a file
        const stat = std.fs.cwd().statFile(file_path) catch |err| {
            return if (err == error.FileNotFound) error.FileNotFound else err;
        };

        if (stat.kind == .directory) return error.IsDir;

        // Read file contents
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const max_size = 1024 * 1024; // 1MB max
        const contents = try file.readToEndAlloc(allocator, max_size);
        defer allocator.free(contents);

        return try fromString(allocator, contents);
    }
};

/// Parse a color from a JSON value
fn parseColor(value: std.json.Value) !Color {
    if (value != .string) return error.InvalidColor;

    const color_str = value.string;

    // Check for hex color (#RRGGBB)
    if (color_str.len > 0 and color_str[0] == '#') {
        return try parseHexColor(color_str);
    }

    // Try named color
    return parseNamedColor(color_str) orelse error.InvalidColor;
}

/// Parse hex color in #RRGGBB format
fn parseHexColor(hex: []const u8) !Color {
    if (hex.len != 7) return error.InvalidColor;
    if (hex[0] != '#') return error.InvalidColor;

    const r = try parseHexByte(hex[1..3]);
    const g = try parseHexByte(hex[3..5]);
    const b = try parseHexByte(hex[5..7]);

    return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
}

/// Parse two hex characters as a byte
fn parseHexByte(hex: []const u8) !u8 {
    if (hex.len != 2) return error.InvalidColor;

    const high = try parseHexDigit(hex[0]);
    const low = try parseHexDigit(hex[1]);

    return (high << 4) | low;
}

/// Parse a single hex digit
fn parseHexDigit(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidColor,
    };
}

/// Parse a named color
fn parseNamedColor(name: []const u8) ?Color {
    const color_map = std.StaticStringMap(Color).initComptime(.{
        .{ "reset", .reset },
        .{ "black", .black },
        .{ "red", .red },
        .{ "green", .green },
        .{ "yellow", .yellow },
        .{ "blue", .blue },
        .{ "magenta", .magenta },
        .{ "cyan", .cyan },
        .{ "white", .white },
        .{ "bright_black", .bright_black },
        .{ "bright_red", .bright_red },
        .{ "bright_green", .bright_green },
        .{ "bright_yellow", .bright_yellow },
        .{ "bright_blue", .bright_blue },
        .{ "bright_magenta", .bright_magenta },
        .{ "bright_cyan", .bright_cyan },
        .{ "bright_white", .bright_white },
    });

    return color_map.get(name);
}

// Tests
test "parseHexDigit - valid digits" {
    try std.testing.expectEqual(@as(u8, 0), try parseHexDigit('0'));
    try std.testing.expectEqual(@as(u8, 9), try parseHexDigit('9'));
    try std.testing.expectEqual(@as(u8, 10), try parseHexDigit('a'));
    try std.testing.expectEqual(@as(u8, 15), try parseHexDigit('f'));
    try std.testing.expectEqual(@as(u8, 10), try parseHexDigit('A'));
    try std.testing.expectEqual(@as(u8, 15), try parseHexDigit('F'));
}

test "parseHexDigit - invalid characters" {
    try std.testing.expectError(error.InvalidColor, parseHexDigit('g'));
    try std.testing.expectError(error.InvalidColor, parseHexDigit('G'));
    try std.testing.expectError(error.InvalidColor, parseHexDigit('z'));
    try std.testing.expectError(error.InvalidColor, parseHexDigit(' '));
    try std.testing.expectError(error.InvalidColor, parseHexDigit('#'));
}

test "parseHexByte - valid bytes" {
    try std.testing.expectEqual(@as(u8, 0x00), try parseHexByte("00"));
    try std.testing.expectEqual(@as(u8, 0xFF), try parseHexByte("FF"));
    try std.testing.expectEqual(@as(u8, 0xFF), try parseHexByte("ff"));
    try std.testing.expectEqual(@as(u8, 0xAB), try parseHexByte("AB"));
    try std.testing.expectEqual(@as(u8, 0xCD), try parseHexByte("cd"));
    try std.testing.expectEqual(@as(u8, 0x12), try parseHexByte("12"));
}

test "parseHexByte - invalid length" {
    try std.testing.expectError(error.InvalidColor, parseHexByte("0"));
    try std.testing.expectError(error.InvalidColor, parseHexByte("000"));
    try std.testing.expectError(error.InvalidColor, parseHexByte(""));
}

test "parseHexByte - invalid characters" {
    try std.testing.expectError(error.InvalidColor, parseHexByte("GG"));
    try std.testing.expectError(error.InvalidColor, parseHexByte("0G"));
    try std.testing.expectError(error.InvalidColor, parseHexByte("ZZ"));
}

test "parseHexColor - valid colors" {
    const black = try parseHexColor("#000000");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } }, black);

    const white = try parseHexColor("#FFFFFF");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }, white);

    const red = try parseHexColor("#FF0000");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, red);

    const green = try parseHexColor("#00FF00");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0, .g = 255, .b = 0 } }, green);

    const blue = try parseHexColor("#0000FF");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0, .g = 0, .b = 255 } }, blue);

    const custom = try parseHexColor("#AB12CD");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 171, .g = 18, .b = 205 } }, custom);
}

test "parseHexColor - case insensitive" {
    const lower = try parseHexColor("#abcdef");
    const upper = try parseHexColor("#ABCDEF");
    const mixed = try parseHexColor("#AbCdEf");

    try std.testing.expectEqual(lower, upper);
    try std.testing.expectEqual(lower, mixed);
}

test "parseHexColor - invalid format" {
    try std.testing.expectError(error.InvalidColor, parseHexColor("000000")); // missing #
    try std.testing.expectError(error.InvalidColor, parseHexColor("#00000")); // too short
    try std.testing.expectError(error.InvalidColor, parseHexColor("#0000000")); // too long
    try std.testing.expectError(error.InvalidColor, parseHexColor("#GGGGGG")); // invalid chars
    try std.testing.expectError(error.InvalidColor, parseHexColor("")); // empty
    try std.testing.expectError(error.InvalidColor, parseHexColor("#")); // just hash
}

test "parseNamedColor - valid names" {
    try std.testing.expectEqual(Color.reset, parseNamedColor("reset").?);
    try std.testing.expectEqual(Color.black, parseNamedColor("black").?);
    try std.testing.expectEqual(Color.red, parseNamedColor("red").?);
    try std.testing.expectEqual(Color.green, parseNamedColor("green").?);
    try std.testing.expectEqual(Color.yellow, parseNamedColor("yellow").?);
    try std.testing.expectEqual(Color.blue, parseNamedColor("blue").?);
    try std.testing.expectEqual(Color.magenta, parseNamedColor("magenta").?);
    try std.testing.expectEqual(Color.cyan, parseNamedColor("cyan").?);
    try std.testing.expectEqual(Color.white, parseNamedColor("white").?);
    try std.testing.expectEqual(Color.bright_black, parseNamedColor("bright_black").?);
    try std.testing.expectEqual(Color.bright_red, parseNamedColor("bright_red").?);
    try std.testing.expectEqual(Color.bright_green, parseNamedColor("bright_green").?);
    try std.testing.expectEqual(Color.bright_yellow, parseNamedColor("bright_yellow").?);
    try std.testing.expectEqual(Color.bright_blue, parseNamedColor("bright_blue").?);
    try std.testing.expectEqual(Color.bright_magenta, parseNamedColor("bright_magenta").?);
    try std.testing.expectEqual(Color.bright_cyan, parseNamedColor("bright_cyan").?);
    try std.testing.expectEqual(Color.bright_white, parseNamedColor("bright_white").?);
}

test "parseNamedColor - invalid names" {
    try std.testing.expectEqual(@as(?Color, null), parseNamedColor("invalid"));
    try std.testing.expectEqual(@as(?Color, null), parseNamedColor(""));
    try std.testing.expectEqual(@as(?Color, null), parseNamedColor("Red")); // case sensitive
    try std.testing.expectEqual(@as(?Color, null), parseNamedColor("BLUE"));
    try std.testing.expectEqual(@as(?Color, null), parseNamedColor("gray"));
}

test "parseColor - hex colors" {
    const value_black = std.json.Value{ .string = "#000000" };
    const black = try parseColor(value_black);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } }, black);

    const value_white = std.json.Value{ .string = "#FFFFFF" };
    const white = try parseColor(value_white);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }, white);
}

test "parseColor - named colors" {
    const value_red = std.json.Value{ .string = "red" };
    const red = try parseColor(value_red);
    try std.testing.expectEqual(Color.red, red);

    const value_blue = std.json.Value{ .string = "blue" };
    const blue = try parseColor(value_blue);
    try std.testing.expectEqual(Color.blue, blue);
}

test "parseColor - invalid types" {
    const value_number = std.json.Value{ .integer = 42 };
    try std.testing.expectError(error.InvalidColor, parseColor(value_number));

    const value_bool = std.json.Value{ .bool = true };
    try std.testing.expectError(error.InvalidColor, parseColor(value_bool));

    const value_null = std.json.Value{ .null = {} };
    try std.testing.expectError(error.InvalidColor, parseColor(value_null));
}

test "parseColor - invalid color strings" {
    const value_invalid = std.json.Value{ .string = "not_a_color" };
    try std.testing.expectError(error.InvalidColor, parseColor(value_invalid));

    const value_bad_hex = std.json.Value{ .string = "#GGGGGG" };
    try std.testing.expectError(error.InvalidColor, parseColor(value_bad_hex));
}

test "ThemeLoader.fromString - valid theme" {
    const json =
        \\{
        \\  "background": "#1e1e1e",
        \\  "foreground": "#d4d4d4",
        \\  "primary": "#007acc",
        \\  "secondary": "#6a9955",
        \\  "success": "#4ec9b0",
        \\  "warning": "#ce9178",
        \\  "error_color": "#f48771",
        \\  "info": "#9cdcfe",
        \\  "muted": "#808080",
        \\  "border": "#3c3c3c",
        \\  "selection_bg": "#264f78",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const t = try ThemeLoader.fromString(std.testing.allocator, json);

    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0x1e, .g = 0x1e, .b = 0x1e } }, t.background);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0xd4, .g = 0xd4, .b = 0xd4 } }, t.foreground);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0x00, .g = 0x7a, .b = 0xcc } }, t.primary);
}

test "ThemeLoader.fromString - named colors" {
    const json =
        \\{
        \\  "background": "black",
        \\  "foreground": "white",
        \\  "primary": "blue",
        \\  "secondary": "green",
        \\  "success": "bright_green",
        \\  "warning": "yellow",
        \\  "error_color": "red",
        \\  "info": "cyan",
        \\  "muted": "bright_black",
        \\  "border": "white",
        \\  "selection_bg": "blue",
        \\  "selection_fg": "white"
        \\}
    ;

    const t = try ThemeLoader.fromString(std.testing.allocator, json);

    try std.testing.expectEqual(Color.black, t.background);
    try std.testing.expectEqual(Color.white, t.foreground);
    try std.testing.expectEqual(Color.blue, t.primary);
    try std.testing.expectEqual(Color.green, t.secondary);
}

test "ThemeLoader.fromString - mixed colors" {
    const json =
        \\{
        \\  "background": "black",
        \\  "foreground": "#FFFFFF",
        \\  "primary": "blue",
        \\  "secondary": "#00FF00",
        \\  "success": "bright_green",
        \\  "warning": "#FFFF00",
        \\  "error_color": "red",
        \\  "info": "#00FFFF",
        \\  "muted": "bright_black",
        \\  "border": "#808080",
        \\  "selection_bg": "blue",
        \\  "selection_fg": "white"
        \\}
    ;

    const t = try ThemeLoader.fromString(std.testing.allocator, json);

    try std.testing.expectEqual(Color.black, t.background);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }, t.foreground);
}

test "ThemeLoader.fromString - invalid JSON" {
    try std.testing.expectError(error.InvalidJson, ThemeLoader.fromString(std.testing.allocator, "not json"));
    try std.testing.expectError(error.InvalidJson, ThemeLoader.fromString(std.testing.allocator, "{incomplete"));
    try std.testing.expectError(error.InvalidJson, ThemeLoader.fromString(std.testing.allocator, ""));
}

test "ThemeLoader.fromString - not an object" {
    try std.testing.expectError(error.InvalidJson, ThemeLoader.fromString(std.testing.allocator, "[]"));
    try std.testing.expectError(error.InvalidJson, ThemeLoader.fromString(std.testing.allocator, "\"string\""));
    try std.testing.expectError(error.InvalidJson, ThemeLoader.fromString(std.testing.allocator, "42"));
}

test "ThemeLoader.fromString - missing required field" {
    const json =
        \\{
        \\  "background": "black",
        \\  "foreground": "white"
        \\}
    ;

    try std.testing.expectError(error.MissingField, ThemeLoader.fromString(std.testing.allocator, json));
}

test "ThemeLoader.fromString - invalid color value" {
    const json =
        \\{
        \\  "background": "black",
        \\  "foreground": "white",
        \\  "primary": "invalid_color",
        \\  "secondary": "green",
        \\  "success": "bright_green",
        \\  "warning": "yellow",
        \\  "error_color": "red",
        \\  "info": "cyan",
        \\  "muted": "bright_black",
        \\  "border": "white",
        \\  "selection_bg": "blue",
        \\  "selection_fg": "white"
        \\}
    ;

    try std.testing.expectError(error.InvalidColor, ThemeLoader.fromString(std.testing.allocator, json));
}

test "ThemeLoader.fromFile - nonexistent file" {
    try std.testing.expectError(error.FileNotFound, ThemeLoader.fromFile(std.testing.allocator, "/nonexistent/theme.json"));
}
