//! Markdown widget: parses markdown text into an AST and renders it.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

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

/// Longest digit run accepted as an ordered-list number (CommonMark: 9 digits fit a u32).
const number_digits_max: usize = 9;
/// Spaces per list indentation level.
const indent_spaces_per_level: usize = 2;
/// Cells a bullet occupies: the glyph and one space.
const bullet_cells: u32 = 2;

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
            .nodes = std.ArrayList(markdown_mod.Node).empty,
        };
    }

    /// Clean up allocations
    pub fn deinit(self: *Markdown) void {
        self.freeNodes();
        self.nodes.deinit(self.allocator);
        if (self.content.len > 0) {
            self.allocator.free(self.content);
        }
    }

    /// Free every node's allocations and empty the node list (capacity is kept).
    fn freeNodes(self: *Markdown) void {
        for (self.nodes.items) |node| {
            self.allocator.free(node.text);
            if (node.url) |url| self.allocator.free(url);
            if (node.language) |lang| self.allocator.free(lang);
        }
        self.nodes.clearRetainingCapacity();
        assert(self.nodes.items.len == 0);
    }

    /// Set markdown content and parse it
    pub fn setContent(self: *Markdown, content: []const u8) !void {
        self.freeNodes();

        // Free old content and store new
        if (self.content.len > 0) {
            self.allocator.free(self.content);
            self.content = "";
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

    /// Scroll down by n lines (saturates at the last node)
    pub fn scrollDown(self: *Markdown, n: usize) void {
        const max_scroll = if (self.lineCount() > 0) self.lineCount() - 1 else 0;
        const new_offset = self.scroll_offset +| n;
        self.scroll_offset = @min(new_offset, max_scroll);
        assert(self.scroll_offset <= max_scroll);
    }

    /// Scroll up by n lines
    pub fn scrollUp(self: *Markdown, n: usize) void {
        self.scroll_offset -|= n;
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

    /// Append a node that owns a copy of `text`.
    fn appendText(self: *Markdown, node_type: markdown_mod.NodeType, text: []const u8) !void {
        const copy = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(copy);

        try self.nodes.append(self.allocator, .{ .node_type = node_type, .text = copy });
    }

    /// Append a finished code block, taking ownership of `text` and `language`.
    fn appendCodeBlock(self: *Markdown, text: []u8, language: ?[]const u8) !void {
        errdefer self.allocator.free(text);
        errdefer if (language) |lang| self.allocator.free(lang);

        try self.nodes.append(self.allocator, .{
            .node_type = .code_block,
            .text = text,
            .language = language,
        });
    }

    /// Parse markdown content into AST nodes
    fn parse(self: *Markdown) !void {
        var lines = std.mem.splitScalar(u8, self.content, '\n');
        var in_code_block = false;
        var code_block_content = std.ArrayList(u8).empty;
        defer code_block_content.deinit(self.allocator);

        var code_block_lang: ?[]const u8 = null;
        errdefer if (code_block_lang) |lang| self.allocator.free(lang);

        while (lines.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, "\r");
            if (std.mem.startsWith(u8, line, "```")) {
                if (!in_code_block) {
                    in_code_block = true;
                    const lang = std.mem.trim(u8, line[3..], " \t");
                    if (lang.len > 0) code_block_lang = try self.allocator.dupe(u8, lang);
                } else {
                    in_code_block = false;
                    const text = try code_block_content.toOwnedSlice(self.allocator);
                    const lang = code_block_lang;
                    code_block_lang = null;
                    try self.appendCodeBlock(text, lang);
                }
                continue;
            }

            if (in_code_block) {
                try code_block_content.appendSlice(self.allocator, line);
                try code_block_content.append(self.allocator, '\n');
                continue;
            }

            try self.parseLine(line);
        }

        // Handle unclosed code block
        if (in_code_block) {
            const text = try code_block_content.toOwnedSlice(self.allocator);
            const lang = code_block_lang;
            code_block_lang = null;
            try self.appendCodeBlock(text, lang);
        }
    }

    /// Parse a single line
    fn parseLine(self: *Markdown, line: []const u8) !void {
        if (std.mem.trim(u8, line, " \t").len == 0) return;
        if (try self.parseHeading(line)) return;

        // List markers may be indented; 2 spaces make one level (saturating at 255).
        const spaces = std.mem.indexOfNone(u8, line, " ") orelse line.len;
        const indent_level: u8 = @intCast(@min(spaces / indent_spaces_per_level, 255));
        const rest = line[spaces..];
        if (try self.parseOrderedItem(rest, indent_level)) return;
        if (try self.parseUnorderedItem(rest, indent_level)) return;

        try self.parseInline(line);
    }

    /// `# text` through `###### text`; returns false when `line` is not a heading.
    fn parseHeading(self: *Markdown, line: []const u8) !bool {
        assert(line.len > 0);
        const hashes = std.mem.indexOfNone(u8, line, "#") orelse line.len;
        // A heading needs 1..6 hashes followed by a space.
        if (hashes == 0 or hashes > 6) return false;
        if (hashes >= line.len or line[hashes] != ' ') return false;

        var text = std.mem.trim(u8, line[hashes..], " \t");
        // Remove closing hashes
        while (text.len > 0 and text[text.len - 1] == '#') {
            text = std.mem.trimEnd(u8, text[0 .. text.len - 1], " \t");
        }
        const copy = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(copy);

        const level: u8 = @intCast(hashes);
        try self.nodes.append(self.allocator, .{
            .node_type = .heading,
            .text = copy,
            .level = level,
        });
        return true;
    }

    /// `12. text`; numbers are limited to `number_digits_max` digits.
    fn parseOrderedItem(self: *Markdown, rest: []const u8, indent_level: u8) !bool {
        const digits = std.mem.indexOfNone(u8, rest, "0123456789") orelse rest.len;
        if (digits == 0 or digits > number_digits_max) return false;
        if (digits + 1 >= rest.len) return false;
        if (rest[digits] != '.' or rest[digits + 1] != ' ') return false;

        const number = std.fmt.parseInt(u32, rest[0..digits], 10) catch return false;
        const text = std.mem.trim(u8, rest[digits + 2 ..], " \t");
        const copy = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(copy);

        try self.nodes.append(self.allocator, .{
            .node_type = .ordered_item,
            .text = copy,
            .indent_level = indent_level,
            .number = number,
        });
        return true;
    }

    /// `- text` or `* text`
    fn parseUnorderedItem(self: *Markdown, rest: []const u8, indent_level: u8) !bool {
        if (rest.len < 2) return false;
        if (rest[0] != '-' and rest[0] != '*') return false;
        if (rest[1] != ' ') return false;

        const text = std.mem.trim(u8, rest[2..], " \t");
        const copy = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(copy);

        try self.nodes.append(self.allocator, .{
            .node_type = .list_item,
            .text = copy,
            .indent_level = indent_level,
        });
        return true;
    }

    /// Parse inline formatting (bold, italic, code, links) into one node per span.
    fn parseInline(self: *Markdown, text: []const u8) !void {
        assert(text.len > 0);
        var i: usize = 0;
        var last_pos: usize = 0;

        while (i < text.len) {
            const span = matchSpan(text, i) orelse {
                i += 1;
                continue;
            };
            assert(span.next > i);
            assert(span.next <= text.len);

            if (i > last_pos) try self.appendText(.text, text[last_pos..i]);
            if (span.node_type == .link) {
                const url = text[span.url_start..span.url_end];
                try self.appendLink(text[span.start..span.end], url);
            } else {
                try self.appendText(span.node_type, text[span.start..span.end]);
            }
            i = span.next;
            last_pos = i;
        }

        if (last_pos < text.len) try self.appendText(.text, text[last_pos..]);
    }

    /// Append a link node owning copies of its text and URL.
    fn appendLink(self: *Markdown, link_text: []const u8, url: []const u8) !void {
        const text_copy = try self.allocator.dupe(u8, link_text);
        errdefer self.allocator.free(text_copy);

        const url_copy = try self.allocator.dupe(u8, url);
        errdefer self.allocator.free(url_copy);

        try self.nodes.append(self.allocator, .{
            .node_type = .link,
            .text = text_copy,
            .url = url_copy,
        });
    }

    /// Render the markdown widget. Draws one row per node (plus wrapped or code-block rows),
    /// clipped to `area` and to the buffer.
    pub fn render(self: Markdown, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var render_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            render_area = blk.inner(area);
        }

        // Clip to the buffer so coordinate arithmetic below cannot overflow u16.
        const buffer_area = Rect.fromSize(buf.width, buf.height);
        render_area = render_area.intersection(buffer_area) orelse return;
        if (render_area.width == 0 or render_area.height == 0) return;

        var row: u16 = 0;
        var node_idx: usize = self.scroll_offset;
        while (node_idx < self.nodes.items.len and row < render_area.height) : (node_idx += 1) {
            row += renderNode(buf, render_area, row, self.nodes.items[node_idx], self.wrap);
        }
        assert(row >= render_area.height or node_idx >= self.nodes.items.len);
    }
};

