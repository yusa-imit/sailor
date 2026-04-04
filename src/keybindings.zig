const std = @import("std");
const tui = @import("tui/tui.zig");
const KeyCode = tui.KeyCode;
const Modifiers = tui.Modifiers;

/// Key binding action
pub const Action = union(enum) {
    /// Execute a command by name
    command: []const u8,
    /// Execute a callback function
    callback: *const fn (*anyopaque) void,
    /// Insert text at cursor
    insert: []const u8,
    /// Navigate in a direction
    navigate: Direction,
    /// Focus action
    focus: FocusAction,
    /// Clipboard action
    clipboard: ClipboardAction,
    /// Edit action
    edit: EditAction,

    pub const Direction = enum {
        up,
        down,
        left,
        right,
        page_up,
        page_down,
        home,
        end,
    };

    pub const FocusAction = enum {
        next,
        prev,
        first,
        last,
    };

    pub const ClipboardAction = enum {
        copy,
        cut,
        paste,
    };

    pub const EditAction = enum {
        undo,
        redo,
        select_all,
        delete,
        backspace,
    };
};

/// A single key binding
pub const Binding = struct {
    /// Key to bind
    key: KeyCode,
    /// Required modifiers
    mods: Modifiers = .{},
    /// Action to execute
    action: Action,
    /// Optional description for help text
    description: ?[]const u8 = null,
};

/// Key binding registry for a widget or application
pub const KeyBindings = struct {
    bindings: std.ArrayList(Binding),
    allocator: std.mem.Allocator,

    /// Initialize an empty keybindings registry.
    /// Call deinit() to free the bindings list.
    pub fn init(allocator: std.mem.Allocator) KeyBindings {
        return .{
            .allocator = allocator,
            .bindings = std.ArrayList(Binding){},
        };
    }

    /// Free the bindings list.
    pub fn deinit(self: *KeyBindings) void {
        self.bindings.deinit(self.allocator);
    }

    /// Register a key binding
    pub fn bind(self: *KeyBindings, binding: Binding) !void {
        try self.bindings.append(self.allocator, binding);
    }

    /// Register a key to command binding
    pub fn bindCommand(self: *KeyBindings, key: KeyCode, command: []const u8, description: ?[]const u8) !void {
        try self.bind(.{
            .key = key,
            .action = .{ .command = command },
            .description = description,
        });
    }

    /// Register a key with modifiers to command binding
    pub fn bindCommandWithMods(self: *KeyBindings, key: KeyCode, mods: Modifiers, command: []const u8, description: ?[]const u8) !void {
        try self.bind(.{
            .key = key,
            .mods = mods,
            .action = .{ .command = command },
            .description = description,
        });
    }

    /// Find binding for a key
    pub fn find(self: *const KeyBindings, key: KeyCode) ?Binding {
        for (self.bindings.items) |binding| {
            if (std.meta.eql(binding.key, key)) {
                return binding;
            }
        }
        return null;
    }

    /// Find binding for a key with modifiers
    pub fn findWithMods(self: *const KeyBindings, key: KeyCode, mods: Modifiers) ?Binding {
        for (self.bindings.items) |binding| {
            if (std.meta.eql(binding.key, key) and std.meta.eql(binding.mods, mods)) {
                return binding;
            }
        }
        return null;
    }

    /// Get all bindings
    pub fn all(self: *const KeyBindings) []const Binding {
        return self.bindings.items;
    }

    /// Clear all bindings
    pub fn clear(self: *KeyBindings) void {
        self.bindings.clearRetainingCapacity();
    }

    /// Remove a specific binding
    pub fn unbind(self: *KeyBindings, key: KeyCode) bool {
        for (self.bindings.items, 0..) |binding, i| {
            if (std.meta.eql(binding.key, key)) {
                _ = self.bindings.swapRemove(i);
                return true;
            }
        }
        return false;
    }
};

