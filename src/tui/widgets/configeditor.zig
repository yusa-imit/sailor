//! Config editor widget for browsing and editing a typed JSON-like value tree.
const std = @import("std");
const assert = std.debug.assert;
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
const Block = @import("block.zig").Block;

/// Value type in config tree
pub const ValueType = enum {
    object,
    array,
    string,
    number,
    boolean,
    null_value,
};

/// Node in hierarchical config tree
pub const ConfigNode = struct {
    key: []const u8,
    value_type: ValueType,
    value: union {
        object: []const ConfigNode,
        array: []const ConfigNode,
        string: []const u8,
        number: f64,
        boolean: bool,
        null_value: void,
    },
    expanded: bool = true,
};

/// A byte that continues (does not start) a UTF-8 sequence.
fn isContinuation(byte: u8) bool {
    return byte & 0xC0 == 0x80;
}

/// Longest prefix length of `text` that is at most `max` bytes and ends on a character boundary.
fn utf8Prefix(text: []const u8, max: usize) usize {
    if (text.len <= max) return text.len;
    var n = max;
    var back: u8 = 0;
    while (n > 0 and back < 3 and isContinuation(text[n])) : (back += 1) n -= 1;
    return n;
}

/// ConfigEditor widget for hierarchical config editing (JSON/TOML structures)
pub const ConfigEditor = struct {
    /// Root config nodes
    nodes: []const ConfigNode,
    /// Selected node index (flat)
    selected: ?usize = null,
    /// Scroll offset
    offset: usize = 0,
    /// Optional block border
    block: ?Block = null,
    /// Node style
    node_style: Style = .{},
    /// Selected node style
    selected_style: Style = .{},
    /// Expanded symbol
    expanded_symbol: []const u8 = "▼ ",
    /// Collapsed symbol
    collapsed_symbol: []const u8 = "▶ ",
    /// Leaf symbol
    leaf_symbol: []const u8 = "  ",
    /// Indentation
    indent: u16 = 2,
    /// Caller-provided scratch buffer for in-place scalar-value editing
    edit_buffer: []u8 = @constCast(&[_]u8{}),
    /// Number of valid bytes currently held in edit_buffer
    edit_len: usize = 0,
    /// Whether a scalar-value edit is in progress
    is_editing: bool = false,

    /// Create config editor with nodes
    pub fn init(nodes: []const ConfigNode) ConfigEditor {
        return .{ .nodes = nodes };
    }

    /// Set selected node
    pub fn withSelected(self: ConfigEditor, index: ?usize) ConfigEditor {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set scroll offset
    pub fn withOffset(self: ConfigEditor, new_offset: usize) ConfigEditor {
        var result = self;
        result.offset = new_offset;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: ConfigEditor, new_block: Block) ConfigEditor {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set node style
    pub fn withNodeStyle(self: ConfigEditor, new_style: Style) ConfigEditor {
        var result = self;
        result.node_style = new_style;
        return result;
    }

    /// Set selected style
    pub fn withSelectedStyle(self: ConfigEditor, new_style: Style) ConfigEditor {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Render the config editor
    pub fn render(self: ConfigEditor, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        const flat_list = flatten(self.nodes);
        const flat_nodes = flat_list.slice();
        if (flat_nodes.len == 0) return;

        const window = self.visibleWindow(flat_nodes.len, inner_area.height);
        var y = inner_area.y;
        for (flat_nodes[window.start..window.end], window.start..) |flat, i| {
            const is_selected = if (self.selected) |sel| sel == i else false;
            const style = if (is_selected) self.selected_style else self.node_style;
            self.renderRow(buf, inner_area, y, flat, style);
            y +|= 1;
        }
    }

    const Window = struct { start: usize, end: usize };

    /// Choose the half-open range of flat nodes to draw: the requested offset, moved just far
    /// enough to keep a valid selection visible. Never longer than `height` rows.
    fn visibleWindow(self: ConfigEditor, len: usize, height: u16) Window {
        assert(len > 0);
        assert(height > 0);
        const max_items = @min(len, height);
        var start = @min(self.offset, len);
        var end = @min(start + max_items, len);

        // Ensure selected node is visible
        if (self.selected) |sel| {
            if (sel >= len) {
                // Invalid selection - ignore
            } else if (sel >= end) {
                start = sel - max_items + 1;
                end = sel + 1;
            } else if (sel < start) {
                start = sel;
                end = sel + max_items;
            }

            if (end > len) {
                end = len;
                start = len - max_items;
            }
        }
        assert(start <= end);
        assert(end <= len);
        assert(end - start <= max_items);
        return .{ .start = start, .end = end };
    }

    /// Draw one row: indentation, expand symbol, key, ": " and the value, clipped to `inner`.
    fn renderRow(
        self: ConfigEditor,
        buf: *Buffer,
        inner: Rect,
        y: u16,
        flat: FlatNode,
        style: Style,
    ) void {
        const right: u32 = @as(u32, inner.x) + inner.width;
        // Widened: depth * indent cannot overflow u32 (65535 * 65535 + 65535 < 2^32).
        var x: u32 = @as(u32, inner.x) + @as(u32, flat.depth) * self.indent;

        const node = flat.node;
        const is_expandable = node.value_type == .object or node.value_type == .array;
        const symbol = if (!is_expandable)
            self.leaf_symbol
        else if (node.expanded)
            self.expanded_symbol
        else
            self.collapsed_symbol;

        x = drawClipped(buf, x, y, right, symbol, style);
        x = drawClipped(buf, x, y, right, node.key, style);
        x = drawClipped(buf, x, y, right, ": ", style);
        renderValue(buf, x, y, right, node, style);
    }

    /// Draw `text` at column `x`, clipped to the cells left before `right` without splitting a
    /// character. Returns the column after the drawn text; when the text was cut, returns `right`
    /// so nothing further is drawn on the row. Unchanged when `x` is already out of room.
    fn drawClipped(buf: *Buffer, x: u32, y: u16, right: u32, text: []const u8, style: Style) u32 {
        if (x >= right or x >= buf.width) return x;
        const bytes = UnicodeWidth.truncate(text, right - x);
        const drawn = text[0..bytes];
        // x < buf.width <= maxInt(u16), so the narrowing cannot truncate.
        buf.setString(@intCast(x), y, drawn, style);
        if (bytes < text.len) return right;
        const width = UnicodeWidth.stringWidth(drawn);
        assert(width <= right - x); // truncate() never exceeds the room it was given.
        return x + @as(u32, @intCast(width));
    }

    /// Format a number as plain decimal, or in exponent form when decimal would not fit.
    fn formatNumber(scratch: []u8, value: f64) []const u8 {
        assert(scratch.len >= 32);
        if (std.fmt.bufPrint(scratch, "{d}", .{value})) |text| return text else |_| {}
        // `{e}` of an f64 is at most 24 bytes ("-1.7976931348623157e308") and the assert
        // above guarantees 32, so the "?" placeholder is never shown.
        return std.fmt.bufPrint(scratch, "{e}", .{value}) catch "?";
    }

    /// Render a value based on its type
    fn renderValue(
        buf: *Buffer,
        x: u32,
        y: u16,
        right: u32,
        node: *const ConfigNode,
        style: Style,
    ) void {
        var scratch: [64]u8 = undefined;
        switch (node.value_type) {
            .object => _ = drawClipped(buf, x, y, right, "{...}", style),
            .array => _ = drawClipped(buf, x, y, right, "[...]", style),
            .string => {
                var cx = drawClipped(buf, x, y, right, "\"", style);
                cx = drawClipped(buf, cx, y, right, node.value.string, style);
                _ = drawClipped(buf, cx, y, right, "\"", style);
            },
            .number => {
                const text = formatNumber(&scratch, node.value.number);
                _ = drawClipped(buf, x, y, right, text, style);
            },
            .boolean => {
                const text = if (node.value.boolean) "true" else "false";
                _ = drawClipped(buf, x, y, right, text, style);
            },
            .null_value => _ = drawClipped(buf, x, y, right, "null", style),
        }
    }

    /// Return the currently selected node (accounting for tree flattening), or null
    pub fn selectedNode(self: *const ConfigEditor) ?*const ConfigNode {
        const sel = self.selected orelse return null;
        const flat_list = flatten(self.nodes);
        const flat_nodes = flat_list.slice();
        if (sel >= flat_nodes.len) return null;
        return flat_nodes[sel].node;
    }

    /// Format a scalar node's value as raw editable text into scratch
    fn formatScalarText(node: *const ConfigNode, scratch: []u8) []const u8 {
        return switch (node.value_type) {
            .string => node.value.string,
            .number => formatNumber(scratch, node.value.number),
            .boolean => if (node.value.boolean) "true" else "false",
            .null_value => "",
            .object, .array => "",
        };
    }

    /// Begin editing the selected scalar node's value into edit_buffer
    pub fn startEdit(self: *ConfigEditor) void {
        if (self.edit_buffer.len == 0) return;
        const node = self.selectedNode() orelse return;
        if (node.value_type == .object or node.value_type == .array) return;

        var scratch: [64]u8 = undefined;
        const text = formatScalarText(node, &scratch);
        const copy_len = utf8Prefix(text, self.edit_buffer.len);
        @memcpy(self.edit_buffer[0..copy_len], text[0..copy_len]);
        self.edit_len = copy_len;
        self.is_editing = true;
    }

    /// Current in-progress edit text, empty when not editing
    pub fn editText(self: *const ConfigEditor) []const u8 {
        if (!self.is_editing) return "";
        return self.edit_buffer[0..self.edit_len];
    }

    /// Append a character to the in-progress edit, no-op if buffer is full
    pub fn insertChar(self: *ConfigEditor, c: u8) void {
        if (!self.is_editing) return;
        if (self.edit_len >= self.edit_buffer.len) return;
        self.edit_buffer[self.edit_len] = c;
        self.edit_len += 1;
    }

    /// Remove the last character (a whole UTF-8 sequence) of the in-progress edit, no-op if empty
    pub fn deleteChar(self: *ConfigEditor) void {
        if (!self.is_editing) return;
        if (self.edit_len == 0) return;
        var pos = self.edit_len - 1;
        var back: u8 = 0;
        while (pos > 0 and back < 3 and isContinuation(self.edit_buffer[pos])) : (back += 1) {
            pos -= 1;
        }
        self.edit_len = pos;
    }

    /// Confirm the in-progress edit and stop editing
    pub fn confirmEdit(self: *ConfigEditor) void {
        self.is_editing = false;
    }

    /// Discard the in-progress edit and stop editing
    pub fn cancelEdit(self: *ConfigEditor) void {
        self.is_editing = false;
    }

    /// Flatten tree into visible nodes with depth
    const FlatNode = struct {
        node: *const ConfigNode,
        depth: u16,
    };

    /// Most visible nodes one render or selection lookup considers; the rest are not shown.
    const flat_capacity = 256;

    const FlatList = struct {
        buffer: [flat_capacity]FlatNode,
        len: usize,

        fn init() FlatList {
            return .{ .buffer = undefined, .len = 0 };
        }

        fn append(self: *FlatList, item: FlatNode) !void {
            if (self.len >= flat_capacity) return error.TooManyNodes;
            self.buffer[self.len] = item;
            self.len += 1;
        }

        fn slice(self: *const FlatList) []const FlatNode {
            return self.buffer[0..self.len];
        }
    };

    /// Flatten the visible tree; a tree past `flat_capacity` nodes is cut at the capacity.
    fn flatten(nodes: []const ConfigNode) FlatList {
        var list = FlatList.init();
        flattenNodesStack(nodes, 0, &list) catch |err| switch (err) {
            error.TooManyNodes => {}, // Full list of the first visible nodes is the result.
        };
        assert(list.len <= flat_capacity);
        return list;
    }

    /// Depth-first walk. Recursion is bounded: every level appends a node before descending,
    /// so the depth cannot exceed `flat_capacity`.
    fn flattenNodesStack(nodes: []const ConfigNode, depth: u16, out: *FlatList) !void {
        for (nodes) |*node| {
            try out.append(.{ .node = node, .depth = depth });
            if (node.expanded) {
                switch (node.value_type) {
                    .object => try flattenNodesStack(node.value.object, depth + 1, out),
                    .array => try flattenNodesStack(node.value.array, depth + 1, out),
                    else => {},
                }
            }
        }
    }
};

// Tests

const testing = std.testing;

const bold: Style = .{ .bold = true };
const italic: Style = .{ .italic = true };

fn leaf_str(key: []const u8, v: []const u8) ConfigNode {
    return .{ .key = key, .value_type = .string, .value = .{ .string = v } };
}

fn leaf_num(key: []const u8, v: f64) ConfigNode {
    return .{ .key = key, .value_type = .number, .value = .{ .number = v } };
}

fn leaf_bool(key: []const u8, v: bool) ConfigNode {
    return .{ .key = key, .value_type = .boolean, .value = .{ .boolean = v } };
}

fn leaf_null(key: []const u8) ConfigNode {
    return .{ .key = key, .value_type = .null_value, .value = .{ .null_value = {} } };
}

fn branch_obj(key: []const u8, children: []const ConfigNode) ConfigNode {
    return .{ .key = key, .value_type = .object, .value = .{ .object = children } };
}

fn branch_arr(key: []const u8, items: []const ConfigNode) ConfigNode {
    return .{ .key = key, .value_type = .array, .value = .{ .array = items } };
}

fn full(w: u16, h: u16) Rect {
    return .{ .x = 0, .y = 0, .width = w, .height = h };
}

/// Assert row `y` holds `text` from column 0, one codepoint per cell and all in `want`, and
/// that every cell after it is still the default blank cell.
fn expectRow(buf: Buffer, y: u16, text: []const u8, want: Style) !void {
    var view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    var col: u16 = 0;
    while (it.nextCodepoint()) |cp| : (col += 1) {
        const cell = buf.getConst(col, y) orelse return error.TestUnexpectedResult;
        try testing.expectEqual(cp, cell.char);
        try testing.expectEqual(want, cell.style);
    }
    while (col < buf.width) : (col += 1) {
        try testing.expectEqual(Cell{}, buf.getConst(col, y).?);
    }
}

fn expectBlankRow(buf: Buffer, y: u16) !void {
    try expectRow(buf, y, "", .{});
}

fn expectAllBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expectEqual(Cell{}, cell);
}

test "ConfigEditor: init uses documented defaults" {
    const nodes = [_]ConfigNode{leaf_null("a")};
    const editor = ConfigEditor.init(&nodes);
    try testing.expectEqual(@as(usize, 1), editor.nodes.len);
    try testing.expectEqual(@as(?usize, null), editor.selected);
    try testing.expectEqual(@as(usize, 0), editor.offset);
    try testing.expect(editor.block == null);
    try testing.expectEqual(@as(u16, 2), editor.indent);
    try testing.expectEqualStrings("▼ ", editor.expanded_symbol);
    try testing.expectEqualStrings("▶ ", editor.collapsed_symbol);
    try testing.expectEqualStrings("  ", editor.leaf_symbol);
    try testing.expect(!editor.is_editing);
    try testing.expectEqual(@as(usize, 0), editor.edit_len);
}

test "ConfigEditor: each builder replaces only its own field" {
    const nodes = [_]ConfigNode{leaf_null("a")};
    const base = ConfigEditor.init(&nodes);

    const sel = base.withSelected(0);
    try testing.expectEqual(@as(?usize, 0), sel.selected);
    try testing.expectEqual(@as(usize, 0), sel.offset);
    try testing.expectEqual(@as(?usize, null), sel.withSelected(null).selected);

    const off = base.withOffset(5);
    try testing.expectEqual(@as(usize, 5), off.offset);
    try testing.expectEqual(@as(?usize, null), off.selected);

    const blk = base.withBlock(Block{});
    try testing.expect(blk.block != null);
    try testing.expectEqual(@as(usize, 0), blk.offset);

    const ns = base.withNodeStyle(bold);
    try testing.expect(ns.node_style.bold);
    try testing.expect(!ns.selected_style.bold);

    const ss = base.withSelectedStyle(italic);
    try testing.expect(ss.selected_style.italic);
    try testing.expect(!ss.node_style.italic);
}

test "ConfigEditor: render empty editor leaves the buffer untouched" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    ConfigEditor.init(&.{}).render(&buf, full(20, 10));

    buf.check_invariants();
    try expectAllBlank(buf);
}

test "ConfigEditor: render zero-size area draws nothing" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    const nodes = [_]ConfigNode{leaf_str("test", "value")};
    const editor = ConfigEditor.init(&nodes).withBlock(Block{});

    editor.render(&buf, full(0, 10));
    editor.render(&buf, full(10, 0));

    try expectAllBlank(buf);
}

