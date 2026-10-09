//! Codepoint-based clipping helpers shared by widgets that draw into a fixed-width column.
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Style = @import("../style.zig").Style;
const assert = std.debug.assert;

/// Returns the longest prefix of `text` holding at most `cells_max` codepoints.
///
/// Counts one cell per codepoint, never splits a multi-byte sequence, and never returns more
/// than `text`.
pub fn clipCodepoints(text: []const u8, cells_max: u16) []const u8 {
    var cells: u16 = 0;
    for (text, 0..) |byte, i| {
        // UTF-8 continuation bytes (10xxxxxx) do not start a new codepoint.
        if (byte & 0xC0 == 0x80) continue;
        if (cells == cells_max) return text[0..i];
        cells += 1;
    }
    assert(cells <= cells_max);
    return text;
}

/// Draws `text` at (x, y), truncated to `width_max` codepoints. A zero width draws nothing.
pub fn drawClipped(
    buf: *Buffer,
    x: u16,
    y: u16,
    text: []const u8,
    style: Style,
    width_max: u16,
) void {
    const clipped = clipCodepoints(text, width_max);
    assert(clipped.len <= text.len);
    buf.setString(x, y, clipped, style);
}

test "clipCodepoints truncates by codepoint, not byte" {
    try std.testing.expectEqualStrings("abc", clipCodepoints("abcdef", 3));
    try std.testing.expectEqualStrings("abcdef", clipCodepoints("abcdef", 6));
    try std.testing.expectEqualStrings("abcdef", clipCodepoints("abcdef", 100));
    try std.testing.expectEqualStrings("", clipCodepoints("abcdef", 0));
    // Each arrow is three bytes but one cell.
    try std.testing.expectEqualStrings("\u{2191}\u{2191}", clipCodepoints("\u{2191}\u{2191}\u{2191}", 2));
    try std.testing.expectEqualStrings("", clipCodepoints("", 4));
}

test "drawClipped writes only the clipped prefix" {
    var buf = try Buffer.init(std.testing.allocator, 10, 1);
    defer buf.deinit();

    drawClipped(&buf, 2, 0, "hello", .{ .bold = true }, 3);

    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, 'h'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, 'l'), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(5, 0));
    try std.testing.expect(buf.getStyle(3, 0).bold);

    drawClipped(&buf, 0, 0, "zzz", .{}, 0);
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}
