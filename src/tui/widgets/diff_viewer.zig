//! DiffViewer — renders unified diff format (v2.16.0)
//!
//! Parses and displays unified diff output with color-coded line types.
//! No allocation required — diff text is iterated line-by-line during render.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Line classification for unified diff format.
pub const LineKind = enum {
    diff_header, // "diff --git", "index", "new file mode", "deleted file mode"
    file_header, // "--- a/..." or "+++ b/..."
    hunk_header, // "@@ -a,b +c,d @@"
    removed,     // "-" prefix — deleted line
    added,       // "+" prefix — added line
    context,     // " " prefix or bare line — unchanged
    no_newline,  // "\\ No newline at end of file"
};

/// Classifies a single line of unified diff text.
pub fn classifyLine(line: []const u8) LineKind {
    if (line.len == 0) return .context;

    if (std.mem.startsWith(u8, line, "--- ") or std.mem.startsWith(u8, line, "+++ ")) {
        return .file_header;
    }
    if (std.mem.startsWith(u8, line, "@@ ")) return .hunk_header;
    if (std.mem.startsWith(u8, line, "diff ") or
        std.mem.startsWith(u8, line, "index ") or
        std.mem.startsWith(u8, line, "new file") or
        std.mem.startsWith(u8, line, "deleted file") or
        std.mem.startsWith(u8, line, "old mode") or
        std.mem.startsWith(u8, line, "new mode") or
        std.mem.startsWith(u8, line, "rename ") or
        std.mem.startsWith(u8, line, "similarity ") or
        std.mem.startsWith(u8, line, "Binary "))
    {
        return .diff_header;
    }
    if (std.mem.startsWith(u8, line, "\\ ")) return .no_newline;
    if (line[0] == '-') return .removed;
    if (line[0] == '+') return .added;
    return .context;
}

/// DiffViewer widget — renders unified diff format with color coding.
///
/// Example:
/// ```zig
/// const viewer = DiffViewer{
///     .content = diff_text,
///     .scroll = 0,
/// };
/// viewer.render(buf, area);
/// ```
pub const DiffViewer = struct {
    /// Raw unified diff text (caller owns lifetime).
    content: []const u8 = "",
    /// Vertical scroll offset (in lines).
    scroll: usize = 0,
    /// Horizontal scroll offset (in columns).
    h_scroll: usize = 0,
    /// Optional border block.
    block: ?Block = null,

    // Line kind styles
    removed_style: Style = .{ .fg = .red },
    added_style: Style = .{ .fg = .green },
    hunk_style: Style = .{ .fg = .cyan, .bold = true },
    header_style: Style = .{ .fg = .bright_black, .bold = true },
    file_style: Style = .{ .bold = true },
    context_style: Style = .{},
    no_newline_style: Style = .{ .fg = .yellow, .dim = true },

    /// Set the diff content.
    pub fn withContent(self: DiffViewer, content: []const u8) DiffViewer {
        var r = self;
        r.content = content;
        return r;
    }

    /// Set vertical scroll offset.
    pub fn withScroll(self: DiffViewer, scroll: usize) DiffViewer {
        var r = self;
        r.scroll = scroll;
        return r;
    }

    /// Set horizontal scroll offset.
    pub fn withHScroll(self: DiffViewer, h_scroll: usize) DiffViewer {
        var r = self;
        r.h_scroll = h_scroll;
        return r;
    }

    /// Wrap with a border block.
    pub fn withBlock(self: DiffViewer, blk: Block) DiffViewer {
        var r = self;
        r.block = blk;
        return r;
    }

    /// Count total lines in the diff content.
    pub fn lineCount(self: DiffViewer) usize {
        if (self.content.len == 0) return 0;
        var count: usize = 0;
        var it = std.mem.splitScalar(u8, self.content, '\n');
        while (it.next()) |_| count += 1;
        return count;
    }

    /// Count lines by kind. Returns counts for added, removed, and hunk headers.
    pub fn counts(self: DiffViewer) struct { added: usize, removed: usize, hunks: usize } {
        var result = .{ .added = @as(usize, 0), .removed = @as(usize, 0), .hunks = @as(usize, 0) };
        var it = std.mem.splitScalar(u8, self.content, '\n');
        while (it.next()) |line| {
            switch (classifyLine(line)) {
                .added => result.added += 1,
                .removed => result.removed += 1,
                .hunk_header => result.hunks += 1,
                else => {},
            }
        }
        return result;
    }

    /// Render the diff into the buffer, clipped to area.
    pub fn render(self: DiffViewer, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        var line_num: usize = 0;
        var row: u16 = 0;
        var it = std.mem.splitScalar(u8, self.content, '\n');

        while (it.next()) |line| {
            defer line_num += 1;

            if (line_num < self.scroll) continue;
            if (row >= inner.height) break;

            const kind = classifyLine(line);
            const style = switch (kind) {
                .removed => self.removed_style,
                .added => self.added_style,
                .hunk_header => self.hunk_style,
                .diff_header => self.header_style,
                .file_header => self.file_style,
                .no_newline => self.no_newline_style,
                .context => self.context_style,
            };

            // Apply horizontal scroll
            const display = if (self.h_scroll >= line.len) "" else line[self.h_scroll..];

            // Clip to inner.width columns (UTF-8 aware)
            const clipped = clipToWidth(display, inner.width);

            if (clipped.len > 0) {
                buf.setString(inner.x, inner.y + row, clipped, style);
            }

            row += 1;
        }
    }
};

/// Clips a UTF-8 string to at most `max_cols` terminal columns.
/// Returns a sub-slice of `s`; does not allocate.
fn clipToWidth(s: []const u8, max_cols: u16) []const u8 {
    var col: u16 = 0;
    var idx: usize = 0;
    while (idx < s.len and col < max_cols) {
        const cp_len = std.unicode.utf8ByteSequenceLength(s[idx]) catch 1;
        if (idx + cp_len > s.len) break;
        col += 1;
        idx += cp_len;
    }
    return s[0..idx];
}
