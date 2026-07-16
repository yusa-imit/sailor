const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const symbols = @import("../symbols.zig");

const TRACK_WIDTH = 6; // Fixed track width: [◯    ] or [    ◉]

/// Single toggle switch widget (boolean on/off slider-style control)
pub const ToggleSwitch = struct {
    label: []const u8,
    checked: bool = false,
    disabled: bool = false,
    focused: bool = false,
    on_label: []const u8 = "ON",
    off_label: []const u8 = "OFF",
    style: Style = .{},
    on_style: Style = .{},
    off_style: Style = .{},
    focused_style: Style = .{},
    disabled_style: Style = .{},

    /// Creates a new toggle switch with the given label.
    /// Default state: unchecked, enabled, unfocused, default labels and styles.
    pub fn init(label: []const u8) ToggleSwitch {
        return .{ .label = label };
    }

    /// Sets the checked state of the toggle switch.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withChecked(self: ToggleSwitch, checked: bool) ToggleSwitch {
        var result = self;
        result.checked = checked;
        return result;
    }

    /// Sets the disabled state of the toggle switch.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withDisabled(self: ToggleSwitch, disabled: bool) ToggleSwitch {
        var result = self;
        result.disabled = disabled;
        return result;
    }

    /// Sets the focus state of the toggle switch.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withFocus(self: ToggleSwitch, focused: bool) ToggleSwitch {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Sets the on/off labels.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withLabels(self: ToggleSwitch, on_label: []const u8, off_label: []const u8) ToggleSwitch {
        var result = self;
        result.on_label = on_label;
        result.off_label = off_label;
        return result;
    }

    /// Sets the base style applied when not focused.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withStyle(self: ToggleSwitch, style: Style) ToggleSwitch {
        var result = self;
        result.style = style;
        return result;
    }

    /// Sets the style applied when checked.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withOnStyle(self: ToggleSwitch, style: Style) ToggleSwitch {
        var result = self;
        result.on_style = style;
        return result;
    }

    /// Sets the style applied when unchecked.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withOffStyle(self: ToggleSwitch, style: Style) ToggleSwitch {
        var result = self;
        result.off_style = style;
        return result;
    }

    /// Sets the style applied when focused.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withFocusedStyle(self: ToggleSwitch, style: Style) ToggleSwitch {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Sets the style applied when disabled.
    /// Returns a new toggle switch instance for method chaining.
    pub fn withDisabledStyle(self: ToggleSwitch, style: Style) ToggleSwitch {
        var result = self;
        result.disabled_style = style;
        return result;
    }

    /// Toggles the checked state between true and false.
    /// No-op if disabled.
    pub fn toggle(self: *ToggleSwitch) void {
        if (!self.disabled) {
            self.checked = !self.checked;
        }
    }

    /// Renders the toggle switch to the given buffer within the specified area.
    /// Format: `[◯    ] Label` when off, `[    ◉] Label` when on
    /// Applies appropriate style based on focus, checked state, and disabled state.
    pub fn render(self: ToggleSwitch, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Determine the display style
        var display_style = if (self.checked) self.on_style else self.off_style;
        if (self.disabled) {
            display_style = self.disabled_style;
        } else if (self.focused) {
            display_style = self.focused_style;
        }

        // Render the track with brackets: [◯    ] or [    ◉]
        // x=0: '['
        buf.set(area.x, area.y, .{
            .char = '[',
            .style = display_style,
        });

        // x=1-5: spaces and knob
        if (self.checked) {
            // On-state: knob at x=5 (◉)
            buf.set(area.x + 1, area.y, .{
                .char = ' ',
                .style = display_style,
            });
            buf.set(area.x + 2, area.y, .{
                .char = ' ',
                .style = display_style,
            });
            buf.set(area.x + 3, area.y, .{
                .char = ' ',
                .style = display_style,
            });
            buf.set(area.x + 4, area.y, .{
                .char = ' ',
                .style = display_style,
            });
            buf.set(area.x + 5, area.y, .{
                .char = '◉',
                .style = display_style,
            });
        } else {
            // Off-state: knob at x=1 (◯)
            buf.set(area.x + 1, area.y, .{
                .char = '◯',
                .style = display_style,
            });
            buf.set(area.x + 2, area.y, .{
                .char = ' ',
                .style = display_style,
            });
            buf.set(area.x + 3, area.y, .{
                .char = ' ',
                .style = display_style,
            });
            buf.set(area.x + 4, area.y, .{
                .char = ' ',
                .style = display_style,
            });
            buf.set(area.x + 5, area.y, .{
                .char = ' ',
                .style = display_style,
            });
        }

        // x=6: space separator (after 6-cell track)
        if (area.width > 6) {
            buf.set(area.x + 6, area.y, .{
                .char = ' ',
                .style = display_style,
            });
        }

        // Render label starting at x=8 (x=7 might be extra space or label continuation)
        if (area.width > 8) {
            const label_space = area.width - 8;
            var x: u16 = 0;
            for (self.label) |ch| {
                if (x >= label_space) break;
                buf.set(@intCast(area.x + 8 + x), area.y, .{
                    .char = @intCast(ch),
                    .style = display_style,
                });
                x += 1;
            }
        }
    }
};