/// A recognized inline span: content is `text[start..end]`, parsing resumes at `next`.
const Span = struct {
    node_type: NodeType,
    start: usize,
    end: usize,
    next: usize,
    url_start: usize = 0,
    url_end: usize = 0,
};

/// Index of the first `needle` byte in `text[from..]`, or null.
fn findByte(text: []const u8, from: usize, needle: u8) ?usize {
    if (from >= text.len) return null;
    return std.mem.findScalarPos(u8, text, from, needle);
}

/// Index of the first run of `count` copies of `delimiter` at or after `from`, or null.
fn findRun(text: []const u8, from: usize, delimiter: u8, count: usize) ?usize {
    assert(count >= 1);
    assert(count <= 3);
    var j = from;
    while (j + count <= text.len) : (j += 1) {
        const run = text[j .. j + count];
        if (std.mem.indexOfNone(u8, run, &[_]u8{delimiter}) == null) return j;
    }
    return null;
}

/// True if `byte` is an ASCII letter or digit.
fn isWordByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte);
}

/// Underscore emphasis does not open or close inside a word (`snake_case_name`).
fn underscoreFlanked(text: []const u8, open: usize, close_end: usize) bool {
    assert(open < close_end);
    assert(close_end <= text.len);
    // Also reject spans that start or end in the middle of a longer underscore run.
    if (open > 0 and (isWordByte(text[open - 1]) or text[open - 1] == '_')) return false;
    if (close_end < text.len and (isWordByte(text[close_end]) or text[close_end] == '_')) {
        return false;
    }
    return true;
}