/// Common key binding presets
pub const Presets = struct {
    /// Vim-style navigation bindings
    pub fn vim(allocator: std.mem.Allocator) !KeyBindings {
        var kb = KeyBindings.init(allocator);

        try kb.bindCommand(.{ .char = 'h' }, "move_left", "Move left");
        try kb.bindCommand(.{ .char = 'j' }, "move_down", "Move down");
        try kb.bindCommand(.{ .char = 'k' }, "move_up", "Move up");
        try kb.bindCommand(.{ .char = 'l' }, "move_right", "Move right");
        try kb.bindCommand(.{ .char = 'g' }, "goto_top", "Go to top");
        try kb.bindCommand(.{ .char = 'G' }, "goto_bottom", "Go to bottom");

        return kb;
    }

    /// Emacs-style navigation bindings
    pub fn emacs(allocator: std.mem.Allocator) !KeyBindings {
        var kb = KeyBindings.init(allocator);

        // Ctrl bindings
        try kb.bindCommandWithMods(.{ .char = 'b' }, .{ .ctrl = true }, "move_left", "Move left (Ctrl+B)");
        try kb.bindCommandWithMods(.{ .char = 'f' }, .{ .ctrl = true }, "move_right", "Move right (Ctrl+F)");
        try kb.bindCommandWithMods(.{ .char = 'n' }, .{ .ctrl = true }, "move_down", "Move down (Ctrl+N)");
        try kb.bindCommandWithMods(.{ .char = 'p' }, .{ .ctrl = true }, "move_up", "Move up (Ctrl+P)");
        try kb.bindCommandWithMods(.{ .char = 'a' }, .{ .ctrl = true }, "goto_line_start", "Go to line start (Ctrl+A)");
        try kb.bindCommandWithMods(.{ .char = 'e' }, .{ .ctrl = true }, "goto_line_end", "Go to line end (Ctrl+E)");

        return kb;
    }

    /// Default arrow key navigation
    pub fn arrows(allocator: std.mem.Allocator) !KeyBindings {
        var kb = KeyBindings.init(allocator);

        try kb.bind(.{
            .key = .up,
            .action = .{ .navigate = .up },
            .description = "Move up",
        });
        try kb.bind(.{
            .key = .down,
            .action = .{ .navigate = .down },
            .description = "Move down",
        });
        try kb.bind(.{
            .key = .left,
            .action = .{ .navigate = .left },
            .description = "Move left",
        });
        try kb.bind(.{
            .key = .right,
            .action = .{ .navigate = .right },
            .description = "Move right",
        });
        try kb.bind(.{
            .key = .page_up,
            .action = .{ .navigate = .page_up },
            .description = "Page up",
        });
        try kb.bind(.{
            .key = .page_down,
            .action = .{ .navigate = .page_down },
            .description = "Page down",
        });
        try kb.bind(.{
            .key = .home,
            .action = .{ .navigate = .home },
            .description = "Go to start",
        });
        try kb.bind(.{
            .key = .end,
            .action = .{ .navigate = .end },
            .description = "Go to end",
        });

        return kb;
    }

    /// Tab focus navigation
    pub fn tabFocus(allocator: std.mem.Allocator) !KeyBindings {
        var kb = KeyBindings.init(allocator);

        try kb.bind(.{
            .key = .tab,
            .action = .{ .focus = .next },
            .description = "Focus next widget",
        });
        // Shift+Tab for prev (handled via modifiers)
        try kb.bind(.{
            .key = .tab,
            .mods = .{ .shift = true },
            .action = .{ .focus = .prev },
            .description = "Focus previous widget (Shift+Tab)",
        });

        return kb;
    }

    /// Standard keyboard shortcuts (copy, paste, cut, undo, etc.)
    pub fn standard(allocator: std.mem.Allocator) !KeyBindings {
        var kb = KeyBindings.init(allocator);

        // Clipboard shortcuts
        try kb.bind(.{
            .key = .{ .char = 'c' },
            .mods = .{ .ctrl = true },
            .action = .{ .clipboard = .copy },
            .description = "Copy (Ctrl+C)",
        });
        try kb.bind(.{
            .key = .{ .char = 'x' },
            .mods = .{ .ctrl = true },
            .action = .{ .clipboard = .cut },
            .description = "Cut (Ctrl+X)",
        });
        try kb.bind(.{
            .key = .{ .char = 'v' },
            .mods = .{ .ctrl = true },
            .action = .{ .clipboard = .paste },
            .description = "Paste (Ctrl+V)",
        });

        // Edit shortcuts
        try kb.bind(.{
            .key = .{ .char = 'z' },
            .mods = .{ .ctrl = true },
            .action = .{ .edit = .undo },
            .description = "Undo (Ctrl+Z)",
        });
        try kb.bind(.{
            .key = .{ .char = 'y' },
            .mods = .{ .ctrl = true },
            .action = .{ .edit = .redo },
            .description = "Redo (Ctrl+Y)",
        });
        try kb.bind(.{
            .key = .{ .char = 'a' },
            .mods = .{ .ctrl = true },
            .action = .{ .edit = .select_all },
            .description = "Select all (Ctrl+A)",
        });

        // Delete/Backspace
        try kb.bind(.{
            .key = .delete,
            .action = .{ .edit = .delete },
            .description = "Delete",
        });
        try kb.bind(.{
            .key = .backspace,
            .action = .{ .edit = .backspace },
            .description = "Backspace",
        });

        return kb;
    }
};

