const std = @import("std");
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;

/// Shadow direction for 3D effects
pub const ShadowDirection = enum {
    bottom_right,
    bottom_left,
    top_right,
    top_left,
    bottom,
    right,
};

/// Shadow style configuration
pub const ShadowStyle = struct {
    /// Character used for shadow
    char: u21 = '░',
    /// Style for shadow rendering
    style: Style = .{ .fg = Color.bright_black },
    /// Shadow depth (number of cells)
    depth: u8 = 1,
    /// Direction of shadow
    direction: ShadowDirection = .bottom_right,

    /// Default subtle shadow
    pub const subtle: ShadowStyle = .{
        .char = '░',
        .style = .{ .fg = Color.bright_black },
        .depth = 1,
        .direction = .bottom_right,
    };

    /// Medium shadow
    pub const medium: ShadowStyle = .{
        .char = '▒',
        .style = .{ .fg = Color.bright_black },
        .depth = 2,
        .direction = .bottom_right,
    };

    /// Heavy shadow
    pub const heavy: ShadowStyle = .{
        .char = '▓',
        .style = .{ .fg = Color.black },
        .depth = 2,
        .direction = .bottom_right,
    };

    /// Custom shadow with specific char and color
    pub fn custom(char: u21, color: Color, depth: u8, direction: ShadowDirection) ShadowStyle {
        return .{
            .char = char,
            .style = .{ .fg = color },
            .depth = depth,
            .direction = direction,
        };
    }
};

/// Border effect style for 3D appearance
pub const BorderEffect = enum {
    /// Standard flat border
    flat,
    /// Raised border (light top/left, dark bottom/right)
    raised,
    /// Sunken border (dark top/left, light bottom/right)
    sunken,
    /// Double-line effect
    double,
};

/// Border style with 3D effects
pub const BorderStyle3D = struct {
    effect: BorderEffect = .flat,
    highlight_color: Color = Color.white,
    shadow_color: Color = Color.bright_black,

    /// Get style for top/left border (highlight for raised, shadow for sunken)
    pub fn getTopLeftStyle(self: BorderStyle3D, base_style: Style) Style {
        return switch (self.effect) {
            .flat, .double => base_style,
            .raised => .{ .fg = self.highlight_color, .bg = base_style.bg, .bold = true },
            .sunken => .{ .fg = self.shadow_color, .bg = base_style.bg, .dim = true },
        };
    }

    /// Get style for bottom/right border (shadow for raised, highlight for sunken)
    pub fn getBottomRightStyle(self: BorderStyle3D, base_style: Style) Style {
        return switch (self.effect) {
            .flat, .double => base_style,
            .raised => .{ .fg = self.shadow_color, .bg = base_style.bg, .dim = true },
            .sunken => .{ .fg = self.highlight_color, .bg = base_style.bg, .bold = true },
        };
    }

    /// Preset for raised button appearance
    pub const raised_button: BorderStyle3D = .{
        .effect = .raised,
        .highlight_color = Color.white,
        .shadow_color = Color.bright_black,
    };

    /// Preset for sunken input field appearance
    pub const sunken_input: BorderStyle3D = .{
        .effect = .sunken,
        .highlight_color = Color.white,
        .shadow_color = Color.bright_black,
    };
};

