//! Rich Text Parser — v1.22.0
//!
//! Converts markdown-like text to styled Line/Span arrays.
//!
//! Supported markdown:
//! - **bold** → bold style
//! - *italic* or _italic_ → italic style
//! - ***bold italic*** → both modifiers
//! - `code` → dim style
//! - ~~strikethrough~~ → strikethrough modifier
//! - # Heading (1-6) → bold + bright_white
//!
//! Edge cases:
//! - Unclosed markers → treated as literal text
//! - Tight binding required: no space after opening marker
//! - Underscore/asterisk in words requires careful handling

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const style_mod = @import("style.zig");
const Span = style_mod.Span;
const Line = style_mod.Line;
const Style = style_mod.Style;
const Color = style_mod.Color;
const SpanBuilder = style_mod.SpanBuilder;
const LineBuilder = style_mod.LineBuilder;

pub const RichTextParser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) RichTextParser {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RichTextParser) void {
        _ = self; // Parser doesn't own persistent state
    }

    /// Parse markdown text to Line array (multi-line, headings supported)
    /// Returns owned slice - caller must free both lines array and spans within each line
    pub fn parse(self: *RichTextParser, text: []const u8) ![]Line {
        var lines_list = ArrayList(Line){};
        defer lines_list.deinit(self.allocator);

        // Handle empty input
        if (text.len == 0) {
            return try self.allocator.dupe(Line, &[_]Line{});
        }

        var start: usize = 0;

        while (start < text.len) {
            // Find next newline
            var end = start;
            while (end < text.len and text[end] != '\n') {
                end += 1;
            }

            // Extract line content
            const line_text = text[start..end];

            // Parse line (handles both headings and inline)
            const line = try self.parseInline(line_text);
            try lines_list.append(self.allocator, line);

            // Move to next line (skip newline)
            start = end + 1;
        }

        return try lines_list.toOwnedSlice(self.allocator);
    }

    /// Parse single-line markdown with inline formatting only
    /// Returns owned Line with owned spans - caller must free Line.spans
    pub fn parseInline(self: *RichTextParser, text: []const u8) !Line {
        var builder = LineBuilder.init(self.allocator);
        defer builder.deinit();

        // Check if this is a heading
        const heading_result = tryParseHeading(text);
        if (heading_result.is_heading) {
            const heading_text = heading_result.content;
            const heading_style = Style{
                .bold = true,
                .fg = .bright_white,
            };
            _ = builder.text(heading_text, heading_style);
            return try builder.buildOwned();
        }

        // Parse inline formatting
        try self.parseInlineMarkdown(text, &builder);

        return try builder.buildOwned();
    }

    // ========================================================================
    // Heading Detection
    // ========================================================================

    fn tryParseHeading(text: []const u8) struct { is_heading: bool, content: []const u8 } {
        // Count leading # characters
        var hash_count: usize = 0;
        var i: usize = 0;

        while (i < text.len and text[i] == '#') {
            hash_count += 1;
            i += 1;
        }

        // Valid heading: 1-6 hashes followed by space
        if (hash_count > 0 and hash_count <= 6 and i < text.len and text[i] == ' ') {
            return .{
                .is_heading = true,
                .content = std.mem.trim(u8, text[i + 1 ..], " "),
            };
        }

        return .{
            .is_heading = false,
            .content = text,
        };
    }

    // ========================================================================
    // Inline Markdown Parsing
    // ========================================================================

    fn parseInlineMarkdown(self: *RichTextParser, text: []const u8, builder: *LineBuilder) !void {
        var pos: usize = 0;

        while (pos < text.len) {
            // Try to match formatters in order of specificity (longest first)

            // Try *** (bold+italic)
            if (pos + 6 <= text.len and std.mem.eql(u8, text[pos .. pos + 3], "***")) {
                if (tryMatchMarker(text, pos, "***")) |match| {
                    if (pos > 0) _ = builder.raw(text[0..pos]);
                    const style = Style{ .bold = true, .italic = true };
                    _ = builder.text(match.content, style);
                    return self.parseInlineMarkdown(text[match.end_pos..], builder);
                }
            }

            // Try ** (bold)
            if (pos + 4 <= text.len and std.mem.eql(u8, text[pos .. pos + 2], "**")) {
                if (tryMatchMarker(text, pos, "**")) |match| {
                    if (pos > 0) _ = builder.raw(text[0..pos]);
                    const style = Style{ .bold = true };
                    _ = builder.text(match.content, style);
                    return self.parseInlineMarkdown(text[match.end_pos..], builder);
                }
            }

            // Try ~~ (strikethrough)
            if (pos + 4 <= text.len and std.mem.eql(u8, text[pos .. pos + 2], "~~")) {
                if (tryMatchMarker(text, pos, "~~")) |match| {
                    if (pos > 0) _ = builder.raw(text[0..pos]);
                    const style = Style{ .strikethrough = true };
                    _ = builder.text(match.content, style);
                    return self.parseInlineMarkdown(text[match.end_pos..], builder);
                }
            }

            // Try ` (backtick code)
            if (text[pos] == '`') {
                if (tryMatchMarker(text, pos, "`")) |match| {
                    if (pos > 0) _ = builder.raw(text[0..pos]);
                    const style = Style{ .dim = true };
                    _ = builder.text(match.content, style);
                    return self.parseInlineMarkdown(text[match.end_pos..], builder);
                }
            }

            // Try * (italic) — must avoid matching word-internal asterisks
            if (text[pos] == '*' and !isWordInternalMarker(text, pos, '*')) {
                if (tryMatchMarker(text, pos, "*")) |match| {
                    if (pos > 0) _ = builder.raw(text[0..pos]);
                    const style = Style{ .italic = true };
                    _ = builder.text(match.content, style);
                    return self.parseInlineMarkdown(text[match.end_pos..], builder);
                }
            }

            // Try _ (italic) — must avoid matching word-internal underscores
            if (text[pos] == '_' and !isWordInternalMarker(text, pos, '_')) {
                if (tryMatchMarker(text, pos, "_")) |match| {
                    if (pos > 0) _ = builder.raw(text[0..pos]);
                    const style = Style{ .italic = true };
                    _ = builder.text(match.content, style);
                    return self.parseInlineMarkdown(text[match.end_pos..], builder);
                }
            }

            // No match, advance
            pos += 1;
        }

        // No formatting found, add entire text as plain
        if (text.len > 0) {
            _ = builder.raw(text);
        }
    }

    // ========================================================================
    // Marker Matching Helpers
    // ========================================================================

    fn isWordInternalMarker(text: []const u8, pos: usize, _: u8) bool {
        // Check if marker is surrounded by word characters (not formatting)
        const is_after_word = pos > 0 and isWordChar(text[pos - 1]);
        const is_before_word = pos + 1 < text.len and isWordChar(text[pos + 1]);

        return is_after_word and is_before_word;
    }

    fn isWordChar(ch: u8) bool {
        return (ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or
            ch == '_';
    }
};

