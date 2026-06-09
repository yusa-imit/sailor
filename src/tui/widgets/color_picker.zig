//! ColorPicker Widget — v2.27.0
//!
//! Interactive color selection widget supporting three modes:
//! - palette_256: Full 256-color palette (16x16 grid)
//! - palette_16: Basic ANSI 16-color palette (8x2 grid)
//! - rgb_sliders: RGB component sliders [0-255]
//!
//! No-alloc rendering. Writer-based API.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Color picker mode
pub const ColorPickerMode = enum {
    palette_256,   // Full 256-color palette
    palette_16,    // Basic ANSI 16-color palette
    rgb_sliders,   // RGB component sliders
};

/// Active RGB component in slider mode
pub const RgbComponent = enum {
    r,
    g,
    b,
};

/// ColorPicker widget — interactive color selection
pub const ColorPicker = struct {
    mode: ColorPickerMode,
    cursor_x: u8,              // Palette column cursor [0..15] for palette modes, unused in rgb_sliders
    cursor_y: u8,              // Palette row cursor [0..15] for palette_256, [0..1] for palette_16
    r: u8,                     // RGB red component [0..255]
    g: u8,                     // RGB green component [0..255]
    b: u8,                     // RGB blue component [0..255]
    active_component: RgbComponent,  // Active RGB slider (rgb_sliders mode)
    block: ?Block,             // Optional border block
    style: Style,              // Default cell style
    cursor_style: Style,       // Cursor highlight style

    /// Initialize a new ColorPicker with the given mode
    pub fn init(mode: ColorPickerMode) ColorPicker {
        return .{
            .mode = mode,
            .cursor_x = 0,
            .cursor_y = 0,
            .r = 0,
            .g = 0,
            .b = 0,
            .active_component = .r,
            .block = null,
            .style = .{},
            .cursor_style = .{},
        };
    }

    /// Set mode (builder pattern)
    pub fn withMode(self: ColorPicker, mode: ColorPickerMode) ColorPicker {
        var result = self;
        result.mode = mode;
        return result;
    }

    /// Set border block (builder pattern)
    pub fn withBlock(self: ColorPicker, block: Block) ColorPicker {
        var result = self;
        result.block = block;
        return result;
    }

    /// Set default cell style (builder pattern)
    pub fn withStyle(self: ColorPicker, style: Style) ColorPicker {
        var result = self;
        result.style = style;
        return result;
    }

    /// Set cursor highlight style (builder pattern)
    pub fn withCursorStyle(self: ColorPicker, style: Style) ColorPicker {
        var result = self;
        result.cursor_style = style;
        return result;
    }

    /// Set color from an existing Color (builder pattern)
    /// - For indexed colors: sets cursor position in palette
    /// - For RGB colors: sets r/g/b and switches to rgb_sliders mode
    pub fn withColor(self: ColorPicker, color: Color) ColorPicker {
        var result = self;
        switch (color) {
            .indexed => |idx| {
                result.cursor_x = @intCast(idx % 16);
                result.cursor_y = @intCast(idx / 16);
            },
            .rgb => |rgb| {
                result.r = rgb.r;
                result.g = rgb.g;
                result.b = rgb.b;
                result.mode = .rgb_sliders;
            },
            else => {},
        }
        return result;
    }

    // ========================================================================
    // Palette Navigation
    // ========================================================================

    /// Move cursor right (palette modes)
    pub fn moveRight(self: *ColorPicker) void {
        const max_x: u8 = if (self.mode == .palette_16) 7 else 15;
        if (self.cursor_x < max_x) {
            self.cursor_x += 1;
        }
    }

    /// Move cursor left (palette modes)
    pub fn moveLeft(self: *ColorPicker) void {
        if (self.cursor_x > 0) {
            self.cursor_x -= 1;
        }
    }

    /// Move cursor down (palette modes)
    pub fn moveDown(self: *ColorPicker) void {
        const max_y: u8 = if (self.mode == .palette_16) 1 else 15;
        if (self.cursor_y < max_y) {
            self.cursor_y += 1;
        }
    }

    /// Move cursor up (palette modes)
    pub fn moveUp(self: *ColorPicker) void {
        if (self.cursor_y > 0) {
            self.cursor_y -= 1;
        }
    }

    // ========================================================================
    // RGB Slider Navigation
    // ========================================================================

    /// Cycle to next RGB component: r → g → b → r
    pub fn nextComponent(self: *ColorPicker) void {
        self.active_component = switch (self.active_component) {
            .r => .g,
            .g => .b,
            .b => .r,
        };
    }

    /// Cycle to previous RGB component: r → b → g → r
    pub fn prevComponent(self: *ColorPicker) void {
        self.active_component = switch (self.active_component) {
            .r => .b,
            .b => .g,
            .g => .r,
        };
    }

    /// Increment active RGB component by amount (clamped to 255)
    pub fn incrementComponent(self: *ColorPicker, amount: u8) void {
        const new_val = switch (self.active_component) {
            .r => std.math.add(u8, self.r, amount) catch 255,
            .g => std.math.add(u8, self.g, amount) catch 255,
            .b => std.math.add(u8, self.b, amount) catch 255,
        };
        switch (self.active_component) {
            .r => self.r = new_val,
            .g => self.g = new_val,
            .b => self.b = new_val,
        }
    }

    /// Decrement active RGB component by amount (clamped to 0)
    pub fn decrementComponent(self: *ColorPicker, amount: u8) void {
        switch (self.active_component) {
            .r => self.r = if (self.r >= amount) self.r - amount else 0,
            .g => self.g = if (self.g >= amount) self.g - amount else 0,
            .b => self.b = if (self.b >= amount) self.b - amount else 0,
        }
    }

    // ========================================================================
    // Color Access
    // ========================================================================

    /// Get the color at the current cursor position
    pub fn selectedColor(self: ColorPicker) Color {
        return switch (self.mode) {
            .palette_256 => .{ .indexed = self.cursor_y * 16 + self.cursor_x },
            .palette_16 => self.selectedColorPalette16(),
            .rgb_sliders => .{ .rgb = .{ .r = self.r, .g = self.g, .b = self.b } },
        };
    }

    /// Get basic ANSI color from palette_16 cursor position
    fn selectedColorPalette16(self: ColorPicker) Color {
        const index = self.cursor_y * 8 + self.cursor_x;
        return switch (index) {
            0 => Color.black,
            1 => Color.red,
            2 => Color.green,
            3 => Color.yellow,
            4 => Color.blue,
            5 => Color.magenta,
            6 => Color.cyan,
            7 => Color.white,
            8 => Color.bright_black,
            9 => Color.bright_red,
            10 => Color.bright_green,
            11 => Color.bright_yellow,
            12 => Color.bright_blue,
            13 => Color.bright_magenta,
            14 => Color.bright_cyan,
            15 => Color.bright_white,
            else => Color.reset,
        };
    }

    // ========================================================================
    // Rendering
    // ========================================================================

    /// Render the color picker to a buffer
    pub fn render(self: ColorPicker, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }
        if (inner.width == 0 or inner.height == 0) return;

        switch (self.mode) {
            .palette_256 => self.renderPalette256(buf, inner),
            .palette_16 => self.renderPalette16(buf, inner),
            .rgb_sliders => self.renderRgbSliders(buf, inner),
        }
    }

    /// Render 16x16 palette grid. Each swatch is 2 chars wide.
    fn renderPalette256(self: ColorPicker, buf: *Buffer, area: Rect) void {
        var row: u16 = 0;
        while (row < 16 and row < area.height) : (row += 1) {
            var col: u16 = 0;
            while (col < 16) : (col += 1) {
                const bx = area.x + col * 2;
                const by = area.y + row;
                if (bx + 1 >= area.x + area.width or by >= area.y + area.height) break;
                const color_idx: u8 = @intCast(row * 16 + col);
                const is_cursor = col == self.cursor_x and row == self.cursor_y;
                const swatch_style = if (is_cursor)
                    Style{ .bg = .{ .indexed = color_idx }, .fg = self.cursor_style.fg, .bold = self.cursor_style.bold, .underline = self.cursor_style.underline }
                else
                    Style{ .bg = .{ .indexed = color_idx } };
                const cell: @import("../buffer.zig").Cell = .{ .char = ' ', .style = swatch_style };
                buf.set(bx, by, cell);
                buf.set(bx + 1, by, cell);
            }
        }
    }

    /// Render 8x2 palette grid for basic 16 colors. Each swatch is 3 chars wide.
    fn renderPalette16(self: ColorPicker, buf: *Buffer, area: Rect) void {
        const basic_colors = [16]Color{
            Color.black, Color.red, Color.green, Color.yellow,
            Color.blue, Color.magenta, Color.cyan, Color.white,
            Color.bright_black, Color.bright_red, Color.bright_green, Color.bright_yellow,
            Color.bright_blue, Color.bright_magenta, Color.bright_cyan, Color.bright_white,
        };
        var row: u16 = 0;
        while (row < 2 and row < area.height) : (row += 1) {
            var col: u16 = 0;
            while (col < 8) : (col += 1) {
                const bx = area.x + col * 3;
                const by = area.y + row;
                if (bx + 2 >= area.x + area.width or by >= area.y + area.height) break;
                const color_idx = row * 8 + col;
                const bg = basic_colors[color_idx];
                const is_cursor = col == self.cursor_x and row == self.cursor_y;
                const swatch_style = if (is_cursor)
                    Style{ .bg = bg, .bold = self.cursor_style.bold, .underline = self.cursor_style.underline }
                else
                    Style{ .bg = bg };
                const cell: @import("../buffer.zig").Cell = .{ .char = ' ', .style = swatch_style };
                buf.set(bx, by, cell);
                buf.set(bx + 1, by, cell);
                buf.set(bx + 2, by, cell);
            }
        }
    }

    /// Render three RGB slider bars with labels.
    fn renderRgbSliders(self: ColorPicker, buf: *Buffer, area: Rect) void {
        if (area.width < 10) return;

        const components = [3]struct { label: u8, value: u8, comp: RgbComponent }{
            .{ .label = 'R', .value = self.r, .comp = .r },
            .{ .label = 'G', .value = self.g, .comp = .g },
            .{ .label = 'B', .value = self.b, .comp = .b },
        };

        // Track width = area.width - 3 (label) - 1 (space) - 4 (value " 255")
        const track_w: u16 = if (area.width > 8) area.width - 8 else 1;

        var i: u16 = 0;
        for (components) |comp| {
            if (i >= area.height) break;
            const by = area.y + i;
            const is_active = comp.comp == self.active_component;
            const label_style = if (is_active) self.cursor_style else self.style;

            // Label: "R: "
            const label_buf = [3]u8{ comp.label, ':', ' ' };
            buf.setString(area.x, by, &label_buf, label_style);

            // Slider bar
            const filled: u16 = @intCast((@as(u32, comp.value) * track_w) / 255);
            var bx: u16 = area.x + 3;
            const bar_end = area.x + 3 + track_w;
            while (bx < bar_end and bx < area.x + area.width) : (bx += 1) {
                const pos_in_bar = bx - (area.x + 3);
                const bar_char: u21 = if (pos_in_bar < filled) '█' else '░';
                const cell: @import("../buffer.zig").Cell = .{ .char = bar_char, .style = self.style };
                buf.set(bx, by, cell);
            }

            // Value label: " 255"
            var val_str: [4]u8 = undefined;
            const val_slice = std.fmt.bufPrint(&val_str, "{d:>3} ", .{comp.value}) catch " ?? ";
            const vx = area.x + 3 + track_w;
            if (vx < area.x + area.width) {
                buf.setString(vx, by, val_slice, self.style);
            }

            i += 1;
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

test "ColorPicker.init default palette_256" {
    const cp = ColorPicker.init(.palette_256);
    try testing.expectEqual(ColorPickerMode.palette_256, cp.mode);
    try testing.expectEqual(@as(u8, 0), cp.cursor_x);
    try testing.expectEqual(@as(u8, 0), cp.cursor_y);
}

test "ColorPicker.selectedColor at (0,0) returns indexed 0" {
    const cp = ColorPicker.init(.palette_256);
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .indexed = 0 }, color);
}
