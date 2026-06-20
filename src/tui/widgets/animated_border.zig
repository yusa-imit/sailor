//! AnimatedBorder widget — a border with frame-based color animation.
//!
//! The AnimatedBorder widget renders a colored border around an area with various
//! animation styles that cycle through a color palette based on the current frame.
//!
//! ## Features
//! - Multiple animation styles: rainbow, pulse, chase, flash, gradient
//! - Frame-based animation with configurable speed
//! - Optional title text with custom styling
//! - Customizable border characters (BoxSet)
//! - Fluent builder API for configuration
//!
//! ## Usage
//! ```zig
//! var border = AnimatedBorder.init()
//!     .withAnimationStyle(.rainbow)
//!     .withTitle("Loading");
//! border.tick();
//! border.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const symbols_mod = @import("../symbols.zig");
const BoxSet = symbols_mod.BoxSet;

/// Default color palette for animations
const default_colors = [_]Color{
    Color.red, Color.yellow, Color.green, Color.cyan, Color.blue, Color.magenta,
};

/// AnimatedBorder widget with frame-based color animation
pub const AnimatedBorder = struct {
    /// Animation style determines how colors cycle
    pub const AnimationStyle = enum {
        rainbow, // Each position gets a color based on position + frame
        pulse,   // All positions get the same color cycling by frame
        chase,   // One animated cell chases around; rest get base_style
        flash,   // Alternates between two colors
        gradient, // Position-based gradient that shifts with frame
    };

    frame: u32 = 0,
    style: AnimationStyle = .rainbow,
    speed: u8 = 4,
    colors: []const Color = &default_colors,
    base_style: Style = .{},
    title: []const u8 = "",
    title_style: Style = .{},
    border_set: BoxSet = BoxSet.rounded,

    /// Initialize with default values
    pub fn init() AnimatedBorder {
        return .{ .colors = &default_colors };
    }

    /// Increment frame by 1 (wrapping at u32 max)
    pub fn tick(self: *AnimatedBorder) void {
        self.frame +%= 1;
    }

    /// Increment frame by n (wrapping at u32 max)
    pub fn tickBy(self: *AnimatedBorder, n: u32) void {
        self.frame +%= n;
    }

    /// Reset frame to 0
    pub fn reset(self: *AnimatedBorder) void {
        self.frame = 0;
    }

    /// Get the inner area (shrink by 1 on all sides)
    pub fn innerArea(_: @This(), area: Rect) Rect {
        if (area.width <= 2 or area.height <= 2) {
            return Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
        }
        return Rect{
            .x = area.x + 1,
            .y = area.y + 1,
            .width = area.width - 2,
            .height = area.height - 2,
        };
    }

    /// Builder: set frame
    pub fn withFrame(self: @This(), frame: u32) @This() {
        var copy = self;
        copy.frame = frame;
        return copy;
    }

    /// Builder: set animation style
    pub fn withAnimationStyle(self: @This(), s: AnimationStyle) @This() {
        var copy = self;
        copy.style = s;
        return copy;
    }

    /// Builder: set speed
    pub fn withSpeed(self: @This(), speed: u8) @This() {
        var copy = self;
        copy.speed = speed;
        return copy;
    }

    /// Builder: set colors
    pub fn withColors(self: @This(), colors: []const Color) @This() {
        var copy = self;
        copy.colors = colors;
        return copy;
    }

    /// Builder: set base_style
    pub fn withBaseStyle(self: @This(), s: Style) @This() {
        var copy = self;
        copy.base_style = s;
        return copy;
    }

    /// Builder: set title
    pub fn withTitle(self: @This(), title: []const u8) @This() {
        var copy = self;
        copy.title = title;
        return copy;
    }

    /// Builder: set title_style
    pub fn withTitleStyle(self: @This(), s: Style) @This() {
        var copy = self;
        copy.title_style = s;
        return copy;
    }

    /// Builder: set border_set
    pub fn withBorderSet(self: @This(), bs: BoxSet) @This() {
        var copy = self;
        copy.border_set = bs;
        return copy;
    }

    /// Render the animated border
    pub fn render(self: @This(), buf: *Buffer, area: Rect) void {
        const w = area.width;
        const h = area.height;

        // Guard: minimum 2x2 area to draw anything
        if (w < 2 or h < 2) return;

        const speed_val: u32 = if (self.speed == 0) 1 else @as(u32, self.speed);
        const step = self.frame / speed_val;

        // Calculate perimeter length: 2*(w + h) - 4
        const perim: u32 = 2 * @as(u32, w) + 2 * @as(u32, h) - 4;
        if (perim == 0) return;

        // Render border perimeter
        var pos: u32 = 0;

        // Top edge: y=area.y, x=area.x..area.x+w-1
        for (0..w) |px| {
            const col = area.x + @as(u16, @intCast(px));
            const char = if (px == 0)
                self.border_set.top_left
            else if (px == w - 1)
                self.border_set.top_right
            else
                self.border_set.horizontal;

            const cell_color = self.getAnimationColor(pos, step, perim);
            const cell_style = self.getAnimationStyle(pos, step, perim, cell_color);
            buf.setString(col, area.y, char, cell_style);
            pos += 1;
        }

        // Right edge: y=area.y+1..area.y+h-2, x=area.x+w-1
        for (1..h - 1) |py| {
            const row = area.y + @as(u16, @intCast(py));
            const col = area.x + w - 1;
            const char = self.border_set.vertical;

            const cell_color = self.getAnimationColor(pos, step, perim);
            const cell_style = self.getAnimationStyle(pos, step, perim, cell_color);
            buf.setString(col, row, char, cell_style);
            pos += 1;
        }

        // Bottom edge: y=area.y+h-1, x=area.x+w-1..area.x (right to left)
        for (0..w) |px| {
            const px_rev = w - 1 - px;
            const col = area.x + @as(u16, @intCast(px_rev));
            const char = if (px_rev == 0)
                self.border_set.bottom_left
            else if (px_rev == w - 1)
                self.border_set.bottom_right
            else
                self.border_set.horizontal;

            const cell_color = self.getAnimationColor(pos, step, perim);
            const cell_style = self.getAnimationStyle(pos, step, perim, cell_color);
            buf.setString(col, area.y + h - 1, char, cell_style);
            pos += 1;
        }

        // Left edge: y=area.y+h-2..area.y+1 (bottom to top), x=area.x
        for (1..h - 1) |py| {
            const py_rev = h - 1 - py;
            const row = area.y + @as(u16, @intCast(py_rev));
            const char = self.border_set.vertical;

            const cell_color = self.getAnimationColor(pos, step, perim);
            const cell_style = self.getAnimationStyle(pos, step, perim, cell_color);
            buf.setString(area.x, row, char, cell_style);
            pos += 1;
        }

        // Render title if present
        if (self.title.len > 0 and area.width >= 5) {
            const max_title_len = area.width - 4;
            const rendered = if (self.title.len > max_title_len)
                self.title[0..max_title_len]
            else
                self.title;

            buf.setString(area.x + 2, area.y, rendered, self.title_style);
        }
    }

    /// Get animation color for a perimeter position
    fn getAnimationColor(self: @This(), pos: u32, step: u32, perim: u32) Color {
        if (self.colors.len == 0) return .reset;

        return switch (self.style) {
            .rainbow => blk: {
                const idx = (pos + step) % @as(u32, @intCast(self.colors.len));
                break :blk self.colors[@intCast(idx)];
            },
            .pulse => blk: {
                const idx = step % @as(u32, @intCast(self.colors.len));
                break :blk self.colors[@intCast(idx)];
            },
            .chase => blk: {
                const chase_pos = step % perim;
                if (pos == chase_pos) {
                    break :blk self.colors[0];
                }
                break :blk .reset;
            },
            .flash => blk: {
                const phase = step % 2;
                if (phase == 0) {
                    break :blk self.colors[0];
                }
                if (self.colors.len > 1) {
                    break :blk self.colors[1];
                }
                break :blk .reset;
            },
            .gradient => blk: {
                const idx = (pos * @as(u32, @intCast(self.colors.len)) / perim + step) % @as(u32, @intCast(self.colors.len));
                break :blk self.colors[@intCast(idx)];
            },
        };
    }

    /// Get animation style for a perimeter position
    fn getAnimationStyle(self: @This(), pos: u32, step: u32, perim: u32, color: Color) Style {
        return switch (self.style) {
            .chase => blk: {
                const chase_pos = step % perim;
                if (pos == chase_pos) {
                    break :blk self.base_style.withFg(color);
                }
                break :blk self.base_style;
            },
            .flash => blk: {
                const phase = step % 2;
                if (phase == 0 or (phase == 1 and self.colors.len > 1)) {
                    break :blk self.base_style.withFg(color);
                }
                break :blk self.base_style;
            },
            else => self.base_style.withFg(color),
        };
    }
};

// Tests
test "AnimatedBorder init returns default frame value" {
    const border = AnimatedBorder.init();
    try std.testing.expectEqual(@as(u32, 0), border.frame);
}

test "AnimatedBorder init returns default animation style" {
    const border = AnimatedBorder.init();
    try std.testing.expectEqual(AnimatedBorder.AnimationStyle.rainbow, border.style);
}

test "AnimatedBorder init returns default speed" {
    const border = AnimatedBorder.init();
    try std.testing.expectEqual(@as(u8, 4), border.speed);
}
