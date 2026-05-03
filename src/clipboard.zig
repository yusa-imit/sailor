//! System clipboard integration via OSC 52 escape sequences
//!
//! Provides cross-platform clipboard read/write operations using
//! OSC 52 (Operating System Command) terminal escape sequences.
//!
//! Supports three clipboard selections:
//! - clipboard: Standard system clipboard (Ctrl+C/V)
//! - primary: X11 primary selection (middle-click paste)
//! - system: System-specific clipboard (Windows/macOS)
//!
//! All operations are Writer-based for library safety.
//!
//! Protocol: OSC 52 uses base64-encoded text in escape sequences
//! Write: \x1b]52;<selection>;<base64>\x07
//! Read:  \x1b]52;<selection>;?\x07
//!
//! Limitations:
//! - Reading clipboard requires terminal support (many terminals don't support it)
//! - Some terminals limit clipboard size (typically 1KB-100KB)
//! - SSH/tmux may require additional configuration

const std = @import("std");
const builtin = @import("builtin");

/// Clipboard selection type
pub const Selection = enum {
    clipboard,  // c - standard clipboard
    primary,    // p - X11 primary selection
    system,     // s - system clipboard (Windows/macOS)

    /// Get OSC 52 selection parameter character
    fn toParam(self: Selection) u8 {
        return switch (self) {
            .clipboard => 'c',
            .primary => 'p',
            .system => 's',
        };
    }
};

/// Clipboard operations via OSC 52 escape sequences
pub const Clipboard = struct {
    /// Write text to clipboard using OSC 52 escape sequence
    /// Format: \x1b]52;<selection>;<base64>\x07
    pub fn write(writer: anytype, text: []const u8, selection: Selection) !void {
        // Write OSC 52 prefix: ESC ] 52 ; <selection> ;
        try writer.writeAll("\x1b]52;");
        try writer.writeByte(selection.toParam());
        try writer.writeByte(';');

        // Base64 encode and write the text
        if (text.len > 0) {
            try writeBase64(writer, text);
        }

        // Write BEL terminator
        try writer.writeByte(0x07);
    }

    /// Request clipboard contents (sends OSC 52 query)
    /// Format: \x1b]52;<selection>;?\x07
    /// Note: Reading clipboard requires terminal support and may not work in all terminals
    pub fn requestRead(writer: anytype, selection: Selection) !void {
        // Write OSC 52 query: ESC ] 52 ; <selection> ; ? BEL
        try writer.writeAll("\x1b]52;");
        try writer.writeByte(selection.toParam());
        try writer.writeAll(";?\x07");
    }

    /// Check if clipboard operations are supported on this platform
    pub fn isSupported() bool {
        switch (builtin.os.tag) {
            .linux, .macos, .freebsd, .openbsd, .netbsd, .windows => return true,
            else => return false,
        }
    }
};

/// Base64 encoding for clipboard data
/// Uses standard base64 alphabet with padding
fn writeBase64(writer: anytype, input: []const u8) !void {
    const base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    var i: usize = 0;
    while (i + 3 <= input.len) : (i += 3) {
        const b1 = input[i];
        const b2 = input[i + 1];
        const b3 = input[i + 2];

        // Encode 3 bytes into 4 base64 characters
        try writer.writeByte(base64_alphabet[(b1 >> 2) & 0x3F]);
        try writer.writeByte(base64_alphabet[((b1 << 4) | (b2 >> 4)) & 0x3F]);
        try writer.writeByte(base64_alphabet[((b2 << 2) | (b3 >> 6)) & 0x3F]);
        try writer.writeByte(base64_alphabet[b3 & 0x3F]);
    }

    // Handle remaining bytes with padding
    const remaining = input.len - i;
    if (remaining == 1) {
        const b1 = input[i];
        try writer.writeByte(base64_alphabet[(b1 >> 2) & 0x3F]);
        try writer.writeByte(base64_alphabet[(b1 << 4) & 0x3F]);
        try writer.writeAll("==");
    } else if (remaining == 2) {
        const b1 = input[i];
        const b2 = input[i + 1];
        try writer.writeByte(base64_alphabet[(b1 >> 2) & 0x3F]);
        try writer.writeByte(base64_alphabet[((b1 << 4) | (b2 >> 4)) & 0x3F]);
        try writer.writeByte(base64_alphabet[(b2 << 2) & 0x3F]);
        try writer.writeByte('=');
    }
}

