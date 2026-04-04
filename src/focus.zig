const std = @import("std");
const style_mod = @import("tui/style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;

/// Focus ring visualization styles
pub const FocusStyle = struct {
    /// Border style when focused
    border: Style = .{ .fg = .cyan, .bold = true },
    /// Background style when focused
    background: ?Style = null,
    /// Character to use for focus indicator (e.g., ">")
    indicator: ?u21 = null,
    /// Indicator position
    indicator_position: IndicatorPosition = .left,

    pub const IndicatorPosition = enum {
        left,
        right,
        both,
    };

    /// Default focus style (cyan border, bold)
    pub fn default() FocusStyle {
        return .{};
    }

    /// Subtle focus style (blue border, no bold)
    pub fn subtle() FocusStyle {
        return .{
            .border = .{ .fg = .blue },
        };
    }

    /// Highlighted focus style (yellow background)
    pub fn highlighted() FocusStyle {
        return .{
            .border = .{ .fg = .yellow, .bold = true },
            .background = .{ .bg = .{ .indexed = 235 } }, // Dark gray
        };
    }

    /// Indicator style (arrow on left)
    pub fn withIndicator(char: u21) FocusStyle {
        return .{
            .border = .{ .fg = .cyan, .bold = true },
            .indicator = char,
            .indicator_position = .left,
        };
    }
};

/// Visual focus indicator for rendering focus feedback on widgets
pub const FocusIndicator = struct {
    /// Current focus state
    focused: bool = false,
    /// Visual style for focus
    style: FocusStyle = FocusStyle.default(),

    /// Initialize focus indicator with default style
    pub fn init() FocusIndicator {
        return .{};
    }

    /// Initialize with custom style
    pub fn initWithStyle(style: FocusStyle) FocusIndicator {
        return .{
            .style = style,
        };
    }

    /// Set focus state
    pub fn setFocused(self: *FocusIndicator, focused: bool) void {
        self.focused = focused;
    }

    /// Check if currently focused
    pub fn isFocused(self: *const FocusIndicator) bool {
        return self.focused;
    }

    /// Render focus indicator on buffer within rect
    /// This applies visual feedback based on FocusStyle
    pub fn render(self: *const FocusIndicator, buffer: anytype, rect: anytype) void {
        if (!self.focused) return; // No visual feedback when not focused

        // Apply background style if specified
        if (self.style.background) |bg_style| {
            var y: u16 = rect.y;
            while (y < rect.y + rect.height) : (y += 1) {
                var x: u16 = rect.x;
                while (x < rect.x + rect.width) : (x += 1) {
                    if (x < buffer.width and y < buffer.height) {
                        if (buffer.get(x, y)) |cell_ptr| {
                            cell_ptr.style.bg = bg_style.bg;
                        }
                    }
                }
            }
        }

        // Apply border style (top, bottom, left, right edges)
        const border_style = self.style.border;

        // Top and bottom borders
        var x: u16 = rect.x;
        while (x < rect.x + rect.width) : (x += 1) {
            if (x < buffer.width) {
                // Top border
                if (rect.y < buffer.height) {
                    if (buffer.get(x, rect.y)) |cell_ptr| {
                        // Merge border style with existing background
                        cell_ptr.style.fg = border_style.fg;
                        cell_ptr.style.bold = border_style.bold;
                    }
                }
                // Bottom border
                const bottom_y = rect.y + rect.height -| 1;
                if (bottom_y < buffer.height) {
                    if (buffer.get(x, bottom_y)) |cell_ptr| {
                        cell_ptr.style.fg = border_style.fg;
                        cell_ptr.style.bold = border_style.bold;
                    }
                }
            }
        }

        // Left and right borders
        var y: u16 = rect.y;
        while (y < rect.y + rect.height) : (y += 1) {
            if (y < buffer.height) {
                // Left border
                if (rect.x < buffer.width) {
                    if (buffer.get(rect.x, y)) |cell_ptr| {
                        cell_ptr.style.fg = border_style.fg;
                        cell_ptr.style.bold = border_style.bold;
                    }
                }
                // Right border
                const right_x = rect.x + rect.width -| 1;
                if (right_x < buffer.width) {
                    if (buffer.get(right_x, y)) |cell_ptr| {
                        cell_ptr.style.fg = border_style.fg;
                        cell_ptr.style.bold = border_style.bold;
                    }
                }
            }
        }

        // Render indicator character if specified
        if (self.style.indicator) |indicator_char| {
            const mid_y = rect.y + rect.height / 2;
            if (mid_y < buffer.height) {
                switch (self.style.indicator_position) {
                    .left => {
                        if (rect.x > 0 and rect.x - 1 < buffer.width) {
                            buffer.setChar(rect.x - 1, mid_y, indicator_char, border_style);
                        }
                    },
                    .right => {
                        const indicator_x = rect.x + rect.width;
                        if (indicator_x < buffer.width) {
                            buffer.setChar(indicator_x, mid_y, indicator_char, border_style);
                        }
                    },
                    .both => {
                        if (rect.x > 0 and rect.x - 1 < buffer.width) {
                            buffer.setChar(rect.x - 1, mid_y, indicator_char, border_style);
                        }
                        const indicator_x = rect.x + rect.width;
                        if (indicator_x < buffer.width) {
                            buffer.setChar(indicator_x, mid_y, indicator_char, border_style);
                        }
                    },
                }
            }
        }
    }
};

/// Focus manager for tracking focus across widgets
pub const FocusManager = struct {
    /// Currently focused widget ID
    focused_id: ?usize = null,
    /// Focus order (widget IDs in tab order)
    order: std.ArrayList(usize),
    /// Allocator for order list
    allocator: std.mem.Allocator,
    /// Whether focus wraps around (last -> first)
    wrap: bool = true,

    /// Initialize focus manager with no widgets focused.
    /// Call deinit() to free the focus order list.
    pub fn init(allocator: std.mem.Allocator) FocusManager {
        return .{
            .allocator = allocator,
            .order = std.ArrayList(usize){},
        };
    }

    /// Free the focus order list.
    pub fn deinit(self: *FocusManager) void {
        self.order.deinit(self.allocator);
    }

    /// Register a widget in the focus order
    pub fn register(self: *FocusManager, widget_id: usize) !void {
        try self.order.append(self.allocator, widget_id);
        if (self.focused_id == null and self.order.items.len == 1) {
            self.focused_id = widget_id;
        }
    }

    /// Unregister a widget from focus order
    pub fn unregister(self: *FocusManager, widget_id: usize) void {
        for (self.order.items, 0..) |id, i| {
            if (id == widget_id) {
                _ = self.order.swapRemove(i);
                if (self.focused_id == widget_id) {
                    self.focused_id = if (self.order.items.len > 0) self.order.items[0] else null;
                }
                break;
            }
        }
    }

    /// Check if a widget is focused
    pub fn isFocused(self: *const FocusManager, widget_id: usize) bool {
        return self.focused_id == widget_id;
    }

    /// Set focus to a specific widget
    pub fn setFocus(self: *FocusManager, widget_id: usize) void {
        self.focused_id = widget_id;
    }

    /// Move focus to next widget
    pub fn focusNext(self: *FocusManager) void {
        if (self.order.items.len == 0) return;
        if (self.focused_id == null) {
            self.focused_id = self.order.items[0];
            return;
        }

        const current_id = self.focused_id.?;
        for (self.order.items, 0..) |id, i| {
            if (id == current_id) {
                if (i + 1 < self.order.items.len) {
                    self.focused_id = self.order.items[i + 1];
                } else if (self.wrap) {
                    self.focused_id = self.order.items[0];
                }
                return;
            }
        }
    }

    /// Move focus to previous widget
    pub fn focusPrev(self: *FocusManager) void {
        if (self.order.items.len == 0) return;
        if (self.focused_id == null) {
            self.focused_id = self.order.items[self.order.items.len - 1];
            return;
        }

        const current_id = self.focused_id.?;
        for (self.order.items, 0..) |id, i| {
            if (id == current_id) {
                if (i > 0) {
                    self.focused_id = self.order.items[i - 1];
                } else if (self.wrap) {
                    self.focused_id = self.order.items[self.order.items.len - 1];
                }
                return;
            }
        }
    }

    /// Clear all focus
    pub fn clear(self: *FocusManager) void {
        self.focused_id = null;
    }

    /// Get count of focusable widgets
    pub fn count(self: *const FocusManager) usize {
        return self.order.items.len;
    }
};

test "focus: FocusManager init and deinit" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(?usize, null), manager.focused_id);
    try std.testing.expectEqual(@as(usize, 0), manager.count());
}

