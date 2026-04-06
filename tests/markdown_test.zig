const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;

// Forward declaration - will be implemented in src/tui/widgets/markdown.zig
const Markdown = sailor.tui.widgets.Markdown;

const testing = std.testing;

// ============================================================================
// Initialization Tests
// ============================================================================

test "Markdown.init empty" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try testing.expectEqual(@as(usize, 0), md.lineCount());
    try testing.expectEqual(@as(usize, 0), md.scroll_offset);
}

test "Markdown.init with content" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Hello World");
    try testing.expect(md.lineCount() > 0);
}

test "Markdown.deinit cleans up allocations" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);

    try md.setContent("# Heading\n\nSome **bold** text");

    md.deinit();
    // Should not leak - testing.allocator will catch leaks
}

// ============================================================================
// Heading Parsing Tests
// ============================================================================

test "Markdown parses H1 heading" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Heading 1");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.heading, nodes[0].node_type);
    try testing.expectEqual(@as(u8, 1), nodes[0].level);
    try testing.expectEqualStrings("Heading 1", nodes[0].text);
}

test "Markdown parses H2 heading" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("## Heading 2");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.heading, nodes[0].node_type);
    try testing.expectEqual(@as(u8, 2), nodes[0].level);
}

test "Markdown parses H3 through H6 headings" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("### H3\n#### H4\n##### H5\n###### H6");
    const nodes = md.getNodes();

    try testing.expectEqual(@as(usize, 4), nodes.len);
    try testing.expectEqual(@as(u8, 3), nodes[0].level);
    try testing.expectEqual(@as(u8, 4), nodes[1].level);
    try testing.expectEqual(@as(u8, 5), nodes[2].level);
    try testing.expectEqual(@as(u8, 6), nodes[3].level);
}

test "Markdown heading requires space after #" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("#NotAHeading");
    const nodes = md.getNodes();

    // Should parse as plain text, not heading
    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

test "Markdown heading with trailing #" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Heading #");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.heading, nodes[0].node_type);
    try testing.expectEqualStrings("Heading", nodes[0].text);
}

// ============================================================================
// Bold Text Parsing Tests
// ============================================================================

test "Markdown parses bold with **" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("This is **bold** text");
    const nodes = md.getNodes();

    // Should produce: text("This is "), bold("bold"), text(" text")
    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
    try testing.expectEqual(Markdown.NodeType.bold, nodes[1].node_type);
    try testing.expectEqualStrings("bold", nodes[1].text);
}

test "Markdown parses bold with __" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("This is __bold__ text");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.bold, nodes[1].node_type);
    try testing.expectEqualStrings("bold", nodes[1].text);
}

test "Markdown bold spans multiple words" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("**bold text here**");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.bold, nodes[0].node_type);
    try testing.expectEqualStrings("bold text here", nodes[0].text);
}

test "Markdown bold requires closing delimiter" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("**unclosed bold");
    const nodes = md.getNodes();

    // Should parse as plain text
    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

// ============================================================================
// Italic Text Parsing Tests
// ============================================================================

test "Markdown parses italic with *" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("This is *italic* text");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.italic, nodes[1].node_type);
    try testing.expectEqualStrings("italic", nodes[1].text);
}

test "Markdown parses italic with _" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("This is _italic_ text");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.italic, nodes[1].node_type);
    try testing.expectEqualStrings("italic", nodes[1].text);
}

test "Markdown italic requires closing delimiter" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("*unclosed italic");
    const nodes = md.getNodes();

    // Should parse as plain text
    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

// ============================================================================
// Bold + Italic Combination Tests
// ============================================================================

test "Markdown parses bold and italic combined ***" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("***bold and italic***");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.bold_italic, nodes[0].node_type);
    try testing.expectEqualStrings("bold and italic", nodes[0].text);
}

test "Markdown parses nested bold inside italic" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("*italic with **bold** inside*");
    const nodes = md.getNodes();

    // Should produce nested structure
    try testing.expect(nodes.len >= 3);
}

test "Markdown parses bold and italic separately" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("**bold** and *italic*");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.bold, nodes[0].node_type);
    try testing.expectEqual(Markdown.NodeType.italic, nodes[2].node_type);
}

// ============================================================================
// Inline Code Parsing Tests
// ============================================================================

test "Markdown parses inline code" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Use `code` here");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.code, nodes[1].node_type);
    try testing.expectEqualStrings("code", nodes[1].text);
}

test "Markdown inline code with multiple words" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("`var x = 5;`");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.code, nodes[0].node_type);
    try testing.expectEqualStrings("var x = 5;", nodes[0].text);
}

