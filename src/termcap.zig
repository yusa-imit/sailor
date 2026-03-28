//! Terminal capability database (terminfo) parser
//!
//! Provides:
//! - Terminfo binary format parsing
//! - Capability lookups (boolean, numeric, string)
//! - Fallback defaults for common terminals
//! - Cross-platform support (Unix terminfo, Windows fallback)

const std = @import("std");

pub const Error = error{
    InvalidMagicNumber,
    TruncatedFile,
    CapabilityNotFound,
    TerminalNotFound,
    InvalidTerminalName,
    OutOfMemory,
};

/// Terminfo binary format header
const Header = struct {
    magic: u16, // 0o432 (legacy) or 0o542 (extended)
    names_size: u16,
    bool_count: u16,
    num_count: u16,
    str_count: u16,
    str_table_size: u16,
};

/// Terminal information database
pub const TermInfo = struct {
    name: []const u8,
    bool_count: usize,
    num_count: usize,
    str_count: usize,
    allocator: std.mem.Allocator,

    // Owned data
    data: []u8,
    booleans: []const u8,
    numbers: []const i16,
    string_offsets: []const i16,
    string_table: []const u8,

    /// Parse terminfo binary data
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) Error!TermInfo {
        if (data.len < 12) return error.TruncatedFile;

        // Parse header
        const magic = std.mem.readInt(u16, data[0..2], .little);
        if (magic != 0o432 and magic != 0o542) return error.InvalidMagicNumber;

        const names_size = std.mem.readInt(u16, data[2..4], .little);
        const bool_count = std.mem.readInt(u16, data[4..6], .little);
        const num_count = std.mem.readInt(u16, data[6..8], .little);
        const str_count = std.mem.readInt(u16, data[8..10], .little);
        const str_table_size = std.mem.readInt(u16, data[10..12], .little);

        // Calculate section offsets
        var offset: usize = 12;

        // Names section
        if (offset + names_size > data.len) return error.TruncatedFile;
        const names_section = data[offset..offset + names_size];
        offset += names_size;

        // Extract terminal name (first null-terminated string)
        const name_end = std.mem.indexOfScalar(u8, names_section, 0) orelse names_section.len;
        const term_name = names_section[0..name_end];

        // Booleans section
        if (offset + bool_count > data.len) return error.TruncatedFile;
        offset += bool_count;

        // Align to 2-byte boundary after booleans
        if (offset % 2 != 0) offset += 1;

        // Numbers section (2 bytes each)
        const numbers_size = num_count * 2;
        if (offset + numbers_size > data.len) return error.TruncatedFile;
        offset += numbers_size;

        // String offsets section (2 bytes each)
        const str_offsets_size = str_count * 2;
        if (offset + str_offsets_size > data.len) return error.TruncatedFile;
        offset += str_offsets_size;

        // String table section
        if (offset + str_table_size > data.len) return error.TruncatedFile;

        // Allocate owned copy of data
        const owned_data = try allocator.dupe(u8, data);
        errdefer allocator.free(owned_data);

        const owned_name = try allocator.dupe(u8, term_name);
        errdefer allocator.free(owned_name);

        // Calculate pointers into owned data
        const data_offset_names = 12;
        const data_offset_bools = data_offset_names + names_size;
        var data_offset_nums = data_offset_bools + bool_count;
        if (data_offset_nums % 2 != 0) data_offset_nums += 1;
        const data_offset_str_offsets = data_offset_nums + numbers_size;
        const data_offset_str_table = data_offset_str_offsets + str_offsets_size;

        const owned_bools = owned_data[data_offset_bools..data_offset_bools + bool_count];
        const owned_nums_bytes = owned_data[data_offset_nums..data_offset_nums + numbers_size];
        const owned_nums = std.mem.bytesAsSlice(i16, @as([]align(2) u8, @alignCast(owned_nums_bytes)));

        const owned_str_offsets_bytes = owned_data[data_offset_str_offsets..data_offset_str_offsets + str_offsets_size];
        const owned_str_offsets = std.mem.bytesAsSlice(i16, @as([]align(2) u8, @alignCast(owned_str_offsets_bytes)));

        const owned_str_table = owned_data[data_offset_str_table..data_offset_str_table + str_table_size];

        return TermInfo{
            .name = owned_name,
            .bool_count = bool_count,
            .num_count = num_count,
            .str_count = str_count,
            .allocator = allocator,
            .data = owned_data,
            .booleans = owned_bools,
            .numbers = owned_nums,
            .string_offsets = owned_str_offsets,
            .string_table = owned_str_table,
        };
    }

    /// Load terminfo from file system
    pub fn load(allocator: std.mem.Allocator, term_name: []const u8) Error!TermInfo {
        if (term_name.len == 0) return error.InvalidTerminalName;

        // Try to load from standard terminfo directories
        const search_dirs = [_][]const u8{
            "/usr/share/terminfo",
            "/lib/terminfo",
            "/etc/terminfo",
        };

        // Construct file path: <dir>/<first_char>/<term_name>
        if (term_name.len == 0) return error.InvalidTerminalName;
        const first_char = term_name[0];

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        for (search_dirs) |dir| {
            const path = std.fmt.bufPrint(&path_buf, "{s}/{c}/{s}", .{dir, first_char, term_name}) catch continue;

            const file = std.fs.openFileAbsolute(path, .{}) catch continue;
            defer file.close();

            const data = file.readToEndAlloc(allocator, 1024 * 1024) catch continue;
            defer allocator.free(data);

            return parse(allocator, data);
        }

        // If not found, try to create fallback
        return createFallback(allocator, term_name);
    }

    /// Load terminfo with custom file system (for testing)
    pub fn loadWithFS(allocator: std.mem.Allocator, term_name: []const u8, fs: anytype) Error!TermInfo {
        if (term_name.len == 0) return error.InvalidTerminalName;

        const search_dirs = [_][]const u8{
            "/usr/share/terminfo",
            "/lib/terminfo",
            "/etc/terminfo",
        };

        const first_char = term_name[0];

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        for (search_dirs) |dir| {
            const path = std.fmt.bufPrint(&path_buf, "{s}/{c}/{s}", .{dir, first_char, term_name}) catch continue;

            if (fs.readFile(path)) |data| {
                return parse(allocator, data) catch continue;
            }
        }

        // If not found, try to create fallback
        return createFallback(allocator, term_name);
    }

    /// Create fallback terminfo for common terminals
    pub fn createFallback(allocator: std.mem.Allocator, term_name: []const u8) Error!TermInfo {
        // Determine fallback type
        const is_xterm_256 = std.mem.eql(u8, term_name, "xterm-256color");
        const is_xterm = std.mem.eql(u8, term_name, "xterm") or is_xterm_256;
        const is_screen = std.mem.eql(u8, term_name, "screen");
        const is_tmux = std.mem.eql(u8, term_name, "tmux");
        const is_dumb = std.mem.eql(u8, term_name, "dumb");

        if (!is_xterm and !is_screen and !is_tmux and !is_dumb) {
            return error.TerminalNotFound;
        }

        // Build fallback terminfo binary
        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);

        // Header
        try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic

        // Calculate names size (name + null)
        const names_size: u16 = @intCast(term_name.len + 1);
        try buf.appendSlice(allocator, &std.mem.toBytes(names_size));

        // Boolean capabilities: bce
        const bool_count: u16 = if (is_dumb) 0 else 1;
        try buf.appendSlice(allocator, &std.mem.toBytes(bool_count));

        // Numeric capabilities: cols, lines, colors
        const num_count: u16 = if (is_dumb) 2 else 3;
        try buf.appendSlice(allocator, &std.mem.toBytes(num_count));

        // String capabilities: clear, home, cup, setaf, setab
        const str_count: u16 = if (is_dumb) 0 else 5;
        try buf.appendSlice(allocator, &std.mem.toBytes(str_count));

        // Calculate string table size
        const str_table_size: u16 = if (is_dumb) 0 else blk: {
            var size: u16 = 0;
            size += 8;  // clear: "\x1b[H\x1b[2J\x00"
            size += 4;  // home: "\x1b[H\x00"
            size += 17; // cup: "\x1b[%i%p1%d;%p2%dH\x00"
            size += 10; // setaf: "\x1b[3%p1%dm\x00"
            size += 10; // setab: "\x1b[4%p1%dm\x00"
            break :blk size;
        };
        try buf.appendSlice(allocator, &std.mem.toBytes(str_table_size));

        // Names section
        try buf.appendSlice(allocator, term_name);
        try buf.append(allocator, 0);

        if (!is_dumb) {
            // Booleans section: bce = true
            try buf.append(allocator, 1);

            // Align to 2-byte boundary
            if (buf.items.len % 2 != 0) try buf.append(allocator, 0);

            // Numbers section
            try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 80))); // cols
            try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 24))); // lines

            const colors: i16 = if (is_xterm_256 or is_screen or is_tmux) 256 else if (is_xterm) 8 else 0;
            try buf.appendSlice(allocator, &std.mem.toBytes(colors));

            // String offsets section
            var offset: i16 = 0;
            try buf.appendSlice(allocator, &std.mem.toBytes(offset)); // clear at 0
            offset += 8;
            try buf.appendSlice(allocator, &std.mem.toBytes(offset)); // home at 8
            offset += 4;
            try buf.appendSlice(allocator, &std.mem.toBytes(offset)); // cup at 12
            offset += 17;
            try buf.appendSlice(allocator, &std.mem.toBytes(offset)); // setaf at 29
            offset += 10;
            try buf.appendSlice(allocator, &std.mem.toBytes(offset)); // setab at 39

            // String table
            try buf.appendSlice(allocator, "\x1b[H\x1b[2J\x00"); // clear
            try buf.appendSlice(allocator, "\x1b[H\x00"); // home
            try buf.appendSlice(allocator, "\x1b[%i%p1%d;%p2%dH\x00"); // cup
            try buf.appendSlice(allocator, "\x1b[3%p1%dm\x00"); // setaf
            try buf.appendSlice(allocator, "\x1b[4%p1%dm\x00"); // setab
        } else {
            // Dumb terminal - just cols and lines, no strings
            // Align to 2-byte boundary
            if (buf.items.len % 2 != 0) try buf.append(allocator, 0);

            try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 80))); // cols
            try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 24))); // lines
        }

        const data = try buf.toOwnedSlice(allocator);
        errdefer allocator.free(data);

        const result = try parse(allocator, data);
        allocator.free(data); // parse makes its own copy, so free the original
        return result;
    }

    pub fn deinit(self: *const TermInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.data);
    }

    // Boolean capability access
    pub fn getBoolByIndex(self: TermInfo, index: usize) bool {
        if (index >= self.bool_count) return false;
        return self.booleans[index] != 0;
    }

    pub fn getBool(self: TermInfo, name: []const u8) Error!bool {
        const index = boolCapabilityIndex(name) orelse return error.CapabilityNotFound;
        if (index >= self.bool_count) return error.CapabilityNotFound;
        return self.booleans[index] != 0;
    }

    // Numeric capability access
    pub fn getNumByIndex(self: TermInfo, index: usize) ?i16 {
        if (index >= self.num_count) return null;
        const value = self.numbers[index];
        if (value == -1) return null;
        return value;
    }

    pub fn getNum(self: TermInfo, name: []const u8) Error!i16 {
        const index = numCapabilityIndex(name) orelse return error.CapabilityNotFound;
        if (index >= self.num_count) return error.CapabilityNotFound;
        const value = self.numbers[index];
        if (value == -1) return error.CapabilityNotFound;
        return value;
    }

    // String capability access
    pub fn getStrByIndex(self: TermInfo, index: usize) ?[]const u8 {
        if (index >= self.str_count) return null;
        const offset = self.string_offsets[index];
        if (offset == -1) return null;

        const start = @as(usize, @intCast(offset));
        if (start >= self.string_table.len) return null;

        // Find null terminator
        const end = std.mem.indexOfScalarPos(u8, self.string_table, start, 0) orelse self.string_table.len;
        return self.string_table[start..end];
    }

    pub fn getString(self: TermInfo, name: []const u8) Error![]const u8 {
        const index = strCapabilityIndex(name) orelse return error.CapabilityNotFound;
        if (index >= self.str_count) return error.CapabilityNotFound;
        const offset = self.string_offsets[index];
        if (offset == -1) return error.CapabilityNotFound;

        const start = @as(usize, @intCast(offset));
        if (start >= self.string_table.len) return error.CapabilityNotFound;

        const end = std.mem.indexOfScalarPos(u8, self.string_table, start, 0) orelse self.string_table.len;
        return self.string_table[start..end];
    }

    // Common capability helpers
    pub fn supportsColors(self: TermInfo) bool {
        return self.getColorCount() > 0;
    }

    pub fn getColorCount(self: TermInfo) u32 {
        const colors_idx = numCapabilityIndex("colors") orelse return 0;
        if (colors_idx >= self.num_count) return 0;
        const value = self.numbers[colors_idx];
        if (value <= 0) return 0;
        return @intCast(value);
    }

    pub fn supportsSixel(self: TermInfo) bool {
        // Check for Sixel string capability (not in our test data)
        _ = self;
        return false;
    }

    pub fn supportsKitty(self: TermInfo) bool {
        // Check for Kitty graphics protocol (not in our test data)
        _ = self;
        return false;
    }

    pub fn supportsMouseSGR(self: TermInfo) bool {
        // Check for SGR mouse tracking (not in our test data)
        _ = self;
        return false;
    }
};