test "ConfigEditor: string leaf renders symbol, key, separator and quoted value" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    const nodes = [_]ConfigNode{leaf_str("name", "test")};

    ConfigEditor.init(&nodes).withNodeStyle(bold).render(&buf, full(30, 3));

    try expectRow(buf, 0, "  name: \"test\"", bold);
    try expectBlankRow(buf, 1);
    try expectBlankRow(buf, 2);
}

test "ConfigEditor: every scalar type renders its own literal" {
    var buf = try Buffer.init(testing.allocator, 40, 6);
    defer buf.deinit();
    const nodes = [_]ConfigNode{
        leaf_str("s", "hello"),
        leaf_num("n", 3.14),
        leaf_bool("t", true),
        leaf_bool("f", false),
        leaf_null("z"),
        leaf_str("e", ""),
    };

    ConfigEditor.init(&nodes).render(&buf, full(40, 6));

    try expectRow(buf, 0, "  s: \"hello\"", .{});
    try expectRow(buf, 1, "  n: 3.14", .{});
    try expectRow(buf, 2, "  t: true", .{});
    try expectRow(buf, 3, "  f: false", .{});
    try expectRow(buf, 4, "  z: null", .{});
    try expectRow(buf, 5, "  e: \"\"", .{});
}

test "ConfigEditor: numbers render as plain decimals, huge ones in exponent form" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();
    const nodes = [_]ConfigNode{
        leaf_num("int", 42.0),
        leaf_num("neg", -42.5),
        leaf_num("big", 1.0e308),
        leaf_num("tiny", 5.0e-324),
        leaf_num("zero", 0.0),
    };

    ConfigEditor.init(&nodes).render(&buf, full(40, 5));

    try expectRow(buf, 0, "  int: 42", .{});
    try expectRow(buf, 1, "  neg: -42.5", .{});
    // Regression: {d} of 1e308 needs 309 bytes; it used to fall back to a bogus "0".
    try expectRow(buf, 2, "  big: 1e308", .{});
    try expectRow(buf, 3, "  tiny: 5e-324", .{});
    try expectRow(buf, 4, "  zero: 0", .{});
}