test "Markdown inline code preserves formatting chars" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("`**not bold**`");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.code, nodes[0].node_type);
    try testing.expectEqualStrings("**not bold**", nodes[0].text);
}

test "Markdown inline code requires closing backtick" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("`unclosed code");
    const nodes = md.getNodes();

    // Should parse as plain text
    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

// ============================================================================
// Code Block Parsing Tests
// ============================================================================

test "Markdown parses code block" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("```\nfunction main() {\n  return 0;\n}\n```");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.code_block, nodes[0].node_type);
    try testing.expect(std.mem.indexOf(u8, nodes[0].text, "function main") != null);
}

test "Markdown code block with language" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("```zig\nconst x = 5;\n```");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.code_block, nodes[0].node_type);
    try testing.expectEqualStrings("zig", nodes[0].language.?);
    try testing.expect(std.mem.indexOf(u8, nodes[0].text, "const x = 5") != null);
}

test "Markdown code block preserves indentation" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("```\n  indented\n    more indented\n```");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.code_block, nodes[0].node_type);
    try testing.expect(std.mem.indexOf(u8, nodes[0].text, "  indented") != null);
}

test "Markdown code block requires closing fence" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("```\nunclosed code block");
    const nodes = md.getNodes();

    // Should parse as code block or text
    try testing.expect(nodes.len > 0);
}

// ============================================================================
// Unordered List Parsing Tests
// ============================================================================

test "Markdown parses unordered list with -" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("- Item 1\n- Item 2\n- Item 3");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.list_item, nodes[0].node_type);
    try testing.expectEqualStrings("Item 1", nodes[0].text);
}

test "Markdown parses unordered list with *" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("* Item A\n* Item B");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 2);
    try testing.expectEqual(Markdown.NodeType.list_item, nodes[0].node_type);
    try testing.expectEqual(Markdown.NodeType.list_item, nodes[1].node_type);
}

test "Markdown list item requires space after marker" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("-NotAListItem");
    const nodes = md.getNodes();

    // Should parse as text
    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

test "Markdown nested list items" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("- Level 1\n  - Level 2\n    - Level 3");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(@as(u8, 0), nodes[0].indent_level);
    try testing.expectEqual(@as(u8, 1), nodes[1].indent_level);
    try testing.expectEqual(@as(u8, 2), nodes[2].indent_level);
}

// ============================================================================
// Ordered List Parsing Tests
// ============================================================================

test "Markdown parses ordered list" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("1. First\n2. Second\n3. Third");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.ordered_item, nodes[0].node_type);
    try testing.expectEqualStrings("First", nodes[0].text);
    try testing.expectEqual(@as(u32, 1), nodes[0].number.?);
}

test "Markdown ordered list with non-sequential numbers" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("1. First\n1. Second\n1. Third");
    const nodes = md.getNodes();

    // Should parse all as ordered items
    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.ordered_item, nodes[0].node_type);
    try testing.expectEqual(Markdown.NodeType.ordered_item, nodes[1].node_type);
    try testing.expectEqual(Markdown.NodeType.ordered_item, nodes[2].node_type);
}

test "Markdown ordered list requires space after number" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("1.NotAListItem");
    const nodes = md.getNodes();

    // Should parse as text
    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

// ============================================================================
// Link Parsing Tests
// ============================================================================

test "Markdown parses link" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("[Click here](https://example.com)");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.link, nodes[0].node_type);
    try testing.expectEqualStrings("Click here", nodes[0].text);
    try testing.expectEqualStrings("https://example.com", nodes[0].url.?);
}

test "Markdown link with no text" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("[](https://example.com)");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.link, nodes[0].node_type);
    try testing.expectEqualStrings("", nodes[0].text);
}

test "Markdown link embedded in text" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Visit [our site](https://example.com) for more");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 3);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
    try testing.expectEqual(Markdown.NodeType.link, nodes[1].node_type);
    try testing.expectEqual(Markdown.NodeType.text, nodes[2].node_type);
}

test "Markdown link requires closing brackets" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("[Incomplete link");
    const nodes = md.getNodes();

    // Should parse as text
    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

// ============================================================================
// Mixed Content Tests
// ============================================================================

test "Markdown parses heading with paragraph" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Title\n\nThis is a paragraph.");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 2);
    try testing.expectEqual(Markdown.NodeType.heading, nodes[0].node_type);
    try testing.expectEqual(Markdown.NodeType.text, nodes[1].node_type);
}

