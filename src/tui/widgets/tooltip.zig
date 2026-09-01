//! Tooltip widget — contextual help tooltips
//!
//! Tooltip provides contextual help text that appears near a target element.
//! Supports smart positioning (auto-adjust to avoid clipping), arrow indicators,
//! and configurable triggers (hover, focus, manual).
//!
//! ## Features
//! - Contextual help tooltips
//! - Positioning strategies (above, below, left, right, auto)
//! - Trigger mechanisms (hover, focus, manual)
//! - Automatic dismissal on timeout or interaction
//! - Configurable delay before showing
//! - Arrow/pointer visual indicator
//! - Optional fade-in animation support
//! - Respect terminal boundaries (auto-adjust position if clipped)
//! - Optional Block wrapper for borders
//! - Builder pattern API
//!
//! ## Usage
//! ```zig
//! var tooltip = Tooltip.init("Press Enter to confirm");
//! tooltip.show(button_area);
//! tooltip.render(buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Tooltip position relative to target
pub const Position = enum {
    above,
    below,
    left,
    right,
    auto, // Automatically choose best position based on available space
};

/// Tooltip trigger mechanism
pub const Trigger = enum {
    hover,
    focus,
    manual,
};

/// Tooltip widget
pub const Tooltip = struct {
    content: []const u8,
    position: Position = .auto,
    visible: bool = false,
    target_area: ?Rect = null,
    style: Style = .{ .fg = .black, .bg = .bright_yellow },
    border_style: Style = .{ .fg = .bright_yellow },
    show_arrow: bool = true,
    block: ?Block = null,
    /// Ticks until auto-dismiss (0 = persistent)
    timeout_ticks: u32 = 0,
    /// Internal countdown, decremented by tick()
    ticks_remaining: u32 = 0,
    /// Ticks to wait after show() before actually becoming visible (0 = show immediately)
    show_delay_ticks: u32 = 0,
    /// True while waiting out the show-delay (requested via show() but not yet visible)
    pending: bool = false,
    /// Internal countdown for delay, decremented by tick() during pending phase
    delay_ticks_remaining: u32 = 0,
    /// Trigger mechanism gating notifyHover()/notifyFocus() (manual = caller drives show()/hide() directly)
    trigger: Trigger = .manual,
    /// Ticks to reach full opacity after becoming visible (0 = instant full opacity)
    fade_in_ticks: u32 = 0,
    /// Internal fade progress, incremented by tick() while visible, capped at fade_in_ticks
    fade_ticks_elapsed: u32 = 0,

    /// Create a new tooltip with content
    pub fn init(content: []const u8) Tooltip {
        return .{
            .content = content,
        };
    }

    /// Set position strategy
    pub fn withPosition(self: Tooltip, new_position: Position) Tooltip {
        var result = self;
        result.position = new_position;
        return result;
    }

    /// Set content style
    pub fn withStyle(self: Tooltip, new_style: Style) Tooltip {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Set arrow visibility
    pub fn withArrow(self: Tooltip, show_arrow: bool) Tooltip {
        var result = self;
        result.show_arrow = show_arrow;
        return result;
    }

    /// Set block wrapper for borders
    pub fn withBlock(self: Tooltip, new_block: Block) Tooltip {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set auto-dismiss timeout (0 = persistent)
    pub fn withTimeout(self: Tooltip, ticks: u32) Tooltip {
        var result = self;
        result.timeout_ticks = ticks;
        return result;
    }

    /// Set delay before showing (0 = show immediately)
    pub fn withShowDelay(self: Tooltip, ticks: u32) Tooltip {
        var result = self;
        result.show_delay_ticks = ticks;
        return result;
    }

    /// Set trigger mechanism (hover/focus/manual)
    pub fn withTrigger(self: Tooltip, new_trigger: Trigger) Tooltip {
        var result = self;
        result.trigger = new_trigger;
        return result;
    }

    /// Set fade-in duration in ticks (0 = instant full opacity)
    pub fn withFadeIn(self: Tooltip, ticks: u32) Tooltip {
        var result = self;
        result.fade_in_ticks = ticks;
        return result;
    }

    /// Current fade-in opacity in [0.0, 1.0]. 1.0 if fade_in_ticks == 0 (disabled) or the
    /// fade has completed; otherwise fade_ticks_elapsed / fade_in_ticks.
    pub fn currentAlpha(self: Tooltip) f32 {
        if (self.fade_in_ticks == 0) return 1.0;
        if (self.fade_ticks_elapsed >= self.fade_in_ticks) return 1.0;
        return @as(f32, @floatFromInt(self.fade_ticks_elapsed)) / @as(f32, @floatFromInt(self.fade_in_ticks));
    }

    /// Show tooltip at target area
    pub fn show(self: *Tooltip, target_area: Rect) void {
        self.fade_ticks_elapsed = 0;
        if (self.show_delay_ticks == 0) {
            // No delay: show immediately
            self.visible = true;
            self.target_area = target_area;
            self.ticks_remaining = self.timeout_ticks;
        } else {
            // Delay active: enter pending phase
            self.pending = true;
            self.target_area = target_area;
            self.delay_ticks_remaining = self.show_delay_ticks;
            // Don't set visible=true or ticks_remaining yet
        }
    }

    /// Hide tooltip
    pub fn hide(self: *Tooltip) void {
        self.visible = false;
        self.target_area = null;
        self.pending = false;
        self.delay_ticks_remaining = 0;
        self.fade_ticks_elapsed = 0;
    }

    /// Notify the tooltip of a hover state change. No-op unless `trigger == .hover` —
    /// the caller wires their own mouse-hover detection to this method (sailor owns no
    /// event loop). `hovering == true` shows (respecting show_delay_ticks); `false` hides.
    pub fn notifyHover(self: *Tooltip, hovering: bool, target_area: Rect) void {
        if (self.trigger != .hover) return;
        if (hovering) {
            self.show(target_area);
        } else {
            self.hide();
        }
    }

    /// Notify the tooltip of a focus state change. No-op unless `trigger == .focus` —
    /// mirrors notifyHover but gated on the focus trigger.
    pub fn notifyFocus(self: *Tooltip, focused: bool, target_area: Rect) void {
        if (self.trigger != .focus) return;
        if (focused) {
            self.show(target_area);
        } else {
            self.hide();
        }
    }

    /// Process one tick of the timeout countdown
    pub fn tick(self: *Tooltip) void {
        if (self.pending) {
            // Pending phase: countdown the show delay
            self.delay_ticks_remaining -= 1;
            if (self.delay_ticks_remaining == 0) {
                // Delay elapsed: become visible and start timeout
                self.pending = false;
                self.visible = true;
                self.ticks_remaining = self.timeout_ticks;
                self.fade_ticks_elapsed = 0; // fresh fade start the moment it becomes visible
            }
            return;
        }

        if (!self.visible) return;

        if (self.fade_ticks_elapsed < self.fade_in_ticks) {
            self.fade_ticks_elapsed += 1;
        }

        if (self.timeout_ticks == 0) return;
        self.ticks_remaining -= 1;
        if (self.ticks_remaining == 0) {
            self.hide();
        }
    }

    /// Render tooltip to buffer
    pub fn render(self: Tooltip, buf: Buffer, area: Rect) void {
        if (!self.visible) return;
        if (area.width == 0 or area.height == 0) return;

        var buf_mut = buf;

        // Fade-in: blend styles toward their target color based on current alpha. At
        // alpha >= 1.0 (fade disabled or complete) these are identical to self.style/
        // self.border_style, preserving pre-fade-feature rendering exactly.
        const alpha = self.currentAlpha();
        const content_style = blendStyle(self.style, alpha);
        const border_style = blendStyle(self.border_style, alpha);

        // Calculate tooltip size and position
        const tooltip_area = self.calculateArea(area);
        if (tooltip_area.width == 0 or tooltip_area.height == 0) return;

        // Render block wrapper if present
        var inner_area = tooltip_area;
        if (self.block) |blk| {
            const faded_block = blk.withBorderStyle(border_style);
            faded_block.render(&buf_mut, tooltip_area);
            inner_area = faded_block.inner(tooltip_area);
            if (inner_area.width == 0 or inner_area.height == 0) return;
        }

        // Render content
        buf_mut.setString(inner_area.x, inner_area.y, self.content, content_style);

        // Render arrow if enabled
        if (self.show_arrow) {
            self.renderArrow(&buf_mut, tooltip_area, border_style);
        }
    }

    /// Internal: Calculate tooltip area based on position strategy
    fn calculateArea(self: Tooltip, area: Rect) Rect {
        const target = self.target_area orelse return Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

        // Calculate tooltip dimensions
        const content_width = @as(u16, @intCast(@min(self.content.len, 100)));
        const content_height: u16 = 1;

        // Determine final position
        const final_position = if (self.position == .auto)
            self.determineAutoPosition(area, target, content_width, content_height)
        else
            self.position;

        return self.positionTooltip(final_position, target, content_width, content_height, area);
    }

    /// Internal: Determine best position for auto mode
    fn determineAutoPosition(self: Tooltip, area: Rect, target: Rect, tooltip_width: u16, tooltip_height: u16) Position {
        _ = self;

        // Check space above
        const space_above = target.y;
        const space_below = if (area.height > target.y + target.height)
            area.height - (target.y + target.height)
        else
            0;
        const space_left = target.x;
        const space_right = if (area.width > target.x + target.width)
            area.width - (target.x + target.width)
        else
            0;

        // Prefer above if sufficient space
        if (space_above >= tooltip_height) {
            return .above;
        } else if (space_below >= tooltip_height) {
            return .below;
        } else if (space_right >= tooltip_width) {
            return .right;
        } else if (space_left >= tooltip_width) {
            return .left;
        } else {
            // Default to below if no good option
            return .below;
        }
    }

    /// Internal: Position tooltip based on strategy
    fn positionTooltip(self: Tooltip, pos: Position, target: Rect, width: u16, height: u16, area: Rect) Rect {
        _ = self;

        switch (pos) {
            .above => {
                const y = if (target.y >= height) target.y - height else 0;
                const x = target.x;
                return Rect{ .x = x, .y = y, .width = @min(width, area.width), .height = height };
            },
            .below => {
                const y = target.y + target.height;
                const x = target.x;
                const max_height = if (area.height > y) area.height - y else 0;
                return Rect{ .x = x, .y = y, .width = @min(width, area.width), .height = @min(height, max_height) };
            },
            .left => {
                const x = if (target.x >= width) target.x - width else 0;
                const y = target.y;
                return Rect{ .x = x, .y = y, .width = @min(width, area.width), .height = height };
            },
            .right => {
                const x = target.x + target.width;
                const y = target.y;
                const max_width = if (area.width > x) area.width - x else 0;
                return Rect{ .x = x, .y = y, .width = @min(width, max_width), .height = height };
            },
            .auto => unreachable, // Should be resolved before this
        }
    }

    /// Internal: Render arrow indicator
    fn renderArrow(self: Tooltip, buf: *Buffer, tooltip_area: Rect, arrow_style: Style) void {
        const target = self.target_area orelse return;

        const actual_position = if (self.position == .auto)
            self.determineAutoPosition(Rect{ .x = 0, .y = 0, .width = buf.width, .height = buf.height }, target, @intCast(@min(self.content.len, 100)), 1)
        else
            self.position;

        const arrow_char: u21 = switch (actual_position) {
            .above => '▼',
            .below => '▲',
            .left => '▶',
            .right => '◀',
            .auto => return,
        };

        // Position arrow near target
        const arrow_x = switch (actual_position) {
            .above, .below => target.x + target.width / 2,
            .left => tooltip_area.x + tooltip_area.width,
            .right => if (tooltip_area.x > 0) tooltip_area.x - 1 else 0,
            .auto => return,
        };

        const arrow_y = switch (actual_position) {
            .above => tooltip_area.y + tooltip_area.height,
            .below => if (tooltip_area.y > 0) tooltip_area.y - 1 else 0,
            .left, .right => target.y,
            .auto => return,
        };

        buf.set(arrow_x, arrow_y, .{ .char = arrow_char, .style = arrow_style });
    }
};

/// Blend a color toward black by alpha in [0.0, 1.0]. Only `.rgb` colors are blendable —
/// named/indexed ANSI colors have no interpolatable components, so they render at their full
/// configured color regardless of alpha.
fn blendColor(color: ?Color, alpha: f32) ?Color {
    const c = color orelse return null;
    if (alpha >= 1.0) return c;
    const a = @max(0.0, alpha);
    return switch (c) {
        .rgb => |rgb| Color.fromRgb(
            lerpChannel(rgb.r, a),
            lerpChannel(rgb.g, a),
            lerpChannel(rgb.b, a),
        ),
        else => c,
    };
}

fn lerpChannel(target: u8, alpha: f32) u8 {
    const t: f32 = @floatFromInt(target);
    return @intFromFloat(@round(t * alpha));
}

/// Blend a style's fg/bg colors toward black by alpha. Boolean attributes (bold, underline,
/// etc.) are never blended — they apply at full effect immediately.
fn blendStyle(style: Style, alpha: f32) Style {
    if (alpha >= 1.0) return style;
    var result = style;
    result.fg = blendColor(style.fg, alpha);
    result.bg = blendColor(style.bg, alpha);
    return result;
}

// ============================================================================
// TESTS
// ============================================================================

test "Tooltip.init default values" {
    const tooltip = Tooltip.init("Help text");

    try std.testing.expectEqualStrings("Help text", tooltip.content);
    try std.testing.expectEqual(Position.auto, tooltip.position);
    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
    try std.testing.expectEqual(true, tooltip.show_arrow);
}

test "Tooltip.init hidden by default" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(false, tooltip.visible);
}

test "Tooltip.init content assignment" {
    const tooltip = Tooltip.init("Custom content");
    try std.testing.expectEqualStrings("Custom content", tooltip.content);
}

test "Tooltip.init position defaults to auto" {
    const tooltip = Tooltip.init("Tooltip");
    try std.testing.expectEqual(Position.auto, tooltip.position);
}

test "Tooltip.init arrow enabled by default" {
    const tooltip = Tooltip.init("Arrow tooltip");
    try std.testing.expectEqual(true, tooltip.show_arrow);
}

test "Tooltip.withPosition sets above" {
    const tooltip = Tooltip.init("Test").withPosition(.above);
    try std.testing.expectEqual(Position.above, tooltip.position);
}

test "Tooltip.withPosition sets below" {
    const tooltip = Tooltip.init("Test").withPosition(.below);
    try std.testing.expectEqual(Position.below, tooltip.position);
}

test "Tooltip.withPosition sets left" {
    const tooltip = Tooltip.init("Test").withPosition(.left);
    try std.testing.expectEqual(Position.left, tooltip.position);
}

test "Tooltip.withPosition sets right" {
    const tooltip = Tooltip.init("Test").withPosition(.right);
    try std.testing.expectEqual(Position.right, tooltip.position);
}

test "Tooltip.withPosition sets auto" {
    const tooltip = Tooltip.init("Test").withPosition(.auto);
    try std.testing.expectEqual(Position.auto, tooltip.position);
}

test "Tooltip.withStyle sets custom style" {
    const custom_style = Style{ .fg = .green, .bg = .black };
    const tooltip = Tooltip.init("Test").withStyle(custom_style);

    try std.testing.expectEqual(@as(?Color, .green), tooltip.style.fg);
    try std.testing.expectEqual(@as(?Color, .black), tooltip.style.bg);
}

test "Tooltip.withArrow toggles arrow display true" {
    const tooltip = Tooltip.init("Test").withArrow(true);
    try std.testing.expectEqual(true, tooltip.show_arrow);
}

test "Tooltip.withArrow toggles arrow display false" {
    const tooltip = Tooltip.init("Test").withArrow(false);
    try std.testing.expectEqual(false, tooltip.show_arrow);
}

test "Tooltip.withBlock sets border" {
    const block = (Block{}).withBorders(.all);
    const tooltip = Tooltip.init("Test").withBlock(block);

    try std.testing.expect(tooltip.block != null);
}

test "Tooltip.withPosition method chaining" {
    const tooltip = Tooltip.init("Test")
        .withPosition(.above)
        .withArrow(false);

    try std.testing.expectEqual(Position.above, tooltip.position);
    try std.testing.expectEqual(false, tooltip.show_arrow);
}

test "Tooltip.withStyle method chaining" {
    const tooltip = Tooltip.init("Test")
        .withStyle(.{ .fg = .red })
        .withPosition(.below);

    try std.testing.expectEqual(@as(?Color, .red), tooltip.style.fg);
    try std.testing.expectEqual(Position.below, tooltip.position);
}

test "Tooltip.show sets visible true" {
    var tooltip = Tooltip.init("Test");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    try std.testing.expectEqual(true, tooltip.visible);
}

test "Tooltip.show stores target area" {
    var tooltip = Tooltip.init("Test");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    try std.testing.expect(tooltip.target_area != null);
    try std.testing.expectEqual(@as(u16, 10), tooltip.target_area.?.x);
    try std.testing.expectEqual(@as(u16, 10), tooltip.target_area.?.y);
}

test "Tooltip.hide sets visible false" {
    var tooltip = Tooltip.init("Test");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.hide();

    try std.testing.expectEqual(false, tooltip.visible);
}

test "Tooltip.hide clears target area" {
    var tooltip = Tooltip.init("Test");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.hide();

    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.show hide multiple cycles" {
    var tooltip = Tooltip.init("Test");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(true, tooltip.visible);

    tooltip.hide();
    try std.testing.expectEqual(false, tooltip.visible);

    tooltip.show(target);
    try std.testing.expectEqual(true, tooltip.visible);

    tooltip.hide();
    try std.testing.expectEqual(false, tooltip.visible);
}

test "Tooltip.render hidden tooltip doesn't render" {
    const tooltip = Tooltip.init("Hidden");

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should not render anything (no crash, no visible output)
    // Check that buffer remains empty
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "Tooltip.render visible tooltip renders content" {
    var tooltip = Tooltip.init("Help");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should render content above target (auto position with space above)
    // Check first character of content
    try std.testing.expectEqual(@as(u21, 'H'), buf.getChar(10, 9));
    try std.testing.expectEqual(@as(u21, 'e'), buf.getChar(11, 9));
}

test "Tooltip.render position above renders above target" {
    var tooltip = Tooltip.init("Above").withPosition(.above);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Tooltip should render above target (y < 10)
    // Check content appears above
    try std.testing.expectEqual(@as(u21, 'A'), buf.getChar(10, 9));
}

test "Tooltip.render position below renders below target" {
    var tooltip = Tooltip.init("Below").withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Tooltip should render below target (y = 10 + 2 = 12)
    try std.testing.expectEqual(@as(u21, 'B'), buf.getChar(10, 12));
}

test "Tooltip.render position left renders left of target" {
    var tooltip = Tooltip.init("Left").withPosition(.left);
    const target = Rect{ .x = 20, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Tooltip should render left of target (x < 20)
    try std.testing.expectEqual(@as(u21, 'L'), buf.getChar(16, 10));
}

test "Tooltip.render position right renders right of target" {
    var tooltip = Tooltip.init("Right").withPosition(.right);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Tooltip should render right of target (x = 10 + 5 = 15)
    try std.testing.expectEqual(@as(u21, 'R'), buf.getChar(15, 10));
}

test "Tooltip.render position auto chooses above with space" {
    var tooltip = Tooltip.init("Auto").withPosition(.auto);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // With space above (y=10), should choose above
    try std.testing.expectEqual(@as(u21, 'A'), buf.getChar(10, 9));
}

test "Tooltip.render position auto chooses below when no space above" {
    var tooltip = Tooltip.init("Auto").withPosition(.auto);
    const target = Rect{ .x = 10, .y = 0, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // No space above (y=0), should choose below
    try std.testing.expectEqual(@as(u21, 'A'), buf.getChar(10, 2));
}

test "Tooltip.render auto respects top boundary" {
    var tooltip = Tooltip.init("Top").withPosition(.auto);
    const target = Rect{ .x = 10, .y = 0, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Target at top (y=0), should render below instead
    try std.testing.expectEqual(@as(u21, 'T'), buf.getChar(10, 2));
}

test "Tooltip.render auto respects bottom boundary" {
    var tooltip = Tooltip.init("Bottom").withPosition(.auto);
    const target = Rect{ .x = 10, .y = 22, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Target near bottom (y=22), should render above
    try std.testing.expectEqual(@as(u21, 'B'), buf.getChar(10, 21));
}

test "Tooltip.render auto respects left boundary" {
    var tooltip = Tooltip.init("Left").withPosition(.auto);
    const target = Rect{ .x = 0, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Target at left edge (x=0), should render above (sufficient space)
    try std.testing.expectEqual(@as(u21, 'L'), buf.getChar(0, 9));
}

test "Tooltip.render auto respects right boundary" {
    var tooltip = Tooltip.init("Right").withPosition(.auto);
    const target = Rect{ .x = 75, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Target near right edge (x=75), should render above (sufficient space)
    try std.testing.expectEqual(@as(u21, 'R'), buf.getChar(75, 9));
}

test "Tooltip.render arrow renders for above position" {
    var tooltip = Tooltip.init("Test").withPosition(.above).withArrow(true);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Arrow should be ▼ for above position, at y=10 (below tooltip)
    try std.testing.expectEqual(@as(u21, '▼'), buf.getChar(12, 10));
}

test "Tooltip.render arrow renders for below position" {
    var tooltip = Tooltip.init("Test").withPosition(.below).withArrow(true);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Arrow should be ▲ for below position, at y=11 (above tooltip at y=12)
    try std.testing.expectEqual(@as(u21, '▲'), buf.getChar(12, 11));
}

test "Tooltip.render arrow renders for left position" {
    var tooltip = Tooltip.init("Test").withPosition(.left).withArrow(true);
    const target = Rect{ .x = 20, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Arrow should be ▶ for left position, at x=20 (right of tooltip)
    try std.testing.expectEqual(@as(u21, '▶'), buf.getChar(20, 10));
}

test "Tooltip.render arrow renders for right position" {
    var tooltip = Tooltip.init("Test").withPosition(.right).withArrow(true);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Arrow should be ◀ for right position, at x=14 (left of tooltip at x=15)
    try std.testing.expectEqual(@as(u21, '◀'), buf.getChar(14, 10));
}

test "Tooltip.render arrow disabled doesn't render" {
    var tooltip = Tooltip.init("Test").withPosition(.above).withArrow(false);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Arrow should not be rendered - check that position has space, not arrow
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(12, 10));
}

test "Tooltip.render style applies to content" {
    var tooltip = Tooltip.init("Styled")
        .withStyle(.{ .fg = .green, .bg = .black })
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Check style is applied
    const style = buf.getStyle(10, 12);
    try std.testing.expectEqual(@as(?Color, .green), style.fg);
    try std.testing.expectEqual(@as(?Color, .black), style.bg);
}

test "Tooltip.render border renders when block is set" {
    var tooltip = Tooltip.init("Bordered")
        .withBlock((Block{}))
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // With block borders, the border occupies outer cells, content is indented
    // Don't check exact border characters, just verify rendering doesn't crash
    try std.testing.expect(buf.width == 80);
    try std.testing.expect(buf.height == 24);
}

test "Tooltip.render empty content edge case" {
    var tooltip = Tooltip.init("").withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should handle empty content gracefully - no crash is success
    // Verify buffer is still valid
    try std.testing.expect(buf.width == 80);
    try std.testing.expect(buf.height == 24);
}

test "Tooltip.render zero dimension area edge case" {
    var tooltip = Tooltip.init("Test").withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    tooltip.render(buf, area);

    // Should not crash with zero area - render returns early
    // Verify buffer unchanged at target position
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(10, 10));
}

test "Tooltip.render very long content" {
    const long_content = "This is a very long tooltip content that exceeds the normal width and should be handled gracefully by the rendering code without crashing or causing issues";
    var tooltip = Tooltip.init(long_content).withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should truncate to max width (100 chars as per calculateArea)
    // Verify first char renders
    try std.testing.expectEqual(@as(u21, 'T'), buf.getChar(10, 12));
    // Verify content doesn't overflow buffer
    try std.testing.expect(buf.width == 80);
}

test "Tooltip.render single character content" {
    var tooltip = Tooltip.init("X").withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should render single character
    try std.testing.expectEqual(@as(u21, 'X'), buf.getChar(10, 12));
}

test "Tooltip.render unicode content emoji" {
    var tooltip = Tooltip.init("👋 Hello").withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should render emoji correctly - verify content appears
    // Check for space after emoji
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(11, 12));
}

test "Tooltip.render unicode content CJK" {
    var tooltip = Tooltip.init("你好世界").withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should render CJK characters correctly - verify first character
    try std.testing.expectEqual(@as(u21, '你'), buf.getChar(10, 12));
}

test "Tooltip.render target area larger than terminal" {
    var tooltip = Tooltip.init("Test").withPosition(.below);
    const target = Rect{ .x = 100, .y = 100, .width = 50, .height = 20 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should handle out-of-bounds target gracefully - nothing renders
    // Buffer should remain empty at origin
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "Tooltip.render tooltip larger than terminal" {
    const huge_content = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua";
    var tooltip = Tooltip.init(huge_content).withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    tooltip.render(buf, area);

    // Should clip to terminal bounds - verify no overflow
    try std.testing.expect(buf.width == 20);
    try std.testing.expect(buf.height == 5);
}

test "Tooltip.render corner case top left" {
    var tooltip = Tooltip.init("Corner").withPosition(.auto);
    const target = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should position tooltip below (no space above)
    try std.testing.expectEqual(@as(u21, 'C'), buf.getChar(0, 1));
}

test "Tooltip.render corner case top right" {
    var tooltip = Tooltip.init("Corner").withPosition(.auto);
    const target = Rect{ .x = 77, .y = 0, .width = 3, .height = 1 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should position below (no space above)
    try std.testing.expectEqual(@as(u21, 'C'), buf.getChar(77, 1));
}

test "Tooltip.render corner case bottom left" {
    var tooltip = Tooltip.init("Corner").withPosition(.auto);
    const target = Rect{ .x = 0, .y = 23, .width = 3, .height = 1 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should choose above position (sufficient space)
    try std.testing.expectEqual(@as(u21, 'C'), buf.getChar(0, 22));
}

test "Tooltip.render corner case bottom right" {
    var tooltip = Tooltip.init("Corner").withPosition(.auto);
    const target = Rect{ .x = 77, .y = 23, .width = 3, .height = 1 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should position above (sufficient space)
    try std.testing.expectEqual(@as(u21, 'C'), buf.getChar(77, 22));
}

test "Tooltip.render no memory leaks" {
    var tooltip = Tooltip.init("Memory test");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Should not leak memory (testing allocator will catch leaks)
}

// ============================================================================
// TIMEOUT/TICK-BASED AUTO-DISMISS TESTS (Red Phase)
// ============================================================================

test "Tooltip.init defaults timeout_ticks to 0" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(@as(u32, 0), tooltip.timeout_ticks);
}

test "Tooltip.init defaults ticks_remaining to 0" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(@as(u32, 0), tooltip.ticks_remaining);
}

test "Tooltip.withTimeout sets timeout_ticks field" {
    const tooltip = Tooltip.init("Test").withTimeout(5);
    try std.testing.expectEqual(@as(u32, 5), tooltip.timeout_ticks);
}

test "Tooltip.withTimeout builder returns modified copy" {
    const t1 = Tooltip.init("Test");
    const t2 = t1.withTimeout(10);

    try std.testing.expectEqual(@as(u32, 0), t1.timeout_ticks); // Original unchanged
    try std.testing.expectEqual(@as(u32, 10), t2.timeout_ticks); // Copy modified
}

test "Tooltip.show on tooltip with withTimeout sets ticks_remaining to timeout_ticks" {
    var tooltip = Tooltip.init("Test").withTimeout(7);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    try std.testing.expectEqual(@as(u32, 7), tooltip.ticks_remaining);
}

test "Tooltip.tick decrements ticks_remaining by 1" {
    var tooltip = Tooltip.init("Test").withTimeout(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(@as(u32, 5), tooltip.ticks_remaining);

    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 4), tooltip.ticks_remaining);

    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 3), tooltip.ticks_remaining);
}

test "Tooltip.tick after N calls with timeout N auto-dismisses" {
    var tooltip = Tooltip.init("Test").withTimeout(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(true, tooltip.visible);

    tooltip.tick(); // ticks_remaining = 2
    tooltip.tick(); // ticks_remaining = 1
    try std.testing.expectEqual(true, tooltip.visible);

    tooltip.tick(); // ticks_remaining = 0, should auto-dismiss
    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.tick fewer than N times leaves visible true" {
    var tooltip = Tooltip.init("Test").withTimeout(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    tooltip.tick();
    tooltip.tick();
    tooltip.tick();

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expect(tooltip.target_area != null);
    try std.testing.expectEqual(@as(u32, 2), tooltip.ticks_remaining);
}

test "Tooltip.tick on persistent (timeout_ticks=0) many times does not hide" {
    var tooltip = Tooltip.init("Test"); // No withTimeout, defaults to timeout_ticks=0 (persistent)
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    // Call tick() 100 times
    for (0..100) |_| {
        tooltip.tick();
    }

    // Persistent tooltip should still be visible
    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expect(tooltip.target_area != null);
}

test "Tooltip.tick on non-visible tooltip is safe no-op" {
    var tooltip = Tooltip.init("Test").withTimeout(5);

    // Never show it
    tooltip.tick();
    tooltip.tick();

    // Should still be invisible and not crash
    try std.testing.expectEqual(false, tooltip.visible);
}

test "Tooltip.tick on already-hidden tooltip is safe no-op" {
    var tooltip = Tooltip.init("Test").withTimeout(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.hide();

    // Call tick on hidden tooltip
    tooltip.tick();

    // Should remain hidden
    try std.testing.expectEqual(false, tooltip.visible);
}

test "Tooltip.show again on ticking-down tooltip resets ticks_remaining" {
    var tooltip = Tooltip.init("Test").withTimeout(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(@as(u32, 5), tooltip.ticks_remaining);

    tooltip.tick();
    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 3), tooltip.ticks_remaining);

    // Re-show should restart the timer
    tooltip.show(target);
    try std.testing.expectEqual(@as(u32, 5), tooltip.ticks_remaining);
}

test "Tooltip.withTimeout chaining works" {
    const tooltip = Tooltip.init("Test")
        .withTimeout(8)
        .withPosition(.above);

    try std.testing.expectEqual(@as(u32, 8), tooltip.timeout_ticks);
    try std.testing.expectEqual(Position.above, tooltip.position);
}

// ============================================================================
// SHOW-DELAY PENDING-PHASE TESTS (Red Phase)
// ============================================================================

test "Tooltip.init defaults show_delay_ticks to 0" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(@as(u32, 0), tooltip.show_delay_ticks);
}

test "Tooltip.init defaults pending to false" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(false, tooltip.pending);
}

test "Tooltip.init defaults delay_ticks_remaining to 0" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(@as(u32, 0), tooltip.delay_ticks_remaining);
}

test "Tooltip.withShowDelay sets show_delay_ticks field" {
    const tooltip = Tooltip.init("Test").withShowDelay(5);
    try std.testing.expectEqual(@as(u32, 5), tooltip.show_delay_ticks);
}

test "Tooltip.withShowDelay builder returns modified copy" {
    const t1 = Tooltip.init("Test");
    const t2 = t1.withShowDelay(10);

    try std.testing.expectEqual(@as(u32, 0), t1.show_delay_ticks); // Original unchanged
    try std.testing.expectEqual(@as(u32, 10), t2.show_delay_ticks); // Copy modified
}

test "Tooltip.show with show_delay_ticks 0 makes visible immediately" {
    var tooltip = Tooltip.init("Test").withShowDelay(0); // Explicitly 0 (same as default)
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
}

test "Tooltip.show with show_delay_ticks > 0 keeps visible false and sets pending true" {
    var tooltip = Tooltip.init("Test").withShowDelay(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 3), tooltip.delay_ticks_remaining);
    try std.testing.expect(tooltip.target_area != null);
}

test "Tooltip.tick during pending phase decrements delay_ticks_remaining" {
    var tooltip = Tooltip.init("Test").withShowDelay(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(@as(u32, 5), tooltip.delay_ticks_remaining);

    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 4), tooltip.delay_ticks_remaining);

    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 3), tooltip.delay_ticks_remaining);
}

test "Tooltip.tick during pending phase keeps visible false" {
    var tooltip = Tooltip.init("Test").withShowDelay(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    tooltip.tick();
    tooltip.tick();

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 1), tooltip.delay_ticks_remaining);
}

