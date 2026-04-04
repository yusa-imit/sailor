//! Enhanced paste handling utilities for multi-line paste operations
//!
//! Provides higher-level utilities for working with bracketed paste mode:
//! - Extract pasted content from bracketed buffer
//! - Handle multi-line paste safely
//! - Integrate with existing input handling
//! - Provide streaming paste reader
//!
//! Requires bracketed paste mode to be enabled (see term.BracketedPaste).
//! Paste content is wrapped with \x1b[200~ (start) and \x1b[201~ (end).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Paste handling utilities
pub const PasteHandler = struct {
    const start_marker = "\x1b[200~";
    const end_marker = "\x1b[201~";

    /// Extract paste content from buffer containing bracketed paste markers.
    /// Returns slice between \x1b[200~ and \x1b[201~ markers.
    /// Returns error if markers not found or malformed.
    pub fn extractPaste(buffer: []const u8) ![]const u8 {
        const start_pos = findPasteStart(buffer) orelse return error.MissingStartMarker;
        const end_pos = findPasteEnd(buffer) orelse return error.MissingEndMarker;

        if (end_pos < start_pos) return error.MalformedPaste;

        return buffer[start_pos..end_pos];
    }

    /// Check if buffer contains complete paste (both start and end markers).
    pub fn hasCompletePaste(buffer: []const u8) bool {
        return findPasteStart(buffer) != null and findPasteEnd(buffer) != null;
    }

    /// Find paste start position in buffer (returns index after \x1b[200~).
    pub fn findPasteStart(buffer: []const u8) ?usize {
        if (std.mem.indexOf(u8, buffer, start_marker)) |idx| {
            return idx + start_marker.len;
        }
        return null;
    }

    /// Find paste end position in buffer (returns index before \x1b[201~).
    pub fn findPasteEnd(buffer: []const u8) ?usize {
        if (std.mem.indexOf(u8, buffer, end_marker)) |idx| {
            return idx;
        }
        return null;
    }

    /// Split multi-line paste into lines.
    /// Allocates slice of lines, caller owns memory.
    pub fn splitLines(allocator: Allocator, paste: []const u8) ![][]const u8 {
        if (paste.len == 0) {
            const lines = try allocator.alloc([]const u8, 1);
            lines[0] = "";
            return lines;
        }

        // Count lines by scanning for line terminators
        var line_count: usize = 1; // At least one line
        var i: usize = 0;
        while (i < paste.len) : (i += 1) {
            if (paste[i] == '\n') {
                line_count += 1;
            } else if (paste[i] == '\r') {
                // Check if next char is \n (CRLF)
                if (i + 1 < paste.len and paste[i + 1] == '\n') {
                    i += 1; // Skip the \n
                }
                line_count += 1;
            }
        }

        // Allocate array for line slices
        const lines = try allocator.alloc([]const u8, line_count);
        errdefer allocator.free(lines);

        // Extract line slices
        var line_idx: usize = 0;
        var line_start: usize = 0;
        i = 0;
        while (i < paste.len) : (i += 1) {
            const is_lf = paste[i] == '\n';
            const is_cr = paste[i] == '\r';

            if (is_lf or is_cr) {
                lines[line_idx] = paste[line_start..i];
                line_idx += 1;

                // Handle CRLF
                if (is_cr and i + 1 < paste.len and paste[i + 1] == '\n') {
                    i += 1;
                }

                line_start = i + 1;
            }
        }

        // Add final line if there's content after last newline
        if (line_start < paste.len) {
            lines[line_idx] = paste[line_start..];
        } else if (line_idx < line_count) {
            // If paste ends with newline, add empty last line
            lines[line_idx] = "";
        }

        return lines;
    }

    /// Process paste content with callback for each line.
    /// No allocation - streams lines to callback.
    pub fn processLines(paste: []const u8, callback: fn ([]const u8) void) void {
        if (paste.len == 0) {
            callback("");
            return;
        }

        var line_start: usize = 0;
        var i: usize = 0;
        while (i < paste.len) : (i += 1) {
            const is_lf = paste[i] == '\n';
            const is_cr = paste[i] == '\r';

            if (is_lf or is_cr) {
                callback(paste[line_start..i]);

                // Handle CRLF
                if (is_cr and i + 1 < paste.len and paste[i + 1] == '\n') {
                    i += 1;
                }

                line_start = i + 1;
            }
        }

        // Process final line
        if (line_start < paste.len) {
            callback(paste[line_start..]);
        } else if (line_start == paste.len and paste.len > 0) {
            // Trailing newline creates empty last line
            callback("");
        }
    }
};

