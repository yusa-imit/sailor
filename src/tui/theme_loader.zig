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
