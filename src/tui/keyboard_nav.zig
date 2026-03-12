const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const focus_mod = @import("../focus.zig");
const FocusManager = focus_mod.FocusManager;

/// Keyboard-only navigation improvements for accessibility.
/// Provides skip links, focus indicators, and navigation shortcuts.
pub const KeyboardNavigator = struct {
    allocator: Allocator,
    skip_links: ArrayList(SkipLink),
    focus_indicator_style: FocusIndicatorStyle,
    visible_focus: bool,

    pub const SkipLink = struct {
        name: []const u8,
        target_id: []const u8,
        shortcut: ?[]const u8,
    };

    pub const FocusIndicatorStyle = enum {
        none, // No visual focus indicator
        outline, // Simple outline (default)
        highlight, // Background highlight
        bold_outline, // Thick outline with color
        custom, // User-defined style
    };

    pub fn init(allocator: Allocator) KeyboardNavigator {
        return .{
            .allocator = allocator,
            .skip_links = ArrayList(SkipLink){},
            .focus_indicator_style = .outline,
            .visible_focus = true,
        };
    }

    pub fn deinit(self: *KeyboardNavigator) void {
        for (self.skip_links.items) |link| {
            self.allocator.free(link.name);
            self.allocator.free(link.target_id);
            if (link.shortcut) |shortcut| {
                self.allocator.free(shortcut);
            }
        }
        self.skip_links.deinit(self.allocator);
    }

    /// Add a skip link (e.g., "Skip to main content")
    pub fn addSkipLink(self: *KeyboardNavigator, name: []const u8, target_id: []const u8, shortcut: ?[]const u8) !void {
        const skip_link = SkipLink{
            .name = try self.allocator.dupe(u8, name),
            .target_id = try self.allocator.dupe(u8, target_id),
            .shortcut = if (shortcut) |s| try self.allocator.dupe(u8, s) else null,
        };
        try self.skip_links.append(self.allocator, skip_link);
    }

    /// Get all skip links
    pub fn getSkipLinks(self: *const KeyboardNavigator) []const SkipLink {
        return self.skip_links.items;
    }

    /// Find skip link by shortcut
    pub fn findSkipLinkByShortcut(self: *const KeyboardNavigator, shortcut: []const u8) ?SkipLink {
        for (self.skip_links.items) |link| {
            if (link.shortcut) |s| {
                if (std.mem.eql(u8, s, shortcut)) {
                    return link;
                }
            }
        }
        return null;
    }

    /// Set focus indicator style
    pub fn setFocusIndicatorStyle(self: *KeyboardNavigator, style: FocusIndicatorStyle) void {
        self.focus_indicator_style = style;
    }

    /// Enable or disable visible focus
    pub fn setVisibleFocus(self: *KeyboardNavigator, visible: bool) void {
        self.visible_focus = visible;
    }

    /// Get focus indicator characters based on style
    pub fn getFocusIndicator(self: *const KeyboardNavigator) FocusIndicator {
        if (!self.visible_focus) {
            return .{
                .top_left = ' ',
                .top_right = ' ',
                .bottom_left = ' ',
                .bottom_right = ' ',
                .horizontal = ' ',
                .vertical = ' ',
            };
        }

        return switch (self.focus_indicator_style) {
            .none => .{
                .top_left = ' ',
                .top_right = ' ',
                .bottom_left = ' ',
                .bottom_right = ' ',
                .horizontal = ' ',
                .vertical = ' ',
            },
            .outline => .{
                .top_left = '┌',
                .top_right = '┐',
                .bottom_left = '└',
                .bottom_right = '┘',
                .horizontal = '─',
                .vertical = '│',
            },
            .bold_outline => .{
                .top_left = '┏',
                .top_right = '┓',
                .bottom_left = '┗',
                .bottom_right = '┛',
                .horizontal = '━',
                .vertical = '┃',
            },
            .highlight => .{
                .top_left = '▛',
                .top_right = '▜',
                .bottom_left = '▙',
                .bottom_right = '▟',
                .horizontal = '▀',
                .vertical = '▌',
            },
            .custom => .{
                .top_left = '╔',
                .top_right = '╗',
                .bottom_left = '╚',
                .bottom_right = '╝',
                .horizontal = '═',
                .vertical = '║',
            },
        };
    }

    pub const FocusIndicator = struct {
        top_left: u21,
        top_right: u21,
        bottom_left: u21,
        bottom_right: u21,
        horizontal: u21,
        vertical: u21,
    };
};

