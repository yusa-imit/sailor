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

    const area = Rect.new(2, 2, 5, 3);
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

    const area = Rect.new(4, 2, 4, 3);
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

    const area = Rect.new(2, 3, 4, 3);
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

    const area = Rect.new(4, 4, 3, 3);
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

    const area = Rect.new(2, 2, 5, 3);
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

    const area = Rect.new(2, 2, 5, 3);
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

    const area = Rect.new(2, 2, 4, 3);
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
    const area = Rect.new(4, 3, 4, 3);
    const shadow = ShadowStyle{ .depth = 2, .direction = .bottom_right };

    // Should not panic, shadow clipped at buffer boundaries
    renderShadow(&buf, area, shadow);
}

test "applyBorderEffect raised" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    // Create a border area
    const area = Rect.new(2, 2, 6, 4);

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

    const area = Rect.new(2, 2, 6, 4);

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

    const area = Rect.new(2, 2, 6, 4);
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
    const area = Rect.new(2, 2, 1, 1);
    const effect = BorderStyle3D.raised_button;

    // Should not panic
    applyBorderEffect(&buf, area, effect, .{});
}
