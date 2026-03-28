const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// ChunkedBuffer widget - efficient rendering for large text without loading entire content
/// Uses lazy loading via callback to fetch only visible lines
pub const ChunkedBuffer = struct {
    /// Total number of lines in the buffer
    total_lines: usize,
    /// Vertical scroll offset (index of first visible line)
    line_offset: usize = 0,
    /// Horizontal scroll offset (column position)
    column_offset: usize = 0,
    /// Optional block (border)
    block: ?Block = null,
    /// Text style for rendered content
    text_style: Style = .{},
    /// Enable text wrapping (vs truncation)
    wrap: bool = false,

    /// Callback type for fetching line text
    /// Takes line index and writes to writer
    pub const LineCallback = *const fn (line_index: usize, writer: anytype) anyerror!void;

    /// Create a ChunkedBuffer with total line count
    pub fn init(total: usize) ChunkedBuffer {
        return .{ .total_lines = total };
    }

    /// Set vertical scroll offset
    pub fn withLineOffset(self: ChunkedBuffer, offset: usize) ChunkedBuffer {
        var result = self;
        result.line_offset = offset;
        return result;
    }

    /// Set horizontal scroll offset
    pub fn withColumnOffset(self: ChunkedBuffer, offset: usize) ChunkedBuffer {
        var result = self;
        result.column_offset = offset;
        return result;
    }

    /// Set block
    pub fn withBlock(self: ChunkedBuffer, new_block: Block) ChunkedBuffer {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set text style
    pub fn withTextStyle(self: ChunkedBuffer, new_style: Style) ChunkedBuffer {
        var result = self;
        result.text_style = new_style;
        return result;
    }

    /// Enable/disable text wrapping
    pub fn withWrap(self: ChunkedBuffer, enable: bool) ChunkedBuffer {
        var result = self;
        result.wrap = enable;
        return result;
    }

    /// Render ChunkedBuffer using callback to fetch lines on-demand
    pub fn render(
        self: ChunkedBuffer,
        buf: *Buffer,
        area: Rect,
        comptime callback: LineCallback,
        allocator: std.mem.Allocator,
    ) !void {
        var render_area = area;

        // Render block if present
        if (self.block) |b| {
            b.render(buf, area);
            render_area = b.inner(area);
        }

        // Early exit for zero-size areas
        if (render_area.height == 0 or render_area.width == 0) return;

        // Calculate visible line range
        const start_line = @min(self.line_offset, self.total_lines);
        const max_visible = @min(self.total_lines - start_line, render_area.height);

        // Render only visible lines
        var y: u16 = 0;
        for (0..max_visible) |i| {
            const line_index = start_line + i;
            if (y >= render_area.height) break;

            // Fetch line content via callback
            var line_buf = std.ArrayList(u8){};
            defer line_buf.deinit(allocator);

            try callback(line_index, line_buf.writer(allocator));

            if (self.wrap) {
                // Wrap mode: render line with wrapping
                y = try self.renderLineWrapped(buf, render_area, line_buf.items, y, allocator);
            } else {
                // Truncate mode: render single line with horizontal offset
                try self.renderLineTruncated(buf, render_area, line_buf.items, y);
                y += 1;
            }
        }
    }

    /// Render a single line with truncation (horizontal scrolling)
    fn renderLineTruncated(
        self: ChunkedBuffer,
        buf: *Buffer,
        area: Rect,
        line_text: []const u8,
        y: u16,
    ) !void {
        // Apply horizontal offset
        var display_text = line_text;
        const skip_cols = self.column_offset;

        // Skip characters until we've passed column_offset display columns
        var byte_offset: usize = 0;
        var cols_skipped: usize = 0;
        while (byte_offset < line_text.len and cols_skipped < skip_cols) {
            const cp_len = std.unicode.utf8ByteSequenceLength(line_text[byte_offset]) catch 1;
            const cp_width = if (cp_len == 1) 1 else charWidth(line_text[byte_offset .. byte_offset + cp_len]);
            byte_offset += cp_len;
            cols_skipped += cp_width;
        }

        if (byte_offset < line_text.len) {
            display_text = line_text[byte_offset..];
        } else {
            display_text = "";
        }

        // Truncate to viewport width
        const max_width = area.width;
        var truncated = display_text;
        var width_used: usize = 0;
        var end_byte: usize = 0;

        while (end_byte < display_text.len and width_used < max_width) {
            const cp_len = std.unicode.utf8ByteSequenceLength(display_text[end_byte]) catch 1;
            if (end_byte + cp_len > display_text.len) break;

            const cp_width = if (cp_len == 1) 1 else charWidth(display_text[end_byte .. end_byte + cp_len]);
            if (width_used + cp_width > max_width) break;

            end_byte += cp_len;
            width_used += cp_width;
        }
        truncated = display_text[0..end_byte];

        buf.setString(area.x, area.y + y, truncated, self.text_style);
    }

    /// Render a single line with wrapping
    fn renderLineWrapped(
        self: ChunkedBuffer,
        buf: *Buffer,
        area: Rect,
        line_text: []const u8,
        start_y: u16,
        allocator: std.mem.Allocator,
    ) !u16 {
        _ = allocator;
        var y = start_y;
        const max_width = area.width;

        var byte_offset: usize = 0;
        while (byte_offset < line_text.len and y < area.height) {
            // Find chunk that fits in max_width
            var chunk_end = byte_offset;
            var width_used: usize = 0;

            while (chunk_end < line_text.len and width_used < max_width) {
                const cp_len = std.unicode.utf8ByteSequenceLength(line_text[chunk_end]) catch 1;
                if (chunk_end + cp_len > line_text.len) break;

                const cp_width = if (cp_len == 1) 1 else charWidth(line_text[chunk_end .. chunk_end + cp_len]);
                if (width_used + cp_width > max_width) break;

                chunk_end += cp_len;
                width_used += cp_width;
            }

            const chunk = line_text[byte_offset..chunk_end];
            buf.setString(area.x, area.y + y, chunk, self.text_style);

            byte_offset = chunk_end;
            y += 1;
        }

        return y;
    }

    /// Calculate display width of a character
    fn charWidth(cp_bytes: []const u8) usize {
        if (cp_bytes.len == 0) return 0;
        if (cp_bytes.len == 1) return 1; // ASCII

        const cp = std.unicode.utf8Decode(cp_bytes) catch return 1;

        // Wide characters (CJK, emoji) take 2 cells
        // This is a simplified check - real impl should use unicode width tables
        if (cp >= 0x1F300 and cp <= 0x1F9FF) return 2; // Emoji
        if (cp >= 0x4E00 and cp <= 0x9FFF) return 2; // CJK Unified Ideographs
        if (cp >= 0x3000 and cp <= 0x303F) return 2; // CJK Symbols
        if (cp >= 0xFF00 and cp <= 0xFFEF) return 2; // Fullwidth forms

        return 1;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ChunkedBuffer.init creates buffer with total line count" {
    const cb = ChunkedBuffer.init(1_000_000); // 1 million lines
    try testing.expectEqual(@as(usize, 1_000_000), cb.total_lines);
    try testing.expectEqual(@as(usize, 0), cb.line_offset);
    try testing.expectEqual(@as(usize, 0), cb.column_offset);
    try testing.expectEqual(@as(?Block, null), cb.block);
    try testing.expectEqual(false, cb.wrap);
}

test "ChunkedBuffer builder methods chain correctly" {
    const block = Block.init().withBorders(.all);
    const style = Style{ .fg = .{ .indexed = 2 } };

    const cb = ChunkedBuffer.init(100)
        .withLineOffset(10)
        .withColumnOffset(5)
        .withBlock(block)
        .withTextStyle(style)
        .withWrap(true);

    try testing.expectEqual(@as(usize, 10), cb.line_offset);
    try testing.expectEqual(@as(usize, 5), cb.column_offset);
    try testing.expect(cb.block != null);
    try testing.expectEqual(true, cb.wrap);
}

test "ChunkedBuffer.render displays only visible lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const cb = ChunkedBuffer.init(100); // 100 total lines

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should call callback exactly 10 times (viewport height)
    try testing.expectEqual(@as(usize, 10), call_count);
}

test "ChunkedBuffer.render writes correct line content to buffer" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("Line {d}", .{line_index});
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Verify line 0 contains "Line 0"
    const line0 = buf.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "Line 0") != null);

    // Verify line 2 contains "Line 2"
    const line2 = buf.getLine(2, 0, 40);
    defer allocator.free(line2);
    try testing.expect(std.mem.indexOf(u8, line2, "Line 2") != null);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

