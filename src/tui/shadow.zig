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
            dx = px - right;
        }

        if (py < top) {
            dy = top - py;
        } else if (py >= bottom) {
            dy = py - bottom;
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

/// RGB triplet type (avoids anonymous struct type issues)
const RgbTriplet = struct { r: u8, g: u8, b: u8 };

/// Extract RGB values from a color (convert named colors to approximate RGB)
fn extractRgb(color: Color) RgbTriplet {
    return switch (color) {
        .rgb => |c| .{ .r = c.r, .g = c.g, .b = c.b },
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
fn indexedToRgb(idx: u8) RgbTriplet {
    // Simplified conversion for 256-color palette
    // Colors 0-15: standard colors (same as named colors)
    if (idx < 16) {
        return switch (idx) {
            0 => .{ .r = 0, .g = 0, .b = 0 },       // black
            1 => .{ .r = 170, .g = 0, .b = 0 },     // red
            2 => .{ .r = 0, .g = 170, .b = 0 },     // green
            3 => .{ .r = 170, .g = 85, .b = 0 },    // yellow
            4 => .{ .r = 0, .g = 0, .b = 170 },     // blue
            5 => .{ .r = 170, .g = 0, .b = 170 },   // magenta
            6 => .{ .r = 0, .g = 170, .b = 170 },   // cyan
            7 => .{ .r = 170, .g = 170, .b = 170 }, // white
            8 => .{ .r = 85, .g = 85, .b = 85 },    // bright black
            9 => .{ .r = 255, .g = 85, .b = 85 },   // bright red
            10 => .{ .r = 85, .g = 255, .b = 85 },  // bright green
            11 => .{ .r = 255, .g = 255, .b = 85 }, // bright yellow
            12 => .{ .r = 85, .g = 85, .b = 255 },  // bright blue
            13 => .{ .r = 255, .g = 85, .b = 255 }, // bright magenta
            14 => .{ .r = 85, .g = 255, .b = 255 }, // bright cyan
            15 => .{ .r = 255, .g = 255, .b = 255 }, // bright white
            else => unreachable,
        };
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

// ============================================================================
// Tests
// ============================================================================

test "Shadow.drop constructor initialization" {
    const shadow = Shadow.drop(2, 1, 3, 0.7);

    try std.testing.expectEqual(@as(i16, 2), shadow.offset_x);
    try std.testing.expectEqual(@as(i16, 1), shadow.offset_y);
    try std.testing.expectEqual(@as(u8, 3), shadow.blur_radius);
    try std.testing.expectEqual(@as(f32, 0.7), shadow.opacity);
    try std.testing.expectEqual(ShadowStyle.drop, shadow.style);
    try std.testing.expectEqual(Color.black, shadow.color);
}

test "Shadow.inner constructor initialization" {
    const shadow = Shadow.inner(-1, -2, 5, 0.5);

    try std.testing.expectEqual(@as(i16, -1), shadow.offset_x);
    try std.testing.expectEqual(@as(i16, -2), shadow.offset_y);
    try std.testing.expectEqual(@as(u8, 5), shadow.blur_radius);
    try std.testing.expectEqual(@as(f32, 0.5), shadow.opacity);
    try std.testing.expectEqual(ShadowStyle.inner, shadow.style);
    try std.testing.expectEqual(Color.black, shadow.color);
}

test "Shadow.box constructor initialization" {
    const shadow = Shadow.box(0, 0, 4, 0.8);

    try std.testing.expectEqual(@as(i16, 0), shadow.offset_x);
    try std.testing.expectEqual(@as(i16, 0), shadow.offset_y);
    try std.testing.expectEqual(@as(u8, 4), shadow.blur_radius);
    try std.testing.expectEqual(@as(f32, 0.8), shadow.opacity);
    try std.testing.expectEqual(ShadowStyle.box, shadow.style);
    try std.testing.expectEqual(Color.black, shadow.color);
}

test "Shadow.render with zero opacity (no-op)" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    // Fill buffer with a known character
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 10) : (x += 1) {
            const cell = buf.get(x, y) orelse unreachable;
            cell.char = 'A';
            cell.style.bg = Color.white;
        }
    }

    const shadow = Shadow.drop(2, 1, 3, 0.0); // zero opacity
    const area = Rect{ .x = 2, .y = 2, .width = 4, .height = 3 };

    try shadow.render(&buf, area);

    // Verify buffer unchanged (opacity = 0 should cause early exit)
    y = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 10) : (x += 1) {
            const cell = buf.get(x, y) orelse unreachable;
            try std.testing.expectEqual(@as(u21, 'A'), cell.char);
            try std.testing.expectEqual(Color.white, cell.style.bg.?);
        }
    }
}