test "focus: register widget sets initial focus" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try std.testing.expectEqual(@as(?usize, 1), manager.focused_id);
    try std.testing.expectEqual(@as(usize, 1), manager.count());
}

test "focus: register multiple widgets" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    try std.testing.expectEqual(@as(usize, 3), manager.count());
    try std.testing.expectEqual(@as(?usize, 1), manager.focused_id);
}

test "focus: isFocused" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);

    try std.testing.expect(manager.isFocused(1));
    try std.testing.expect(!manager.isFocused(2));
}

test "focus: setFocus" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(2);
    try std.testing.expect(manager.isFocused(2));
}

test "focus: focusNext" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    try std.testing.expect(manager.isFocused(1));
    manager.focusNext();
    try std.testing.expect(manager.isFocused(2));
    manager.focusNext();
    try std.testing.expect(manager.isFocused(3));
}

test "focus: focusNext wraps around" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);

    manager.setFocus(2);
    manager.focusNext();
    try std.testing.expect(manager.isFocused(1));
}

test "focus: focusPrev" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(3);
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(2));
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(1));
}

test "focus: focusPrev wraps around" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);

    manager.setFocus(1);
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(2));
}

test "focus: unregister widget" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.unregister(2);
    try std.testing.expectEqual(@as(usize, 2), manager.count());
}