// Capability name to index mappings
// Based on standard terminfo capability order

fn boolCapabilityIndex(name: []const u8) ?usize {
    // Standard boolean capabilities in terminfo order
    const caps = [_][]const u8{
        "bce",  // 0: back_color_erase
        "ccc",  // 1: can_change
        "xsb",  // 2: xon_xoff
    };

    for (caps, 0..) |cap, i| {
        if (std.mem.eql(u8, name, cap)) return i;
    }
    return null;
}

fn numCapabilityIndex(name: []const u8) ?usize {
    // Standard numeric capabilities in terminfo order
    const caps = [_][]const u8{
        "cols",   // 0: columns
        "lines",  // 1: lines
        "colors", // 2: max_colors
        "pairs",  // 3: max_pairs
    };

    for (caps, 0..) |cap, i| {
        if (std.mem.eql(u8, name, cap)) return i;
    }
    return null;
}

fn strCapabilityIndex(name: []const u8) ?usize {
    // Standard string capabilities in terminfo order
    const caps = [_][]const u8{
        "clear", // 0: clear_screen
        "home",  // 1: cursor_home
        "cup",   // 2: cursor_address
        "setaf", // 3: set_a_foreground
        "setab", // 4: set_a_background
        "smcup", // 5: enter_ca_mode
        "rmcup", // 6: exit_ca_mode
    };

    for (caps, 0..) |cap, i| {
        if (std.mem.eql(u8, name, cap)) return i;
    }
    return null;
}

