//! Terminfo/Termcap Database Tests
//!
//! Tests for terminal capability database parsing and querying.
//! All tests use mocked file I/O to avoid depending on system terminfo files.

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const sailor = @import("sailor");

// Mock terminfo binary data generator
const MockTerminfo = struct {
    const Header = struct {
        magic: u16, // 0o432 (legacy) or 0o542 (extended)
        names_size: u16,
        bool_count: u16,
        num_count: u16,
        str_count: u16,
        str_table_size: u16,
    };

    /// Generate minimal valid terminfo binary
    fn generateMinimal(allocator: std.mem.Allocator) ![]u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 32);
        errdefer buf.deinit(allocator);

        // Header (magic number for legacy format)
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 10))); // names_size: "xterm" + null
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size

        // Terminal names section (null-separated, double-null terminated)
        try buf.appendSlice(allocator, "xterm\x00\x00\x00\x00\x00");

        return buf.toOwnedSlice(allocator);
    }

    /// Generate terminfo with boolean capabilities
    fn generateWithBooleans(allocator: std.mem.Allocator) ![]u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 32);
        errdefer buf.deinit(allocator);

        // Header
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 12))); // names_size
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 4))); // bool_count: 4 booleans
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size

        // Terminal names
        try buf.appendSlice(allocator, "xterm-256\x00\x00");

        // Boolean section (1 byte each: 0=absent, 1=present)
        try buf.append(allocator, 1); // auto_left_margin (am)
        try buf.append(allocator, 1); // auto_right_margin (am)
        try buf.append(allocator, 0); // beehive_glitch (xsb)
        try buf.append(allocator, 1); // back_color_erase (bce)

        return buf.toOwnedSlice(allocator);
    }

    /// Generate terminfo with numeric capabilities
    fn generateWithNumbers(allocator: std.mem.Allocator) ![]u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 64);
        errdefer buf.deinit(allocator);

        // Header
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 18))); // names_size
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 3))); // num_count: 3 numbers
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size

        // Terminal names
        try buf.appendSlice(allocator, "xterm-256color\x00\x00\x00\x00");

        // Numeric section (2 bytes each, little-endian, -1 means absent)
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 80))); // columns
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 24))); // lines
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 256))); // colors

        return buf.toOwnedSlice(allocator);
    }

    /// Generate terminfo with string capabilities
    fn generateWithStrings(allocator: std.mem.Allocator) ![]u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 64);
        errdefer buf.deinit(allocator);

        // Header
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 2))); // str_count: 2 strings
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 12))); // str_table_size

        // Terminal names
        try buf.appendSlice(allocator, "xterm\x00");

        // String offsets section (2 bytes each, offset into string table, -1 means absent)
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 0))); // clear_screen offset
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 9))); // cursor_home offset

        // String table (null-terminated strings)
        try buf.appendSlice(allocator, "\x1b[H\x1b[2J\x00"); // clear_screen: ESC[H ESC[2J
        try buf.appendSlice(allocator, "\x1b[H\x00"); // cursor_home: ESC[H

        return buf.toOwnedSlice(allocator);
    }

    /// Generate complete terminfo with all capability types
    fn generateComplete(allocator: std.mem.Allocator) ![]u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 128);
        errdefer buf.deinit(allocator);

        // Header
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 18))); // names_size
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 2))); // bool_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 3))); // num_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 3))); // str_count
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 29))); // str_table_size

        // Terminal names
        try buf.appendSlice(allocator, "xterm-256color\x00\x00\x00\x00");

        // Booleans
        try buf.append(allocator, 1); // back_color_erase (bce)
        try buf.append(allocator, 0); // can_change (ccc)

        // Numbers
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 80))); // columns
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 24))); // lines
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 256))); // colors

        // String offsets
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 0))); // clear_screen
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 9))); // cursor_home
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 13))); // cursor_address

        // String table
        try buf.appendSlice(allocator, "\x1b[H\x1b[2J\x00"); // clear
        try buf.appendSlice(allocator, "\x1b[H\x00"); // home
        try buf.appendSlice(allocator, "\x1b[%i%p1%d;%p2%dH\x00"); // cup (cursor addressing)

        return buf.toOwnedSlice(allocator);
    }
};

