//! ReorderableList Widget — v2.24.0
//!
//! Interactive list widget that supports drag-and-drop reordering via keyboard.
//! Maintains a separate order index array so item labels remain immutable while
//! the display sequence can be freely rearranged.
//!
//! ## Features
//! - Cursor-based navigation (up/down)
//! - Drag mode: moveCursorUp/Down swaps adjacent order entries
//! - toggleDrag/startDrag/stopDrag to control drag state
//! - getOrderedItem(idx) returns item at visual row idx
//! - Optional Block wrapper for borders/title
//!
//! ## Usage
//! ```zig
//! var order = [_]usize{ 0, 1, 2 };
//! var list = ReorderableList{
//!     .items = &[_][]const u8{ "A", "B", "C" },
//!     .order = &order,
//! };
//! list.startDrag();
//! list.moveCursorDown(); // moves "A" down one position
//! list.stopDrag();
//! list.render(buf, area);
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

/// ReorderableList widget — list with keyboard drag-and-drop reordering
pub const ReorderableList = struct {
    items: []const []const u8,  // source item labels (immutable)
    order: []usize,              // display order: order[visual_row] = items_index
    cursor: usize = 0,           // current cursor position (visual row)
    drag_active: bool = false,   // true while user is dragging an item

    cursor_style: Style = .{ .bg = .blue },
    drag_style: Style = .{ .bg = .yellow, .bold = true },
    normal_style: Style = .{},

    cursor_symbol: []const u8 = "> ",
    drag_symbol: []const u8 = "* ",
    normal_symbol: []const u8 = "  ",

    block: ?Block = null,

    /// Move cursor up one row. When drag_active, swaps the dragged item up.
    pub fn moveCursorUp(self: *ReorderableList) void {
        if (self.cursor == 0) return;
        if (self.drag_active) {
            const tmp = self.order[self.cursor];
            self.order[self.cursor] = self.order[self.cursor - 1];
            self.order[self.cursor - 1] = tmp;
        }
        self.cursor -= 1;
    }

    /// Move cursor down one row. When drag_active, swaps the dragged item down.
    pub fn moveCursorDown(self: *ReorderableList) void {
        if (self.items.len == 0) return;
        if (self.cursor >= self.items.len - 1) return;
        if (self.drag_active) {
            const tmp = self.order[self.cursor];
            self.order[self.cursor] = self.order[self.cursor + 1];
            self.order[self.cursor + 1] = tmp;
        }
        self.cursor += 1;
    }

    /// Activate drag mode.
    pub fn startDrag(self: *ReorderableList) void {
        self.drag_active = true;
    }

    /// Deactivate drag mode.
    pub fn stopDrag(self: *ReorderableList) void {
        self.drag_active = false;
    }

    /// Toggle drag mode.
    pub fn toggleDrag(self: *ReorderableList) void {
        self.drag_active = !self.drag_active;
    }

    /// Return the item label at visual row `idx` (follows order slice).
    pub fn getOrderedItem(self: ReorderableList, idx: usize) []const u8 {
        return self.items[self.order[idx]];
    }

    /// Render the widget to a buffer.
    pub fn render(self: ReorderableList, buf: *Buffer, area: Rect) void {
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner_area = block.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        var row: u16 = 0;
        for (0..self.items.len) |idx| {
            if (row >= inner_area.height) break;

            const y = inner_area.y + row;
            var x = inner_area.x;

            const is_cursor = (idx == self.cursor);
            const style = if (is_cursor and self.drag_active)
                self.drag_style
            else if (is_cursor)
                self.cursor_style
            else
                self.normal_style;

            const symbol = if (is_cursor and self.drag_active)
                self.drag_symbol
            else if (is_cursor)
                self.cursor_symbol
            else
                self.normal_symbol;

            buf.setString(x, y, symbol, style);
            x += @intCast(symbol.len);

            if (x < inner_area.x + inner_area.width) {
                const remaining = inner_area.x + inner_area.width - x;
                const label = self.getOrderedItem(idx);
                const text = if (label.len > remaining) label[0..remaining] else label;
                buf.setString(x, y, text, style);
            }

            row += 1;
        }
    }
};