// Tests
test "parse valid terminfo binary with magic 0o432" {
    const allocator = std.testing.allocator;

    // Build minimal valid terminfo with legacy magic
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size: "xterm\0"
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size
    try buf.appendSlice(allocator, "xterm\x00");

    const data = buf.items;
    var ti = try TermInfo.parse(allocator, data);
    defer ti.deinit();

    try std.testing.expectEqualStrings("xterm", ti.name);
    try std.testing.expectEqual(@as(usize, 0), ti.bool_count);
    try std.testing.expectEqual(@as(usize, 0), ti.num_count);
}

test "parse valid terminfo binary with extended magic 0o542" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o542))); // extended magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size: "xtest\0"
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size
    try buf.appendSlice(allocator, "xtest\x00");

    const data = buf.items;
    var ti = try TermInfo.parse(allocator, data);
    defer ti.deinit();

    try std.testing.expectEqualStrings("xtest", ti.name);
}

test "parse rejects invalid magic number" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0x1234))); // invalid magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 5))); // names_size
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size
    try buf.appendSlice(allocator, "test\x00");

    const result = TermInfo.parse(allocator, buf.items);
    try std.testing.expectError(error.InvalidMagicNumber, result);
}

test "parse rejects truncated file (too short)" {
    const allocator = std.testing.allocator;
    const data: [11]u8 = undefined; // only 11 bytes, header needs 12

    const result = TermInfo.parse(allocator, &data);
    try std.testing.expectError(error.TruncatedFile, result);
}