/// Render a drop shadow for a rectangular area
pub fn renderShadow(buf: *Buffer, area: Rect, shadow: ShadowStyle) void {
    const depth = shadow.depth;
    if (depth == 0) return;

    switch (shadow.direction) {
        .bottom_right => {
            // Right edge shadow
            var y: u16 = area.y + 1;
            while (y < area.y + area.height and y < buf.height) : (y += 1) {
                var d: u8 = 0;
                while (d < depth and area.x + area.width + d < buf.width) : (d += 1) {
                    buf.set(area.x + area.width + d, y, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
            // Bottom edge shadow
            var x: u16 = area.x + depth;
            while (x < area.x + area.width + depth and x < buf.width) : (x += 1) {
                var d: u8 = 0;
                while (d < depth and area.y + area.height + d < buf.height) : (d += 1) {
                    buf.set(x, area.y + area.height + d, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
        },
        .bottom_left => {
            // Left edge shadow
            var y: u16 = area.y + 1;
            while (y < area.y + area.height and y < buf.height) : (y += 1) {
                var d: u8 = 0;
                while (d < depth and d <= area.x) : (d += 1) {
                    buf.set(area.x -| d -| 1, y, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
            // Bottom edge shadow
            var x: u16 = area.x -| depth;
            while (x < area.x + area.width and x < buf.width) : (x += 1) {
                var d: u8 = 0;
                while (d < depth and area.y + area.height + d < buf.height) : (d += 1) {
                    buf.set(x, area.y + area.height + d, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
        },
        .top_right => {
            // Right edge shadow
            var y: u16 = area.y;
            while (y < area.y + area.height -| 1 and y < buf.height) : (y += 1) {
                var d: u8 = 0;
                while (d < depth and area.x + area.width + d < buf.width) : (d += 1) {
                    buf.set(area.x + area.width + d, y, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
            // Top edge shadow
            var x: u16 = area.x + depth;
            while (x < area.x + area.width + depth and x < buf.width) : (x += 1) {
                var d: u8 = 0;
                while (d < depth and d <= area.y) : (d += 1) {
                    buf.set(x, area.y -| d -| 1, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
        },
        .top_left => {
            // Left edge shadow
            var y: u16 = area.y;
            while (y < area.y + area.height -| 1 and y < buf.height) : (y += 1) {
                var d: u8 = 0;
                while (d < depth and d <= area.x) : (d += 1) {
                    buf.set(area.x -| d -| 1, y, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
            // Top edge shadow
            var x: u16 = area.x -| depth;
            while (x < area.x + area.width and x < buf.width) : (x += 1) {
                var d: u8 = 0;
                while (d < depth and d <= area.y) : (d += 1) {
                    buf.set(x, area.y -| d -| 1, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
        },
        .bottom => {
            // Bottom edge only
            var x: u16 = area.x;
            while (x < area.x + area.width and x < buf.width) : (x += 1) {
                var d: u8 = 0;
                while (d < depth and area.y + area.height + d < buf.height) : (d += 1) {
                    buf.set(x, area.y + area.height + d, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
        },
        .right => {
            // Right edge only
            var y: u16 = area.y;
            while (y < area.y + area.height and y < buf.height) : (y += 1) {
                var d: u8 = 0;
                while (d < depth and area.x + area.width + d < buf.width) : (d += 1) {
                    buf.set(area.x + area.width + d, y, .{
                        .char = shadow.char,
                        .style = shadow.style,
                    });
                }
            }
        },
    }
}

/// Apply 3D border effect to area edges (modifies existing border cells)
pub fn applyBorderEffect(buf: *Buffer, area: Rect, effect: BorderStyle3D, base_style: Style) void {
    if (effect.effect == .flat) return;
    if (area.width < 2 or area.height < 2) return;

    const top_left_style = effect.getTopLeftStyle(base_style);
    const bottom_right_style = effect.getBottomRightStyle(base_style);

    // Top edge
    var x: u16 = area.x;
    while (x < area.x + area.width and x < buf.width) : (x += 1) {
        if (buf.getConst(x, area.y)) |cell| {
            if (cell.char != ' ') { // Only modify border characters
                buf.set(x, area.y, .{ .char = cell.char, .style = top_left_style });
            }
        }
    }

    // Bottom edge
    x = area.x;
    while (x < area.x + area.width and x < buf.width) : (x += 1) {
        const y = area.y + area.height -| 1;
        if (y >= buf.height) continue;
        if (buf.getConst(x, y)) |cell| {
            if (cell.char != ' ') {
                buf.set(x, y, .{ .char = cell.char, .style = bottom_right_style });
            }
        }
    }

    // Left edge
    var y: u16 = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        if (buf.getConst(area.x, y)) |cell| {
            if (cell.char != ' ') {
                buf.set(area.x, y, .{ .char = cell.char, .style = top_left_style });
            }
        }
    }

    // Right edge
    y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        const x_right = area.x + area.width -| 1;
        if (x_right >= buf.width) continue;
        if (buf.getConst(x_right, y)) |cell| {
            if (cell.char != ' ') {
                buf.set(x_right, y, .{ .char = cell.char, .style = bottom_right_style });
            }
        }
    }
}

test "ShadowStyle presets" {
    const subtle = ShadowStyle.subtle;
    try std.testing.expectEqual(@as(u21, '░'), subtle.char);
    try std.testing.expectEqual(@as(u8, 1), subtle.depth);
    try std.testing.expectEqual(ShadowDirection.bottom_right, subtle.direction);

    const heavy = ShadowStyle.heavy;
    try std.testing.expectEqual(@as(u21, '▓'), heavy.char);
    try std.testing.expectEqual(@as(u8, 2), heavy.depth);
}

test "ShadowStyle custom" {
    const custom = ShadowStyle.custom('█', Color.red, 3, .top_left);
    try std.testing.expectEqual(@as(u21, '█'), custom.char);
    try std.testing.expectEqual(@as(u8, 3), custom.depth);
    try std.testing.expectEqual(ShadowDirection.top_left, custom.direction);
}

test "BorderEffect styles" {
    const base = Style{ .fg = Color.blue };

    const raised = BorderStyle3D.raised_button;
    const top_left = raised.getTopLeftStyle(base);
    try std.testing.expect(top_left.bold);

    const bottom_right = raised.getBottomRightStyle(base);
    try std.testing.expect(bottom_right.dim);

    const sunken = BorderStyle3D.sunken_input;
    const sunken_top = sunken.getTopLeftStyle(base);
    try std.testing.expect(sunken_top.dim);
}

test "renderShadow bottom_right" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 2, .width = 5, .height = 3 };
    const shadow = ShadowStyle{ .depth = 1, .direction = .bottom_right };
    renderShadow(&buf, area, shadow);

    // Check right edge shadow
    const right_shadow = buf.getConst(7, 3).?;
    try std.testing.expectEqual(@as(u21, '░'), right_shadow.char);

    // Check bottom edge shadow
    const bottom_shadow = buf.getConst(4, 5).?;
    try std.testing.expectEqual(@as(u21, '░'), bottom_shadow.char);
}

test "renderShadow bottom_left" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 4, .y = 2, .width = 4, .height = 3 };
    const shadow = ShadowStyle{ .depth = 1, .direction = .bottom_left };
    renderShadow(&buf, area, shadow);

    // Check left edge shadow (at x=3, since area.x=4 and depth=1)
    const left_shadow = buf.getConst(3, 3).?;
    try std.testing.expectEqual(@as(u21, '░'), left_shadow.char);

    // Check bottom edge shadow
    const bottom_shadow = buf.getConst(5, 5).?;
    try std.testing.expectEqual(@as(u21, '░'), bottom_shadow.char);
}

test "renderShadow top_right" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 3, .width = 4, .height = 3 };
    const shadow = ShadowStyle{ .depth = 1, .direction = .top_right };
    renderShadow(&buf, area, shadow);

    // Check right edge shadow
    const right_shadow = buf.getConst(6, 3).?;
    try std.testing.expectEqual(@as(u21, '░'), right_shadow.char);

    // Check top edge shadow (at y=2, since area.y=3 and depth=1)
    const top_shadow = buf.getConst(4, 2).?;
    try std.testing.expectEqual(@as(u21, '░'), top_shadow.char);
}

test "renderShadow top_left" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 4, .y = 4, .width = 3, .height = 3 };
    const shadow = ShadowStyle{ .depth = 1, .direction = .top_left };
    renderShadow(&buf, area, shadow);

    // Check left edge shadow
    const left_shadow = buf.getConst(3, 4).?;
    try std.testing.expectEqual(@as(u21, '░'), left_shadow.char);

    // Check top edge shadow
    const top_shadow = buf.getConst(4, 3).?;
    try std.testing.expectEqual(@as(u21, '░'), top_shadow.char);
}

test "renderShadow bottom only" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 2, .width = 5, .height = 3 };
    const shadow = ShadowStyle{ .depth = 1, .direction = .bottom };
    renderShadow(&buf, area, shadow);

    // Check bottom edge shadow
    const bottom_shadow = buf.getConst(4, 5).?;
    try std.testing.expectEqual(@as(u21, '░'), bottom_shadow.char);

    // Right edge should be empty
    const right_cell = buf.getConst(7, 3).?;
    try std.testing.expectEqual(@as(u21, ' '), right_cell.char);
}

test "renderShadow right only" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 2, .width = 5, .height = 3 };
    const shadow = ShadowStyle{ .depth = 1, .direction = .right };
    renderShadow(&buf, area, shadow);

    // Check right edge shadow
    const right_shadow = buf.getConst(7, 3).?;
    try std.testing.expectEqual(@as(u21, '░'), right_shadow.char);

    // Bottom edge should be empty
    const bottom_cell = buf.getConst(4, 5).?;
    try std.testing.expectEqual(@as(u21, ' '), bottom_cell.char);
}

test "renderShadow with depth 2" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 2, .width = 4, .height = 3 };
    const shadow = ShadowStyle{ .depth = 2, .direction = .bottom_right };
    renderShadow(&buf, area, shadow);

    // Check first layer of right shadow
    const right1 = buf.getConst(6, 3).?;
    try std.testing.expectEqual(@as(u21, '░'), right1.char);

    // Check second layer of right shadow
    const right2 = buf.getConst(7, 3).?;
    try std.testing.expectEqual(@as(u21, '░'), right2.char);

    // Check first layer of bottom shadow
    const bottom1 = buf.getConst(4, 5).?;
    try std.testing.expectEqual(@as(u21, '░'), bottom1.char);

    // Check second layer of bottom shadow
    const bottom2 = buf.getConst(4, 6).?;
    try std.testing.expectEqual(@as(u21, '░'), bottom2.char);
}

test "renderShadow boundary clipping" {
    var buf = try Buffer.init(std.testing.allocator, 8, 6);
    defer buf.deinit();

    // Area extends to edge of buffer
    const area = Rect{ .x = 4, .y = 3, .width = 4, .height = 3 };
    const shadow = ShadowStyle{ .depth = 2, .direction = .bottom_right };

    // Should not panic, shadow clipped at buffer boundaries
    renderShadow(&buf, area, shadow);
}

test "applyBorderEffect raised" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Create a border area
    const area = Rect{ .x = 2, .y = 2, .width = 6, .height = 4 };

    // Draw simple border
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        buf.set(area.x, y, .{ .char = '│', .style = .{} });
        buf.set(area.x + area.width - 1, y, .{ .char = '│', .style = .{} });
    }
    var x: u16 = area.x;
    while (x < area.x + area.width) : (x += 1) {
        buf.set(x, area.y, .{ .char = '─', .style = .{} });
        buf.set(x, area.y + area.height - 1, .{ .char = '─', .style = .{} });
    }

    const effect = BorderStyle3D.raised_button;
    applyBorderEffect(&buf, area, effect, .{});

    // Check top edge has highlight (bold)
    const top_cell = buf.getConst(4, 2).?;
    try std.testing.expect(top_cell.style.bold);

    // Check bottom edge has shadow (dim)
    const bottom_cell = buf.getConst(4, 5).?;
    try std.testing.expect(bottom_cell.style.dim);
}

test "applyBorderEffect sunken" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 2, .width = 6, .height = 4 };

    // Draw simple border
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        buf.set(area.x, y, .{ .char = '│', .style = .{} });
        buf.set(area.x + area.width - 1, y, .{ .char = '│', .style = .{} });
    }
    var x: u16 = area.x;
    while (x < area.x + area.width) : (x += 1) {
        buf.set(x, area.y, .{ .char = '─', .style = .{} });
        buf.set(x, area.y + area.height - 1, .{ .char = '─', .style = .{} });
    }

    const effect = BorderStyle3D.sunken_input;
    applyBorderEffect(&buf, area, effect, .{});

    // Check top edge has shadow (dim)
    const top_cell = buf.getConst(4, 2).?;
    try std.testing.expect(top_cell.style.dim);

    // Check bottom edge has highlight (bold)
    const bottom_cell = buf.getConst(4, 5).?;
    try std.testing.expect(bottom_cell.style.bold);
}

test "applyBorderEffect flat (no-op)" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 2, .width = 6, .height = 4 };
    const base_style = Style{ .fg = Color.blue };

    buf.set(2, 2, .{ .char = '┌', .style = base_style });

    const effect = BorderStyle3D{ .effect = .flat };
    applyBorderEffect(&buf, area, effect, base_style);

    // Cell should be unchanged
    const cell = buf.getConst(2, 2).?;
    try std.testing.expectEqual(@as(u21, '┌'), cell.char);
    try std.testing.expectEqual(Color.blue, cell.style.fg.?);
}

test "applyBorderEffect small area (no-op)" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Area too small for border effect
    const area = Rect{ .x = 2, .y = 2, .width = 1, .height = 1 };
    const effect = BorderStyle3D.raised_button;

    // Should not panic
    applyBorderEffect(&buf, area, effect, .{});
}

/// Blur configuration for box blur effect
pub const BlurConfig = struct {
    /// Blur radius (1 = 3×3 kernel, 2 = 5×5 kernel)
    radius: u8 = 1,
    /// Only process fg colors (true) or ignore bg
    fg_only: bool = true,
};

/// Transparency blend configuration
pub const TransparencyConfig = struct {
    /// 1.0 = fully opaque (no change), 0.0 = blend fully to background
    alpha: f32 = 0.5,
    /// Background color to blend toward; null defaults to black (0,0,0)
    background: ?Color = null,
};

/// Apply box blur to area — averages neighboring RGB fg colors.
/// Non-RGB colors are left unchanged.
pub fn applyBlur(buf: *Buffer, area: Rect, config: BlurConfig) void {
    if (area.width == 0 or area.height == 0) return;
    const r: i32 = config.radius;
    var y: u16 = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            const cell = buf.getConst(x, y) orelse continue;
            const fg = cell.style.fg orelse continue;
            switch (fg) {
                .rgb => {},
                else => continue,
            }
            var sum_r: u32 = 0;
            var sum_g: u32 = 0;
            var sum_b: u32 = 0;
            var count: u32 = 0;
            var ny: i32 = @as(i32, y) - r;
            while (ny <= @as(i32, y) + r) : (ny += 1) {
                if (ny < 0 or ny >= @as(i32, buf.height)) continue;
                var nx: i32 = @as(i32, x) - r;
                while (nx <= @as(i32, x) + r) : (nx += 1) {
                    if (nx < 0 or nx >= @as(i32, buf.width)) continue;
                    const nc = buf.getConst(@intCast(nx), @intCast(ny)) orelse continue;
                    const nfg = nc.style.fg orelse continue;
                    switch (nfg) {
                        .rgb => |c| {
                            sum_r += c.r;
                            sum_g += c.g;
                            sum_b += c.b;
                            count += 1;
                        },
                        else => {},
                    }
                }
            }
            if (count > 0) {
                buf.set(x, y, .{
                    .char = cell.char,
                    .style = cell.style.withFg(Color.fromRgb(
                        @intCast(sum_r / count),
                        @intCast(sum_g / count),
                        @intCast(sum_b / count),
                    )),
                });
            }
        }
    }
}

/// Apply transparency to area — blends RGB fg colors toward background using alpha.
/// Non-RGB colors are left unchanged.
pub fn applyTransparency(buf: *Buffer, area: Rect, config: TransparencyConfig) void {
    if (area.width == 0 or area.height == 0) return;
    const bg_r: f32 = if (config.background) |bg| switch (bg) {
        .rgb => |c| @floatFromInt(c.r),
        else => 0.0,
    } else 0.0;
    const bg_g: f32 = if (config.background) |bg| switch (bg) {
        .rgb => |c| @floatFromInt(c.g),
        else => 0.0,
    } else 0.0;
    const bg_b: f32 = if (config.background) |bg| switch (bg) {
        .rgb => |c| @floatFromInt(c.b),
        else => 0.0,
    } else 0.0;
    const alpha = @min(1.0, @max(0.0, config.alpha));
    var y: u16 = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            const cell = buf.getConst(x, y) orelse continue;
            const fg = cell.style.fg orelse continue;
            switch (fg) {
                .rgb => |c| {
                    const new_r: u8 = @intFromFloat(@as(f32, @floatFromInt(c.r)) * alpha + bg_r * (1.0 - alpha));
                    const new_g: u8 = @intFromFloat(@as(f32, @floatFromInt(c.g)) * alpha + bg_g * (1.0 - alpha));
                    const new_b: u8 = @intFromFloat(@as(f32, @floatFromInt(c.b)) * alpha + bg_b * (1.0 - alpha));
                    buf.set(x, y, .{
                        .char = cell.char,
                        .style = cell.style.withFg(Color.fromRgb(new_r, new_g, new_b)),
                    });
                },
                else => {},
            }
        }
    }
}

