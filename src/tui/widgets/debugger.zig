const std = @import("std");
const tui = @import("../tui.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const BoxSet = @import("../symbols.zig").BoxSet;

/// Widget tree node for debugging
pub const WidgetNode = struct {
    name: []const u8,
    area: Rect,
    children: std.ArrayList(WidgetNode),
    metadata: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, area: Rect) WidgetNode {
        return .{
            .name = name,
            .area = area,
            .children = std.ArrayList(WidgetNode).init(allocator),
        };
    }

    pub fn deinit(self: *WidgetNode) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn addChild(self: *WidgetNode, child: WidgetNode) !void {
        try self.children.append(child);
    }
};

/// Display mode for the debugger
pub const DisplayMode = enum {
    tree, // Hierarchical tree view
    bounds, // Layout bounds visualization
    both, // Split view with tree and bounds
};

/// Widget debugger for inspecting widget tree and layout bounds
pub const WidgetDebugger = struct {
    root: ?WidgetNode = null,
    mode: DisplayMode = .both,
    selected_index: usize = 0,
    show_dimensions: bool = true,
    show_positions: bool = true,
    highlight_selected: bool = true,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WidgetDebugger {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WidgetDebugger) void {
        if (self.root) |*root| {
            root.deinit();
        }
    }

    /// Set the widget tree to inspect
    pub fn setTree(self: *WidgetDebugger, root: WidgetNode) void {
        if (self.root) |*old_root| {
            old_root.deinit();
        }
        self.root = root;
        self.selected_index = 0;
    }

    /// Set display mode
    pub fn setMode(self: *WidgetDebugger, mode: DisplayMode) void {
        self.mode = mode;
    }

    /// Navigate to next widget
    pub fn selectNext(self: *WidgetDebugger) void {
        if (self.root) |*root| {
            const total = countNodes(root);
            if (total > 0) {
                self.selected_index = (self.selected_index + 1) % total;
            }
        }
    }

    /// Navigate to previous widget
    pub fn selectPrev(self: *WidgetDebugger) void {
        if (self.root) |*root| {
            const total = countNodes(root);
            if (total > 0) {
                if (self.selected_index == 0) {
                    self.selected_index = total - 1;
                } else {
                    self.selected_index -= 1;
                }
            }
        }
    }

    /// Render the debugger
    pub fn render(self: *const WidgetDebugger, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        const root = self.root orelse return;

        switch (self.mode) {
            .tree => try self.renderTree(buf, area, &root),
            .bounds => try self.renderBounds(buf, area, &root),
            .both => {
                // Split view: tree on left, bounds on right
                const split_x = area.width / 2;
                const left = Rect{ .x = area.x, .y = area.y, .width = split_x, .height = area.height };
                const right = Rect{ .x = area.x + split_x, .y = area.y, .width = area.width - split_x, .height = area.height };

                try self.renderTree(buf, left, &root);
                try self.renderBounds(buf, right, &root);
            },
        }
    }

    fn renderTree(self: *const WidgetDebugger, buf: *Buffer, area: Rect, root: *const WidgetNode) !void {
        if (area.width == 0 or area.height == 0) return;

        // Draw border
        const block = Block{
            .title = "Widget Tree",
            .borders = .all,
            .border_set = BoxSet.single,
        };
        block.render(buf, area);
        const inner = block.inner(area);

        // Render tree nodes
        var y: u16 = inner.y;
        var current_index: usize = 0;
        try self.renderTreeNode(buf, inner, root, 0, &y, &current_index);
    }

    fn renderTreeNode(
        self: *const WidgetDebugger,
        buf: *Buffer,
        area: Rect,
        node: *const WidgetNode,
        depth: usize,
        y: *u16,
        current_index: *usize,
    ) !void {
        if (y.* >= area.y + area.height) return;

        const is_selected = current_index.* == self.selected_index;
        const indent = depth * 2;

        // Render indentation
        var x = area.x;
        var i: usize = 0;
        while (i < indent and x < area.x + area.width) : (i += 1) {
            buf.setString(x, y.*, " ", .{});
            x += 1;
        }

        // Render tree symbols
        if (depth > 0 and x + 2 <= area.x + area.width) {
            buf.setString(x, y.*, "├─", .{});
            x += 2;
        }

        // Render widget name
        const style: Style = if (is_selected and self.highlight_selected)
            .{ .fg = .{ .basic = .black }, .bg = .{ .basic = .white }, .bold = true }
        else
            .{ .fg = .{ .basic = .cyan }, .bold = true };

        if (x < area.x + area.width) {
            const max_width = area.x + area.width - x;
            const name_len = @min(node.name.len, max_width);
            buf.setString(x, y.*, node.name[0..name_len], style);
            x += @intCast(name_len);
        }

        // Render dimensions
        if (self.show_dimensions and x + 20 <= area.x + area.width) {
            var dim_buf: [64]u8 = undefined;
            const dim_str = std.fmt.bufPrint(&dim_buf, " [{}x{}]", .{ node.area.width, node.area.height }) catch "";
            buf.setString(x, y.*, dim_str, .{ .fg = .{ .basic = .yellow } });
            x += @intCast(dim_str.len);
        }

        // Render positions
        if (self.show_positions and x + 20 <= area.x + area.width) {
            var pos_buf: [64]u8 = undefined;
            const pos_str = std.fmt.bufPrint(&pos_buf, " @({},{})", .{ node.area.x, node.area.y }) catch "";
            buf.setString(x, y.*, pos_str, .{ .fg = .{ .basic = .green } });
        }

        y.* += 1;
        current_index.* += 1;

        // Render children
        for (node.children.items) |*child| {
            try self.renderTreeNode(buf, area, child, depth + 1, y, current_index);
        }
    }

    fn renderBounds(self: *const WidgetDebugger, buf: *Buffer, area: Rect, root: *const WidgetNode) !void {
        if (area.width == 0 or area.height == 0) return;

        // Draw border
        const block = Block{
            .title = "Layout Bounds",
            .borders = .all,
            .border_set = BoxSet.single,
        };
        block.render(buf, area);
        const inner = block.inner(area);

        // Render bounds for all nodes
        var current_index: usize = 0;
        try self.renderNodeBounds(buf, inner, root, &current_index);
    }

    fn renderNodeBounds(
        self: *const WidgetDebugger,
        buf: *Buffer,
        area: Rect,
        node: *const WidgetNode,
        current_index: *usize,
    ) !void {
        const is_selected = current_index.* == self.selected_index;

        // Map node area to display area (scale to fit)
        const scale_x = if (node.area.width > 0) @as(f32, @floatFromInt(area.width)) / @as(f32, @floatFromInt(node.area.width)) else 1.0;
        const scale_y = if (node.area.height > 0) @as(f32, @floatFromInt(area.height)) / @as(f32, @floatFromInt(node.area.height)) else 1.0;
        const scale = @min(scale_x, scale_y);

        const display_x = area.x + @as(u16, @intFromFloat(@as(f32, @floatFromInt(node.area.x)) * scale));
        const display_y = area.y + @as(u16, @intFromFloat(@as(f32, @floatFromInt(node.area.y)) * scale));
        const display_w = @max(1, @as(u16, @intFromFloat(@as(f32, @floatFromInt(node.area.width)) * scale)));
        const display_h = @max(1, @as(u16, @intFromFloat(@as(f32, @floatFromInt(node.area.height)) * scale)));

        // Clip to display area
        if (display_x >= area.x + area.width or display_y >= area.y + area.height) {
            current_index.* += 1;
            for (node.children.items) |*child| {
                try self.renderNodeBounds(buf, area, child, current_index);
            }
            return;
        }

        const clipped_w = @min(display_w, area.x + area.width - display_x);
        const clipped_h = @min(display_h, area.y + area.height - display_y);

        // Draw bounds rectangle
        const style: Style = if (is_selected and self.highlight_selected)
            .{ .fg = .{ .basic = .white }, .bg = .{ .basic = .blue }, .bold = true }
        else
            .{ .fg = .{ .basic = .cyan } };

        // Top border
        var x = display_x;
        while (x < display_x + clipped_w) : (x += 1) {
            buf.setString(x, display_y, "─", style);
        }

        // Bottom border
        if (clipped_h > 1) {
            x = display_x;
            while (x < display_x + clipped_w) : (x += 1) {
                buf.setString(x, display_y + clipped_h - 1, "─", style);
            }
        }

        // Left and right borders
        var y = display_y;
        while (y < display_y + clipped_h) : (y += 1) {
            buf.setString(display_x, y, "│", style);
            if (clipped_w > 1) {
                buf.setString(display_x + clipped_w - 1, y, "│", style);
            }
        }

        // Corners
        buf.setString(display_x, display_y, "┌", style);
        if (clipped_w > 1) {
            buf.setString(display_x + clipped_w - 1, display_y, "┐", style);
        }
        if (clipped_h > 1) {
            buf.setString(display_x, display_y + clipped_h - 1, "└", style);
            if (clipped_w > 1) {
                buf.setString(display_x + clipped_w - 1, display_y + clipped_h - 1, "┘", style);
            }
        }

        // Render widget name in center if space available
        if (clipped_w > node.name.len + 2 and clipped_h > 1) {
            const name_x = display_x + (clipped_w - @as(u16, @intCast(node.name.len))) / 2;
            const name_y = display_y + clipped_h / 2;
            buf.setString(name_x, name_y, node.name, style);
        }

        current_index.* += 1;

        // Render children
        for (node.children.items) |*child| {
            try self.renderNodeBounds(buf, area, child, current_index);
        }
    }

    fn countNodes(node: *const WidgetNode) usize {
        var count: usize = 1;
        for (node.children.items) |*child| {
            count += countNodes(child);
        }
        return count;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "WidgetDebugger: init and deinit" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    try testing.expect(debugger.root == null);
    try testing.expectEqual(DisplayMode.both, debugger.mode);
}

test "WidgetNode: create and add children" {
    const allocator = testing.allocator;

    var root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    defer root.deinit();

    const child1 = WidgetNode.init(allocator, "Child1", .{ .x = 0, .y = 0, .width = 50, .height = 25 });
    try root.addChild(child1);

    const child2 = WidgetNode.init(allocator, "Child2", .{ .x = 50, .y = 0, .width = 50, .height = 25 });
    try root.addChild(child2);

    try testing.expectEqual(@as(usize, 2), root.children.items.len);
    try testing.expectEqualStrings("Child1", root.children.items[0].name);
    try testing.expectEqualStrings("Child2", root.children.items[1].name);
}

test "WidgetDebugger: setTree" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    const root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    debugger.setTree(root);

    try testing.expect(debugger.root != null);
    try testing.expectEqualStrings("Root", debugger.root.?.name);
}

