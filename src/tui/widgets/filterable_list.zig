//! FilterableList Widget — v2.25.0
//!
//! Interactive list widget with an embedded text filter input.
//! Items are filtered case-insensitively by substring match.
//! Top row displays "Filter: <str>", remaining rows show filtered items.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Simple case-insensitive substring containment check
fn containsSubstringCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var h_idx: usize = 0;
    while (h_idx <= haystack.len - needle.len) : (h_idx += 1) {
        var match = true;
        for (needle, 0..) |n_char, offset| {
            const h_char = haystack[h_idx + offset];
            if (std.ascii.toLower(n_char) != std.ascii.toLower(h_char)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

/// FilterableList widget — stateful interactive list with incremental filtering
pub const FilterableList = struct {
    /// Source items (immutable, caller-owned)
    items: []const []const u8,
    /// Caller-provided mutable filter buffer
    filter_buf: []u8,
    /// Current filter string length
    filter_len: usize = 0,
    /// Position in filtered results
    cursor: usize = 0,
    /// Style for cursor item
    cursor_style: Style = .{},
    /// Style for non-cursor items
    normal_style: Style = .{},
    /// Style for filter input line
    filter_style: Style = .{},
    /// Symbol for cursor item (default "▶ ")
    cursor_symbol: []const u8 = "▶ ",
    /// Symbol for non-cursor items (default "  ")
    normal_symbol: []const u8 = "  ",
    /// Optional block wrapper
    block: ?Block = null,

    /// Fill a caller-provided scratch buffer with filtered items and return the slice
    /// Case-insensitive substring matching on all items
    pub fn filteredItems(self: FilterableList, scratch: [][]const u8) [][]const u8 {
        const filter_str = self.filter_buf[0..self.filter_len];
        var count: usize = 0;

        for (self.items) |item| {
            if (count >= scratch.len) break;
            if (containsSubstringCaseInsensitive(item, filter_str)) {
                scratch[count] = item;
                count += 1;
            }
        }
        return scratch[0..count];
    }

    /// Append character to filter, clamping at buffer capacity
    pub fn typeChar(self: *FilterableList, c: u8) void {
        if (self.filter_len < self.filter_buf.len) {
            self.filter_buf[self.filter_len] = c;
            self.filter_len += 1;
        }
    }

    /// Remove last character from filter
    pub fn backspace(self: *FilterableList) void {
        if (self.filter_len > 0) {
            self.filter_len -= 1;
        }
    }

    /// Clear the filter completely
    pub fn clearFilter(self: *FilterableList) void {
        self.filter_len = 0;
        self.cursor = 0;
    }

    /// Get the current filter string as a slice
    pub fn getFilter(self: FilterableList) []const u8 {
        return self.filter_buf[0..self.filter_len];
    }

    /// Move cursor up, clamping at 0
    pub fn moveCursorUp(self: *FilterableList) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    /// Move cursor down, clamping at filtered count - 1
    pub fn moveCursorDown(self: *FilterableList, scratch: [][]const u8) void {
        const filtered = self.filteredItems(scratch);
        if (filtered.len > 0 and self.cursor < filtered.len - 1) {
            self.cursor += 1;
        }
    }

    /// Get item at cursor in filtered results, or null if out of bounds
    pub fn getCursorItem(self: FilterableList, scratch: [][]const u8) ?[]const u8 {
        const filtered = self.filteredItems(scratch);
        if (self.cursor < filtered.len) {
            return filtered[self.cursor];
        }
        return null;
    }

    /// Render the FilterableList to a buffer
    /// - Row 0: "Filter: " + filter string (filter_style)
    /// - Rows 1+: filtered items with cursor/normal symbols and styles
    pub fn render(self: FilterableList, buf: *Buffer, area: Rect) void {
        if (area.height == 0 or area.width == 0) {
            return;
        }

        // Handle block wrapper if present
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner_area = block.inner(area);
            if (inner_area.height == 0 or inner_area.width == 0) {
                return;
            }
        }

        // Row 0: Filter line
        const filter_prefix = "Filter: ";
        var col = inner_area.x;

        // Write "Filter: " label
        for (filter_prefix) |ch| {
            if (col >= inner_area.x + inner_area.width) break;
            buf.set(col, inner_area.y, .{
                .char = ch,
                .style = self.filter_style,
            });
            col += 1;
        }

        // Write filter string
        const filter_str = self.filter_buf[0..self.filter_len];
        for (filter_str) |ch| {
            if (col >= inner_area.x + inner_area.width) break;
            buf.set(col, inner_area.y, .{
                .char = ch,
                .style = self.filter_style,
            });
            col += 1;
        }

        // Render filtered items below (starting at row inner_area.y + 1)
        var scratch: [256][]const u8 = undefined;
        const filtered = self.filteredItems(&scratch);

        var item_row: u16 = 1;
        for (filtered, 0..) |item, idx| {
            if (item_row >= inner_area.height) break;

            const screen_y = inner_area.y + item_row;
            var screen_x = inner_area.x;

            // Write cursor or normal symbol
            const symbol = if (idx == self.cursor) self.cursor_symbol else self.normal_symbol;
            const symbol_style = if (idx == self.cursor) self.cursor_style else self.normal_style;

            for (symbol) |ch| {
                if (screen_x >= inner_area.x + inner_area.width) break;
                buf.set(screen_x, screen_y, .{
                    .char = ch,
                    .style = symbol_style,
                });
                screen_x += 1;
            }

            // Write item text
            const item_style = if (idx == self.cursor) self.cursor_style else self.normal_style;
            for (item) |ch| {
                if (screen_x >= inner_area.x + inner_area.width) break;
                buf.set(screen_x, screen_y, .{
                    .char = ch,
                    .style = item_style,
                });
                screen_x += 1;
            }

            item_row += 1;
        }
    }
};

// ============================================================================
// Allocator-based FilterableList for managed scenarios
// ============================================================================

/// A filtered item with match information
pub const FilteredItem = struct {
    /// The item text
    text: []const u8,
    /// Match score (for fuzzy or relevance scoring)
    score: f32,
    /// Byte positions of matched characters
    match_positions: []const u16,
};

/// Allocator-based FilterableList with full management
pub const FilterableListManaged = struct {
    allocator: std.mem.Allocator,
    /// All items in the list
    items: std.ArrayList([]const u8),
    /// Visible items after filtering
    visible: std.ArrayList(FilteredItem),
    /// Current filter string
    filter: []const u8,
    /// Index of selected item in visible list
    selected_index: usize,

    /// Initialize a new managed filterable list
    pub fn init(alloc: std.mem.Allocator) !FilterableListManaged {
        const items = try std.ArrayList([]const u8).initCapacity(alloc, 8);
        const visible = try std.ArrayList(FilteredItem).initCapacity(alloc, 8);

        return FilterableListManaged{
            .allocator = alloc,
            .items = items,
            .visible = visible,
            .filter = "",
            .selected_index = 0,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FilterableListManaged) void {
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
    pub fn setItems(self: *FilterableListManaged, items: []const []const u8) !void {
        self.items.clearRetainingCapacity();

        // Copy items
        for (items) |item| {
            try self.items.append(item);
        }

        // Clamp selection to new size
        if (self.selected_index >= self.items.items.len) {
            self.selected_index = 0;
        }

        // Rebuild visible list with current filter
        try self.rebuildVisible();
    }

    /// Set the filter string and update visible items
    pub fn setFilter(self: *FilterableListManaged, new_filter: []const u8) !void {
        // Free old filter if allocated
        if (self.filter.len > 0) {
            self.allocator.free(self.filter);
        }

        // Avoid allocating for empty filter
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
    pub fn clearFilter(self: *FilterableListManaged) void {
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

        // Rebuild with all items (no positions needed)
        self.visible.ensureTotalCapacity(self.allocator, self.items.items.len) catch {};
        for (self.items.items) |item_text| {
            self.visible.append(.{
                .text = item_text,
                .score = 0.0,
                .match_positions = &[_]u16{},
            }) catch {};
        }

        self.selected_index = 0;
    }

    /// Get visible filtered items
    pub fn getVisible(self: *const FilterableListManaged) []const FilteredItem {
        return self.visible.items;
    }

    /// Select next visible item
    pub fn selectNext(self: *FilterableListManaged) void {
        if (self.visible.items.len == 0) return;
        self.selected_index = (self.selected_index + 1) % self.visible.items.len;
    }

    /// Select previous visible item
    pub fn selectPrev(self: *FilterableListManaged) void {
        if (self.visible.items.len == 0) return;
        if (self.selected_index == 0) {
            self.selected_index = self.visible.items.len - 1;
        } else {
            self.selected_index -= 1;
        }
    }

    /// Get currently selected item text
    pub fn getSelected(self: *const FilterableListManaged) ?[]const u8 {
        if (self.visible.items.len == 0 or self.selected_index >= self.visible.items.len) {
            return null;
        }
        return self.visible.items[self.selected_index].text;
    }

    /// Render the list to a buffer
    pub fn render(self: *FilterableListManaged, buf: *Buffer, area: Rect) !void {
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

    fn rebuildVisible(self: *FilterableListManaged) !void {
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
                try self.visible.append(FilteredItem{
                    .text = item_text,
                    .score = 0.0,
                    .match_positions = &[_]u16{},
                });
            }
            return;
        }

        // Substring match each item
        for (self.items.items) |item_text| {
            if (containsSubstringCaseInsensitive(item_text, self.filter)) {
                // Calculate a basic score: shorter distance to start, longer match = higher
                const score = calculateScore(item_text, self.filter);
                try self.visible.append(FilteredItem{
                    .text = item_text,
                    .score = score,
                    .match_positions = &[_]u16{},
                });
            }
        }

        // Sort by score descending
        std.mem.sort(FilteredItem, self.visible.items, {}, sortByScoreDescending);
    }

    fn sortByScoreDescending(_: void, a: FilteredItem, b: FilteredItem) bool {
        return a.score > b.score;
    }
};

fn calculateScore(item: []const u8, filter: []const u8) f32 {
    // Find position of first match
    var pos: usize = 0;
    for (item) |ch| {
        if (std.ascii.toLower(ch) == std.ascii.toLower(filter[0])) {
            break;
        }
        pos += 1;
    }

    // Prefer matches at start (prefix match gets higher score)
    const prefix_bonus = if (pos == 0) 1.0 else 0.5;
    const length_bonus = @min(1.0, @as(f32, @floatFromInt(filter.len)) / @as(f32, @floatFromInt(item.len)));
    return prefix_bonus + length_bonus;
}