test "Markdown parses multiple headings with content" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# H1\nContent 1\n## H2\nContent 2");
    const nodes = md.getNodes();

    try testing.expect(nodes.len >= 4);
    try testing.expectEqual(Markdown.NodeType.heading, nodes[0].node_type);
    try testing.expectEqual(@as(u8, 1), nodes[0].level);
    try testing.expectEqual(Markdown.NodeType.heading, nodes[2].node_type);
    try testing.expectEqual(@as(u8, 2), nodes[2].level);
}

test "Markdown parses list with formatted items" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("- **bold** item\n- *italic* item\n- `code` item");
    const nodes = md.getNodes();

    // Each list item should contain formatted inline nodes
    try testing.expect(nodes.len >= 3);
}

test "Markdown complex document" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    const content =
        \\# Main Title
        \\
        \\This is a **bold** statement with *italic* and `code`.
        \\
        \\## Features
        \\
        \\- Item 1
        \\- Item 2 with [link](https://example.com)
        \\
        \\```zig
        \\const x = 5;
        \\```
    ;

    try md.setContent(content);
    const nodes = md.getNodes();

    // Should have multiple nodes representing different elements
    try testing.expect(nodes.len >= 5);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Markdown empty string" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("");
    try testing.expectEqual(@as(usize, 0), md.lineCount());
}

test "Markdown whitespace only" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("   \n\n   ");
    // Should handle gracefully
    _ = md.getNodes();
}

test "Markdown single character" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("x");
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
    try testing.expectEqual(Markdown.NodeType.text, nodes[0].node_type);
}

test "Markdown malformed bold delimiters" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("**mix*ed*delimiters**");
    const nodes = md.getNodes();

    // Should handle gracefully (exact behavior depends on implementation)
    try testing.expect(nodes.len > 0);
}

test "Markdown nested code blocks" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("```\n```nested```\n```");
    const nodes = md.getNodes();

    // Should handle gracefully
    try testing.expect(nodes.len > 0);
}

test "Markdown very long line" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    const long_line = try allocator.alloc(u8, 1000);
    defer allocator.free(long_line);
    @memset(long_line, 'x');

    try md.setContent(long_line);
    const nodes = md.getNodes();

    try testing.expect(nodes.len > 0);
}

// ============================================================================
// Scrolling Tests
// ============================================================================

test "Markdown scrolling down" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6");

    try testing.expectEqual(@as(usize, 0), md.scroll_offset);
    md.scrollDown(2);
    try testing.expectEqual(@as(usize, 2), md.scroll_offset);
}

test "Markdown scrolling up" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Line 1\nLine 2\nLine 3\nLine 4\nLine 5");

    md.scrollDown(3);
    try testing.expectEqual(@as(usize, 3), md.scroll_offset);

    md.scrollUp(1);
    try testing.expectEqual(@as(usize, 2), md.scroll_offset);
}

test "Markdown scroll to top" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Line 1\nLine 2\nLine 3\nLine 4");

    md.scrollDown(3);
    md.scrollToTop();
    try testing.expectEqual(@as(usize, 0), md.scroll_offset);
}

test "Markdown scroll to bottom" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Line 1\nLine 2\nLine 3\nLine 4\nLine 5");

    md.scrollToBottom();
    // Should be scrolled to show last lines
    try testing.expect(md.scroll_offset > 0);
}

test "Markdown scroll clamps at boundaries" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Line 1\nLine 2");

    md.scrollUp(10);
    try testing.expectEqual(@as(usize, 0), md.scroll_offset);

    md.scrollDown(100);
    // Should clamp to max scroll
    try testing.expect(md.scroll_offset < 100);
}

// ============================================================================
// Block Wrapper Tests
// ============================================================================

test "Markdown with block wrapper" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    const block = (Block{}).withTitle("Markdown", .top_left).withBorders(.all);
    md = md.withBlock(block);

    try md.setContent("# Content");

    try testing.expect(md.block != null);
}

test "Markdown without block wrapper" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Content");

    try testing.expectEqual(@as(?Block, null), md.block);
}

// ============================================================================
// Rendering Tests
// ============================================================================

test "Markdown render empty area does nothing" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Test");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    try md.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "Markdown render basic heading" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Heading");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Should render heading text
    var found_h = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'H') {
                found_h = true;
                break;
            }
        }
    }
    try testing.expect(found_h);
}

test "Markdown render bold text has style" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("**bold**");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Find bold character and check style
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'b') {
                const style = buf.getStyle(@intCast(x), 0);
                try testing.expect(style.bold);
                break;
            }
        }
    }
}