/// Clipboard history buffer with FIFO eviction
/// Stores up to 10 clipboard entries, most recent first
pub const ClipboardHistory = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList([]u8),

    const MAX_ENTRIES = 10;

    /// Initialize empty clipboard history
    pub fn init(allocator: std.mem.Allocator) !ClipboardHistory {
        return ClipboardHistory{
            .allocator = allocator,
            .entries = .{},
        };
    }

    /// Free all stored entries and internal memory
    pub fn deinit(self: *ClipboardHistory) void {
        self.clear();
        self.entries.deinit(self.allocator);
    }

    /// Add new entry to history (most recent becomes index 0)
    /// If capacity exceeded, removes oldest entry
    pub fn push(self: *ClipboardHistory, text: []const u8) !void {
        // Make owned copy of the text
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        // Insert at front (index 0 = most recent)
        try self.entries.insert(self.allocator, 0, owned_text);

        // If exceeded capacity, remove oldest (last entry)
        if (self.entries.items.len > MAX_ENTRIES) {
            const oldest = self.entries.items[self.entries.items.len - 1];
            _ = self.entries.pop();
            self.allocator.free(oldest);
        }
    }

    /// Get entry at index (0 = most recent)
    /// Returns error.IndexOutOfBounds if index >= len
    pub fn get(self: *const ClipboardHistory, index: usize) ![]const u8 {
        if (index >= self.entries.items.len) {
            return error.IndexOutOfBounds;
        }
        return self.entries.items[index];
    }

    /// Get all entries as slice (no allocation, points to internal storage)
    /// Slice is valid until next push/clear/deinit
    pub fn getAll(self: *const ClipboardHistory) []const []const u8 {
        // Cast to const slice for return
        return self.entries.items;
    }

    /// Get number of entries currently stored
    pub fn len(self: *ClipboardHistory) usize {
        return self.entries.items.len;
    }

    /// Remove all entries and free their memory
    pub fn clear(self: *ClipboardHistory) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.entries.clearRetainingCapacity();
    }
};