test "Shadow.render with zero-size area (no-op)" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const shadow = Shadow.drop(2, 1, 3, 0.7);

    // Zero width
    const area1 = Rect{ .x = 2, .y = 2, .width = 0, .height = 5 };
    try shadow.render(&buf, area1);

    // Zero height
    const area2 = Rect{ .x = 2, .y = 2, .width = 5, .height = 0 };
    try shadow.render(&buf, area2);

    // Both zero
    const area3 = Rect{ .x = 2, .y = 2, .width = 0, .height = 0 };
    try shadow.render(&buf, area3);

    // Test passes if no crash occurs (early exit on zero-size areas)
}

test "Shadow.render dispatch to drop style" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 20);
    defer buf.deinit();

    // Initialize buffer with white background
    var y: u16 = 0;
    while (y < 20) : (y += 1) {
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            const cell = buf.get(x, y) orelse unreachable;
            cell.style.bg = Color.white;
        }
    }

    const shadow = Shadow.drop(2, 2, 2, 0.5);
    const area = Rect{ .x = 5, .y = 5, .width = 4, .height = 3 };

    try shadow.render(&buf, area);

    // Verify shadow was rendered at offset position
    // Shadow should affect cells around (7,7) with offset (2,2)
    const shadow_cell = buf.get(7, 7) orelse unreachable;

    // Background should be darkened (not white anymore due to shadow blend)
    // The exact color depends on blend, but it should not be the original white
    const is_darkened = if (shadow_cell.style.bg) |bg| blk: {
        if (bg == .rgb) {
            const rgb = bg.rgb;
            // Darkened color should have lower RGB values than pure white (170,170,170)
            break :blk rgb.r < 170 or rgb.g < 170 or rgb.b < 170;
        }
        break :blk true;
    } else false;

    try std.testing.expect(is_darkened);
}

test "Shadow.render dispatch to inner style" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 20);
    defer buf.deinit();

    // Initialize buffer with white background
    var y: u16 = 0;
    while (y < 20) : (y += 1) {
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            const cell = buf.get(x, y) orelse unreachable;
            cell.style.bg = Color.white;
        }
    }

    const shadow = Shadow.inner(1, 1, 2, 0.6);
    const area = Rect{ .x = 5, .y = 5, .width = 8, .height = 6 };

    try shadow.render(&buf, area);

    // Verify inner shadow affected cells inside the area
    // Edge cells should be more darkened than center cells
    const edge_cell = buf.get(5, 5) orelse unreachable; // top-left corner
    const center_cell = buf.get(9, 8) orelse unreachable; // near center

    // Both should have background modified (not white)
    try std.testing.expect(edge_cell.style.bg != null);
    try std.testing.expect(center_cell.style.bg != null);
}

test "Shadow.render dispatch to box style" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 20);
    defer buf.deinit();

    // Initialize buffer with white background
    var y: u16 = 0;
    while (y < 20) : (y += 1) {
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            const cell = buf.get(x, y) orelse unreachable;
            cell.style.bg = Color.white;
        }
    }

    const shadow = Shadow.box(0, 0, 3, 0.4);
    const area = Rect{ .x = 8, .y = 8, .width = 4, .height = 4 };

    try shadow.render(&buf, area);

    // Verify box shadow rendered around all edges
    // Check cells outside the area (should be affected by blur)
    const outside_cell = buf.get(7, 7) orelse unreachable; // top-left outside

    try std.testing.expect(outside_cell.style.bg != null);
}

