//! Shared helpers for the example programs (not an example itself).
//!
//! Provides plain-text Paragraph rendering (split on newlines) and a
//! one-shot "print the whole buffer" routine built on the buffer diff API.

const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Line = sailor.tui.style.Line;
const Span = sailor.tui.style.Span;
const Paragraph = sailor.tui.widgets.Paragraph;

/// Upper bound on the number of text lines `renderText` lays out.
pub const text_lines_max: usize = 64;

/// Render multi-line plain `text` into `area` with a single `style`.
/// Lines beyond `text_lines_max` are dropped.
pub fn renderText(
    buf: *Buffer,
    area: Rect,
    text: []const u8,
    alignment: sailor.tui.widgets.Alignment,
    style: Style,
) void {
    std.debug.assert(area.x <= buf.width);
    std.debug.assert(area.y <= buf.height);

    var spans: [text_lines_max][1]Span = undefined;
    var lines: [text_lines_max]Line = undefined;
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |row| {
        if (count == text_lines_max) break;
        spans[count] = .{Span.styled(row, style)};
        lines[count] = .{ .spans = &spans[count] };
        count += 1;
    }
    const para = Paragraph{ .lines = lines[0..count], .alignment = alignment };
    para.render(buf, area);
}

/// Write every cell of `buf` to `writer` as ANSI (diff against a blank buffer).
pub fn renderBuffer(
    allocator: std.mem.Allocator,
    buf: Buffer,
    writer: *std.Io.Writer,
) !void {
    std.debug.assert(buf.width > 0);
    std.debug.assert(buf.height > 0);

    var blank = try Buffer.init(allocator, buf.width, buf.height);
    defer blank.deinit();

    const ops = try sailor.tui.buffer.diff(allocator, blank, buf);
    defer allocator.free(ops);

    try sailor.tui.buffer.renderDiff(ops, writer);
}
