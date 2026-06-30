//! Treemap Widget — Hierarchical Proportional Rectangle Visualization
//!
//! Treemap displays a collection of items as proportional rectangles,
//! using a binary partition layout algorithm to recursively divide space.
//! Each item's rectangle size corresponds to its value.
//!
//! ## Features
//! - Binary partition layout algorithm
//! - Proportional sizing based on item values
//! - Customizable styles for items, labels, and focused state
//! - Support up to 64 items (MAX_ITEMS cap)
//! - Optional block borders
//! - Label rendering with centering and truncation
//!
//! ## Usage
//! ```zig
//! const items = [_]TreemapItem{
//!     .{ .label = "A", .value = 100.0 },
//!     .{ .label = "B", .value = 50.0 },
//!     .{ .label = "C", .value = 25.0 },
//! };
//!
//! const treemap = Treemap.init()
//!     .withItems(&items)
//!     .withFocused(0)
//!     .withShowValue(false);
//!
//! treemap.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Single item in a Treemap
pub const TreemapItem = struct {
    label: []const u8 = "",
    value: f32 = 0,
    style: Style = .{},
};

/// Treemap widget for proportional rectangle visualization
pub const Treemap = struct {
    pub const MAX_ITEMS: usize = 64;

    items: []const TreemapItem = &.{},
    focused: usize = 0,
    style: Style = .{},
    label_style: Style = .{},
    focused_style: Style = .{},
    show_value: bool = false,
    block: ?Block = null,

    /// Initialize a new Treemap with default values
    pub fn init() Treemap {
        return .{};
    }

    /// Return the number of items to render (capped at MAX_ITEMS)
    pub fn itemCount(self: Treemap) usize {
        return @min(self.items.len, MAX_ITEMS);
    }

    /// Calculate total value of all items (capped at MAX_ITEMS)
    pub fn totalValue(self: Treemap) f32 {
        var total: f32 = 0.0;
        const n = self.itemCount();
        for (0..n) |i| {
            total += self.items[i].value;
        }
        return total;
    }

    /// Set items (builder pattern)
    pub fn withItems(self: Treemap, items: []const TreemapItem) Treemap {
        var result = self;
        result.items = items;
        return result;
    }

    /// Set focused item index (builder pattern)
    pub fn withFocused(self: Treemap, focused: usize) Treemap {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Set base style (builder pattern)
    pub fn withStyle(self: Treemap, style: Style) Treemap {
        var result = self;
        result.style = style;
        return result;
    }

    /// Set label style (builder pattern)
    pub fn withLabelStyle(self: Treemap, label_style: Style) Treemap {
        var result = self;
        result.label_style = label_style;
        return result;
    }

    /// Set focused style (builder pattern)
    pub fn withFocusedStyle(self: Treemap, focused_style: Style) Treemap {
        var result = self;
        result.focused_style = focused_style;
        return result;
    }

    /// Set show_value flag (builder pattern)
    pub fn withShowValue(self: Treemap, show_value: bool) Treemap {
        var result = self;
        result.show_value = show_value;
        return result;
    }

    /// Set block border (builder pattern)
    pub fn withBlock(self: Treemap, block: ?Block) Treemap {
        var result = self;
        result.block = block;
        return result;
    }

    /// Draw a single cell/item
    fn drawCell(self: Treemap, buf: *Buffer, area: Rect, item: TreemapItem, is_focused: bool) void {
        if (area.width == 0 or area.height == 0) return;

        const cell_style = if (is_focused) item.style.merge(self.focused_style) else item.style;

        // Fill entire area with spaces using cell_style background
        buf.fill(area, ' ', cell_style);

        // Draw box chars if area >= 2x2
        if (area.width >= 2 and area.height >= 2) {
            buf.set(area.x, area.y, Cell.init('┌', cell_style));
            buf.set(area.x + area.width - 1, area.y, Cell.init('┐', cell_style));
            buf.set(area.x, area.y + area.height - 1, Cell.init('└', cell_style));
            buf.set(area.x + area.width - 1, area.y + area.height - 1, Cell.init('┘', cell_style));

            // Top and bottom borders
            for (1..area.width - 1) |dx| {
                buf.set(area.x + @as(u16, @intCast(dx)), area.y, Cell.init('─', cell_style));
                buf.set(area.x + @as(u16, @intCast(dx)), area.y + area.height - 1, Cell.init('─', cell_style));
            }

            // Left and right borders
            for (1..area.height - 1) |dy| {
                buf.set(area.x, area.y + @as(u16, @intCast(dy)), Cell.init('│', cell_style));
                buf.set(area.x + area.width - 1, area.y + @as(u16, @intCast(dy)), Cell.init('│', cell_style));
            }
        }

        // Draw label if area is large enough
        const has_border = area.width >= 2 and area.height >= 2;
        if (has_border and area.width >= 4 and area.height >= 3) {
            const inner_x = area.x + 1;
            const inner_y = area.y + (area.height / 2); // vertically centered in inner area
            const inner_w = area.width - 2;

            if (item.label.len > 0) {
                const label_style = if (is_focused) self.label_style.merge(self.focused_style) else self.label_style;
                const max_len = @min(item.label.len, inner_w);
                const label = item.label[0..max_len];
                const label_x = inner_x + (inner_w - @as(u16, @intCast(max_len))) / 2;
                buf.setString(label_x, inner_y, label, label_style);
            }
        }
    }

    /// Recursively render partition treemap
    fn renderPartition(buf: *Buffer, area: Rect, items: []const TreemapItem, indices: []const usize, total: f32, self: Treemap) void {
        if (items.len == 0 or area.width == 0 or area.height == 0 or total <= 0) {
            return;
        }

        if (items.len == 1) {
            const is_focused = indices[0] == self.focused;
            self.drawCell(buf, area, items[0], is_focused);
            return;
        }

        const half = items.len / 2;
        var left_total: f32 = 0.0;
        for (0..half) |i| {
            left_total += items[i].value;
        }
        const right_total = total - left_total;

        if (area.width >= area.height) {
            // Horizontal split (left/right)
            const left_w_f = @as(f32, @floatFromInt(area.width)) * left_total / total;
            var left_w = @as(u16, @intFromFloat(left_w_f));
            left_w = @min(left_w, area.width);

            if (left_w > 0 and left_total > 0) {
                const left_area = Rect{ .x = area.x, .y = area.y, .width = left_w, .height = area.height };
                renderPartition(buf, left_area, items[0..half], indices[0..half], left_total, self);
            }

            if (left_w < area.width and right_total > 0) {
                const right_w = area.width - left_w;
                const right_area = Rect{ .x = area.x + left_w, .y = area.y, .width = right_w, .height = area.height };
                renderPartition(buf, right_area, items[half..], indices[half..], right_total, self);
            }
        } else {
            // Vertical split (top/bottom)
            const top_h_f = @as(f32, @floatFromInt(area.height)) * left_total / total;
            var top_h = @as(u16, @intFromFloat(top_h_f));
            top_h = @min(top_h, area.height);

            if (top_h > 0 and left_total > 0) {
                const top_area = Rect{ .x = area.x, .y = area.y, .width = area.width, .height = top_h };
                renderPartition(buf, top_area, items[0..half], indices[0..half], left_total, self);
            }

            if (top_h < area.height and right_total > 0) {
                const bot_h = area.height - top_h;
                const bot_area = Rect{ .x = area.x, .y = area.y + top_h, .width = area.width, .height = bot_h };
                renderPartition(buf, bot_area, items[half..], indices[half..], right_total, self);
            }
        }
    }

    /// Render the treemap to a buffer
    pub fn render(self: Treemap, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Calculate inner area after block border
        const inner = if (self.block) |b| blk: {
            b.render(buf, area);
            break :blk b.inner(area);
        } else area;

        if (inner.width == 0 or inner.height == 0) return;

        // Fill inner area with base style
        buf.fill(inner, ' ', self.style);

        const n = self.itemCount();
        if (n == 0) return;

        const total = self.totalValue();
        if (total <= 0) return;

        // Stack-allocate sorted arrays
        var sorted_items: [MAX_ITEMS]TreemapItem = undefined;
        var sorted_indices: [MAX_ITEMS]usize = undefined;

        // Copy items and indices
        for (0..n) |i| {
            sorted_items[i] = self.items[i];
            sorted_indices[i] = i;
        }

        // Insertion sort descending by value
        for (1..n) |i| {
            const ki = sorted_items[i];
            const ii = sorted_indices[i];
            var j = i;
            while (j > 0 and sorted_items[j - 1].value < ki.value) {
                sorted_items[j] = sorted_items[j - 1];
                sorted_indices[j] = sorted_indices[j - 1];
                j -= 1;
            }
            sorted_items[j] = ki;
            sorted_indices[j] = ii;
        }

        // Render partition recursively
        renderPartition(buf, inner, sorted_items[0..n], sorted_indices[0..n], total, self);
    }
};