test "WidgetDebugger: setMode" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    debugger.setMode(.tree);
    try testing.expectEqual(DisplayMode.tree, debugger.mode);

    debugger.setMode(.bounds);
    try testing.expectEqual(DisplayMode.bounds, debugger.mode);

    debugger.setMode(.both);
    try testing.expectEqual(DisplayMode.both, debugger.mode);
}

test "WidgetDebugger: selectNext and selectPrev" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    var root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    const child1 = WidgetNode.init(allocator, "Child1", .{ .x = 0, .y = 0, .width = 50, .height = 25 });
    try root.addChild(child1);
    const child2 = WidgetNode.init(allocator, "Child2", .{ .x = 50, .y = 0, .width = 50, .height = 25 });
    try root.addChild(child2);

    debugger.setTree(root);
    try testing.expectEqual(@as(usize, 0), debugger.selected_index);

    debugger.selectNext();
    try testing.expectEqual(@as(usize, 1), debugger.selected_index);

    debugger.selectNext();
    try testing.expectEqual(@as(usize, 2), debugger.selected_index);

    debugger.selectNext(); // Wrap around
    try testing.expectEqual(@as(usize, 0), debugger.selected_index);

    debugger.selectPrev(); // Wrap to end
    try testing.expectEqual(@as(usize, 2), debugger.selected_index);

    debugger.selectPrev();
    try testing.expectEqual(@as(usize, 1), debugger.selected_index);
}