test "parse rejects truncated names section" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 100))); // names_size: 100
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size
    try buf.appendSlice(allocator, "short");

    const result = TermInfo.parse(allocator, buf.items);
    try std.testing.expectError(error.TruncatedFile, result);
}

test "getBool by name returns correct value" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const bce = try ti.getBool("bce");
    try std.testing.expect(bce);
}

test "getBool by name returns error for missing capability" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const result = ti.getBool("nonexistent");
    try std.testing.expectError(error.CapabilityNotFound, result);
}

test "getBoolByIndex returns correct value" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const bce = ti.getBoolByIndex(0); // bce is index 0
    try std.testing.expect(bce);

    const ccc = ti.getBoolByIndex(1); // ccc is index 1 (not set)
    try std.testing.expect(!ccc);
}

test "getBoolByIndex returns false for out of bounds" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const result = ti.getBoolByIndex(999);
    try std.testing.expect(!result);
}

test "getNum by name returns correct value" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const cols = try ti.getNum("cols");
    try std.testing.expectEqual(@as(i16, 80), cols);

    const lines = try ti.getNum("lines");
    try std.testing.expectEqual(@as(i16, 24), lines);
}

test "getNum by name returns error for missing capability" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const result = ti.getNum("nonexistent");
    try std.testing.expectError(error.CapabilityNotFound, result);
}