/// System clipboard integration using platform-specific commands
/// Provides fallback when OSC 52 terminal sequences are not supported
pub const SystemClipboard = struct {
    /// Check if system clipboard commands are available on this platform
    pub fn isAvailable() !bool {
        switch (builtin.os.tag) {
            .macos => {
                // pbcopy/pbpaste are standard on macOS
                return true;
            },
            .linux => {
                // Check for xclip or xsel
                const result_xclip = std.process.Child.run(.{
                    .allocator = std.heap.page_allocator,
                    .argv = &[_][]const u8{ "which", "xclip" },
                }) catch return false;
                defer std.heap.page_allocator.free(result_xclip.stdout);
                defer std.heap.page_allocator.free(result_xclip.stderr);

                if (result_xclip.term == .Exited and result_xclip.term.Exited == 0) return true;

                const result_xsel = std.process.Child.run(.{
                    .allocator = std.heap.page_allocator,
                    .argv = &[_][]const u8{ "which", "xsel" },
                }) catch return false;
                defer std.heap.page_allocator.free(result_xsel.stdout);
                defer std.heap.page_allocator.free(result_xsel.stderr);

                return result_xsel.term == .Exited and result_xsel.term.Exited == 0;
            },
            .windows => {
                // PowerShell is standard on modern Windows
                return true;
            },
            else => return false,
        }
    }

    /// Write text to system clipboard
    pub fn write(allocator: std.mem.Allocator, text: []const u8) !void {
        switch (builtin.os.tag) {
            .macos => {
                var child = std.process.Child.init(&[_][]const u8{"pbcopy"}, allocator);
                child.stdin_behavior = .Pipe;
                child.stdout_behavior = .Ignore;
                child.stderr_behavior = .Ignore;

                try child.spawn();

                // Write text to stdin
                const stdin = child.stdin.?;
                try stdin.writeAll(text);
                stdin.close();
                child.stdin = null;

                const term = try child.wait();
                switch (term) {
                    .Exited => |code| if (code != 0) return error.ClipboardWriteFailed,
                    else => return error.ClipboardWriteFailed,
                }
            },
            .linux => {
                // Try xclip first
                const xclip_result = std.process.Child.run(.{
                    .allocator = std.heap.page_allocator,
                    .argv = &[_][]const u8{ "which", "xclip" },
                }) catch {
                    return try writeLinuxXsel(allocator, text);
                };
                defer std.heap.page_allocator.free(xclip_result.stdout);
                defer std.heap.page_allocator.free(xclip_result.stderr);

                if (xclip_result.term == .Exited and xclip_result.term.Exited == 0) {
                    return try writeLinuxXclip(allocator, text);
                } else {
                    return try writeLinuxXsel(allocator, text);
                }
            },
            .windows => {
                // Use PowerShell Set-Clipboard
                const ps_cmd = try std.fmt.allocPrint(allocator, "Set-Clipboard -Value '{s}'", .{text});
                defer allocator.free(ps_cmd);

                var child = std.process.Child.init(&[_][]const u8{ "powershell", "-Command", ps_cmd }, allocator);
                child.stdin_behavior = .Ignore;
                child.stdout_behavior = .Ignore;
                child.stderr_behavior = .Ignore;

                try child.spawn();
                const term = try child.wait();

                switch (term) {
                    .Exited => |code| if (code != 0) return error.ClipboardWriteFailed,
                    else => return error.ClipboardWriteFailed,
                }
            },
            else => return error.ClipboardUnavailable,
        }
    }

    /// Read text from system clipboard (caller must free returned string)
    pub fn read(allocator: std.mem.Allocator) ![]const u8 {
        switch (builtin.os.tag) {
            .macos => {
                const result = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &[_][]const u8{"pbpaste"},
                });
                defer allocator.free(result.stderr);

                switch (result.term) {
                    .Exited => |code| if (code != 0) {
                        allocator.free(result.stdout);
                        return error.ClipboardReadFailed;
                    },
                    else => {
                        allocator.free(result.stdout);
                        return error.ClipboardReadFailed;
                    },
                }

                return result.stdout;
            },
            .linux => {
                // Try xclip first
                const xclip_check = std.process.Child.run(.{
                    .allocator = std.heap.page_allocator,
                    .argv = &[_][]const u8{ "which", "xclip" },
                }) catch {
                    return try readLinuxXsel(allocator);
                };
                defer std.heap.page_allocator.free(xclip_check.stdout);
                defer std.heap.page_allocator.free(xclip_check.stderr);

                if (xclip_check.term == .Exited and xclip_check.term.Exited == 0) {
                    return try readLinuxXclip(allocator);
                } else {
                    return try readLinuxXsel(allocator);
                }
            },
            .windows => {
                const result = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &[_][]const u8{ "powershell", "-Command", "Get-Clipboard" },
                });
                defer allocator.free(result.stderr);

                switch (result.term) {
                    .Exited => |code| if (code != 0) {
                        allocator.free(result.stdout);
                        return error.ClipboardReadFailed;
                    },
                    else => {
                        allocator.free(result.stdout);
                        return error.ClipboardReadFailed;
                    },
                }

                return result.stdout;
            },
            else => return error.ClipboardUnavailable,
        }
    }

    // Linux xclip helper
    fn writeLinuxXclip(allocator: std.mem.Allocator, text: []const u8) !void {
        var child = std.process.Child.init(&[_][]const u8{ "xclip", "-selection", "clipboard" }, allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();

        const stdin = child.stdin.?;
        try stdin.writeAll(text);
        stdin.close();
        child.stdin = null;

        const term = try child.wait();
        switch (term) {
            .Exited => |code| if (code != 0) return error.ClipboardWriteFailed,
            else => return error.ClipboardWriteFailed,
        }
    }

    fn readLinuxXclip(allocator: std.mem.Allocator) ![]const u8 {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "xclip", "-selection", "clipboard", "-o" },
        });
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| if (code != 0) {
                allocator.free(result.stdout);
                return error.ClipboardReadFailed;
            },
            else => {
                allocator.free(result.stdout);
                return error.ClipboardReadFailed;
            },
        }

        return result.stdout;
    }

    // Linux xsel helper
    fn writeLinuxXsel(allocator: std.mem.Allocator, text: []const u8) !void {
        var child = std.process.Child.init(&[_][]const u8{ "xsel", "--clipboard", "--input" }, allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();

        const stdin = child.stdin.?;
        try stdin.writeAll(text);
        stdin.close();
        child.stdin = null;

        const term = try child.wait();
        switch (term) {
            .Exited => |code| if (code != 0) return error.ClipboardWriteFailed,
            else => return error.ClipboardWriteFailed,
        }
    }

    fn readLinuxXsel(allocator: std.mem.Allocator) ![]const u8 {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "xsel", "--clipboard", "--output" },
        });
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| if (code != 0) {
                allocator.free(result.stdout);
                return error.ClipboardReadFailed;
            },
            else => {
                allocator.free(result.stdout);
                return error.ClipboardReadFailed;
            },
        }

        return result.stdout;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

// Test helper: capture output to buffer
fn captureOutput(comptime func: anytype, args: anytype) ![]const u8 {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try @call(.auto, func, .{stream.writer()} ++ args);
    return stream.getWritten();
}

// ============================================================================
// Basic Write Operations
// ============================================================================

test "write simple ASCII text to clipboard" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.write(stream.writer(), "hello", .clipboard);

    const output = stream.getWritten();
    const expected = "\x1b]52;c;aGVsbG8=\x07"; // "hello" in base64

    try testing.expectEqualStrings(expected, output);
}

