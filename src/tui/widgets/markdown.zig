const std = @import("std");
const Allocator = std.mem.Allocator;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Node types in the parsed markdown AST
pub const NodeType = enum {
    text,
    heading,
    bold,
    italic,
    bold_italic,
    code,
    code_block,
    list_item,
    ordered_item,
    link,
};

/// A node in the parsed markdown AST
pub const Node = struct {
    node_type: NodeType,
    text: []const u8,
    level: u8 = 0, // For headings (1-6)
    indent_level: u8 = 0, // For list items
    number: ?u32 = null, // For ordered list items
    url: ?[]const u8 = null, // For links
    language: ?[]const u8 = null, // For code blocks
};

const markdown_mod = @This();

/// Markdown widget - parses and renders markdown content
pub const Markdown = struct {
    // Re-export module-level types for convenient access
    pub const NodeType = markdown_mod.NodeType;
    pub const Node = markdown_mod.Node;

    allocator: Allocator,
    nodes: std.ArrayList(markdown_mod.Node),
    content: []const u8 = "",
    scroll_offset: usize = 0,
    block: ?Block = null,
    wrap: bool = false,

    /// Create a new markdown renderer
    pub fn init(allocator: Allocator) !Markdown {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(markdown_mod.Node){},
        };
    }

    /// Clean up allocations
    pub fn deinit(self: *Markdown) void {
        // Free all node text allocations
        for (self.nodes.items) |node| {
            self.allocator.free(node.text);
            if (node.url) |url| {
                self.allocator.free(url);
            }
            if (node.language) |lang| {
                self.allocator.free(lang);
            }
        }
        self.nodes.deinit(self.allocator);
        if (self.content.len > 0) {
            self.allocator.free(self.content);
        }
    }

    /// Set markdown content and parse it
    pub fn setContent(self: *Markdown, content: []const u8) !void {
        // Clear existing nodes
        for (self.nodes.items) |node| {
            self.allocator.free(node.text);
            if (node.url) |url| {
                self.allocator.free(url);
            }
            if (node.language) |lang| {
                self.allocator.free(lang);
            }
        }
        self.nodes.clearRetainingCapacity();

        // Free old content and store new
        if (self.content.len > 0) {
            self.allocator.free(self.content);
        }
        self.content = try self.allocator.dupe(u8, content);

        // Parse content
        try self.parse();
    }

    /// Get parsed nodes
    pub fn getNodes(self: Markdown) []const markdown_mod.Node {
        return self.nodes.items;
    }

    /// Get line count for rendering
    pub fn lineCount(self: Markdown) usize {
        return self.nodes.items.len;
    }

    /// Scroll down by n lines
    pub fn scrollDown(self: *Markdown, n: usize) void {
        const max_scroll = if (self.lineCount() > 0) self.lineCount() - 1 else 0;
        const new_offset = self.scroll_offset + n;
        self.scroll_offset = if (new_offset > max_scroll) max_scroll else new_offset;
    }

    /// Scroll up by n lines
    pub fn scrollUp(self: *Markdown, n: usize) void {
        if (self.scroll_offset >= n) {
            self.scroll_offset -= n;
        } else {
            self.scroll_offset = 0;
        }
    }

    /// Scroll to top
    pub fn scrollToTop(self: *Markdown) void {
        self.scroll_offset = 0;
    }

    /// Scroll to bottom
    pub fn scrollToBottom(self: *Markdown) void {
        const line_count = self.lineCount();
        if (line_count > 0) {
            self.scroll_offset = line_count - 1;
        }
    }

    /// Set block wrapper
    pub fn withBlock(self: Markdown, new_block: Block) Markdown {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set wrapping mode
    pub fn withWrap(self: Markdown, enable_wrap: bool) Markdown {
        var result = self;
        result.wrap = enable_wrap;
        return result;
    }

    /// Parse markdown content into AST nodes
    fn parse(self: *Markdown) !void {
        var lines = std.mem.splitScalar(u8, self.content, '\n');
        var in_code_block = false;
        var code_block_content = std.ArrayList(u8){};
        defer code_block_content.deinit(self.allocator);
        var code_block_lang: ?[]const u8 = null;

        while (lines.next()) |line| {
            // Handle code blocks
            if (std.mem.startsWith(u8, line, "```")) {
                if (!in_code_block) {
                    // Start code block
                    in_code_block = true;
                    const lang_start = 3;
                    if (line.len > lang_start) {
                        const lang = std.mem.trim(u8, line[lang_start..], " \t\r");
                        if (lang.len > 0) {
                            code_block_lang = try self.allocator.dupe(u8, lang);
                        }
                    }
                } else {
                    // End code block
                    in_code_block = false;
                    const text = try code_block_content.toOwnedSlice(self.allocator);
                    try self.nodes.append(self.allocator,markdown_mod.Node{
                        .node_type = .code_block,
                        .text = text,
                        .language = code_block_lang,
                    });
                    code_block_lang = null;
                }
                continue;
            }

            if (in_code_block) {
                try code_block_content.appendSlice(self.allocator, line);
                try code_block_content.append(self.allocator, '\n');
                continue;
            }

            // Parse line
            try self.parseLine(line);
        }

        // Handle unclosed code block
        if (in_code_block) {
            const text = try code_block_content.toOwnedSlice(self.allocator);
            try self.nodes.append(self.allocator,markdown_mod.Node{
                .node_type = .code_block,
                .text = text,
                .language = code_block_lang,
            });
        }
    }

    /// Parse a single line
    fn parseLine(self: *Markdown, line: []const u8) !void {
        if (line.len == 0) return;

        // Check for heading
        if (std.mem.startsWith(u8, line, "#")) {
            var level: u8 = 0;
            var i: usize = 0;
            while (i < line.len and i < 6 and line[i] == '#') : (i += 1) {
                level += 1;
            }
            // Must have space after #
            if (i < line.len and line[i] == ' ') {
                var text = std.mem.trim(u8, line[i..], " \t\r");
                // Remove trailing #
                while (text.len > 0 and text[text.len - 1] == '#') {
                    text = std.mem.trim(u8, text[0 .. text.len - 1], " \t\r");
                }
                const text_copy = try self.allocator.dupe(u8, text);
                try self.nodes.append(self.allocator,markdown_mod.Node{
                    .node_type = .heading,
                    .text = text_copy,
                    .level = level,
                });
                return;
            }
        }

        // Check for ordered list
        if (line.len >= 2) {
            var i: usize = 0;
            // Count leading spaces for indentation (2 spaces = 1 level)
            while (i < line.len and line[i] == ' ') : (i += 1) {}
            const indent_level: u8 = @intCast(i / 2);

            const rest = line[i..];
            if (rest.len >= 2) {
                var num: u32 = 0;
                var j: usize = 0;
                while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {
                    num = num * 10 + (rest[j] - '0');
                }
                if (j > 0 and j < rest.len and rest[j] == '.') {
                    if (j + 1 < rest.len and rest[j + 1] == ' ') {
                        const text = std.mem.trim(u8, rest[j + 2 ..], " \t\r");
                        const text_copy = try self.allocator.dupe(u8, text);
                        try self.nodes.append(self.allocator,markdown_mod.Node{
                            .node_type = .ordered_item,
                            .text = text_copy,
                            .indent_level = indent_level,
                            .number = num,
                        });
                        return;
                    }
                }
            }
        }

        // Check for unordered list
        if (line.len >= 2) {
            var i: usize = 0;
            // Count leading spaces for indentation (2 spaces = 1 level)
            while (i < line.len and line[i] == ' ') : (i += 1) {}
            const indent_level: u8 = @intCast(i / 2);

            const rest = line[i..];
            if (rest.len >= 2 and (rest[0] == '-' or rest[0] == '*')) {
                if (rest[1] == ' ') {
                    const text = std.mem.trim(u8, rest[2..], " \t\r");
                    const text_copy = try self.allocator.dupe(u8, text);
                    try self.nodes.append(self.allocator,markdown_mod.Node{
                        .node_type = .list_item,
                        .text = text_copy,
                        .indent_level = indent_level,
                    });
                    return;
                }
            }
        }

        // Parse inline formatting
        try self.parseInline(line);
    }

    /// Parse inline formatting (bold, italic, code, links)
    fn parseInline(self: *Markdown, text: []const u8) !void {
        if (text.len == 0) return;

        var i: usize = 0;
        var last_pos: usize = 0;

        while (i < text.len) {
            // Check for bold+italic ***
            if (i + 2 < text.len and text[i] == '*' and text[i + 1] == '*' and text[i + 2] == '*') {
                // Add text before
                if (i > last_pos) {
                    const before = try self.allocator.dupe(u8, text[last_pos..i]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .text, .text = before });
                }

                // Find closing ***
                const start = i + 3;
                var end: ?usize = null;
                var j = start;
                while (j + 2 < text.len) : (j += 1) {
                    if (text[j] == '*' and text[j + 1] == '*' and text[j + 2] == '*') {
                        end = j;
                        break;
                    }
                }

                if (end) |e| {
                    const content = try self.allocator.dupe(u8, text[start..e]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .bold_italic, .text = content });
                    i = e + 3;
                    last_pos = i;
                    continue;
                }
            }

            // Check for bold ** or __
            if (i + 1 < text.len and ((text[i] == '*' and text[i + 1] == '*') or (text[i] == '_' and text[i + 1] == '_'))) {
                const delimiter = text[i];

                // Add text before
                if (i > last_pos) {
                    const before = try self.allocator.dupe(u8, text[last_pos..i]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .text, .text = before });
                }

                // Find closing
                const start = i + 2;
                var end: ?usize = null;
                var j = start;
                while (j + 1 < text.len) : (j += 1) {
                    if (text[j] == delimiter and text[j + 1] == delimiter) {
                        end = j;
                        break;
                    }
                }

                if (end) |e| {
                    const content = try self.allocator.dupe(u8, text[start..e]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .bold, .text = content });
                    i = e + 2;
                    last_pos = i;
                    continue;
                } else {
                    // No closing delimiter found, treat as literal text
                    i += 1;
                    continue;
                }
            }

            // Check for italic * or _
            if (text[i] == '*' or text[i] == '_') {
                const delimiter = text[i];

                // Add text before
                if (i > last_pos) {
                    const before = try self.allocator.dupe(u8, text[last_pos..i]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .text, .text = before });
                }

                // Find closing
                const start = i + 1;
                var end: ?usize = null;
                for (start..text.len) |j| {
                    if (text[j] == delimiter) {
                        end = j;
                        break;
                    }
                }

                if (end) |e| {
                    const content = try self.allocator.dupe(u8, text[start..e]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .italic, .text = content });
                    i = e + 1;
                    last_pos = i;
                    continue;
                } else {
                    // No closing delimiter found, treat as literal text
                    i += 1;
                    continue;
                }
            }

            // Check for inline code `
            if (text[i] == '`') {
                // Add text before
                if (i > last_pos) {
                    const before = try self.allocator.dupe(u8, text[last_pos..i]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .text, .text = before });
                }

                // Find closing `
                const start = i + 1;
                var end: ?usize = null;
                for (start..text.len) |j| {
                    if (text[j] == '`') {
                        end = j;
                        break;
                    }
                }

                if (end) |e| {
                    const content = try self.allocator.dupe(u8, text[start..e]);
                    try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .code, .text = content });
                    i = e + 1;
                    last_pos = i;
                    continue;
                }
            }

            // Check for link [text](url)
            if (text[i] == '[') {
                // Find closing ]
                var text_end: ?usize = null;
                for (i + 1..text.len) |j| {
                    if (text[j] == ']') {
                        text_end = j;
                        break;
                    }
                }

                if (text_end) |te| {
                    // Check for (url)
                    if (te + 1 < text.len and text[te + 1] == '(') {
                        var url_end: ?usize = null;
                        for (te + 2..text.len) |j| {
                            if (text[j] == ')') {
                                url_end = j;
                                break;
                            }
                        }

                        if (url_end) |ue| {
                            // Add text before
                            if (i > last_pos) {
                                const before = try self.allocator.dupe(u8, text[last_pos..i]);
                                try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .text, .text = before });
                            }

                            const link_text = try self.allocator.dupe(u8, text[i + 1 .. te]);
                            const url = try self.allocator.dupe(u8, text[te + 2 .. ue]);
                            try self.nodes.append(self.allocator,markdown_mod.Node{
                                .node_type = .link,
                                .text = link_text,
                                .url = url,
                            });
                            i = ue + 1;
                            last_pos = i;
                            continue;
                        }
                    }
                }
            }

            i += 1;
        }

        // Add remaining text
        if (last_pos < text.len) {
            const remaining = try self.allocator.dupe(u8, text[last_pos..]);
            try self.nodes.append(self.allocator,markdown_mod.Node{ .node_type = .text, .text = remaining });
        }
    }

    /// Render the markdown widget
    pub fn render(self: Markdown, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Render block first if present
        var render_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            render_area = blk.inner(area);
            if (render_area.width == 0 or render_area.height == 0) return;
        }

        // Render nodes
        var y: u16 = 0;
        var node_idx: usize = self.scroll_offset;

        while (node_idx < self.nodes.items.len and y < render_area.height) : (node_idx += 1) {
            const node = self.nodes.items[node_idx];

            // Calculate style based on node type
            const node_style = switch (node.node_type) {
                .heading => Style{ .bold = true },
                .bold => Style{ .bold = true },
                .italic => Style{ .italic = true },
                .bold_italic => Style{ .bold = true, .italic = true },
                .code, .code_block => Style{},
                .text, .list_item, .ordered_item, .link => Style{},
            };

            // Calculate indent for list items
            var x_offset: u16 = 0;
            if (node.node_type == .list_item or node.node_type == .ordered_item) {
                x_offset = node.indent_level * 2;
            }

            // Render bullet or number for lists
            if (node.node_type == .list_item) {
                if (render_area.x + x_offset < render_area.x + render_area.width) {
                    buf.set(render_area.x + x_offset, render_area.y + y, .{ .char = '•', .style = node_style });
                    x_offset += 2;
                }
            } else if (node.node_type == .ordered_item) {
                if (node.number) |num| {
                    var num_buf: [16]u8 = undefined;
                    const num_str = std.fmt.bufPrint(&num_buf, "{d}. ", .{num}) catch "";
                    for (num_str, 0..) |ch, i| {
                        const x = render_area.x + x_offset + @as(u16, @intCast(i));
                        if (x < render_area.x + render_area.width) {
                            buf.set(x, render_area.y + y, .{ .char = ch, .style = node_style });
                        }
                    }
                    x_offset += @intCast(num_str.len);
                }
            }

            // Render text
            var x: u16 = x_offset;
            for (node.text) |ch| {
                if (x >= render_area.width) {
                    if (self.wrap) {
                        y += 1;
                        x = x_offset;
                        if (y >= render_area.height) break;
                    } else {
                        break;
                    }
                }

                const px = render_area.x + x;
                const py = render_area.y + y;
                if (px < render_area.x + render_area.width and py < render_area.y + render_area.height) {
                    buf.set(px, py, .{ .char = ch, .style = node_style });
                }
                x += 1;
            }

            y += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Markdown init and deinit" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try testing.expectEqual(@as(usize, 0), md.nodes.items.len);
    try testing.expectEqual(@as(usize, 0), md.scroll_offset);
    try testing.expect(!md.wrap);
}

