const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
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

        // Flatten visible nodes using stack-allocated buffer
        var flat_list = FlatList.init();
        flattenNodesStack(self.nodes, 0, &flat_list) catch return;

        const flat_nodes = flat_list.slice();
        if (flat_nodes.len == 0) return;

        // Calculate visible range
        const max_items = @min(flat_nodes.len, inner_area.height);
        var start = @min(self.offset, flat_nodes.len);
        var end = @min(start + max_items, flat_nodes.len);

        // Ensure selected node is visible
        if (self.selected) |sel| {
            if (sel >= flat_nodes.len) {
                // Invalid selection - ignore
            } else if (sel >= end) {
                start = sel - max_items + 1;
                end = sel + 1;
            } else if (sel < start) {
                start = sel;
                end = sel + max_items;
            }

            if (end > flat_nodes.len) {
                end = flat_nodes.len;
                start = if (flat_nodes.len >= max_items) flat_nodes.len - max_items else 0;
            }
        }

        // Render visible nodes
        var y = inner_area.y;
        for (flat_nodes[start..end], start..) |flat, i| {
            if (y >= inner_area.y + inner_area.height) break;

            const is_selected = if (self.selected) |sel| sel == i else false;
            const style = if (is_selected) self.selected_style else self.node_style;

            var x = inner_area.x;

            // Render indentation
            const indent_width = flat.depth * self.indent;
            x += indent_width;

            // Render expand/collapse symbol
            const is_expandable = flat.node.value_type == .object or flat.node.value_type == .array;
            const node_symbol = if (is_expandable)
                if (flat.node.expanded) self.expanded_symbol else self.collapsed_symbol
            else
                self.leaf_symbol;

            if (node_symbol.len > 0 and x + node_symbol.len <= inner_area.x + inner_area.width) {
                buf.setString(x, y, node_symbol, style);
                x += @intCast(node_symbol.len);
            }

            // Render key
            if (x < inner_area.x + inner_area.width) {
                const available_width = inner_area.x + inner_area.width - x;
                const key = flat.node.key;
                const key_len = @min(key.len, available_width);
                buf.setString(x, y, key[0..key_len], style);
                x += @intCast(key_len);
            }

            // Render ": " separator
            if (x + 2 <= inner_area.x + inner_area.width) {
                buf.setString(x, y, ": ", style);
                x += 2;
            }

            // Render value
            if (x < inner_area.x + inner_area.width) {
                const available_width = inner_area.x + inner_area.width - x;
                renderValue(buf, x, y, flat.node, style, available_width);
            }

            y += 1;
        }
    }

    /// Render a value based on its type
    fn renderValue(buf: *Buffer, x: u16, y: u16, node: *const ConfigNode, style: Style, available_width: u16) void {
        if (available_width == 0) return;

        switch (node.value_type) {
            .object => {
                const text = "{...}";
                const len = @min(text.len, available_width);
                buf.setString(x, y, text[0..len], style);
            },
            .array => {
                const text = "[...]";
                const len = @min(text.len, available_width);
                buf.setString(x, y, text[0..len], style);
            },
            .string => {
                // Render string in quotes
                var buf_local: [256]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf_local, "\"{s}\"", .{node.value.string}) catch {
                    const fallback = "\"...\"";
                    const len = @min(fallback.len, available_width);
                    buf.setString(x, y, fallback[0..len], style);
                    return;
                };
                const len = @min(formatted.len, available_width);
                buf.setString(x, y, formatted[0..len], style);
            },
            .number => {
                var buf_local: [64]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf_local, "{d}", .{node.value.number}) catch {
                    const fallback = "0";
                    buf.setString(x, y, fallback, style);
                    return;
                };
                const len = @min(formatted.len, available_width);
                buf.setString(x, y, formatted[0..len], style);
            },
            .boolean => {
                const text = if (node.value.boolean) "true" else "false";
                const len = @min(text.len, available_width);
                buf.setString(x, y, text[0..len], style);
            },
            .null_value => {
                const text = "null";
                const len = @min(text.len, available_width);
                buf.setString(x, y, text[0..len], style);
            },
        }
    }

    /// Flatten tree into visible nodes with depth
    const FlatNode = struct {
        node: *const ConfigNode,
        depth: u16,
    };

    const FlatList = struct {
        buffer: [256]FlatNode,
        len: usize,

        fn init() FlatList {
            return .{ .buffer = undefined, .len = 0 };
        }

        fn append(self: *FlatList, item: FlatNode) !void {
            if (self.len >= 256) return error.TooManyNodes;
            self.buffer[self.len] = item;
            self.len += 1;
        }

        fn slice(self: *const FlatList) []const FlatNode {
            return self.buffer[0..self.len];
        }
    };

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

