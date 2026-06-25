const std = @import("std");
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Block = @import("block.zig").Block;

/// RingMenu widget — arranges selectable text items in a circular ring
pub const RingMenu = struct {
    items: []const []const u8 = &.{},
    selected: usize = 0,
    center_label: []const u8 = "",
    style: Style = .{},
    selected_style: Style = .{},
    center_style: Style = .{},
    radius: u8 = 4,
    block: ?Block = null,

    pub fn init() RingMenu {
        return .{};
    }

    pub fn withItems(self: RingMenu, items: []const []const u8) RingMenu {
        var result = self;
        result.items = items;
        return result;
    }

    pub fn withSelected(self: RingMenu, selected: usize) RingMenu {
        var result = self;
        result.selected = selected;
        return result;
    }

    pub fn withCenterLabel(self: RingMenu, label: []const u8) RingMenu {
        var result = self;
        result.center_label = label;
        return result;
    }

    pub fn withStyle(self: RingMenu, style: Style) RingMenu {
        var result = self;
        result.style = style;
        return result;
    }

    pub fn withSelectedStyle(self: RingMenu, style: Style) RingMenu {
        var result = self;
        result.selected_style = style;
        return result;
    }

    pub fn withCenterStyle(self: RingMenu, style: Style) RingMenu {
        var result = self;
        result.center_style = style;
        return result;
    }

    pub fn withRadius(self: RingMenu, radius: u8) RingMenu {
        var result = self;
        result.radius = radius;
        return result;
    }

    pub fn withBlock(self: RingMenu, block: Block) RingMenu {
        var result = self;
        result.block = block;
        return result;
    }

    pub fn next(self: *RingMenu) void {
        if (self.items.len == 0) return;
        self.selected = (self.selected + 1) % self.items.len;
    }

    pub fn prev(self: *RingMenu) void {
        if (self.items.len == 0) return;
        self.selected = if (self.selected == 0) self.items.len - 1 else self.selected - 1;
    }

    pub fn selectedItem(self: RingMenu) ?[]const u8 {
        if (self.items.len == 0 or self.selected >= self.items.len) return null;
        return self.items[self.selected];
    }

    pub fn render(self: RingMenu, buf: *Buffer, area: Rect) void {
        // 1. Apply block border → inner area
        const inner = if (self.block) |b| blk: {
            b.render(buf, area);
            break :blk b.inner(area);
        } else area;

        // 2. Guard zero-size inner
        if (inner.width == 0 or inner.height == 0) return;

        // 3. Compute center
        const cx = inner.x + inner.width / 2;
        const cy = inner.y + inner.height / 2;
        const n = self.items.len;

        // 4. Render each item at its ring position
        if (n > 0) {
            for (0..n) |i| {
                const label = self.items[i];
                if (label.len == 0) continue;

                // Compute angle: clockwise from top
                const angle = std.math.tau * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n)) - std.math.pi / 2.0;

                // Compute raw position (×2 horizontal for terminal aspect ratio)
                const raw_ix = @as(f64, @floatFromInt(cx)) + @round(@as(f64, @floatFromInt(self.radius)) * @cos(angle) * 2.0);
                const raw_iy = @as(f64, @floatFromInt(cy)) + @round(@as(f64, @floatFromInt(self.radius)) * @sin(angle));

                // Clamp to inner area
                const ix = @as(u16, @intCast(@max(@as(i32, inner.x), @min(@as(i32, inner.x + inner.width) - 1, @as(i32, @intFromFloat(raw_ix))))));
                const iy = @as(u16, @intCast(@max(@as(i32, inner.y), @min(@as(i32, inner.y + inner.height) - 1, @as(i32, @intFromFloat(raw_iy))))));

                // Center label on computed position, clamped to area
                const half_len = @as(i32, @intCast(label.len / 2));
                const raw_lx: i32 = @as(i32, ix) - half_len;
                const max_lx = @as(i32, inner.x + inner.width) - @as(i32, @intCast(label.len));
                const lx = @as(u16, @intCast(@max(@as(i32, inner.x), @min(max_lx, raw_lx))));

                // Choose style
                const the_style = if (i == self.selected) self.selected_style else self.style;
                buf.setString(lx, iy, label, the_style);
            }
        }

        // 5. Render center label
        if (self.center_label.len > 0) {
            // Use ceil(len/2) for multi-char labels, floor(len/2) for single-char
            const half_len = @as(i32, @intCast(if (self.center_label.len == 1) @as(usize, 0) else (self.center_label.len + 1) / 2));
            const raw_lx: i32 = @as(i32, cx) - half_len;
            const max_lx = @as(i32, inner.x + inner.width) - @as(i32, @intCast(self.center_label.len));
            const lx = @as(u16, @intCast(@max(@as(i32, inner.x), @min(if (max_lx < @as(i32, inner.x)) @as(i32, inner.x) else max_lx, raw_lx))));
            buf.setString(lx, cy, self.center_label, self.center_style);
        }
    }
};
