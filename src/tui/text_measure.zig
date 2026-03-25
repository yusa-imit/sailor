const std = @import("std");
const style_mod = @import("style.zig");
const UnicodeWidth = @import("../unicode.zig").UnicodeWidth;

const Allocator = std.mem.Allocator;
const Line = style_mod.Line;
const Span = style_mod.Span;
const Style = style_mod.Style;
const Color = style_mod.Color;

/// Represents the dimensions of measured text
pub const TextSize = struct {
    width: usize,
    height: usize,
};

/// Configuration for text measurement
pub const MeasureOptions = struct {
    /// Tab width in spaces (default: 4)
    tab_width: usize = 4,
    /// Whether to strip ANSI escape sequences (default: true)
    strip_ansi: bool = true,
};

/// Measure a single line of styled text (Line structure with Spans)
/// Returns TextSize with width calculated using proper Unicode widths
/// and height as 1 for a single line
pub fn measureLine(line: Line, opts: MeasureOptions) TextSize {
    var total_width: usize = 0;

    for (line.spans) |span| {
        total_width += measureSpanWidth(span.content, opts);
    }

    return .{
        .width = total_width,
        .height = 1,
    };
}

/// Measure plain text (without styling)
/// Returns TextSize with width and height calculated
pub fn measureText(text: []const u8, opts: MeasureOptions) TextSize {
    if (text.len == 0) {
        return .{ .width = 0, .height = 0 };
    }

    var lines: usize = 1;
    var current_line_width: usize = 0;
    var max_width: usize = 0;

    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '\n') {
            max_width = @max(max_width, current_line_width);
            current_line_width = 0;
            lines += 1;
            i += 1;
        } else if (text[i] == '\t' and opts.tab_width > 0) {
            current_line_width += opts.tab_width;
            i += 1;
        } else {
            // Handle UTF-8 character
            const byte = text[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (i + char_len <= text.len) {
                const codepoint = if (char_len == 1)
                    @as(u21, byte)
                else
                    std.unicode.utf8Decode(text[i .. i + char_len]) catch @as(u21, byte);

                current_line_width += UnicodeWidth.charWidth(codepoint);
                i += char_len;
            } else {
                i += 1;
            }
        }
    }

    max_width = @max(max_width, current_line_width);

    return .{
        .width = max_width,
        .height = lines,
    };
}

