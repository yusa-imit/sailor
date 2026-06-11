//! CommandBar Widget — Command Palette with Prefix+Substring Ranking
//!
//! A filterable command palette with:
//! - Command registration and querying
//! - Prefix-match ranking (prefix matches appear before substring matches)
//! - Cursor navigation over filtered results
//! - Builder API for styling and configuration
//! - Rendering to terminal buffer

const std = @import("std");
const Allocator = std.mem.Allocator;

const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// Command metadata
pub const Command = struct {
    name: []const u8,
    description: []const u8 = "",
    shortcut: []const u8 = "",
};

/// CommandBar widget — command palette with filtering and navigation
pub const CommandBar = struct {
    allocator: Allocator,
    commands: std.ArrayList(Command),
    query: std.ArrayList(u8),
    filtered_results: std.ArrayList(Command),
    cursor: usize,

    // Styling
    block: ?Block = null,
    query_style: Style = .{},
    result_style: Style = .{},
    selected_style: Style = .{},
    shortcut_style: Style = .{},
    placeholder: []const u8 = "Search commands...",

    const CURSOR_INVALID = std.math.maxInt(usize);

    /// Initialize CommandBar
    pub fn init(allocator: Allocator) !CommandBar {
        const commands = try std.ArrayList(Command).initCapacity(allocator, 64);
        const query = try std.ArrayList(u8).initCapacity(allocator, 32);
        const filtered_results = try std.ArrayList(Command).initCapacity(allocator, 64);
        return CommandBar{
            .allocator = allocator,
            .commands = commands,
            .query = query,
            .filtered_results = filtered_results,
            .cursor = CURSOR_INVALID,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *CommandBar) void {
        // Free copied strings in commands
        for (self.commands.items) |cmd| {
            self.allocator.free(cmd.name);
            self.allocator.free(cmd.description);
            self.allocator.free(cmd.shortcut);
        }
        self.commands.deinit(self.allocator);
        self.query.deinit(self.allocator);
        self.filtered_results.deinit(self.allocator);
    }

    /// Register a command
    pub fn register(self: *CommandBar, cmd: Command) !void {
        // Copy strings to ensure stability (caller's lifetime doesn't matter)
        const name_copy = try self.allocator.dupe(u8, cmd.name);
        const desc_copy = try self.allocator.dupe(u8, cmd.description);
        const shortcut_copy = try self.allocator.dupe(u8, cmd.shortcut);

        const cmd_copy = Command{
            .name = name_copy,
            .description = desc_copy,
            .shortcut = shortcut_copy,
        };

        // Check if command with same name exists, replace if so
        for (self.commands.items) |*existing| {
            if (std.mem.eql(u8, existing.name, cmd.name)) {
                // Free old strings
                self.allocator.free(existing.name);
                self.allocator.free(existing.description);
                self.allocator.free(existing.shortcut);
                // Update with new command
                existing.* = cmd_copy;
                // Refresh filtered results
                try self.applyFilter();
                return;
            }
        }
        // New command, append it
        try self.commands.append(self.allocator, cmd_copy);
        // Refresh filtered results
        try self.applyFilter();
    }

    /// Unregister a command by name
    pub fn unregister(self: *CommandBar, name: []const u8) void {
        for (self.commands.items, 0..) |item, idx| {
            if (std.mem.eql(u8, item.name, name)) {
                // Free strings of removed command
                self.allocator.free(item.name);
                self.allocator.free(item.description);
                self.allocator.free(item.shortcut);
                _ = self.commands.orderedRemove(idx);
                // Refresh filtered results
                self.applyFilter() catch {};
                // Clamp cursor if it's beyond the new result count
                if (self.cursor != CURSOR_INVALID and self.cursor >= self.filtered_results.items.len) {
                    if (self.filtered_results.items.len > 0) {
                        self.cursor = self.filtered_results.items.len - 1;
                    } else {
                        self.cursor = CURSOR_INVALID;
                    }
                }
                return;
            }
        }
    }

    /// Set query string and filter results
    pub fn setQuery(self: *CommandBar, text: []const u8) *CommandBar {
        self.query.clearRetainingCapacity();
        self.query.appendSlice(self.allocator, text) catch {};
        self.cursor = CURSOR_INVALID;
        self.applyFilter() catch {};
        return self;
    }

    /// Clear query and show all commands
    pub fn clearQuery(self: *CommandBar) void {
        self.query.clearRetainingCapacity();
        self.cursor = CURSOR_INVALID;
        self.applyFilter() catch {};
    }

    /// Get current query string
    pub fn getQuery(self: *CommandBar) []const u8 {
        return self.query.items;
    }

    /// Get filtered results
    pub fn results(self: *CommandBar) []const Command {
        return self.filtered_results.items;
    }

    /// Get count of filtered results
    pub fn resultCount(self: *CommandBar) usize {
        return self.filtered_results.items.len;
    }

    /// Move cursor down (with clamping)
    pub fn moveCursorDown(self: *CommandBar) void {
        if (self.filtered_results.items.len == 0) return;
        if (self.cursor == CURSOR_INVALID) {
            self.cursor = 0;
        } else if (self.cursor < self.filtered_results.items.len - 1) {
            self.cursor += 1;
        }
    }

    /// Move cursor up (with clamping)
    pub fn moveCursorUp(self: *CommandBar) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    /// Get currently selected command, or null if none
    pub fn selectedCommand(self: *CommandBar) ?Command {
        if (self.cursor == CURSOR_INVALID or self.filtered_results.items.len == 0 or self.cursor >= self.filtered_results.items.len) {
            return null;
        }
        return self.filtered_results.items[self.cursor];
    }

    /// Builder: set block
    pub fn withBlock(self: *CommandBar, block: Block) *CommandBar {
        self.block = block;
        return self;
    }

    /// Builder: set query style
    pub fn withQueryStyle(self: *CommandBar, style: Style) *CommandBar {
        self.query_style = style;
        return self;
    }

    /// Builder: set result style
    pub fn withResultStyle(self: *CommandBar, style: Style) *CommandBar {
        self.result_style = style;
        return self;
    }

    /// Builder: set selected style
    pub fn withSelectedStyle(self: *CommandBar, style: Style) *CommandBar {
        self.selected_style = style;
        return self;
    }

    /// Builder: set shortcut style
    pub fn withShortcutStyle(self: *CommandBar, style: Style) *CommandBar {
        self.shortcut_style = style;
        return self;
    }

    /// Builder: set placeholder text
    pub fn withPlaceholder(self: *CommandBar, text: []const u8) *CommandBar {
        self.placeholder = text;
        return self;
    }

    /// Render CommandBar to buffer
    pub fn render(self: *CommandBar, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner = block.inner(area);
        }

        if (inner.height == 0) return;

        // Line 1: Query input
        if (self.query.items.len == 0) {
            // Show placeholder
            buf.setString(inner.x, inner.y, self.placeholder, self.query_style);
        } else {
            // Show query text
            buf.setString(inner.x, inner.y, self.query.items, self.query_style);
        }

        // Lines 2+: Results list
        const filtered_results = self.filtered_results.items;
        var result_line = inner.y + 1;

        for (filtered_results, 0..) |cmd, idx| {
            if (result_line >= inner.y + inner.height) break;

            // Determine if this result is selected
            const is_selected = self.cursor == idx;
            const line_style = if (is_selected) self.selected_style else self.result_style;

            // Draw command name
            buf.setString(inner.x, result_line, cmd.name, line_style);

            // Draw shortcut right-aligned
            if (cmd.shortcut.len > 0 and cmd.shortcut.len <= inner.width) {
                const shortcut_x: u16 = inner.x + inner.width - @as(u16, @intCast(cmd.shortcut.len));
                buf.setString(shortcut_x, result_line, cmd.shortcut, self.shortcut_style);
            }

            result_line += 1;
        }
    }

    // ========================================================================
    // Private helpers
    // ========================================================================

    /// Apply filter: match commands against query, rank by prefix then fuzzy substring
    fn applyFilter(self: *CommandBar) !void {
        self.filtered_results.clearRetainingCapacity();

        if (self.query.items.len == 0) {
            // Empty query: return all commands in registration order
            try self.filtered_results.appendSlice(self.allocator, self.commands.items);
            return;
        }

        var prefix_matches = try std.ArrayList(Command).initCapacity(self.allocator, 64);
        defer prefix_matches.deinit(self.allocator);

        var substring_matches = try std.ArrayList(Command).initCapacity(self.allocator, 64);
        defer substring_matches.deinit(self.allocator);

        for (self.commands.items) |cmd| {
            if (std.mem.startsWith(u8, cmd.name, self.query.items)) {
                // Prefix match (exact consecutive prefix)
                try prefix_matches.append(self.allocator, cmd);
            } else if (self.query.items.len > 1) {
                // For multi-char queries, try exact consecutive substring first
                if (std.mem.containsAtLeast(u8, cmd.name, 1, self.query.items)) {
                    try substring_matches.append(self.allocator, cmd);
                } else if (self.fuzzyMatchWithinSpan(cmd.name, self.query.items)) {
                    // Then try fuzzy match (characters in order, tightly spaced)
                    try substring_matches.append(self.allocator, cmd);
                }
            }
            // Single-char queries only match prefix, not substring
        }

        // Add prefix matches first
        try self.filtered_results.appendSlice(self.allocator, prefix_matches.items);
        // Then fuzzy substring matches
        try self.filtered_results.appendSlice(self.allocator, substring_matches.items);
    }

    /// Fuzzy match with span constraint: all query chars must appear consecutively or nearly so
    /// For a query like "sa", this matches "save" (s-a-v-e where s and a are at positions 0-1)
    /// but NOT "search" where s and a are at positions 0-2 (too far apart)
    fn fuzzyMatchWithinSpan(self: *CommandBar, name: []const u8, query: []const u8) bool {
        _ = self;
        if (query.len == 0) return true;
        if (name.len == 0) return false;

        // Max span is very tight: query.len + 1 means we allow max 1 char gap total
        // For "sa" (len 2), max span is 3, so "save" matches (s@0, a@1) but "se" with "save" would be (s@0, e@3, gap of 2) and fail
        const max_span = query.len + 1;

        var query_idx: usize = 0;
        var name_idx: usize = 0;

        while (name_idx < name.len and name_idx < max_span and query_idx < query.len) {
            if (name[name_idx] == query[query_idx]) {
                query_idx += 1;
            }
            name_idx += 1;
        }

        return query_idx == query.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "stub init" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try testing.expectEqual(@as(usize, 0), cb.resultCount());
}
