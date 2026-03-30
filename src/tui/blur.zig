const std = @import("std");
const tui = @import("tui.zig");
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Color = tui.Color;
const Style = tui.Style;
const Cell = tui.Cell;

/// BlurMode defines different blur rendering techniques
pub const BlurMode = enum {
    /// Use box drawing characters to simulate blur
    box_drawing,
    /// Use half-block characters with color mixing
    half_blocks,
    /// Use shade characters (░▒▓)
    shade_chars,
    /// Use Braille patterns for fine-grained blur
    braille,
};

/// TransparencyMode defines how transparency is rendered
pub const TransparencyMode = enum {
    /// No transparency
    none,
    /// Character-based transparency (░▒▓)
    char_fade,
    /// Color dimming (if terminal supports)
    color_dim,
    /// Checkerboard pattern
    checkerboard,
};

/// BlurEffect applies blur effects to buffer regions
pub const BlurEffect = struct {
    mode: BlurMode,
    intensity: u8, // 0-255

    /// Create a new blur effect with the specified mode and intensity (0-255)
    pub fn init(mode: BlurMode, intensity: u8) BlurEffect {
        return .{
            .mode = mode,
            .intensity = intensity,
        };
    }

    /// Apply blur effect to the specified buffer region
    /// Uses character-based rendering (box drawing, half blocks, shade chars, or Braille)
    pub fn apply(self: BlurEffect, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        switch (self.mode) {
            .box_drawing => self.applyBoxDrawing(buf, area),
            .half_blocks => self.applyHalfBlocks(buf, area),
            .shade_chars => self.applyShadeChars(buf, area),
            .braille => self.applyBraille(buf, area),
        }
    }

    fn applyBoxDrawing(self: BlurEffect, buf: *Buffer, area: Rect) void {
        // Use box drawing characters to create blur effect
        const chars = [_]u21{ '░', '▒', '▓' };
        const char_index = (self.intensity * chars.len) / 256;
        const blur_char = if (char_index < chars.len) chars[char_index] else chars[chars.len - 1];

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const cell_ptr = buf.get(x, y) orelse continue;
                var new_style = cell_ptr.style;
                new_style.dim = true;

                const new_cell = Cell.init(blur_char, new_style);
                buf.set(x, y, new_cell);
            }
        }
    }

    fn applyHalfBlocks(self: BlurEffect, buf: *Buffer, area: Rect) void {
        // Use half-block characters (▀▄) with color mixing
        const intensity_ratio = @as(f32, @floatFromInt(self.intensity)) / 255.0;

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const cell_ptr = buf.get(x, y) orelse continue;
                const blur_char: u21 = if ((x + y) % 2 == 0) '▀' else '▄';

                var new_style = cell_ptr.style;
                if (intensity_ratio > 0.5) {
                    new_style.dim = true;
                }

                const new_cell = Cell.init(blur_char, new_style);
                buf.set(x, y, new_cell);
            }
        }
    }

    fn applyShadeChars(self: BlurEffect, buf: *Buffer, area: Rect) void {
        // Use shade characters ░▒▓ based on intensity
        const chars = [_]u21{ '░', '▒', '▓', '█' };
        const char_index = (self.intensity * chars.len) / 256;
        const shade_char = if (char_index < chars.len) chars[char_index] else chars[chars.len - 1];

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const cell_ptr = buf.get(x, y) orelse continue;
                const new_cell = Cell.init(shade_char, cell_ptr.style);
                buf.set(x, y, new_cell);
            }
        }
    }

    fn applyBraille(self: BlurEffect, buf: *Buffer, area: Rect) void {
        // Use Braille patterns for fine-grained blur
        const braille_base: u21 = 0x2800; // Braille pattern blank
        const intensity_ratio = @as(f32, @floatFromInt(self.intensity)) / 255.0;
        const dot_threshold = intensity_ratio * 8.0;

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const cell_ptr = buf.get(x, y) orelse continue;

                // Generate random-like Braille pattern based on position
                const hash = (@as(u32, x) *% 2654435761) +% (@as(u32, y) *% 2246822519);
                const dots = @as(u8, @intCast((hash >> 16) & 0xFF));
                const active_dots = @min(dots % 9, @as(u8, @intFromFloat(dot_threshold)));

                const braille_char = braille_base + active_dots;
                const new_cell = Cell.init(braille_char, cell_ptr.style);
                buf.set(x, y, new_cell);
            }
        }
    }
};