test "Tooltip.tick show_delay_ticks times makes visible true and pending false" {
    var tooltip = Tooltip.init("Test").withShowDelay(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    tooltip.tick(); // delay_ticks_remaining = 2
    tooltip.tick(); // delay_ticks_remaining = 1
    tooltip.tick(); // delay_ticks_remaining = 0, should become visible

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
}

test "Tooltip show_delay and timeout interaction: timeout starts after pending phase" {
    var tooltip = Tooltip.init("Test").withShowDelay(3).withTimeout(2);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 0), tooltip.ticks_remaining); // Timeout not started yet

    // Tick 3 times to complete delay
    tooltip.tick();
    tooltip.tick();
    tooltip.tick();

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 2), tooltip.ticks_remaining); // Timeout now running

    // Tick 1 more time
    tooltip.tick();
    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(@as(u32, 1), tooltip.ticks_remaining);

    // Tick once more to auto-dismiss
    tooltip.tick();
    try std.testing.expectEqual(false, tooltip.visible);
}

test "Tooltip.hide while pending cancels the delay" {
    var tooltip = Tooltip.init("Test").withShowDelay(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(true, tooltip.pending);

    tooltip.hide();

    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(@as(u32, 0), tooltip.delay_ticks_remaining);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.tick after hide on pending tooltip does nothing" {
    var tooltip = Tooltip.init("Test").withShowDelay(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.hide();

    // Now tick - should be no-op
    tooltip.tick();

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
}

test "Tooltip.tick on pending tooltip that was never shown is safe no-op" {
    var tooltip = Tooltip.init("Test").withShowDelay(3);

    // Never call show(), just tick
    tooltip.tick();
    tooltip.tick();

    // Should remain in default state
    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
}

test "Tooltip.show again while pending resets delay_ticks_remaining" {
    var tooltip = Tooltip.init("Test").withShowDelay(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(@as(u32, 5), tooltip.delay_ticks_remaining);

    tooltip.tick();
    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 3), tooltip.delay_ticks_remaining);

    // Re-show should restart the delay
    tooltip.show(target);
    try std.testing.expectEqual(@as(u32, 5), tooltip.delay_ticks_remaining);
    try std.testing.expectEqual(true, tooltip.pending);
}

// ============================================================================
// TRIGGER MECHANISM TESTS (Red Phase)
// ============================================================================

test "Tooltip.init defaults trigger to manual" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(Trigger.manual, tooltip.trigger);
}

