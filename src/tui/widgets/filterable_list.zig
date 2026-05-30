//! FilterableList widget — searchable list with fuzzy filtering
//!
//! FilterableList displays a list of items that can be filtered using fuzzy search.
//! Only items matching the filter are shown, sorted by match score.
//!
//! ## Features
//! - Fuzzy filtering on item text
//! - Score-based sorting (descending)
//! - Selection navigation with wrapping
//! - Match position tracking
//! - Rendering to Buffer

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const fuzzy = @import("../../fuzzy.zig");
const FuzzyMatcher = fuzzy.FuzzyMatcher;

/// A filtered item with match information
pub const FilteredItem = struct {
    /// The item text
    text: []const u8,
    /// Fuzzy match score (0.0-1.0)
    score: f32,
    /// Byte positions of matched characters
    match_positions: []const u16,
};

/// FilterableList widget
pub const FilterableList = struct {
    allocator: std.mem.Allocator,
    /// All items in the list (PUBLIC — tests access this)
    items: std.ArrayList([]const u8),
    /// Visible items after filtering
    visible: std.ArrayList(FilteredItem),
    /// Current filter string
    filter: []const u8,
    /// Index of selected item in visible list
    selected_index: usize,

    /// Initialize a new filterable list
    pub fn init(alloc: std.mem.Allocator) !FilterableList {
        const items = try std.ArrayList([]const u8).initCapacity(alloc, 8);
        const visible = try std.ArrayList(FilteredItem).initCapacity(alloc, 8);

        return FilterableList{
            .allocator = alloc,
            .items = items,
            .visible = visible,
            .filter = "",
            .selected_index = 0,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FilterableList) void {
        // Free positions in visible items
        for (self.visible.items) |item| {
            if (item.match_positions.len > 0) {
                self.allocator.free(item.match_positions);
            }
        }

        // Free filter if allocated
        if (self.filter.len > 0) {
            self.allocator.free(self.filter);
        }

        self.visible.deinit(self.allocator);
        self.items.deinit(self.allocator);
    }

    /// Set the items in the list
    pub fn setItems(self: *FilterableList, items: []const []const u8) !void {
        self.items.clearRetainingCapacity();

        // Copy items
        for (items) |item| {
            try self.items.append(self.allocator, item);
        }

        // Clamp selection to new size
        if (self.selected_index >= self.items.items.len) {
            self.selected_index = 0;
        }

        // Rebuild visible list with current filter
        try self.rebuildVisible();
    }

    /// Set the filter string and update visible items
    pub fn setFilter(self: *FilterableList, new_filter: []const u8) !void {
        // Free old filter if allocated (non-empty → was duped)
        if (self.filter.len > 0) {
            self.allocator.free(self.filter);
        }

        // Avoid allocating for empty filter — use string literal directly
        if (new_filter.len == 0) {
            self.filter = "";
        } else {
            self.filter = try self.allocator.dupe(u8, new_filter);
        }

        // Rebuild visible items
        try self.rebuildVisible();

        // Reset selection
        self.selected_index = 0;
    }

    /// Clear the filter (show all items)
    pub fn clearFilter(self: *FilterableList) void {
        if (self.filter.len > 0) {
            self.allocator.free(self.filter);
        }
        self.filter = "";

        // Free positions of current visible items
        for (self.visible.items) |item| {
            if (item.match_positions.len > 0) {
                self.allocator.free(item.match_positions);
            }
        }
        self.visible.clearRetainingCapacity();

        // Rebuild with all items (no positions needed — avoids error return)
        self.visible.ensureTotalCapacity(self.allocator, self.items.items.len) catch {};
        for (self.items.items) |item_text| {
            self.visible.append(self.allocator, .{
                .text = item_text,
                .score = 0.0,
                .match_positions = &[_]u16{},
            }) catch {};
        }

        self.selected_index = 0;
    }

    /// Get visible filtered items
    pub fn getVisible(self: *const FilterableList) []const FilteredItem {
        return self.visible.items;
    }

    /// Select next visible item
    pub fn selectNext(self: *FilterableList) void {
        if (self.visible.items.len == 0) return;
        self.selected_index = (self.selected_index + 1) % self.visible.items.len;
    }

    /// Select previous visible item
    pub fn selectPrev(self: *FilterableList) void {
        if (self.visible.items.len == 0) return;
        if (self.selected_index == 0) {
            self.selected_index = self.visible.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
    }

    /// Get currently selected item text
    pub fn getSelected(self: *const FilterableList) ?[]const u8 {
        if (self.visible.items.len == 0 or self.selected_index >= self.visible.items.len) {
            return null;
        }
        return self.visible.items[self.selected_index].text;
    }

    /// Render the list to a buffer
    pub fn render(self: *FilterableList, buf: *Buffer, area: Rect) !void {
        if (self.visible.items.len == 0) return;

        var y: u16 = area.y;
        for (self.visible.items) |item| {
            if (y >= area.y + area.height) break;

            // Write item text
            var x: u16 = area.x;
            for (item.text) |ch| {
                if (x >= area.x + area.width) break;
                buf.set(x, y, .{ .char = ch, .style = .{} });
                x += 1;
            }

            y += 1;
        }
    }

    fn rebuildVisible(self: *FilterableList) !void {
        // Free old visible items and positions
        for (self.visible.items) |item| {
            if (item.match_positions.len > 0) {
                self.allocator.free(item.match_positions);
            }
        }
        self.visible.clearRetainingCapacity();

        // Empty filter shows all items
        if (self.filter.len == 0) {
            for (self.items.items) |item_text| {
                try self.visible.append(self.allocator, FilteredItem{
                    .text = item_text,
                    .score = 0.0,
                    .match_positions = &[_]u16{},
                });
            }
            return;
        }

        // Fuzzy match each item
        // NOTE: FuzzyMatcher uses a static buffer — copy positions before next match call
        for (self.items.items) |item_text| {
            if (FuzzyMatcher.match(self.filter, item_text)) |match_result| {
                const positions_copy = try self.allocator.dupe(u16, match_result.positions);
                try self.visible.append(self.allocator, FilteredItem{
                    .text = item_text,
                    .score = match_result.score,
                    .match_positions = positions_copy,
                });
            }
        }

        // Sort by score descending
        std.mem.sort(FilteredItem, self.visible.items, {}, sortByScoreDescending);
    }

    fn sortByScoreDescending(context: void, a: FilteredItem, b: FilteredItem) bool {
        _ = context;
        return a.score > b.score;
    }
};

test "filterable list init creates empty list" {
    var list = try FilterableList.init(std.testing.allocator);
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 0), list.getVisible().len);
}

test "filterable list setItems stores items" {
    var list = try FilterableList.init(std.testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    try std.testing.expectEqual(@as(usize, 3), list.getVisible().len);
}