test "focus: unregister focused widget moves focus" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(1);
    manager.unregister(1);
    try std.testing.expect(!manager.isFocused(1));
    try std.testing.expect(manager.focused_id != null);
}

test "focus: clear removes focus" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    manager.clear();
    try std.testing.expectEqual(@as(?usize, null), manager.focused_id);
}

test "focus: FocusStyle default" {
    const fs = FocusStyle.default();
    try std.testing.expectEqual(Color.cyan, fs.border.fg.?);
    try std.testing.expect(fs.border.bold);
}

test "focus: FocusStyle subtle" {
    const fs = FocusStyle.subtle();
    try std.testing.expectEqual(Color.blue, fs.border.fg.?);
    try std.testing.expect(!fs.border.bold);
}

test "focus: FocusStyle highlighted" {
    const fs = FocusStyle.highlighted();
    try std.testing.expectEqual(Color.yellow, fs.border.fg.?);
    try std.testing.expect(fs.background != null);
}

test "focus: FocusStyle withIndicator" {
    const fs = FocusStyle.withIndicator('>');
    try std.testing.expectEqual(@as(?u21, '>'), fs.indicator);
    try std.testing.expectEqual(FocusStyle.IndicatorPosition.left, fs.indicator_position);
}

// Additional comprehensive tests for focus indicator system (v1.35.0)

test "focus: focusNext from null focuses first widget" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.clear();
    manager.focusNext();
    try std.testing.expect(manager.isFocused(1));
}

test "focus: focusPrev from null focuses last widget" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.clear();
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(3));
}

test "focus: focusNext on empty manager does nothing" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    manager.focusNext();
    try std.testing.expectEqual(@as(?usize, null), manager.focused_id);
}