test "WidgetDebugger: render tree mode" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    var root = WidgetNode.init(allocator, "Dashboard", .{ .x = 0, .y = 0, .width = 80, .height = 24 });
    const header = WidgetNode.init(allocator, "Header", .{ .x = 0, .y = 0, .width = 80, .height = 3 });
    try root.addChild(header);
    const body = WidgetNode.init(allocator, "Body", .{ .x = 0, .y = 3, .width = 80, .height = 21 });
    try root.addChild(body);

    debugger.setTree(root);
    debugger.setMode(.tree);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Verify border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, '┐'), buf.get(79, 0).char);

    // Verify title
    const title_y = 0;
    const title = buf.getString(1, title_y, 11);
    defer allocator.free(title);
    try testing.expectEqualStrings("Widget Tree", title);
}

test "WidgetDebugger: render bounds mode" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    const root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    debugger.setTree(root);
    debugger.setMode(.bounds);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Verify border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).char);
    try testing.expectEqual(@as(u21, '┐'), buf.get(79, 0).char);

    // Verify title
    const title = buf.getString(1, 0, 13);
    defer allocator.free(title);
    try testing.expectEqualStrings("Layout Bounds", title);
}

test "WidgetDebugger: render both mode" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    const root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    debugger.setTree(root);
    debugger.setMode(.both);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Both views should render (tree on left, bounds on right)
    // Verify left border (tree)
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).char);

    // Verify right border (bounds) starts at mid-point
    try testing.expectEqual(@as(u21, '┌'), buf.get(40, 0).char);
}