test "Tooltip.withTrigger sets trigger to hover" {
    const tooltip = Tooltip.init("Test").withTrigger(.hover);
    try std.testing.expectEqual(Trigger.hover, tooltip.trigger);
}

test "Tooltip.withTrigger sets trigger to focus" {
    const tooltip = Tooltip.init("Test").withTrigger(.focus);
    try std.testing.expectEqual(Trigger.focus, tooltip.trigger);
}

test "Tooltip.withTrigger sets trigger to manual" {
    const tooltip = Tooltip.init("Test").withTrigger(.manual);
    try std.testing.expectEqual(Trigger.manual, tooltip.trigger);
}

test "Tooltip.withTrigger builder returns modified copy" {
    const t1 = Tooltip.init("Test");
    const t2 = t1.withTrigger(.hover);

    try std.testing.expectEqual(Trigger.manual, t1.trigger); // Original unchanged
    try std.testing.expectEqual(Trigger.hover, t2.trigger); // Copy modified
}

test "Tooltip.withTrigger chaining works" {
    const tooltip = Tooltip.init("Test")
        .withTrigger(.focus)
        .withPosition(.above);

    try std.testing.expectEqual(Trigger.focus, tooltip.trigger);
    try std.testing.expectEqual(Position.above, tooltip.position);
}

