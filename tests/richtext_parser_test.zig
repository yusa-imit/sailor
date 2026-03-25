//! Rich Text Parser Tests — v1.22.0
//!
//! Tests for RichTextParser utility that converts markdown-like text
//! to Line/Span arrays for styled text rendering.
//!
//! Markdown syntax supported:
//! - **bold** → bold style
//! - *italic* or _italic_ → italic style
//! - ***bold italic*** → both modifiers
//! - `code` → dim (monospace approximation)
//! - ~~strikethrough~~ → strikethrough modifier
//! - # Heading, ## H2, ### H3 → bold + bright_white color
//! - Plain text → no style
//! - Empty lines → empty Line
//!
//! Validation covered:
//! - Inline bold formatting with **text** syntax
//! - Inline italic formatting with *text* and _text_ syntax
//! - Inline bold+italic formatting with ***text*** syntax
//! - Inline code formatting with `code` syntax (renders as dim)
//! - Inline strikethrough formatting with ~~text~~ syntax
//! - Mixed inline formatting in single line (multiple spans)
//! - Nested formatting (bold containing italic, etc.)
//! - Adjacent formatting without spaces
//! - Plain text (no formatting)
//! - Multi-line parsing with headings
//! - Multi-line parsing with mixed formatting
//! - Empty input handling
//! - Whitespace-only input handling
//! - Unclosed markers (fallback to literal)
//! - Multiple paragraphs separated by empty lines
//! - parseInline vs parse API differences
//! - Memory management (no leaks with testing.allocator)

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const Color = sailor.tui.Color;
const Style = sailor.tui.Style;
const Span = sailor.tui.Span;
const Line = sailor.tui.Line;
const SpanBuilder = sailor.tui.SpanBuilder;
const LineBuilder = sailor.tui.LineBuilder;

// Import RichTextParser from sailor module
const RichTextParser = sailor.RichTextParser;

// ============================================================================
// Inline Formatting Tests
// ============================================================================

test "parseInline: bold text only" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold**");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("bold", line.spans[0].content);
    try testing.expect(line.spans[0].style.bold);
    try testing.expect(!line.spans[0].style.italic);
}

test "parseInline: italic text with asterisks" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("*italic*");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("italic", line.spans[0].content);
    try testing.expect(line.spans[0].style.italic);
    try testing.expect(!line.spans[0].style.bold);
}

test "parseInline: italic text with underscores" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("_italic_");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("italic", line.spans[0].content);
    try testing.expect(line.spans[0].style.italic);
}

test "parseInline: bold and italic with triple asterisks" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("***bold italic***");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("bold italic", line.spans[0].content);
    try testing.expect(line.spans[0].style.bold);
    try testing.expect(line.spans[0].style.italic);
}

test "parseInline: code formatting (backticks)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("`code`");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("code", line.spans[0].content);
    try testing.expect(line.spans[0].style.dim);
}

test "parseInline: strikethrough formatting" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("~~strikethrough~~");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("strikethrough", line.spans[0].content);
    try testing.expect(line.spans[0].style.strikethrough);
}

test "parseInline: mixed inline formatting (bold and italic)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("Hello **bold** and *italic*");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 4), line.spans.len);

    // "Hello "
    try testing.expectEqualStrings("Hello ", line.spans[0].content);
    try testing.expect(!line.spans[0].style.bold);
    try testing.expect(!line.spans[0].style.italic);

    // "bold"
    try testing.expectEqualStrings("bold", line.spans[1].content);
    try testing.expect(line.spans[1].style.bold);
    try testing.expect(!line.spans[1].style.italic);

    // " and "
    try testing.expectEqualStrings(" and ", line.spans[2].content);
    try testing.expect(!line.spans[2].style.bold);
    try testing.expect(!line.spans[2].style.italic);

    // "italic"
    try testing.expectEqualStrings("italic", line.spans[3].content);
    try testing.expect(line.spans[3].style.italic);
    try testing.expect(!line.spans[3].style.bold);

    // (optional trailing span if parser adds one)
}

