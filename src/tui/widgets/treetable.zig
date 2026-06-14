//! TreeTable Widget — hierarchical tree with multiple table columns.
//!
//! TreeTable combines tree navigation (expand/collapse) with table columns.
//! Each node has cells (column data) and optional children. Expanding/collapsing
//! controls visibility of children in rendering and selection navigation.
//!
//! ## Features
//! - Tree navigation with expand/collapse
//! - Multiple columns with automatic width calculation
//! - Tree symbols (expanded, collapsed, leaf)
//! - Depth-based indentation
//! - Row selection and scrolling
//! - Optional Block wrapper for borders
//!
//! ## Usage
//! ```zig
//! const tt = TreeTable{
//!     .columns = &columns,
//!     .nodes = &nodes,
//! };
//! tt.render(buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const table_mod = @import("table.zig");
const Alignment = table_mod.Alignment;
const ColumnWidth = table_mod.ColumnWidth;
const Column = table_mod.Column;

/// A node in the tree with cells and optional children
pub const TreeTableNode = struct {
    cells: []const []const u8,
    children: []const TreeTableNode = &.{},
    expanded: bool = true,
};

/// TreeTable widget — hierarchical data display with columns
pub const TreeTable = struct {
    columns: []const Column,
    nodes: []const TreeTableNode,
    selected: ?usize = null,
    offset: usize = 0,
    block: ?Block = null,
    header_style: Style = .{},
    row_style: Style = .{},
    selected_style: Style = .{},
    column_spacing: u16 = 1,
    expanded_symbol: []const u8 = "▼ ",
    collapsed_symbol: []const u8 = "▶ ",
    leaf_symbol: []const u8 = "  ",
    indent: u16 = 2,

    /// Create a TreeTable with columns and nodes
    pub fn init(columns: []const Column, nodes: []const TreeTableNode) TreeTable {
        return .{ .columns = columns, .nodes = nodes };
    }

    /// Set the selected row index (flat enumeration order)
    pub fn withSelected(self: TreeTable, index: ?usize) TreeTable {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set scroll offset
    pub fn withOffset(self: TreeTable, new_offset: usize) TreeTable {
        var result = self;
        result.offset = new_offset;
        return result;
    }

    /// Set the block (border) for this table
    pub fn withBlock(self: TreeTable, new_block: Block) TreeTable {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set header style
    pub fn withHeaderStyle(self: TreeTable, new_style: Style) TreeTable {
        var result = self;
        result.header_style = new_style;
        return result;
    }

    /// Set row style
    pub fn withRowStyle(self: TreeTable, new_style: Style) TreeTable {
        var result = self;
        result.row_style = new_style;
        return result;
    }

    /// Set selected row style
    pub fn withSelectedStyle(self: TreeTable, new_style: Style) TreeTable {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set column spacing
    pub fn withColumnSpacing(self: TreeTable, spacing: u16) TreeTable {
        var result = self;
        result.column_spacing = spacing;
        return result;
    }

    /// Set expanded tree symbol
    pub fn withExpandedSymbol(self: TreeTable, symbol: []const u8) TreeTable {
        var result = self;
        result.expanded_symbol = symbol;
        return result;
    }

    /// Set collapsed tree symbol
    pub fn withCollapsedSymbol(self: TreeTable, symbol: []const u8) TreeTable {
        var result = self;
        result.collapsed_symbol = symbol;
        return result;
    }

    /// Set leaf tree symbol
    pub fn withLeafSymbol(self: TreeTable, symbol: []const u8) TreeTable {
        var result = self;
        result.leaf_symbol = symbol;
        return result;
    }

    /// Set indentation per depth level
    pub fn withIndent(self: TreeTable, indent_width: u16) TreeTable {
        var result = self;
        result.indent = indent_width;
        return result;
    }

    /// Count visible rows (respecting expanded state)
    pub fn visibleCount(self: TreeTable) usize {
        return countVisible(self.nodes);
    }

    /// Helper: count visible nodes recursively (DFS pre-order)
    fn countVisible(nodes: []const TreeTableNode) usize {
        var count: usize = 0;
        for (nodes) |node| {
            count += 1; // Count this node
            if (node.expanded and node.children.len > 0) {
                count += countVisible(node.children);
            }
        }
        return count;
    }

    /// Move selection down to next visible row
    pub fn selectNext(self: *TreeTable) void {
        const count = self.visibleCount();
        if (count == 0) return;

        if (self.selected) |sel| {
            if (sel + 1 < count) {
                self.selected = sel + 1;
            }
            // else: stay at last row (clamped)
        } else {
            self.selected = 0;
        }
    }

    /// Move selection up to previous visible row
    pub fn selectPrev(self: *TreeTable) void {
        if (self.selected) |sel| {
            if (sel > 0) {
                self.selected = sel - 1;
            }
            // else: stay at 0
        }
        // if null: stay null
    }

    /// Helper: flat node with depth info
    const FlatNode = struct {
        node: *const TreeTableNode,
        depth: usize,
    };

    /// Helper: collect visible nodes into flat list (DFS pre-order)
    fn collectVisible(nodes: []const TreeTableNode, depth: usize, result: []FlatNode, count: *usize) void {
        for (nodes) |*node| {
            if (count.* < result.len) {
                result[count.*] = .{ .node = node, .depth = depth };
                count.* += 1;
            }
            if (node.expanded and node.children.len > 0) {
                collectVisible(node.children, depth + 1, result, count);
            }
        }
    }

    /// Calculate column widths based on available space
    fn calculateColumnWidths(self: TreeTable, available_width: u16, widths_buf: []u16) void {
        if (widths_buf.len < self.columns.len) return;

        const spacing_total = if (self.columns.len > 0) (self.columns.len - 1) * self.column_spacing else 0;
        var remaining_width = available_width -| @as(u16, @intCast(spacing_total));

        // First pass: assign fixed and percentage widths
        var flex_columns: usize = 0;
        for (self.columns, 0..) |col, i| {
            switch (col.width) {
                .fixed => |w| {
                    widths_buf[i] = @min(w, remaining_width);
                    remaining_width -|= widths_buf[i];
                },
                .percentage => |pct| {
                    const w = (available_width * @as(u16, pct)) / 100;
                    widths_buf[i] = @min(w, remaining_width);
                    remaining_width -|= widths_buf[i];
                },
                .min => |min_w| {
                    widths_buf[i] = @min(min_w, remaining_width);
                    remaining_width -|= widths_buf[i];
                    flex_columns += 1;
                },
                .max => |max_w| {
                    widths_buf[i] = @min(max_w, remaining_width);
                    remaining_width -|= widths_buf[i];
                    flex_columns += 1;
                },
            }
        }

        // Second pass: distribute remaining space to flex columns
        if (flex_columns > 0 and remaining_width > 0) {
            const extra_per_col = remaining_width / @as(u16, @intCast(flex_columns));
            for (self.columns, 0..) |col, i| {
                switch (col.width) {
                    .min => widths_buf[i] += extra_per_col,
                    .max => |max_w| widths_buf[i] = @min(widths_buf[i] + extra_per_col, max_w),
                    else => {},
                }
            }
        }
    }

    /// Render a cell at the given position
    fn renderCell(buf: *Buffer, x: u16, y: u16, text: []const u8, width: u16, alignment: Alignment, cell_style: Style) void {
        if (width == 0) return;

        const offset = alignText(text, width, alignment);
        var col: u16 = 0;

        // Fill with spaces before text (for center/right alignment)
        while (col < offset) : (col += 1) {
            buf.set(x + col, y, .{ .char = ' ', .style = cell_style });
        }

        // Render text with proper UTF-8 decoding
        var text_idx: usize = 0;
        while (col < width and text_idx < text.len) {
            const byte = text[text_idx];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (text_idx + char_len > text.len) break;

            const codepoint = if (char_len == 1)
                @as(u21, byte)
            else
                std.unicode.utf8Decode(text[text_idx .. text_idx + char_len]) catch @as(u21, byte);

            buf.set(x + col, y, .{ .char = codepoint, .style = cell_style });
            text_idx += char_len;
            col += 1;
        }

        // Fill remaining width with spaces
        while (col < width) : (col += 1) {
            buf.set(x + col, y, .{ .char = ' ', .style = cell_style });
        }
    }

    /// Calculate x offset for text based on alignment
    fn alignText(text: []const u8, width: u16, alignment: Alignment) u16 {
        const text_len = @min(text.len, width);
        return switch (alignment) {
            .left => 0,
            .center => (width -| @as(u16, @intCast(text_len))) / 2,
            .right => width -| @as(u16, @intCast(text_len)),
        };
    }

    /// Render the TreeTable widget
    pub fn render(self: TreeTable, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Calculate column widths (max 64 columns supported)
        var widths: [64]u16 = undefined;
        if (self.columns.len > 64) return;
        self.calculateColumnWidths(inner_area.width, widths[0..self.columns.len]);

        var y = inner_area.y;

        // Render header row
        if (y < inner_area.y + inner_area.height) {
            var x = inner_area.x;
            for (self.columns, 0..) |col, i| {
                if (x >= inner_area.x + inner_area.width) break;
                renderCell(buf, x, y, col.title, widths[i], col.alignment, self.header_style);
                x += widths[i];
                if (i < self.columns.len - 1) x += self.column_spacing;
            }
            y += 1;
        }

        // Calculate visible rows available
        const max_rows = inner_area.height -| 1; // Subtract header row
        if (max_rows == 0) return;

        // Collect visible nodes into flat list
        var flat_buf: [1024]FlatNode = undefined;
        var flat_count: usize = 0;
        collectVisible(self.nodes, 0, &flat_buf, &flat_count);

        // Calculate start and end indices for scrolling
        const start_idx = @min(self.offset, flat_count);
        const end_idx = @min(start_idx + max_rows, flat_count);

        // Render visible data rows
        for (start_idx..end_idx) |flat_idx| {
            if (y >= inner_area.y + inner_area.height) break;

            const flat_node = flat_buf[flat_idx];
            const node = flat_node.node;
            const depth = flat_node.depth;
            const is_selected = if (self.selected) |sel| flat_idx == sel else false;
            const cell_style = if (is_selected) self.selected_style else self.row_style;

            var x = inner_area.x;

            // Render first column with tree prefix
            if (self.columns.len > 0) {
                const col_width = widths[0];
                if (col_width > 0) {
                    // Build prefix: indent spaces + symbol + cell text
                    var prefix_buf: [256]u8 = undefined;
                    var prefix_len: usize = 0;

                    // Add indent spaces (depth * indent)
                    const indent_spaces = depth * self.indent;
                    for (0..indent_spaces) |_| {
                        if (prefix_len < prefix_buf.len) {
                            prefix_buf[prefix_len] = ' ';
                            prefix_len += 1;
                        }
                    }

                    // Add symbol
                    const symbol = if (node.children.len == 0)
                        self.leaf_symbol
                    else if (node.expanded)
                        self.expanded_symbol
                    else
                        self.collapsed_symbol;

                    for (symbol) |ch| {
                        if (prefix_len < prefix_buf.len) {
                            prefix_buf[prefix_len] = ch;
                            prefix_len += 1;
                        }
                    }

                    // Add cell text
                    const cell_text = if (node.cells.len > 0) node.cells[0] else "";
                    for (cell_text) |ch| {
                        if (prefix_len < prefix_buf.len) {
                            prefix_buf[prefix_len] = ch;
                            prefix_len += 1;
                        }
                    }

                    // Render the prefix+text as cell, truncated to column width
                    const prefix = prefix_buf[0..prefix_len];
                    renderCell(buf, x, y, prefix, col_width, self.columns[0].alignment, cell_style);
                    x += col_width;
                }

                // Render remaining columns
                for (1..self.columns.len) |col_idx| {
                    if (x >= inner_area.x + inner_area.width) break;

                    const cell_text = if (col_idx < node.cells.len) node.cells[col_idx] else "";
                    renderCell(buf, x, y, cell_text, widths[col_idx], self.columns[col_idx].alignment, cell_style);

                    x += widths[col_idx];
                    if (col_idx < self.columns.len - 1) x += self.column_spacing;
                }
            }

            y += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TreeTable init creates table with default values" {
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .percentage = 50 } },
        .{ .title = "Type", .width = .{ .percentage = 50 } },
    };
    const tt = TreeTable.init(&cols, &.{});
    try std.testing.expectEqual(@as(?usize, null), tt.selected);
    try std.testing.expectEqual(@as(usize, 0), tt.offset);
    try std.testing.expectEqual(@as(u16, 1), tt.column_spacing);
    try std.testing.expectEqual(@as(u16, 2), tt.indent);
}