/// Navigation hints for keyboard users
pub const NavigationHints = struct {
    allocator: Allocator,
    hints: ArrayList(Hint),

    pub const Hint = struct {
        key: []const u8,
        description: []const u8,
        category: Category,

        pub const Category = enum {
            navigation,
            focus,
            action,
            editing,
            help,
        };
    };

    pub fn init(allocator: Allocator) NavigationHints {
        return .{
            .allocator = allocator,
            .hints = ArrayList(Hint){},
        };
    }

    pub fn deinit(self: *NavigationHints) void {
        for (self.hints.items) |hint| {
            self.allocator.free(hint.key);
            self.allocator.free(hint.description);
        }
        self.hints.deinit(self.allocator);
    }

    /// Add a navigation hint
    pub fn addHint(self: *NavigationHints, key: []const u8, description: []const u8, category: Hint.Category) !void {
        const hint = Hint{
            .key = try self.allocator.dupe(u8, key),
            .description = try self.allocator.dupe(u8, description),
            .category = category,
        };
        try self.hints.append(self.allocator, hint);
    }

    /// Get hints by category
    pub fn getHintsByCategory(self: *const NavigationHints, allocator: Allocator, category: Hint.Category) ![]const Hint {
        var filtered: ArrayList(Hint) = .{};
        errdefer filtered.deinit(allocator);

        for (self.hints.items) |hint| {
            if (hint.category == category) {
                try filtered.append(allocator, hint);
            }
        }

        return filtered.toOwnedSlice(allocator);
    }

    /// Generate standard navigation hints
    pub fn addStandardHints(self: *NavigationHints) !void {
        // Navigation
        try self.addHint("Tab", "Next focusable element", .focus);
        try self.addHint("Shift+Tab", "Previous focusable element", .focus);
        try self.addHint("Arrow keys", "Navigate within widget", .navigation);
        try self.addHint("Home", "Go to start", .navigation);
        try self.addHint("End", "Go to end", .navigation);
        try self.addHint("Page Up", "Scroll up one page", .navigation);
        try self.addHint("Page Down", "Scroll down one page", .navigation);

        // Actions
        try self.addHint("Enter", "Activate/Select", .action);
        try self.addHint("Space", "Toggle/Select", .action);
        try self.addHint("Esc", "Cancel/Close", .action);

        // Editing
        try self.addHint("Ctrl+A", "Select all", .editing);
        try self.addHint("Ctrl+C", "Copy", .editing);
        try self.addHint("Ctrl+X", "Cut", .editing);
        try self.addHint("Ctrl+V", "Paste", .editing);
        try self.addHint("Ctrl+Z", "Undo", .editing);

        // Help
        try self.addHint("F1", "Help", .help);
        try self.addHint("?", "Show shortcuts", .help);
    }

    /// Format hints as text
    pub fn formatHints(self: *const NavigationHints, allocator: Allocator) ![]const u8 {
        var buf: ArrayList(u8) = .{};
        defer buf.deinit(allocator);
        const writer = buf.writer(allocator);

        try writer.writeAll("Keyboard Navigation:\n\n");

        const categories = [_]Hint.Category{ .navigation, .focus, .action, .editing, .help };
        const category_names = [_][]const u8{ "Navigation", "Focus", "Actions", "Editing", "Help" };

        for (categories, category_names) |category, name| {
            const hints = try self.getHintsByCategory(allocator, category);
            defer allocator.free(hints);

            if (hints.len > 0) {
                try writer.print("{s}:\n", .{name});
                for (hints) |hint| {
                    try writer.print("  {s:<20} {s}\n", .{ hint.key, hint.description });
                }
                try writer.writeAll("\n");
            }
        }

        return buf.toOwnedSlice(allocator);
    }
};

// Tests
test "KeyboardNavigator: init and deinit" {
    const allocator = std.testing.allocator;
    var nav = KeyboardNavigator.init(allocator);
    defer nav.deinit();

    try std.testing.expect(nav.visible_focus);
    try std.testing.expectEqual(KeyboardNavigator.FocusIndicatorStyle.outline, nav.focus_indicator_style);
}