/// Match an emphasis span of `width` delimiter bytes at `text[i..]`.
fn matchEmphasis(text: []const u8, i: usize, width: usize) ?Span {
    const delimiter = text[i];
    const start = i + width;
    const end = findRun(text, start, delimiter, width) orelse return null;
    if (delimiter == '_' and !underscoreFlanked(text, i, end + width)) return null;
    const node_type: NodeType = switch (width) {
        1 => .italic,
        2 => .bold,
        else => .bold_italic,
    };
    return .{ .node_type = node_type, .start = start, .end = end, .next = end + width };
}

/// Match a `[text](url)` link at `text[i..]`.
fn matchLink(text: []const u8, i: usize) ?Span {
    assert(text[i] == '[');
    const text_end = findByte(text, i + 1, ']') orelse return null;
    if (text_end + 1 >= text.len or text[text_end + 1] != '(') return null;
    const url_end = findByte(text, text_end + 2, ')') orelse return null;
    return .{
        .node_type = .link,
        .start = i + 1,
        .end = text_end,
        .url_start = text_end + 2,
        .url_end = url_end,
        .next = url_end + 1,
    };
}

/// Match the inline span that starts at `text[i]`, if any. Pure; never allocates.
fn matchSpan(text: []const u8, i: usize) ?Span {
    assert(i < text.len);
    const byte = text[i];
    const is_delimiter = byte == '*' or byte == '_';
    const doubled = i + 1 < text.len and text[i + 1] == byte;
    const tripled = doubled and i + 2 < text.len and text[i + 2] == byte;

    if (byte == '*' and tripled) {
        if (matchEmphasis(text, i, 3)) |span| return span;
    }
    if (is_delimiter and doubled) return matchEmphasis(text, i, 2);
    if (is_delimiter) return matchEmphasis(text, i, 1);
    if (byte == '`') {
        const end = findByte(text, i + 1, '`') orelse return null;
        return .{ .node_type = .code, .start = i + 1, .end = end, .next = end + 1 };
    }
    if (byte == '[') return matchLink(text, i);
    return null;
}

