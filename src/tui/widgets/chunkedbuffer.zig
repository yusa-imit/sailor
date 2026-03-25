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