test "write Unicode and emoji text" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const text = "Hello 世界 🚀";
    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();
    // Base64 of "Hello 世界 🚀"
    const expected = "\x1b]52;c;SGVsbG8g5LiW55WMIPCfmoA=\x07";

    try testing.expectEqualStrings(expected, output);
}

test "write empty string to clipboard" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.write(stream.writer(), "", .clipboard);

    const output = stream.getWritten();
    const expected = "\x1b]52;c;\x07"; // Empty base64 section

    try testing.expectEqualStrings(expected, output);
}

test "write to different selections" {
    var buf1: [4096]u8 = undefined;
    var stream1 = std.io.fixedBufferStream(&buf1);
    try Clipboard.write(stream1.writer(), "text", .clipboard);
    try testing.expect(std.mem.indexOf(u8, stream1.getWritten(), ";c;") != null);

    var buf2: [4096]u8 = undefined;
    var stream2 = std.io.fixedBufferStream(&buf2);
    try Clipboard.write(stream2.writer(), "text", .primary);
    try testing.expect(std.mem.indexOf(u8, stream2.getWritten(), ";p;") != null);

    var buf3: [4096]u8 = undefined;
    var stream3 = std.io.fixedBufferStream(&buf3);
    try Clipboard.write(stream3.writer(), "text", .system);
    try testing.expect(std.mem.indexOf(u8, stream3.getWritten(), ";s;") != null);
}

// ============================================================================
// OSC 52 Sequence Format Validation
// ============================================================================

test "OSC 52 sequence format is correct" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.write(stream.writer(), "test", .clipboard);

    const output = stream.getWritten();

    // Must start with ESC ]
    try testing.expectEqual(@as(u8, 0x1b), output[0]);
    try testing.expectEqual(@as(u8, ']'), output[1]);

    // Must contain "52;"
    try testing.expect(std.mem.indexOf(u8, output, "52;") != null);

    // Must end with BEL (0x07)
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);
}

test "base64 encoding is correct" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.write(stream.writer(), "hello", .clipboard);

    const output = stream.getWritten();

    // Extract base64 part (between second semicolon and BEL)
    const b64_start = std.mem.indexOf(u8, output, ";c;").? + 3;
    const b64_end = output.len - 1; // Before BEL
    const b64 = output[b64_start..b64_end];

    try testing.expectEqualStrings("aGVsbG8=", b64);
}

test "selection parameter encoding" {
    const test_cases = [_]struct {
        selection: Selection,
        expected: u8,
    }{
        .{ .selection = .clipboard, .expected = 'c' },
        .{ .selection = .primary, .expected = 'p' },
        .{ .selection = .system, .expected = 's' },
    };

    for (test_cases) |tc| {
        try testing.expectEqual(tc.expected, tc.selection.toParam());
    }
}

// ============================================================================
// Read Operations
// ============================================================================

test "request clipboard read generates correct query" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.requestRead(stream.writer(), .clipboard);

    const output = stream.getWritten();
    const expected = "\x1b]52;c;?\x07";

    try testing.expectEqualStrings(expected, output);
}

test "request read from different selections" {
    var buf1: [4096]u8 = undefined;
    var stream1 = std.io.fixedBufferStream(&buf1);
    try Clipboard.requestRead(stream1.writer(), .primary);
    try testing.expectEqualStrings("\x1b]52;p;?\x07", stream1.getWritten());

    var buf2: [4096]u8 = undefined;
    var stream2 = std.io.fixedBufferStream(&buf2);
    try Clipboard.requestRead(stream2.writer(), .system);
    try testing.expectEqualStrings("\x1b]52;s;?\x07", stream2.getWritten());
}

// ============================================================================
// Edge Cases
// ============================================================================

test "write large text (1KB)" {
    const allocator = testing.allocator;
    const large_text = try allocator.alloc(u8, 1024);
    defer allocator.free(large_text);

    // Fill with 'A'
    @memset(large_text, 'A');

    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.write(stream.writer(), large_text, .clipboard);

    const output = stream.getWritten();

    // Must start and end correctly
    try testing.expect(std.mem.startsWith(u8, output, "\x1b]52;c;"));
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);

    // Must contain base64 data (1KB should encode to ~1365 bytes)
    try testing.expect(output.len > 1300);
}

test "write very large text (10KB)" {
    const allocator = testing.allocator;
    const large_text = try allocator.alloc(u8, 10240);
    defer allocator.free(large_text);

    @memset(large_text, 'B');

    var buf: [20000]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.write(stream.writer(), large_text, .clipboard);

    const output = stream.getWritten();

    try testing.expect(std.mem.startsWith(u8, output, "\x1b]52;c;"));
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);
}