/// Text style for a node type.
fn nodeStyle(node_type: NodeType) Style {
    return switch (node_type) {
        .heading => Style{ .bold = true },
        .bold => Style{ .bold = true },
        .italic => Style{ .italic = true },
        .bold_italic => Style{ .bold = true, .italic = true },
        .code, .code_block => Style{},
        .text, .list_item, .ordered_item, .link => Style{},
    };
}

/// Draw the bullet or number of a list node on `row`; returns the column where text starts.
fn renderListPrefix(buf: *Buffer, area: Rect, row: u16, node: Node, style: Style) u32 {
    assert(row < area.height);
    var x: u32 = switch (node.node_type) {
        .list_item, .ordered_item => @as(u32, node.indent_level) * @as(u32, indent_spaces_per_level),
        else => return 0,
    };
    const y = area.y + row;
    if (node.node_type == .list_item) {
        if (x < area.width) buf.set(area.x + @as(u16, @intCast(x)), y, Cell.init('•', style));
        return x + bullet_cells;
    }

    const number = node.number orelse return x;
    var num_buf: [16]u8 = undefined;
    // A u32 has at most 10 digits, so "{d}. " always fits in 16 bytes.
    const num_str = std.fmt.bufPrint(&num_buf, "{d}. ", .{number}) catch return x;
    for (num_str) |ch| {
        if (x < area.width) buf.set(area.x + @as(u16, @intCast(x)), y, Cell.init(ch, style));
        x += 1;
    }
    return x;
}

/// Next code point of `text` at byte `i`; malformed UTF-8 yields U+FFFD for one byte.
const Decoded = struct { cp: u21, len: usize };

fn decodeAt(text: []const u8, i: usize) Decoded {
    assert(i < text.len);
    const replacement: u21 = 0xFFFD;
    const invalid = Decoded{ .cp = replacement, .len = 1 };
    const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return invalid;
    if (i + len > text.len) return invalid;
    const cp = std.unicode.utf8Decode(text[i .. i + len]) catch return invalid;
    return .{ .cp = cp, .len = len };
}

/// Draw one logical line starting at column `x_start` of row `row`; returns rows used.
/// Never draws past the right edge or below `area`; wraps when `wrap` is set.
fn renderLine(buf: *Buffer, area: Rect, row: u16, x_start: u32, line: []const u8, wrap: bool, style: Style) u16 {
    assert(row < area.height);
    const rows_max: u16 = area.height - row;
    if (x_start >= area.width) return 1;

    var x = x_start;
    var rows: u16 = 1;
    var i: usize = 0;
    while (i < line.len) {
        const next = decodeAt(line, i);
        i += next.len;
        const cell_width: u32 = UnicodeWidth.charWidth(next.cp);
        if (cell_width == 0) continue;

        if (x + cell_width > area.width) {
            if (!wrap or rows >= rows_max) break;
            rows += 1;
            x = x_start;
            if (x + cell_width > area.width) continue;
        }
        const px = area.x + @as(u16, @intCast(x));
        buf.set(px, area.y + row + rows - 1, Cell.init(next.cp, style));
        x += cell_width;
    }
    assert(rows >= 1);
    assert(rows <= rows_max);
    return rows;
}

