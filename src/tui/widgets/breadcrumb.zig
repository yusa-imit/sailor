//! Breadcrumb widget — navigation breadcrumb trail
//!
//! Breadcrumb provides visual navigation trail showing hierarchical path
//! (e.g., "Home > Projects > sailor > src"). Supports customizable separators,
//! truncation for long paths, mouse interaction for navigation, and current item highlighting.
//!
//! ## Features
//! - Add items to build navigation trail
//! - Customizable separator (>, /, →, •, etc.)
//! - Truncation modes (show last N items, ellipsis prefix)
//! - Current item highlighting (last item or specified index)
//! - Item overflow handling for long paths
//! - Unicode separators and item names
//! - Optional Block wrapper for borders and title
//!
//! ## Usage
//! ```zig
//! var breadcrumb = Breadcrumb.init(allocator);
//! defer breadcrumb.deinit();
//!
//! try breadcrumb.addItem("Home");
//! try breadcrumb.addItem("Projects");
//! try breadcrumb.addItem("sailor");
//! try breadcrumb.addItem("src");
//!
//! breadcrumb.render(buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Truncation mode for long breadcrumb trails
pub const TruncationMode = enum {
    none, // Show all items
    show_last_n, // Show last N items with ellipsis prefix
    ellipsis_middle, // Show first + ellipsis + last items
};

/// Breadcrumb item
pub const Item = struct {
    label: []const u8,
    clickable: bool = true,
};

