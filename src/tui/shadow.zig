//! Shadow Effects System for TUI Widgets
//!
//! Provides drop shadows, inner shadows, and box shadows for enhanced visual depth.
//! Shadows are rendered by darkening buffer cells based on offset, blur radius, and opacity.
//!
//! ## Features
//! - Drop shadow (external shadow with offset)
//! - Inner shadow (internal darkening effect)
//! - Box shadow (uniform glow/shadow on all sides)
//! - Configurable blur radius with Gaussian-like falloff
//! - Opacity control for shadow intensity
//! - Colored shadows (not just black)
//!
//! ## Usage
//! ```zig
//! const shadow = Shadow.drop(2, 1, 3, 0.7);
//! try shadow.render(&buffer, widget_area);
//! ```

const std = @import("std");
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const style_mod = @import("style.zig");
const Color = style_mod.Color;
const Style = style_mod.Style;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;

/// Shadow rendering style
pub const ShadowStyle = enum {
    drop,  // External shadow at offset position
    inner, // Internal shadow (only inside widget area)
    box,   // Shadow on all four sides (like CSS box-shadow)
};

/// Shadow configuration and rendering
pub const Shadow = struct {
    offset_x: i16,
    offset_y: i16,
    blur_radius: u8,
    color: Color,
    opacity: f32,
    style: ShadowStyle,

    /// Convenience constructor for drop shadow
    pub fn drop(offset_x: i16, offset_y: i16, blur: u8, opacity: f32) Shadow {
        return .{
            .offset_x = offset_x,
            .offset_y = offset_y,
            .blur_radius = blur,
            .color = Color.black,
            .opacity = opacity,
            .style = .drop,
        };
    }

    /// Convenience constructor for inner shadow
    pub fn inner(offset_x: i16, offset_y: i16, blur: u8, opacity: f32) Shadow {
        return .{
            .offset_x = offset_x,
            .offset_y = offset_y,
            .blur_radius = blur,
            .color = Color.black,
            .opacity = opacity,
            .style = .inner,
        };
    }

    /// Convenience constructor for box shadow
    pub fn box(offset_x: i16, offset_y: i16, blur: u8, opacity: f32) Shadow {
        return .{
            .offset_x = offset_x,
            .offset_y = offset_y,
            .blur_radius = blur,
            .color = Color.black,
            .opacity = opacity,
            .style = .box,
        };
    }

    /// Render shadow effect to buffer
    pub fn render(self: Shadow, buf: *Buffer, area: Rect) !void {
        // Early exit for zero opacity (invisible shadow)
        if (self.opacity <= 0.0) return;

        // Early exit for zero-size area
        if (area.width == 0 or area.height == 0) return;

        switch (self.style) {
            .drop => try self.renderDrop(buf, area),
            .inner => try self.renderInner(buf, area),
            .box => try self.renderBox(buf, area),
        }
    }

    /// Render drop shadow (external shadow at offset)
    fn renderDrop(self: Shadow, buf: *Buffer, area: Rect) !void {
        // Calculate shadow area (offset from widget area)
        const shadow_x = @as(i32, area.x) + self.offset_x;
        const shadow_y = @as(i32, area.y) + self.offset_y;

        // Early exit if zero offset and zero blur
        if (self.offset_x == 0 and self.offset_y == 0 and self.blur_radius == 0) {
            // Render a subtle shadow at the widget position
            try self.renderShadowRect(buf, area, 0, 0);
            return;
        }

        // Render shadow rectangle at offset position
        const blur_i32: i32 = @intCast(self.blur_radius);
        const min_x = shadow_x - blur_i32;
        const min_y = shadow_y - blur_i32;
        const max_x = shadow_x + @as(i32, area.width) + blur_i32;
        const max_y = shadow_y + @as(i32, area.height) + blur_i32;

        // Iterate over shadow area with blur
        var y: i32 = min_y;
        while (y < max_y) : (y += 1) {
            var x: i32 = min_x;
            while (x < max_x) : (x += 1) {
                // Check bounds
                if (x < 0 or y < 0 or x >= buf.width or y >= buf.height) continue;

                const ux: u16 = @intCast(x);
                const uy: u16 = @intCast(y);

                // Calculate distance from shadow core area
                const distance = self.distanceToRect(x, y, shadow_x, shadow_y, area.width, area.height);

                // Calculate shadow intensity based on distance and blur
                const intensity = self.calculateIntensity(distance);
                if (intensity <= 0.0) continue;

                // Apply shadow to cell
                self.applyShadowToCell(buf, ux, uy, intensity);
            }
        }
    }

    /// Render inner shadow (only inside widget area)
    fn renderInner(self: Shadow, buf: *Buffer, area: Rect) !void {
        // Inner shadow only affects cells inside the widget area
        var y: u16 = 0;
        while (y < area.height) : (y += 1) {
            var x: u16 = 0;
            while (x < area.width) : (x += 1) {
                const cell_x = area.x + x;
                const cell_y = area.y + y;

                // Check buffer bounds
                if (cell_x >= buf.width or cell_y >= buf.height) continue;

                // Calculate distance from edge (inverted for inner shadow)
                // Inner shadow is strongest near edges, weakest at center
                const dist_from_left = x;
                const dist_from_right = area.width - x - 1;
                const dist_from_top = y;
                const dist_from_bottom = area.height - y - 1;

                const min_dist = @min(@min(dist_from_left, dist_from_right), @min(dist_from_top, dist_from_bottom));

                // Apply offset influence (shadow direction)
                const offset_influence = self.calculateInnerShadowInfluence(x, y, area.width, area.height);

                // Shadow is strongest at edges (distance 0), fades inward
                const distance_f: f32 = @floatFromInt(min_dist);
                const intensity = self.calculateIntensity(distance_f) * offset_influence;

                if (intensity <= 0.0) continue;

                self.applyShadowToCell(buf, cell_x, cell_y, intensity);
            }
        }
    }

    /// Render box shadow (uniform effect on all sides)
    fn renderBox(self: Shadow, buf: *Buffer, area: Rect) !void {
        // Box shadow renders around all edges uniformly
        const blur_i32: i32 = @intCast(self.blur_radius);

        const min_x = @as(i32, area.x) + self.offset_x - blur_i32;
        const min_y = @as(i32, area.y) + self.offset_y - blur_i32;
        const max_x = @as(i32, area.x) + @as(i32, area.width) + self.offset_x + blur_i32;
        const max_y = @as(i32, area.y) + @as(i32, area.height) + self.offset_y + blur_i32;

        var y: i32 = min_y;
        while (y < max_y) : (y += 1) {
            var x: i32 = min_x;
            while (x < max_x) : (x += 1) {
                // Check bounds
                if (x < 0 or y < 0 or x >= buf.width or y >= buf.height) continue;

                const ux: u16 = @intCast(x);
                const uy: u16 = @intCast(y);

                // Calculate distance from widget edges (for box shadow)
                const widget_x = @as(i32, area.x) + self.offset_x;
                const widget_y = @as(i32, area.y) + self.offset_y;
                const distance = self.distanceToRect(x, y, widget_x, widget_y, area.width, area.height);

                const intensity = self.calculateIntensity(distance);
                if (intensity <= 0.0) continue;

                self.applyShadowToCell(buf, ux, uy, intensity);
            }
        }
    }

    /// Calculate distance from point to rectangle edge
    fn distanceToRect(self: Shadow, px: i32, py: i32, rect_x: i32, rect_y: i32, rect_w: u16, rect_h: u16) f32 {
        _ = self;

        // Rectangle boundaries
        const left = rect_x;
        const right = rect_x + @as(i32, rect_w);
        const top = rect_y;
        const bottom = rect_y + @as(i32, rect_h);

        // Point is inside rectangle: distance is 0
        if (px >= left and px < right and py >= top and py < bottom) {
            return 0.0;
        }

        // Calculate distance to nearest edge
        var dx: i32 = 0;
        var dy: i32 = 0;

        if (px < left) {
            dx = left - px;
        } else if (px >= right) {
            dx = px - right + 1;
        }

        if (py < top) {
            dy = top - py;
        } else if (py >= bottom) {
            dy = py - bottom + 1;
        }

        // Euclidean distance
        const dx_f: f32 = @floatFromInt(dx);
        const dy_f: f32 = @floatFromInt(dy);
        return @sqrt(dx_f * dx_f + dy_f * dy_f);
    }

    /// Calculate shadow intensity based on distance (Gaussian-like falloff)
    fn calculateIntensity(self: Shadow, distance: f32) f32 {
        // Zero blur: sharp cutoff at distance 0
        if (self.blur_radius == 0) {
            return if (distance <= 0.0) self.opacity else 0.0;
        }

        // Gaussian-like falloff: intensity = opacity * exp(-(distance^2) / (2 * sigma^2))
        // For simplicity, use sigma = blur_radius / 2
        const blur_f: f32 = @floatFromInt(self.blur_radius);
        const sigma = blur_f / 2.0;
        const sigma_sq = sigma * sigma;

        // Gaussian formula
        const distance_sq = distance * distance;
        const exponent = -distance_sq / (2.0 * sigma_sq);
        const gaussian = @exp(exponent);

        return self.opacity * gaussian;
    }

    /// Calculate inner shadow influence based on offset direction
    fn calculateInnerShadowInfluence(self: Shadow, x: u16, y: u16, width: u16, height: u16) f32 {
        // Inner shadow is influenced by offset direction
        // Positive offset_x: shadow stronger on left edge
        // Negative offset_x: shadow stronger on right edge
        // Similar for offset_y

        const center_x: f32 = @as(f32, @floatFromInt(width)) / 2.0;
        const center_y: f32 = @as(f32, @floatFromInt(height)) / 2.0;

        const x_f: f32 = @floatFromInt(x);
        const y_f: f32 = @floatFromInt(y);

        // Calculate influence based on offset direction
        var influence: f32 = 1.0;

        // X direction influence
        if (self.offset_x != 0) {
            const offset_x_f: f32 = @floatFromInt(self.offset_x);
            const x_normalized = (x_f - center_x) / center_x; // -1 to 1
            const x_influence = 1.0 - (x_normalized * offset_x_f / @abs(offset_x_f)) * 0.5;
            influence *= @max(0.0, @min(1.0, x_influence));
        }

        // Y direction influence
        if (self.offset_y != 0) {
            const offset_y_f: f32 = @floatFromInt(self.offset_y);
            const y_normalized = (y_f - center_y) / center_y; // -1 to 1
            const y_influence = 1.0 - (y_normalized * offset_y_f / @abs(offset_y_f)) * 0.5;
            influence *= @max(0.0, @min(1.0, y_influence));
        }

        return influence;
    }

    /// Apply shadow effect to a specific cell
    fn applyShadowToCell(self: Shadow, buf: *Buffer, x: u16, y: u16, intensity: f32) void {
        const cell = buf.get(x, y) orelse return;

        // Get current background color (or use reset as default)
        const current_bg = cell.style.bg orelse Color.reset;

        // Darken the background by blending with shadow color
        const darkened = self.blendColors(current_bg, self.color, intensity);

        // Apply to cell background
        cell.style.bg = darkened;
    }

    /// Blend two colors based on intensity (opacity)
    fn blendColors(self: Shadow, base: Color, shadow: Color, intensity: f32) Color {
        _ = self;

        // Clamp intensity to [0, 1]
        const t = @max(0.0, @min(1.0, intensity));

        // Extract RGB from colors (only works for RGB colors)
        const base_rgb = extractRgb(base);
        const shadow_rgb = extractRgb(shadow);

        // Interpolate between base and shadow
        const r = interpolateU8(base_rgb.r, shadow_rgb.r, t);
        const g = interpolateU8(base_rgb.g, shadow_rgb.g, t);
        const b = interpolateU8(base_rgb.b, shadow_rgb.b, t);

        return Color.fromRgb(r, g, b);
    }

    /// Render shadow for a rectangular area (helper for drop shadow)
    fn renderShadowRect(self: Shadow, buf: *Buffer, rect: Rect, offset_x: i32, offset_y: i32) !void {
        _ = offset_x;
        _ = offset_y;

        var y: u16 = 0;
        while (y < rect.height) : (y += 1) {
            var x: u16 = 0;
            while (x < rect.width) : (x += 1) {
                const cell_x = rect.x + x;
                const cell_y = rect.y + y;

                if (cell_x >= buf.width or cell_y >= buf.height) continue;

                self.applyShadowToCell(buf, cell_x, cell_y, self.opacity);
            }
        }
    }
};

