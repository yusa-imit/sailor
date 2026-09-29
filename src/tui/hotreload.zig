//! Hot-reload system that watches a theme JSON file and reloads it on change.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const theme_mod = @import("theme.zig");
const Theme = theme_mod.Theme;
const Color = @import("style.zig").Color;

/// Hot-reload system for watching and applying theme file changes
pub const ThemeWatcher = struct {
    /// Path to theme file being watched
    path: []const u8,
    /// Last modification time
    last_mtime_ns: i128,
    /// Current loaded theme
    current: Theme,
    /// Check interval in nanoseconds (default: 500ms)
    check_interval_ns: u64,
    /// Last check timestamp
    last_check_ns: u64,
    allocator: Allocator,

    /// Initialize theme watcher
    pub fn init(
        allocator: Allocator,
        io: std.Io,
        path: []const u8,
        check_interval_ms: u32,
    ) !ThemeWatcher {
        const path_copy = try allocator.dupe(u8, path);
        errdefer allocator.free(path_copy);

        // Load initial theme
        const initial_theme = loadThemeFromFile(allocator, io, path) catch theme_mod.default_dark;
        const mtime = getFileModTime(io, path) catch 0;

        return .{
            .path = path_copy,
            .last_mtime_ns = mtime,
            .current = initial_theme,
            .check_interval_ns = @as(u64, check_interval_ms) * 1_000_000,
            .last_check_ns = 0,
            .allocator = allocator,
        };
    }

    /// Free watcher resources
    pub fn deinit(self: *ThemeWatcher) void {
        self.allocator.free(self.path);
    }

    /// Check for file changes and reload if modified
    /// Returns true if theme was reloaded
    pub fn check(self: *ThemeWatcher, io: std.Io) bool {
        const now = std.Io.Clock.awake.now(io).toNanoseconds();

        // Throttle checks to avoid excessive file system operations
        if (self.last_check_ns > 0) {
            const elapsed = @as(u64, @intCast(now)) - self.last_check_ns;
            if (elapsed < self.check_interval_ns) return false;
        }

        self.last_check_ns = @intCast(now);

        // Check modification time
        const mtime = getFileModTime(io, self.path) catch return false;

        if (mtime > self.last_mtime_ns) {
            // File modified, reload theme
            if (loadThemeFromFile(self.allocator, io, self.path)) |new_theme| {
                self.current = new_theme;
                self.last_mtime_ns = mtime;
                return true;
            } else |_| {
                // Failed to load, keep current theme
                return false;
            }
        }

        return false;
    }

    /// Get current theme
    pub fn theme(self: ThemeWatcher) Theme {
        return self.current;
    }

    /// Manually reload theme from file
    pub fn reload(self: *ThemeWatcher, io: std.Io) !void {
        const new_theme = try loadThemeFromFile(self.allocator, io, self.path);
        self.current = new_theme;
        const mtime = try getFileModTime(io, self.path);
        self.last_mtime_ns = mtime;
    }
};

/// Get file modification time in nanoseconds
fn getFileModTime(io: std.Io, path: []const u8) !i128 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    return stat.mtime.toNanoseconds();
}

/// Load theme from JSON file
fn loadThemeFromFile(allocator: Allocator, io: std.Io, path: []const u8) !Theme {
    const max_size = 1024 * 1024; // 1MB max
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_size));
    defer allocator.free(content);

    return try parseThemeJson(content);
}

/// Parse theme from JSON string
fn parseThemeJson(json_str: []const u8) !Theme {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, json_str, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    var theme = Theme{};

    if (root.get("background")) |v| theme.background = try parseColor(v.string);
    if (root.get("foreground")) |v| theme.foreground = try parseColor(v.string);
    if (root.get("primary")) |v| theme.primary = try parseColor(v.string);
    if (root.get("secondary")) |v| theme.secondary = try parseColor(v.string);
    if (root.get("success")) |v| theme.success = try parseColor(v.string);
    if (root.get("warning")) |v| theme.warning = try parseColor(v.string);
    if (root.get("error")) |v| theme.error_color = try parseColor(v.string);
    if (root.get("info")) |v| theme.info = try parseColor(v.string);
    if (root.get("muted")) |v| theme.muted = try parseColor(v.string);
    if (root.get("border")) |v| theme.border = try parseColor(v.string);
    if (root.get("selection_bg")) |v| theme.selection_bg = try parseColor(v.string);
    if (root.get("selection_fg")) |v| theme.selection_fg = try parseColor(v.string);

    return theme;
}