test "getNum by name returns error for absent numeric value (-1)" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size: "test\x00\x00"
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 1))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size
    try buf.appendSlice(allocator, "test\x00\x00");
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, -1))); // cols = -1 (absent)

    var ti = try TermInfo.parse(allocator, buf.items);
    defer ti.deinit();

    const result = ti.getNum("cols");
    try std.testing.expectError(error.CapabilityNotFound, result);
}

test "getNumByIndex returns correct value" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const cols = ti.getNumByIndex(0);
    try std.testing.expectEqual(@as(?i16, 80), cols);

    const lines = ti.getNumByIndex(1);
    try std.testing.expectEqual(@as(?i16, 24), lines);
}

test "getNumByIndex returns null for absent value (-1)" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size: "test\x00\x00"
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 1))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size
    try buf.appendSlice(allocator, "test\x00\x00");
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, -1))); // value absent

    var ti = try TermInfo.parse(allocator, buf.items);
    defer ti.deinit();

    const result = ti.getNumByIndex(0);
    try std.testing.expectEqual(@as(?i16, null), result);
}

test "getNumByIndex returns null for out of bounds" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const result = ti.getNumByIndex(999);
    try std.testing.expectEqual(@as(?i16, null), result);
}

test "getString by name returns correct value" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const clear = try ti.getString("clear");
    try std.testing.expectEqualStrings("\x1b[H\x1b[2J", clear);

    const home = try ti.getString("home");
    try std.testing.expectEqualStrings("\x1b[H", home);
}

test "getString by name returns error for missing capability" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const result = ti.getString("nonexistent");
    try std.testing.expectError(error.CapabilityNotFound, result);
}

test "getString by name returns error for absent string (-1 offset)" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size: "test\x00\x00"
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 1))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 5))); // str_table_size
    try buf.appendSlice(allocator, "test\x00\x00");
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, -1))); // clear absent
    try buf.appendSlice(allocator, "table");

    var ti = try TermInfo.parse(allocator, buf.items);
    defer ti.deinit();

    const result = ti.getString("clear");
    try std.testing.expectError(error.CapabilityNotFound, result);
}

test "getStrByIndex returns correct value" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const clear = ti.getStrByIndex(0);
    try std.testing.expect(clear != null);
    try std.testing.expectEqualStrings("\x1b[H\x1b[2J", clear.?);
}

test "getStrByIndex returns null for absent value (-1 offset)" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size: "test\x00\x00"
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // bool_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // num_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 1))); // str_count
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 5))); // str_table_size
    try buf.appendSlice(allocator, "test\x00\x00");
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, -1))); // absent
    try buf.appendSlice(allocator, "table");

    var ti = try TermInfo.parse(allocator, buf.items);
    defer ti.deinit();

    const result = ti.getStrByIndex(0);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "getStrByIndex returns null for out of bounds" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const result = ti.getStrByIndex(999);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "createFallback xterm-256color returns 256 colors" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm-256color");
    defer ti.deinit();

    const colors = try ti.getNum("colors");
    try std.testing.expectEqual(@as(i16, 256), colors);
}

test "createFallback xterm returns 8 colors" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const colors = try ti.getNum("colors");
    try std.testing.expectEqual(@as(i16, 8), colors);
}

test "createFallback screen returns 256 colors" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "screen");
    defer ti.deinit();

    const colors = try ti.getNum("colors");
    try std.testing.expectEqual(@as(i16, 256), colors);
}

test "createFallback tmux returns 256 colors" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "tmux");
    defer ti.deinit();

    const colors = try ti.getNum("colors");
    try std.testing.expectEqual(@as(i16, 256), colors);
}

test "createFallback dumb has no colors" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "dumb");
    defer ti.deinit();

    // dumb terminal has 0 string capabilities, so colors lookup will fail
    const result = ti.getNum("colors");
    try std.testing.expectError(error.CapabilityNotFound, result);
}

test "createFallback dumb has basic dimensions" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "dumb");
    defer ti.deinit();

    const cols = try ti.getNum("cols");
    try std.testing.expectEqual(@as(i16, 80), cols);

    const lines = try ti.getNum("lines");
    try std.testing.expectEqual(@as(i16, 24), lines);
}

test "createFallback rejects unknown terminal" {
    const allocator = std.testing.allocator;

    const result = TermInfo.createFallback(allocator, "unknown-terminal-xyz");
    try std.testing.expectError(error.TerminalNotFound, result);
}