test "WidgetDebugger: zero-size area" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    const root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    debugger.setTree(root);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    // Should not crash with zero-size area
    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 10 });
}

test "WidgetDebugger: highlight selected" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    var root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    const child = WidgetNode.init(allocator, "Child", .{ .x = 0, .y = 0, .width = 20, .height = 10 });
    try root.addChild(child);

    debugger.setTree(root);
    debugger.highlight_selected = true;
    debugger.selected_index = 0; // Root selected

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 24 });

    // First widget should be highlighted (tree mode on left side in both mode)
    const cell = buf.get(1, 1); // Inside border, first widget name position
    try testing.expect(cell.style.bold);
}

test "WidgetDebugger: show/hide dimensions and positions" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    const root = WidgetNode.init(allocator, "Root", .{ .x = 10, .y = 5, .width = 40, .height = 20 });
    debugger.setTree(root);
    debugger.setMode(.tree);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    // With dimensions and positions
    debugger.show_dimensions = true;
    debugger.show_positions = true;
    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Dimensions should be rendered (look for brackets)
    var found_dimensions = false;
    var x: u16 = 0;
    while (x < 80) : (x += 1) {
        if (buf.get(x, 1).char == '[') {
            found_dimensions = true;
            break;
        }
    }
    try testing.expect(found_dimensions);

    // Without dimensions and positions
    buf.clear();
    debugger.show_dimensions = false;
    debugger.show_positions = false;
    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "WidgetDebugger: nested children" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    var root = WidgetNode.init(allocator, "App", .{ .x = 0, .y = 0, .width = 80, .height = 24 });
    var panel = WidgetNode.init(allocator, "Panel", .{ .x = 0, .y = 0, .width = 40, .height = 24 });
    const button1 = WidgetNode.init(allocator, "Button1", .{ .x = 5, .y = 5, .width = 10, .height = 3 });
    try panel.addChild(button1);
    const button2 = WidgetNode.init(allocator, "Button2", .{ .x = 5, .y = 10, .width = 10, .height = 3 });
    try panel.addChild(button2);
    try root.addChild(panel);

    debugger.setTree(root);

    // Total nodes: App (1) + Panel (1) + Button1 (1) + Button2 (1) = 4
    const total = WidgetDebugger.countNodes(&root);
    try testing.expectEqual(@as(usize, 4), total);
}

test "WidgetDebugger: countNodes" {
    const allocator = testing.allocator;

    var root = WidgetNode.init(allocator, "Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    defer root.deinit();

    try testing.expectEqual(@as(usize, 1), WidgetDebugger.countNodes(&root));

    const child1 = WidgetNode.init(allocator, "Child1", .{ .x = 0, .y = 0, .width = 50, .height = 25 });
    try root.addChild(child1);

    try testing.expectEqual(@as(usize, 2), WidgetDebugger.countNodes(&root));

    const child2 = WidgetNode.init(allocator, "Child2", .{ .x = 50, .y = 0, .width = 50, .height = 25 });
    try root.addChild(child2);

    try testing.expectEqual(@as(usize, 3), WidgetDebugger.countNodes(&root));
}

test "WidgetDebugger: empty tree" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    // Should handle rendering with no tree set
    try debugger.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "WidgetDebugger: navigation with empty tree" {
    const allocator = testing.allocator;
    var debugger = WidgetDebugger.init(allocator);
    defer debugger.deinit();

    // Should not crash with no tree
    debugger.selectNext();
    debugger.selectPrev();
    try testing.expectEqual(@as(usize, 0), debugger.selected_index);
}
