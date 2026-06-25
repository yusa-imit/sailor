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
const paragraph_mod = @import("paragraph.zig");
const Alignment = paragraph_mod.Alignment;

pub const MAX_SECTIONS: usize = 64;

pub const SplitText = struct {
    text: []const u8 = "",
    delimiter: []const u8 = "\n---\n",
    section_headers: []const []const u8 = &.{},
    style: Style = .{},
    header_style: Style = .{},
    divider_style: Style = .{},
    divider_char: u21 = '─',
    show_dividers: bool = true,
    alignment: Alignment = .left,
    block: ?Block = null,

    pub fn init() SplitText {
        return .{};
    }

    pub fn sectionCount(self: SplitText) usize {
        if (self.text.len == 0) return 0;
        if (self.delimiter.len == 0) return 1;

        var count: usize = 1;
        var i: usize = 0;

        while (i + self.delimiter.len <= self.text.len) : (i += 1) {
            if (std.mem.eql(u8, self.text[i .. i + self.delimiter.len], self.delimiter)) {
                count += 1;
                if (count >= MAX_SECTIONS) break;
                i += self.delimiter.len - 1;
            }
        }

        return count;
    }

    pub fn withText(self: SplitText, t: []const u8) SplitText {
        var c = self;
        c.text = t;
        return c;
    }

    pub fn withDelimiter(self: SplitText, d: []const u8) SplitText {
        var c = self;
        c.delimiter = d;
        return c;
    }

    pub fn withSectionHeaders(self: SplitText, h: []const []const u8) SplitText {
        var c = self;
        c.section_headers = h;
        return c;
    }

    pub fn withStyle(self: SplitText, s: Style) SplitText {
        var c = self;
        c.style = s;
        return c;
    }

    pub fn withHeaderStyle(self: SplitText, s: Style) SplitText {
        var c = self;
        c.header_style = s;
        return c;
    }

    pub fn withDividerStyle(self: SplitText, s: Style) SplitText {
        var c = self;
        c.divider_style = s;
        return c;
    }

    pub fn withDividerChar(self: SplitText, ch: u21) SplitText {
        var c = self;
        c.divider_char = ch;
        return c;
    }

    pub fn withShowDividers(self: SplitText, b: bool) SplitText {
        var c = self;
        c.show_dividers = b;
        return c;
    }

    pub fn withAlignment(self: SplitText, a: Alignment) SplitText {
        var c = self;
        c.alignment = a;
        return c;
    }

    pub fn withBlock(self: SplitText, b: Block) SplitText {
        var c = self;
        c.block = b;
        return c;
    }

    pub fn render(self: SplitText, buf: *Buffer, area: Rect) void {
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

        // Guard: empty text
        if (self.text.len == 0) return;

        // Find all section boundaries
        var section_starts: [MAX_SECTIONS]usize = undefined;
        var section_ends: [MAX_SECTIONS]usize = undefined;
        var N: usize = 0;

        // Populate section starts/ends
        section_starts[0] = 0;
        N = 1;

        if (self.delimiter.len > 0) {
            var i: usize = 0;
            while (i + self.delimiter.len <= self.text.len) {
                if (std.mem.eql(u8, self.text[i .. i + self.delimiter.len], self.delimiter) and N < MAX_SECTIONS) {
                    section_ends[N - 1] = i;
                    section_starts[N] = i + self.delimiter.len;
                    N += 1;
                    i += self.delimiter.len;
                } else {
                    i += 1;
                }
            }
        }
        section_ends[N - 1] = self.text.len;

        // Compute section heights
        const base_h: u16 = @intCast(inner.height / N);
        const extra: u16 = @intCast(inner.height - base_h * @as(u16, @intCast(N)));

        // Render each section
        var current_y: u16 = inner.y;
        for (0..N) |i| {
            const section_text = self.text[section_starts[i]..section_ends[i]];
            const section_h: u16 = base_h + if (i == N - 1) extra else 0;

            // Skip if section has zero height
            if (section_h == 0) continue;

            var content_y = current_y;

            // Render header if available
            const has_header = i < self.section_headers.len and self.section_headers[i].len > 0;
            if (has_header and content_y < inner.y + inner.height) {
                const header = self.section_headers[i];
                const header_width: u16 = @intCast(@min(header.len, inner.width));
                for (0..header_width) |k| {
                    const x = inner.x + @as(u16, @intCast(k));
                    buf.set(x, content_y, .{ .char = header[k], .style = self.header_style });
                }
                content_y += 1;
            }

            // Compute text end y (divider row may consume the last row)
            var text_end_y = current_y + section_h;
            const divider_y = current_y + section_h - 1;

            // Render divider at bottom of section (if not last section and show_dividers)
            if (self.show_dividers and i < N - 1 and divider_y < inner.y + inner.height) {
                for (0..inner.width) |col| {
                    const x = inner.x + @as(u16, @intCast(col));
                    buf.set(x, divider_y, .{ .char = self.divider_char, .style = self.divider_style });
                }
                text_end_y = divider_y;
            }

            // Render section text
            renderText(section_text, buf, inner.x, content_y, text_end_y, inner.width, self.style, self.alignment);

            current_y += section_h;
        }
    }
};

fn renderText(
    text: []const u8,
    buf: *Buffer,
    x: u16,
    y_start: u16,
    y_end: u16,
    width: u16,
    style: Style,
    alignment: Alignment,
) void {
    if (width == 0 or y_start >= y_end) return;

    var current_y = y_start;
    var pos: usize = 0;

    while (pos < text.len and current_y < y_end) {
        const remaining = text[pos..];
        if (remaining.len == 0) break;

        // Find how many chars fit on this line
        var line_len: usize = @min(remaining.len, width);

        // Try to break at word boundary (last space before line_len)
        if (line_len < remaining.len) {
            var last_space: ?usize = null;
            for (0..line_len) |k| {
                if (remaining[k] == ' ') last_space = k;
            }
            if (last_space) |sp| {
                line_len = sp;
            }
        }

        const line = remaining[0..line_len];

        // Compute alignment x
        const line_width: u16 = @intCast(line.len);
        const draw_x: u16 = switch (alignment) {
            .left => x,
            .center => if (line_width >= width) x else x + (width - line_width) / 2,
            .right => if (line_width >= width) x else x + width - line_width,
            .justify => x,
        };

        // Render each character
        for (line, 0..) |ch, k| {
            const cell_x = draw_x + @as(u16, @intCast(k));
            buf.set(cell_x, current_y, .{ .char = ch, .style = style });
        }

        current_y += 1;

        // Advance pos past the line (and any trailing space)
        pos += line_len;
        if (pos < text.len and text[pos] == ' ') pos += 1;
    }
}
