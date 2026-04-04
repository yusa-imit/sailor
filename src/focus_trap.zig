const std = @import("std");
const focus_mod = @import("focus.zig");
const FocusManager = focus_mod.FocusManager;

/// Widget ID type (same as FocusManager uses)
pub const FocusId = usize;

/// Focus trap for modal dialogs and popups
/// Prevents focus from leaving a specific set of widgets
pub const FocusTrap = struct {
    /// Widgets that are part of this trap
    widgets: std.ArrayList(FocusId),
    /// Active state
    active: bool = false,
    /// Whether to cycle focus (wrap around) or stop at boundaries
    cycle: bool = true,
    /// Focus manager this trap is attached to
    manager: ?*FocusManager = null,

    allocator: std.mem.Allocator,

    /// Initialize a new focus trap
    pub fn init(allocator: std.mem.Allocator) FocusTrap {
        return .{
            .allocator = allocator,
            .widgets = std.ArrayList(FocusId){},
        };
    }

    /// Free resources
    pub fn deinit(self: *FocusTrap) void {
        self.widgets.deinit(self.allocator);
    }

    /// Add a widget to the trap
    pub fn addWidget(self: *FocusTrap, id: FocusId) !void {
        try self.widgets.append(self.allocator, id);
    }

    /// Remove a widget from the trap
    pub fn removeWidget(self: *FocusTrap, id: FocusId) void {
        for (self.widgets.items, 0..) |widget_id, i| {
            if (widget_id == id) {
                _ = self.widgets.swapRemove(i);
                return;
            }
        }
    }

    /// Clear all widgets from the trap
    pub fn clear(self: *FocusTrap) void {
        self.widgets.clearRetainingCapacity();
    }

    /// Check if a widget is in this trap
    pub fn contains(self: *const FocusTrap, id: FocusId) bool {
        for (self.widgets.items) |widget_id| {
            if (widget_id == id) return true;
        }
        return false;
    }

    /// Activate the trap
    pub fn activate(self: *FocusTrap, manager: *FocusManager) !void {
        self.active = true;
        self.manager = manager;

        // Focus the first widget in the trap
        if (self.widgets.items.len > 0) {
            manager.setFocus(self.widgets.items[0]);
        }
    }

    /// Deactivate the trap
    pub fn deactivate(self: *FocusTrap) void {
        self.active = false;
        self.manager = null;
    }

    /// Handle tab navigation within the trap
    /// Returns true if navigation was handled by the trap
    pub fn handleTab(self: *FocusTrap, forward: bool) bool {
        if (!self.active) return false;
        if (self.manager == null) return false;
        if (self.widgets.items.len == 0) return false;

        const manager = self.manager.?;
        const current_focus = manager.focused_id;

        // Find current index
        var current_index: ?usize = null;
        for (self.widgets.items, 0..) |widget_id, i| {
            if (current_focus) |focused_id| {
                if (widget_id == focused_id) {
                    current_index = i;
                    break;
                }
            }
        }

        // Determine next index
        const next_index = if (current_index) |idx| blk: {
            if (forward) {
                if (idx + 1 >= self.widgets.items.len) {
                    break :blk if (self.cycle) 0 else idx;
                } else {
                    break :blk idx + 1;
                }
            } else {
                if (idx == 0) {
                    break :blk if (self.cycle) self.widgets.items.len - 1 else 0;
                } else {
                    break :blk idx - 1;
                }
            }
        } else 0;

        // Focus next widget
        manager.setFocus(self.widgets.items[next_index]);
        return true;
    }

    /// Get the number of widgets in the trap
    pub fn count(self: *const FocusTrap) usize {
        return self.widgets.items.len;
    }

    /// Get all widget IDs in the trap
    pub fn getWidgets(self: *const FocusTrap) []const FocusId {
        return self.widgets.items;
    }
};