test "ConfigEditor: expanded object draws children one indent level deeper" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();
    const children = [_]ConfigNode{ leaf_str("name", "Alice"), leaf_num("age", 30.0) };
    const nodes = [_]ConfigNode{branch_obj("user", &children)};

    ConfigEditor.init(&nodes).render(&buf, full(40, 5));

    // Regression: the symbol advanced the cursor by its byte length (4), not its width (2).
    try expectRow(buf, 0, "▼ user: {...}", .{});
    try expectRow(buf, 1, "    name: \"Alice\"", .{});
    try expectRow(buf, 2, "    age: 30", .{});
    try expectBlankRow(buf, 3);
}

test "ConfigEditor: collapsed containers hide children and show the collapsed marker" {
    var buf = try Buffer.init(testing.allocator, 30, 4);
    defer buf.deinit();
    const items = [_]ConfigNode{leaf_str("0", "hidden")};
    var arr = branch_arr("items", &items);
    arr.expanded = false;
    const after = leaf_bool("after", true);
    const nodes = [_]ConfigNode{ arr, after };

    ConfigEditor.init(&nodes).render(&buf, full(30, 4));

    try expectRow(buf, 0, "▶ items: [...]", .{});
    try expectRow(buf, 1, "  after: true", .{});
    try expectBlankRow(buf, 2);
}