test "focus: focusPrev on empty manager does nothing" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    manager.focusPrev();
    try std.testing.expectEqual(@as(?usize, null), manager.focused_id);
}

test "focus: single widget no wrap on focusNext" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();
    manager.wrap = false;

    try manager.register(1);
    manager.focusNext();
    try std.testing.expect(manager.isFocused(1));
}

test "focus: single widget no wrap on focusPrev" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();
    manager.wrap = false;

    try manager.register(1);
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(1));
}

test "focus: focusNext without wrap stops at end" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();
    manager.wrap = false;

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(3);
    manager.focusNext();
    try std.testing.expect(manager.isFocused(3));
}

test "focus: focusPrev without wrap stops at start" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();
    manager.wrap = false;

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(1);
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(1));
}

test "focus: multiple focusNext cycles through all" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.focusNext();
    manager.focusNext();
    manager.focusNext();
    manager.focusNext();
    try std.testing.expect(manager.isFocused(2));
}

test "focus: multiple focusPrev cycles backward" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    // Start at 1, prev 4 times: 1->3->2->1->3
    manager.focusPrev();
    manager.focusPrev();
    manager.focusPrev();
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(3));
}

test "focus: register many widgets allocates correctly" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    for (0..100) |i| {
        try manager.register(i);
    }

    try std.testing.expectEqual(@as(usize, 100), manager.count());
    try std.testing.expect(manager.isFocused(0));
}

test "focus: unregister all leaves manager empty" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.unregister(1);
    manager.unregister(2);
    manager.unregister(3);

    try std.testing.expectEqual(@as(usize, 0), manager.count());
    try std.testing.expectEqual(@as(?usize, null), manager.focused_id);
}

test "focus: unregister last focused widget focuses first" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(3);
    manager.unregister(3);

    try std.testing.expect(manager.isFocused(1));
}

test "focus: unregister middle widget maintains correct focus" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.unregister(2);
    manager.focusNext();

    try std.testing.expect(manager.isFocused(3));
}

test "focus: setFocus on non-existent widget doesn't validate" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);

    manager.setFocus(999);
    try std.testing.expect(manager.isFocused(999));
}

test "focus: FocusStyle default has cyan color" {
    const fs = FocusStyle.default();
    try std.testing.expect(fs.background == null);
    try std.testing.expect(fs.indicator == null);
}

test "focus: FocusStyle subtle is not bold" {
    const fs = FocusStyle.subtle();
    try std.testing.expect(!fs.border.bold);
}

test "focus: FocusStyle highlighted has background" {
    const fs = FocusStyle.highlighted();
    try std.testing.expect(fs.background != null);
}

test "focus: FocusStyle withIndicator sets position" {
    const fs = FocusStyle.withIndicator('*');
    try std.testing.expectEqual(FocusStyle.IndicatorPosition.left, fs.indicator_position);
}

test "focus: IndicatorPosition enum has all values" {
    _ = FocusStyle.IndicatorPosition.left;
    _ = FocusStyle.IndicatorPosition.right;
    _ = FocusStyle.IndicatorPosition.both;
}

test "focus: FocusStyle indicator can be null" {
    const fs = FocusStyle.default();
    try std.testing.expectEqual(@as(?u21, null), fs.indicator);
}

test "focus: FocusStyle background can be null" {
    const fs = FocusStyle.default();
    try std.testing.expectEqual(@as(?Style, null), fs.background);
}

test "focus: FocusStyle border defaults to cyan bold" {
    const fs = FocusStyle.default();
    try std.testing.expect(fs.border.bold);
    try std.testing.expectEqual(Color.cyan, fs.border.fg.?);
}

test "focus: FocusManager wrap defaults to true" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expect(manager.wrap);
}

test "focus: FocusManager wrap can be disabled" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();
    manager.wrap = false;

    try std.testing.expect(!manager.wrap);
}

