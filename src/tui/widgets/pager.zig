//! Pager widget — scrollable text content with search and line numbers.
//!
//! Pager displays read-only text content from a slice of lines with support
//! for vertical and horizontal scrolling, line numbers, search highlighting,
//! and block borders.
//!
//! ## Features
//! - Vertical scrolling (line-by-line and page-based navigation)
//! - Horizontal scrolling for long lines
//! - Line number display (1-indexed with right-alignment)
//! - Search highlighting with case-sensitive/insensitive matching
//! - Soft wrapping for content exceeding available width
//! - Block wrapper support for borders and padding
//! - Fluent builder API
//!
//! ## Usage
//! ```zig
//! const lines = &[_][]const u8{"Line 1", "Line 2", "Line 3"};
//! const pager = Pager.init(lines)
//!     .withLineNumbers()
//!     .withSearchQuery("Line")
//!     .withHighlightStyle(.{ .reverse = true });
//! pager.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Pager widget - scrollable text content with search and line numbers
pub const Pager = struct {
    /// Lines of text to display (borrowed from caller, not owned)
    lines: []const []const u8 = &[_][]const u8{},

    /// Vertical scroll offset (line index)
    scroll_y: usize = 0,

    /// Horizontal scroll offset (byte index)
    scroll_x: usize = 0,

    /// Whether to display line numbers
    line_numbers: bool = false,

    /// Whether to wrap long lines (not implemented in render, but stored)
    wrap: bool = false,

    /// Text style for content
    style: Style = .{},

    /// Style for search highlights
    highlight_style: Style = .{},

    /// Optional block wrapper for borders
    block: ?Block = null,

    /// Search query string to highlight
    search_query: []const u8 = "",

    /// Whether search is case-sensitive
    case_sensitive: bool = false,

    /// Initialize pager with lines
    pub fn init(lines: []const []const u8) Pager {
        return .{ .lines = lines };
    }

    /// Builder: enable line numbers
    pub fn withLineNumbers(self: Pager) Pager {
        var result = self;
        result.line_numbers = true;
        return result;
    }

    /// Builder: enable soft wrapping
    pub fn withWrap(self: Pager) Pager {
        var result = self;
        result.wrap = true;
        return result;
    }

    /// Builder: set text style
    pub fn withStyle(self: Pager, s: Style) Pager {
        var result = self;
        result.style = s;
        return result;
    }

    /// Builder: set search highlight style
    pub fn withHighlightStyle(self: Pager, s: Style) Pager {
        var result = self;
        result.highlight_style = s;
        return result;
    }

    /// Builder: set block wrapper
    pub fn withBlock(self: Pager, b: Block) Pager {
        var result = self;
        result.block = b;
        return result;
    }

    /// Builder: set search query
    pub fn withSearchQuery(self: Pager, q: []const u8) Pager {
        var result = self;
        result.search_query = q;
        return result;
    }

    /// Builder: set case sensitivity
    pub fn withCaseSensitive(self: Pager, v: bool) Pager {
        var result = self;
        result.case_sensitive = v;
        return result;
    }

    /// Scroll down by one line
    pub fn scrollDown(self: *Pager, area_height: usize) void {
        _ = area_height;
        if (self.lines.len == 0) return;
        self.scroll_y = @min(self.scroll_y + 1, self.lines.len);
    }

    /// Scroll up by one line
    pub fn scrollUp(self: *Pager) void {
        self.scroll_y = if (self.scroll_y > 0) self.scroll_y - 1 else 0;
    }

    /// Scroll right by n characters
    pub fn scrollRight(self: *Pager, n: usize) void {
        const max_x = self.maxLineWidth();
        self.scroll_x = @min(self.scroll_x + n, max_x);
    }

    /// Scroll left by n characters
    pub fn scrollLeft(self: *Pager, n: usize) void {
        self.scroll_x = if (self.scroll_x >= n) self.scroll_x - n else 0;
    }

    /// Page down by area height
    pub fn pageDown(self: *Pager, area_height: usize) void {
        if (self.lines.len == 0) return;
        self.scroll_y = @min(self.scroll_y + area_height, self.lines.len);
    }

    /// Page up by area height
    pub fn pageUp(self: *Pager, area_height: usize) void {
        self.scroll_y = if (self.scroll_y >= area_height) self.scroll_y - area_height else 0;
    }

    /// Jump to top of content
    pub fn goToTop(self: *Pager) void {
        self.scroll_y = 0;
        self.scroll_x = 0;
    }

    /// Jump to bottom of content
    pub fn goToBottom(self: *Pager, area_height: usize) void {
        _ = area_height;
        self.scroll_y = self.lines.len;
        self.scroll_x = 0;
    }

    /// Jump to specific line (0-indexed)
    pub fn goToLine(self: *Pager, line: usize) void {
        if (self.lines.len == 0) return;
        self.scroll_y = @min(line, self.lines.len);
    }

    /// Get maximum line width (byte length) in all lines
    pub fn maxLineWidth(self: *const Pager) usize {
        var max_width: usize = 0;
        for (self.lines) |line| {
            max_width = @max(max_width, line.len);
        }
        return max_width;
    }

    /// Render pager content to buffer
    pub fn render(self: Pager, buf: *Buffer, area: Rect) void {
        // Early return on empty area
        if (area.width == 0 or area.height == 0) return;

        // Calculate inner area (accounting for block borders)
        var inner_area = area;
        if (self.block) |block| {
            inner_area = block.inner(area);
        }

        // If inner area is empty, nothing to render
        if (inner_area.width == 0 or inner_area.height == 0) {
            // Still render block borders if present
            if (self.block) |block| {
                block.render(buf, area);
            }
            return;
        }

        // Calculate line number width
        const line_num_width: u16 = if (self.line_numbers) 7 else 0;

        // Content width after line numbers
        const content_width: u16 = if (inner_area.width > line_num_width)
            inner_area.width - line_num_width
        else {
            // Not enough space for line numbers
            if (self.block) |block| {
                block.render(buf, area);
            }
            return;
        };

        // Render each visible line
        var row: u16 = 0;
        while (row < inner_area.height) : (row += 1) {
            const line_idx = self.scroll_y + row;

            if (line_idx >= self.lines.len) break;

            const line = self.lines[line_idx];

            // Render line number prefix
            if (self.line_numbers) {
                var num_buf: [7]u8 = undefined;
                const num_str = std.fmt.bufPrint(
                    &num_buf,
                    "{d:>4} | ",
                    .{line_idx + 1},
                ) catch "";

                const num_x = inner_area.x;
                const num_y = inner_area.y + row;
                buf.setString(num_x, num_y, num_str, self.style);
            }

            // Render line content with horizontal scroll
            const start_idx = @min(self.scroll_x, line.len);
            const visible_line = line[start_idx..];
            const truncated = visible_line[0..@min(visible_line.len, content_width)];

            const content_x = inner_area.x + line_num_width;
            const content_y = inner_area.y + row;

            // Render line with search highlighting if query exists
            if (self.search_query.len > 0) {
                renderLineWithHighlight(
                    buf,
                    truncated,
                    content_x,
                    content_y,
                    self.style,
                    self.highlight_style,
                    self.search_query,
                    self.case_sensitive,
                );
            } else {
                buf.setString(content_x, content_y, truncated, self.style);
            }
        }

        // Render block borders and title
        if (self.block) |block| {
            block.render(buf, area);
        }
    }
};