/// TransparencyEffect applies transparency effects to buffer regions
pub const TransparencyEffect = struct {
    mode: TransparencyMode,
    alpha: u8, // 0-255 (0 = fully transparent, 255 = opaque)

    /// Create a new transparency effect with the specified mode and alpha (0=transparent, 255=opaque)
    pub fn init(mode: TransparencyMode, alpha: u8) TransparencyEffect {
        return .{
            .mode = mode,
            .alpha = alpha,
        };
    }

    /// Apply transparency effect to the specified buffer region
    /// Uses character fading, color dimming, or checkerboard patterns
    pub fn apply(self: TransparencyEffect, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        switch (self.mode) {
            .none => {},
            .char_fade => self.applyCharFade(buf, area),
            .color_dim => self.applyColorDim(buf, area),
            .checkerboard => self.applyCheckerboard(buf, area),
        }
    }

    fn applyCharFade(self: TransparencyEffect, buf: *Buffer, area: Rect) void {
        // Use ░▒▓ characters based on alpha
        const chars = [_]u21{ ' ', '░', '▒', '▓' };
        const alpha_index = (self.alpha * chars.len) / 256;
        const fade_char = if (alpha_index < chars.len) chars[alpha_index] else chars[chars.len - 1];

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const cell_ptr = buf.get(x, y) orelse continue;
                const new_cell = Cell.init(fade_char, cell_ptr.style);
                buf.set(x, y, new_cell);
            }
        }
    }

    fn applyColorDim(self: TransparencyEffect, buf: *Buffer, area: Rect) void {
        // Dim colors based on alpha
        const should_dim = self.alpha < 192; // < 75% opacity

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const cell_ptr = buf.get(x, y) orelse continue;
                var new_style = cell_ptr.style;
                new_style.dim = should_dim;

                const new_cell = Cell.init(cell_ptr.char, new_style);
                buf.set(x, y, new_cell);
            }
        }
    }

    fn applyCheckerboard(self: TransparencyEffect, buf: *Buffer, area: Rect) void {
        // Checkerboard pattern for transparency
        const show_cell_threshold = self.alpha;

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                const is_checkerboard = (x + y) % 2 == 0;

                // Use alpha to determine if we show the cell
                const hash = (@as(u32, x) *% 31) +% (@as(u32, y) *% 17);
                const threshold = @as(u8, @intCast((hash >> 8) & 0xFF));

                if (threshold > show_cell_threshold and is_checkerboard) {
                    // Make cell transparent (empty)
                    const empty_cell = Cell.init(' ', Style{});
                    buf.set(x, y, empty_cell);
                }
            }
        }
    }

    /// Blend two colors based on alpha value
    /// Returns foreground color unless it's reset, in which case returns background
    pub fn blendColors(self: TransparencyEffect, fg: Color, bg: Color) Color {
        _ = self;
        // Simplified: return fg unless it's reset
        // Full implementation would do RGB mixing
        if (fg == .reset) return bg;
        return fg;
    }
};

/// Combined blur+transparency effect
pub const CompositeEffect = struct {
    blur: ?BlurEffect,
    transparency: ?TransparencyEffect,

    /// Create a composite effect combining blur and transparency
    /// Either effect can be null to apply only one
    pub fn init(blur: ?BlurEffect, transparency: ?TransparencyEffect) CompositeEffect {
        return .{
            .blur = blur,
            .transparency = transparency,
        };
    }

    /// Apply composite effect to buffer region
    /// Applies blur first, then transparency if both are present
    pub fn apply(self: CompositeEffect, buf: *Buffer, area: Rect) void {
        // Apply blur first, then transparency
        if (self.blur) |blur_effect| {
            blur_effect.apply(buf, area);
        }

        if (self.transparency) |trans_effect| {
            trans_effect.apply(buf, area);
        }
    }
};