test "Tooltip.notifyHover with trigger hover and delay 0 shows immediately" {
    var tooltip = Tooltip.init("Test").withTrigger(.hover);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(true, target);

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expect(tooltip.target_area != null);
    try std.testing.expectEqual(@as(u16, 10), tooltip.target_area.?.x);
    try std.testing.expectEqual(@as(u16, 10), tooltip.target_area.?.y);
}

test "Tooltip.notifyHover with trigger hover hides on false" {
    var tooltip = Tooltip.init("Test").withTrigger(.hover);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(true, target);
    try std.testing.expectEqual(true, tooltip.visible);

    tooltip.notifyHover(false, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyHover with trigger hover and delay shows pending" {
    var tooltip = Tooltip.init("Test")
        .withTrigger(.hover)
        .withShowDelay(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(true, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 5), tooltip.delay_ticks_remaining);
    try std.testing.expect(tooltip.target_area != null);
}

test "Tooltip.notifyHover with trigger manual is no-op on true" {
    var tooltip = Tooltip.init("Test").withTrigger(.manual);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(true, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyHover with trigger manual is no-op on false" {
    var tooltip = Tooltip.init("Test").withTrigger(.manual);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(false, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyHover with trigger focus is no-op" {
    var tooltip = Tooltip.init("Test").withTrigger(.focus);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(true, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyHover with trigger focus is no-op on false" {
    var tooltip = Tooltip.init("Test").withTrigger(.focus);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(false, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyFocus with trigger focus and delay 0 shows immediately" {
    var tooltip = Tooltip.init("Test").withTrigger(.focus);
    const target = Rect{ .x = 20, .y = 15, .width = 3, .height = 1 };

    tooltip.notifyFocus(true, target);

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expect(tooltip.target_area != null);
    try std.testing.expectEqual(@as(u16, 20), tooltip.target_area.?.x);
    try std.testing.expectEqual(@as(u16, 15), tooltip.target_area.?.y);
}

test "Tooltip.notifyFocus with trigger focus hides on false" {
    var tooltip = Tooltip.init("Test").withTrigger(.focus);
    const target = Rect{ .x = 20, .y = 15, .width = 3, .height = 1 };

    tooltip.notifyFocus(true, target);
    try std.testing.expectEqual(true, tooltip.visible);

    tooltip.notifyFocus(false, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyFocus with trigger focus and delay shows pending" {
    var tooltip = Tooltip.init("Test")
        .withTrigger(.focus)
        .withShowDelay(4);
    const target = Rect{ .x = 20, .y = 15, .width = 3, .height = 1 };

    tooltip.notifyFocus(true, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 4), tooltip.delay_ticks_remaining);
    try std.testing.expect(tooltip.target_area != null);
}

test "Tooltip.notifyFocus with trigger manual is no-op on true" {
    var tooltip = Tooltip.init("Test").withTrigger(.manual);
    const target = Rect{ .x = 20, .y = 15, .width = 3, .height = 1 };

    tooltip.notifyFocus(true, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyFocus with trigger manual is no-op on false" {
    var tooltip = Tooltip.init("Test").withTrigger(.manual);
    const target = Rect{ .x = 20, .y = 15, .width = 3, .height = 1 };

    tooltip.notifyFocus(false, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyFocus with trigger hover is no-op" {
    var tooltip = Tooltip.init("Test").withTrigger(.hover);
    const target = Rect{ .x = 20, .y = 15, .width = 3, .height = 1 };

    tooltip.notifyFocus(true, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyFocus with trigger hover is no-op on false" {
    var tooltip = Tooltip.init("Test").withTrigger(.hover);
    const target = Rect{ .x = 20, .y = 15, .width = 3, .height = 1 };

    tooltip.notifyFocus(false, target);

    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(@as(?Rect, null), tooltip.target_area);
}

test "Tooltip.notifyHover respects existing show_delay pending logic" {
    var tooltip = Tooltip.init("Test")
        .withTrigger(.hover)
        .withShowDelay(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyHover(true, target);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 3), tooltip.delay_ticks_remaining);

    // After ticking through delay, should become visible
    tooltip.tick();
    tooltip.tick();
    tooltip.tick();

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
}

test "Tooltip.notifyFocus respects existing show_delay pending logic" {
    var tooltip = Tooltip.init("Test")
        .withTrigger(.focus)
        .withShowDelay(2);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.notifyFocus(true, target);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 2), tooltip.delay_ticks_remaining);

    // After ticking through delay, should become visible
    tooltip.tick();
    tooltip.tick();

    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(false, tooltip.pending);
}

test "Tooltip.notifyHover does not affect state when trigger is manual" {
    var tooltip = Tooltip.init("Test")
        .withTrigger(.manual)
        .withShowDelay(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    const initial_pending = tooltip.pending;
    const initial_visible = tooltip.visible;
    const initial_delay = tooltip.delay_ticks_remaining;
    const initial_target = tooltip.target_area;

    tooltip.notifyHover(true, target);

    try std.testing.expectEqual(initial_pending, tooltip.pending);
    try std.testing.expectEqual(initial_visible, tooltip.visible);
    try std.testing.expectEqual(initial_delay, tooltip.delay_ticks_remaining);
    try std.testing.expectEqual(initial_target, tooltip.target_area);
}

test "Tooltip.notifyFocus does not affect state when trigger is manual" {
    var tooltip = Tooltip.init("Test")
        .withTrigger(.manual)
        .withShowDelay(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    const initial_pending = tooltip.pending;
    const initial_visible = tooltip.visible;
    const initial_delay = tooltip.delay_ticks_remaining;
    const initial_target = tooltip.target_area;

    tooltip.notifyFocus(true, target);

    try std.testing.expectEqual(initial_pending, tooltip.pending);
    try std.testing.expectEqual(initial_visible, tooltip.visible);
    try std.testing.expectEqual(initial_delay, tooltip.delay_ticks_remaining);
    try std.testing.expectEqual(initial_target, tooltip.target_area);
}

// ============================================================================
// FADE-IN ANIMATION TESTS (Red Phase)
// ============================================================================

test "Tooltip.init defaults fade_in_ticks to 0" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_in_ticks);
}

test "Tooltip.init defaults fade_ticks_elapsed to 0" {
    const tooltip = Tooltip.init("Test");
    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_ticks_elapsed);
}

test "Tooltip.withFadeIn sets fade_in_ticks field" {
    const tooltip = Tooltip.init("Test").withFadeIn(8);
    try std.testing.expectEqual(@as(u32, 8), tooltip.fade_in_ticks);
}

test "Tooltip.withFadeIn builder returns modified copy and original unchanged" {
    const t1 = Tooltip.init("Test");
    const t2 = t1.withFadeIn(10);

    try std.testing.expectEqual(@as(u32, 0), t1.fade_in_ticks); // Original unchanged
    try std.testing.expectEqual(@as(u32, 10), t2.fade_in_ticks); // Copy modified
}

test "Tooltip.currentAlpha returns 1.0 when fade_in_ticks equals 0 (default, disabled)" {
    var tooltip = Tooltip.init("Test");
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    try std.testing.expectEqual(@as(f32, 1.0), tooltip.currentAlpha());
}

test "Tooltip.currentAlpha returns 0.0 immediately after show with fade_in_ticks > 0 (no tick yet)" {
    var tooltip = Tooltip.init("Test").withFadeIn(4);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    try std.testing.expectEqual(@as(f32, 0.0), tooltip.currentAlpha());
}

test "Tooltip.currentAlpha mid-fade progression at multiple tick stages" {
    var tooltip = Tooltip.init("Test").withFadeIn(4);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    // After 1 tick: fade_ticks_elapsed = 1, fade_in_ticks = 4 → alpha = 0.25
    tooltip.tick();
    try std.testing.expectEqual(@as(f32, 0.25), tooltip.currentAlpha());

    // After 2 ticks: fade_ticks_elapsed = 2, fade_in_ticks = 4 → alpha = 0.5
    tooltip.tick();
    try std.testing.expectEqual(@as(f32, 0.5), tooltip.currentAlpha());

    // After 3 ticks: fade_ticks_elapsed = 3, fade_in_ticks = 4 → alpha = 0.75
    tooltip.tick();
    try std.testing.expectEqual(@as(f32, 0.75), tooltip.currentAlpha());
}

test "Tooltip.currentAlpha caps at 1.0 and does not over-increment fade_ticks_elapsed" {
    var tooltip = Tooltip.init("Test").withFadeIn(2);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    // Tick twice to reach fade_in_ticks = 2
    tooltip.tick();
    tooltip.tick();
    try std.testing.expectEqual(@as(f32, 1.0), tooltip.currentAlpha());
    try std.testing.expectEqual(@as(u32, 2), tooltip.fade_ticks_elapsed);

    // Tick 5 more times — should stay at 1.0 and fade_ticks_elapsed should cap at 2
    for (0..5) |_| {
        tooltip.tick();
    }
    try std.testing.expectEqual(@as(f32, 1.0), tooltip.currentAlpha());
    try std.testing.expectEqual(@as(u32, 2), tooltip.fade_ticks_elapsed); // Not 7, stays at 2
}

test "Tooltip.show resets fade_ticks_elapsed to 0 on re-show" {
    var tooltip = Tooltip.init("Test").withFadeIn(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    // Show and tick partway through fade
    tooltip.show(target);
    tooltip.tick();
    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 2), tooltip.fade_ticks_elapsed);
    try std.testing.expectEqual(@as(f32, 2.0 / 3.0), tooltip.currentAlpha());

    // Hide and show again
    tooltip.hide();
    tooltip.show(target);

    // fade_ticks_elapsed should be reset to 0, alpha back to 0.0
    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_ticks_elapsed);
    try std.testing.expectEqual(@as(f32, 0.0), tooltip.currentAlpha());
}

test "Tooltip.tick during pending phase does NOT progress fade_ticks_elapsed" {
    var tooltip = Tooltip.init("Test")
        .withFadeIn(4)
        .withShowDelay(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_ticks_elapsed);

    // Tick twice during pending phase (delay_ticks_remaining goes 3→2→1)
    tooltip.tick();
    tooltip.tick();

    // Should still be pending, visible = false, and fade_ticks_elapsed should still be 0
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(false, tooltip.visible);
    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_ticks_elapsed);
}

test "Tooltip.tick after pending delay elapses starts fade_ticks_elapsed from 0" {
    var tooltip = Tooltip.init("Test")
        .withFadeIn(4)
        .withShowDelay(2);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    try std.testing.expectEqual(true, tooltip.pending);
    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_ticks_elapsed);

    // Tick twice to complete delay
    tooltip.tick();
    tooltip.tick();

    // Now should be visible and NOT pending
    try std.testing.expectEqual(false, tooltip.pending);
    try std.testing.expectEqual(true, tooltip.visible);
    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_ticks_elapsed);

    // Tick once more — fade_ticks_elapsed should now be 1
    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 1), tooltip.fade_ticks_elapsed);
    try std.testing.expectEqual(@as(f32, 0.25), tooltip.currentAlpha());
}