// 1. Zero/Empty Edge Cases

test "ChunkedBuffer.init with zero total lines" {
    const cb = ChunkedBuffer.init(0);
    try testing.expectEqual(@as(usize, 0), cb.total_lines);
}

test "ChunkedBuffer.render with zero-width area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    const cb = ChunkedBuffer.init(100);

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);
    // Should not call callback when width is zero
    try testing.expectEqual(@as(usize, 0), call_count);
}

test "ChunkedBuffer.render with zero-height area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };
    const cb = ChunkedBuffer.init(100);

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);
    // Should not call callback when height is zero
    try testing.expectEqual(@as(usize, 0), call_count);
}

test "ChunkedBuffer.render with zero total_lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const cb = ChunkedBuffer.init(0); // Zero lines

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);
    // Should not call callback when no lines exist
    try testing.expectEqual(@as(usize, 0), call_count);
}

// 2. Line Offset Edge Cases

test "ChunkedBuffer.render with line_offset equal to total_lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const cb = ChunkedBuffer.init(20).withLineOffset(20); // At boundary

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);
    // Should not render any lines when offset equals total
    try testing.expectEqual(@as(usize, 0), call_count);
}

test "ChunkedBuffer.render with line_offset beyond total_lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const cb = ChunkedBuffer.init(20).withLineOffset(50); // Beyond boundary

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);
    // Should not render any lines when offset exceeds total
    try testing.expectEqual(@as(usize, 0), call_count);
}

