//! FilterBar Widget — Multi-tag filter input bar with pill rendering
//!
//! A filterable tag display widget with:
//! - Dynamic tag management (add, remove, toggle active state)
//! - String duplication for memory independence
//! - Builder API for styling configuration
//! - Pill-based rendering with active/inactive styling
//! - Support for optional borders and custom placeholders

const std = @import("std");
const Allocator = std.mem.Allocator;

const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// A single filter tag
pub const FilterTag = struct {
    key: []const u8,   // owned (duped), freed on removeTag/clearAll/deinit
    value: []const u8, // owned (duped)
    active: bool,
};

/// FilterBar widget — dynamic tag list with pill rendering
pub const FilterBar = struct {
    allocator: Allocator,
    tags: std.ArrayList(FilterTag),

    block: ?Block = null,
    tag_style: Style = .{},
    active_style: Style = .{},
    inactive_style: Style = .{},
    placeholder: []const u8 = "No filters",

    /// Initialize FilterBar with empty tag list
    pub fn init(allocator: Allocator) FilterBar {
        // Use initCapacity with 0 to get an empty list
        const tags = std.ArrayList(FilterTag).initCapacity(allocator, 0) catch {
            // If allocation fails, return with an empty manually-constructed list
            return FilterBar{
                .allocator = allocator,
                .tags = .{
                    .items = &[_]FilterTag{},
                    .capacity = 0,
                },
            };
        };
        return FilterBar{
            .allocator = allocator,
            .tags = tags,
        };
    }

    /// Deinit: free all duped strings and the ArrayList
    pub fn deinit(self: *FilterBar) void {
        // Free all duped strings in tags
        for (self.tags.items) |tag| {
            self.allocator.free(tag.key);
            self.allocator.free(tag.value);
        }
        self.tags.deinit(self.allocator);
    }

    /// Add a new tag with key and value (duped), active=true by default
    pub fn addTag(self: *FilterBar, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);

        const tag = FilterTag{
            .key = key_copy,
            .value = value_copy,
            .active = true,
        };

        try self.tags.append(self.allocator, tag);
    }

    /// Remove tag at index (no-op if OOB)
    pub fn removeTag(self: *FilterBar, index: usize) void {
        if (index >= self.tags.items.len) return;

        const tag = self.tags.items[index];
        self.allocator.free(tag.key);
        self.allocator.free(tag.value);

        _ = self.tags.orderedRemove(index);
    }

    /// Toggle active state of tag at index (no-op if OOB)
    pub fn toggleTag(self: *FilterBar, index: usize) void {
        if (index >= self.tags.items.len) return;
        self.tags.items[index].active = !self.tags.items[index].active;
    }

    /// Clear all tags (free all strings, retain capacity)
    pub fn clearAll(self: *FilterBar) void {
        for (self.tags.items) |tag| {
            self.allocator.free(tag.key);
            self.allocator.free(tag.value);
        }
        self.tags.clearRetainingCapacity();
    }

    /// Count active tags
    pub fn activeCount(self: *FilterBar) usize {
        var count: usize = 0;
        for (self.tags.items) |tag| {
            if (tag.active) count += 1;
        }
        return count;
    }

    /// Total tag count
    pub fn tagCount(self: *FilterBar) usize {
        return self.tags.items.len;
    }

    /// Builder: set block
    pub fn withBlock(self: *FilterBar, block: Block) *FilterBar {
        self.block = block;
        return self;
    }

    /// Builder: set tag_style
    pub fn withTagStyle(self: *FilterBar, style: Style) *FilterBar {
        self.tag_style = style;
        return self;
    }

    /// Builder: set active_style
    pub fn withActiveStyle(self: *FilterBar, style: Style) *FilterBar {
        self.active_style = style;
        return self;
    }

    /// Builder: set inactive_style
    pub fn withInactiveStyle(self: *FilterBar, style: Style) *FilterBar {
        self.inactive_style = style;
        return self;
    }

    /// Builder: set placeholder
    pub fn withPlaceholder(self: *FilterBar, text: []const u8) *FilterBar {
        self.placeholder = text;
        return self;
    }

    /// Render FilterBar to buffer
    pub fn render(self: *FilterBar, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner = block.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        // If no tags, show placeholder
        if (self.tags.items.len == 0) {
            buf.setString(inner.x, inner.y, self.placeholder, self.tag_style);
            return;
        }

        // Render tags horizontally as pills: [key:value] [key:value] ...
        var x: u16 = inner.x;
        const max_x: u16 = inner.x + inner.width;

        for (self.tags.items) |tag| {
            // Determine style based on active state
            const pill_style = if (tag.active) self.active_style else self.inactive_style;

            // Build pill string: "[key:value]"
            var pill_buf: [512]u8 = undefined;
            const pill_len = std.fmt.bufPrint(pill_buf[0..], "[{s}:{s}]", .{ tag.key, tag.value }) catch {
                // If formatting fails, skip this tag
                continue;
            };

            // Check if pill would fit
            const pill_width = @as(u16, @intCast(pill_len.len));
            if (x + pill_width > max_x) break;

            // Render pill
            buf.setString(x, inner.y, pill_len, pill_style);
            x += pill_width;

            // Add space between pills if not at end
            if (x < max_x) {
                x += 1;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "FilterBar init creates empty FilterBar" {
    const allocator = testing.allocator;
    var fb = FilterBar.init(allocator);
    defer fb.deinit();

    try testing.expectEqual(0, fb.tagCount());
    try testing.expectEqual(0, fb.activeCount());
}