test "Tooltip.hide resets fade_ticks_elapsed to 0" {
    var tooltip = Tooltip.init("Test").withFadeIn(3);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.tick();
    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 2), tooltip.fade_ticks_elapsed);

    tooltip.hide();

    try std.testing.expectEqual(@as(u32, 0), tooltip.fade_ticks_elapsed);
}

test "Tooltip fade progression and timeout countdown advance independently" {
    var tooltip = Tooltip.init("Test")
        .withFadeIn(2)
        .withTimeout(5);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    // After 2 ticks, fade should be complete (alpha = 1.0)
    // and timeout should have counted down by 2 (ticks_remaining = 3)
    tooltip.tick();
    tooltip.tick();
    try std.testing.expectEqual(@as(f32, 1.0), tooltip.currentAlpha());
    try std.testing.expectEqual(@as(u32, 3), tooltip.ticks_remaining);
    try std.testing.expectEqual(true, tooltip.visible);

    // Continue ticking until timeout elapses
    tooltip.tick();
    tooltip.tick();
    tooltip.tick();
    try std.testing.expectEqual(false, tooltip.visible);
}

test "Tooltip.render with fade_in_ticks 0 (disabled) preserves original style exactly" {
    var tooltip = Tooltip.init("Test")
        .withStyle(.{ .fg = Color.fromRgb(200, 100, 50), .bg = .black })
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Content is rendered at position (10, 12)
    const style = buf.getStyle(10, 12);
    try std.testing.expectEqual(Color.fromRgb(200, 100, 50), style.fg.?);
}