test "keybindings: init and deinit" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try std.testing.expectEqual(@as(usize, 0), kb.bindings.items.len);
}

test "keybindings: bind command" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bindCommand(.{ .char = 'q' }, "quit", "Quit application");

    try std.testing.expectEqual(@as(usize, 1), kb.bindings.items.len);
    const binding = kb.bindings.items[0];
    try std.testing.expectEqual(KeyCode{ .char = 'q' }, binding.key);
    try std.testing.expectEqualStrings("quit", binding.action.command);
}

test "keybindings: find binding" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bindCommand(.{ .char = 'q' }, "quit", null);

    const found = kb.find(.{ .char = 'q' });
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("quit", found.?.action.command);
}

test "keybindings: find nonexistent binding" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    const found = kb.find(.{ .char = 'q' });
    try std.testing.expect(found == null);
}

test "keybindings: unbind" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bindCommand(.{ .char = 'q' }, "quit", null);
    try std.testing.expectEqual(@as(usize, 1), kb.bindings.items.len);

    const removed = kb.unbind(.{ .char = 'q' });
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 0), kb.bindings.items.len);
}

test "keybindings: clear" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bindCommand(.{ .char = 'q' }, "quit", null);
    try kb.bindCommand(.{ .char = 'h' }, "help", null);

    kb.clear();
    try std.testing.expectEqual(@as(usize, 0), kb.bindings.items.len);
}

test "keybindings: vim preset" {
    var kb = try Presets.vim(std.testing.allocator);
    defer kb.deinit();

    const h_binding = kb.find(.{ .char = 'h' });
    try std.testing.expect(h_binding != null);
    try std.testing.expectEqualStrings("move_left", h_binding.?.action.command);
}

test "keybindings: emacs preset" {
    var kb = try Presets.emacs(std.testing.allocator);
    defer kb.deinit();

    // Ctrl+B
    const b_binding = kb.findWithMods(.{ .char = 'b' }, .{ .ctrl = true });
    try std.testing.expect(b_binding != null);
    try std.testing.expectEqualStrings("move_left", b_binding.?.action.command);
}

test "keybindings: arrows preset" {
    var kb = try Presets.arrows(std.testing.allocator);
    defer kb.deinit();

    const up_binding = kb.find(.up);
    try std.testing.expect(up_binding != null);
    try std.testing.expectEqual(Action.Direction.up, up_binding.?.action.navigate);
}

test "keybindings: tab focus preset" {
    var kb = try Presets.tabFocus(std.testing.allocator);
    defer kb.deinit();

    const tab_binding = kb.find(.tab);
    try std.testing.expect(tab_binding != null);
    try std.testing.expectEqual(Action.FocusAction.next, tab_binding.?.action.focus);
}

test "keybindings: bind with modifiers" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bindCommandWithMods(.{ .char = 's' }, .{ .ctrl = true }, "save", "Save file");

    const found = kb.findWithMods(.{ .char = 's' }, .{ .ctrl = true });
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("save", found.?.action.command);
}