/// Internal: Measure width of a span's content string
fn measureSpanWidth(content: []const u8, opts: MeasureOptions) usize {
    var width: usize = 0;
    var i: usize = 0;

    while (i < content.len) {
        if (content[i] == '\t' and opts.tab_width > 0) {
            width += opts.tab_width;
            i += 1;
        } else if (content[i] == '\n') {
            // Newline should be handled by caller, but if present, just skip
            i += 1;
        } else {
            // Handle UTF-8 character
            const byte = content[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (i + char_len <= content.len) {
                const codepoint = if (char_len == 1)
                    @as(u21, byte)
                else
                    std.unicode.utf8Decode(content[i .. i + char_len]) catch @as(u21, byte);

                width += UnicodeWidth.charWidth(codepoint);
                i += char_len;
            } else {
                i += 1;
            }
        }
    }

    return width;
}

// =============================================================================
// Tests
// =============================================================================

test "measureLine - empty line" {
    var spans: [0]Span = .{};
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});

    try std.testing.expectEqual(@as(usize, 0), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - single ASCII span" {
    var spans: [1]Span = .{Span.raw("hello")};
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});

    try std.testing.expectEqual(@as(usize, 5), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - multiple ASCII spans" {
    var spans: [3]Span = .{
        Span.raw("hello"),
        Span.raw(" "),
        Span.raw("world"),
    };
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});

    try std.testing.expectEqual(@as(usize, 11), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - styled spans (style ignored, content measured)" {
    var spans: [2]Span = .{
        Span.styled("bold", .{ .bold = true }),
        Span.styled("text", .{ .fg = .red }),
    };
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});

    try std.testing.expectEqual(@as(usize, 8), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - CJK characters" {
    var spans: [1]Span = .{Span.raw("你好")};
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});

    // Each CJK character is width 2
    try std.testing.expectEqual(@as(usize, 4), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - mixed ASCII and CJK" {
    var spans: [1]Span = .{Span.raw("Hi你好")};
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});

    // H(1) + i(1) + 你(2) + 好(2) = 6
    try std.testing.expectEqual(@as(usize, 6), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - emoji characters" {
    var spans: [1]Span = .{Span.raw("Hello 🎉 World")};
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});

    // H(1) + e(1) + l(1) + l(1) + o(1) + space(1) + emoji(2) + space(1) + W(1) + o(1) + r(1) + l(1) + d(1) = 15
    try std.testing.expectEqual(@as(usize, 15), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - tabs expanded to spaces" {
    var spans: [1]Span = .{Span.raw("a\tb")};
    const line = Line{ .spans = &spans };
    // a(1) + tab(4) + b(1) = 6
    const size = measureLine(line, .{ .tab_width = 4 });

    try std.testing.expectEqual(@as(usize, 6), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureLine - custom tab width" {
    var spans: [1]Span = .{Span.raw("\t\t")};
    const line = Line{ .spans = &spans };
    // tab(2) + tab(2) = 4
    const size = measureLine(line, .{ .tab_width = 2 });

    try std.testing.expectEqual(@as(usize, 4), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - empty string" {
    const size = measureText("", .{});

    try std.testing.expectEqual(@as(usize, 0), size.width);
    try std.testing.expectEqual(@as(usize, 0), size.height);
}

test "measureText - single line ASCII" {
    const size = measureText("hello", .{});

    try std.testing.expectEqual(@as(usize, 5), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - two lines" {
    const size = measureText("hello\nworld", .{});

    try std.testing.expectEqual(@as(usize, 5), size.width);
    try std.testing.expectEqual(@as(usize, 2), size.height);
}

test "measureText - multiple lines with varying widths" {
    const size = measureText("a\nbb\nccc", .{});

    // Max width is 3 (from "ccc"), height is 3
    try std.testing.expectEqual(@as(usize, 3), size.width);
    try std.testing.expectEqual(@as(usize, 3), size.height);
}

test "measureText - trailing newline" {
    const size = measureText("hello\n", .{});

    try std.testing.expectEqual(@as(usize, 5), size.width);
    try std.testing.expectEqual(@as(usize, 2), size.height);
}

test "measureText - multiple trailing newlines" {
    const size = measureText("text\n\n", .{});

    try std.testing.expectEqual(@as(usize, 4), size.width);
    try std.testing.expectEqual(@as(usize, 3), size.height);
}

test "measureText - CJK single line" {
    const size = measureText("你好世界", .{});

    // 4 CJK characters × 2 width each = 8
    try std.testing.expectEqual(@as(usize, 8), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - mixed ASCII and CJK single line" {
    const size = measureText("Hello你好", .{});

    // H(1) + e(1) + l(1) + l(1) + o(1) + 你(2) + 好(2) = 9
    try std.testing.expectEqual(@as(usize, 9), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - CJK multi-line" {
    const size = measureText("你\n好", .{});

    // Both lines have width 2, max is 2
    try std.testing.expectEqual(@as(usize, 2), size.width);
    try std.testing.expectEqual(@as(usize, 2), size.height);
}

test "measureText - emoji in text" {
    const size = measureText("🎉test🎉", .{});

    // emoji(2) + t(1) + e(1) + s(1) + t(1) + emoji(2) = 8
    try std.testing.expectEqual(@as(usize, 8), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - emoji multi-line" {
    const size = measureText("🎉\n👍", .{});

    // Each emoji is width 2
    try std.testing.expectEqual(@as(usize, 2), size.width);
    try std.testing.expectEqual(@as(usize, 2), size.height);
}

test "measureText - tabs single line" {
    const size = measureText("a\tb\tc", .{ .tab_width = 4 });

    // a(1) + tab(4) + b(1) + tab(4) + c(1) = 11
    try std.testing.expectEqual(@as(usize, 11), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - tabs multi-line" {
    const size = measureText("a\tb\n\tc", .{ .tab_width = 4 });

    // Line 1: a(1) + tab(4) + b(1) = 6
    // Line 2: tab(4) + c(1) = 5
    // Max width = 6
    try std.testing.expectEqual(@as(usize, 6), size.width);
    try std.testing.expectEqual(@as(usize, 2), size.height);
}

test "measureText - tabs with width 2" {
    const size = measureText("a\tb", .{ .tab_width = 2 });

    // a(1) + tab(2) + b(1) = 4
    try std.testing.expectEqual(@as(usize, 4), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - tabs with width 0 (no expansion)" {
    const size = measureText("a\tb", .{ .tab_width = 0 });

    // a(1) + tab(0) + b(1) = 2
    try std.testing.expectEqual(@as(usize, 2), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - newline and tab combination" {
    const size = measureText("a\t\nb\t", .{ .tab_width = 4 });

    // Line 1: a(1) + tab(4) = 5
    // Line 2: b(1) + tab(4) = 5
    // Max width = 5
    try std.testing.expectEqual(@as(usize, 5), size.width);
    try std.testing.expectEqual(@as(usize, 2), size.height);
}

test "measureText - long line with short lines after" {
    const size = measureText("this is a long line\nshort\nx", .{});

    // Line 1: 19 characters = 19
    // Line 2: 5 characters = 5
    // Line 3: 1 character = 1
    // Max width = 19
    try std.testing.expectEqual(@as(usize, 19), size.width);
    try std.testing.expectEqual(@as(usize, 3), size.height);
}

test "measureText - only newlines" {
    const size = measureText("\n\n\n", .{});

    try std.testing.expectEqual(@as(usize, 0), size.width);
    try std.testing.expectEqual(@as(usize, 4), size.height);
}

test "measureText - spaces and newlines" {
    const size = measureText("  \n   \n    ", .{});

    // Line 1: 2 spaces = 2
    // Line 2: 3 spaces = 3
    // Line 3: 4 spaces = 4
    // Max width = 4
    try std.testing.expectEqual(@as(usize, 4), size.width);
    try std.testing.expectEqual(@as(usize, 3), size.height);
}

test "measureSpanWidth - ASCII content" {
    const width = measureSpanWidth("test", .{});
    try std.testing.expectEqual(@as(usize, 4), width);
}

test "measureSpanWidth - empty content" {
    const width = measureSpanWidth("", .{});
    try std.testing.expectEqual(@as(usize, 0), width);
}

test "measureSpanWidth - CJK content" {
    const width = measureSpanWidth("日本", .{});
    // 2 CJK characters × 2 = 4
    try std.testing.expectEqual(@as(usize, 4), width);
}

test "measureSpanWidth - tabs expanded" {
    const width = measureSpanWidth("\t", .{ .tab_width = 4 });
    try std.testing.expectEqual(@as(usize, 4), width);
}

test "measureSpanWidth - multiple tabs" {
    const width = measureSpanWidth("\t\t", .{ .tab_width = 4 });
    // 4 + 4 = 8
    try std.testing.expectEqual(@as(usize, 8), width);
}

test "measureSpanWidth - mixed content" {
    const width = measureSpanWidth("A\t你", .{ .tab_width = 4 });
    // A(1) + tab(4) + 你(2) = 7
    try std.testing.expectEqual(@as(usize, 7), width);
}

test "measureSpanWidth - emoji only" {
    const width = measureSpanWidth("🎯", .{});
    try std.testing.expectEqual(@as(usize, 2), width);
}

test "measureSpanWidth - newline in content" {
    const width = measureSpanWidth("a\nb", .{});
    // Newline is skipped, so just a(1) + b(1) = 2
    // Actually measuring only the content, newlines are "transparent"
    try std.testing.expectEqual(@as(usize, 2), width);
}

test "measureLine - empty span list" {
    var spans: [0]Span = .{};
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});
    try std.testing.expectEqual(@as(usize, 0), size.width);
}

test "measureLine - span with only whitespace" {
    var spans: [1]Span = .{Span.raw("   ")};
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});
    try std.testing.expectEqual(@as(usize, 3), size.width);
}

test "measureText - line with only tabs" {
    const size = measureText("\t\t", .{ .tab_width = 4 });
    try std.testing.expectEqual(@as(usize, 8), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - mixed width characters with tabs and newlines" {
    const size = measureText("a\t你\nworld", .{ .tab_width = 4 });

    // Line 1: a(1) + tab(4) + 你(2) = 7
    // Line 2: w(1) + o(1) + r(1) + l(1) + d(1) = 5
    // Max width = 7
    try std.testing.expectEqual(@as(usize, 7), size.width);
    try std.testing.expectEqual(@as(usize, 2), size.height);
}

test "measureText - real-world example 1" {
    const size = measureText("Title\nBody\nFooter", .{});
    try std.testing.expectEqual(@as(usize, 5), size.width);
    try std.testing.expectEqual(@as(usize, 3), size.height);
}

test "measureText - real-world example 2" {
    const size = measureText("┌────┐\n│你好│\n└────┘", .{});
    // Line 1: ┌(1) + ─(1) + ─(1) + ─(1) + ─(1) + ┐(1) = 6
    // Line 2: │(1) + 你(2) + 好(2) + │(1) = 6
    // Line 3: └(1) + ─(1) + ─(1) + ─(1) + ─(1) + ┘(1) = 6
    try std.testing.expectEqual(@as(usize, 6), size.width);
    try std.testing.expectEqual(@as(usize, 3), size.height);
}

test "measureLine - many spans with varied content" {
    var spans: [4]Span = .{
        Span.raw("a"),
        Span.raw("你"),
        Span.raw("b"),
        Span.raw("好"),
    };
    const line = Line{ .spans = &spans };
    const size = measureLine(line, .{});
    // a(1) + 你(2) + b(1) + 好(2) = 6
    try std.testing.expectEqual(@as(usize, 6), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - width exactly matches line length" {
    const size = measureText("exactly", .{});
    try std.testing.expectEqual(@as(usize, 7), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - single character" {
    const size = measureText("x", .{});
    try std.testing.expectEqual(@as(usize, 1), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - single CJK character" {
    const size = measureText("日", .{});
    try std.testing.expectEqual(@as(usize, 2), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}

test "measureText - alternating ASCII and CJK" {
    const size = measureText("a日b月c星", .{});
    // a(1) + 日(2) + b(1) + 月(2) + c(1) + 星(2) = 9
    try std.testing.expectEqual(@as(usize, 9), size.width);
    try std.testing.expectEqual(@as(usize, 1), size.height);
}