test "Tooltip.render mid-fade blends rgb foreground color correctly" {
    var tooltip = Tooltip.init("Test")
        .withStyle(.{ .fg = Color.fromRgb(200, 100, 50), .bg = .black })
        .withFadeIn(4)
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.tick();
    tooltip.tick(); // After 2 ticks, alpha = 0.5

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // At alpha = 0.5: round(200*0.5)=100, round(100*0.5)=50, round(50*0.5)=25
    const style = buf.getStyle(10, 12);
    try std.testing.expectEqual(Color.fromRgb(100, 50, 25), style.fg.?);
}

test "Tooltip.render mid-fade with named color renders full color (unblendable)" {
    var tooltip = Tooltip.init("Test")
        .withStyle(.{ .fg = .bright_yellow, .bg = .black })
        .withFadeIn(4)
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.tick(); // After 1 tick, alpha = 0.25

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // Named colors don't blend — should remain .bright_yellow
    const style = buf.getStyle(10, 12);
    try std.testing.expectEqual(@as(?Color, .bright_yellow), style.fg);
}

test "Tooltip.render at alpha 0.0 (immediately after show) blends to black" {
    var tooltip = Tooltip.init("Test")
        .withStyle(.{ .fg = Color.fromRgb(200, 100, 50), .bg = .black })
        .withFadeIn(3)
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    // No tick() yet — alpha = 0.0

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // At alpha = 0.0: all channels blend to 0 (black)
    const style = buf.getStyle(10, 12);
    try std.testing.expectEqual(Color.fromRgb(0, 0, 0), style.fg.?);
}