// Tests
const testing = std.testing;

test "BlurEffect.init" {
    const blur = BlurEffect.init(.box_drawing, 128);
    try testing.expectEqual(BlurMode.box_drawing, blur.mode);
    try testing.expectEqual(@as(u8, 128), blur.intensity);
}

test "BlurEffect.apply box_drawing mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const blur = BlurEffect.init(.box_drawing, 128);
    const area = Rect{ .x = 2, .y = 1, .width = 5, .height = 3 };
    blur.apply(&buf, area);

    // Check that blur chars are applied in area
    const cell_ptr = buf.get(3, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char == '░' or cell_ptr.char == '▒' or cell_ptr.char == '▓');
}

test "BlurEffect.apply shade_chars mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const blur = BlurEffect.init(.shade_chars, 200);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    blur.apply(&buf, area);

    // Shade chars should be applied
    const cell_ptr = buf.get(5, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char == '░' or cell_ptr.char == '▒' or cell_ptr.char == '▓' or cell_ptr.char == '█');
}

test "BlurEffect.apply half_blocks mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const blur = BlurEffect.init(.half_blocks, 100);
    const area = Rect{ .x = 1, .y = 1, .width = 8, .height = 3 };
    blur.apply(&buf, area);

    // Half-block chars should be applied
    const cell_ptr = buf.get(4, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char == '▀' or cell_ptr.char == '▄');
}

test "BlurEffect.apply braille mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const blur = BlurEffect.init(.braille, 150);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    blur.apply(&buf, area);

    // Braille chars should be in range 0x2800-0x28FF
    const cell_ptr = buf.get(5, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char >= 0x2800 and cell_ptr.char <= 0x28FF);
}

test "BlurEffect zero-size area is no-op" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const blur = BlurEffect.init(.box_drawing, 128);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    // Should not crash
    blur.apply(&buf, area);
}

test "BlurEffect intensity affects character selection" {
    var buf1 = try Buffer.init(testing.allocator, 5, 5);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 5, 5);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };

    const low_blur = BlurEffect.init(.shade_chars, 50);
    low_blur.apply(&buf1, area);

    const high_blur = BlurEffect.init(.shade_chars, 250);
    high_blur.apply(&buf2, area);

    // Different intensities should produce different chars
    const cell1 = buf1.get(2, 2) orelse return error.TestUnexpectedNull;
    const cell2 = buf2.get(2, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell1.char != cell2.char);
}

test "TransparencyEffect.init" {
    const trans = TransparencyEffect.init(.char_fade, 128);
    try testing.expectEqual(TransparencyMode.char_fade, trans.mode);
    try testing.expectEqual(@as(u8, 128), trans.alpha);
}

test "TransparencyEffect.apply none mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const original_cell = buf.get(5, 2) orelse return error.TestUnexpectedNull;
    const original_char = original_cell.char;

    const trans = TransparencyEffect.init(.none, 128);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    trans.apply(&buf, area);

    // Buffer should be unchanged
    const after_cell = buf.get(5, 2) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(original_char, after_cell.char);
}

test "TransparencyEffect.apply char_fade mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const trans = TransparencyEffect.init(.char_fade, 128);
    const area = Rect{ .x = 2, .y = 1, .width = 6, .height = 3 };
    trans.apply(&buf, area);

    // Fade chars should be applied
    const cell_ptr = buf.get(4, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char == ' ' or cell_ptr.char == '░' or cell_ptr.char == '▒' or cell_ptr.char == '▓');
}

test "TransparencyEffect.apply color_dim mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const trans = TransparencyEffect.init(.color_dim, 100);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    trans.apply(&buf, area);

    // Dim flag should be set
    const cell_ptr = buf.get(5, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.style.dim);
}