/// Draw a node starting at `row`; returns the rows it used (at least 1, at most what is left).
fn renderNode(buf: *Buffer, area: Rect, row: u16, node: Node, wrap: bool) u16 {
    assert(row < area.height);
    const style = nodeStyle(node.node_type);
    const x_start = renderListPrefix(buf, area, row, node, style);

    // A trailing newline ends the last line instead of starting an empty one.
    const body = if (std.mem.endsWith(u8, node.text, "\n")) node.text[0 .. node.text.len - 1] else node.text;
    const rows_max: u16 = area.height - row;
    var used: u16 = 0;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        if (used >= rows_max) break;
        used += renderLine(buf, area, row + used, x_start, line, wrap, style);
    }
    assert(used >= 1);
    return @min(used, rows_max);
}

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

    try testing.expectEqual(@as(usize, 4), md.nodes.items.len);
    try testing.expectEqual(NodeType.text, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("normal ", md.nodes.items[0].text);

    try testing.expectEqual(NodeType.bold, md.nodes.items[1].node_type);
    try testing.expectEqualStrings("bold", md.nodes.items[1].text);

    // The gap between two spans is kept as its own text node.
    try testing.expectEqual(NodeType.text, md.nodes.items[2].node_type);
    try testing.expectEqualStrings(" ", md.nodes.items[2].text);

    try testing.expectEqual(NodeType.code, md.nodes.items[3].node_type);
    try testing.expectEqualStrings("code", md.nodes.items[3].text);
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

/// Assert that the cells of row `y` starting at `x` hold exactly the codepoints of `text`.
fn expectRow(buf: Buffer, x: u16, y: u16, text: []const u8) !void {
    var iter = std.unicode.Utf8View.initUnchecked(text).iterator();
    var i: u16 = 0;
    while (iter.nextCodepoint()) |cp| : (i += 1) {
        try testing.expectEqual(cp, buf.getChar(x + i, y));
    }
}

/// Assert that every cell of row `y` from column `x` to the right edge is blank.
fn expectBlankFrom(buf: Buffer, x: u16, y: u16) !void {
    var col = x;
    while (col < buf.width) : (col += 1) {
        try testing.expectEqual(@as(u21, ' '), buf.getChar(col, y));
    }
}

/// Assert that every cell of the buffer is the default blank cell.
fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

/// Count the cells of the buffer that hold `char`.
fn countChar(buf: Buffer, char: u21) usize {
    var count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == char) count += 1;
    }
    return count;
}

test "Markdown render heading draws bold text and nothing else" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Test");

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 5 });

    try expectRow(buf, 0, 0, "Test");
    try testing.expect(buf.getStyle(0, 0).bold);
    try testing.expect(buf.getStyle(3, 0).bold);
    try expectBlankFrom(buf, 4, 0);
    try testing.expectEqual(@as(usize, 4), 20 * 5 - countChar(buf, ' '));
}

test "Markdown render with zero-sized area draws nothing" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Test");

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try expectBlank(buf);
}

test "Markdown render with scroll offset skips earlier nodes" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Line 1\n# Line 2\n# Line 3");
    md.scroll_offset = 1;

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 5 });

    try expectRow(buf, 0, 0, "Line 2");
    try expectRow(buf, 0, 1, "Line 3");
    try expectBlankFrom(buf, 0, 2);
    try testing.expectEqual(@as(usize, 0), countChar(buf, '1'));

    md.scroll_offset = 99;
    buf.clear();
    md.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 5 });
    try expectBlank(buf);
}

test "Markdown render with block border draws content inside it" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Test");
    md.block = (Block{}).withBorders(.all).withTitle("Markdown", .top_left);

    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 5 });

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(19, 4));
    try expectRow(buf, 2, 0, "Markdown");
    try expectRow(buf, 1, 1, "Test");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(0, 1));
}