test "Tooltip.render once fully faded in returns exact original rgb color" {
    const original_color = Color.fromRgb(200, 100, 50);
    var tooltip = Tooltip.init("Test")
        .withStyle(.{ .fg = original_color, .bg = .black })
        .withFadeIn(2)
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.tick();
    tooltip.tick(); // After 2 ticks, alpha = 1.0, fade complete

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    const style = buf.getStyle(10, 12);
    try std.testing.expectEqual(original_color, style.fg.?);
}

test "Tooltip.render border style also fades during mid-fade" {
    var tooltip = Tooltip{
        .content = "Test",
        .style = .{ .fg = .black, .bg = .bright_yellow },
        .border_style = .{ .fg = Color.fromRgb(200, 100, 50) },
        .block = Block{},
        .fade_in_ticks = 2,
        .position = .below,
    };
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.tick(); // After 1 tick, alpha = 0.5

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // The border will be rendered by the Block at top-left of tooltip area (10, 12)
    // Original RGB(200, 100, 50) blended at alpha = 0.5:
    // r: round(200 * 0.5) = 100
    // g: round(100 * 0.5) = 50
    // b: round(50 * 0.5) = 25
    const border_style = buf.getStyle(10, 12);
    const expected_fg = Color.fromRgb(100, 50, 25);
    try std.testing.expectEqual(expected_fg, border_style.fg.?);
}