// ============================================================================
// Tests for applyBlur and applyTransparency
// ============================================================================

test "BlurConfig default values" {
    const config = BlurConfig{};
    try std.testing.expectEqual(@as(u8, 1), config.radius);
    try std.testing.expect(config.fg_only);
}

test "BlurConfig custom values" {
    const config = BlurConfig{
        .radius = 2,
        .fg_only = false,
    };
    try std.testing.expectEqual(@as(u8, 2), config.radius);
    try std.testing.expect(!config.fg_only);
}

test "TransparencyConfig default values" {
    const config = TransparencyConfig{};
    try std.testing.expectEqual(@as(f32, 0.5), config.alpha);
    try std.testing.expectEqual(@as(?Color, null), config.background);
}

test "TransparencyConfig custom values" {
    const config = TransparencyConfig{
        .alpha = 0.75,
        .background = Color.white,
    };
    try std.testing.expectEqual(@as(f32, 0.75), config.alpha);
    try std.testing.expectEqual(Color.white, config.background.?);
}

test "applyBlur single cell area unchanged" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Set single cell with RGB color
    const original_color = Color.fromRgb(200, 100, 50);
    buf.set(5, 5, .{
        .char = 'X',
        .style = .{ .fg = original_color },
    });

    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    const config = BlurConfig{};
    applyBlur(&buf, area, config);

    // Single cell should be unchanged (nothing to average with)
    const cell = buf.getConst(5, 5).?;
    try std.testing.expectEqual(@as(u21, 'X'), cell.char);
    if (cell.style.fg) |fg| {
        switch (fg) {
            .rgb => |c| {
                try std.testing.expectEqual(@as(u8, 200), c.r);
                try std.testing.expectEqual(@as(u8, 100), c.g);
                try std.testing.expectEqual(@as(u8, 50), c.b);
            },
            else => try std.testing.expect(false), // Should be RGB
        }
    } else {
        try std.testing.expect(false); // Should have color
    }
}

