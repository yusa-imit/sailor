const std = @import("std");
const sailor = @import("sailor");
const Theme = sailor.tui.Theme;
const Color = sailor.tui.Color;
const Style = sailor.tui.Style;

// This module tests the theme plugin system that loads themes from JSON files.
// These tests are written BEFORE implementation (TDD Red phase).
// All tests will FAIL until ThemeLoader is implemented.

// NOTE: ThemeLoader does not exist yet — these tests define the expected API

// ============================================================================
// Test: Parse complete theme from JSON string
// ============================================================================

test "ThemeLoader - parse complete theme from JSON string" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "#282a36",
        \\  "foreground": "#f8f8f2",
        \\  "primary": "#bd93f9",
        \\  "secondary": "#8be9fd",
        \\  "success": "#50fa7b",
        \\  "warning": "#f1fa8c",
        \\  "error_color": "#ff5555",
        \\  "info": "#8be9fd",
        \\  "muted": "#6272a4",
        \\  "border": "#44475a",
        \\  "selection_bg": "#44475a",
        \\  "selection_fg": "#f8f8f2"
        \\}
    ;

    // Expected API: sailor.tui.ThemeLoader.fromString(allocator, json_string)
    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    // Verify parsed theme matches Dracula color scheme
    switch (theme.background) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0x28), c.r);
            try std.testing.expectEqual(@as(u8, 0x2a), c.g);
            try std.testing.expectEqual(@as(u8, 0x36), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    switch (theme.primary) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0xbd), c.r);
            try std.testing.expectEqual(@as(u8, 0x93), c.g);
            try std.testing.expectEqual(@as(u8, 0xf9), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

// ============================================================================
// Test: Hex color parsing (various formats)
// ============================================================================

test "ThemeLoader - parse hex colors with #RRGGBB format" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "#FF0000",
        \\  "foreground": "#00FF00",
        \\  "primary": "#0000FF",
        \\  "secondary": "#FFFF00",
        \\  "success": "#00FFFF",
        \\  "warning": "#FF00FF",
        \\  "error_color": "#FFFFFF",
        \\  "info": "#000000",
        \\  "muted": "#808080",
        \\  "border": "#C0C0C0",
        \\  "selection_bg": "#123456",
        \\  "selection_fg": "#ABCDEF"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    // Pure red
    switch (theme.background) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 255), c.r);
            try std.testing.expectEqual(@as(u8, 0), c.g);
            try std.testing.expectEqual(@as(u8, 0), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    // Pure green
    switch (theme.foreground) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0), c.r);
            try std.testing.expectEqual(@as(u8, 255), c.g);
            try std.testing.expectEqual(@as(u8, 0), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    // Mixed color #123456
    switch (theme.selection_bg) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0x12), c.r);
            try std.testing.expectEqual(@as(u8, 0x34), c.g);
            try std.testing.expectEqual(@as(u8, 0x56), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

test "ThemeLoader - parse hex colors case insensitive" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "#ff0000",
        \\  "foreground": "#FF0000",
        \\  "primary": "#Ff0000",
        \\  "secondary": "#fF0000",
        \\  "success": "#00ff00",
        \\  "warning": "#00FF00",
        \\  "error_color": "#0000ff",
        \\  "info": "#0000FF",
        \\  "muted": "#abcdef",
        \\  "border": "#ABCDEF",
        \\  "selection_bg": "#123ABC",
        \\  "selection_fg": "#abc123"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    // All reds should be the same
    for ([_]Color{ theme.background, theme.foreground, theme.primary, theme.secondary }) |color| {
        switch (color) {
            .rgb => |c| {
                try std.testing.expectEqual(@as(u8, 255), c.r);
                try std.testing.expectEqual(@as(u8, 0), c.g);
                try std.testing.expectEqual(@as(u8, 0), c.b);
            },
            else => return error.ExpectedRgbColor,
        }
    }
}

// ============================================================================
// Test: Named color parsing
// ============================================================================