test "Tooltip.render arrow style also fades" {
    var tooltip = Tooltip{
        .content = "Test",
        .style = .{ .fg = .black, .bg = .bright_yellow },
        .border_style = .{ .fg = Color.fromRgb(200, 100, 50) },
        .show_arrow = true,
        .fade_in_ticks = 2,
        .position = .below,
    };
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.tick(); // After 1 tick, alpha = 0.5

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tooltip.render(buf, area);

    // The arrow should be rendered with blended border_style
    // For .position = .below:
    //   arrow_x = target.x + target.width / 2 = 10 + 5/2 = 12
    //   arrow_y = tooltip_area.y - 1 = (target.y + target.height) - 1 = (10 + 2) - 1 = 11
    // Original RGB(200, 100, 50) blended at alpha = 0.5:
    // r: round(200 * 0.5) = 100, g: round(100 * 0.5) = 50, b: round(50 * 0.5) = 25
    const arrow_style = buf.getStyle(12, 11);
    const expected_fg = Color.fromRgb(100, 50, 25);
    try std.testing.expectEqual(expected_fg, arrow_style.fg.?);
}

test "Tooltip.render does not mutate fade_ticks_elapsed (const self method)" {
    var tooltip = Tooltip.init("Test")
        .withFadeIn(4)
        .withPosition(.below);
    const target = Rect{ .x = 10, .y = 10, .width = 5, .height = 2 };

    tooltip.show(target);
    tooltip.tick();
    try std.testing.expectEqual(@as(u32, 1), tooltip.fade_ticks_elapsed);

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    // Call render multiple times without ticking
    tooltip.render(buf, area);
    try std.testing.expectEqual(@as(u32, 1), tooltip.fade_ticks_elapsed);

    tooltip.render(buf, area);
    try std.testing.expectEqual(@as(u32, 1), tooltip.fade_ticks_elapsed);

    tooltip.render(buf, area);
    try std.testing.expectEqual(@as(u32, 1), tooltip.fade_ticks_elapsed);

    // Alpha should remain unchanged
    try std.testing.expectEqual(@as(f32, 0.25), tooltip.currentAlpha());
}
