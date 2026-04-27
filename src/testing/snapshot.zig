//! SnapshotRecorder — Capture and compare widget render output for regression testing
//!
//! Provides tools to:
//! - Convert Buffer to string snapshot
//! - Compare snapshots with exact or fuzzy matching
//! - Visualize differences between snapshots
//! - Support auto-update mode for approved changes
//!
//! This is essential for TUI widget testing — capture expected output once,
//! then verify future renders match the snapshot.

const std = @import("std");
const Allocator = std.mem.Allocator;
const tui = @import("../tui/tui.zig");
const Buffer = tui.Buffer;
const Cell = tui.Cell;
const Style = tui.Style;

/// Snapshot represents captured buffer content
pub const Snapshot = struct {
    content: []const u8,
    allocator: Allocator,

    /// Create snapshot from string content
    pub fn init(allocator: Allocator, content: []const u8) !Snapshot {
        const owned_content = try allocator.dupe(u8, content);
        return Snapshot{
            .content = owned_content,
            .allocator = allocator,
        };
    }

    /// Free snapshot resources
    pub fn deinit(self: *Snapshot) void {
        self.allocator.free(self.content);
    }

    /// Create deep copy of snapshot
    pub fn clone(self: *const Snapshot) !Snapshot {
        const cloned_content = try self.allocator.dupe(u8, self.content);
        return Snapshot{
            .content = cloned_content,
            .allocator = self.allocator,
        };
    }
};

/// Snapshot comparison and visualization tool
pub const SnapshotRecorder = struct {
    allocator: Allocator,

    /// Initialize recorder
    pub fn init(allocator: Allocator) SnapshotRecorder {
        return SnapshotRecorder{ .allocator = allocator };
    }

    /// Capture buffer as snapshot
    /// Converts buffer cells to string representation with newlines between rows
    pub fn captureBuffer(self: *SnapshotRecorder, buffer: *const Buffer) !Snapshot {
        const unicode_mod = @import("../unicode.zig");
        const UnicodeWidth = unicode_mod.UnicodeWidth;

        var result = std.ArrayList(u8){};
        defer result.deinit(self.allocator);

        var empty_buffer = true;
        for (0..buffer.height) |y| {
            var line = std.ArrayList(u8){};
            defer line.deinit(self.allocator);

            // Collect all characters in the row
            var x: usize = 0;
            while (x < buffer.width) {
                const cell = buffer.getConst(@intCast(x), @intCast(y)) orelse {
                    x += 1;
                    continue;
                };

                // Convert u21 codepoint to UTF-8 bytes
                var utf8_buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch {
                    x += 1;
                    continue;
                };
                try line.appendSlice(self.allocator, utf8_buf[0..len]);

                // Advance by character width (1 or 2 for wide characters)
                const char_width = UnicodeWidth.charWidth(cell.char);
                x += if (char_width > 0) char_width else 1;
            }

            // Trim trailing spaces from the line
            var trimmed = line.items;
            while (trimmed.len > 0 and trimmed[trimmed.len - 1] == ' ') {
                trimmed = trimmed[0 .. trimmed.len - 1];
            }

            // If line is non-empty or we already have content, add it
            if (trimmed.len > 0) {
                if (!empty_buffer) {
                    try result.append(self.allocator, '\n');
                }
                try result.appendSlice(self.allocator, trimmed);
                empty_buffer = false;
            } else if (!empty_buffer) {
                // Empty line in the middle of content - preserve it
                try result.append(self.allocator, '\n');
            }
        }

        const content = try result.toOwnedSlice(self.allocator);
        return Snapshot{
            .content = content,
            .allocator = self.allocator,
        };
    }

    /// Comparison mode
    pub const MatchMode = enum {
        exact, // Compare including styles
        fuzzy, // Compare text only, ignore styles
    };

    /// Check if two snapshots match
    pub fn matches(self: *SnapshotRecorder, a: *const Snapshot, b: *const Snapshot, mode: MatchMode) bool {
        _ = self;
        _ = mode; // For now, both exact and fuzzy do the same thing
        return std.mem.eql(u8, a.content, b.content);
    }

    /// Visualize differences between snapshots
    /// Writes color-coded diff to writer
    pub fn diff(self: *SnapshotRecorder, a: *const Snapshot, b: *const Snapshot, writer: anytype) !void {
        // Split both snapshots into lines
        var lines_a = std.ArrayList([]const u8){};
        defer lines_a.deinit(self.allocator);
        var lines_b = std.ArrayList([]const u8){};
        defer lines_b.deinit(self.allocator);

        var iter_a = std.mem.splitScalar(u8, a.content, '\n');
        while (iter_a.next()) |line| {
            try lines_a.append(self.allocator, line);
        }

        var iter_b = std.mem.splitScalar(u8, b.content, '\n');
        while (iter_b.next()) |line| {
            try lines_b.append(self.allocator, line);
        }

        // Simple line-by-line comparison
        const max_lines = @max(lines_a.items.len, lines_b.items.len);
        for (0..max_lines) |i| {
            const has_a = i < lines_a.items.len;
            const has_b = i < lines_b.items.len;

            if (has_a and has_b) {
                // Both snapshots have this line
                if (!std.mem.eql(u8, lines_a.items[i], lines_b.items[i])) {
                    // Lines differ - show deletion and addition
                    try writer.print("- {s}\n", .{lines_a.items[i]});
                    try writer.print("+ {s}\n", .{lines_b.items[i]});
                }
                // If lines match, show nothing
            } else if (has_a) {
                // Line exists in A but not in B (deletion)
                try writer.print("- {s}\n", .{lines_a.items[i]});
            } else if (has_b) {
                // Line exists in B but not in A (addition)
                try writer.print("+ {s}\n", .{lines_b.items[i]});
            }
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "Snapshot.init and deinit" {
    const content = "Hello, World!";
    var snapshot = try Snapshot.init(std.testing.allocator, content);
    defer snapshot.deinit();

    try std.testing.expectEqualStrings(content, snapshot.content);
}

test "Snapshot.init with empty string" {
    var snapshot = try Snapshot.init(std.testing.allocator, "");
    defer snapshot.deinit();

    try std.testing.expectEqualStrings("", snapshot.content);
}

test "Snapshot.clone creates independent copy" {
    const content = "Original content";
    var original = try Snapshot.init(std.testing.allocator, content);
    defer original.deinit();

    var cloned = try original.clone();
    defer cloned.deinit();

    try std.testing.expectEqualStrings(original.content, cloned.content);

    // Verify independence — modifying one doesn't affect the other
    // (This is a conceptual test — actual mutation would require different API)
    try std.testing.expect(original.content.ptr != cloned.content.ptr);
}

test "SnapshotRecorder.captureBuffer simple text" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);
    var buffer = try Buffer.init(std.testing.allocator, 10, 3);
    defer buffer.deinit();

    // Write some content
    buffer.setString(0, 0, "Hello", .{});
    buffer.setString(0, 1, "World", .{});
    buffer.setString(0, 2, "Test", .{});

    var snapshot = try recorder.captureBuffer(&buffer);
    defer snapshot.deinit();

    // Expected format: each row as a line
    // Trailing spaces should be trimmed for compactness
    const expected = "Hello\nWorld\nTest";
    try std.testing.expectEqualStrings(expected, snapshot.content);
}

test "SnapshotRecorder.captureBuffer empty buffer" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);
    var buffer = try Buffer.init(std.testing.allocator, 5, 2);
    defer buffer.deinit();

    var snapshot = try recorder.captureBuffer(&buffer);
    defer snapshot.deinit();

    // Empty buffer should produce empty or minimal output
    // Design choice: empty lines or single newline?
    // Let's expect empty string for completely empty buffer
    try std.testing.expectEqualStrings("", snapshot.content);
}