test "Markdown parse heading levels" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Level 1\n## Level 2\n### Level 3");

    try testing.expectEqual(@as(usize, 3), md.nodes.items.len);
    try testing.expectEqual(NodeType.heading, md.nodes.items[0].node_type);
    try testing.expectEqual(@as(u8, 1), md.nodes.items[0].level);
    try testing.expectEqualStrings("Level 1", md.nodes.items[0].text);

    try testing.expectEqual(@as(u8, 2), md.nodes.items[1].level);
    try testing.expectEqualStrings("Level 2", md.nodes.items[1].text);

    try testing.expectEqual(@as(u8, 3), md.nodes.items[2].level);
    try testing.expectEqualStrings("Level 3", md.nodes.items[2].text);
}

test "Markdown parse bold text" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("**bold text**");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.bold, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("bold text", md.nodes.items[0].text);
}

test "Markdown parse italic text" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("*italic text*");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.italic, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("italic text", md.nodes.items[0].text);
}

test "Markdown parse bold italic text" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("***bold italic***");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.bold_italic, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("bold italic", md.nodes.items[0].text);
}

test "Markdown parse inline code" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("`inline code`");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.code, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("inline code", md.nodes.items[0].text);
}

test "Markdown parse code block" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("```zig\nconst x = 42;\n```");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.code_block, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("const x = 42;\n", md.nodes.items[0].text);
    try testing.expect(md.nodes.items[0].language != null);
    try testing.expectEqualStrings("zig", md.nodes.items[0].language.?);
}