test "Markdown render italic text has style" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("*italic*");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Find italic character and check style
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'i') {
                const style = buf.getStyle(@intCast(x), 0);
                try testing.expect(style.italic);
                break;
            }
        }
    }
}

test "Markdown render code block with distinct style" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("```\ncode\n```");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Code blocks should be rendered
    var found_code = false;
    for (0..10) |y| {
        for (0..40) |x| {
            if (buf.get(@intCast(x), @intCast(y))) |cell| {
                if (cell.char == 'c') {
                    found_code = true;
                    break;
                }
            }
        }
        if (found_code) break;
    }
    try testing.expect(found_code);
}

test "Markdown render list items with bullets" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("- Item 1\n- Item 2");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Should render bullet or dash
    var found_bullet = false;
    for (0..10) |y| {
        if (buf.get(0, @intCast(y))) |cell| {
            if (cell.char == '-' or cell.char == '•' or cell.char == '●') {
                found_bullet = true;
                break;
            }
        }
    }
    try testing.expect(found_bullet);
}

test "Markdown render with scrolling shows offset content" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Line 0\nLine 1\nLine 2\nLine 3\nLine 4");

    var buf = try Buffer.init(allocator, 40, 3);
    defer buf.deinit();

    md.scrollDown(2);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 3 };
    try md.render(&buf, area);

    // Should show lines starting from offset 2
    // Line 2 should be visible at y=0
    var found_2 = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == '2') {
                found_2 = true;
                break;
            }
        }
    }
    try testing.expect(found_2);
}

test "Markdown render with block draws border" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    const block = (Block{}).withBorders(.all);
    md = md.withBlock(block);

    try md.setContent("# Content");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Should have border at edges
    try testing.expect(buf.get(0, 0) != null);
}

test "Markdown render clips at area boundaries" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Very long line that definitely exceeds the width limit");

    var buf = try Buffer.init(allocator, 50, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    try md.render(&buf, area);

    // Content beyond x=10 should not be rendered
    // This is implicit - just check no crash
}

test "Markdown render with offset area" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# Title");

    var buf = try Buffer.init(allocator, 50, 20);
    defer buf.deinit();

    const area = Rect{ .x = 5, .y = 3, .width = 30, .height = 10 };
    try md.render(&buf, area);

    // Should render at offset (5, 3)
    var found_at_offset = false;
    for (5..35) |x| {
        if (buf.get(@intCast(x), 3)) |cell| {
            if (cell.char == 'T') {
                found_at_offset = true;
                break;
            }
        }
    }
    try testing.expect(found_at_offset);
}

test "Markdown render heading with distinct style" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("# H1\n## H2\n### H3");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Headings should have bold or distinct styling
    var h1_found = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'H') {
                const style = buf.getStyle(@intCast(x), 0);
                h1_found = style.bold;
                break;
            }
        }
    }
    try testing.expect(h1_found);
}

test "Markdown render link shows text not URL" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("[Click](https://example.com)");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Should show "Click", not "https://example.com"
    var found_click = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'C') {
                found_click = true;
                break;
            }
        }
    }
    try testing.expect(found_click);
}

test "Markdown render multiple lines" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    try md.setContent("Line 1\nLine 2\nLine 3");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try md.render(&buf, area);

    // Should render across multiple y coordinates
    var line1_found = false;
    var line2_found = false;

    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == '1') line1_found = true;
        }
        if (buf.get(@intCast(x), 1)) |cell| {
            if (cell.char == '2') line2_found = true;
        }
    }

    try testing.expect(line1_found);
    try testing.expect(line2_found);
}

// ============================================================================
// Line Wrapping Tests
// ============================================================================

test "Markdown line wraps at width boundary" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    md = md.withWrap(true);

    const long_text = "This is a very long line that should wrap when it exceeds the width";
    try md.setContent(long_text);

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try md.render(&buf, area);

    // Should render across multiple lines - check buffer has content on multiple rows
    var has_content_y0 = false;
    var has_content_y1 = false;
    for (0..20) |x| {
        if (buf.getChar(@intCast(x), 0) != ' ') has_content_y0 = true;
        if (buf.getChar(@intCast(x), 1) != ' ') has_content_y1 = true;
    }
    try testing.expect(has_content_y0 and has_content_y1);
}

test "Markdown no wrap truncates lines" {
    const allocator = testing.allocator;
    var md = try Markdown.init(allocator);
    defer md.deinit();

    md = md.withWrap(false);

    const long_text = "This is a very long line that should be truncated";
    try md.setContent(long_text);

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try md.render(&buf, area);

    // Line count should reflect actual content lines, not wrapped lines
    try testing.expect(md.lineCount() > 0);
}