test "KeyboardNavigator: add skip links" {
    const allocator = std.testing.allocator;
    var nav = KeyboardNavigator.init(allocator);
    defer nav.deinit();

    try nav.addSkipLink("Skip to main content", "main", "1");
    try nav.addSkipLink("Skip to navigation", "nav", "2");

    const links = nav.getSkipLinks();
    try std.testing.expectEqual(@as(usize, 2), links.len);
    try std.testing.expectEqualStrings("Skip to main content", links[0].name);
    try std.testing.expectEqualStrings("main", links[0].target_id);
}

test "KeyboardNavigator: find skip link by shortcut" {
    const allocator = std.testing.allocator;
    var nav = KeyboardNavigator.init(allocator);
    defer nav.deinit();

    try nav.addSkipLink("Skip to main", "main", "Ctrl+1");
    try nav.addSkipLink("Skip to footer", "footer", "Ctrl+2");

    const link = nav.findSkipLinkByShortcut("Ctrl+1");
    try std.testing.expect(link != null);
    try std.testing.expectEqualStrings("Skip to main", link.?.name);

    const not_found = nav.findSkipLinkByShortcut("Ctrl+9");
    try std.testing.expect(not_found == null);
}

test "KeyboardNavigator: focus indicator styles" {
    const allocator = std.testing.allocator;
    var nav = KeyboardNavigator.init(allocator);
    defer nav.deinit();

    nav.setFocusIndicatorStyle(.outline);
    const outline = nav.getFocusIndicator();
    try std.testing.expectEqual(@as(u21, '┌'), outline.top_left);

    nav.setFocusIndicatorStyle(.bold_outline);
    const bold = nav.getFocusIndicator();
    try std.testing.expectEqual(@as(u21, '┏'), bold.top_left);

    nav.setFocusIndicatorStyle(.highlight);
    const highlight = nav.getFocusIndicator();
    try std.testing.expectEqual(@as(u21, '▛'), highlight.top_left);
}

test "KeyboardNavigator: disable visible focus" {
    const allocator = std.testing.allocator;
    var nav = KeyboardNavigator.init(allocator);
    defer nav.deinit();

    nav.setVisibleFocus(false);
    const indicator = nav.getFocusIndicator();
    try std.testing.expectEqual(@as(u21, ' '), indicator.top_left);
}

test "NavigationHints: init and deinit" {
    const allocator = std.testing.allocator;
    var hints = NavigationHints.init(allocator);
    defer hints.deinit();

    try std.testing.expectEqual(@as(usize, 0), hints.hints.items.len);
}

test "NavigationHints: add hints" {
    const allocator = std.testing.allocator;
    var hints = NavigationHints.init(allocator);
    defer hints.deinit();

    try hints.addHint("Tab", "Next element", .focus);
    try hints.addHint("Enter", "Activate", .action);

    try std.testing.expectEqual(@as(usize, 2), hints.hints.items.len);
}

test "NavigationHints: get by category" {
    const allocator = std.testing.allocator;
    var hints = NavigationHints.init(allocator);
    defer hints.deinit();

    try hints.addHint("Tab", "Next", .focus);
    try hints.addHint("Enter", "Activate", .action);
    try hints.addHint("Shift+Tab", "Previous", .focus);

    const focus_hints = try hints.getHintsByCategory(allocator, .focus);
    defer allocator.free(focus_hints);

    try std.testing.expectEqual(@as(usize, 2), focus_hints.len);
}

test "NavigationHints: add standard hints" {
    const allocator = std.testing.allocator;
    var hints = NavigationHints.init(allocator);
    defer hints.deinit();

    try hints.addStandardHints();

    try std.testing.expect(hints.hints.items.len > 10);
}

test "NavigationHints: format hints" {
    const allocator = std.testing.allocator;
    var hints = NavigationHints.init(allocator);
    defer hints.deinit();

    try hints.addHint("Tab", "Next element", .focus);
    try hints.addHint("Enter", "Activate", .action);

    const formatted = try hints.formatHints(allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "Keyboard Navigation:") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Tab") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Enter") != null);
}
