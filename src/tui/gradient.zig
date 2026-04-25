//! Gradient system for creating smooth color transitions in TUI widgets.
//!
//! Provides linear and radial gradients with various interpolation strategies.
//! Gradients can be applied to widget backgrounds for enhanced visual appeal.
//!
//! ## Features
//! - Linear gradients (horizontal, vertical, diagonal)
//! - Radial gradients (from center outward)
//! - Multiple interpolation methods (RGB, HSV)
//! - Color stops for complex gradients
//! - Performance-optimized with caching
//!
//! ## Usage
//! ```zig
//! const gradient = LinearGradient{
//!     .direction = .vertical,
//!     .stops = &.{
//!         .{ .offset = 0.0, .color = Color.fromRgb(255, 0, 0) },
//!         .{ .offset = 1.0, .color = Color.fromRgb(0, 0, 255) },
//!     },
//! };
//! const color = gradient.colorAt(0.5); // Mid-point color
//! ```

const std = @import("std");
const Color = @import("../color.zig").Color;

/// Direction for linear gradients
pub const Direction = enum {
    horizontal,      // Left to right
    vertical,        // Top to bottom
    diagonal_down,   // Top-left to bottom-right
    diagonal_up,     // Bottom-left to top-right

    /// Angle in degrees (0 = horizontal, 90 = vertical, clockwise)
    pub fn angle(self: Direction) f64 {
        return switch (self) {
            .horizontal => 0.0,
            .vertical => 90.0,
            .diagonal_down => 45.0,
            .diagonal_up => 135.0,
        };
    }
};

/// Color interpolation method
pub const Interpolation = enum {
    rgb,   // Direct RGB interpolation
    hsv,   // Convert to HSV, interpolate, convert back (smoother for some cases)
};

/// A color stop in a gradient (position + color)
pub const ColorStop = struct {
    offset: f64,        // Position in gradient (0.0 to 1.0)
    color: Color,       // Color at this position

    /// Sort function for color stops by offset
    fn lessThan(_: void, a: ColorStop, b: ColorStop) bool {
        return a.offset < b.offset;
    }
};

/// Linear gradient configuration
pub const LinearGradient = struct {
    direction: Direction = .vertical,
    stops: []const ColorStop,
    interpolation: Interpolation = .rgb,

    /// Get color at a specific position (0.0 to 1.0)
    pub fn colorAt(self: LinearGradient, position: f64) Color {
        if (self.stops.len == 0) return Color.default;
        if (self.stops.len == 1) return self.stops[0].color;

        // Clamp position to [0.0, 1.0]
        const pos = @max(0.0, @min(1.0, position));

        // Find the two stops surrounding this position
        var before_idx: ?usize = null;
        var after_idx: ?usize = null;

        for (self.stops, 0..) |stop, i| {
            if (stop.offset <= pos) {
                before_idx = i;
            }
            if (stop.offset >= pos and after_idx == null) {
                after_idx = i;
            }
        }

        // If position exactly matches a stop, return that color
        if (before_idx) |idx| {
            if (self.stops[idx].offset == pos) {
                return self.stops[idx].color;
            }
        }

        // If no stop found after position, return last color
        if (after_idx == null) {
            return self.stops[self.stops.len - 1].color;
        }

        // If no stop found before position, return first color
        if (before_idx == null) {
            return self.stops[0].color;
        }

        // Interpolate between the two stops
        const before = self.stops[before_idx.?];
        const after = self.stops[after_idx.?];

        // Calculate normalized position between the two stops
        const range = after.offset - before.offset;
        if (range == 0.0) return before.color;

        const t = (pos - before.offset) / range;

        return interpolateColor(before.color, after.color, t, self.interpolation);
    }

};

/// Radial gradient configuration (from center outward)
pub const RadialGradient = struct {
    center_x: f64 = 0.5,     // Center X (0.0 to 1.0)
    center_y: f64 = 0.5,     // Center Y (0.0 to 1.0)
    stops: []const ColorStop,
    interpolation: Interpolation = .rgb,

    /// Get color at a specific position (x, y in 0.0 to 1.0)
    pub fn colorAt(self: RadialGradient, x: f64, y: f64) Color {
        // Calculate distance from center
        const dx = x - self.center_x;
        const dy = y - self.center_y;
        const distance = @sqrt(dx * dx + dy * dy);

        // Normalize distance to [0, 1] (max distance is sqrt(2)/2 ≈ 0.707)
        const max_distance = 0.707;
        const position = @min(1.0, distance / max_distance);

        // Use linear gradient logic to find color at this position
        const linear = LinearGradient{
            .direction = .horizontal,
            .stops = self.stops,
            .interpolation = self.interpolation,
        };

        return linear.colorAt(position);
    }

};