test "ChunkedBuffer.render with line_offset near end" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const cb = ChunkedBuffer.init(25).withLineOffset(22); // 3 lines remaining

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);
    // Should render only 3 lines (25 - 22)
    try testing.expectEqual(@as(usize, 3), call_count);
}

// 3. Column Offset Edge Cases

test "ChunkedBuffer.render with column_offset larger than line length" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    const cb = ChunkedBuffer.init(10).withColumnOffset(100); // Far beyond line

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            try writer.print("Line {d}", .{line_index});
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should render empty (scrolled past content)
    const line0 = buf.getLine(0, 0, 40);
    defer allocator.free(line0);
    // Line should be empty or contain no visible text
    try testing.expect(std.mem.trim(u8, line0, " ").len == 0);
}

test "ChunkedBuffer.render with column_offset in middle of multi-byte UTF-8" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    const cb = ChunkedBuffer.init(10).withColumnOffset(3); // Skip 3 columns

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("AB中文"); // ASCII + CJK
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should handle UTF-8 boundary correctly
    const line0 = buf.getLine(0, 0, 40);
    defer allocator.free(line0);
    // After skipping 3 columns (A=1, B=1, 中=2 partially), should show remaining
    try testing.expect(line0.len > 0); // Should render something without crashing
}

test "ChunkedBuffer.render with column_offset and wide characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    const cb = ChunkedBuffer.init(10).withColumnOffset(2); // Skip 2 display columns

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("😀X"); // Emoji (width 2) + ASCII
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should skip emoji (2 columns) and show X
    const line0 = buf.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "X") != null);
}

// 4. Truncation Mode Edge Cases

test "ChunkedBuffer truncation with line exactly fitting viewport width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("ABCDEFGHIJ"); // Exactly 10 chars
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 10);
    defer allocator.free(line0);
    try testing.expectEqualStrings("ABCDEFGHIJ", line0);
}

test "ChunkedBuffer truncation with line one character too long" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("ABCDEFGHIJK"); // 11 chars
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 10);
    defer allocator.free(line0);
    // Should truncate last character
    try testing.expect(std.mem.startsWith(u8, line0, "ABCDEFGHIJ"));
    try testing.expect(std.mem.indexOf(u8, line0, "K") == null);
}

test "ChunkedBuffer truncation with wide character at boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("ABCD中"); // 4 ASCII + 1 wide char (would overflow)
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 5);
    defer allocator.free(line0);
    // Should not split wide character - truncate before it
    try testing.expect(std.mem.startsWith(u8, line0, "ABCD"));
}

test "ChunkedBuffer truncation with empty line" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(_: usize, _: anytype) !void {
            // Write nothing
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 10);
    defer allocator.free(line0);
    // Empty line should render as spaces
    try testing.expect(std.mem.trim(u8, line0, " ").len == 0);
}

test "ChunkedBuffer truncation with line of only wide characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 6, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 6, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("中文测试"); // 4 CJK chars = 8 display columns
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 6);
    defer allocator.free(line0);
    // Should fit exactly 3 wide chars (6 columns)
    try testing.expect(std.mem.indexOf(u8, line0, "中") != null);
}