test "focus: register order preserved in sequence" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(5);
    try manager.register(3);
    try manager.register(7);

    manager.setFocus(5);
    manager.focusNext();
    try std.testing.expect(manager.isFocused(3));
    manager.focusNext();
    try std.testing.expect(manager.isFocused(7));
}

test "focus: unregister unfocused widget leaves focus unchanged" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(1);
    manager.unregister(3);

    try std.testing.expect(manager.isFocused(1));
}

test "focus: large widget ID supported" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    const large_id: usize = 999999999;
    try manager.register(large_id);
    try std.testing.expect(manager.isFocused(large_id));
}

test "focus: setFocus multiple times works" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.setFocus(1);
    try std.testing.expect(manager.isFocused(1));
    manager.setFocus(2);
    try std.testing.expect(manager.isFocused(2));
    manager.setFocus(3);
    try std.testing.expect(manager.isFocused(3));
}

test "focus: clear on already cleared manager is safe" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    manager.clear();
    manager.clear();

    try std.testing.expectEqual(@as(?usize, null), manager.focused_id);
}

test "focus: clear only clears focus not widgets" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    manager.clear();

    // Clear removes focus but not the widgets
    try std.testing.expectEqual(@as(?usize, null), manager.focused_id);
    try std.testing.expectEqual(@as(usize, 2), manager.count());
}

test "focus: isFocused on empty manager always false" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expect(!manager.isFocused(1));
    try std.testing.expect(!manager.isFocused(999));
}

test "focus: FocusStyle withIndicator sets cyan border" {
    const fs = FocusStyle.withIndicator('→');
    try std.testing.expectEqual(Color.cyan, fs.border.fg.?);
    try std.testing.expect(fs.border.bold);
}

test "focus: custom FocusStyle can have all null optional fields" {
    const fs: FocusStyle = .{
        .border = .{ .fg = .red },
        .background = null,
        .indicator = null,
    };

    try std.testing.expectEqual(@as(?u21, null), fs.indicator);
    try std.testing.expectEqual(@as(?Style, null), fs.background);
}

test "focus: FocusManager count reflects actual widgets" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try std.testing.expectEqual(@as(usize, 1), manager.count());

    try manager.register(2);
    try std.testing.expectEqual(@as(usize, 2), manager.count());

    manager.unregister(1);
    try std.testing.expectEqual(@as(usize, 1), manager.count());
}

test "focus: focusNext from middle to end to wrap" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(10);
    try manager.register(20);
    try manager.register(30);

    manager.setFocus(20);
    manager.focusNext();
    try std.testing.expect(manager.isFocused(30));
    manager.focusNext();
    try std.testing.expect(manager.isFocused(10));
}

test "focus: focusPrev from middle to start to wrap" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(10);
    try manager.register(20);
    try manager.register(30);

    manager.setFocus(20);
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(10));
    manager.focusPrev();
    try std.testing.expect(manager.isFocused(30));
}

test "focus: alternating next and prev" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    manager.focusNext(); // 1 -> 2
    manager.focusPrev(); // 2 -> 1
    manager.focusNext(); // 1 -> 2
    manager.focusNext(); // 2 -> 3
    manager.focusPrev(); // 3 -> 2

    try std.testing.expect(manager.isFocused(2));
}

test "focus: FocusStyle creates distinct styles" {
    const default_style = FocusStyle.default();
    const subtle_style = FocusStyle.subtle();
    const highlighted_style = FocusStyle.highlighted();

    try std.testing.expect(default_style.border.bold);
    try std.testing.expect(!subtle_style.border.bold);
    try std.testing.expect(highlighted_style.background != null);
}

test "focus: register with duplicate IDs (no dedup)" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(1);
    try manager.register(1);
    try manager.register(1);

    try std.testing.expectEqual(@as(usize, 3), manager.count());
}