test "ConfigEditor: nested arrays and objects indent by depth times indent" {
    var buf = try Buffer.init(testing.allocator, 40, 5);
    defer buf.deinit();
    const l3 = [_]ConfigNode{leaf_str("deep", "v")};
    const l2 = [_]ConfigNode{branch_obj("level2", &l3)};
    const l1 = [_]ConfigNode{branch_arr("level1", &l2)};

    var editor = ConfigEditor.init(&l1);
    editor.indent = 3;
    editor.render(&buf, full(40, 5));

    try expectRow(buf, 0, "▼ level1: [...]", .{});
    try expectRow(buf, 1, "   ▼ level2: {...}", .{});
    try expectRow(buf, 2, "        deep: \"v\"", .{});
    try expectBlankRow(buf, 3);
}

test "ConfigEditor: custom symbols replace the defaults" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    const kids = [_]ConfigNode{leaf_null("k")};
    const nodes = [_]ConfigNode{ branch_obj("o", &kids), leaf_null("l") };

    var editor = ConfigEditor.init(&nodes);
    editor.expanded_symbol = "- ";
    editor.leaf_symbol = "* ";
    editor.indent = 1;
    editor.render(&buf, full(30, 3));

    try expectRow(buf, 0, "- o: {...}", .{});
    try expectRow(buf, 1, " * k: null", .{});
    try expectRow(buf, 2, "* l: null", .{});
}

test "ConfigEditor: selected row uses selected_style, others node_style" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    const nodes = [_]ConfigNode{ leaf_str("key1", "value1"), leaf_str("key2", "value2") };

    ConfigEditor.init(&nodes)
        .withNodeStyle(bold)
        .withSelectedStyle(italic)
        .withSelected(1)
        .render(&buf, full(30, 3));

    try expectRow(buf, 0, "  key1: \"value1\"", bold);
    try expectRow(buf, 1, "  key2: \"value2\"", italic);
}

test "ConfigEditor: offset skips leading rows" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    const nodes = [_]ConfigNode{ leaf_null("item0"), leaf_null("item1"), leaf_null("item2") };

    ConfigEditor.init(&nodes).withOffset(1).render(&buf, full(30, 3));

    try expectRow(buf, 0, "  item1: null", .{});
    try expectRow(buf, 1, "  item2: null", .{});
    try expectBlankRow(buf, 2);
}

