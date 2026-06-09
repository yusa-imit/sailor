//! MultiSelectList Widget — v2.24.0
//!
//! Multi-selection list with cursor navigation, toggle selection, and customizable rendering.
//! Each item can be independently selected/deselected with keyboard navigation.
//!
//! ## Features
//! - Cursor-based navigation (up/down)
//! - Toggle selection on individual items
//! - Select all / deselect all operations
//! - Custom symbols for cursor, selected, and unselected items
//! - Optional Block wrapper for borders and title
//! - Customizable styles for cursor, selected, and normal items
//!
//! ## Usage
//! ```zig
//! var selections = [_]bool{ false, false, false };
//! var list = MultiSelectList{
//!     .items = &[_][]const u8{ "Item 1", "Item 2", "Item 3" },
//!     .selections = &selections,
//! };
//! list.moveCursorDown();
//! list.toggleCursor();
//! const count = list.countSelected();
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

/// MultiSelectList widget - list with multi-selection support
pub const MultiSelectList = struct {
    items: []const []const u8,       // source items (immutable)
    selections: []bool,               // caller-provided selection state, same len as items
    cursor: usize = 0,               // current cursor position
    cursor_style: Style = .{ .bg = .blue },
    selected_style: Style = .{ .fg = .cyan, .bold = true },
    normal_style: Style = .{},
    cursor_symbol: []const u8 = "> ",
    selected_symbol: []const u8 = "[x] ",
    unselected_symbol: []const u8 = "[ ] ",
    block: ?Block = null,

    /// Move cursor up one position (clamps at 0)
    pub fn moveCursorUp(self: *MultiSelectList) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    /// Move cursor down one position (clamps at items.len-1)
    pub fn moveCursorDown(self: *MultiSelectList) void {
        if (self.items.len == 0) return;
        if (self.cursor < self.items.len - 1) {
            self.cursor += 1;
        }
    }

    /// Toggle selection state of item at cursor position
    pub fn toggleCursor(self: *MultiSelectList) void {
        if (self.cursor < self.selections.len) {
            self.selections[self.cursor] = !self.selections[self.cursor];
        }
    }

    /// Select all items
    pub fn selectAll(self: *MultiSelectList) void {
        for (self.selections) |*sel| {
            sel.* = true;
        }
    }

    /// Deselect all items
    pub fn deselectAll(self: *MultiSelectList) void {
        for (self.selections) |*sel| {
            sel.* = false;
        }
    }

    /// Count number of selected items
    pub fn countSelected(self: MultiSelectList) usize {
        var count: usize = 0;
        for (self.selections) |sel| {
            if (sel) count += 1;
        }
        return count;
    }

    /// Check if item at index is selected (bounds-safe)
    pub fn isSelected(self: MultiSelectList, idx: usize) bool {
        if (idx >= self.selections.len) return false;
        return self.selections[idx];
    }

    /// Render the widget to a buffer
    pub fn render(self: MultiSelectList, buf: *Buffer, area: Rect) void {
        // Handle block if present
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner_area = block.inner(area);
        }

        // Bounds check
        if (inner_area.width == 0 or inner_area.height == 0) {
            return;
        }

        // Render each item
        var row: u16 = 0;
        for (self.items, 0..) |item, idx| {
            if (row >= inner_area.height) break;

            const y = inner_area.y + row;
            var x = inner_area.x;

            const is_cursor = (idx == self.cursor);
            const is_selected = self.isSelected(idx);

            // Determine style and symbol
            const style = if (is_cursor) self.cursor_style else if (is_selected) self.selected_style else self.normal_style;
            const symbol = if (is_cursor) self.cursor_symbol else if (is_selected) self.selected_symbol else self.unselected_symbol;

            // Write symbol
            buf.setString(x, y, symbol, style);
            x += @intCast(symbol.len);

            // Write item text (ensure we don't overflow width)
            if (x < inner_area.x + inner_area.width) {
                const remaining_width = inner_area.x + inner_area.width - x;
                const text = if (item.len > remaining_width) item[0..remaining_width] else item;
                buf.setString(x, y, text, style);
            }

            row += 1;
        }
    }
};