test "TransparencyEffect.apply checkerboard mode" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const trans = TransparencyEffect.init(.checkerboard, 128);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    trans.apply(&buf, area);

    // Some cells should be empty (space)
    var found_empty = false;
    for (0..area.height) |y| {
        for (0..area.width) |x| {
            if (buf.get(@intCast(x), @intCast(y))) |cell_ptr| {
                if (cell_ptr.char == ' ') {
                    found_empty = true;
                    break;
                }
            }
        }
    }
    try testing.expect(found_empty);
}

test "TransparencyEffect alpha affects fade" {
    var buf1 = try Buffer.init(testing.allocator, 5, 5);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 5, 5);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };

    const low_alpha = TransparencyEffect.init(.char_fade, 50);
    low_alpha.apply(&buf1, area);

    const high_alpha = TransparencyEffect.init(.char_fade, 250);
    high_alpha.apply(&buf2, area);

    // Different alphas should produce different chars
    const cell1 = buf1.get(2, 2) orelse return error.TestUnexpectedNull;
    const cell2 = buf2.get(2, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell1.char != cell2.char);
}

test "TransparencyEffect.blendColors" {
    const trans = TransparencyEffect.init(.char_fade, 128);

    const fg = Color.red;
    const bg = Color.blue;

    const result = trans.blendColors(fg, bg);
    try testing.expectEqual(Color.red, result); // Simplified: returns fg
}

test "TransparencyEffect.blendColors with reset" {
    const trans = TransparencyEffect.init(.char_fade, 128);

    const fg = Color.reset;
    const bg = Color.green;

    const result = trans.blendColors(fg, bg);
    try testing.expectEqual(Color.green, result); // Returns bg when fg is reset
}

test "CompositeEffect.init with both effects" {
    const blur = BlurEffect.init(.box_drawing, 100);
    const trans = TransparencyEffect.init(.char_fade, 150);

    const composite = CompositeEffect.init(blur, trans);

    try testing.expect(composite.blur != null);
    try testing.expect(composite.transparency != null);
}

test "CompositeEffect.init with only blur" {
    const blur = BlurEffect.init(.shade_chars, 100);

    const composite = CompositeEffect.init(blur, null);

    try testing.expect(composite.blur != null);
    try testing.expect(composite.transparency == null);
}

test "CompositeEffect.init with only transparency" {
    const trans = TransparencyEffect.init(.color_dim, 150);

    const composite = CompositeEffect.init(null, trans);

    try testing.expect(composite.blur == null);
    try testing.expect(composite.transparency != null);
}

test "CompositeEffect.apply with both effects" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const blur = BlurEffect.init(.box_drawing, 128);
    const trans = TransparencyEffect.init(.color_dim, 100);
    const composite = CompositeEffect.init(blur, trans);

    const area = Rect{ .x = 2, .y = 1, .width = 6, .height = 3 };
    composite.apply(&buf, area);

    // Both effects should be applied
    const cell_ptr = buf.get(4, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char == '░' or cell_ptr.char == '▒' or cell_ptr.char == '▓');
    try testing.expect(cell_ptr.style.dim);
}

test "CompositeEffect.apply with only blur" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const blur = BlurEffect.init(.shade_chars, 200);
    const composite = CompositeEffect.init(blur, null);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    composite.apply(&buf, area);

    const cell_ptr = buf.get(5, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char == '░' or cell_ptr.char == '▒' or cell_ptr.char == '▓' or cell_ptr.char == '█');
}

test "CompositeEffect.apply with only transparency" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const trans = TransparencyEffect.init(.char_fade, 128);
    const composite = CompositeEffect.init(null, trans);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    composite.apply(&buf, area);

    const cell_ptr = buf.get(5, 2) orelse return error.TestUnexpectedNull;
    try testing.expect(cell_ptr.char == ' ' or cell_ptr.char == '░' or cell_ptr.char == '▒' or cell_ptr.char == '▓');
}