test "applyBlur 3x3 uniform color unchanged" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Fill 3x3 area with same RGB color
    const uniform_color = Color.fromRgb(150, 150, 150);
    var y: u16 = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 2;
        while (x < 5) : (x += 1) {
            buf.set(x, y, .{
                .char = 'U',
                .style = .{ .fg = uniform_color },
            });
        }
    }

    const area = Rect{ .x = 2, .y = 2, .width = 3, .height = 3 };
    const config = BlurConfig{ .radius = 1 };
    applyBlur(&buf, area, config);

    // All colors should remain the same (uniform color averages to itself)
    y = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 2;
        while (x < 5) : (x += 1) {
            const cell = buf.getConst(x, y).?;
            if (cell.style.fg) |fg| {
                switch (fg) {
                    .rgb => |c| {
                        try std.testing.expectEqual(@as(u8, 150), c.r);
                        try std.testing.expectEqual(@as(u8, 150), c.g);
                        try std.testing.expectEqual(@as(u8, 150), c.b);
                    },
                    else => try std.testing.expect(false),
                }
            }
        }
    }
}

test "applyBlur softens bright center surrounded by dark" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Create 3x3 area: center is bright white, surrounding is black
    const black = Color.fromRgb(0, 0, 0);
    const white = Color.fromRgb(255, 255, 255);

    // Set all to black first
    var y: u16 = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 2;
        while (x < 5) : (x += 1) {
            buf.set(x, y, .{
                .char = 'X',
                .style = .{ .fg = black },
            });
        }
    }

    // Set center to white
    buf.set(3, 3, .{
        .char = 'X',
        .style = .{ .fg = white },
    });

    const area = Rect{ .x = 2, .y = 2, .width = 3, .height = 3 };
    const config = BlurConfig{ .radius = 1 };
    applyBlur(&buf, area, config);

    // Center should now be closer to black (blurred toward neighbors)
    // The exact value depends on implementation, but should be < 255
    const center_cell = buf.getConst(3, 3).?;
    if (center_cell.style.fg) |fg| {
        switch (fg) {
            .rgb => |c| {
                // After blur, center should be reduced (not pure white anymore)
                try std.testing.expect(c.r < 255 or c.g < 255 or c.b < 255);
            },
            else => try std.testing.expect(false),
        }
    }
}