test "Markdown render draws multibyte text one cell per code point" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("héllo ✓ 日本");

    var buf = try Buffer.init(testing.allocator, 20, 2);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 2 });

    // The whole line is one text node: 'é' and '✓' take one cell, each wide glyph takes two.
    try expectRow(buf, 0, 0, "héllo ✓ ");
    try testing.expectEqual(@as(u21, '日'), buf.getChar(8, 0));
    try testing.expectEqual(@as(u21, '本'), buf.getChar(10, 0));
    try expectBlankFrom(buf, 12, 0);
    try expectBlankFrom(buf, 0, 1);
}

test "Markdown render replaces malformed UTF-8 with U+FFFD" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("a\xFFb\xE2\x97");

    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try testing.expectEqual(@as(u21, 'a'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 0xFFFD), buf.getChar(1, 0));
    try testing.expectEqual(@as(u21, 'b'), buf.getChar(2, 0));
    try testing.expectEqual(@as(u21, 0xFFFD), buf.getChar(3, 0));
    try testing.expectEqual(@as(u21, 0xFFFD), buf.getChar(4, 0));
    try expectBlankFrom(buf, 5, 0);
}

test "Markdown render drops control characters instead of writing them to cells" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("a\x1b[31mb\tc");

    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });

    try expectRow(buf, 0, 0, "a[31mbc");
    try testing.expectEqual(@as(usize, 0), countChar(buf, 0x1b));
    try testing.expectEqual(@as(usize, 0), countChar(buf, '\t'));
}

test "Markdown render lists with bullets, numbers and indentation" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("- a\n  - b\n12. c");

    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 4 });

    try expectRow(buf, 0, 0, "• a");
    try expectBlankFrom(buf, 3, 0);
    try expectRow(buf, 2, 1, "• b");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
    try expectRow(buf, 0, 2, "12. c");
    try expectBlankFrom(buf, 5, 2);
    try expectBlankFrom(buf, 0, 3);
}

test "Markdown render code block puts each line on its own row" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("```\nab\n\ncd\n```\n# After");

    var buf = try Buffer.init(testing.allocator, 10, 6);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 6 });

    try expectRow(buf, 0, 0, "ab");
    try expectBlankFrom(buf, 2, 0);
    try expectBlankFrom(buf, 0, 1);
    try expectRow(buf, 0, 2, "cd");
    try expectRow(buf, 0, 3, "After");
    try testing.expectEqual(@as(usize, 0), countChar(buf, '\n'));
    try expectBlankFrom(buf, 0, 4);
}

test "Markdown render wraps long lines only when wrap is set" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("abcdefgh\nnext");

    var buf = try Buffer.init(testing.allocator, 5, 4);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 4 });
    try expectRow(buf, 0, 0, "abcde");
    try expectRow(buf, 0, 1, "next");
    try expectBlankFrom(buf, 0, 2);

    md.wrap = true;
    buf.clear();
    md.render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 4 });
    try expectRow(buf, 0, 0, "abcde");
    try expectRow(buf, 0, 1, "fgh");
    try expectBlankFrom(buf, 3, 1);
    try expectRow(buf, 0, 2, "next");
}

test "Markdown render wrapped list items keep their indent" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("- abcdef");
    md.wrap = true;

    var buf = try Buffer.init(testing.allocator, 6, 3);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 6, .height = 3 });

    try expectRow(buf, 0, 0, "• abcd");
    try expectRow(buf, 2, 1, "ef");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
    try expectBlankFrom(buf, 0, 2);
}

test "Markdown render stops wrapping at the bottom of the area" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("abcdefghijkl\nnever");
    md.wrap = true;

    var buf = try Buffer.init(testing.allocator, 4, 3);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 2 });

    try expectRow(buf, 0, 0, "abcd");
    try expectRow(buf, 0, 1, "efgh");
    try expectBlankFrom(buf, 0, 2);
}

test "Markdown render clips to an offset area" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Hello World");

    var buf = try Buffer.init(testing.allocator, 12, 4);
    defer buf.deinit();

    md.render(&buf, .{ .x = 3, .y = 1, .width = 5, .height = 2 });

    try expectRow(buf, 3, 1, "Hello");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(8, 1));
    try testing.expectEqual(@as(usize, 5), 12 * 4 - countChar(buf, ' '));
}