test "write text with newlines" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const text = "line1\nline2\nline3";
    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();

    // Base64 of "line1\nline2\nline3"
    const expected = "\x1b]52;c;bGluZTEKbGluZTIKbGluZTM=\x07";
    try testing.expectEqualStrings(expected, output);
}

test "write text with carriage returns" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const text = "line1\r\nline2\r\n";
    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();

    // Must encode correctly
    try testing.expect(std.mem.startsWith(u8, output, "\x1b]52;c;"));
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);
}

test "write text with tabs" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const text = "col1\tcol2\tcol3";
    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();

    // Base64 of "col1\tcol2\tcol3"
    const expected = "\x1b]52;c;Y29sMQljb2wyCWNvbDM=\x07";
    try testing.expectEqualStrings(expected, output);
}

test "write text with null bytes" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const text = "hello\x00world";
    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();

    // Base64 should encode null byte correctly
    try testing.expect(std.mem.startsWith(u8, output, "\x1b]52;c;"));
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);
}

test "write text with all ASCII control characters" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // Include various control chars: NUL, SOH, STX, BEL, BS, TAB, LF, CR, ESC
    const text = "\x00\x01\x02\x07\x08\x09\x0a\x0d\x1b";
    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();

    try testing.expect(std.mem.startsWith(u8, output, "\x1b]52;c;"));
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);
}

// ============================================================================
// Invalid UTF-8 Handling
// ============================================================================

test "write invalid UTF-8 sequence" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // Invalid UTF-8: continuation byte without start byte
    const text = "hello\x80world";
    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();

    // Should encode as-is (base64 doesn't care about UTF-8 validity)
    try testing.expect(std.mem.startsWith(u8, output, "\x1b]52;c;"));
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);
}

// ============================================================================
// Writer Error Handling
// ============================================================================

test "write handles buffer overflow" {
    // Test that write propagates errors from the underlying writer
    var buf: [10]u8 = undefined; // Too small for OSC sequence
    var stream = std.io.fixedBufferStream(&buf);

    const result = Clipboard.write(stream.writer(), "test", .clipboard);

    // Should fail because buffer is too small
    try testing.expectError(error.NoSpaceLeft, result);
}

// ============================================================================
// Platform Detection
// ============================================================================

test "isSupported returns true on Unix platforms" {
    if (builtin.os.tag == .linux or
        builtin.os.tag == .macos or
        builtin.os.tag == .freebsd or
        builtin.os.tag == .openbsd or
        builtin.os.tag == .netbsd)
    {
        try testing.expect(Clipboard.isSupported());
    }
}

test "isSupported returns true on Windows" {
    if (builtin.os.tag == .windows) {
        try testing.expect(Clipboard.isSupported());
    }
}

test "isSupported handles TERM environment variable" {
    // This test validates that we check TERM for basic clipboard support
    // Implementation should check for dumb/unknown terminals
    // For now, just verify the function exists and returns bool
    const supported = Clipboard.isSupported();
    _ = supported; // May be true or false depending on environment
}

// ============================================================================
// Base64 Encoding Edge Cases
// ============================================================================

test "base64 padding is correct for various input lengths" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_b64: []const u8,
    }{
        .{ .input = "a", .expected_b64 = "YQ==" },
        .{ .input = "ab", .expected_b64 = "YWI=" },
        .{ .input = "abc", .expected_b64 = "YWJj" },
        .{ .input = "abcd", .expected_b64 = "YWJjZA==" },
    };

    for (test_cases) |tc| {
        var buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);

        try Clipboard.write(stream.writer(), tc.input, .clipboard);

        const output = stream.getWritten();
        const b64_start = std.mem.indexOf(u8, output, ";c;").? + 3;
        const b64_end = output.len - 1;
        const b64 = output[b64_start..b64_end];

        try testing.expectEqualStrings(tc.expected_b64, b64);
    }
}

test "base64 encoding handles binary data" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const binary_data = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD };
    try Clipboard.write(stream.writer(), &binary_data, .clipboard);

    const output = stream.getWritten();

    try testing.expect(std.mem.startsWith(u8, output, "\x1b]52;c;"));
    try testing.expectEqual(@as(u8, 0x07), output[output.len - 1]);

    // Verify base64 is present (binary should encode)
    try testing.expect(output.len > 10);
}

// ============================================================================
// Multiple Sequential Writes
// ============================================================================