test "applyBlur at buffer edge no panic" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Apply blur to area at buffer edge
    const area = Rect{ .x = 8, .y = 8, .width = 2, .height = 2 };
    const config = BlurConfig{ .radius = 1 };

    // Should not panic or crash
    applyBlur(&buf, area, config);
}

test "applyBlur preserves non-RGB named colors" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Fill 3x3 area with named color (not RGB)
    var y: u16 = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 2;
        while (x < 5) : (x += 1) {
            buf.set(x, y, .{
                .char = 'C',
                .style = .{ .fg = Color.red },
            });
        }
    }

    const area = Rect{ .x = 2, .y = 2, .width = 3, .height = 3 };
    const config = BlurConfig{ .radius = 1 };
    applyBlur(&buf, area, config);

    // Named colors should be unchanged
    y = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 2;
        while (x < 5) : (x += 1) {
            const cell = buf.getConst(x, y).?;
            try std.testing.expectEqual(Color.red, cell.style.fg.?);
        }
    }
}

test "applyBlur maintains non-null fg after blur" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Fill area with RGB colors
    const color1 = Color.fromRgb(100, 100, 100);
    const color2 = Color.fromRgb(200, 200, 200);

    var y: u16 = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 2;
        while (x < 5) : (x += 1) {
            const c = if ((x + y) % 2 == 0) color1 else color2;
            buf.set(x, y, .{
                .char = 'C',
                .style = .{ .fg = c },
            });
        }
    }

    const area = Rect{ .x = 2, .y = 2, .width = 3, .height = 3 };
    const config = BlurConfig{ .radius = 1 };
    applyBlur(&buf, area, config);

    // All cells should still have non-null foreground
    y = 2;
    while (y < 5) : (y += 1) {
        var x: u16 = 2;
        while (x < 5) : (x += 1) {
            const cell = buf.getConst(x, y).?;
            try std.testing.expect(cell.style.fg != null);
        }
    }
}