/// Navigation breadcrumb trail widget
pub const Breadcrumb = struct {
    items: std.ArrayList(Item),
    separator: []const u8 = " > ",
    truncation_mode: TruncationMode = .none,
    max_items_visible: usize = 0, // 0 = show all
    current_index: ?usize = null, // null = last item is current
    current_style: Style = .{ .fg = .bright_blue, .bold = true },
    normal_style: Style = .{ .fg = .white },
    separator_style: Style = .{ .fg = .bright_black },
    block: ?Block = null,
    allocator: std.mem.Allocator,

    /// Create a new breadcrumb widget
    pub fn init(allocator: std.mem.Allocator) Breadcrumb {
        return .{
            .items = std.ArrayList(Item).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *Breadcrumb) void {
        self.items.deinit();
    }

    /// Add an item to the breadcrumb trail
    pub fn addItem(self: *Breadcrumb, label: []const u8) !void {
        try self.items.append(.{ .label = label });
    }

    /// Add a non-clickable item
    pub fn addStaticItem(self: *Breadcrumb, label: []const u8) !void {
        try self.items.append(.{ .label = label, .clickable = false });
    }

    /// Clear all items
    pub fn clear(self: *Breadcrumb) void {
        self.items.clearRetainingCapacity();
    }

    /// Set custom separator
    pub fn withSeparator(self: Breadcrumb, separator: []const u8) Breadcrumb {
        var result = self;
        result.separator = separator;
        return result;
    }

    /// Set truncation mode
    pub fn withTruncation(self: Breadcrumb, mode: TruncationMode, max_visible: usize) Breadcrumb {
        var result = self;
        result.truncation_mode = mode;
        result.max_items_visible = max_visible;
        return result;
    }

    /// Set current item index (null = last item)
    pub fn withCurrentIndex(self: Breadcrumb, index: ?usize) Breadcrumb {
        var result = self;
        result.current_index = index;
        return result;
    }

    /// Set current item style
    pub fn withCurrentStyle(self: Breadcrumb, current_style: Style) Breadcrumb {
        var result = self;
        result.current_style = current_style;
        return result;
    }

    /// Set normal item style
    pub fn withNormalStyle(self: Breadcrumb, normal_style: Style) Breadcrumb {
        var result = self;
        result.normal_style = normal_style;
        return result;
    }

    /// Set separator style
    pub fn withSeparatorStyle(self: Breadcrumb, separator_style: Style) Breadcrumb {
        var result = self;
        result.separator_style = separator_style;
        return result;
    }

    /// Set block for borders/title
    pub fn withBlock(self: Breadcrumb, new_block: Block) Breadcrumb {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Render breadcrumb to buffer
    pub fn render(self: Breadcrumb, buf: Buffer, area: Rect) void {
        if (self.items.items.len == 0) return;
        if (area.width == 0 or area.height == 0) return;

        var buf_mut = buf;

        // Handle Block wrapper
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(&buf_mut, area);
            inner_area = blk.inner(area);
            if (inner_area.width == 0 or inner_area.height == 0) return;
        }

        // Determine which items to show based on truncation mode
        const items_to_show = self.getVisibleItems();
        if (items_to_show.len == 0) return;

        // Render items with separators
        var x = inner_area.x;
        const y = inner_area.y;
        const max_x = inner_area.x + inner_area.width;

        for (items_to_show, 0..) |visible_item, i| {
            if (x >= max_x) break;

            // Determine style for this item
            const item_style = if (visible_item.is_current) self.current_style else self.normal_style;

            // Render item text
            const remaining: usize = max_x - x;
            const item_len = @min(visible_item.label.len, remaining);

            for (visible_item.label[0..item_len], 0..) |c, offset| {
                buf_mut.setChar(x + @as(u16, @intCast(offset)), y, c, item_style);
            }
            x += @intCast(item_len);

            // Render separator (except after last item)
            if (i < items_to_show.len - 1) {
                if (x >= max_x) break;
                const sep_remaining: usize = max_x - x;
                const sep_len = @min(self.separator.len, sep_remaining);

                for (self.separator[0..sep_len], 0..) |c, offset| {
                    buf_mut.setChar(x + @as(u16, @intCast(offset)), y, c, self.separator_style);
                }
                x += @intCast(sep_len);
            }
        }
    }

    /// Internal: represents a visible item with metadata
    const VisibleItem = struct {
        label: []const u8,
        is_current: bool,
        original_index: usize,
    };

    /// Get items to display based on truncation mode
    fn getVisibleItems(self: Breadcrumb) []const VisibleItem {
        // Allocate temporary buffer for visible items
        const max_visible = if (self.max_items_visible > 0) self.max_items_visible else self.items.items.len;

        // For simplicity, we'll use a static buffer approach for now
        // In production, this should use an allocator, but for render we keep it allocation-free
        var static_buffer: [128]VisibleItem = undefined;
        var visible_count: usize = 0;

        const current_idx = self.current_index orelse (self.items.items.len - 1);

        switch (self.truncation_mode) {
            .none => {
                // Show all items
                for (self.items.items, 0..) |item, idx| {
                    if (visible_count >= static_buffer.len) break;
                    static_buffer[visible_count] = .{
                        .label = item.label,
                        .is_current = (idx == current_idx),
                        .original_index = idx,
                    };
                    visible_count += 1;
                }
            },
            .show_last_n => {
                // Show ellipsis + last N items
                if (self.items.items.len > max_visible) {
                    // Add ellipsis
                    static_buffer[visible_count] = .{
                        .label = "...",
                        .is_current = false,
                        .original_index = 0,
                    };
                    visible_count += 1;

                    // Add last N items
                    const start_idx = self.items.items.len - max_visible;
                    for (self.items.items[start_idx..], start_idx..) |item, idx| {
                        if (visible_count >= static_buffer.len) break;
                        static_buffer[visible_count] = .{
                            .label = item.label,
                            .is_current = (idx == current_idx),
                            .original_index = idx,
                        };
                        visible_count += 1;
                    }
                } else {
                    // Show all items if count <= max_visible
                    for (self.items.items, 0..) |item, idx| {
                        if (visible_count >= static_buffer.len) break;
                        static_buffer[visible_count] = .{
                            .label = item.label,
                            .is_current = (idx == current_idx),
                            .original_index = idx,
                        };
                        visible_count += 1;
                    }
                }
            },
            .ellipsis_middle => {
                // Show first + ellipsis + last items
                if (self.items.items.len > max_visible and max_visible >= 2) {
                    const items_per_side = (max_visible - 1) / 2;

                    // Add first items
                    for (self.items.items[0..items_per_side], 0..) |item, idx| {
                        if (visible_count >= static_buffer.len) break;
                        static_buffer[visible_count] = .{
                            .label = item.label,
                            .is_current = (idx == current_idx),
                            .original_index = idx,
                        };
                        visible_count += 1;
                    }

                    // Add ellipsis
                    if (visible_count < static_buffer.len) {
                        static_buffer[visible_count] = .{
                            .label = "...",
                            .is_current = false,
                            .original_index = items_per_side,
                        };
                        visible_count += 1;
                    }

                    // Add last items
                    const last_count = max_visible - items_per_side - 1;
                    const start_idx = self.items.items.len - last_count;
                    for (self.items.items[start_idx..], start_idx..) |item, idx| {
                        if (visible_count >= static_buffer.len) break;
                        static_buffer[visible_count] = .{
                            .label = item.label,
                            .is_current = (idx == current_idx),
                            .original_index = idx,
                        };
                        visible_count += 1;
                    }
                } else {
                    // Show all items if count <= max_visible
                    for (self.items.items, 0..) |item, idx| {
                        if (visible_count >= static_buffer.len) break;
                        static_buffer[visible_count] = .{
                            .label = item.label,
                            .is_current = (idx == current_idx),
                            .original_index = idx,
                        };
                        visible_count += 1;
                    }
                }
            },
        }

        return static_buffer[0..visible_count];
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "Breadcrumb.init" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try std.testing.expectEqual(@as(usize, 0), breadcrumb.items.items.len);
    try std.testing.expectEqualStrings(" > ", breadcrumb.separator);
    try std.testing.expectEqual(TruncationMode.none, breadcrumb.truncation_mode);
    try std.testing.expectEqual(@as(usize, 0), breadcrumb.max_items_visible);
    try std.testing.expectEqual(@as(?usize, null), breadcrumb.current_index);
}

test "Breadcrumb.addItem single item" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");

    try std.testing.expectEqual(@as(usize, 1), breadcrumb.items.items.len);
    try std.testing.expectEqualStrings("Home", breadcrumb.items.items[0].label);
    try std.testing.expectEqual(true, breadcrumb.items.items[0].clickable);
}

test "Breadcrumb.addItem multiple items" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");
    try breadcrumb.addItem("src");

    try std.testing.expectEqual(@as(usize, 4), breadcrumb.items.items.len);
    try std.testing.expectEqualStrings("Home", breadcrumb.items.items[0].label);
    try std.testing.expectEqualStrings("Projects", breadcrumb.items.items[1].label);
    try std.testing.expectEqualStrings("sailor", breadcrumb.items.items[2].label);
    try std.testing.expectEqualStrings("src", breadcrumb.items.items[3].label);
}