/// Stack-based focus trap manager
/// Supports nested traps (e.g., dialog within dialog)
pub const FocusTrapStack = struct {
    traps: std.ArrayList(*FocusTrap),
    allocator: std.mem.Allocator,

    /// Initialize a new trap stack
    pub fn init(allocator: std.mem.Allocator) FocusTrapStack {
        return .{
            .traps = std.ArrayList(*FocusTrap){},
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *FocusTrapStack) void {
        self.traps.deinit(self.allocator);
    }

    /// Push a trap onto the stack and activate it
    pub fn push(self: *FocusTrapStack, trap: *FocusTrap, manager: *FocusManager) !void {
        try trap.activate(manager);
        try self.traps.append(self.allocator, trap);
    }

    /// Pop the top trap and deactivate it
    pub fn pop(self: *FocusTrapStack) ?*FocusTrap {
        if (self.traps.items.len == 0) return null;

        const trap = self.traps.items[self.traps.items.len - 1];
        self.traps.items.len -= 1;
        trap.deactivate();
        return trap;
    }

    /// Get the currently active trap (top of stack)
    pub fn getActive(self: *const FocusTrapStack) ?*FocusTrap {
        if (self.traps.items.len == 0) return null;
        return self.traps.items[self.traps.items.len - 1];
    }

    /// Handle tab navigation through the active trap
    pub fn handleTab(self: *FocusTrapStack, forward: bool) bool {
        if (self.getActive()) |trap| {
            return trap.handleTab(forward);
        }
        return false;
    }

    /// Get the depth of the trap stack
    pub fn depth(self: *const FocusTrapStack) usize {
        return self.traps.items.len;
    }

    /// Check if a widget is in any active trap
    pub fn isTrapped(self: *const FocusTrapStack, id: FocusId) bool {
        for (self.traps.items) |trap| {
            if (trap.contains(id)) return true;
        }
        return false;
    }

    /// Clear all traps
    pub fn clear(self: *FocusTrapStack) void {
        while (self.pop()) |_| {}
    }
};

test "focus_trap: init and deinit" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    try std.testing.expectEqual(@as(usize, 0), trap.count());
    try std.testing.expectEqual(false, trap.active);
}

test "focus_trap: add widget" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);

    try std.testing.expectEqual(@as(usize, 2), trap.count());
}

test "focus_trap: remove widget" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);
    trap.removeWidget(1);

    try std.testing.expectEqual(@as(usize, 1), trap.count());
    try std.testing.expectEqual(false, trap.contains(1));
    try std.testing.expectEqual(true, trap.contains(2));
}

test "focus_trap: clear" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);
    trap.clear();

    try std.testing.expectEqual(@as(usize, 0), trap.count());
}

test "focus_trap: contains" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);

    try std.testing.expectEqual(true, trap.contains(1));
    try std.testing.expectEqual(true, trap.contains(2));
    try std.testing.expectEqual(false, trap.contains(3));
}

test "focus_trap: activate and deactivate" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap.addWidget(1);
    try manager.register(1);

    try trap.activate(&manager);
    try std.testing.expectEqual(true, trap.active);
    try std.testing.expect(trap.manager != null);

    trap.deactivate();
    try std.testing.expectEqual(false, trap.active);
    try std.testing.expect(trap.manager == null);
}

test "focus_trap: activate focuses first widget" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);
    try manager.register(1);
    try manager.register(2);

    try trap.activate(&manager);

    const focused = manager.focused_id;
    try std.testing.expectEqual(@as(FocusId, 1), focused.?);
}

test "focus_trap: handle tab forward with cycle" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();
    trap.cycle = true;

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);
    try trap.addWidget(3);
    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    try trap.activate(&manager);

    // Start at 1, tab to 2
    _ = trap.handleTab(true);
    try std.testing.expectEqual(@as(FocusId, 2), manager.focused_id.?);

    // Tab to 3
    _ = trap.handleTab(true);
    try std.testing.expectEqual(@as(FocusId, 3), manager.focused_id.?);

    // Tab should cycle back to 1
    _ = trap.handleTab(true);
    try std.testing.expectEqual(@as(FocusId, 1), manager.focused_id.?);
}

test "focus_trap: handle tab backward with cycle" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();
    trap.cycle = true;

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);
    try trap.addWidget(3);
    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    try trap.activate(&manager);

    // Start at 1, shift+tab should cycle to 3
    _ = trap.handleTab(false);
    try std.testing.expectEqual(@as(FocusId, 3), manager.focused_id.?);

    // Shift+tab to 2
    _ = trap.handleTab(false);
    try std.testing.expectEqual(@as(FocusId, 2), manager.focused_id.?);
}

test "focus_trap: handle tab without cycle" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();
    trap.cycle = false;

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);
    try manager.register(1);
    try manager.register(2);

    try trap.activate(&manager);

    // Tab from 1 to 2
    _ = trap.handleTab(true);
    try std.testing.expectEqual(@as(FocusId, 2), manager.focused_id.?);

    // Tab should stay at 2 (no cycle)
    _ = trap.handleTab(true);
    try std.testing.expectEqual(@as(FocusId, 2), manager.focused_id.?);
}

test "focus_trap: get widgets" {
    var trap = FocusTrap.init(std.testing.allocator);
    defer trap.deinit();

    try trap.addWidget(1);
    try trap.addWidget(2);
    try trap.addWidget(3);

    const widgets = trap.getWidgets();
    try std.testing.expectEqual(@as(usize, 3), widgets.len);
    try std.testing.expectEqual(@as(FocusId, 1), widgets[0]);
    try std.testing.expectEqual(@as(FocusId, 2), widgets[1]);
    try std.testing.expectEqual(@as(FocusId, 3), widgets[2]);
}

test "focus_trap_stack: init and deinit" {
    var stack = FocusTrapStack.init(std.testing.allocator);
    defer stack.deinit();

    try std.testing.expectEqual(@as(usize, 0), stack.depth());
}