test "SnapshotRecorder.captureBuffer with unicode" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);
    var buffer = try Buffer.init(std.testing.allocator, 10, 2);
    defer buffer.deinit();

    buffer.setString(0, 0, "Hello 世界", .{});
    buffer.setString(0, 1, "Test ✓", .{});

    var snapshot = try recorder.captureBuffer(&buffer);
    defer snapshot.deinit();

    const expected = "Hello 世界\nTest ✓";
    try std.testing.expectEqualStrings(expected, snapshot.content);
}

test "SnapshotRecorder.matches exact mode identical" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer b.deinit();

    try std.testing.expect(recorder.matches(&a, &b, .exact));
}

test "SnapshotRecorder.matches exact mode mismatch" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello\nTest");
    defer b.deinit();

    try std.testing.expect(!recorder.matches(&a, &b, .exact));
}

test "SnapshotRecorder.matches fuzzy mode same text" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    // Fuzzy mode ignores style differences
    // For now, snapshots only contain text, so fuzzy == exact
    // This test will become meaningful when we encode styles in snapshots
    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer b.deinit();

    try std.testing.expect(recorder.matches(&a, &b, .fuzzy));
}

test "SnapshotRecorder.matches fuzzy mode different text" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Goodbye\nWorld");
    defer b.deinit();

    try std.testing.expect(!recorder.matches(&a, &b, .fuzzy));
}

test "SnapshotRecorder.matches empty snapshots" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "");
    defer b.deinit();

    try std.testing.expect(recorder.matches(&a, &b, .exact));
    try std.testing.expect(recorder.matches(&a, &b, .fuzzy));
}

test "SnapshotRecorder.diff identical snapshots" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer b.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);

    try recorder.diff(&a, &b, output.writer(std.testing.allocator));

    // Identical snapshots should produce no output or minimal "no changes" message
    // Design choice: empty output or "No differences"?
    // Let's expect empty output
    try std.testing.expectEqualStrings("", output.items);
}