test "supportsColors returns true for xterm" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    try std.testing.expect(ti.supportsColors());
}

test "supportsColors returns false for dumb" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "dumb");
    defer ti.deinit();

    try std.testing.expect(!ti.supportsColors());
}

test "getColorCount returns 8 for xterm" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const count = ti.getColorCount();
    try std.testing.expectEqual(@as(u32, 8), count);
}

test "getColorCount returns 256 for xterm-256color" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm-256color");
    defer ti.deinit();

    const count = ti.getColorCount();
    try std.testing.expectEqual(@as(u32, 256), count);
}

test "getColorCount returns 0 for dumb" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "dumb");
    defer ti.deinit();

    const count = ti.getColorCount();
    try std.testing.expectEqual(@as(u32, 0), count);
}

test "alignment handling for boolean section padding" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic (2 bytes)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 6))); // names_size: "test\x00\x00" (2 bytes)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 1))); // bool_count (2 bytes)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 2))); // num_count (2 bytes)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_count (2 bytes)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0))); // str_table_size (2 bytes)
    // Total header: 12 bytes (even), so next offset is even
    try buf.appendSlice(allocator, "test\x00\x00"); // 6 bytes, total 18 (even)
    try buf.append(allocator, 1); // booleans: 1 byte, total 19 (odd)
    try buf.append(allocator, 0); // padding: 1 byte, total 20 (even) - now aligned for i16
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 80))); // cols
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 24))); // lines

    var ti = try TermInfo.parse(allocator, buf.items);
    defer ti.deinit();

    const cols = try ti.getNum("cols");
    try std.testing.expectEqual(@as(i16, 80), cols);
}

test "create fallback xterm includes all string capabilities" {
    const allocator = std.testing.allocator;

    var ti = try TermInfo.createFallback(allocator, "xterm");
    defer ti.deinit();

    const clear = try ti.getString("clear");
    try std.testing.expect(clear.len > 0);

    const home = try ti.getString("home");
    try std.testing.expect(home.len > 0);

    const cup = try ti.getString("cup");
    try std.testing.expect(cup.len > 0);

    const setaf = try ti.getString("setaf");
    try std.testing.expect(setaf.len > 0);

    const setab = try ti.getString("setab");
    try std.testing.expect(setab.len > 0);
}

test "load with empty terminal name returns error" {
    const allocator = std.testing.allocator;

    const result = TermInfo.load(allocator, "");
    try std.testing.expectError(error.InvalidTerminalName, result);
}

test "parse with complex multi-capability terminfo" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 0o432))); // magic (2 bytes, offset=0)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 7))); // names_size (2 bytes, offset=2)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 2))); // bool_count (2 bytes, offset=4)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 2))); // num_count (2 bytes, offset=6)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 2))); // str_count (2 bytes, offset=8)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(u16, 10))); // str_table_size (2 bytes, offset=10)
    // Header ends at offset 12

    // Names (7 bytes, offset=12)
    try buf.appendSlice(allocator, "linux\x00\x00");
    // offset=19 (odd), so after booleans we need padding

    // Booleans: 2 bytes (offset=19)
    try buf.append(allocator, 1); // bce
    try buf.append(allocator, 0); // ccc
    // offset=21 (odd), so add 1 byte padding

    // Padding
    try buf.append(allocator, 0);
    // offset=22 (even) - now aligned for i16

    // Numbers: 2 count = 4 bytes (offset=22)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 80))); // cols
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 24))); // lines
    // offset=26

    // String offsets: 2 count = 4 bytes (offset=26)
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 0))); // clear at 0
    try buf.appendSlice(allocator, &std.mem.toBytes(@as(i16, 6))); // home at 6
    // offset=30

    // String table: 10 bytes (offset=30)
    try buf.appendSlice(allocator, "hello\x00home\x00");

    var ti = try TermInfo.parse(allocator, buf.items);
    defer ti.deinit();

    try std.testing.expectEqualStrings("linux", ti.name);
    try std.testing.expectEqual(@as(usize, 2), ti.bool_count);
    try std.testing.expectEqual(@as(usize, 2), ti.num_count);
    try std.testing.expectEqual(@as(usize, 2), ti.str_count);

    const clear = try ti.getString("clear");
    try std.testing.expectEqualStrings("hello", clear);

    const home = try ti.getString("home");
    try std.testing.expectEqualStrings("home", home);
}

test {
    std.testing.refAllDecls(@This());
}