// Mock file system for terminfo file reading
const MockFS = struct {
    files: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) MockFS {
        return .{
            .files = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *MockFS) void {
        self.files.deinit();
    }

    fn addFile(self: *MockFS, path: []const u8, content: []const u8) !void {
        try self.files.put(path, content);
    }

    pub fn readFile(self: *MockFS, path: []const u8) ?[]const u8 {
        return self.files.get(path);
    }
};

// --- Terminfo Binary Format Parsing Tests ---

test "termcap: parse minimal terminfo header" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateMinimal(allocator);
    defer allocator.free(data);

    // This should parse successfully and extract terminal name
    const terminfo = sailor.termcap.TermInfo.parse(allocator, data) catch |err| {
        std.debug.print("Failed to parse minimal terminfo: {}\n", .{err});
        return err;
    };
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm", terminfo.name);
    try testing.expectEqual(@as(usize, 0), terminfo.bool_count);
    try testing.expectEqual(@as(usize, 0), terminfo.num_count);
    try testing.expectEqual(@as(usize, 0), terminfo.str_count);
}

test "termcap: parse terminfo with boolean capabilities" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateWithBooleans(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm-256", terminfo.name);
    try testing.expectEqual(@as(usize, 4), terminfo.bool_count);

    // Boolean capabilities: index-based access
    // 0: auto_left_margin = true
    // 1: auto_right_margin = true
    // 2: beehive_glitch = false
    // 3: back_color_erase = true
    try testing.expect(terminfo.getBoolByIndex(0) == true);
    try testing.expect(terminfo.getBoolByIndex(1) == true);
    try testing.expect(terminfo.getBoolByIndex(2) == false);
    try testing.expect(terminfo.getBoolByIndex(3) == true);
}

test "termcap: parse terminfo with numeric capabilities" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateWithNumbers(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm-256color", terminfo.name);
    try testing.expectEqual(@as(usize, 3), terminfo.num_count);

    // Numeric capabilities: index-based access
    // 0: columns = 80
    // 1: lines = 24
    // 2: colors = 256
    try testing.expectEqual(@as(i16, 80), terminfo.getNumByIndex(0).?);
    try testing.expectEqual(@as(i16, 24), terminfo.getNumByIndex(1).?);
    try testing.expectEqual(@as(i16, 256), terminfo.getNumByIndex(2).?);
}

test "termcap: parse terminfo with string capabilities" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateWithStrings(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm", terminfo.name);
    try testing.expectEqual(@as(usize, 2), terminfo.str_count);

    // String capabilities: index-based access
    // 0: clear_screen = "\x1b[H\x1b[2J"
    // 1: cursor_home = "\x1b[H"
    const clear = terminfo.getStrByIndex(0).?;
    const home = terminfo.getStrByIndex(1).?;

    try testing.expectEqualStrings("\x1b[H\x1b[2J", clear);
    try testing.expectEqualStrings("\x1b[H", home);
}

test "termcap: parse complete terminfo with all capability types" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm-256color", terminfo.name);

    // Verify all capability types are present
    try testing.expectEqual(@as(usize, 2), terminfo.bool_count);
    try testing.expectEqual(@as(usize, 3), terminfo.num_count);
    try testing.expectEqual(@as(usize, 3), terminfo.str_count);

    // Check specific values
    try testing.expect(terminfo.getBoolByIndex(0) == true); // bce
    try testing.expectEqual(@as(i16, 256), terminfo.getNumByIndex(2).?); // colors
    try testing.expectEqualStrings("\x1b[H", terminfo.getStrByIndex(1).?); // home
}