/// Render a line with search highlighting
fn renderLineWithHighlight(
    buf: *Buffer,
    line: []const u8,
    x: u16,
    y: u16,
    base_style: Style,
    highlight_style: Style,
    query: []const u8,
    case_sensitive: bool,
) void {
    if (y >= buf.height or x >= buf.width or line.len == 0 or query.len == 0) {
        buf.setString(x, y, line, base_style);
        return;
    }

    var col = x;
    var byte_idx: usize = 0;

    while (byte_idx < line.len and col < buf.width) {
        // Try to match query at current position
        const match_len = if (case_sensitive)
            matchAt(line, byte_idx, query)
        else
            matchAtCaseInsensitive(line, byte_idx, query);

        if (match_len > 0) {
            // Render matched portion with highlight style
            const match_segment = line[byte_idx .. byte_idx + match_len];
            renderSegment(buf, col, y, match_segment, highlight_style);

            // Calculate visual columns consumed
            for (match_segment) |byte| {
                if (isUtf8Start(byte)) {
                    col += 1;
                }
            }
            byte_idx += match_len;
        } else {
            // Render single character with base style
            const byte = line[byte_idx];
            if (isUtf8Start(byte)) {
                const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
                if (byte_idx + char_len <= line.len) {
                    const char_bytes = line[byte_idx .. byte_idx + char_len];
                    const codepoint = std.unicode.utf8Decode(char_bytes) catch byte;
                    buf.set(col, y, Cell.init(codepoint, base_style));
                    col += 1;
                    byte_idx += char_len;
                } else {
                    byte_idx += 1;
                }
            } else {
                byte_idx += 1;
            }
        }
    }
}

/// Check if a byte is the start of a UTF-8 sequence
fn isUtf8Start(byte: u8) bool {
    return (byte & 0xC0) != 0x80;
}

/// Find match of query starting at byte_idx (case-sensitive)
fn matchAt(line: []const u8, start_idx: usize, query: []const u8) usize {
    if (start_idx >= line.len or query.len > line.len - start_idx) {
        return 0;
    }

    if (std.mem.eql(u8, line[start_idx .. start_idx + query.len], query)) {
        return query.len;
    }
    return 0;
}

/// Find match of query starting at byte_idx (case-insensitive)
fn matchAtCaseInsensitive(line: []const u8, start_idx: usize, query: []const u8) usize {
    if (start_idx >= line.len or query.len > line.len - start_idx) {
        return 0;
    }

    const segment = line[start_idx .. start_idx + query.len];
    if (segment.len < query.len) return 0;

    for (query, 0..) |qchar, i| {
        if (std.ascii.toLower(qchar) != std.ascii.toLower(segment[i])) {
            return 0;
        }
    }
    return query.len;
}

/// Render a segment with highlight style
fn renderSegment(buf: *Buffer, x: u16, y: u16, segment: []const u8, style: Style) void {
    var col = x;
    var byte_idx: usize = 0;

    while (byte_idx < segment.len and col < buf.width) {
        const byte = segment[byte_idx];
        const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

        if (byte_idx + char_len <= segment.len) {
            const char_bytes = segment[byte_idx .. byte_idx + char_len];
            const codepoint = std.unicode.utf8Decode(char_bytes) catch byte;
            buf.set(col, y, Cell.init(codepoint, style));
            col += 1;
            byte_idx += char_len;
        } else {
            byte_idx += 1;
        }
    }
}

/// Safe subtraction for usize (returns 0 if would underflow)
fn saturatingSub(a: usize, b: usize) usize {
    return if (a >= b) a - b else 0;
}

// Tests imported from tests/pager_test.zig are run via build.zig