/// Helper function to merge a group base style into an item's styles
/// If the item's style property is not set (null/default), use the group's property
fn applyGroupStyle(item: ToggleSwitch, group_style: Style) ToggleSwitch {
    var result = item;

    // Apply group style as base to each style property
    // Item's explicit styles override group style
    result.on_style = mergeStyles(group_style, item.on_style);
    result.off_style = mergeStyles(group_style, item.off_style);
    result.disabled_style = mergeStyles(group_style, item.disabled_style);
    result.focused_style = mergeStyles(group_style, item.focused_style);
    result.style = mergeStyles(group_style, item.style);

    return result;
}

/// Merge base style with an override style
/// Base provides defaults; override takes precedence where specified
fn mergeStyles(base: Style, override: Style) Style {
    var result = base;

    // Color properties: override takes precedence if set
    if (override.fg != null) result.fg = override.fg;
    if (override.bg != null) result.bg = override.bg;

    // Boolean properties: OR them together (if either has the flag, result has it)
    result.bold = result.bold or override.bold;
    result.dim = result.dim or override.dim;
    result.italic = result.italic or override.italic;
    result.underline = result.underline or override.underline;
    result.blink = result.blink or override.blink;
    result.reverse = result.reverse or override.reverse;
    result.strikethrough = result.strikethrough or override.strikethrough;

    return result;
}