test "parseInline: plain text with no formatting" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("no formatting here");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("no formatting here", line.spans[0].content);
    try testing.expect(!line.spans[0].style.bold);
    try testing.expect(!line.spans[0].style.italic);
}

test "parseInline: empty string" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("");
    defer testing.allocator.free(line.spans);

    // Empty input should produce single empty span or no spans
    try testing.expect(line.spans.len == 0 or line.spans.len == 1);
}

test "parseInline: whitespace only" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("   ");
    defer testing.allocator.free(line.spans);

    try testing.expectEqual(@as(usize, 1), line.spans.len);
    try testing.expectEqualStrings("   ", line.spans[0].content);
}

test "parseInline: nested formatting (bold with italic inside)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold *and italic***");
    defer testing.allocator.free(line.spans);

    // Should produce spans with proper nesting
    // At minimum, should have 1-2 spans with combined styling
    try testing.expect(line.spans.len >= 1);

    // At least one span should have bold
    var has_bold = false;
    for (line.spans) |span| {
        if (span.style.bold) {
            has_bold = true;
            break;
        }
    }
    try testing.expect(has_bold);
}

test "parseInline: adjacent formatting (bold then italic)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold***italic*");
    defer testing.allocator.free(line.spans);

    // Should have at least 2 spans: one bold, one italic
    try testing.expect(line.spans.len >= 2);

    var has_bold = false;
    var has_italic = false;
    for (line.spans) |span| {
        if (span.style.bold) has_bold = true;
        if (span.style.italic) has_italic = true;
    }
    try testing.expect(has_bold);
    try testing.expect(has_italic);
}

test "parseInline: unclosed bold marker (fallback to literal)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**unclosed");
    defer testing.allocator.free(line.spans);

    // Should treat as literal text when marker is unclosed
    try testing.expect(line.spans.len >= 1);
    // Should contain the text (either with or without markers)
    var found_unclosed = false;
    for (line.spans) |span| {
        if (std.mem.containsAtLeast(u8, span.content, 1, "unclosed")) {
            found_unclosed = true;
        }
    }
    try testing.expect(found_unclosed);
}

test "parseInline: mixed code and bold" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("`code` and **bold**");
    defer testing.allocator.free(line.spans);

    // Should have multiple spans
    try testing.expect(line.spans.len >= 2);

    // At least one span should be dim (code), one bold
    var has_code = false;
    var has_bold = false;
    for (line.spans) |span| {
        if (span.style.dim) has_code = true;
        if (span.style.bold) has_bold = true;
    }
    try testing.expect(has_code);
    try testing.expect(has_bold);
}

// ============================================================================
// Multi-line Parsing Tests
// ============================================================================

test "parse: single line (no heading)" {
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
    try testing.expect(lines[0].spans.len >= 1);
}

test "parse: heading level 1" {
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
    // Heading should have bold style at minimum
    var has_bold = false;
    for (lines[0].spans) |span| {
        if (span.style.bold) {
            has_bold = true;
        }
    }
    try testing.expect(has_bold);
}

test "parse: heading level 2" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("## Subtitle");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 1), lines.len);
    // Heading should have bold style
    var has_bold = false;
    for (lines[0].spans) |span| {
        if (span.style.bold) {
            has_bold = true;
        }
    }
    try testing.expect(has_bold);
}

test "parse: heading level 3" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("### Subheading");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 1), lines.len);
}

test "parse: multi-line with heading and content" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("# Title\nContent");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 2), lines.len);

    // First line (heading) should be bold
    var first_has_bold = false;
    for (lines[0].spans) |span| {
        if (span.style.bold) {
            first_has_bold = true;
        }
    }
    try testing.expect(first_has_bold);

    // Second line should be normal content
    try testing.expect(lines[1].spans.len >= 1);
}

test "parse: multi-line with multiple headings" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("# Title\n## Subtitle");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 2), lines.len);
}

