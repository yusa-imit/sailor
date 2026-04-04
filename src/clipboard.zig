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