test "termcap: reject invalid magic number" {
    const allocator = testing.allocator;

    var buf: [12]u8 = undefined;
    // Invalid magic number (should be 0o432 or 0o542)
    std.mem.writeInt(u16, buf[0..2], 0xDEAD, .little);
    std.mem.writeInt(u16, buf[2..4], 10, .little); // names_size
    std.mem.writeInt(u16, buf[4..6], 0, .little); // bool_count
    std.mem.writeInt(u16, buf[6..8], 0, .little); // num_count
    std.mem.writeInt(u16, buf[8..10], 0, .little); // str_count
    std.mem.writeInt(u16, buf[10..12], 0, .little); // str_table_size

    const result = sailor.termcap.TermInfo.parse(allocator, &buf);
    try testing.expectError(error.InvalidMagicNumber, result);
}

test "termcap: reject truncated terminfo file" {
    const allocator = testing.allocator;

    // Only header, missing terminal names
    var buf: [12]u8 = undefined;
    std.mem.writeInt(u16, buf[0..2], 0o432, .little);
    std.mem.writeInt(u16, buf[2..4], 10, .little);
    std.mem.writeInt(u16, buf[4..6], 0, .little);
    std.mem.writeInt(u16, buf[6..8], 0, .little);
    std.mem.writeInt(u16, buf[8..10], 0, .little);
    std.mem.writeInt(u16, buf[10..12], 0, .little);

    const result = sailor.termcap.TermInfo.parse(allocator, &buf);
    try testing.expectError(error.TruncatedFile, result);
}

// --- Capability Lookup by Name Tests ---

test "termcap: lookup boolean capability by name" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    // Look up "bce" (back_color_erase) - should be true
    const bce = try terminfo.getBool("bce");
    try testing.expect(bce == true);

    // Look up "ccc" (can_change) - should be false
    const ccc = try terminfo.getBool("ccc");
    try testing.expect(ccc == false);

    // Look up non-existent boolean - should error
    const result = terminfo.getBool("nonexistent");
    try testing.expectError(error.CapabilityNotFound, result);
}

test "termcap: lookup numeric capability by name" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    // Look up "cols" (columns)
    const cols = try terminfo.getNum("cols");
    try testing.expectEqual(@as(i16, 80), cols);

    // Look up "lines"
    const lines = try terminfo.getNum("lines");
    try testing.expectEqual(@as(i16, 24), lines);

    // Look up "colors"
    const colors = try terminfo.getNum("colors");
    try testing.expectEqual(@as(i16, 256), colors);

    // Look up non-existent numeric - should error
    const result = terminfo.getNum("nonexistent");
    try testing.expectError(error.CapabilityNotFound, result);
}

test "termcap: lookup string capability by name" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    // Look up "clear" (clear_screen)
    const clear = try terminfo.getString("clear");
    try testing.expectEqualStrings("\x1b[H\x1b[2J", clear);

    // Look up "home" (cursor_home)
    const home = try terminfo.getString("home");
    try testing.expectEqualStrings("\x1b[H", home);

    // Look up "cup" (cursor_address)
    const cup = try terminfo.getString("cup");
    try testing.expectEqualStrings("\x1b[%i%p1%d;%p2%dH", cup);

    // Look up non-existent string - should error
    const result = terminfo.getString("nonexistent");
    try testing.expectError(error.CapabilityNotFound, result);
}

// --- File Loading Tests (with mocked I/O) ---

test "termcap: load from TERM environment variable" {
    const allocator = testing.allocator;

    var mock_fs = MockFS.init(allocator);
    defer mock_fs.deinit();

    // Add mock terminfo file
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);
    try mock_fs.addFile("/usr/share/terminfo/x/xterm-256color", data);

    // Mock TERM=xterm-256color
    const terminfo = try sailor.termcap.TermInfo.loadWithFS(allocator, "xterm-256color", &mock_fs);
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm-256color", terminfo.name);
}

test "termcap: search multiple terminfo directories" {
    const allocator = testing.allocator;

    var mock_fs = MockFS.init(allocator);
    defer mock_fs.deinit();

    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    // Only available in /lib/terminfo (not in /usr/share/terminfo)
    try mock_fs.addFile("/lib/terminfo/x/xterm-256color", data);

    // Should search both directories and find it in /lib/terminfo
    const terminfo = try sailor.termcap.TermInfo.loadWithFS(allocator, "xterm-256color", &mock_fs);
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm-256color", terminfo.name);
}