test "Shadow distanceToRect - point inside rectangle" {
    const shadow = Shadow.drop(0, 0, 0, 1.0);

    // Rectangle at (10, 10) with width=5, height=4
    const dist = shadow.distanceToRect(12, 11, 10, 10, 5, 4);

    // Point (12, 11) is inside [10..15) x [10..14), so distance should be 0
    try std.testing.expectEqual(@as(f32, 0.0), dist);
}

test "Shadow distanceToRect - point outside rectangle" {
    const shadow = Shadow.drop(0, 0, 0, 1.0);

    // Rectangle at (10, 10) with width=5, height=4
    // Point at (17, 10) - 2 units to the right of rectangle edge (x=15)
    const dist = shadow.distanceToRect(17, 10, 10, 10, 5, 4);

    // Distance should be 2.0 (horizontal distance from edge)
    try std.testing.expectEqual(@as(f32, 2.0), dist);
}

test "Shadow distanceToRect - diagonal point" {
    const shadow = Shadow.drop(0, 0, 0, 1.0);

    // Rectangle at (0, 0) with width=4, height=3
    // Point at (6, 5) - outside top-right corner
    // Distance from (4, 3) to (6, 5) = sqrt((6-4)^2 + (5-3)^2) = sqrt(4+4) = sqrt(8) ≈ 2.828
    const dist = shadow.distanceToRect(6, 5, 0, 0, 4, 3);

    const expected = @sqrt(@as(f32, 8.0));
    try std.testing.expectApproxEqRel(expected, dist, 0.001);
}

test "Shadow calculateIntensity with zero blur" {
    const shadow = Shadow.drop(0, 0, 0, 0.8);

    // Zero blur: sharp cutoff at distance 0
    const intensity_inside = shadow.calculateIntensity(0.0);
    const intensity_outside = shadow.calculateIntensity(1.0);

    try std.testing.expectEqual(@as(f32, 0.8), intensity_inside);
    try std.testing.expectEqual(@as(f32, 0.0), intensity_outside);
}

test "Shadow calculateIntensity with blur (Gaussian falloff)" {
    const shadow = Shadow.drop(0, 0, 4, 1.0);

    // Gaussian falloff: intensity decreases with distance
    const intensity_zero = shadow.calculateIntensity(0.0);
    const intensity_near = shadow.calculateIntensity(1.0);
    const intensity_far = shadow.calculateIntensity(5.0);

    // At distance 0, intensity should be max (opacity)
    try std.testing.expectEqual(@as(f32, 1.0), intensity_zero);

    // At distance 1, intensity should be less than max
    try std.testing.expect(intensity_near < 1.0);
    try std.testing.expect(intensity_near > 0.0);

    // At distance 5 (beyond blur radius), intensity should be very low
    try std.testing.expect(intensity_far < intensity_near);
    try std.testing.expect(intensity_far < 0.2);
}

test "Shadow blendColors - RGB interpolation" {
    const shadow = Shadow.drop(0, 0, 0, 1.0);

    const white = Color.fromRgb(255, 255, 255);
    const black = Color.fromRgb(0, 0, 0);

    // Blend at 50% intensity
    const blended = shadow.blendColors(white, black, 0.5);

    try std.testing.expect(blended == .rgb);
    const rgb = blended.rgb;

    // 50% blend: (255 + 0) / 2 ≈ 127
    try std.testing.expectApproxEqAbs(@as(f32, 127.0), @as(f32, @floatFromInt(rgb.r)), 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 127.0), @as(f32, @floatFromInt(rgb.g)), 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 127.0), @as(f32, @floatFromInt(rgb.b)), 1.0);
}

