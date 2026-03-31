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