test "termcap: fallback when terminfo file not found" {
    const allocator = testing.allocator;

    var mock_fs = MockFS.init(allocator);
    defer mock_fs.deinit();

    // No files in mock FS - should use fallback defaults
    const terminfo = try sailor.termcap.TermInfo.loadWithFS(allocator, "xterm", &mock_fs);
    defer terminfo.deinit();

    // Fallback should provide basic xterm capabilities
    try testing.expectEqualStrings("xterm", terminfo.name);
    try testing.expect(terminfo.supportsColors());
}

test "termcap: error when unknown terminal and no fallback" {
    const allocator = testing.allocator;

    var mock_fs = MockFS.init(allocator);
    defer mock_fs.deinit();

    // Unknown terminal with no fallback
    const result = sailor.termcap.TermInfo.loadWithFS(allocator, "bogus-terminal-9000", &mock_fs);
    try testing.expectError(error.TerminalNotFound, result);
}

// --- Common Capability Helpers Tests ---

test "termcap: supportsColors checks color capability" {
    const allocator = testing.allocator;

    // Terminal with colors
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    try testing.expect(terminfo.supportsColors());
}

test "termcap: getColorCount returns correct value" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    const count = terminfo.getColorCount();
    try testing.expectEqual(@as(u32, 256), count);
}

test "termcap: getColorCount returns 0 when no colors" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateMinimal(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    const count = terminfo.getColorCount();
    try testing.expectEqual(@as(u32, 0), count);
}

test "termcap: supportsMouseSGR checks for SGR mouse tracking" {
    const allocator = testing.allocator;

    // Create terminfo with mouse support (would need extended capabilities)
    // For now, test that the function exists and returns false for basic xterm
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    // Basic xterm without mouse support
    const has_mouse = terminfo.supportsMouseSGR();
    try testing.expect(!has_mouse);
}

test "termcap: supportsSixel checks for Sixel graphics" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    // Basic xterm-256color doesn't support Sixel
    const has_sixel = terminfo.supportsSixel();
    try testing.expect(!has_sixel);
}

test "termcap: supportsKitty checks for Kitty graphics protocol" {
    const allocator = testing.allocator;
    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    // Basic xterm doesn't support Kitty protocol
    const has_kitty = terminfo.supportsKitty();
    try testing.expect(!has_kitty);
}

// --- Fallback Defaults Tests ---

test "termcap: xterm fallback provides basic capabilities" {
    const allocator = testing.allocator;

    const terminfo = try sailor.termcap.TermInfo.createFallback(allocator, "xterm");
    defer terminfo.deinit();

    try testing.expectEqualStrings("xterm", terminfo.name);
    try testing.expect(terminfo.supportsColors());
    try testing.expectEqual(@as(u32, 8), terminfo.getColorCount());

    // Should have basic cursor control strings
    const clear = try terminfo.getString("clear");
    try testing.expect(clear.len > 0);
}

test "termcap: xterm-256color fallback provides 256 colors" {
    const allocator = testing.allocator;

    const terminfo = try sailor.termcap.TermInfo.createFallback(allocator, "xterm-256color");
    defer terminfo.deinit();

    try testing.expect(terminfo.supportsColors());
    try testing.expectEqual(@as(u32, 256), terminfo.getColorCount());
}

test "termcap: screen fallback provides screen-specific capabilities" {
    const allocator = testing.allocator;

    const terminfo = try sailor.termcap.TermInfo.createFallback(allocator, "screen");
    defer terminfo.deinit();

    try testing.expectEqualStrings("screen", terminfo.name);
    try testing.expect(terminfo.supportsColors());
}

test "termcap: tmux fallback provides tmux-specific capabilities" {
    const allocator = testing.allocator;

    const terminfo = try sailor.termcap.TermInfo.createFallback(allocator, "tmux");
    defer terminfo.deinit();

    try testing.expectEqualStrings("tmux", terminfo.name);
    try testing.expect(terminfo.supportsColors());
}