test "ConfigEditor: create empty editor" {
    const editor = ConfigEditor.init(&.{});
    try std.testing.expectEqual(@as(usize, 0), editor.nodes.len);
    try std.testing.expectEqual(@as(?usize, null), editor.selected);
}

test "ConfigEditor: create with single string node" {
    const nodes = [_]ConfigNode{
        .{
            .key = "name",
            .value_type = .string,
            .value = .{ .string = "test" },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(usize, 1), editor.nodes.len);
    try std.testing.expectEqual(ValueType.string, editor.nodes[0].value_type);
    try std.testing.expectEqualStrings("test", editor.nodes[0].value.string);
}

test "ConfigEditor: create with number node" {
    const nodes = [_]ConfigNode{
        .{
            .key = "count",
            .value_type = .number,
            .value = .{ .number = 42.0 },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(f64, 42.0), editor.nodes[0].value.number);
}

test "ConfigEditor: create with boolean node" {
    const nodes = [_]ConfigNode{
        .{
            .key = "enabled",
            .value_type = .boolean,
            .value = .{ .boolean = true },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expect(editor.nodes[0].value.boolean);
}

test "ConfigEditor: create with null node" {
    const nodes = [_]ConfigNode{
        .{
            .key = "nothing",
            .value_type = .null_value,
            .value = .{ .null_value = {} },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(ValueType.null_value, editor.nodes[0].value_type);
}

test "ConfigEditor: create with object node" {
    const children = [_]ConfigNode{
        .{
            .key = "name",
            .value_type = .string,
            .value = .{ .string = "Alice" },
        },
        .{
            .key = "age",
            .value_type = .number,
            .value = .{ .number = 30.0 },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "user",
            .value_type = .object,
            .value = .{ .object = &children },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(ValueType.object, editor.nodes[0].value_type);
    try std.testing.expectEqual(@as(usize, 2), editor.nodes[0].value.object.len);
}

test "ConfigEditor: create with array node" {
    const items = [_]ConfigNode{
        .{
            .key = "0",
            .value_type = .string,
            .value = .{ .string = "apple" },
        },
        .{
            .key = "1",
            .value_type = .string,
            .value = .{ .string = "banana" },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "fruits",
            .value_type = .array,
            .value = .{ .array = &items },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(ValueType.array, editor.nodes[0].value_type);
    try std.testing.expectEqual(@as(usize, 2), editor.nodes[0].value.array.len);
}

test "ConfigEditor: with selected" {
    const nodes = [_]ConfigNode{
        .{
            .key = "test",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const editor = ConfigEditor.init(&nodes).withSelected(0);
    try std.testing.expectEqual(@as(?usize, 0), editor.selected);
}

test "ConfigEditor: with offset" {
    const nodes = [_]ConfigNode{
        .{
            .key = "test",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const editor = ConfigEditor.init(&nodes).withOffset(5);
    try std.testing.expectEqual(@as(usize, 5), editor.offset);
}

test "ConfigEditor: with block" {
    const nodes = [_]ConfigNode{
        .{
            .key = "test",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const blk = (Block{});
    const editor = ConfigEditor.init(&nodes).withBlock(blk);
    try std.testing.expect(editor.block != null);
}

test "ConfigEditor: with node style" {
    const nodes = [_]ConfigNode{
        .{
            .key = "test",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const style = Style{ .bold = true };
    const editor = ConfigEditor.init(&nodes).withNodeStyle(style);
    try std.testing.expect(editor.node_style.bold);
}

test "ConfigEditor: with selected style" {
    const nodes = [_]ConfigNode{
        .{
            .key = "test",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const style = Style{ .italic = true };
    const editor = ConfigEditor.init(&nodes).withSelectedStyle(style);
    try std.testing.expect(editor.selected_style.italic);
}

test "ConfigEditor: expanded object shows children" {
    const children = [_]ConfigNode{
        .{
            .key = "nested",
            .value_type = .string,
            .value = .{ .string = "data" },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "parent",
            .value_type = .object,
            .value = .{ .object = &children },
            .expanded = true,
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expect(editor.nodes[0].expanded);
}

test "ConfigEditor: collapsed object hides children" {
    const children = [_]ConfigNode{
        .{
            .key = "hidden",
            .value_type = .string,
            .value = .{ .string = "data" },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "parent",
            .value_type = .object,
            .value = .{ .object = &children },
            .expanded = false,
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expect(!editor.nodes[0].expanded);
}

test "ConfigEditor: deeply nested structure" {
    const level3 = [_]ConfigNode{
        .{
            .key = "deep",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const level2 = [_]ConfigNode{
        .{
            .key = "level2",
            .value_type = .object,
            .value = .{ .object = &level3 },
        },
    };
    const level1 = [_]ConfigNode{
        .{
            .key = "level1",
            .value_type = .object,
            .value = .{ .object = &level2 },
        },
    };

    const editor = ConfigEditor.init(&level1);
    try std.testing.expectEqual(@as(usize, 1), editor.nodes.len);
    try std.testing.expectEqual(@as(usize, 1), editor.nodes[0].value.object.len);
}

test "ConfigEditor: render empty editor" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const editor = ConfigEditor.init(&.{});
    editor.render(&buf, Rect.init(0, 0, 20, 10));

    // Should not crash
}

test "ConfigEditor: render single string value" {
    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();

    const nodes = [_]ConfigNode{
        .{
            .key = "name",
            .value_type = .string,
            .value = .{ .string = "test" },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    editor.render(&buf, Rect.init(0, 0, 30, 5));

    // Should not crash
}

test "ConfigEditor: render with selection" {
    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();

    const nodes = [_]ConfigNode{
        .{
            .key = "key1",
            .value_type = .string,
            .value = .{ .string = "value1" },
        },
        .{
            .key = "key2",
            .value_type = .string,
            .value = .{ .string = "value2" },
        },
    };
    const editor = ConfigEditor.init(&nodes).withSelected(1);
    editor.render(&buf, Rect.init(0, 0, 30, 5));

    // Should not crash
}

test "ConfigEditor: render nested object" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const children = [_]ConfigNode{
        .{
            .key = "name",
            .value_type = .string,
            .value = .{ .string = "Alice" },
        },
        .{
            .key = "age",
            .value_type = .number,
            .value = .{ .number = 30.0 },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "user",
            .value_type = .object,
            .value = .{ .object = &children },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    editor.render(&buf, Rect.init(0, 0, 40, 10));

    // Should not crash
}

test "ConfigEditor: render with block" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const nodes = [_]ConfigNode{
        .{
            .key = "test",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const blk = (Block{});
    const editor = ConfigEditor.init(&nodes).withBlock(blk);
    editor.render(&buf, Rect.init(0, 0, 30, 10));

    // Should not crash
}

test "ConfigEditor: render with offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 3);
    defer buf.deinit();

    const nodes = [_]ConfigNode{
        .{
            .key = "item0",
            .value_type = .string,
            .value = .{ .string = "value0" },
        },
        .{
            .key = "item1",
            .value_type = .string,
            .value = .{ .string = "value1" },
        },
        .{
            .key = "item2",
            .value_type = .string,
            .value = .{ .string = "value2" },
        },
    };
    const editor = ConfigEditor.init(&nodes).withOffset(1);
    editor.render(&buf, Rect.init(0, 0, 30, 3));

    // Should skip first item
}

test "ConfigEditor: render zero size area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const nodes = [_]ConfigNode{
        .{
            .key = "test",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const editor = ConfigEditor.init(&nodes);

    // Should not crash
    editor.render(&buf, Rect.init(0, 0, 0, 10));
    editor.render(&buf, Rect.init(0, 0, 10, 0));
}

test "ConfigEditor: render all value types" {
    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    const nodes = [_]ConfigNode{
        .{
            .key = "string_val",
            .value_type = .string,
            .value = .{ .string = "hello" },
        },
        .{
            .key = "number_val",
            .value_type = .number,
            .value = .{ .number = 3.14 },
        },
        .{
            .key = "bool_val",
            .value_type = .boolean,
            .value = .{ .boolean = true },
        },
        .{
            .key = "null_val",
            .value_type = .null_value,
            .value = .{ .null_value = {} },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    editor.render(&buf, Rect.init(0, 0, 50, 20));

    // Should render all types without crashing
}

test "ConfigEditor: render array with mixed types" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const items = [_]ConfigNode{
        .{
            .key = "0",
            .value_type = .string,
            .value = .{ .string = "text" },
        },
        .{
            .key = "1",
            .value_type = .number,
            .value = .{ .number = 42.0 },
        },
        .{
            .key = "2",
            .value_type = .boolean,
            .value = .{ .boolean = false },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "mixed_array",
            .value_type = .array,
            .value = .{ .array = &items },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    editor.render(&buf, Rect.init(0, 0, 40, 10));

    // Should render mixed array without crashing
}

test "ConfigEditor: large config structure" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const database_config = [_]ConfigNode{
        .{
            .key = "host",
            .value_type = .string,
            .value = .{ .string = "localhost" },
        },
        .{
            .key = "port",
            .value_type = .number,
            .value = .{ .number = 5432.0 },
        },
    };

    const server_config = [_]ConfigNode{
        .{
            .key = "port",
            .value_type = .number,
            .value = .{ .number = 8080.0 },
        },
        .{
            .key = "debug",
            .value_type = .boolean,
            .value = .{ .boolean = true },
        },
    };

    const nodes = [_]ConfigNode{
        .{
            .key = "database",
            .value_type = .object,
            .value = .{ .object = &database_config },
        },
        .{
            .key = "server",
            .value_type = .object,
            .value = .{ .object = &server_config },
        },
    };

    const editor = ConfigEditor.init(&nodes);
    editor.render(&buf, Rect.init(0, 0, 80, 24));

    // Should render complex structure
}

test "ConfigEditor: collapsed array node" {
    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();

    const items = [_]ConfigNode{
        .{
            .key = "0",
            .value_type = .string,
            .value = .{ .string = "hidden" },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "items",
            .value_type = .array,
            .value = .{ .array = &items },
            .expanded = false,
        },
    };
    const editor = ConfigEditor.init(&nodes);
    editor.render(&buf, Rect.init(0, 0, 30, 5));

    // Children should not be visible
    try std.testing.expect(!editor.nodes[0].expanded);
}

// Memory safety tests

test "ConfigEditor: render does not leak memory" {
    const children = [_]ConfigNode{
        .{
            .key = "child1",
            .value_type = .string,
            .value = .{ .string = "value1" },
        },
        .{
            .key = "child2",
            .value_type = .number,
            .value = .{ .number = 123.0 },
        },
    };
    const nodes = [_]ConfigNode{
        .{
            .key = "parent",
            .value_type = .object,
            .value = .{ .object = &children },
        },
    };

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const editor = ConfigEditor.init(&nodes);

    // Render multiple times - should not leak
    for (0..100) |_| {
        editor.render(&buf, Rect.init(0, 0, 40, 10));
    }
}

test "ConfigEditor: render large tree does not leak" {
    const l3 = [_]ConfigNode{
        .{
            .key = "l3_1",
            .value_type = .string,
            .value = .{ .string = "deep" },
        },
        .{
            .key = "l3_2",
            .value_type = .number,
            .value = .{ .number = 999.0 },
        },
    };
    const l2 = [_]ConfigNode{
        .{
            .key = "l2_1",
            .value_type = .object,
            .value = .{ .object = &l3 },
        },
        .{
            .key = "l2_2",
            .value_type = .object,
            .value = .{ .object = &l3 },
        },
    };
    const l1 = [_]ConfigNode{
        .{
            .key = "l1_1",
            .value_type = .object,
            .value = .{ .object = &l2 },
        },
        .{
            .key = "l1_2",
            .value_type = .object,
            .value = .{ .object = &l2 },
        },
    };

    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    const editor = ConfigEditor.init(&l1);

    // Render multiple times
    for (0..50) |_| {
        editor.render(&buf, Rect.init(0, 0, 50, 20));
    }
}

// Edge case tests

test "ConfigEditor: empty string value" {
    const nodes = [_]ConfigNode{
        .{
            .key = "empty",
            .value_type = .string,
            .value = .{ .string = "" },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqualStrings("", editor.nodes[0].value.string);
}

test "ConfigEditor: empty object" {
    const nodes = [_]ConfigNode{
        .{
            .key = "empty_obj",
            .value_type = .object,
            .value = .{ .object = &.{} },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(usize, 0), editor.nodes[0].value.object.len);
}

test "ConfigEditor: empty array" {
    const nodes = [_]ConfigNode{
        .{
            .key = "empty_arr",
            .value_type = .array,
            .value = .{ .array = &.{} },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(usize, 0), editor.nodes[0].value.array.len);
}

test "ConfigEditor: negative number" {
    const nodes = [_]ConfigNode{
        .{
            .key = "negative",
            .value_type = .number,
            .value = .{ .number = -42.5 },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(f64, -42.5), editor.nodes[0].value.number);
}

test "ConfigEditor: very large number" {
    const nodes = [_]ConfigNode{
        .{
            .key = "large",
            .value_type = .number,
            .value = .{ .number = 1.0e308 },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(f64, 1.0e308), editor.nodes[0].value.number);
}

test "ConfigEditor: unicode in string value" {
    const nodes = [_]ConfigNode{
        .{
            .key = "unicode",
            .value_type = .string,
            .value = .{ .string = "Hello 世界 🌍" },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqualStrings("Hello 世界 🌍", editor.nodes[0].value.string);
}

test "ConfigEditor: multiple root nodes" {
    const nodes = [_]ConfigNode{
        .{
            .key = "root1",
            .value_type = .string,
            .value = .{ .string = "value1" },
        },
        .{
            .key = "root2",
            .value_type = .string,
            .value = .{ .string = "value2" },
        },
        .{
            .key = "root3",
            .value_type = .object,
            .value = .{ .object = &.{} },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(usize, 3), editor.nodes.len);
}

test "ConfigEditor: special characters in keys" {
    const nodes = [_]ConfigNode{
        .{
            .key = "key-with-dashes",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
        .{
            .key = "key_with_underscores",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
        .{
            .key = "key.with.dots",
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqual(@as(usize, 3), editor.nodes.len);
}

test "ConfigEditor: very long key name" {
    const long_key = "this_is_a_very_long_key_name_that_might_cause_rendering_issues_if_not_handled_properly";
    const nodes = [_]ConfigNode{
        .{
            .key = long_key,
            .value_type = .string,
            .value = .{ .string = "value" },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqualStrings(long_key, editor.nodes[0].key);
}

test "ConfigEditor: very long string value" {
    const long_value = "this is a very long string value that might span multiple lines in the terminal and needs to be handled gracefully by the rendering logic";
    const nodes = [_]ConfigNode{
        .{
            .key = "long_value",
            .value_type = .string,
            .value = .{ .string = long_value },
        },
    };
    const editor = ConfigEditor.init(&nodes);
    try std.testing.expectEqualStrings(long_value, editor.nodes[0].value.string);
}
