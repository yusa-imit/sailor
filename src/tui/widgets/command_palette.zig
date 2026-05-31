//! Command Palette widget — searchable command registry with fuzzy matching
//!
//! CommandPalette provides a filterable command palette widget for terminal applications,
//! supporting fuzzy search on command titles and categories.
//!
//! ## Features
//! - Command registration with id, title, category, description
//! - Fuzzy search on title and category
//! - Score-based result sorting
//! - Selection navigation with wrapping
//! - Handler execution
//! - Rendering to Buffer

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const fuzzy = @import("../../fuzzy.zig");
const FuzzyMatcher = fuzzy.FuzzyMatcher;

/// A command that can be executed
pub const Command = struct {
    /// Unique command identifier
    id: []const u8,
    /// Display title
    title: []const u8,
    /// Optional category (e.g., "File", "Edit")
    category: ?[]const u8 = null,
    /// Optional description
    description: ?[]const u8 = null,
    /// Handler function to execute
    handler: *const fn () void,
};

/// Result of a command search
pub const CommandResult = struct {
    /// The command
    command: Command,
    /// Fuzzy match score (0.0-1.0)
    score: f32,
    /// Byte positions of matched characters in title
    match_positions: []const u16,
};

/// CommandPalette widget
pub const CommandPalette = struct {
    allocator: std.mem.Allocator,
    /// Registered commands (PUBLIC — tests access this)
    commands: std.ArrayList(Command),
    /// Current search results
    results: std.ArrayList(CommandResult),
    /// Current query string
    query: []const u8,
    /// Index of selected result
    selected_index: usize,
    /// Fuzzy matcher instance (holds internal buffer — no global state)
    matcher: FuzzyMatcher,

    /// Initialize a new command palette
    pub fn init(alloc: std.mem.Allocator) !CommandPalette {
        const commands = try std.ArrayList(Command).initCapacity(alloc, 8);
        const results = try std.ArrayList(CommandResult).initCapacity(alloc, 8);

        return CommandPalette{
            .allocator = alloc,
            .commands = commands,
            .results = results,
            .query = "",
            .selected_index = 0,
            .matcher = FuzzyMatcher{},
        };
    }

    /// Clean up resources
    pub fn deinit(self: *CommandPalette) void {
        // Free any allocated query string
        if (self.query.len > 0) {
            self.allocator.free(self.query);
        }

        // Free positions in results
        for (self.results.items) |result| {
            if (result.match_positions.len > 0) {
                self.allocator.free(result.match_positions);
            }
        }

        self.results.deinit(self.allocator);
        self.commands.deinit(self.allocator);
    }

    /// Register a command
    pub fn register(self: *CommandPalette, cmd: Command) !void {
        try self.commands.append(self.allocator, cmd);
    }

    /// Set the search query and update results
    pub fn setQuery(self: *CommandPalette, new_query: []const u8) !void {
        // Free old query if it was allocated (non-empty → was duped)
        if (self.query.len > 0) {
            self.allocator.free(self.query);
        }

        // Avoid allocating for empty queries — use string literal directly
        if (new_query.len == 0) {
            self.query = "";
        } else {
            self.query = try self.allocator.dupe(u8, new_query);
        }

        // Rebuild results
        try self.rebuildResults();

        // Reset selection
        self.selected_index = 0;
    }

    /// Get current search results
    pub fn getResults(self: *const CommandPalette) []const CommandResult {
        return self.results.items;
    }

    /// Select next result
    pub fn selectNext(self: *CommandPalette) void {
        if (self.results.items.len == 0) return;
        self.selected_index = (self.selected_index + 1) % self.results.items.len;
    }

    /// Select previous result
    pub fn selectPrev(self: *CommandPalette) void {
        if (self.results.items.len == 0) return;
        if (self.selected_index == 0) {
            self.selected_index = self.results.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
    }

    /// Get currently selected command result
    pub fn getSelected(self: *const CommandPalette) ?CommandResult {
        if (self.results.items.len == 0 or self.selected_index >= self.results.items.len) {
            return null;
        }
        return self.results.items[self.selected_index];
    }

    /// Execute the handler of the selected command
    pub fn activate(self: *CommandPalette) void {
        if (self.getSelected()) |selected| {
            selected.command.handler();
        }
    }

    /// Render the palette to a buffer
    pub fn render(self: *CommandPalette, buf: *Buffer, area: Rect) !void {
        if (self.results.items.len == 0) return;

        var y: u16 = area.y;
        for (self.results.items) |result| {
            if (y >= area.y + area.height) break;

            // Write command title
            var x: u16 = area.x;
            for (result.command.title) |ch| {
                if (x >= area.x + area.width) break;
                buf.set(x, y, .{ .char = ch, .style = .{} });
                x += 1;
            }

            y += 1;
        }
    }

    fn rebuildResults(self: *CommandPalette) !void {
        // Free old results and positions
        for (self.results.items) |result| {
            if (result.match_positions.len > 0) {
                self.allocator.free(result.match_positions);
            }
        }
        self.results.clearRetainingCapacity();

        // Empty query shows all commands
        if (self.query.len == 0) {
            for (self.commands.items) |cmd| {
                try self.results.append(self.allocator, CommandResult{
                    .command = cmd,
                    .score = 0.0,
                    .match_positions = &[_]u16{},
                });
            }
            return;
        }

        // Fuzzy match each command against query
        for (self.commands.items) |cmd| {
            var best_score: f32 = 0.0;
            var best_positions: []const u16 = &[_]u16{};
            var positions_owned = false;

            // Try title match — copy positions before next match() overwrites the buffer
            if (self.matcher.match(self.query, cmd.title)) |title_match| {
                best_score = title_match.score;
                const owned = try self.allocator.dupe(u16, title_match.positions);
                best_positions = owned;
                positions_owned = true;
            }

            // Try category match
            if (cmd.category) |cat| {
                if (self.matcher.match(self.query, cat)) |cat_match| {
                    if (cat_match.score > best_score) {
                        if (positions_owned) self.allocator.free(best_positions);
                        const owned = try self.allocator.dupe(u16, cat_match.positions);
                        best_score = cat_match.score;
                        best_positions = owned;
                        positions_owned = true;
                    }
                }
            }

            if (best_score > 0.0) {
                try self.results.append(self.allocator, CommandResult{
                    .command = cmd,
                    .score = best_score,
                    .match_positions = best_positions,
                });
            } else if (positions_owned) {
                self.allocator.free(best_positions);
            }
        }

        // Sort by score descending
        std.mem.sort(CommandResult, self.results.items, {}, sortByScoreDescending);
    }

    fn sortByScoreDescending(context: void, a: CommandResult, b: CommandResult) bool {
        _ = context;
        return a.score > b.score;
    }
};

test "command palette init creates empty palette" {
    var palette = try CommandPalette.init(std.testing.allocator);
    defer palette.deinit();

    try std.testing.expectEqual(@as(usize, 0), palette.commands.items.len);
}

test "command palette register single command" {
    var palette = try CommandPalette.init(std.testing.allocator);
    defer palette.deinit();

    const cmd = Command{
        .id = "test",
        .title = "Test",
        .handler = testHandler,
    };
    try palette.register(cmd);
    try std.testing.expectEqual(@as(usize, 1), palette.commands.items.len);
}

fn testHandler() void {}