/// Toggle switch group for managing multiple related toggle switches
pub const ToggleSwitchGroup = struct {
    items: []ToggleSwitch,
    focused: usize = 0,
    block: ?Block = null,
    style: Style = .{},
    show_help: bool = true,

    /// Creates a new toggle switch group from a slice of toggle switches.
    /// Focus starts on the first item. Help text is shown by default.
    pub fn init(items: []ToggleSwitch) ToggleSwitchGroup {
        return .{ .items = items };
    }

    /// Sets an optional border block around the toggle switch group.
    /// Returns a new group instance for method chaining.
    pub fn withBlock(self: ToggleSwitchGroup, block: Block) ToggleSwitchGroup {
        var result = self;
        result.block = block;
        return result;
    }

    /// Sets the default style for the toggle switch group background.
    /// Returns a new group instance for method chaining.
    pub fn withStyle(self: ToggleSwitchGroup, style: Style) ToggleSwitchGroup {
        var result = self;
        result.style = style;
        return result;
    }

    /// Controls whether to display keyboard shortcut help text at the bottom.
    /// Returns a new group instance for method chaining.
    pub fn withHelp(self: ToggleSwitchGroup, show: bool) ToggleSwitchGroup {
        var result = self;
        result.show_help = show;
        return result;
    }

    /// Get currently focused toggle switch
    pub fn focusedItem(self: *ToggleSwitchGroup) ?*ToggleSwitch {
        if (self.focused < self.items.len) {
            return &self.items[self.focused];
        }
        return null;
    }

    /// Move focus to next toggle switch, skipping disabled items when possible
    pub fn focusNext(self: *ToggleSwitchGroup) void {
        if (self.items.len == 0) return;

        const start_idx = self.focused;
        var current_idx = (self.focused + 1) % self.items.len;
        var iterations: usize = 0;

        // Try to find an enabled item, up to items.len iterations
        while (iterations < self.items.len) : (iterations += 1) {
            if (!self.items[current_idx].disabled) {
                self.focused = current_idx;
                return;
            }
            current_idx = (current_idx + 1) % self.items.len;
        }

        // If we get here, all items are disabled - stay at start position
        self.focused = start_idx;
    }

    /// Move focus to previous toggle switch, skipping disabled items when possible
    pub fn focusPrev(self: *ToggleSwitchGroup) void {
        if (self.items.len == 0) return;

        const start_idx = self.focused;
        var current_idx = if (self.focused == 0) self.items.len - 1 else self.focused - 1;
        var iterations: usize = 0;

        // Try to find an enabled item, up to items.len iterations
        while (iterations < self.items.len) : (iterations += 1) {
            if (!self.items[current_idx].disabled) {
                self.focused = current_idx;
                return;
            }
            current_idx = if (current_idx == 0) self.items.len - 1 else current_idx - 1;
        }

        // If we get here, all items are disabled - stay at start position
        self.focused = start_idx;
    }

    /// Toggle currently focused toggle switch (and uncheck all others - radio-like behavior)
    pub fn toggleFocused(self: *ToggleSwitchGroup) void {
        if (self.focusedItem()) |item| {
            if (!item.disabled) {
                // Make the focused item checked and uncheck all others
                for (self.items, 0..) |*switch_item, i| {
                    if (i == self.focused) {
                        switch_item.checked = true;
                    } else {
                        switch_item.checked = false;
                    }
                }
            }
        }
    }

    /// Renders the toggle switch group to the given buffer within the specified area.
    /// Displays all toggle switches vertically with optional border block.
    /// The focused toggle switch is visually highlighted.
    pub fn render(self: ToggleSwitchGroup, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        // Reserve space for help text
        const help_height: u16 = if (self.show_help) 1 else 0;
        const items_height = if (render_area.height > help_height)
            render_area.height - help_height
        else
            0;

        // Render toggle switches
        var y: u16 = 0;
        for (self.items, 0..) |item, i| {
            if (y >= items_height) break;

            const is_focused = (i == self.focused);
            // Apply group base style to item, then apply focus
            const styled_item = applyGroupStyle(item, self.style).withFocus(is_focused);

            const item_area = Rect{
                .x = render_area.x,
                .y = render_area.y + y,
                .width = render_area.width,
                .height = 1,
            };
            styled_item.render(buf, item_area);
            y += 1;
        }

        // Render help text if configured
        if (self.show_help and render_area.height > 0) {
            const help_y = render_area.y + render_area.height - 1;
            const help_text = "↑/↓: Navigate | Space: Toggle";
            const help_style = Style{ .fg = .gray };

            for (help_text, 0..) |ch, x| {
                if (x >= render_area.width) break;
                buf.set(@intCast(render_area.x + x), help_y, .{
                    .char = @intCast(ch),
                    .style = help_style,
                });
            }
        }
    }
};

// Tests

test "ToggleSwitch.init creates with default label only" {
    const ts = ToggleSwitch.init("Test Label");
    try std.testing.expectEqualStrings("Test Label", ts.label);
}

test "ToggleSwitch.init defaults checked to false" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expect(!ts.checked);
}

test "ToggleSwitch.init defaults disabled to false" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expect(!ts.disabled);
}

test "ToggleSwitch.init defaults focused to false" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expect(!ts.focused);
}

test "ToggleSwitch.init defaults on_label to ON" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expectEqualStrings("ON", ts.on_label);
}

test "ToggleSwitch.init defaults off_label to OFF" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expectEqualStrings("OFF", ts.off_label);
}

test "ToggleSwitch.init defaults style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expectEqual(Style{}, ts.style);
}

test "ToggleSwitch.init defaults on_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expectEqual(Style{}, ts.on_style);
}

test "ToggleSwitch.init defaults off_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expectEqual(Style{}, ts.off_style);
}

test "ToggleSwitch.init defaults focused_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expectEqual(Style{}, ts.focused_style);
}

test "ToggleSwitch.init defaults disabled_style to empty Style" {
    const ts = ToggleSwitch.init("Toggle me");
    try std.testing.expectEqual(Style{}, ts.disabled_style);
}

test "withChecked does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withChecked(true);
    try std.testing.expect(!ts1.checked);
    try std.testing.expect(ts2.checked);
}

test "withDisabled does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withDisabled(true);
    try std.testing.expect(!ts1.disabled);
    try std.testing.expect(ts2.disabled);
}

test "withFocus does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withFocus(true);
    try std.testing.expect(!ts1.focused);
    try std.testing.expect(ts2.focused);
}