test "ThemeLoader - parse named colors" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "black",
        \\  "foreground": "white",
        \\  "primary": "blue",
        \\  "secondary": "cyan",
        \\  "success": "green",
        \\  "warning": "yellow",
        \\  "error_color": "red",
        \\  "info": "bright_blue",
        \\  "muted": "bright_black",
        \\  "border": "magenta",
        \\  "selection_bg": "bright_cyan",
        \\  "selection_fg": "bright_white"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    // Verify named colors are parsed correctly
    try std.testing.expectEqual(Color.black, theme.background);
    try std.testing.expectEqual(Color.white, theme.foreground);
    try std.testing.expectEqual(Color.blue, theme.primary);
    try std.testing.expectEqual(Color.cyan, theme.secondary);
    try std.testing.expectEqual(Color.green, theme.success);
    try std.testing.expectEqual(Color.yellow, theme.warning);
    try std.testing.expectEqual(Color.red, theme.error_color);
    try std.testing.expectEqual(Color.bright_blue, theme.info);
    try std.testing.expectEqual(Color.bright_black, theme.muted);
    try std.testing.expectEqual(Color.magenta, theme.border);
    try std.testing.expectEqual(Color.bright_cyan, theme.selection_bg);
    try std.testing.expectEqual(Color.bright_white, theme.selection_fg);
}

test "ThemeLoader - parse reset color" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "reset",
        \\  "foreground": "reset",
        \\  "primary": "blue",
        \\  "secondary": "cyan",
        \\  "success": "green",
        \\  "warning": "yellow",
        \\  "error_color": "red",
        \\  "info": "blue",
        \\  "muted": "bright_black",
        \\  "border": "white",
        \\  "selection_bg": "blue",
        \\  "selection_fg": "black"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    try std.testing.expectEqual(Color.reset, theme.background);
    try std.testing.expectEqual(Color.reset, theme.foreground);
}

// ============================================================================
// Test: Mixed named and hex colors
// ============================================================================