test "applyTransparency alpha 1.0 no change" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Set cell with RGB color
    const original_color = Color.fromRgb(100, 150, 200);
    buf.set(5, 5, .{
        .char = 'A',
        .style = .{ .fg = original_color },
    });

    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    const config = TransparencyConfig{ .alpha = 1.0, .background = Color.black };
    applyTransparency(&buf, area, config);

    // With alpha=1.0 (fully opaque), color should be unchanged
    const cell = buf.getConst(5, 5).?;
    if (cell.style.fg) |fg| {
        switch (fg) {
            .rgb => |c| {
                try std.testing.expectEqual(@as(u8, 100), c.r);
                try std.testing.expectEqual(@as(u8, 150), c.g);
                try std.testing.expectEqual(@as(u8, 200), c.b);
            },
            else => try std.testing.expect(false),
        }
    }
}

test "applyTransparency alpha 0.0 becomes background" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Set cell with RGB color
    const fg_color = Color.fromRgb(255, 0, 0);
    buf.set(5, 5, .{
        .char = 'T',
        .style = .{ .fg = fg_color },
    });

    const bg_color = Color.fromRgb(50, 50, 50);
    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    const config = TransparencyConfig{ .alpha = 0.0, .background = bg_color };
    applyTransparency(&buf, area, config);

    // With alpha=0.0 (fully transparent), color should become background
    const cell = buf.getConst(5, 5).?;
    if (cell.style.fg) |fg| {
        switch (fg) {
            .rgb => |c| {
                try std.testing.expectEqual(@as(u8, 50), c.r);
                try std.testing.expectEqual(@as(u8, 50), c.g);
                try std.testing.expectEqual(@as(u8, 50), c.b);
            },
            else => try std.testing.expect(false),
        }
    }
}