test "withLabels does not modify original" {
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withLabels("YES", "NO");
    try std.testing.expectEqualStrings("ON", ts1.on_label);
    try std.testing.expectEqualStrings("OFF", ts1.off_label);
    try std.testing.expectEqualStrings("YES", ts2.on_label);
    try std.testing.expectEqualStrings("NO", ts2.off_label);
}

test "withStyle does not modify original" {
    const style1 = Style{ .fg = .red };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withStyle(style1);
    try std.testing.expectEqual(Style{}, ts1.style);
    try std.testing.expectEqual(style1, ts2.style);
}

test "withOnStyle does not modify original" {
    const style1 = Style{ .fg = .green };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withOnStyle(style1);
    try std.testing.expectEqual(Style{}, ts1.on_style);
    try std.testing.expectEqual(style1, ts2.on_style);
}

test "withOffStyle does not modify original" {
    const style1 = Style{ .fg = .gray };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withOffStyle(style1);
    try std.testing.expectEqual(Style{}, ts1.off_style);
    try std.testing.expectEqual(style1, ts2.off_style);
}

test "withFocusedStyle does not modify original" {
    const style1 = Style{ .bold = true };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withFocusedStyle(style1);
    try std.testing.expectEqual(Style{}, ts1.focused_style);
    try std.testing.expectEqual(style1, ts2.focused_style);
}

test "withDisabledStyle does not modify original" {
    const style1 = Style{ .dim = true };
    const ts1 = ToggleSwitch.init("Test");
    const ts2 = ts1.withDisabledStyle(style1);
    try std.testing.expectEqual(Style{}, ts1.disabled_style);
    try std.testing.expectEqual(style1, ts2.disabled_style);
}

test "toggle flips checked from false to true" {
    var ts = ToggleSwitch.init("Toggle");
    try std.testing.expect(!ts.checked);
    ts.toggle();
    try std.testing.expect(ts.checked);
}

test "toggle flips checked from true to false" {
    var ts = ToggleSwitch.init("Toggle").withChecked(true);
    try std.testing.expect(ts.checked);
    ts.toggle();
    try std.testing.expect(!ts.checked);
}

test "toggle is no-op when disabled" {
    var ts = ToggleSwitch.init("Toggle").withDisabled(true).withChecked(false);
    ts.toggle();
    try std.testing.expect(!ts.checked);
}

test "toggle is no-op when disabled even if checked" {
    var ts = ToggleSwitch.init("Toggle").withDisabled(true).withChecked(true);
    ts.toggle();
    try std.testing.expect(ts.checked);
}

test "ToggleSwitchGroup.init sets default focused to 0" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
    };
    const group = ToggleSwitchGroup.init(&items);
    try std.testing.expectEqual(@as(usize, 0), group.focused);
}

test "ToggleSwitchGroup.init sets block to null by default" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
    };
    const group = ToggleSwitchGroup.init(&items);
    try std.testing.expectEqual(@as(?Block, null), group.block);
}

test "ToggleSwitchGroup.init sets style to empty Style by default" {
    var items = [_]ToggleSwitch{
        ToggleSwitch.init("A"),
    };
    const group = ToggleSwitchGroup.init(&items);
    try std.testing.expectEqual(Style{}, group.style);
}

test "ToggleSwitchGroup.withBlock does not modify original" {
    var items = [_]ToggleSwitch{ ToggleSwitch.init("A") };
    const group1 = ToggleSwitchGroup.init(&items);
    const block = Block{};
    const group2 = group1.withBlock(block);
    try std.testing.expectEqual(@as(?Block, null), group1.block);
    try std.testing.expect(group2.block != null);
}

test "ToggleSwitchGroup.withStyle does not modify original" {
    var items = [_]ToggleSwitch{ ToggleSwitch.init("A") };
    const group1 = ToggleSwitchGroup.init(&items);
    const style = Style{ .fg = .red };
    const group2 = group1.withStyle(style);
    try std.testing.expectEqual(Style{}, group1.style);
    try std.testing.expectEqual(style, group2.style);
}

test "ToggleSwitchGroup.withHelp does not modify original" {
    var items = [_]ToggleSwitch{ ToggleSwitch.init("A") };
    const group1 = ToggleSwitchGroup.init(&items);
    const group2 = group1.withHelp(false);
    try std.testing.expect(group1.show_help);
    try std.testing.expect(!group2.show_help);
}