test "ConfigEditor: offset past the end draws no rows" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    const nodes = [_]ConfigNode{ leaf_null("a"), leaf_null("b") };

    ConfigEditor.init(&nodes).withOffset(99).render(&buf, full(30, 3));

    try expectAllBlank(buf);
}

test "ConfigEditor: selection below the window scrolls it down just enough" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const nodes = [_]ConfigNode{
        leaf_null("a"), leaf_null("b"), leaf_null("c"), leaf_null("d"), leaf_null("e"),
    };

    ConfigEditor.init(&nodes).withSelected(4).render(&buf, full(20, 3));

    try expectRow(buf, 0, "  c: null", .{});
    try expectRow(buf, 1, "  d: null", .{});
    try expectRow(buf, 2, "  e: null", .{});
}

test "ConfigEditor: selection above the window scrolls it up to the selection" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const nodes = [_]ConfigNode{
        leaf_null("a"), leaf_null("b"), leaf_null("c"), leaf_null("d"), leaf_null("e"),
    };

    ConfigEditor.init(&nodes).withOffset(3).withSelected(1).render(&buf, full(20, 3));

    try expectRow(buf, 0, "  b: null", .{});
    try expectRow(buf, 1, "  c: null", .{});
    try expectRow(buf, 2, "  d: null", .{});
}

test "ConfigEditor: out-of-range selection is ignored and styles nothing" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const nodes = [_]ConfigNode{ leaf_null("a"), leaf_null("b") };

    ConfigEditor.init(&nodes)
        .withNodeStyle(bold)
        .withSelectedStyle(italic)
        .withSelected(99)
        .withOffset(1)
        .render(&buf, full(20, 3));

    try expectRow(buf, 0, "  b: null", bold);
    try expectBlankRow(buf, 1);
}

test "ConfigEditor: block draws borders and content inside, right border survives clipping" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    const nodes = [_]ConfigNode{ leaf_str("name", "test"), leaf_null("b"), leaf_null("c") };

    ConfigEditor.init(&nodes).withBlock(Block{}).render(&buf, full(10, 5));

    try testing.expectEqual(@as(u21, '┌'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '┐'), buf.getConst(9, 0).?.char);
    try testing.expectEqual(@as(u21, '└'), buf.getConst(0, 4).?.char);
    try testing.expectEqual(@as(u21, '┘'), buf.getConst(9, 4).?.char);
    // Inner width is 8: "  name: \"test\"" is cut to "  name: " and must not touch column 9.
    const want = "  name: ";
    for (want, 1..) |ch, col| {
        try testing.expectEqual(@as(u21, ch), buf.getConst(@intCast(col), 1).?.char);
    }
    try testing.expectEqual(@as(u21, '│'), buf.getConst(0, 1).?.char);
    try testing.expectEqual(@as(u21, '│'), buf.getConst(9, 1).?.char);
    try testing.expectEqual(@as(u21, 'c'), buf.getConst(3, 3).?.char);
    try testing.expectEqual(@as(u21, '─'), buf.getConst(5, 4).?.char);
}

test "ConfigEditor: block with no room for content draws only the block" {
    var buf = try Buffer.init(testing.allocator, 6, 2);
    defer buf.deinit();
    const nodes = [_]ConfigNode{leaf_str("name", "test")};

    ConfigEditor.init(&nodes).withBlock(Block{}).render(&buf, full(6, 2));

    try testing.expectEqual(@as(u21, '┌'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '┘'), buf.getConst(5, 1).?.char);
    try testing.expectEqual(@as(u21, '─'), buf.getConst(3, 0).?.char);
}

test "ConfigEditor: narrow area clips text at the right edge by cells" {
    var buf = try Buffer.init(testing.allocator, 30, 2);
    defer buf.deinit();
    const nodes = [_]ConfigNode{leaf_str("name", "test")};

    ConfigEditor.init(&nodes).render(&buf, full(10, 2));

    try expectRow(buf, 0, "  name: \"t", .{});
    // Nothing leaks past the area into the rest of the wider buffer.
    var col: u16 = 10;
    while (col < 30) : (col += 1) try testing.expectEqual(Cell{}, buf.getConst(col, 0).?);
}

test "ConfigEditor: area offset in the buffer is respected" {
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    const nodes = [_]ConfigNode{leaf_null("a")};

    ConfigEditor.init(&nodes).render(&buf, .{ .x = 5, .y = 2, .width = 12, .height = 2 });

    const want = "  a: null";
    for (want, 5..) |ch, col| {
        try testing.expectEqual(@as(u21, ch), buf.getConst(@intCast(col), 2).?.char);
    }
    try testing.expectEqual(Cell{}, buf.getConst(4, 2).?);
    try testing.expectEqual(Cell{}, buf.getConst(5 + want.len, 2).?);
    try expectBlankRow(buf, 0);
    try expectBlankRow(buf, 3);
}