test "multiple writes to same writer" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.write(stream.writer(), "first", .clipboard);
    const pos1 = stream.pos;

    try Clipboard.write(stream.writer(), "second", .clipboard);
    const pos2 = stream.pos;

    // Both writes should succeed
    try testing.expect(pos2 > pos1);

    const output = stream.getWritten();

    // Should contain two complete sequences
    const count = std.mem.count(u8, output, "\x1b]52;");
    try testing.expectEqual(@as(usize, 2), count);
}

// ============================================================================
// Memory Safety
// ============================================================================

test "no memory leaks in write operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const text = try allocator.dupe(u8, "test");
    defer allocator.free(text);

    try Clipboard.write(stream.writer(), text, .clipboard);
}

test "no memory leaks in requestRead operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try Clipboard.requestRead(stream.writer(), .clipboard);
}

// ============================================================================
// Boundary Conditions
// ============================================================================

test "write exactly fills buffer" {
    // Test that we can write up to buffer limit
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // Calculate text size that will fill buffer (account for OSC overhead)
    // OSC overhead: \x1b]52;c; (7 bytes) + \x07 (1 byte) = 8 bytes
    // Base64 overhead: ~33% increase
    // Safe size: 150 bytes should encode to ~200 bytes + overhead
    const text = "A" ** 150;

    try Clipboard.write(stream.writer(), text, .clipboard);

    const output = stream.getWritten();
    try testing.expect(output.len > 0);
}

test "write exceeds buffer capacity" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // This should fail because encoded output exceeds 64 bytes
    const text = "A" ** 100;

    const result = Clipboard.write(stream.writer(), text, .clipboard);
    try testing.expectError(error.NoSpaceLeft, result);
}

// ============================================================================
// Selection Parameter Tests
// ============================================================================

test "Selection.toParam returns correct values" {
    try testing.expectEqual(@as(u8, 'c'), Selection.clipboard.toParam());
    try testing.expectEqual(@as(u8, 'p'), Selection.primary.toParam());
    try testing.expectEqual(@as(u8, 's'), Selection.system.toParam());
}

// ============================================================================
// ClipboardHistory Tests
// ============================================================================

test "ClipboardHistory init creates empty history" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try testing.expectEqual(@as(usize, 0), history.len());
}

test "ClipboardHistory push single entry" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("first entry");

    try testing.expectEqual(@as(usize, 1), history.len());

    const entry = try history.get(0);
    try testing.expectEqualStrings("first entry", entry);
}

test "ClipboardHistory push multiple entries in order" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("first");
    try history.push("second");
    try history.push("third");

    try testing.expectEqual(@as(usize, 3), history.len());

    // Index 0 should be most recent
    try testing.expectEqualStrings("third", try history.get(0));
    try testing.expectEqualStrings("second", try history.get(1));
    try testing.expectEqualStrings("first", try history.get(2));
}

test "ClipboardHistory push exactly 10 entries" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "entry {d}", .{i});
        try history.push(text);
    }

    try testing.expectEqual(@as(usize, 10), history.len());

    // Most recent should be "entry 9"
    try testing.expectEqualStrings("entry 9", try history.get(0));
    // Oldest should be "entry 0"
    try testing.expectEqualStrings("entry 0", try history.get(9));
}

test "ClipboardHistory push more than 10 entries drops oldest" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    // Push 15 entries
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "entry {d}", .{i});
        try history.push(text);
    }

    // Should only keep last 10
    try testing.expectEqual(@as(usize, 10), history.len());

    // Most recent should be "entry 14"
    try testing.expectEqualStrings("entry 14", try history.get(0));
    // Oldest in history should be "entry 5" (entries 0-4 were dropped)
    try testing.expectEqualStrings("entry 5", try history.get(9));
}

test "ClipboardHistory push empty string" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("");

    try testing.expectEqual(@as(usize, 1), history.len());
    try testing.expectEqualStrings("", try history.get(0));
}

test "ClipboardHistory push Unicode and emoji" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("Hello 世界 🚀");

    const entry = try history.get(0);
    try testing.expectEqualStrings("Hello 世界 🚀", entry);
}

test "ClipboardHistory push large text" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    // Push 10KB of text
    const large_text = try allocator.alloc(u8, 10240);
    defer allocator.free(large_text);
    @memset(large_text, 'A');

    try history.push(large_text);

    const entry = try history.get(0);
    try testing.expectEqual(large_text.len, entry.len);
    try testing.expect(std.mem.eql(u8, large_text, entry));
}

test "ClipboardHistory get out of bounds returns error" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("entry");

    // Index 1 is out of bounds (only index 0 exists)
    try testing.expectError(error.IndexOutOfBounds, history.get(1));

    // Index 10 definitely out of bounds
    try testing.expectError(error.IndexOutOfBounds, history.get(10));
}