// 5. Wrapping Mode Edge Cases

test "ChunkedBuffer wrap with line wrapping exactly at viewport width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const cb = ChunkedBuffer.init(10).withWrap(true);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("ABCDEFGHIJKLMNO"); // 15 chars, should wrap to 2 lines
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 10);
    defer allocator.free(line0);
    try testing.expectEqualStrings("ABCDEFGHIJ", line0);

    const line1 = buf.getLine(1, 0, 10);
    defer allocator.free(line1);
    try testing.expect(std.mem.startsWith(u8, line1, "KLMNO"));
}

test "ChunkedBuffer wrap with line wrapping multiple times" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    const cb = ChunkedBuffer.init(10).withWrap(true);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("ABCDEFGHIJKLMNO"); // 15 chars / 5 width = 3 lines
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 5);
    defer allocator.free(line0);
    try testing.expectEqualStrings("ABCDE", line0);

    const line1 = buf.getLine(1, 0, 5);
    defer allocator.free(line1);
    try testing.expectEqualStrings("FGHIJ", line1);

    const line2 = buf.getLine(2, 0, 5);
    defer allocator.free(line2);
    try testing.expect(std.mem.startsWith(u8, line2, "KLMNO"));
}

test "ChunkedBuffer wrap with wide character at wrap boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const cb = ChunkedBuffer.init(10).withWrap(true);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("ABCD中EF"); // Wide char at position 4
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 5);
    defer allocator.free(line0);
    // Should not split wide character - wrap it to next line
    try testing.expect(std.mem.startsWith(u8, line0, "ABCD"));

    const line1 = buf.getLine(1, 0, 5);
    defer allocator.free(line1);
    // Wide char should be on second line
    try testing.expect(std.mem.indexOf(u8, line1, "中") != null);
}

test "ChunkedBuffer wrap with wide character wider than viewport" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 1, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 5 };
    const cb = ChunkedBuffer.init(10).withWrap(true);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("中文"); // Each char needs 2 columns but viewport is 1
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    // Should handle gracefully without crashing
    const line0 = buf.getLine(0, 0, 1);
    defer allocator.free(line0);
    // Might be empty or partial - just shouldn't crash
    try testing.expect(line0.len >= 0);
}

test "ChunkedBuffer wrap with empty line" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const cb = ChunkedBuffer.init(10).withWrap(true);

    const Ctx = struct {
        fn callback(_: usize, _: anytype) !void {
            // Empty line
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 10);
    defer allocator.free(line0);
    // Empty line should render and advance y by 1
    try testing.expect(std.mem.trim(u8, line0, " ").len == 0);
}

// 6. Unicode Edge Cases

test "ChunkedBuffer handles CJK characters with correct width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("你好世界"); // 4 CJK chars = 8 display width
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 10);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "你") != null);
}

test "ChunkedBuffer handles emoji with correct width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("😀😁"); // 2 emoji = 4 display width
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 10);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "😀") != null);
}

test "ChunkedBuffer handles mixed ASCII and wide characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    const cb = ChunkedBuffer.init(10);

    const Ctx = struct {
        fn callback(line_index: usize, writer: anytype) !void {
            _ = line_index;
            try writer.writeAll("Hello世界Test😀"); // Mix of ASCII, CJK, emoji
        }
    };

    try cb.render(&buf, area, Ctx.callback, allocator);

    const line0 = buf.getLine(0, 0, 20);
    defer allocator.free(line0);
    try testing.expect(std.mem.indexOf(u8, line0, "Hello") != null);
    try testing.expect(std.mem.indexOf(u8, line0, "世界") != null);
}

// 7. Block Integration

test "ChunkedBuffer with block reduces inner area correctly" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const block = Block.init().withBorders(.all);
    const cb = ChunkedBuffer.init(100).withBlock(block);

    var call_count: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn callback(line_index: usize, writer: anytype) !void {
            count.* += 1;
            try writer.print("Line {d}", .{line_index});
        }
    };
    Ctx.count = &call_count;

    try cb.render(&buf, area, Ctx.callback, allocator);

    // With borders, inner area is reduced by 2 in each dimension
    // Height: 10 - 2 = 8, so should render 8 lines
    try testing.expectEqual(@as(usize, 8), call_count);
}