test "Markdown parse unordered list" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("- Item 1\n- Item 2");

    try testing.expectEqual(@as(usize, 2), md.nodes.items.len);
    try testing.expectEqual(NodeType.list_item, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("Item 1", md.nodes.items[0].text);
    try testing.expectEqual(@as(u8, 0), md.nodes.items[0].indent_level);

    try testing.expectEqual(NodeType.list_item, md.nodes.items[1].node_type);
    try testing.expectEqualStrings("Item 2", md.nodes.items[1].text);
}

test "Markdown parse ordered list" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("1. First\n2. Second");

    try testing.expectEqual(@as(usize, 2), md.nodes.items.len);
    try testing.expectEqual(NodeType.ordered_item, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("First", md.nodes.items[0].text);
    try testing.expect(md.nodes.items[0].number != null);
    try testing.expectEqual(@as(u32, 1), md.nodes.items[0].number.?);

    try testing.expectEqual(NodeType.ordered_item, md.nodes.items[1].node_type);
    try testing.expectEqualStrings("Second", md.nodes.items[1].text);
    try testing.expectEqual(@as(u32, 2), md.nodes.items[1].number.?);
}

test "Markdown parse nested list with indentation" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("- Item 1\n  - Nested");

    try testing.expectEqual(@as(usize, 2), md.nodes.items.len);
    try testing.expectEqual(@as(u8, 0), md.nodes.items[0].indent_level);
    try testing.expectEqual(@as(u8, 1), md.nodes.items[1].indent_level);
}