/// Streaming paste reader for handling large pastes
pub const PasteReader = struct {
    buffer: []const u8,
    paste_start: ?usize,
    paste_end: ?usize,
    read_pos: usize,

    const start_marker = "\x1b[200~";
    const end_marker = "\x1b[201~";

    /// Initialize reader with input buffer.
    pub fn init(buffer: []const u8) PasteReader {
        const paste_start = PasteHandler.findPasteStart(buffer);
        const paste_end = PasteHandler.findPasteEnd(buffer);

        return PasteReader{
            .buffer = buffer,
            .paste_start = paste_start,
            .paste_end = paste_end,
            .read_pos = paste_start orelse 0,
        };
    }

    /// Read next chunk of paste content.
    /// Returns null when paste ends or no more data.
    pub fn next(self: *PasteReader) ?[]const u8 {
        // No paste markers found
        if (self.paste_start == null or self.paste_end == null) {
            return null;
        }

        const start = self.paste_start.?;
        const end = self.paste_end.?;

        // Already read all content
        if (self.read_pos >= end) {
            return null;
        }

        // Return entire paste content in one chunk
        const content = self.buffer[start..end];
        self.read_pos = end;
        return content;
    }

    /// Reset reader to beginning.
    pub fn reset(self: *PasteReader) void {
        self.read_pos = self.paste_start orelse 0;
    }
};

// ============================================================================
// TESTS - Following TDD: Write FAILING tests first
// ============================================================================

// 1. Basic Extraction Tests (5 tests)

test "extract single-line paste" {
    const input = "\x1b[200~hello world\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("hello world", result);
}

test "extract multi-line paste" {
    const input = "\x1b[200~line1\nline2\nline3\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("line1\nline2\nline3", result);
}

test "extract paste with special characters" {
    const input = "\x1b[200~tab\there\r\nwindows\nnewline\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("tab\there\r\nwindows\nnewline", result);
}

test "extract empty paste" {
    const input = "\x1b[200~\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("", result);
}

test "extract paste with unicode and emoji" {
    const input = "\x1b[200~Hello 世界 🌍\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("Hello 世界 🌍", result);
}

// 2. Marker Detection Tests (6 tests)

test "hasCompletePaste returns true for complete paste" {
    const input = "\x1b[200~content\x1b[201~";
    try std.testing.expect(PasteHandler.hasCompletePaste(input));
}

test "hasCompletePaste returns false for only start marker" {
    const input = "\x1b[200~content without end";
    try std.testing.expect(!PasteHandler.hasCompletePaste(input));
}

test "hasCompletePaste returns false for only end marker" {
    const input = "content without start\x1b[201~";
    try std.testing.expect(!PasteHandler.hasCompletePaste(input));
}

test "hasCompletePaste returns false for no markers" {
    const input = "plain text without markers";
    try std.testing.expect(!PasteHandler.hasCompletePaste(input));
}

test "findPasteStart returns correct position" {
    const input = "prefix\x1b[200~content\x1b[201~";
    const start = PasteHandler.findPasteStart(input);
    try std.testing.expect(start != null);
    try std.testing.expectEqual(@as(usize, 12), start.?); // After "prefix\x1b[200~"
}

test "findPasteEnd returns correct position" {
    const input = "prefix\x1b[200~content\x1b[201~suffix";
    const end = PasteHandler.findPasteEnd(input);
    try std.testing.expect(end != null);
    try std.testing.expectEqual(@as(usize, 19), end.?); // Before "\x1b[201~suffix"
}

// 3. Error Cases Tests (5 tests)

test "extractPaste errors on missing start marker" {
    const input = "no start marker\x1b[201~";
    const result = PasteHandler.extractPaste(input);
    try std.testing.expectError(error.MissingStartMarker, result);
}