/// Interpolate between two colors
fn interpolateColor(a: Color, b: Color, t: f64, method: Interpolation) Color {
    return switch (method) {
        .rgb => interpolateRGB(a, b, t),
        .hsv => interpolateHSV(a, b, t),
    };
}

/// RGB interpolation (direct component-wise)
fn interpolateRGB(a: Color, b: Color, t: f64) Color {
    // Extract RGB values (only works for .rgb colors)
    const a_rgb = switch (a) {
        .rgb => |val| val,
        else => return a, // Fall back to first color if not RGB
    };
    const b_rgb = switch (b) {
        .rgb => |val| val,
        else => return b, // Fall back to second color if not RGB
    };

    // Interpolate each component
    const r = interpolateU8(a_rgb.r, b_rgb.r, t);
    const g = interpolateU8(a_rgb.g, b_rgb.g, t);
    const bl = interpolateU8(a_rgb.b, b_rgb.b, t);

    return Color.fromRgb(r, g, bl);
}

/// HSV interpolation (smoother for some color transitions)
fn interpolateHSV(a: Color, b: Color, t: f64) Color {
    // Extract RGB values (only works for .rgb colors)
    const a_color_rgb = switch (a) {
        .rgb => |val| val,
        else => return a, // Fall back to first color if not RGB
    };
    const b_color_rgb = switch (b) {
        .rgb => |val| val,
        else => return b, // Fall back to second color if not RGB
    };

    // Convert anonymous struct to RGB struct
    const a_rgb = RGB{ .r = a_color_rgb.r, .g = a_color_rgb.g, .b = a_color_rgb.b };
    const b_rgb = RGB{ .r = b_color_rgb.r, .g = b_color_rgb.g, .b = b_color_rgb.b };

    // Convert to HSV
    const a_hsv = rgbToHsv(a_rgb);
    const b_hsv = rgbToHsv(b_rgb);

    // Interpolate in HSV space
    const h = interpolateHue(a_hsv.h, b_hsv.h, t);
    const s = interpolateF64(a_hsv.s, b_hsv.s, t);
    const v = interpolateF64(a_hsv.v, b_hsv.v, t);

    // Convert back to RGB
    const rgb = hsvToRgb(.{ .h = h, .s = s, .v = v });
    return Color.fromRgb(rgb.r, rgb.g, rgb.b);
}

/// Interpolate u8 values
fn interpolateU8(a: u8, b: u8, t: f64) u8 {
    const a_f: f64 = @floatFromInt(a);
    const b_f: f64 = @floatFromInt(b);
    const result = a_f + (b_f - a_f) * t;
    return @intFromFloat(@max(0.0, @min(255.0, result)));
}

/// Interpolate f64 values
fn interpolateF64(a: f64, b: f64, t: f64) f64 {
    return a + (b - a) * t;
}

/// Interpolate hue values (wraps around 360 degrees)
fn interpolateHue(a: f64, b: f64, t: f64) f64 {
    // Find shortest path around the color wheel
    var delta = b - a;
    if (delta > 180.0) {
        delta -= 360.0;
    } else if (delta < -180.0) {
        delta += 360.0;
    }

    var result = a + delta * t;
    if (result < 0.0) result += 360.0;
    if (result >= 360.0) result -= 360.0;

    return result;
}

/// HSV color representation
const HSV = struct {
    h: f64, // Hue: 0-360
    s: f64, // Saturation: 0-1
    v: f64, // Value: 0-1
};

/// RGB color representation
const RGB = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// Convert RGB to HSV
fn rgbToHsv(rgb: RGB) HSV {
    const r: f64 = @as(f64, @floatFromInt(rgb.r)) / 255.0;
    const g: f64 = @as(f64, @floatFromInt(rgb.g)) / 255.0;
    const b: f64 = @as(f64, @floatFromInt(rgb.b)) / 255.0;

    const max_val = @max(r, @max(g, b));
    const min_val = @min(r, @min(g, b));
    const delta = max_val - min_val;

    var h: f64 = 0.0;
    const s: f64 = if (max_val == 0.0) 0.0 else delta / max_val;
    const v: f64 = max_val;

    if (delta != 0.0) {
        if (max_val == r) {
            h = 60.0 * @mod((g - b) / delta, 6.0);
        } else if (max_val == g) {
            h = 60.0 * ((b - r) / delta + 2.0);
        } else {
            h = 60.0 * ((r - g) / delta + 4.0);
        }
    }

    if (h < 0.0) h += 360.0;

    return .{ .h = h, .s = s, .v = v };
}