test "ThemeLoader - parse mixed named and hex colors" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "black",
        \\  "foreground": "#ffffff",
        \\  "primary": "blue",
        \\  "secondary": "#00ffff",
        \\  "success": "green",
        \\  "warning": "#ffff00",
        \\  "error_color": "red",
        \\  "info": "#0000ff",
        \\  "muted": "bright_black",
        \\  "border": "#808080",
        \\  "selection_bg": "bright_blue",
        \\  "selection_fg": "#000000"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    // Named color
    try std.testing.expectEqual(Color.black, theme.background);

    // Hex color
    switch (theme.foreground) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 255), c.r);
            try std.testing.expectEqual(@as(u8, 255), c.g);
            try std.testing.expectEqual(@as(u8, 255), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    // Named color
    try std.testing.expectEqual(Color.blue, theme.primary);

    // Hex color
    switch (theme.secondary) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0), c.r);
            try std.testing.expectEqual(@as(u8, 255), c.g);
            try std.testing.expectEqual(@as(u8, 255), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

// ============================================================================
// Test: Load theme from file
// ============================================================================

test "ThemeLoader - load theme from file path" {
    const allocator = std.testing.allocator;

    // Create temporary file with theme JSON
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const theme_json =
        \\{
        \\  "background": "#1e1e1e",
        \\  "foreground": "#d4d4d4",
        \\  "primary": "#4ec9b0",
        \\  "secondary": "#569cd6",
        \\  "success": "#6a9955",
        \\  "warning": "#dcdcaa",
        \\  "error_color": "#f48771",
        \\  "info": "#569cd6",
        \\  "muted": "#858585",
        \\  "border": "#3e3e3e",
        \\  "selection_bg": "#264f78",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const file = try tmp_dir.dir.createFile("theme.json", .{});
    defer file.close();
    try file.writeAll(theme_json);

    // Get absolute path to temp file
    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_dir_path);

    const theme_path = try std.fs.path.join(allocator, &.{ tmp_dir_path, "theme.json" });
    defer allocator.free(theme_path);

    // Expected API: sailor.tui.ThemeLoader.fromFile(allocator, file_path)
    const theme = try sailor.tui.ThemeLoader.fromFile(allocator, theme_path);

    // Verify theme was loaded correctly
    switch (theme.background) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0x1e), c.r);
            try std.testing.expectEqual(@as(u8, 0x1e), c.g);
            try std.testing.expectEqual(@as(u8, 0x1e), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    switch (theme.primary) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0x4e), c.r);
            try std.testing.expectEqual(@as(u8, 0xc9), c.g);
            try std.testing.expectEqual(@as(u8, 0xb0), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

// ============================================================================
// Test: Error cases - invalid JSON
// ============================================================================

test "ThemeLoader - error on invalid JSON syntax" {
    const allocator = std.testing.allocator;

    const invalid_json = "{ this is not valid json }";

    const result = sailor.tui.ThemeLoader.fromString(allocator, invalid_json);
    try std.testing.expectError(error.InvalidJson, result);
}

test "ThemeLoader - error on malformed JSON" {
    const allocator = std.testing.allocator;

    const malformed_json =
        \\{
        \\  "background": "#ff0000",
        \\  "foreground": "#00ff00"
        \\  "primary": "#0000ff"
        \\}
    ; // Missing comma after foreground

    const result = sailor.tui.ThemeLoader.fromString(allocator, malformed_json);
    try std.testing.expectError(error.InvalidJson, result);
}

// ============================================================================
// Test: Error cases - missing required fields
// ============================================================================

test "ThemeLoader - error on missing background field" {
    const allocator = std.testing.allocator;

    const incomplete_json =
        \\{
        \\  "foreground": "#ffffff",
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, incomplete_json);
    try std.testing.expectError(error.MissingField, result);
}

test "ThemeLoader - error on missing multiple fields" {
    const allocator = std.testing.allocator;

    const incomplete_json =
        \\{
        \\  "background": "#000000",
        \\  "foreground": "#ffffff",
        \\  "primary": "#0000ff"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, incomplete_json);
    try std.testing.expectError(error.MissingField, result);
}

test "ThemeLoader - all 12 fields are required" {
    const allocator = std.testing.allocator;

    // Test missing error_color field
    const missing_error_color =
        \\{
        \\  "background": "#ffffff",
        \\  "foreground": "#ffffff",
        \\  "primary": "#ffffff",
        \\  "secondary": "#ffffff",
        \\  "success": "#ffffff",
        \\  "warning": "#ffffff",
        \\  "info": "#ffffff",
        \\  "muted": "#ffffff",
        \\  "border": "#ffffff",
        \\  "selection_bg": "#ffffff",
        \\  "selection_fg": "#ffffff"
        \\}
    ;
    const result = sailor.tui.ThemeLoader.fromString(allocator, missing_error_color);
    try std.testing.expectError(error.MissingField, result);
}

// ============================================================================
// Test: Error cases - invalid color values
// ============================================================================

test "ThemeLoader - error on invalid hex color format" {
    const allocator = std.testing.allocator;

    const invalid_hex =
        \\{
        \\  "background": "#ZZZ",
        \\  "foreground": "#ffffff",
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, invalid_hex);
    try std.testing.expectError(error.InvalidColor, result);
}

test "ThemeLoader - error on wrong hex length" {
    const allocator = std.testing.allocator;

    const short_hex =
        \\{
        \\  "background": "#fff",
        \\  "foreground": "#ffffff",
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, short_hex);
    try std.testing.expectError(error.InvalidColor, result);
}

test "ThemeLoader - error on unknown named color" {
    const allocator = std.testing.allocator;

    const unknown_color =
        \\{
        \\  "background": "purple_rainbow",
        \\  "foreground": "white",
        \\  "primary": "blue",
        \\  "secondary": "cyan",
        \\  "success": "green",
        \\  "warning": "yellow",
        \\  "error_color": "red",
        \\  "info": "blue",
        \\  "muted": "bright_black",
        \\  "border": "white",
        \\  "selection_bg": "blue",
        \\  "selection_fg": "black"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, unknown_color);
    try std.testing.expectError(error.InvalidColor, result);
}

test "ThemeLoader - error on hex without # prefix" {
    const allocator = std.testing.allocator;

    const no_hash =
        \\{
        \\  "background": "ff0000",
        \\  "foreground": "#ffffff",
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, no_hash);
    try std.testing.expectError(error.InvalidColor, result);
}

// ============================================================================
// Test: Error cases - file not found
// ============================================================================

test "ThemeLoader - error on file not found" {
    const allocator = std.testing.allocator;

    const nonexistent_path = "/nonexistent/path/to/theme.json";

    const result = sailor.tui.ThemeLoader.fromFile(allocator, nonexistent_path);
    try std.testing.expectError(error.FileNotFound, result);
}

test "ThemeLoader - error on directory instead of file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_dir_path);

    const result = sailor.tui.ThemeLoader.fromFile(allocator, tmp_dir_path);
    try std.testing.expectError(error.IsDir, result);
}