test "Markdown parse link" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("[example](https://example.com)");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.link, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("example", md.nodes.items[0].text);
    try testing.expect(md.nodes.items[0].url != null);
    try testing.expectEqualStrings("https://example.com", md.nodes.items[0].url.?);
}

test "Markdown parse mixed inline formatting" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("normal **bold** `code`");

    try testing.expectEqual(@as(usize, 3), md.nodes.items.len);
    try testing.expectEqual(NodeType.text, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("normal ", md.nodes.items[0].text);

    try testing.expectEqual(NodeType.bold, md.nodes.items[1].node_type);
    try testing.expectEqualStrings("bold", md.nodes.items[1].text);

    try testing.expectEqual(NodeType.code, md.nodes.items[2].node_type);
    try testing.expectEqualStrings("code", md.nodes.items[2].text);
}

test "Markdown empty content" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("");
    try testing.expectEqual(@as(usize, 0), md.nodes.items.len);
}

test "Markdown whitespace-only content" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("   \n\n   ");
    try testing.expectEqual(@as(usize, 0), md.nodes.items.len);
}

test "Markdown malformed heading (no space after #)" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("#NoSpace");

    // Should be treated as plain text
    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.text, md.nodes.items[0].node_type);
}

test "Markdown unclosed bold marker" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("**unclosed");

    // Should be treated as plain text
    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.text, md.nodes.items[0].node_type);
}