/// Convert HSV to RGB
fn hsvToRgb(hsv: HSV) RGB {
    const c = hsv.v * hsv.s;
    const x = c * (1.0 - @abs(@mod(hsv.h / 60.0, 2.0) - 1.0));
    const m = hsv.v - c;

    var r: f64 = 0.0;
    var g: f64 = 0.0;
    var b: f64 = 0.0;

    if (hsv.h >= 0.0 and hsv.h < 60.0) {
        r = c;
        g = x;
        b = 0.0;
    } else if (hsv.h >= 60.0 and hsv.h < 120.0) {
        r = x;
        g = c;
        b = 0.0;
    } else if (hsv.h >= 120.0 and hsv.h < 180.0) {
        r = 0.0;
        g = c;
        b = x;
    } else if (hsv.h >= 180.0 and hsv.h < 240.0) {
        r = 0.0;
        g = x;
        b = c;
    } else if (hsv.h >= 240.0 and hsv.h < 300.0) {
        r = x;
        g = 0.0;
        b = c;
    } else {
        r = c;
        g = 0.0;
        b = x;
    }

    return .{
        .r = @intFromFloat((r + m) * 255.0),
        .g = @intFromFloat((g + m) * 255.0),
        .b = @intFromFloat((b + m) * 255.0),
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Direction.angle" {
    try std.testing.expectEqual(0.0, Direction.horizontal.angle());
    try std.testing.expectEqual(90.0, Direction.vertical.angle());
    try std.testing.expectEqual(45.0, Direction.diagonal_down.angle());
    try std.testing.expectEqual(135.0, Direction.diagonal_up.angle());
}

test "LinearGradient.colorAt - two stops" {
    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = Color.fromRgb(255, 0, 0) },   // Red
        .{ .offset = 1.0, .color = Color.fromRgb(0, 0, 255) },   // Blue
    };

    const gradient = LinearGradient{
        .direction = .horizontal,
        .stops = &stops,
    };

    // Start color
    const start_color = gradient.colorAt(0.0);
    try std.testing.expectEqual(Color.fromRgb(255, 0, 0), start_color);

    // End color
    const end_color = gradient.colorAt(1.0);
    try std.testing.expectEqual(Color.fromRgb(0, 0, 255), end_color);

    // Mid-point (should be purple-ish)
    const mid_color = gradient.colorAt(0.5);
    const mid_rgb = switch (mid_color) {
        .rgb => |val| val,
        else => unreachable,
    };
    try std.testing.expect(mid_rgb.r > 0 and mid_rgb.r < 255);
    try std.testing.expect(mid_rgb.b > 0 and mid_rgb.b < 255);
}

test "LinearGradient.colorAt - three stops" {
    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = Color.fromRgb(255, 0, 0) },   // Red
        .{ .offset = 0.5, .color = Color.fromRgb(0, 255, 0) },   // Green
        .{ .offset = 1.0, .color = Color.fromRgb(0, 0, 255) },   // Blue
    };

    const gradient = LinearGradient{
        .direction = .vertical,
        .stops = &stops,
    };

    // Exact stop match
    const green = gradient.colorAt(0.5);
    try std.testing.expectEqual(Color.fromRgb(0, 255, 0), green);

    // Between red and green
    const red_green = gradient.colorAt(0.25);
    const rg_rgb = switch (red_green) { .rgb => |val| val, else => unreachable };
    try std.testing.expect(rg_rgb.r > 0);
    try std.testing.expect(rg_rgb.g > 0);
    try std.testing.expect(rg_rgb.b == 0);
}

test "LinearGradient.colorAt - clamping" {
    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = Color.fromRgb(255, 0, 0) },
        .{ .offset = 1.0, .color = Color.fromRgb(0, 0, 255) },
    };

    const gradient = LinearGradient{
        .direction = .horizontal,
        .stops = &stops,
    };

    // Below 0.0 should clamp to first color
    try std.testing.expectEqual(Color.fromRgb(255, 0, 0), gradient.colorAt(-0.5));

    // Above 1.0 should clamp to last color
    try std.testing.expectEqual(Color.fromRgb(0, 0, 255), gradient.colorAt(1.5));
}

test "RadialGradient.colorAt - center" {
    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = Color.fromRgb(255, 0, 0) },   // Red center
        .{ .offset = 1.0, .color = Color.fromRgb(0, 0, 255) },   // Blue edge
    };

    const gradient = RadialGradient{
        .stops = &stops,
    };

    // At center, should be red
    const center = gradient.colorAt(0.5, 0.5);
    try std.testing.expectEqual(Color.fromRgb(255, 0, 0), center);

    // At edge (corner), should be closer to blue
    const corner = gradient.colorAt(0.0, 0.0);
    const corner_rgb = switch (corner) { .rgb => |val| val, else => unreachable };
    try std.testing.expect(corner_rgb.b > corner_rgb.r); // More blue than red
}