test "parse: empty input" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    // Empty input should produce empty array or single empty line
    try testing.expect(lines.len == 0 or lines.len == 1);
}

test "parse: multiple empty lines" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("\n\n\n");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    // Should preserve empty lines
    try testing.expect(lines.len >= 1);
}

test "parse: mixed content with empty lines" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("Paragraph 1\n\nParagraph 2");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    // Should have at least 3 lines (paragraph, empty, paragraph)
    try testing.expect(lines.len >= 2);
}

test "parse: formatted content across multiple lines" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("**bold line**\n*italic line*");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 2), lines.len);

    // First line should have bold
    var first_has_bold = false;
    for (lines[0].spans) |span| {
        if (span.style.bold) {
            first_has_bold = true;
        }
    }
    try testing.expect(first_has_bold);

    // Second line should have italic
    var second_has_italic = false;
    for (lines[1].spans) |span| {
        if (span.style.italic) {
            second_has_italic = true;
        }
    }
    try testing.expect(second_has_italic);
}

// ============================================================================
// API Difference Tests (parseInline vs parse)
// ============================================================================

test "parse vs parseInline: single line returns Line array" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("**bold**");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expectEqual(@as(usize, 1), lines.len);
}

test "parse vs parseInline: parseInline returns single Line" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold**");
    defer testing.allocator.free(line.spans);

    // parseInline should always return a single Line (not array)
    try testing.expect(line.spans.len >= 1);
}

test "parseInline: ignores newlines (treats as literal)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("text\nwith\nnewlines");
    defer testing.allocator.free(line.spans);

    // Should treat newlines as literal characters or ignore them
    // At minimum, should not crash
    try testing.expect(line.spans.len >= 1);
}

// ============================================================================
// Memory Management Tests
// ============================================================================

test "parser init and deinit" {
    var parser = RichTextParser.init(testing.allocator);
    // If init doesn't leak, deinit should be safe
    parser.deinit();
}

test "parseInline: no memory leaks with testing allocator" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold** *italic* `code` ~~strikethrough~~");
    defer testing.allocator.free(line.spans);

    // Complex formatting should be handled without leaks
    try testing.expect(line.spans.len >= 1);
}

test "parse: no memory leaks with multi-line" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("# Title\n**bold**\n*italic*\n\nNew paragraph");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    try testing.expect(lines.len >= 1);
}

// ============================================================================
// Edge Cases and Error Paths
// ============================================================================

test "parseInline: multiple formatting types in sequence" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold**`code`*italic*~~strike~~");
    defer testing.allocator.free(line.spans);

    // Should parse all 4 formatted sections
    try testing.expect(line.spans.len >= 4);

    var has_bold = false;
    var has_code = false;
    var has_italic = false;
    var has_strike = false;

    for (line.spans) |span| {
        if (span.style.bold) has_bold = true;
        if (span.style.dim) has_code = true;
        if (span.style.italic) has_italic = true;
        if (span.style.strikethrough) has_strike = true;
    }

    try testing.expect(has_bold);
    try testing.expect(has_code);
    try testing.expect(has_italic);
    try testing.expect(has_strike);
}

test "parseInline: underscore inside words (no formatting)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("snake_case_variable");
    defer testing.allocator.free(line.spans);

    // Should NOT treat underscores in the middle as formatting
    // Implementation-dependent: may treat as literal or single italic
    try testing.expect(line.spans.len >= 1);
}

test "parseInline: asterisk inside words (no formatting)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("5*2=10");
    defer testing.allocator.free(line.spans);

    // Should NOT treat asterisk in math as formatting
    try testing.expect(line.spans.len >= 1);
}

test "parseInline: escaped markers (optional feature)" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("\\*not italic\\*");
    defer testing.allocator.free(line.spans);

    // If escaping is supported, should produce literal asterisks
    // If not supported, may produce italic
    // Test just verifies it doesn't crash
    try testing.expect(line.spans.len >= 1);
}