test "focus_trap_stack: push and pop" {
    var stack = FocusTrapStack.init(std.testing.allocator);
    defer stack.deinit();

    var trap1 = FocusTrap.init(std.testing.allocator);
    defer trap1.deinit();
    var trap2 = FocusTrap.init(std.testing.allocator);
    defer trap2.deinit();

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap1.addWidget(1);
    try manager.register(1);

    try trap2.addWidget(2);
    try manager.register(2);

    try stack.push(&trap1, &manager);
    try std.testing.expectEqual(@as(usize, 1), stack.depth());

    try stack.push(&trap2, &manager);
    try std.testing.expectEqual(@as(usize, 2), stack.depth());

    _ = stack.pop();
    try std.testing.expectEqual(@as(usize, 1), stack.depth());

    _ = stack.pop();
    try std.testing.expectEqual(@as(usize, 0), stack.depth());
}

test "focus_trap_stack: get active" {
    var stack = FocusTrapStack.init(std.testing.allocator);
    defer stack.deinit();

    var trap1 = FocusTrap.init(std.testing.allocator);
    defer trap1.deinit();
    var trap2 = FocusTrap.init(std.testing.allocator);
    defer trap2.deinit();

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap1.addWidget(1);
    try manager.register(1);

    try trap2.addWidget(2);
    try manager.register(2);

    try std.testing.expect(stack.getActive() == null);

    try stack.push(&trap1, &manager);
    try std.testing.expect(stack.getActive() == &trap1);

    try stack.push(&trap2, &manager);
    try std.testing.expect(stack.getActive() == &trap2);
}

test "focus_trap_stack: is trapped" {
    var stack = FocusTrapStack.init(std.testing.allocator);
    defer stack.deinit();

    var trap1 = FocusTrap.init(std.testing.allocator);
    defer trap1.deinit();
    var trap2 = FocusTrap.init(std.testing.allocator);
    defer trap2.deinit();

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap1.addWidget(1);
    try trap1.addWidget(2);
    try manager.register(1);
    try manager.register(2);

    try trap2.addWidget(3);
    try manager.register(3);

    try stack.push(&trap1, &manager);
    try stack.push(&trap2, &manager);

    try std.testing.expectEqual(true, stack.isTrapped(1));
    try std.testing.expectEqual(true, stack.isTrapped(2));
    try std.testing.expectEqual(true, stack.isTrapped(3));
    try std.testing.expectEqual(false, stack.isTrapped(4));
}

test "focus_trap_stack: clear" {
    var stack = FocusTrapStack.init(std.testing.allocator);
    defer stack.deinit();

    var trap1 = FocusTrap.init(std.testing.allocator);
    defer trap1.deinit();
    var trap2 = FocusTrap.init(std.testing.allocator);
    defer trap2.deinit();

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    try trap1.addWidget(1);
    try manager.register(1);

    try trap2.addWidget(2);
    try manager.register(2);

    try stack.push(&trap1, &manager);
    try stack.push(&trap2, &manager);

    stack.clear();
    try std.testing.expectEqual(@as(usize, 0), stack.depth());
    try std.testing.expectEqual(false, trap1.active);
    try std.testing.expectEqual(false, trap2.active);
}

test "focus_trap_stack: nested traps" {
    var stack = FocusTrapStack.init(std.testing.allocator);
    defer stack.deinit();

    var outer_trap = FocusTrap.init(std.testing.allocator);
    defer outer_trap.deinit();
    var inner_trap = FocusTrap.init(std.testing.allocator);
    defer inner_trap.deinit();

    var manager = FocusManager.init(std.testing.allocator);
    defer manager.deinit();

    // Outer dialog: widgets 1, 2, 3
    try outer_trap.addWidget(1);
    try outer_trap.addWidget(2);
    try outer_trap.addWidget(3);
    try manager.register(1);
    try manager.register(2);
    try manager.register(3);

    // Inner dialog: widgets 4, 5
    try inner_trap.addWidget(4);
    try inner_trap.addWidget(5);
    try manager.register(4);
    try manager.register(5);

    // Show outer dialog
    try stack.push(&outer_trap, &manager);
    try std.testing.expectEqual(@as(FocusId, 1), manager.focused_id.?);

    // Show inner dialog
    try stack.push(&inner_trap, &manager);
    try std.testing.expectEqual(@as(FocusId, 4), manager.focused_id.?);

    // Tab within inner dialog
    _ = stack.handleTab(true);
    try std.testing.expectEqual(@as(FocusId, 5), manager.focused_id.?);

    // Close inner dialog
    _ = stack.pop();
    try std.testing.expectEqual(@as(usize, 1), stack.depth());

    // Focus should return to outer dialog (still at 1 from before)
    try std.testing.expect(stack.getActive() == &outer_trap);
}