test "ConfigEditor: wide characters advance by cells, not bytes" {
    var buf = try Buffer.init(testing.allocator, 30, 2);
    defer buf.deinit();
    const nodes = [_]ConfigNode{leaf_str("世界", "é世")};

    ConfigEditor.init(&nodes).render(&buf, full(30, 2));

    // cols: 0-1 leaf symbol, 2 世, 3 pad, 4 界, 5 pad, 6 ':', 7 ' ', 8 '"', 9 é, 10 世, 12 '"'
    try testing.expectEqual(@as(u21, '世'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(@as(u21, '界'), buf.getConst(4, 0).?.char);
    try testing.expectEqual(@as(u21, ':'), buf.getConst(6, 0).?.char);
    try testing.expectEqual(@as(u21, '"'), buf.getConst(8, 0).?.char);
    try testing.expectEqual(@as(u21, 'é'), buf.getConst(9, 0).?.char);
    try testing.expectEqual(@as(u21, '世'), buf.getConst(10, 0).?.char);
    try testing.expectEqual(@as(u21, '"'), buf.getConst(12, 0).?.char);
    try testing.expectEqual(Cell{}, buf.getConst(13, 0).?);
}

test "ConfigEditor: a wide character that does not fit is dropped whole" {
    var buf = try Buffer.init(testing.allocator, 8, 1);
    defer buf.deinit();
    const nodes = [_]ConfigNode{leaf_null("世界")};

    // Area width 5: symbol 0-1, 世 at 2-3, 界 would need cells 4-5.
    ConfigEditor.init(&nodes).render(&buf, full(5, 1));

    try testing.expectEqual(@as(u21, '世'), buf.getConst(2, 0).?.char);
    try testing.expectEqual(Cell{}, buf.getConst(4, 0).?);
    try testing.expectEqual(Cell{}, buf.getConst(5, 0).?);
}

test "ConfigEditor: very long string value is clipped to the area" {
    var buf = try Buffer.init(testing.allocator, 24, 1);
    defer buf.deinit();
    const long = "x" ** 300;
    const nodes = [_]ConfigNode{leaf_str("k", long)};

    ConfigEditor.init(&nodes).render(&buf, full(24, 1));

    // Regression: strings over 254 bytes used to be replaced by a "..." placeholder.
    try expectRow(buf, 0, "  k: \"" ++ "x" ** 18, .{});
}

test "ConfigEditor: indentation wider than the area draws nothing and cannot overflow" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const l2 = [_]ConfigNode{leaf_null("b")};
    const l1 = [_]ConfigNode{branch_obj("a", &l2)};

    var editor = ConfigEditor.init(&l1);
    editor.indent = 60000; // depth 1 * 60000 + x overflows u16 if narrowed too early
    editor.render(&buf, full(20, 3));

    try expectRow(buf, 0, "▼ a: {...}", .{});
    try expectBlankRow(buf, 1);
    try expectBlankRow(buf, 2);
}

test "ConfigEditor: area extending past maxInt(u16) does not overflow" {
    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();
    const nodes = [_]ConfigNode{ leaf_null("a"), leaf_null("b") };

    const editor = ConfigEditor.init(&nodes);
    editor.render(&buf, .{ .x = 0, .y = 65535, .width = 65535, .height = 65535 });
    try expectAllBlank(buf);
    editor.render(&buf, .{ .x = 65530, .y = 0, .width = 65535, .height = 2 });
    try expectAllBlank(buf);
}

fn manyNodes(comptime n: usize) [n]ConfigNode {
    @setEvalBranchQuota(100_000);
    var arr: [n]ConfigNode = undefined;
    for (&arr, 0..) |*node, i| {
        node.* = leaf_null(std.fmt.comptimePrint("k{d}", .{i}));
    }
    return arr;
}

test "ConfigEditor: trees beyond the flatten capacity show their first nodes" {
    var buf = try Buffer.init(testing.allocator, 20, 6);
    defer buf.deinit();
    const nodes = comptime manyNodes(300);

    // Regression: a tree over 256 visible nodes used to render nothing at all.
    ConfigEditor.init(&nodes).render(&buf, full(20, 6));
    try expectRow(buf, 0, "  k0: null", .{});
    try expectRow(buf, 5, "  k5: null", .{});

    var tail = try Buffer.init(testing.allocator, 20, 6);
    defer tail.deinit();
    ConfigEditor.init(&nodes).withOffset(253).render(&tail, full(20, 6));
    try expectRow(tail, 0, "  k253: null", .{});
    try expectRow(tail, 2, "  k255: null", .{});
    try expectBlankRow(tail, 3);
}

test "ConfigEditor: render is idempotent and does not leak" {
    const children = [_]ConfigNode{ leaf_str("child1", "value1"), leaf_num("child2", 123.0) };
    const nodes = [_]ConfigNode{branch_obj("parent", &children)};
    var once = try Buffer.init(testing.allocator, 40, 10);
    defer once.deinit();
    var many = try Buffer.init(testing.allocator, 40, 10);
    defer many.deinit();
    const editor = ConfigEditor.init(&nodes).withSelected(1);

    editor.render(&once, full(40, 10));
    for (0..100) |_| editor.render(&many, full(40, 10));

    try testing.expectEqualSlices(Cell, once.cells, many.cells);
    try expectRow(once, 2, "    child2: 123", .{});
}

/// Reference first-visible-row for the seeded model: keep `offset` while the selection is
/// inside the window; otherwise move the window the minimum distance, never past the end.
fn modelStart(len: usize, height: usize, offset: usize, sel: ?usize) usize {
    const rows = @min(len, height);
    const s = sel orelse return offset;
    if (s < offset) return @min(s, len - rows);
    if (s >= offset + rows) return s + 1 - rows;
    return offset;
}

test "ConfigEditor: seeded model - random leaf lists render exactly like a reference" {
    var prng = std.Random.DefaultPrng.init(0xC0F1_6ED1);
    const rand = prng.random();
    var nodes: [40]ConfigNode = undefined;
    var keys: [40][8]u8 = undefined;
    var vals: [40][8]u8 = undefined;
    var want: [40][64]u8 = undefined;
    var want_len: [40]usize = undefined;

    for (0..200) |_| {
        const len = rand.uintAtMost(usize, 40);
        for (0..len) |i| {
            const key = try std.fmt.bufPrint(&keys[i], "k{d}", .{i});
            const num = rand.intRangeAtMost(i16, -999, 999);
            const kind = rand.uintLessThan(u8, 4);
            var out: []const u8 = undefined;
            switch (kind) {
                0 => {
                    const v = try std.fmt.bufPrint(&vals[i], "v{d}", .{i});
                    nodes[i] = leaf_str(key, v);
                    out = try std.fmt.bufPrint(&want[i], "  {s}: \"{s}\"", .{ key, v });
                },
                1 => {
                    nodes[i] = leaf_num(key, @floatFromInt(num));
                    out = try std.fmt.bufPrint(&want[i], "  {s}: {d}", .{ key, num });
                },
                2 => {
                    const b = rand.boolean();
                    nodes[i] = leaf_bool(key, b);
                    out = try std.fmt.bufPrint(&want[i], "  {s}: {}", .{ key, b });
                },
                else => {
                    nodes[i] = leaf_null(key);
                    out = try std.fmt.bufPrint(&want[i], "  {s}: null", .{key});
                },
            }
            want_len[i] = out.len;
        }
        const width = rand.intRangeAtMost(u16, 1, 30);
        const height = rand.intRangeAtMost(u16, 1, 8);
        const offset = rand.uintAtMost(usize, len);
        const sel: ?usize = if (len > 0 and rand.boolean()) rand.uintLessThan(usize, len) else null;

        var buf = try Buffer.init(testing.allocator, width, height);
        defer buf.deinit();
        var editor = ConfigEditor.init(nodes[0..len]).withOffset(offset);
        editor.selected = sel;
        editor.render(&buf, full(width, height));
        buf.check_invariants();

        const start = if (len == 0) 0 else modelStart(len, height, offset, sel);
        for (0..height) |row| {
            const idx = start + row;
            for (0..width) |col| {
                const cell = buf.getConst(@intCast(col), @intCast(row)).?;
                const present = idx < len and col < want_len[idx];
                const expect_char: u21 = if (present) want[idx][col] else ' ';
                try testing.expectEqual(expect_char, cell.char);
            }
        }
    }
}

// Scalar-value editing tests

fn editorWith(nodes: []const ConfigNode, edit_buf: []u8) ConfigEditor {
    var editor = ConfigEditor.init(nodes).withSelected(0);
    editor.edit_buffer = edit_buf;
    return editor;
}

test "ConfigEditor: startEdit copies the raw value of each scalar type" {
    const nodes = [_]ConfigNode{
        leaf_str("s", "hello world"),
        leaf_num("n", 42.5),
        leaf_bool("t", true),
        leaf_bool("f", false),
        leaf_null("z"),
    };
    const want = [_][]const u8{ "hello world", "42.5", "true", "false", "" };
    var edit_buf = [_]u8{0} ** 256;

    for (want, 0..) |text, i| {
        var editor = editorWith(&nodes, &edit_buf).withSelected(i);
        editor.edit_buffer = &edit_buf;
        editor.startEdit();
        try testing.expect(editor.is_editing);
        try testing.expectEqualStrings(text, editor.editText());
    }
}

test "ConfigEditor: startEdit on a huge number keeps the value instead of dropping it" {
    const nodes = [_]ConfigNode{leaf_num("big", 1.0e308)};
    var edit_buf = [_]u8{0} ** 256;
    var editor = editorWith(&nodes, &edit_buf);

    editor.startEdit();

    // Regression: {d} overflowed the 64-byte scratch and the edit text came back empty.
    try testing.expectEqualStrings("1e308", editor.editText());
}

test "ConfigEditor: startEdit is a no-op for every unsupported state" {
    const kids = [_]ConfigNode{leaf_str("child", "value")};
    const nodes = [_]ConfigNode{ branch_obj("obj", &kids), branch_arr("arr", &kids) };
    var edit_buf = [_]u8{0} ** 16;

    var on_object = editorWith(&nodes, &edit_buf);
    on_object.startEdit();
    try testing.expect(!on_object.is_editing);

    var on_array = editorWith(&nodes, &edit_buf).withSelected(2);
    on_array.edit_buffer = &edit_buf;
    on_array.startEdit();
    try testing.expect(!on_array.is_editing);

    var no_selection = editorWith(&nodes, &edit_buf).withSelected(null);
    no_selection.startEdit();
    try testing.expect(!no_selection.is_editing);

    var out_of_range = editorWith(&nodes, &edit_buf).withSelected(999);
    out_of_range.startEdit();
    try testing.expect(!out_of_range.is_editing);

    var no_buffer = editorWith(&nodes, &.{}).withSelected(1);
    no_buffer.startEdit();
    try testing.expect(!no_buffer.is_editing);
}

test "ConfigEditor: startEdit follows the flattened selection into children" {
    const kids = [_]ConfigNode{leaf_str("child", "inner")};
    const nodes = [_]ConfigNode{branch_obj("obj", &kids)};
    var edit_buf = [_]u8{0} ** 16;
    var editor = editorWith(&nodes, &edit_buf).withSelected(1);
    editor.edit_buffer = &edit_buf;

    editor.startEdit();

    try testing.expectEqualStrings("inner", editor.editText());
}

test "ConfigEditor: insertChar appends and stops silently at capacity" {
    const nodes = [_]ConfigNode{leaf_str("test", "")};
    var edit_buf = [_]u8{0} ** 2;
    var editor = editorWith(&nodes, &edit_buf);

    editor.startEdit();
    editor.insertChar('A');
    editor.insertChar('B');
    editor.insertChar('C');

    try testing.expectEqualStrings("AB", editor.editText());
    try testing.expectEqual(@as(usize, 2), editor.edit_len);
}

test "ConfigEditor: insertChar and deleteChar do nothing when not editing" {
    const nodes = [_]ConfigNode{leaf_str("test", "abc")};
    var edit_buf = [_]u8{0} ** 8;
    var editor = editorWith(&nodes, &edit_buf);

    editor.insertChar('X');
    editor.deleteChar();

    try testing.expectEqual(@as(usize, 0), editor.edit_len);
    try testing.expectEqualStrings("", editor.editText());
    try testing.expect(!editor.is_editing);
}

test "ConfigEditor: deleteChar removes the last byte and stops at empty" {
    const nodes = [_]ConfigNode{leaf_str("test", "hi")};
    var edit_buf = [_]u8{0} ** 8;
    var editor = editorWith(&nodes, &edit_buf);

    editor.startEdit();
    editor.deleteChar();
    try testing.expectEqualStrings("h", editor.editText());
    editor.deleteChar();
    editor.deleteChar();
    try testing.expectEqualStrings("", editor.editText());
    try testing.expectEqual(@as(usize, 0), editor.edit_len);
    try testing.expect(editor.is_editing);
}

test "ConfigEditor: confirmEdit stops editing and keeps the buffer, cancelEdit hides it" {
    const nodes = [_]ConfigNode{leaf_str("test", "value")};
    var edit_buf = [_]u8{0} ** 16;
    var editor = editorWith(&nodes, &edit_buf);

    editor.startEdit();
    editor.insertChar('!');
    editor.confirmEdit();
    try testing.expect(!editor.is_editing);
    try testing.expectEqual(@as(usize, 6), editor.edit_len);
    try testing.expectEqualStrings("value!", edit_buf[0..editor.edit_len]);
    try testing.expectEqualStrings("", editor.editText());

    editor.startEdit();
    editor.insertChar('X');
    editor.cancelEdit();
    try testing.expect(!editor.is_editing);
    try testing.expectEqualStrings("", editor.editText());
    // The source tree is never written by editing.
    try testing.expectEqualStrings("value", nodes[0].value.string);
}

test "ConfigEditor: a second startEdit restarts from the node value" {
    const nodes = [_]ConfigNode{ leaf_str("a", "one"), leaf_str("b", "two") };
    var edit_buf = [_]u8{0} ** 16;
    var editor = editorWith(&nodes, &edit_buf);

    editor.startEdit();
    editor.insertChar('X');
    editor.selected = 1;
    editor.startEdit();

    try testing.expectEqualStrings("two", editor.editText());
}

test "ConfigEditor: startEdit truncates a value longer than the buffer" {
    const nodes = [_]ConfigNode{leaf_str("test", "hello")};
    var exact = [_]u8{0} ** 5;
    var short = [_]u8{0} ** 3;

    var a = editorWith(&nodes, &exact);
    a.startEdit();
    try testing.expectEqualStrings("hello", a.editText());
    try testing.expectEqual(@as(usize, 5), a.edit_len);

    var b = editorWith(&nodes, &short);
    b.startEdit();
    try testing.expectEqualStrings("hel", b.editText());
    try testing.expectEqual(@as(usize, 3), b.edit_len);
}

test "ConfigEditor: selectedNode indexes the flattened tree" {
    const children = [_]ConfigNode{leaf_str("child", "child_value")};
    var collapsed = branch_obj("closed", &children);
    collapsed.expanded = false;
    const nodes = [_]ConfigNode{
        branch_obj("parent", &children),
        leaf_str("sibling", "sibling_value"),
        collapsed,
        leaf_null("last"),
    };
    const editor = ConfigEditor.init(&nodes);

    try testing.expectEqualStrings("parent", editor.withSelected(0).selectedNode().?.key);
    try testing.expectEqualStrings("child", editor.withSelected(1).selectedNode().?.key);
    try testing.expectEqualStrings("sibling", editor.withSelected(2).selectedNode().?.key);
    try testing.expectEqualStrings("closed", editor.withSelected(3).selectedNode().?.key);
    // The collapsed parent hides its child, so "last" is next.
    try testing.expectEqualStrings("last", editor.withSelected(4).selectedNode().?.key);
    try testing.expect(editor.withSelected(5).selectedNode() == null);
}

test "ConfigEditor: selectedNode is null without a valid selection" {
    const nodes = [_]ConfigNode{leaf_str("test", "value")};
    const editor = ConfigEditor.init(&nodes);

    try testing.expect(editor.selectedNode() == null);
    try testing.expect(editor.withSelected(999).selectedNode() == null);
    try testing.expect(ConfigEditor.init(&.{}).withSelected(0).selectedNode() == null);
}

test "ConfigEditor: selectedNode cannot reach past the flatten capacity" {
    const nodes = comptime manyNodes(300);
    const editor = ConfigEditor.init(&nodes);

    try testing.expectEqualStrings("k255", editor.withSelected(255).selectedNode().?.key);
    try testing.expect(editor.withSelected(256).selectedNode() == null);
}

test "ConfigEditor: deleteChar removes a whole multibyte character" {
    const nodes = [_]ConfigNode{leaf_str("test", "aé世😀")};
    var edit_buf = [_]u8{0} ** 32;
    var editor = editorWith(&nodes, &edit_buf);
    editor.startEdit();

    editor.deleteChar();
    try testing.expectEqualStrings("aé世", editor.editText());
    editor.deleteChar();
    try testing.expectEqualStrings("aé", editor.editText());
    editor.deleteChar();
    try testing.expectEqualStrings("a", editor.editText());
}

test "ConfigEditor: startEdit cuts a long value on a character boundary" {
    const nodes = [_]ConfigNode{leaf_str("test", "a世界")};
    var edit_buf = [_]u8{0} ** 6;
    var editor = editorWith(&nodes, &edit_buf);

    // "a世界" is 7 bytes; 6 would split 界 after its first byte.
    editor.startEdit();

    try testing.expectEqualStrings("a世", editor.editText());
    try testing.expect(std.unicode.utf8ValidateSlice(editor.editText()));
}