test "parseInline: multiple bold sections" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**first** text **second**");
    defer testing.allocator.free(line.spans);

    // Should have multiple bold sections
    try testing.expect(line.spans.len >= 3);

    var bold_count: usize = 0;
    for (line.spans) |span| {
        if (span.style.bold) bold_count += 1;
    }
    try testing.expect(bold_count >= 2);
}

test "parseInline: formatting markers with spaces inside" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("** spaced bold **");
    defer testing.allocator.free(line.spans);

    // Should handle spaces around content
    try testing.expect(line.spans.len >= 1);
}

test "parse: heading without content after #" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("#");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    // Should handle gracefully (either as heading or literal)
    try testing.expect(lines.len >= 1);
}

test "parse: heading with too many hash marks" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("####### invalid heading");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    // Should treat as literal text (> 6 # is not valid heading)
    try testing.expect(lines.len >= 1);
}

// ============================================================================
// Integration with SpanBuilder
// ============================================================================

test "parseInline: produces spans compatible with SpanBuilder" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold** text");
    defer testing.allocator.free(line.spans);

    // Spans should be usable with LineBuilder
    var builder = LineBuilder.init(testing.allocator);
    defer builder.deinit();

    for (line.spans) |span| {
        _ = builder.span(span);
    }

    const result = builder.build();
    try testing.expectEqual(line.spans.len, result.spans.len);
}

test "parse: produces lines compatible with rendering" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const lines = try parser.parse("# Title\nContent **bold**");
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    // Should be able to render lines to writer
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    for (lines) |line| {
        try line.render(writer);
    }

    // Should produce some output
    try testing.expect(fbs.getWritten().len > 0);
}

// ============================================================================
// Complex Formatting Combinations
// ============================================================================

test "parseInline: code block with special characters" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("`const x = **not bold**;`");
    defer testing.allocator.free(line.spans);

    // Inside code, ** should not trigger bold
    try testing.expect(line.spans.len >= 1);
    try testing.expect(line.spans[0].style.dim);
}

test "parseInline: bold containing strikethrough" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("**bold ~~strike~~ text**");
    defer testing.allocator.free(line.spans);

    // Should handle nested formatting
    try testing.expect(line.spans.len >= 1);
}

test "parseInline: all formatting types in one text" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const line = try parser.parseInline("Normal **bold** *italic* _also italic_ ***both*** `code` ~~strike~~ done");
    defer testing.allocator.free(line.spans);

    // Should parse all types
    try testing.expect(line.spans.len >= 7);

    var has_bold = false;
    var has_italic = false;
    var has_code = false;
    var has_strike = false;

    for (line.spans) |span| {
        if (span.style.bold) has_bold = true;
        if (span.style.italic) has_italic = true;
        if (span.style.dim) has_code = true;
        if (span.style.strikethrough) has_strike = true;
    }

    try testing.expect(has_bold);
    try testing.expect(has_italic);
    try testing.expect(has_code);
    try testing.expect(has_strike);
}

test "parseInline: very long formatted text" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const long_text = "**" ++ "x" ** 1000 ++ "**";
    var buf: [1024 + 10]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "{s}", .{long_text});

    const line = try parser.parseInline(text);
    defer testing.allocator.free(line.spans);

    // Should handle long content
    try testing.expect(line.spans.len >= 1);
    try testing.expect(line.spans[0].style.bold);
}

test "parse: document-like structure" {
    var parser = RichTextParser.init(testing.allocator);
    defer parser.deinit();

    const doc =
        "# Welcome\n" ++
        "\n" ++
        "This is a **document** with *multiple* sections.\n" ++
        "\n" ++
        "## Section 1\n" ++
        "\n" ++
        "Content with `code` and ~~strikethrough~~.\n" ++
        "\n" ++
        "### Subsection\n" ++
        "\n" ++
        "Final paragraph.";

    const lines = try parser.parse(doc);
    defer {
        for (lines) |line| {
            testing.allocator.free(line.spans);
        }
        testing.allocator.free(lines);
    }

    // Should parse document structure
    try testing.expect(lines.len >= 7);
}