test "termcap: dumb terminal fallback has no colors" {
    const allocator = testing.allocator;

    const terminfo = try sailor.termcap.TermInfo.createFallback(allocator, "dumb");
    defer terminfo.deinit();

    try testing.expect(!terminfo.supportsColors());
    try testing.expectEqual(@as(u32, 0), terminfo.getColorCount());
}

// --- Cross-Platform Tests ---

test "termcap: works on all platforms" {
    // This test should pass on Linux, macOS, and Windows
    // Terminfo is a Unix concept, but we should handle gracefully on Windows

    const allocator = testing.allocator;

    if (builtin.os.tag == .windows) {
        // On Windows, should use fallback (no terminfo files)
        const terminfo = try sailor.termcap.TermInfo.load(allocator, "xterm");
        defer terminfo.deinit();

        try testing.expect(terminfo.supportsColors());
    } else {
        // On Unix, should try to load real terminfo or fallback
        const terminfo = sailor.termcap.TermInfo.load(allocator, "xterm") catch |err| {
            // Allow TerminalNotFound if system doesn't have terminfo
            if (err == error.TerminalNotFound) return;
            return err;
        };
        defer terminfo.deinit();

        try testing.expect(terminfo.name.len > 0);
    }
}

// --- Memory Safety Tests ---

test "termcap: no memory leaks on parse" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    const data = try MockTerminfo.generateComplete(allocator);
    defer allocator.free(data);

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, data);
    defer terminfo.deinit();

    _ = try terminfo.getString("clear");
}

test "termcap: no memory leaks on load failure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var mock_fs = MockFS.init(allocator);
    defer mock_fs.deinit();

    // Should not leak even when loading fails
    const result = sailor.termcap.TermInfo.loadWithFS(allocator, "bogus-terminal", &mock_fs);
    try testing.expectError(error.TerminalNotFound, result);
}

test "termcap: handles invalid terminfo data gracefully" {
    const allocator = testing.allocator;

    // Completely invalid data
    const invalid_data = "not a terminfo file at all";
    const result = sailor.termcap.TermInfo.parse(allocator, invalid_data);
    try testing.expectError(error.InvalidMagicNumber, result);
}

// --- Edge Cases ---

test "termcap: handles empty terminal name" {
    const allocator = testing.allocator;

    var mock_fs = MockFS.init(allocator);
    defer mock_fs.deinit();

    const result = sailor.termcap.TermInfo.loadWithFS(allocator, "", &mock_fs);
    try testing.expectError(error.InvalidTerminalName, result);
}

test "termcap: handles very long terminal name" {
    const allocator = testing.allocator;

    var mock_fs = MockFS.init(allocator);
    defer mock_fs.deinit();

    const long_name = "x" ** 1000; // 1000 characters
    const result = sailor.termcap.TermInfo.loadWithFS(allocator, long_name, &mock_fs);
    try testing.expectError(error.TerminalNotFound, result);
}

test "termcap: absent numeric capability returns null" {
    const allocator = testing.allocator;

    // Create terminfo with absent numeric (value = -1)
    var buf = try std.ArrayList(u8).initCapacity(allocator, 32);
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 1))); // num_count: 1 number
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size

    try buf.appendSlice(allocator, "xterm\x00");

    // Absent numeric capability (-1)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, -1)));

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, buf.items);
    defer terminfo.deinit();

    const num = terminfo.getNumByIndex(0);
    try testing.expect(num == null);
}

test "termcap: absent string capability returns null" {
    const allocator = testing.allocator;

    // Create terminfo with absent string (offset = -1)
    var buf = try std.ArrayList(u8).initCapacity(allocator, 32);
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 1))); // str_count: 1 string
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size

    try buf.appendSlice(allocator, "xterm\x00");

    // Absent string capability (-1)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, -1)));

    const terminfo = try sailor.termcap.TermInfo.parse(allocator, buf.items);
    defer terminfo.deinit();

    const str = terminfo.getStrByIndex(0);
    try testing.expect(str == null);
}