test "focus: unregister does not shift unregistered IDs" {
    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try manager.register(5);
    try manager.register(10);
    try manager.register(15);

    manager.unregister(10);
    manager.focusNext();

    try std.testing.expect(manager.isFocused(15));
}

// FocusIndicator tests
const Buffer = @import("tui/buffer.zig").Buffer;
const Rect = @import("tui/layout.zig").Rect;

test "focus: FocusIndicator init with default style" {
    const indicator = FocusIndicator.init();
    try std.testing.expect(!indicator.focused);
    try std.testing.expectEqual(Color.cyan, indicator.style.border.fg.?); // cyan
}

test "focus: FocusIndicator initWithStyle custom" {
    const custom_style = FocusStyle.highlighted();
    const indicator = FocusIndicator.initWithStyle(custom_style);
    try std.testing.expect(!indicator.focused);
    try std.testing.expect(indicator.style.background != null);
}

test "focus: FocusIndicator setFocused and isFocused" {
    var indicator = FocusIndicator.init();
    try std.testing.expect(!indicator.isFocused());

    indicator.setFocused(true);
    try std.testing.expect(indicator.isFocused());

    indicator.setFocused(false);
    try std.testing.expect(!indicator.isFocused());
}

test "focus: FocusIndicator render when not focused (no-op)" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    // Fill with 'X' to detect changes
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 10) : (x += 1) {
            buffer.setChar(x, y, 'X', .{});
        }
    }

    const indicator = FocusIndicator.init(); // not focused
    const rect = Rect{ .x = 2, .y = 2, .width = 5, .height = 3 };
    indicator.render(&buffer, rect);

    // Buffer should be unchanged (all 'X')
    y = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 10) : (x += 1) {
            try std.testing.expectEqual(@as(u21, 'X'), buffer.getChar(x, y));
        }
    }
}

test "focus: FocusIndicator render border style when focused" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    // Fill buffer with spaces
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 10) : (x += 1) {
            buffer.setChar(x, y, ' ', .{});
        }
    }

    var indicator = FocusIndicator.init();
    indicator.setFocused(true);

    const rect = Rect{ .x = 2, .y = 2, .width = 5, .height = 3 };
    indicator.render(&buffer, rect);

    // Check that border cells have cyan color
    const top_y: u16 = 2;
    const bottom_y: u16 = 4;
    const left_x: u16 = 2;
    const right_x: u16 = 6;

    // Top border cells should have cyan style
    var x: u16 = left_x;
    while (x <= right_x) : (x += 1) {
        const top_cell = buffer.getConst(x, top_y).?;
        try std.testing.expectEqual(Color.cyan, top_cell.style.fg.?); // cyan
    }

    // Bottom border
    x = left_x;
    while (x <= right_x) : (x += 1) {
        const bottom_cell = buffer.getConst(x, bottom_y).?;
        try std.testing.expectEqual(Color.cyan, bottom_cell.style.fg.?);
    }

    // Left and right borders
    y = top_y;
    while (y <= bottom_y) : (y += 1) {
        const left_cell = buffer.getConst(left_x, y).?;
        const right_cell = buffer.getConst(right_x, y).?;
        try std.testing.expectEqual(Color.cyan, left_cell.style.fg.?);
        try std.testing.expectEqual(Color.cyan, right_cell.style.fg.?);
    }
}

test "focus: FocusIndicator render with background style" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    // Initialize buffer with spaces
    {
        var y: u16 = 0;
        while (y < 10) : (y += 1) {
            var x: u16 = 0;
            while (x < 10) : (x += 1) {
                buffer.setChar(x, y, ' ', .{});
            }
        }
    }

    var indicator = FocusIndicator.initWithStyle(FocusStyle.highlighted());
    indicator.setFocused(true);

    const rect = Rect{ .x = 2, .y = 2, .width = 4, .height = 3 };
    indicator.render(&buffer, rect);

    // All cells within rect should have background color applied
    var y: u16 = rect.y;
    while (y < rect.y + rect.height) : (y += 1) {
        var x: u16 = rect.x;
        while (x < rect.x + rect.width) : (x += 1) {
            const cell = buffer.getConst(x, y).?;
            try std.testing.expect(cell.style.bg != null);
            switch (cell.style.bg.?) {
                .indexed => |idx| try std.testing.expectEqual(@as(u8, 235), idx),
                else => try std.testing.expect(false), // Expected indexed color
            }
        }
    }
}