test "Markdown unclosed code block" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("```\ncode without close");

    // Should still parse as code block
    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.code_block, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("code without close\n", md.nodes.items[0].text);
}

test "Markdown render to buffer" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Test");

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    try md.render(&buf, area);

    // Verify heading was rendered (exact rendering details depend on implementation)
    const cell = buf.get(0, 0);
    try testing.expect(cell.char != ' '); // Should have content
}

test "Markdown render with zero-sized area" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Test");

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    try md.render(&buf, area); // Should not crash
}

test "Markdown render with scroll offset" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Line 1\n# Line 2\n# Line 3");
    md.scroll_offset = 1;

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    try md.render(&buf, area); // Should skip first node
}

test "Markdown render with block border" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Test");
    md.block = Block.init().withTitle("Markdown");

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    try md.render(&buf, area);

    // Verify block was rendered
    const cell = buf.get(0, 0);
    try testing.expect(cell.char == '┌' or cell.char == '╭'); // Top-left border
}

test "Markdown setContent replaces old content" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# First");
    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);

    try md.setContent("# Second");
    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqualStrings("Second", md.nodes.items[0].text);
}

test "Markdown heading with trailing hashes" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Heading ##");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.heading, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("Heading", md.nodes.items[0].text);
}

test "Markdown code block with language" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("```python\nprint('hello')\n```");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqual(NodeType.code_block, md.nodes.items[0].node_type);
    try testing.expect(md.nodes.items[0].language != null);
    try testing.expectEqualStrings("python", md.nodes.items[0].language.?);
}

test "Markdown multiple setContent calls memory safety" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    // Multiple calls should not leak memory
    try md.setContent("# First");
    try md.setContent("# Second");
    try md.setContent("# Third");

    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqualStrings("Third", md.nodes.items[0].text);
}