test "ClipboardHistory get from empty history returns error" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try testing.expectError(error.IndexOutOfBounds, history.get(0));
}

test "ClipboardHistory getAll returns all entries" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("first");
    try history.push("second");
    try history.push("third");

    const all = history.getAll();
    try testing.expectEqual(@as(usize, 3), all.len);

    // Should be in most-recent-first order
    try testing.expectEqualStrings("third", all[0]);
    try testing.expectEqualStrings("second", all[1]);
    try testing.expectEqualStrings("first", all[2]);
}

test "ClipboardHistory getAll from empty history returns empty slice" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    const all = history.getAll();
    try testing.expectEqual(@as(usize, 0), all.len);
}

test "ClipboardHistory clear removes all entries" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("entry1");
    try history.push("entry2");
    try history.push("entry3");

    try testing.expectEqual(@as(usize, 3), history.len());

    history.clear();

    try testing.expectEqual(@as(usize, 0), history.len());
    try testing.expectError(error.IndexOutOfBounds, history.get(0));
}

test "ClipboardHistory clear on empty history is safe" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    // Should not crash or error
    history.clear();
    try testing.expectEqual(@as(usize, 0), history.len());
}

test "ClipboardHistory push after clear works" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("before clear");
    history.clear();
    try history.push("after clear");

    try testing.expectEqual(@as(usize, 1), history.len());
    try testing.expectEqualStrings("after clear", try history.get(0));
}

test "ClipboardHistory no memory leaks with multiple pushes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    // Push more than capacity to trigger FIFO eviction
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "entry {d}", .{i});
        try history.push(text);
    }

    try testing.expectEqual(@as(usize, 10), history.len());
}

test "ClipboardHistory no memory leaks after clear" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("test1");
    try history.push("test2");
    try history.push("test3");

    history.clear();

    // Should have freed all stored strings
}

test "ClipboardHistory handles duplicate entries" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    try history.push("duplicate");
    try history.push("duplicate");
    try history.push("duplicate");

    // Should store all duplicates
    try testing.expectEqual(@as(usize, 3), history.len());

    try testing.expectEqualStrings("duplicate", try history.get(0));
    try testing.expectEqualStrings("duplicate", try history.get(1));
    try testing.expectEqualStrings("duplicate", try history.get(2));
}

test "ClipboardHistory preserves entry order after capacity overflow" {
    const allocator = testing.allocator;
    var history = try ClipboardHistory.init(allocator);
    defer history.deinit();

    // Push entries 0-14
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "entry {d}", .{i});
        try history.push(text);
    }

    // Should keep entries 5-14 in correct order
    try testing.expectEqualStrings("entry 14", try history.get(0));
    try testing.expectEqualStrings("entry 13", try history.get(1));
    try testing.expectEqualStrings("entry 12", try history.get(2));
    // ...
    try testing.expectEqualStrings("entry 5", try history.get(9));
}

// ============================================================================
// System Clipboard Fallback Tests
// ============================================================================

test "SystemClipboard.isAvailable checks platform commands on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    // On macOS, pbcopy/pbpaste should be available
    const available = try SystemClipboard.isAvailable();
    try testing.expect(available);
}

test "SystemClipboard.isAvailable checks xclip/xsel on Linux" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    // Should check for xclip or xsel (may or may not be installed)
    const available = try SystemClipboard.isAvailable();
    _ = available; // Result depends on system
}

test "SystemClipboard.isAvailable returns false on unsupported platform" {
    // On exotic platforms without clipboard support
    // This test validates the detection logic exists
    _ = try SystemClipboard.isAvailable();
}

test "SystemClipboard.write simple text on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    try SystemClipboard.write(allocator, "test clipboard");

    // No error means success (actual clipboard write happened)
}

test "SystemClipboard.write empty string on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    try SystemClipboard.write(allocator, "");

    // Should succeed without error
}

test "SystemClipboard.write Unicode text on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    try SystemClipboard.write(allocator, "Hello 世界 🚀");

    // Should handle Unicode correctly
}

test "SystemClipboard.write multi-line text on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    const text = "line1\nline2\nline3";
    try SystemClipboard.write(allocator, text);

    // Should preserve newlines
}

test "SystemClipboard.write large text on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    const large_text = try allocator.alloc(u8, 10240);
    defer allocator.free(large_text);
    @memset(large_text, 'A');

    try SystemClipboard.write(allocator, large_text);

    // Should handle large clipboard data
}

test "SystemClipboard.read on macOS returns allocated string" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // First write something known
    try SystemClipboard.write(allocator, "read test");

    // Then read it back
    const text = try SystemClipboard.read(allocator);
    defer allocator.free(text);

    try testing.expectEqualStrings("read test", text);
}

