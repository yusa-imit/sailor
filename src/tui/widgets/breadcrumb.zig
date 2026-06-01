//! Breadcrumb Widget — v2.19.0 (Simple API)
//!
//! Navigation breadcrumb for displaying hierarchical paths.
//! Supports custom separators, active item highlighting, and left-truncation.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;

/// Breadcrumb navigation widget
pub const Breadcrumb = struct {
    items: []const []const u8 = &.{},
    separator: []const u8 = " / ",
    active_idx: ?usize = null,
    active_style: Style = .{ .bold = true },
    separator_style: Style = .{ .fg = .bright_black },
    item_style: Style = .{},

    /// Calculate total display width needed for all items
    pub fn totalWidth(self: Breadcrumb) usize {
        if (self.items.len == 0) return 0;
        if (self.items.len == 1) return self.items[0].len;

        var width: usize = 0;
        for (self.items, 0..) |item, i| {
            width += item.len;
            if (i < self.items.len - 1) {
                width += self.separator.len;
            }
        }
        return width;
    }

    /// Return a copy with new items
    pub fn withItems(self: Breadcrumb, items: []const []const u8) Breadcrumb {
        var copy = self;
        copy.items = items;
        return copy;
    }

    /// Return a copy with new separator
    pub fn withSeparator(self: Breadcrumb, sep: []const u8) Breadcrumb {
        var copy = self;
        copy.separator = sep;
        return copy;
    }

    /// Return a copy with active index set
    pub fn withActive(self: Breadcrumb, idx: usize) Breadcrumb {
        var copy = self;
        copy.active_idx = idx;
        return copy;
    }

    /// Render the breadcrumb to the buffer
    pub fn render(self: Breadcrumb, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        if (self.items.len == 0) return;

        const total = self.totalWidth();

        // If all items fit, render them all
        if (total <= area.width) {
            self.renderFull(buf, area);
        } else {
            // Otherwise, truncate from the left
            self.renderTruncated(buf, area);
        }
    }

    fn renderFull(self: Breadcrumb, buf: *Buffer, area: Rect) void {
        var cursor_x: u16 = area.x;

        for (self.items, 0..) |item, i| {
            // Render item with appropriate style
            const is_active = self.active_idx == i;
            const style = if (is_active) self.active_style else self.item_style;
            buf.setString(cursor_x, area.y, item, style);
            cursor_x += @as(u16, @intCast(item.len));

            // Render separator (except after last item)
            if (i < self.items.len - 1) {
                buf.setString(cursor_x, area.y, self.separator, self.separator_style);
                cursor_x += @as(u16, @intCast(self.separator.len));
            }

            // Stop if we've exceeded the available width
            if (cursor_x >= area.x + area.width) break;
        }
    }

    fn renderTruncated(self: Breadcrumb, buf: *Buffer, area: Rect) void {
        const ellipsis = "…";
        const ellipsis_with_sep_len = 1 + self.separator.len;

        // Calculate how much space we have for content after ellipsis + separator
        const available_after_ellipsis = if (area.width > ellipsis_with_sep_len)
            @as(usize, area.width) - ellipsis_with_sep_len
        else
            0;

        // Find how many items from the end fit
        var items_to_render: usize = 0;
        var width_needed: usize = 0;

        var i: isize = @as(isize, @intCast(self.items.len)) - 1;
        while (i >= 0) : (i -= 1) {
            const idx = @as(usize, @intCast(i));
            const item_width = self.items[idx].len;
            if (items_to_render == 0) {
                width_needed = item_width;
                items_to_render = 1;
            } else {
                const sep_and_item = self.separator.len + item_width;
                if (width_needed + sep_and_item <= available_after_ellipsis) {
                    width_needed += sep_and_item;
                    items_to_render += 1;
                } else {
                    break;
                }
            }
        }

        // If no items fit after ellipsis, just render ellipsis
        if (items_to_render == 0) {
            buf.setString(area.x, area.y, ellipsis, self.separator_style);
            return;
        }

        // Render ellipsis + separator
        var cursor_x: u16 = area.x;
        buf.setString(cursor_x, area.y, ellipsis, self.separator_style);
        cursor_x += 1;

        if (area.width > 1) {
            buf.setString(cursor_x, area.y, self.separator, self.separator_style);
            cursor_x += @as(u16, @intCast(self.separator.len));
        }

        // Render the items that fit
        const start_idx = self.items.len - items_to_render;
        for (self.items[start_idx..], 0..) |item, j| {
            if (cursor_x >= area.x + area.width) break;

            // Render item
            const is_active = self.active_idx != null and self.active_idx.? >= start_idx + j;
            const style = if (is_active) self.active_style else self.item_style;
            buf.setString(cursor_x, area.y, item, style);
            cursor_x += @as(u16, @intCast(item.len));

            // Render separator (except after last item)
            if (j < items_to_render - 1) {
                if (cursor_x < area.x + area.width) {
                    buf.setString(cursor_x, area.y, self.separator, self.separator_style);
                    cursor_x += @as(u16, @intCast(self.separator.len));
                }
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Breadcrumb default state" {
    const bc = Breadcrumb{};
    try std.testing.expectEqual(@as(usize, 0), bc.items.len);
    try std.testing.expectEqualSlices(u8, " / ", bc.separator);
    try std.testing.expect(bc.active_idx == null);
}

test "totalWidth empty items" {
    const bc = Breadcrumb{ .items = &.{} };
    try std.testing.expectEqual(@as(usize, 0), bc.totalWidth());
}

test "totalWidth single item" {
    const items = [_][]const u8{"Home"};
    const bc = Breadcrumb{ .items = &items };
    try std.testing.expectEqual(@as(usize, 4), bc.totalWidth());
}

test "totalWidth with separator" {
    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    try std.testing.expectEqual(@as(usize, 11), bc.totalWidth());
}

test "withItems returns updated breadcrumb" {
    const items1 = [_][]const u8{"Old"};
    const items2 = [_][]const u8{ "New", "Path" };
    var bc = Breadcrumb{ .items = &items1 };
    bc = bc.withItems(&items2);
    try std.testing.expectEqual(@as(usize, 2), bc.items.len);
}

test "withSeparator returns updated breadcrumb" {
    const items = [_][]const u8{ "A", "B" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    const updated = bc.withSeparator(" > ");
    try std.testing.expectEqualSlices(u8, " > ", updated.separator);
}

test "withActive sets active_idx" {
    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items };
    const updated = bc.withActive(1);
    try std.testing.expectEqual(@as(?usize, 1), updated.active_idx);
}