test "Markdown render ignores an area outside the buffer without overflow" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Title\n- item");
    md.wrap = true;

    var buf = try Buffer.init(testing.allocator, 10, 4);
    defer buf.deinit();

    md.render(&buf, .{ .x = 65530, .y = 65530, .width = 100, .height = 100 });
    try expectBlank(buf);
    md.render(&buf, .{ .x = 0, .y = 0, .width = 65535, .height = 65535 });
    try expectRow(buf, 0, 0, "Title");
    try expectRow(buf, 0, 1, "• item");
}

test "Markdown render survives maximal list indentation" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    const line = " " ** 600 ++ "- deep\n" ++ " " ** 600 ++ "1. deeper";
    try md.setContent(line);
    try testing.expectEqual(@as(usize, 2), md.nodes.items.len);
    try testing.expectEqual(@as(u8, 255), md.nodes.items[0].indent_level);
    try testing.expectEqual(@as(u8, 255), md.nodes.items[1].indent_level);

    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    // Indent (510 cells) is far past the right edge: both rows are consumed but stay blank.
    md.wrap = true;
    md.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 3 });
    try expectBlank(buf);
}

test "Markdown render handles text far longer than u16" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    const long = [_]u8{'x'} ** 70000;
    try md.setContent(&long);

    var buf = try Buffer.init(testing.allocator, 8, 2);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });
    try expectRow(buf, 0, 0, "xxxxxxxx");
    try expectBlankFrom(buf, 0, 1);

    md.wrap = true;
    md.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });
    try expectRow(buf, 0, 1, "xxxxxxxx");
}

test "Markdown render link shows its text and hides the url" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("[site](http://x.test)");

    var buf = try Buffer.init(testing.allocator, 20, 2);
    defer buf.deinit();

    md.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 2 });
    try expectRow(buf, 0, 0, "site");
    try expectBlankFrom(buf, 4, 0);
    try testing.expectEqual(@as(usize, 0), countChar(buf, 'h'));
}

test "Markdown unclosed delimiters keep the text before them exactly once" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    const cases = [_][]const u8{ "a **b", "a *b", "a `b", "a ***b", "a __b", "a [b](c", "a _b" };
    for (cases) |case| {
        try md.setContent(case);
        try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
        try testing.expectEqual(NodeType.text, md.nodes.items[0].node_type);
        try testing.expectEqualStrings(case, md.nodes.items[0].text);
    }
}

test "Markdown unclosed delimiter after a complete span" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("**ok** and `broken");

    try testing.expectEqual(@as(usize, 2), md.nodes.items.len);
    try testing.expectEqual(NodeType.bold, md.nodes.items[0].node_type);
    try testing.expectEqualStrings("ok", md.nodes.items[0].text);
    try testing.expectEqual(NodeType.text, md.nodes.items[1].node_type);
    try testing.expectEqualStrings(" and `broken", md.nodes.items[1].text);
}

test "Markdown strips carriage returns from CRLF content" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# Title\r\nplain\r\n- item\r\n```\r\ncode\r\n```\r\n");

    try testing.expectEqual(@as(usize, 4), md.nodes.items.len);
    try testing.expectEqualStrings("Title", md.nodes.items[0].text);
    try testing.expectEqualStrings("plain", md.nodes.items[1].text);
    try testing.expectEqualStrings("item", md.nodes.items[2].text);
    try testing.expectEqualStrings("code\n", md.nodes.items[3].text);
}

test "Markdown ordered list numbers are limited to nine digits" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("999999999. max\n1234567890. too long\n99999999999999999999. way too long");

    try testing.expectEqual(@as(usize, 3), md.nodes.items.len);
    try testing.expectEqual(NodeType.ordered_item, md.nodes.items[0].node_type);
    try testing.expectEqual(@as(u32, 999999999), md.nodes.items[0].number.?);
    try testing.expectEqual(NodeType.text, md.nodes.items[1].node_type);
    try testing.expectEqualStrings("1234567890. too long", md.nodes.items[1].text);
    try testing.expectEqual(NodeType.text, md.nodes.items[2].node_type);
}

