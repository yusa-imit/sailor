//! FlowText widget — multi-column text layout with word wrapping and alignment.
//!
//! FlowText arranges text across multiple columns with configurable gutter (spacing)
//! between columns. Text is word-wrapped to fit column widths, with long words
//! hard-split at column boundaries. Each line within a column can be aligned
//! (left, center, right).
//!
//! ## Features
//! - Multi-column layout (1-255 columns)
//! - Configurable gutter spacing between columns
//! - Word-wrapping with hard-split for oversized words
//! - Text alignment (left, center, right) within columns
//! - Optional block wrapper for borders
//! - Inline styling support
//!
//! ## Usage
//! ```zig
//! var widget = FlowText.init()
//!     .withText("Lorem ipsum dolor sit amet...")
//!     .withColumns(2)
//!     .withGutter(1)
//!     .withAlignment(.left);
//! widget.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const paragraph_mod = @import("paragraph.zig");
const Alignment = paragraph_mod.Alignment;

/// FlowText widget - arranges text across multiple columns
pub const FlowText = struct {
    /// Text content to display
    text: []const u8 = "",
    /// Number of columns (1-255, 0 is treated as 1)
    columns: u8 = 2,
    /// Width of gutter (spacing) between columns
    gutter: u8 = 1,
    /// Style applied to rendered text
    style: Style = .{},
    /// Text alignment within columns
    alignment: Alignment = .left,
    /// Optional block wrapper for borders
    block: ?Block = null,

    /// Initialize with default values
    pub fn init() FlowText {
        return .{};
    }

    /// Builder: set text
    pub fn withText(self: FlowText, text: []const u8) FlowText {
        var copy = self;
        copy.text = text;
        return copy;
    }

    /// Builder: set number of columns
    pub fn withColumns(self: FlowText, cols: u8) FlowText {
        var copy = self;
        copy.columns = cols;
        return copy;
    }

    /// Builder: set gutter width
    pub fn withGutter(self: FlowText, g: u8) FlowText {
        var copy = self;
        copy.gutter = g;
        return copy;
    }

    /// Builder: set style
    pub fn withStyle(self: FlowText, s: Style) FlowText {
        var copy = self;
        copy.style = s;
        return copy;
    }

    /// Builder: set alignment
    pub fn withAlignment(self: FlowText, alignment: Alignment) FlowText {
        var copy = self;
        copy.alignment = alignment;
        return copy;
    }

    /// Builder: set block wrapper
    pub fn withBlock(self: FlowText, b: Block) FlowText {
        var copy = self;
        copy.block = b;
        return copy;
    }

    /// Render the widget to a buffer at the given area
    pub fn render(self: FlowText, buf: *Buffer, area: Rect) void {
        // Guard: zero area
        if (area.width == 0 or area.height == 0) return;

        // Determine inner area (either inside block or same as area)
        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        // Guard: zero inner area
        if (inner.width == 0 or inner.height == 0) return;

        // Early exit for empty text
        if (self.text.len == 0) return;

        // Normalize columns (0 is treated as 1)
        const cols = if (self.columns == 0) 1 else self.columns;
        const gutter = self.gutter;

        // Calculate column width
        const total_gutter: u32 = if (cols > 1) @as(u32, gutter) * @as(u32, cols - 1) else 0;
        const available_width: u32 = if (@as(u32, inner.width) > total_gutter)
            @as(u32, inner.width) - total_gutter
        else
            0;

        const col_width = if (available_width > 0)
            @as(u16, @intCast(available_width / @as(u32, @max(cols, 1))))
        else
            0;

        if (col_width == 0) return;

        // Word-wrap text into lines and group by words for column distribution
        var lines: [256][]const u8 = undefined;
        var line_count: usize = 0;
        var word_line_counts: [256]usize = undefined;  // Track line count per word
        var word_count: usize = 0;
        self.wrapTextByWord(col_width, &lines, &line_count, &word_line_counts, &word_count);

        // Distribute words across columns with per-column row tracking
        var col_rows: [256]usize = [_]usize{0} ** 256;
        var line_idx: usize = 0;
        for (0..word_count) |word_idx| {
            const col_idx = word_idx % @as(usize, cols);
            const col_x: u16 = inner.x + @as(u16, @intCast(col_idx)) * (col_width + gutter);

            const word_lines = word_line_counts[word_idx];
            for (0..word_lines) |_| {
                const row = col_rows[col_idx];
                if (row < @as(usize, inner.height)) {
                    const line = lines[line_idx];
                    const line_y = inner.y + @as(u16, @intCast(row));
                    const start_x = self.computeStartX(col_x, col_width, line.len);
                    buf.setString(start_x, line_y, line, self.style);
                }
                col_rows[col_idx] += 1;
                line_idx += 1;
            }
        }
    }

    /// Wrap text into lines fitting col_width, grouping by words for column distribution
    fn wrapTextByWord(
        self: FlowText,
        col_width: u16,
        lines: *[256][]const u8,
        line_count: *usize,
        word_line_counts: *[256]usize,
        word_count: *usize,
    ) void {
        var i: usize = 0;
        line_count.* = 0;
        word_count.* = 0;

        while (i < self.text.len and word_count.* < 256) {
            // Skip whitespace
            while (i < self.text.len and (self.text[i] == ' ' or self.text[i] == '\n' or self.text[i] == '\t')) {
                i += 1;
            }
            if (i >= self.text.len) break;

            // Scan word
            const word_start = i;
            while (i < self.text.len and self.text[i] != ' ' and self.text[i] != '\n' and self.text[i] != '\t') {
                i += 1;
            }
            const word_len = i - word_start;

            const lines_for_word_start = line_count.*;

            // Split word into col_width chunks
            var offset: usize = 0;
            while (offset < word_len and line_count.* < 256) {
                const chunk_end = @min(word_len, offset + @as(usize, col_width));
                lines[line_count.*] = self.text[word_start + offset .. word_start + chunk_end];
                line_count.* += 1;
                offset += @as(usize, col_width);
            }

            word_line_counts[word_count.*] = line_count.* - lines_for_word_start;
            word_count.* += 1;
        }
    }

    /// Compute start x position for a line based on alignment
    fn computeStartX(self: FlowText, col_x: u16, col_width: u16, line_len: usize) u16 {
        return switch (self.alignment) {
            .left => col_x,
            .center => {
                if (line_len <= @as(usize, col_width)) {
                    const offset = (@as(usize, col_width) - line_len) / 2;
                    return col_x + @as(u16, @intCast(offset));
                } else {
                    return col_x;
                }
            },
            .right => {
                if (line_len <= @as(usize, col_width)) {
                    const offset = @as(usize, col_width) - line_len;
                    return col_x + @as(u16, @intCast(offset));
                } else {
                    return col_x;
                }
            },
            .justify => col_x,
        };
    }
};