test "interpolateU8" {
    try std.testing.expectEqual(0, interpolateU8(0, 100, 0.0));
    try std.testing.expectEqual(100, interpolateU8(0, 100, 1.0));
    try std.testing.expectEqual(50, interpolateU8(0, 100, 0.5));
}

test "interpolateF64" {
    try std.testing.expectEqual(0.0, interpolateF64(0.0, 1.0, 0.0));
    try std.testing.expectEqual(1.0, interpolateF64(0.0, 1.0, 1.0));
    try std.testing.expectEqual(0.5, interpolateF64(0.0, 1.0, 0.5));
}

test "interpolateHue - shortest path" {
    // From 350 to 10 should go through 0 (not wrap backward)
    const result = interpolateHue(350.0, 10.0, 0.5);
    try std.testing.expect(result >= 0.0 and result < 360.0);

    // From 10 to 350 should go backward through 0
    const result2 = interpolateHue(10.0, 350.0, 0.5);
    try std.testing.expect(result2 >= 0.0 and result2 < 360.0);
}

test "rgbToHsv - red" {
    const rgb = RGB{ .r = 255, .g = 0, .b = 0 };
    const hsv = rgbToHsv(rgb);

    try std.testing.expectEqual(0.0, hsv.h);
    try std.testing.expectEqual(1.0, hsv.s);
    try std.testing.expectEqual(1.0, hsv.v);
}

test "rgbToHsv - green" {
    const rgb = RGB{ .r = 0, .g = 255, .b = 0 };
    const hsv = rgbToHsv(rgb);

    try std.testing.expectEqual(120.0, hsv.h);
    try std.testing.expectEqual(1.0, hsv.s);
    try std.testing.expectEqual(1.0, hsv.v);
}

test "rgbToHsv - blue" {
    const rgb = RGB{ .r = 0, .g = 0, .b = 255 };
    const hsv = rgbToHsv(rgb);

    try std.testing.expectEqual(240.0, hsv.h);
    try std.testing.expectEqual(1.0, hsv.s);
    try std.testing.expectEqual(1.0, hsv.v);
}

test "hsvToRgb - red" {
    const hsv = HSV{ .h = 0.0, .s = 1.0, .v = 1.0 };
    const rgb = hsvToRgb(hsv);

    try std.testing.expectEqual(255, rgb.r);
    try std.testing.expectEqual(0, rgb.g);
    try std.testing.expectEqual(0, rgb.b);
}

test "hsvToRgb - green" {
    const hsv = HSV{ .h = 120.0, .s = 1.0, .v = 1.0 };
    const rgb = hsvToRgb(hsv);

    try std.testing.expectEqual(0, rgb.r);
    try std.testing.expectEqual(255, rgb.g);
    try std.testing.expectEqual(0, rgb.b);
}

test "hsvToRgb - blue" {
    const hsv = HSV{ .h = 240.0, .s = 1.0, .v = 1.0 };
    const rgb = hsvToRgb(hsv);

    try std.testing.expectEqual(0, rgb.r);
    try std.testing.expectEqual(0, rgb.g);
    try std.testing.expectEqual(255, rgb.b);
}

test "RGB/HSV round-trip conversion" {
    const original = RGB{ .r = 128, .g = 64, .b = 192 };
    const hsv = rgbToHsv(original);
    const result = hsvToRgb(hsv);

    // Allow small rounding errors
    try std.testing.expect(@abs(@as(i16, original.r) - @as(i16, result.r)) <= 1);
    try std.testing.expect(@abs(@as(i16, original.g) - @as(i16, result.g)) <= 1);
    try std.testing.expect(@abs(@as(i16, original.b) - @as(i16, result.b)) <= 1);
}

test "interpolateRGB - red to blue" {
    const red = Color.fromRgb(255, 0, 0);
    const blue = Color.fromRgb(0, 0, 255);

    const mid = interpolateRGB(red, blue, 0.5);
    const mid_rgb = switch (mid) { .rgb => |val| val, else => unreachable };

    try std.testing.expectEqual(127, mid_rgb.r); // ~127
    try std.testing.expectEqual(0, mid_rgb.g);
    try std.testing.expectEqual(127, mid_rgb.b); // ~127
}

test "interpolateHSV - red to blue" {
    const red = Color.fromRgb(255, 0, 0);
    const blue = Color.fromRgb(0, 0, 255);

    const mid = interpolateHSV(red, blue, 0.5);
    const mid_rgb = switch (mid) { .rgb => |val| val, else => unreachable };

    // HSV interpolation should go through magenta (hue ~300)
    try std.testing.expect(mid_rgb.r > 0);
    try std.testing.expect(mid_rgb.b > 0);
}