// ============================================================================
// Test: Loaded theme works with existing style helpers
// ============================================================================

test "ThemeLoader - loaded theme works with style helpers" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "#000000",
        \\  "foreground": "#ffffff",
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    // Test that all style helper methods work
    const bg_style = theme.bg();
    try std.testing.expect(bg_style.bg != null);
    try std.testing.expect(bg_style.fg != null);

    const primary_style = theme.primary_style();
    try std.testing.expect(primary_style.fg != null);
    try std.testing.expect(primary_style.bold);

    const error_style = theme.error_style();
    try std.testing.expect(error_style.fg != null);
    try std.testing.expect(error_style.bold);

    const selection_style = theme.selection_style();
    try std.testing.expect(selection_style.fg != null);
    try std.testing.expect(selection_style.bg != null);

    const muted_style = theme.muted_style();
    try std.testing.expect(muted_style.fg != null);
    try std.testing.expect(muted_style.dim);
}

test "ThemeLoader - loaded theme can render styled spans" {
    const allocator = std.testing.allocator;

    const json_theme =
        \\{
        \\  "background": "black",
        \\  "foreground": "white",
        \\  "primary": "blue",
        \\  "secondary": "cyan",
        \\  "success": "green",
        \\  "warning": "yellow",
        \\  "error_color": "red",
        \\  "info": "bright_blue",
        \\  "muted": "bright_black",
        \\  "border": "white",
        \\  "selection_bg": "bright_blue",
        \\  "selection_fg": "black"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_theme);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Render using theme styles
    const span = sailor.tui.Span.styled("Error!", theme.error_style());
    try span.render(writer);

    const output = fbs.getWritten();
    // Should contain ANSI escape codes for red + bold
    try std.testing.expect(output.len > "Error!".len);
    try std.testing.expect(std.mem.indexOf(u8, output, "Error!") != null);
}

// ============================================================================
// Test: JSON with extra fields (should be ignored)
// ============================================================================

test "ThemeLoader - ignore unknown fields in JSON" {
    const allocator = std.testing.allocator;

    const json_with_extra =
        \\{
        \\  "background": "#000000",
        \\  "foreground": "#ffffff",
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff",
        \\  "custom_field": "#123456",
        \\  "author": "Test User",
        \\  "version": "1.0"
        \\}
    ;

    const theme = try sailor.tui.ThemeLoader.fromString(allocator, json_with_extra);

    // Should successfully parse despite extra fields
    switch (theme.background) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 0), c.r);
            try std.testing.expectEqual(@as(u8, 0), c.g);
            try std.testing.expectEqual(@as(u8, 0), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

// ============================================================================
// Test: Empty or whitespace-only file
// ============================================================================

test "ThemeLoader - error on empty JSON" {
    const allocator = std.testing.allocator;

    const empty_json = "";

    const result = sailor.tui.ThemeLoader.fromString(allocator, empty_json);
    try std.testing.expectError(error.InvalidJson, result);
}

test "ThemeLoader - error on whitespace-only JSON" {
    const allocator = std.testing.allocator;

    const whitespace_json = "   \n\t  ";

    const result = sailor.tui.ThemeLoader.fromString(allocator, whitespace_json);
    try std.testing.expectError(error.InvalidJson, result);
}

// ============================================================================
// Test: Non-string color values
// ============================================================================

test "ThemeLoader - error on numeric color values" {
    const allocator = std.testing.allocator;

    const numeric_colors =
        \\{
        \\  "background": 0,
        \\  "foreground": 255,
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, numeric_colors);
    try std.testing.expectError(error.InvalidColor, result);
}

test "ThemeLoader - error on boolean color values" {
    const allocator = std.testing.allocator;

    const bool_colors =
        \\{
        \\  "background": true,
        \\  "foreground": false,
        \\  "primary": "#0000ff",
        \\  "secondary": "#00ffff",
        \\  "success": "#00ff00",
        \\  "warning": "#ffff00",
        \\  "error_color": "#ff0000",
        \\  "info": "#0000ff",
        \\  "muted": "#808080",
        \\  "border": "#c0c0c0",
        \\  "selection_bg": "#000080",
        \\  "selection_fg": "#ffffff"
        \\}
    ;

    const result = sailor.tui.ThemeLoader.fromString(allocator, bool_colors);
    try std.testing.expectError(error.InvalidColor, result);
}