/// Extract RGB values from a color (convert named colors to approximate RGB)
fn extractRgb(color: Color) struct { r: u8, g: u8, b: u8 } {
    return switch (color) {
        .rgb => |c| c,
        .reset => .{ .r = 0, .g = 0, .b = 0 },
        .black => .{ .r = 0, .g = 0, .b = 0 },
        .red => .{ .r = 170, .g = 0, .b = 0 },
        .green => .{ .r = 0, .g = 170, .b = 0 },
        .yellow => .{ .r = 170, .g = 85, .b = 0 },
        .blue => .{ .r = 0, .g = 0, .b = 170 },
        .magenta => .{ .r = 170, .g = 0, .b = 170 },
        .cyan => .{ .r = 0, .g = 170, .b = 170 },
        .white => .{ .r = 170, .g = 170, .b = 170 },
        .bright_black => .{ .r = 85, .g = 85, .b = 85 },
        .bright_red => .{ .r = 255, .g = 85, .b = 85 },
        .bright_green => .{ .r = 85, .g = 255, .b = 85 },
        .bright_yellow => .{ .r = 255, .g = 255, .b = 85 },
        .bright_blue => .{ .r = 85, .g = 85, .b = 255 },
        .bright_magenta => .{ .r = 255, .g = 85, .b = 255 },
        .bright_cyan => .{ .r = 85, .g = 255, .b = 255 },
        .bright_white => .{ .r = 255, .g = 255, .b = 255 },
        .indexed => |idx| indexedToRgb(idx),
    };
}