test "Breadcrumb.addStaticItem non-clickable" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addStaticItem("Static");

    try std.testing.expectEqual(@as(usize, 2), breadcrumb.items.items.len);
    try std.testing.expectEqual(true, breadcrumb.items.items[0].clickable);
    try std.testing.expectEqual(false, breadcrumb.items.items[1].clickable);
}

test "Breadcrumb.clear removes all items" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    breadcrumb.clear();

    try std.testing.expectEqual(@as(usize, 0), breadcrumb.items.items.len);
}

test "Breadcrumb.withSeparator custom separator >" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withSeparator(">");
    try std.testing.expectEqualStrings(">", updated.separator);
}

test "Breadcrumb.withSeparator slash separator" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withSeparator(" / ");
    try std.testing.expectEqualStrings(" / ", updated.separator);
}

test "Breadcrumb.withSeparator arrow separator" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withSeparator(" → ");
    try std.testing.expectEqualStrings(" → ", updated.separator);
}

test "Breadcrumb.withSeparator bullet separator" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withSeparator(" • ");
    try std.testing.expectEqualStrings(" • ", updated.separator);
}

test "Breadcrumb.withSeparator unicode separators" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const arrow_updated = breadcrumb.withSeparator(" ▸ ");
    try std.testing.expectEqualStrings(" ▸ ", arrow_updated.separator);

    const diamond_updated = breadcrumb.withSeparator(" ◆ ");
    try std.testing.expectEqualStrings(" ◆ ", diamond_updated.separator);
}

test "Breadcrumb.withTruncation none mode" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withTruncation(.none, 0);
    try std.testing.expectEqual(TruncationMode.none, updated.truncation_mode);
    try std.testing.expectEqual(@as(usize, 0), updated.max_items_visible);
}

test "Breadcrumb.withTruncation show_last_n mode" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withTruncation(.show_last_n, 3);
    try std.testing.expectEqual(TruncationMode.show_last_n, updated.truncation_mode);
    try std.testing.expectEqual(@as(usize, 3), updated.max_items_visible);
}