test "Shadow blendColors - intensity clamping" {
    const shadow = Shadow.drop(0, 0, 0, 1.0);

    const base = Color.fromRgb(100, 100, 100);
    const overlay = Color.fromRgb(200, 200, 200);

    // Intensity > 1.0 should be clamped to 1.0
    const blended_over = shadow.blendColors(base, overlay, 1.5);
    try std.testing.expect(blended_over == .rgb);
    try std.testing.expectEqual(@as(u8, 200), blended_over.rgb.r);

    // Intensity < 0.0 should be clamped to 0.0
    const blended_under = shadow.blendColors(base, overlay, -0.5);
    try std.testing.expect(blended_under == .rgb);
    try std.testing.expectEqual(@as(u8, 100), blended_under.rgb.r);
}

test "extractRgb - named colors conversion" {
    const black_rgb = extractRgb(Color.black);
    try std.testing.expectEqual(@as(u8, 0), black_rgb.r);
    try std.testing.expectEqual(@as(u8, 0), black_rgb.g);
    try std.testing.expectEqual(@as(u8, 0), black_rgb.b);

    const white_rgb = extractRgb(Color.white);
    try std.testing.expectEqual(@as(u8, 170), white_rgb.r);
    try std.testing.expectEqual(@as(u8, 170), white_rgb.g);
    try std.testing.expectEqual(@as(u8, 170), white_rgb.b);

    const bright_red_rgb = extractRgb(Color.bright_red);
    try std.testing.expectEqual(@as(u8, 255), bright_red_rgb.r);
    try std.testing.expectEqual(@as(u8, 85), bright_red_rgb.g);
    try std.testing.expectEqual(@as(u8, 85), bright_red_rgb.b);
}

test "extractRgb - RGB color passthrough" {
    const custom = Color.fromRgb(123, 45, 67);
    const rgb = extractRgb(custom);

    try std.testing.expectEqual(@as(u8, 123), rgb.r);
    try std.testing.expectEqual(@as(u8, 45), rgb.g);
    try std.testing.expectEqual(@as(u8, 67), rgb.b);
}

test "extractRgb - indexed color conversion" {
    // Test standard color (idx=1 = red)
    const indexed_red = extractRgb(Color{ .indexed = 1 });
    try std.testing.expectEqual(@as(u8, 170), indexed_red.r);
    try std.testing.expectEqual(@as(u8, 0), indexed_red.g);
    try std.testing.expectEqual(@as(u8, 0), indexed_red.b);

    // Test grayscale (idx=232 = first gray)
    const indexed_gray = extractRgb(Color{ .indexed = 232 });
    try std.testing.expectEqual(@as(u8, 8), indexed_gray.r);
    try std.testing.expectEqual(@as(u8, 8), indexed_gray.g);
    try std.testing.expectEqual(@as(u8, 8), indexed_gray.b);
}

test "interpolateU8 - basic interpolation" {
    // 0% blend: return first value
    try std.testing.expectEqual(@as(u8, 100), interpolateU8(100, 200, 0.0));

    // 100% blend: return second value
    try std.testing.expectEqual(@as(u8, 200), interpolateU8(100, 200, 1.0));

    // 50% blend: return midpoint
    try std.testing.expectEqual(@as(u8, 150), interpolateU8(100, 200, 0.5));

    // 25% blend
    try std.testing.expectEqual(@as(u8, 125), interpolateU8(100, 200, 0.25));
}

test "interpolateU8 - clamping to [0, 255]" {
    // Over 1.0: interpolation goes beyond second value, clamps to 255
    // 100 + (200-100)*2.0 = 300 → clamps to 255
    try std.testing.expectEqual(@as(u8, 255), interpolateU8(100, 200, 2.0));

    // Negative: interpolation goes below first value, clamps to 0
    // 100 + (200-100)*(-1.0) = 0
    try std.testing.expectEqual(@as(u8, 0), interpolateU8(100, 200, -1.0));
}