const MatchResult = struct {
    content: []const u8,
    end_pos: usize,
};

fn tryMatchMarker(text: []const u8, start_pos: usize, marker: []const u8) ?MatchResult {
    const open_pos = start_pos;
    const content_start = open_pos + marker.len;

    // Check tight binding: no space immediately after opening marker
    if (content_start < text.len and text[content_start] == ' ') {
        return null;
    }

    // Find closing marker
    var close_pos = content_start;
    while (close_pos + marker.len <= text.len) {
        if (std.mem.eql(u8, text[close_pos .. close_pos + marker.len], marker)) {
            // Found closing marker
            const content = text[content_start..close_pos];

            // Check tight binding for closing: no space before it
            if (content.len > 0 and text[close_pos - 1] == ' ') {
                close_pos += 1;
                continue;
            }

            return MatchResult{
                .content = content,
                .end_pos = close_pos + marker.len,
            };
        }
        close_pos += 1;
    }

    // No closing marker found
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "RichTextParser.init and deinit" {
    const testing = std.testing;
    var parser = RichTextParser.init(testing.allocator);
    parser.deinit();
}

test "parseInline: bold text only" {
    const testing = std.testing;
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold**");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("bold", line.spans[0].content);
    try testing.expect(line.spans[0].style.bold);
}

test "parseInline: plain text" {
    const testing = std.testing;
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("plain text");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("plain text", line.spans[0].content);
}

test "parse: single line" {
    const testing = std.testing;
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("Hello world");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 1), lines.len);
}

test "parse: heading" {
    const testing = std.testing;
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("# Title");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 1), lines.len);
    var has_bold = false;
    for (lines[0].spans) |span| {
        if (span.style.bold) {
            has_bold = true;
        }
    }
    try testing.expect(has_bold);
}