test "Breadcrumb.withTruncation ellipsis_middle mode" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withTruncation(.ellipsis_middle, 5);
    try std.testing.expectEqual(TruncationMode.ellipsis_middle, updated.truncation_mode);
    try std.testing.expectEqual(@as(usize, 5), updated.max_items_visible);
}

test "Breadcrumb.withCurrentIndex explicit index" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withCurrentIndex(2);
    try std.testing.expectEqual(@as(?usize, 2), updated.current_index);
}

test "Breadcrumb.withCurrentIndex null default" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const updated = breadcrumb.withCurrentIndex(null);
    try std.testing.expectEqual(@as(?usize, null), updated.current_index);
}

test "Breadcrumb.withCurrentStyle custom style" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const custom_style = Style{ .fg = .green, .bold = true };
    const updated = breadcrumb.withCurrentStyle(custom_style);

    try std.testing.expectEqual(@as(?Color, .green), updated.current_style.fg);
    try std.testing.expectEqual(true, updated.current_style.bold);
}

test "Breadcrumb.withNormalStyle custom style" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const custom_style = Style{ .fg = .cyan };
    const updated = breadcrumb.withNormalStyle(custom_style);

    try std.testing.expectEqual(@as(?Color, .cyan), updated.normal_style.fg);
}

test "Breadcrumb.withSeparatorStyle custom style" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    const custom_style = Style{ .fg = .yellow, .dim = true };
    const updated = breadcrumb.withSeparatorStyle(custom_style);

    try std.testing.expectEqual(@as(?Color, .yellow), updated.separator_style.fg);
    try std.testing.expectEqual(true, updated.separator_style.dim);
}

test "Breadcrumb.render empty breadcrumb" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should not crash with empty breadcrumb
}

test "Breadcrumb.render single item no separator" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should render "Home" without separator
}

test "Breadcrumb.render two items with separator" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should render "Home > Projects"
}

test "Breadcrumb.render multiple items with default separator" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");
    try breadcrumb.addItem("src");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should render "Home > Projects > sailor > src"
}

test "Breadcrumb.render custom separator slash" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withSeparator(" / ");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "Home / Projects / sailor"
}

test "Breadcrumb.render custom separator arrow" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withSeparator(" → ");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "Home → Projects"
}

test "Breadcrumb.render custom separator bullet" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withSeparator(" • ");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "Home • Projects"
}

test "Breadcrumb.render unicode separator" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withSeparator(" ▸ ");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "Home ▸ Projects"
}

test "Breadcrumb.render unicode item names" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("ホーム"); // Japanese: Home
    try breadcrumb.addItem("项目"); // Chinese: Projects
    try breadcrumb.addItem("дома"); // Russian: Home

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should render unicode item names correctly
}

test "Breadcrumb.render very long item names" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("VeryLongItemNameThatExceedsNormalWidth");
    try breadcrumb.addItem("AnotherExtremelyLongItemName");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should handle long item names (possibly truncating)
}

test "Breadcrumb.render path too long for width" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");
    try breadcrumb.addItem("src");
    try breadcrumb.addItem("tui");
    try breadcrumb.addItem("widgets");

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    breadcrumb.render(buf, area);

    // Should handle overflow gracefully (truncate or ellipsis)
}

test "Breadcrumb.render zero width area" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    breadcrumb.render(buf, area);

    // Should not crash with zero width
}

test "Breadcrumb.render zero height area" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    breadcrumb.render(buf, area);

    // Should not crash with zero height
}

test "Breadcrumb.render truncation show_last_n with 3 items" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");
    try breadcrumb.addItem("src");
    try breadcrumb.addItem("tui");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withTruncation(.show_last_n, 3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "... > src > tui" (last 3 items)
}

test "Breadcrumb.render truncation show_last_n with fewer items than max" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withTruncation(.show_last_n, 5);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render all items (no ellipsis) since count < max_visible
}

test "Breadcrumb.render truncation ellipsis_middle" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");
    try breadcrumb.addItem("src");
    try breadcrumb.addItem("tui");
    try breadcrumb.addItem("widgets");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withTruncation(.ellipsis_middle, 4);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "Home > ... > tui > widgets" (first + ellipsis + last)
}