/// Parse color from string (name or hex)
fn parseColor(str: []const u8) !Color {
    // Named colors
    if (std.mem.eql(u8, str, "black")) return .black;
    if (std.mem.eql(u8, str, "red")) return .red;
    if (std.mem.eql(u8, str, "green")) return .green;
    if (std.mem.eql(u8, str, "yellow")) return .yellow;
    if (std.mem.eql(u8, str, "blue")) return .blue;
    if (std.mem.eql(u8, str, "magenta")) return .magenta;
    if (std.mem.eql(u8, str, "cyan")) return .cyan;
    if (std.mem.eql(u8, str, "white")) return .white;
    if (std.mem.eql(u8, str, "bright_black")) return .bright_black;
    if (std.mem.eql(u8, str, "bright_red")) return .bright_red;
    if (std.mem.eql(u8, str, "bright_green")) return .bright_green;
    if (std.mem.eql(u8, str, "bright_yellow")) return .bright_yellow;
    if (std.mem.eql(u8, str, "bright_blue")) return .bright_blue;
    if (std.mem.eql(u8, str, "bright_magenta")) return .bright_magenta;
    if (std.mem.eql(u8, str, "bright_cyan")) return .bright_cyan;
    if (std.mem.eql(u8, str, "bright_white")) return .bright_white;
    if (std.mem.eql(u8, str, "reset")) return .reset;

    // Hex color (#RRGGBB)
    if (str.len == 7 and str[0] == '#') {
        const r = try std.fmt.parseInt(u8, str[1..3], 16);
        const g = try std.fmt.parseInt(u8, str[3..5], 16);
        const b = try std.fmt.parseInt(u8, str[5..7], 16);
        return .{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    // Indexed color (0-255)
    if (std.fmt.parseInt(u8, str, 10)) |idx| {
        return .{ .indexed = idx };
    } else |_| {}

    return error.InvalidColor;
}

test "ThemeWatcher getFileModTime" {
    // Create temporary file
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_theme.json";
    const io = std.testing.io;
    var file = try tmp.dir.createFile(io, path, .{});
    file.close(io);

    // Get absolute path for testing
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_len = try tmp.dir.realPathFile(io, path, &buf);
    const abs_path = buf[0..abs_len];

    const mtime = try getFileModTime(io, abs_path);
    try std.testing.expect(mtime > 0);
}

test "ThemeWatcher parseColor named" {
    const red = try parseColor("red");
    try std.testing.expectEqual(Color.red, red);

    const bright_blue = try parseColor("bright_blue");
    try std.testing.expectEqual(Color.bright_blue, bright_blue);
}

test "ThemeWatcher parseColor hex" {
    const color = try parseColor("#ff0000");
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, color);
}

test "ThemeWatcher parseColor indexed" {
    const color = try parseColor("42");
    try std.testing.expectEqual(Color{ .indexed = 42 }, color);
}

test "ThemeWatcher parseColor invalid" {
    const result = parseColor("invalid");
    try std.testing.expectError(error.InvalidColor, result);
}

test "ThemeWatcher parseThemeJson" {
    const json =
        \\{
        \\  "primary": "blue",
        \\  "secondary": "#00ff00",
        \\  "error": "red"
        \\}
    ;

    const theme = try parseThemeJson(json);
    try std.testing.expectEqual(Color.blue, theme.primary);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0, .g = 255, .b = 0 } }, theme.secondary);
    try std.testing.expectEqual(Color.red, theme.error_color);
}

test "ThemeWatcher loadThemeFromFile" {
    // Create temporary theme file
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_theme.json";
    const io = std.testing.io;
    try tmp.dir.writeFile(io, .{ .sub_path = path, .data =
        \\{
        \\  "primary": "green",
        \\  "background": "#000000"
        \\}
    });

    // Get absolute path
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_len = try tmp.dir.realPathFile(io, path, &buf);
    const abs_path = buf[0..abs_len];

    const theme = try loadThemeFromFile(std.testing.allocator, io, abs_path);
    try std.testing.expectEqual(Color.green, theme.primary);
    try std.testing.expectEqual(Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } }, theme.background);
}

test "ThemeWatcher init and deinit" {
    // Create temporary theme file
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_theme.json";
    const io = std.testing.io;
    try tmp.dir.writeFile(io, .{ .sub_path = path, .data =
        \\{
        \\  "primary": "cyan"
        \\}
    });

    // Get absolute path
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_len = try tmp.dir.realPathFile(io, path, &buf);
    const abs_path = buf[0..abs_len];

    var watcher = try ThemeWatcher.init(std.testing.allocator, io, abs_path, 100);
    defer watcher.deinit();

    try std.testing.expectEqual(Color.cyan, watcher.theme().primary);
}

test "ThemeWatcher reload" {
    // Create temporary theme file
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_theme.json";
    const io = std.testing.io;
    try tmp.dir.writeFile(io, .{ .sub_path = path, .data =
        \\{
        \\  "primary": "red"
        \\}
    });

    // Get absolute path
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_len = try tmp.dir.realPathFile(io, path, &buf);
    const abs_path = buf[0..abs_len];

    var watcher = try ThemeWatcher.init(std.testing.allocator, io, abs_path, 100);
    defer watcher.deinit();

    try std.testing.expectEqual(Color.red, watcher.theme().primary);

    // Modify file
    try tmp.dir.writeFile(io, .{ .sub_path = path, .data =
        \\{
        \\  "primary": "blue"
        \\}
    });

    // Manually reload
    try watcher.reload(io);
    try std.testing.expectEqual(Color.blue, watcher.theme().primary);
}