/// Convert indexed color to approximate RGB
fn indexedToRgb(idx: u8) struct { r: u8, g: u8, b: u8 } {
    // Simplified conversion for 256-color palette
    // Colors 0-15: standard colors (same as named colors)
    if (idx < 16) {
        const standard = [_]struct { r: u8, g: u8, b: u8 }{
            .{ .r = 0, .g = 0, .b = 0 },       // 0: black
            .{ .r = 170, .g = 0, .b = 0 },     // 1: red
            .{ .r = 0, .g = 170, .b = 0 },     // 2: green
            .{ .r = 170, .g = 85, .b = 0 },    // 3: yellow
            .{ .r = 0, .g = 0, .b = 170 },     // 4: blue
            .{ .r = 170, .g = 0, .b = 170 },   // 5: magenta
            .{ .r = 0, .g = 170, .b = 170 },   // 6: cyan
            .{ .r = 170, .g = 170, .b = 170 }, // 7: white
            .{ .r = 85, .g = 85, .b = 85 },    // 8: bright black
            .{ .r = 255, .g = 85, .b = 85 },   // 9: bright red
            .{ .r = 85, .g = 255, .b = 85 },   // 10: bright green
            .{ .r = 255, .g = 255, .b = 85 },  // 11: bright yellow
            .{ .r = 85, .g = 85, .b = 255 },   // 12: bright blue
            .{ .r = 255, .g = 85, .b = 255 },  // 13: bright magenta
            .{ .r = 85, .g = 255, .b = 255 },  // 14: bright cyan
            .{ .r = 255, .g = 255, .b = 255 }, // 15: bright white
        };
        return standard[idx];
    }

    // Colors 16-231: 6x6x6 RGB cube
    if (idx >= 16 and idx < 232) {
        const cube_idx = idx - 16;
        const r_idx = cube_idx / 36;
        const g_idx = (cube_idx % 36) / 6;
        const b_idx = cube_idx % 6;

        const values = [_]u8{ 0, 95, 135, 175, 215, 255 };
        return .{
            .r = values[r_idx],
            .g = values[g_idx],
            .b = values[b_idx],
        };
    }

    // Colors 232-255: grayscale ramp
    const gray_value = 8 + (idx - 232) * 10;
    return .{ .r = gray_value, .g = gray_value, .b = gray_value };
}

/// Interpolate between two u8 values
fn interpolateU8(a: u8, b: u8, t: f32) u8 {
    const a_f: f32 = @floatFromInt(a);
    const b_f: f32 = @floatFromInt(b);
    const result = a_f + (b_f - a_f) * t;
    return @intFromFloat(@max(0.0, @min(255.0, result)));
}