test "Markdown list indentation saturates instead of overflowing" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent(" " ** 100 ++ "- mid\n" ++ " " ** 1000 ++ "- deep");

    try testing.expectEqual(@as(u8, 50), md.nodes.items[0].indent_level);
    try testing.expectEqual(@as(u8, 255), md.nodes.items[1].indent_level);
}

test "Markdown underscores inside words are not emphasis" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("snake_case_name and my__init__.py");
    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqualStrings("snake_case_name and my__init__.py", md.nodes.items[0].text);

    try md.setContent("a _b_ c __d__ e");
    try testing.expectEqual(@as(usize, 5), md.nodes.items.len);
    try testing.expectEqual(NodeType.italic, md.nodes.items[1].node_type);
    try testing.expectEqualStrings("b", md.nodes.items[1].text);
    try testing.expectEqual(NodeType.bold, md.nodes.items[3].node_type);
    try testing.expectEqualStrings("d", md.nodes.items[3].text);
}

test "Markdown heading needs one to six hashes and a space" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("###### six\n####### seven\n#\n# # #");

    try testing.expectEqual(@as(usize, 4), md.nodes.items.len);
    try testing.expectEqual(NodeType.heading, md.nodes.items[0].node_type);
    try testing.expectEqual(@as(u8, 6), md.nodes.items[0].level);
    try testing.expectEqual(NodeType.text, md.nodes.items[1].node_type);
    try testing.expectEqualStrings("####### seven", md.nodes.items[1].text);
    try testing.expectEqual(NodeType.text, md.nodes.items[2].node_type);
    try testing.expectEqualStrings("#", md.nodes.items[2].text);
    try testing.expectEqual(NodeType.heading, md.nodes.items[3].node_type);
    try testing.expectEqualStrings("", md.nodes.items[3].text);
}

test "Markdown scrolling saturates at the last node" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("# a\n# b\n# c");
    md.scrollDown(std.math.maxInt(usize));
    try testing.expectEqual(@as(usize, 2), md.scroll_offset);
    md.scrollDown(1);
    try testing.expectEqual(@as(usize, 2), md.scroll_offset);
    md.scrollUp(std.math.maxInt(usize));
    try testing.expectEqual(@as(usize, 0), md.scroll_offset);
    md.scrollToBottom();
    try testing.expectEqual(@as(usize, 2), md.scroll_offset);
    md.scrollUp(1);
    try testing.expectEqual(@as(usize, 1), md.scroll_offset);
}

test "Markdown setContent frees the previous code block language" {
    var md = try Markdown.init(testing.allocator);
    defer md.deinit();

    try md.setContent("```zig\nx\n```\n```c\ny\n```");
    try testing.expectEqual(@as(usize, 2), md.nodes.items.len);
    try testing.expectEqualStrings("zig", md.nodes.items[0].language.?);
    try testing.expectEqualStrings("c", md.nodes.items[1].language.?);
    try md.setContent("```unclosed lang\nz");
    try testing.expectEqual(@as(usize, 1), md.nodes.items.len);
    try testing.expectEqualStrings("unclosed lang", md.nodes.items[0].language.?);
}

test "Markdown parse survives allocation failure at every allocation" {
    const content = "# H\n- a **b** `c` [d](e)\n1. f\n```zig\ncode\n```\n```x\ntail";
    var fail_index: usize = 0;
    while (fail_index < 64) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(testing.allocator, .{
            .fail_index = fail_index,
        });
        var md = try Markdown.init(failing.allocator());
        defer md.deinit();

        md.setContent(content) catch |err| switch (err) {
            error.OutOfMemory => continue,
        };
        // The index is past the last allocation: the parse completed.
        try testing.expectEqual(@as(usize, 5), md.nodes.items.len);
        break;
    }
    try testing.expect(fail_index < 64);
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