test "applyTransparency alpha 0.0 with null background becomes black" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Set cell with RGB color
    const fg_color = Color.fromRgb(200, 100, 50);
    buf.set(5, 5, .{
        .char = 'N',
        .style = .{ .fg = fg_color },
    });

    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    const config = TransparencyConfig{ .alpha = 0.0, .background = null };
    applyTransparency(&buf, area, config);

    // With alpha=0.0 and background=null, should blend to black
    const cell = buf.getConst(5, 5).?;
    if (cell.style.fg) |fg| {
        switch (fg) {
            .rgb => |c| {
                try std.testing.expectEqual(@as(u8, 0), c.r);
                try std.testing.expectEqual(@as(u8, 0), c.g);
                try std.testing.expectEqual(@as(u8, 0), c.b);
            },
            else => try std.testing.expect(false),
        }
    }
}

test "applyTransparency alpha 0.5 midpoint blend" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Set cell with RGB color
    const fg_color = Color.fromRgb(200, 100, 0);
    buf.set(5, 5, .{
        .char = 'M',
        .style = .{ .fg = fg_color },
    });

    const bg_color = Color.fromRgb(0, 100, 200);
    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    const config = TransparencyConfig{ .alpha = 0.5, .background = bg_color };
    applyTransparency(&buf, area, config);

    // With alpha=0.5, should be midpoint: (200+0)/2=100, (100+100)/2=100, (0+200)/2=100
    const cell = buf.getConst(5, 5).?;
    if (cell.style.fg) |fg| {
        switch (fg) {
            .rgb => |c| {
                // Allow 1 unit rounding error
                try std.testing.expect(c.r >= 99 and c.r <= 101);
                try std.testing.expectEqual(@as(u8, 100), c.g);
                try std.testing.expect(c.b >= 99 and c.b <= 101);
            },
            else => try std.testing.expect(false),
        }
    }
}