test "SnapshotRecorder.diff with additions" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer b.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);

    try recorder.diff(&a, &b, output.writer(std.testing.allocator));

    // Should show added line with + prefix
    // Format: "+ World\n"
    try std.testing.expect(std.mem.indexOf(u8, output.items, "+ World") != null);
}

test "SnapshotRecorder.diff with deletions" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello");
    defer b.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);

    try recorder.diff(&a, &b, output.writer(std.testing.allocator));

    // Should show deleted line with - prefix
    // Format: "- World\n"
    try std.testing.expect(std.mem.indexOf(u8, output.items, "- World") != null);
}

test "SnapshotRecorder.diff with modifications" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello\nTest");
    defer b.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);

    try recorder.diff(&a, &b, output.writer(std.testing.allocator));

    // Should show both deletion and addition
    try std.testing.expect(std.mem.indexOf(u8, output.items, "- World") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "+ Test") != null);
}

test "SnapshotRecorder.diff multiline changes" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Line1\nLine2\nLine3");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Line1\nModified\nLine3\nLine4");
    defer b.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);

    try recorder.diff(&a, &b, output.writer(std.testing.allocator));

    // Should show Line2 deleted, Modified and Line4 added
    try std.testing.expect(std.mem.indexOf(u8, output.items, "- Line2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "+ Modified") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "+ Line4") != null);
}

test "SnapshotRecorder.captureBuffer preserves exact layout" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);
    var buffer = try Buffer.init(std.testing.allocator, 15, 2);
    defer buffer.deinit();

    // Write text with specific positioning
    buffer.setString(5, 0, "Right", .{});
    buffer.setString(0, 1, "Left", .{});

    var snapshot = try recorder.captureBuffer(&buffer);
    defer snapshot.deinit();

    // Snapshot should preserve spacing
    // Row 0: "     Right" (5 spaces + "Right")
    // Row 1: "Left"
    const expected = "     Right\nLeft";
    try std.testing.expectEqualStrings(expected, snapshot.content);
}

test "SnapshotRecorder.captureBuffer with styled text" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);
    var buffer = try Buffer.init(std.testing.allocator, 10, 2);
    defer buffer.deinit();

    // Write text with style
    const red_style = Style{ .fg = .red, .bold = true };
    buffer.setString(0, 0, "Styled", red_style);
    buffer.setString(0, 1, "Normal", .{});

    var snapshot = try recorder.captureBuffer(&buffer);
    defer snapshot.deinit();

    // For now, snapshot only captures text (styles ignored in basic implementation)
    // Future: encode styles in snapshot format
    const expected = "Styled\nNormal";
    try std.testing.expectEqualStrings(expected, snapshot.content);
}

test "SnapshotRecorder integration: widget render test" {
    // Integration test showing typical usage for widget testing
    var recorder = SnapshotRecorder.init(std.testing.allocator);
    var buffer = try Buffer.init(std.testing.allocator, 20, 5);
    defer buffer.deinit();

    // Simulate widget render
    buffer.setString(0, 0, "┌────────────────┐", .{});
    buffer.setString(0, 1, "│ Widget Title   │", .{});
    buffer.setString(0, 2, "├────────────────┤", .{});
    buffer.setString(0, 3, "│ Content here   │", .{});
    buffer.setString(0, 4, "└────────────────┘", .{});

    var snapshot = try recorder.captureBuffer(&buffer);
    defer snapshot.deinit();

    // Expected snapshot
    const expected =
        \\┌────────────────┐
        \\│ Widget Title   │
        \\├────────────────┤
        \\│ Content here   │
        \\└────────────────┘
    ;

    try std.testing.expectEqualStrings(expected, snapshot.content);
}

test "SnapshotRecorder.matches with whitespace differences" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Hello\nWorld");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "Hello \nWorld ");
    defer b.deinit();

    // Exact mode: trailing spaces matter
    try std.testing.expect(!recorder.matches(&a, &b, .exact));
}

test "SnapshotRecorder.diff empty to non-empty" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "New content");
    defer b.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);

    try recorder.diff(&a, &b, output.writer(std.testing.allocator));

    // Should show addition
    try std.testing.expect(std.mem.indexOf(u8, output.items, "+ New content") != null);
}

test "SnapshotRecorder.diff non-empty to empty" {
    var recorder = SnapshotRecorder.init(std.testing.allocator);

    var a = try Snapshot.init(std.testing.allocator, "Old content");
    defer a.deinit();

    var b = try Snapshot.init(std.testing.allocator, "");
    defer b.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);

    try recorder.diff(&a, &b, output.writer(std.testing.allocator));

    // Should show deletion
    try std.testing.expect(std.mem.indexOf(u8, output.items, "- Old content") != null);
}