test "focus: FocusIndicator render with indicator character left" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    var indicator = FocusIndicator.initWithStyle(FocusStyle.withIndicator('>'));
    indicator.setFocused(true);

    const rect = Rect{ .x = 3, .y = 2, .width = 4, .height = 3 };
    indicator.render(&buffer, rect);

    // Indicator should be at (x-1, mid_y) = (2, 3)
    const mid_y = rect.y + rect.height / 2; // 2 + 3/2 = 3
    try std.testing.expectEqual(@as(u21, '>'), buffer.getChar(rect.x - 1, mid_y));
}

test "focus: FocusIndicator render with indicator character right" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    var custom_style = FocusStyle.withIndicator('<');
    custom_style.indicator_position = .right;
    var indicator = FocusIndicator.initWithStyle(custom_style);
    indicator.setFocused(true);

    const rect = Rect{ .x = 2, .y = 2, .width = 4, .height = 3 };
    indicator.render(&buffer, rect);

    // Indicator should be at (x+width, mid_y) = (6, 3)
    const mid_y = rect.y + rect.height / 2;
    const right_x = rect.x + rect.width;
    try std.testing.expectEqual(@as(u21, '<'), buffer.getChar(right_x, mid_y));
}

test "focus: FocusIndicator render with indicator character both sides" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    var custom_style = FocusStyle.withIndicator('*');
    custom_style.indicator_position = .both;
    var indicator = FocusIndicator.initWithStyle(custom_style);
    indicator.setFocused(true);

    const rect = Rect{ .x = 3, .y = 2, .width = 4, .height = 3 };
    indicator.render(&buffer, rect);

    const mid_y = rect.y + rect.height / 2;
    // Left indicator at x-1
    try std.testing.expectEqual(@as(u21, '*'), buffer.getChar(rect.x - 1, mid_y));
    // Right indicator at x+width
    try std.testing.expectEqual(@as(u21, '*'), buffer.getChar(rect.x + rect.width, mid_y));
}

test "focus: FocusIndicator render respects buffer bounds" {
    var buffer = try Buffer.init(std.testing.allocator, 5, 5);
    defer buffer.deinit();

    var indicator = FocusIndicator.init();
    indicator.setFocused(true);

    // Rect exceeds buffer bounds
    const rect = Rect{ .x = 3, .y = 3, .width = 10, .height = 10 };
    indicator.render(&buffer, rect);

    // Should not crash, rendering clipped to buffer size
    // Verify no out-of-bounds access (test passes if no crash)
}

test "focus: FocusIndicator render with zero-size rect" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    var indicator = FocusIndicator.init();
    indicator.setFocused(true);

    const rect = Rect{ .x = 2, .y = 2, .width = 0, .height = 0 };
    indicator.render(&buffer, rect);

    // Should not crash with zero-size rect
}

test "focus: FocusIndicator style persistence across renders" {
    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    var indicator = FocusIndicator.init();
    indicator.setFocused(true);

    const rect = Rect{ .x = 2, .y = 2, .width = 4, .height = 3 };

    // First render
    indicator.render(&buffer, rect);
    const first_cell = buffer.getConst(2, 2).?;

    // Second render should produce same style
    indicator.render(&buffer, rect);
    const second_cell = buffer.getConst(2, 2).?;

    try std.testing.expectEqual(first_cell.style.fg, second_cell.style.fg);
    try std.testing.expectEqual(first_cell.style.bold, second_cell.style.bold);
}