test "applyTransparency preserves non-RGB colors" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Set cells with named colors
    buf.set(5, 5, .{
        .char = 'C',
        .style = .{ .fg = Color.blue },
    });
    buf.set(6, 5, .{
        .char = 'C',
        .style = .{ .fg = Color.green },
    });

    const area = Rect{ .x = 5, .y = 5, .width = 2, .height = 1 };
    const config = TransparencyConfig{ .alpha = 0.5, .background = Color.red };
    applyTransparency(&buf, area, config);

    // Named colors should be unchanged
    try std.testing.expectEqual(Color.blue, buf.getConst(5, 5).?.style.fg.?);
    try std.testing.expectEqual(Color.green, buf.getConst(6, 5).?.style.fg.?);
}

test "applyTransparency empty area no panic" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Apply to empty area (width=0)
    const area = Rect{ .x = 5, .y = 5, .width = 0, .height = 1 };
    const config = TransparencyConfig{ .alpha = 0.5, .background = Color.white };

    // Should not panic
    applyTransparency(&buf, area, config);
}

test "applyTransparency zero height no panic" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Apply to empty area (height=0)
    const area = Rect{ .x = 5, .y = 5, .width = 5, .height = 0 };
    const config = TransparencyConfig{ .alpha = 0.5, .background = Color.white };

    // Should not panic
    applyTransparency(&buf, area, config);
}

test "applyTransparency at buffer boundary no panic" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Apply to area at buffer edge
    const area = Rect{ .x = 8, .y = 8, .width = 2, .height = 2 };
    const config = TransparencyConfig{ .alpha = 0.5, .background = Color.white };

    // Should not panic
    applyTransparency(&buf, area, config);
}