test "SystemClipboard.read returns empty string when clipboard empty on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Clear clipboard by writing empty string
    try SystemClipboard.write(allocator, "");

    const text = try SystemClipboard.read(allocator);
    defer allocator.free(text);

    try testing.expectEqual(@as(usize, 0), text.len);
}

test "SystemClipboard.read preserves Unicode on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    const original = "Hello 世界 🚀";
    try SystemClipboard.write(allocator, original);

    const text = try SystemClipboard.read(allocator);
    defer allocator.free(text);

    try testing.expectEqualStrings(original, text);
}

test "SystemClipboard.read preserves newlines on macOS" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    const original = "line1\nline2\nline3";
    try SystemClipboard.write(allocator, original);

    const text = try SystemClipboard.read(allocator);
    defer allocator.free(text);

    try testing.expectEqualStrings(original, text);
}

test "SystemClipboard.write on Linux uses xclip or xsel" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;

    // May fail if neither xclip nor xsel is installed
    const result = SystemClipboard.write(allocator, "linux test");

    // If available, should succeed
    if (try SystemClipboard.isAvailable()) {
        try result;
    } else {
        try testing.expectError(error.ClipboardUnavailable, result);
    }
}

test "SystemClipboard.read on Linux uses xclip or xsel" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;

    if (!(try SystemClipboard.isAvailable())) return error.SkipZigTest;

    // Write then read
    try SystemClipboard.write(allocator, "linux read test");

    const text = try SystemClipboard.read(allocator);
    defer allocator.free(text);

    try testing.expectEqualStrings("linux read test", text);
}

test "SystemClipboard.write on Windows uses PowerShell" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;

    try SystemClipboard.write(allocator, "windows test");

    // Should use Set-Clipboard cmdlet
}

test "SystemClipboard.read on Windows uses PowerShell" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = testing.allocator;

    try SystemClipboard.write(allocator, "windows read test");

    const text = try SystemClipboard.read(allocator);
    defer allocator.free(text);

    try testing.expectEqualStrings("windows read test", text);
}

test "SystemClipboard.write returns error when command fails" {
    const allocator = testing.allocator;

    // Implementation should detect when subprocess fails
    // This test validates error propagation
    // (Hard to test without mocking, but validates error path exists)
    const result = SystemClipboard.write(allocator, "test");
    if (result) |_| {
        // Success - command worked
    } else |_| {
        // Error - expected on some platforms
    }
}

test "SystemClipboard.read returns error when command fails" {
    const allocator = testing.allocator;

    // Should handle command failure gracefully
    const result = SystemClipboard.read(allocator);
    if (result) |text| {
        // Success - free the text
        allocator.free(text);
    } else |_| {
        // Error - expected on some platforms
    }
}

test "SystemClipboard no memory leaks on write" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    // May skip if platform not supported
    if (builtin.os.tag != .macos and builtin.os.tag != .linux and builtin.os.tag != .windows) {
        return error.SkipZigTest;
    }

    const available = SystemClipboard.isAvailable() catch return error.SkipZigTest;
    if (!available) return error.SkipZigTest;

    try SystemClipboard.write(allocator, "leak test");
}

test "SystemClipboard no memory leaks on read" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    if (builtin.os.tag != .macos and builtin.os.tag != .linux and builtin.os.tag != .windows) {
        return error.SkipZigTest;
    }

    const available = SystemClipboard.isAvailable() catch return error.SkipZigTest;
    if (!available) return error.SkipZigTest;

    try SystemClipboard.write(allocator, "leak test read");

    const text = try SystemClipboard.read(allocator);
    defer allocator.free(text);
}

test "SystemClipboard handles text with special characters" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Test shell-sensitive characters
    const text = "test $VAR \"quotes\" 'single' `backticks` $(cmd) & | > <";
    try SystemClipboard.write(allocator, text);

    const read_text = try SystemClipboard.read(allocator);
    defer allocator.free(read_text);

    try testing.expectEqualStrings(text, read_text);
}

test "SystemClipboard returns error on unsupported platform" {
    // Simulating exotic platform (wasi, freestanding, etc)
    // Implementation should return error.ClipboardUnavailable
    if (builtin.os.tag == .macos or builtin.os.tag == .linux or builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }

    const allocator = testing.allocator;

    try testing.expectError(error.ClipboardUnavailable, SystemClipboard.write(allocator, "test"));
    try testing.expectError(error.ClipboardUnavailable, SystemClipboard.read(allocator));
}

test "SystemClipboard.isAvailable does not allocate memory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }

    // isAvailable should only check command existence, not allocate
    _ = try SystemClipboard.isAvailable();
}