test "extractPaste errors on missing end marker" {
    const input = "\x1b[200~no end marker";
    const result = PasteHandler.extractPaste(input);
    try std.testing.expectError(error.MissingEndMarker, result);
}

test "extractPaste errors on end before start" {
    const input = "\x1b[201~reversed\x1b[200~";
    const result = PasteHandler.extractPaste(input);
    try std.testing.expectError(error.MalformedPaste, result);
}

test "extractPaste handles multiple paste sequences" {
    // Should extract first paste only
    const input = "\x1b[200~first\x1b[201~\x1b[200~second\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("first", result);
}

test "extractPaste handles markers in reversed order" {
    const input = "text\x1b[201~middle\x1b[200~text";
    const result = PasteHandler.extractPaste(input);
    try std.testing.expectError(error.MalformedPaste, result);
}

// 4. Line Splitting Tests (6 tests)

test "splitLines handles LF line endings" {
    const allocator = std.testing.allocator;
    const input = "line1\nline2\nline3";
    const lines = try PasteHandler.splitLines(allocator, input);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("line2", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
}

test "splitLines handles CRLF line endings" {
    const allocator = std.testing.allocator;
    const input = "line1\r\nline2\r\nline3";
    const lines = try PasteHandler.splitLines(allocator, input);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("line2", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
}

test "splitLines handles CR line endings" {
    const allocator = std.testing.allocator;
    const input = "line1\rline2\rline3";
    const lines = try PasteHandler.splitLines(allocator, input);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("line2", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
}

test "splitLines handles mixed line endings" {
    const allocator = std.testing.allocator;
    const input = "line1\nline2\r\nline3\rline4";
    const lines = try PasteHandler.splitLines(allocator, input);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 4), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("line2", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
    try std.testing.expectEqualStrings("line4", lines[3]);
}

test "splitLines preserves empty lines" {
    const allocator = std.testing.allocator;
    const input = "line1\n\nline3";
    const lines = try PasteHandler.splitLines(allocator, input);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
}

test "splitLines handles single-line input" {
    const allocator = std.testing.allocator;
    const input = "single line";
    const lines = try PasteHandler.splitLines(allocator, input);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 1), lines.len);
    try std.testing.expectEqualStrings("single line", lines[0]);
}

// 5. Line Processing Tests (3 tests)

test "processLines calls callback for each line" {
    const TestContext = struct {
        var count: usize = 0;

        fn callback(line: []const u8) void {
            count += 1;
            // In a real test, we'd verify the line content
            // For stub testing, just count calls
            _ = line;
        }
    };

    TestContext.count = 0;
    const input = "line1\nline2\nline3";
    PasteHandler.processLines(input, TestContext.callback);

    // Should be called 3 times for 3 lines
    try std.testing.expectEqual(@as(usize, 3), TestContext.count);
}

test "processLines handles empty input" {
    const TestContext = struct {
        var count: usize = 0;

        fn callback(line: []const u8) void {
            _ = line;
            count += 1;
        }
    };

    TestContext.count = 0;
    const input = "";
    PasteHandler.processLines(input, TestContext.callback);

    // Empty input should result in 1 callback with empty string
    try std.testing.expectEqual(@as(usize, 1), TestContext.count);
}

test "processLines handles trailing newline" {
    const TestContext = struct {
        var count: usize = 0;
        var last_empty: bool = false;

        fn callback(line: []const u8) void {
            count += 1;
            last_empty = line.len == 0;
        }
    };

    TestContext.count = 0;
    TestContext.last_empty = false;
    const input = "line1\nline2\n";
    PasteHandler.processLines(input, TestContext.callback);

    // Trailing newline should create 3 lines (line1, line2, empty)
    try std.testing.expectEqual(@as(usize, 3), TestContext.count);
    try std.testing.expect(TestContext.last_empty); // Last line should be empty
}

// 6. Streaming Reader Tests (6 tests)

test "PasteReader next returns content chunks" {
    const input = "\x1b[200~chunk1chunk2\x1b[201~";
    var reader = PasteReader.init(input);

    const chunk = reader.next();
    try std.testing.expect(chunk != null);
    try std.testing.expectEqualStrings("chunk1chunk2", chunk.?);
}

test "PasteReader next returns null after paste ends" {
    const input = "\x1b[200~content\x1b[201~";
    var reader = PasteReader.init(input);

    _ = reader.next(); // Read first chunk
    const second = reader.next();
    try std.testing.expect(second == null);
}

test "PasteReader reset allows re-reading" {
    const input = "\x1b[200~content\x1b[201~";
    var reader = PasteReader.init(input);

    const first = reader.next();
    try std.testing.expect(first != null);

    reader.reset();

    const second = reader.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings(first.?, second.?);
}

test "PasteReader ignores content before paste start" {
    const input = "prefix text\x1b[200~actual content\x1b[201~";
    var reader = PasteReader.init(input);

    const chunk = reader.next();
    try std.testing.expect(chunk != null);
    try std.testing.expectEqualStrings("actual content", chunk.?);
}

test "PasteReader stops at paste end marker" {
    const input = "\x1b[200~content\x1b[201~suffix";
    var reader = PasteReader.init(input);

    const chunk = reader.next();
    try std.testing.expect(chunk != null);
    try std.testing.expectEqualStrings("content", chunk.?);

    // Next call should return null (stopped at end marker)
    try std.testing.expect(reader.next() == null);
}

test "PasteReader handles buffer with no paste" {
    const input = "no paste markers here";
    var reader = PasteReader.init(input);

    const chunk = reader.next();
    try std.testing.expect(chunk == null);
}

// 7. Edge Cases Tests (5 tests)

test "paste at buffer start" {
    const input = "\x1b[200~content\x1b[201~suffix";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("content", result);
}

test "paste at buffer end" {
    const input = "prefix\x1b[200~content\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("content", result);
}

test "paste with content before and after markers" {
    const input = "before\x1b[200~pasted\x1b[201~after";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("pasted", result);
}

test "very large paste" {
    const allocator = std.testing.allocator;

    // Generate 10KB+ paste content
    const marker_start = "\x1b[200~";
    const marker_end = "\x1b[201~";
    const line = "0123456789\n";
    const line_count = 1000;
    const total_size = marker_start.len + (line.len * line_count) + marker_end.len;

    var large_paste = try allocator.alloc(u8, total_size);
    defer allocator.free(large_paste);

    @memcpy(large_paste[0..marker_start.len], marker_start);
    var offset = marker_start.len;
    var i: usize = 0;
    while (i < line_count) : (i += 1) {
        @memcpy(large_paste[offset .. offset + line.len], line);
        offset += line.len;
    }
    @memcpy(large_paste[offset .. offset + marker_end.len], marker_end);

    const result = try PasteHandler.extractPaste(large_paste);
    try std.testing.expect(result.len > 10000);
    try std.testing.expect(std.mem.startsWith(u8, result, "0123456789"));
}

test "nested or escaped markers in paste content" {
    // Paste content containing marker-like sequences should be preserved
    const input = "\x1b[200~content with \\x1b[200~ fake marker\x1b[201~";
    const result = try PasteHandler.extractPaste(input);
    try std.testing.expectEqualStrings("content with \\x1b[200~ fake marker", result);
}

// 8. Memory Safety Tests (2 tests)

test "no leaks in splitLines" {
    const allocator = std.testing.allocator;

    const input = "line1\nline2\nline3\nline4\nline5";
    const lines = try PasteHandler.splitLines(allocator, input);
    defer allocator.free(lines);

    // Test passes if no leak detected by testing allocator
    try std.testing.expectEqual(@as(usize, 5), lines.len);
}

test "processLines requires no allocations" {
    // This test verifies that processLines is truly zero-allocation
    // We can't easily test this without tracking allocations, but we can
    // verify it works without an allocator parameter

    const TestContext = struct {
        var count: usize = 0;

        fn callback(line: []const u8) void {
            _ = line;
            count += 1;
        }
    };

    TestContext.count = 0;
    const input = "line1\nline2\nline3";
    PasteHandler.processLines(input, TestContext.callback);

    try std.testing.expectEqual(@as(usize, 3), TestContext.count);
}