test "keybindings: navigate action" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bind(.{
        .key = .up,
        .action = .{ .navigate = .up },
    });

    const found = kb.find(.up);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(Action.Direction.up, found.?.action.navigate);
}

test "keybindings: focus action" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bind(.{
        .key = .tab,
        .action = .{ .focus = .next },
    });

    const found = kb.find(.tab);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(Action.FocusAction.next, found.?.action.focus);
}

test "keybindings: standard shortcuts preset" {
    var kb = try Presets.standard(std.testing.allocator);
    defer kb.deinit();

    // Test copy (Ctrl+C)
    const copy_binding = kb.findWithMods(.{ .char = 'c' }, .{ .ctrl = true });
    try std.testing.expect(copy_binding != null);
    try std.testing.expectEqual(Action.ClipboardAction.copy, copy_binding.?.action.clipboard);

    // Test paste (Ctrl+V)
    const paste_binding = kb.findWithMods(.{ .char = 'v' }, .{ .ctrl = true });
    try std.testing.expect(paste_binding != null);
    try std.testing.expectEqual(Action.ClipboardAction.paste, paste_binding.?.action.clipboard);

    // Test cut (Ctrl+X)
    const cut_binding = kb.findWithMods(.{ .char = 'x' }, .{ .ctrl = true });
    try std.testing.expect(cut_binding != null);
    try std.testing.expectEqual(Action.ClipboardAction.cut, cut_binding.?.action.clipboard);
}

test "keybindings: standard undo/redo" {
    var kb = try Presets.standard(std.testing.allocator);
    defer kb.deinit();

    // Test undo (Ctrl+Z)
    const undo_binding = kb.findWithMods(.{ .char = 'z' }, .{ .ctrl = true });
    try std.testing.expect(undo_binding != null);
    try std.testing.expectEqual(Action.EditAction.undo, undo_binding.?.action.edit);

    // Test redo (Ctrl+Y)
    const redo_binding = kb.findWithMods(.{ .char = 'y' }, .{ .ctrl = true });
    try std.testing.expect(redo_binding != null);
    try std.testing.expectEqual(Action.EditAction.redo, redo_binding.?.action.edit);
}

test "keybindings: standard select all" {
    var kb = try Presets.standard(std.testing.allocator);
    defer kb.deinit();

    // Test select all (Ctrl+A)
    const select_binding = kb.findWithMods(.{ .char = 'a' }, .{ .ctrl = true });
    try std.testing.expect(select_binding != null);
    try std.testing.expectEqual(Action.EditAction.select_all, select_binding.?.action.edit);
}

test "keybindings: standard delete/backspace" {
    var kb = try Presets.standard(std.testing.allocator);
    defer kb.deinit();

    // Test delete
    const delete_binding = kb.find(.delete);
    try std.testing.expect(delete_binding != null);
    try std.testing.expectEqual(Action.EditAction.delete, delete_binding.?.action.edit);

    // Test backspace
    const backspace_binding = kb.find(.backspace);
    try std.testing.expect(backspace_binding != null);
    try std.testing.expectEqual(Action.EditAction.backspace, backspace_binding.?.action.edit);
}

test "keybindings: clipboard action" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bind(.{
        .key = .{ .char = 'c' },
        .mods = .{ .ctrl = true },
        .action = .{ .clipboard = .copy },
    });

    const found = kb.findWithMods(.{ .char = 'c' }, .{ .ctrl = true });
    try std.testing.expect(found != null);
    try std.testing.expectEqual(Action.ClipboardAction.copy, found.?.action.clipboard);
}

test "keybindings: edit action" {
    var kb = KeyBindings.init(std.testing.allocator);
    defer kb.deinit();

    try kb.bind(.{
        .key = .{ .char = 'z' },
        .mods = .{ .ctrl = true },
        .action = .{ .edit = .undo },
    });

    const found = kb.findWithMods(.{ .char = 'z' }, .{ .ctrl = true });
    try std.testing.expect(found != null);
    try std.testing.expectEqual(Action.EditAction.undo, found.?.action.edit);
}