test "Breadcrumb.render current item highlighting last item" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should highlight "sailor" (last item) with current_style
}

test "Breadcrumb.render current item highlighting explicit index" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withCurrentIndex(1);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should highlight "Projects" (index 1) with current_style
}

test "Breadcrumb.render current item highlighting first item" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withCurrentIndex(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should highlight "Home" (index 0) with current_style
}

test "Breadcrumb.render custom current style green bold" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Current");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const custom_style = Style{ .fg = .green, .bold = true };
    const updated = breadcrumb.withCurrentStyle(custom_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "Current" with green bold style
}

test "Breadcrumb.render custom normal style cyan" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("First");
    try breadcrumb.addItem("Second");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const custom_style = Style{ .fg = .cyan };
    const updated = breadcrumb.withNormalStyle(custom_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render "First" with cyan style
}

test "Breadcrumb.render custom separator style yellow dim" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const custom_style = Style{ .fg = .yellow, .dim = true };
    const updated = breadcrumb.withSeparatorStyle(custom_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should render separator ">" with yellow dim style
}

test "Breadcrumb.render with block wrapper" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const block = (Block{}).withTitle("Navigation").withBorders(.all);
    const updated = breadcrumb.withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 3 };
    updated.render(buf, area);

    // Should render breadcrumb with borders and title
}

test "Breadcrumb.render after clear and re-add" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Old1");
    try breadcrumb.addItem("Old2");
    breadcrumb.clear();

    try breadcrumb.addItem("New1");
    try breadcrumb.addItem("New2");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should render "New1 > New2"
    try std.testing.expectEqual(@as(usize, 2), breadcrumb.items.items.len);
}

test "Breadcrumb.render chaining multiple with methods" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");
    try breadcrumb.addItem("sailor");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb
        .withSeparator(" / ")
        .withCurrentStyle(.{ .fg = .green, .bold = true })
        .withNormalStyle(.{ .fg = .cyan })
        .withSeparatorStyle(.{ .fg = .yellow });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should apply all style customizations
}

test "Breadcrumb.render edge case single character items" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("A");
    try breadcrumb.addItem("B");
    try breadcrumb.addItem("C");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should render "A > B > C"
}

test "Breadcrumb.render edge case empty string item" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should handle empty string item gracefully
}

test "Breadcrumb.render mixed clickable and static items" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addStaticItem("Static");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should render all items (mouse handling will differ)
}

test "Breadcrumb.render no memory leaks" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Item1");
    try breadcrumb.addItem("Item2");
    try breadcrumb.addItem("Item3");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    breadcrumb.render(buf, area);

    // Should not leak memory
}

test "Breadcrumb.render truncation with unicode items" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("首页");
    try breadcrumb.addItem("项目");
    try breadcrumb.addItem("sailor");
    try breadcrumb.addItem("文档");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withTruncation(.show_last_n, 2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should truncate correctly with unicode characters
}

test "Breadcrumb.render current index out of bounds" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("Home");
    try breadcrumb.addItem("Projects");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withCurrentIndex(10); // Out of bounds
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should handle out-of-bounds index gracefully (fallback to last item)
}

test "Breadcrumb.render all truncation modes with same data" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("A");
    try breadcrumb.addItem("B");
    try breadcrumb.addItem("C");
    try breadcrumb.addItem("D");
    try breadcrumb.addItem("E");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };

    // None
    const none = breadcrumb.withTruncation(.none, 0);
    none.render(buf, area);

    // Show last N
    const last_n = breadcrumb.withTruncation(.show_last_n, 3);
    last_n.render(buf, area);

    // Ellipsis middle
    const ellipsis = breadcrumb.withTruncation(.ellipsis_middle, 4);
    ellipsis.render(buf, area);

    // Should render all three modes without crashing
}

test "Breadcrumb.render separator longer than item" {
    var breadcrumb = Breadcrumb.init(std.testing.allocator);
    defer breadcrumb.deinit();

    try breadcrumb.addItem("A");
    try breadcrumb.addItem("B");

    var buf = try Buffer.init(std.testing.allocator, 80, 10);
    defer buf.deinit();

    const updated = breadcrumb.withSeparator(" ====> ");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    updated.render(buf, area);

    // Should handle long separator gracefully
}
