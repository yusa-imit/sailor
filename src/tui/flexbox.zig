//! FlexBox layout system — CSS flexbox-inspired layout engine
//!
//! Provides a flexible layout system with justify-content and align-items support.
//! Based on CSS flexbox principles adapted for terminal UI.
//!
//! Example usage:
//!
//! ```zig
//! const flex = FlexBox.init(.horizontal)
//!     .withJustifyContent(.space_between)
//!     .withAlignItems(.center)
//!     .withGap(2);
//!
//! const rects = try flex.layout(allocator, area, &items);
//! defer allocator.free(rects);
//! ```

const std = @import("std");
const Rect = @import("layout.zig").Rect;

/// FlexBox layout engine
pub const FlexBox = struct {
    /// Layout direction
    direction: Direction = .horizontal,
    /// Justify content along main axis
    justify_content: JustifyContent = .flex_start,
    /// Align items along cross axis
    align_items: AlignItems = .stretch,
    /// Gap between items (in cells)
    gap: u16 = 0,
    /// Wrap behavior
    wrap: Wrap = .no_wrap,

    pub const Direction = enum {
        horizontal, // left to right
        vertical, // top to bottom
    };

    pub const JustifyContent = enum {
        flex_start, // pack to start
        flex_end, // pack to end
        center, // center items
        space_between, // even spacing with items at edges
        space_around, // even spacing with half-space at edges
        space_evenly, // even spacing including edges
    };

    pub const AlignItems = enum {
        flex_start, // align to start of cross axis
        flex_end, // align to end of cross axis
        center, // center on cross axis
        stretch, // stretch to fill cross axis
    };

    pub const Wrap = enum {
        no_wrap, // single line
        wrap, // multiple lines if needed
    };

    pub const Item = struct {
        /// Flex grow factor (0 = fixed, >0 = proportional growth)
        flex_grow: u32 = 0,
        /// Flex shrink factor (0 = no shrink, >0 = proportional shrink)
        flex_shrink: u32 = 1,
        /// Base size before flex (0 = auto from content)
        flex_basis: u16 = 0,
        /// Minimum size constraint
        min_size: u16 = 0,
        /// Maximum size constraint (0 = no max)
        max_size: u16 = 0,
    };

    /// Create a new FlexBox with default settings
    pub fn init(direction: Direction) FlexBox {
        return .{ .direction = direction };
    }

    /// Set justify-content property
    pub fn withJustifyContent(self: FlexBox, justify: JustifyContent) FlexBox {
        var result = self;
        result.justify_content = justify;
        return result;
    }

    /// Set align-items property
    pub fn withAlignItems(self: FlexBox, align_mode: AlignItems) FlexBox {
        var result = self;
        result.align_items = align_mode;
        return result;
    }

    /// Set gap between items
    pub fn withGap(self: FlexBox, gap_size: u16) FlexBox {
        var result = self;
        result.gap = gap_size;
        return result;
    }

    /// Set wrap behavior
    pub fn withWrap(self: FlexBox, wrap_mode: Wrap) FlexBox {
        var result = self;
        result.wrap = wrap_mode;
        return result;
    }

    /// Calculate layout for items
    /// Caller owns returned memory
    pub fn layout(
        self: FlexBox,
        allocator: std.mem.Allocator,
        container: Rect,
        items: []const Item,
    ) ![]Rect {
        if (items.len == 0) return &.{};

        const rects = try allocator.alloc(Rect, items.len);
        errdefer allocator.free(rects);

        // Calculate available space
        const main_size = self.getMainSize(container);
        const cross_size = self.getCrossSize(container);

        // Calculate total gap space
        const total_gap = if (items.len > 1) self.gap * @as(u16, @intCast(items.len - 1)) else 0;
        const available_main = if (main_size > total_gap) main_size - total_gap else 0;

        // Calculate base sizes and totals
        var total_flex_grow: u32 = 0;
        var total_flex_shrink: u32 = 0;
        var total_basis: u16 = 0;

        for (items) |item| {
            total_flex_grow += item.flex_grow;
            total_flex_shrink += item.flex_shrink;
            total_basis += item.flex_basis;
        }

        // Determine if we need to grow or shrink
        const need_grow = total_basis < available_main;
        const need_shrink = total_basis > available_main;

        // Calculate final sizes
        var sizes = try allocator.alloc(u16, items.len);
        defer allocator.free(sizes);

        for (items, 0..) |item, i| {
            if (need_grow and total_flex_grow > 0) {
                // Distribute extra space
                const extra_space = available_main - total_basis;
                const grow_ratio = @as(f64, @floatFromInt(item.flex_grow)) / @as(f64, @floatFromInt(total_flex_grow));
                const additional = @as(u16, @intFromFloat(grow_ratio * @as(f64, @floatFromInt(extra_space))));
                sizes[i] = item.flex_basis + additional;
            } else if (need_shrink and total_flex_shrink > 0) {
                // Reduce to fit
                const deficit = total_basis - available_main;
                const shrink_ratio = @as(f64, @floatFromInt(item.flex_shrink)) / @as(f64, @floatFromInt(total_flex_shrink));
                const reduction = @as(u16, @intFromFloat(shrink_ratio * @as(f64, @floatFromInt(deficit))));
                sizes[i] = if (item.flex_basis > reduction) item.flex_basis - reduction else 0;
            } else {
                sizes[i] = item.flex_basis;
            }

            // Apply min/max constraints
            if (item.min_size > 0 and sizes[i] < item.min_size) {
                sizes[i] = item.min_size;
            }
            if (item.max_size > 0 and sizes[i] > item.max_size) {
                sizes[i] = item.max_size;
            }
        }

        // Calculate positions along main axis
        var positions = try allocator.alloc(u16, items.len);
        defer allocator.free(positions);

        switch (self.justify_content) {
            .flex_start => {
                var pos: u16 = 0;
                for (items, 0..) |_, i| {
                    positions[i] = pos;
                    pos += sizes[i] + self.gap;
                }
            },
            .flex_end => {
                const total_used = blk: {
                    var sum: u16 = 0;
                    for (sizes) |size| sum += size;
                    break :blk sum + total_gap;
                };
                var pos: u16 = if (main_size > total_used) main_size - total_used else 0;
                for (items, 0..) |_, i| {
                    positions[i] = pos;
                    pos += sizes[i] + self.gap;
                }
            },
            .center => {
                const total_used = blk: {
                    var sum: u16 = 0;
                    for (sizes) |size| sum += size;
                    break :blk sum + total_gap;
                };
                var pos: u16 = if (main_size > total_used) @divTrunc(main_size - total_used, 2) else 0;
                for (items, 0..) |_, i| {
                    positions[i] = pos;
                    pos += sizes[i] + self.gap;
                }
            },
            .space_between => {
                if (items.len == 1) {
                    positions[0] = 0;
                } else {
                    const total_size = blk: {
                        var sum: u16 = 0;
                        for (sizes) |size| sum += size;
                        break :blk sum;
                    };
                    const remaining = if (main_size > total_size) main_size - total_size else 0;
                    const gap_size = @divTrunc(remaining, @as(u16, @intCast(items.len - 1)));
                    var pos: u16 = 0;
                    for (items, 0..) |_, i| {
                        positions[i] = pos;
                        pos += sizes[i] + gap_size;
                    }
                }
            },
            .space_around => {
                const total_size = blk: {
                    var sum: u16 = 0;
                    for (sizes) |size| sum += size;
                    break :blk sum;
                };
                const remaining = if (main_size > total_size) main_size - total_size else 0;
                const gap_size = @divTrunc(remaining, @as(u16, @intCast(items.len * 2)));
                var pos: u16 = gap_size;
                for (items, 0..) |_, i| {
                    positions[i] = pos;
                    pos += sizes[i] + gap_size * 2;
                }
            },
            .space_evenly => {
                const total_size = blk: {
                    var sum: u16 = 0;
                    for (sizes) |size| sum += size;
                    break :blk sum;
                };
                const remaining = if (main_size > total_size) main_size - total_size else 0;
                const gap_size = @divTrunc(remaining, @as(u16, @intCast(items.len + 1)));
                var pos: u16 = gap_size;
                for (items, 0..) |_, i| {
                    positions[i] = pos;
                    pos += sizes[i] + gap_size;
                }
            },
        }

        // Build final rectangles
        for (items, 0..) |_, i| {
            const main_pos = positions[i];
            const main_size_final = sizes[i];

            // Calculate cross axis position and size
            const cross_pos: u16 = switch (self.align_items) {
                .flex_start => 0,
                .flex_end => if (cross_size > main_size_final) cross_size - main_size_final else 0,
                .center => if (cross_size > main_size_final) @divTrunc(cross_size - main_size_final, 2) else 0,
                .stretch => 0,
            };

            const cross_size_final: u16 = switch (self.align_items) {
                .stretch => cross_size,
                else => main_size_final,
            };

            // Convert to Rect based on direction
            rects[i] = switch (self.direction) {
                .horizontal => Rect{
                    .x = container.x + main_pos,
                    .y = container.y + cross_pos,
                    .width = main_size_final,
                    .height = cross_size_final,
                },
                .vertical => Rect{
                    .x = container.x + cross_pos,
                    .y = container.y + main_pos,
                    .width = cross_size_final,
                    .height = main_size_final,
                },
            };
        }

        return rects;
    }

    fn getMainSize(self: FlexBox, rect: Rect) u16 {
        return switch (self.direction) {
            .horizontal => rect.width,
            .vertical => rect.height,
        };
    }

    fn getCrossSize(self: FlexBox, rect: Rect) u16 {
        return switch (self.direction) {
            .horizontal => rect.height,
            .vertical => rect.width,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FlexBox.init" {
    const flex = FlexBox.init(.horizontal);
    try std.testing.expectEqual(FlexBox.Direction.horizontal, flex.direction);
    try std.testing.expectEqual(FlexBox.JustifyContent.flex_start, flex.justify_content);
    try std.testing.expectEqual(FlexBox.AlignItems.stretch, flex.align_items);
    try std.testing.expectEqual(@as(u16, 0), flex.gap);
}

test "FlexBox.withJustifyContent" {
    const flex = FlexBox.init(.horizontal).withJustifyContent(.center);
    try std.testing.expectEqual(FlexBox.JustifyContent.center, flex.justify_content);
}

test "FlexBox.withAlignItems" {
    const flex = FlexBox.init(.horizontal).withAlignItems(.center);
    try std.testing.expectEqual(FlexBox.AlignItems.center, flex.align_items);
}

test "FlexBox.withGap" {
    const flex = FlexBox.init(.horizontal).withGap(4);
    try std.testing.expectEqual(@as(u16, 4), flex.gap);
}

test "FlexBox.layout empty items" {
    const flex = FlexBox.init(.horizontal);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items: []const FlexBox.Item = &.{};

    const rects = try flex.layout(std.testing.allocator, container, items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 0), rects.len);
}

test "FlexBox.layout single item flex_start" {
    const flex = FlexBox.init(.horizontal).withJustifyContent(.flex_start);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 30 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 1), rects.len);
    try std.testing.expectEqual(@as(i32, 0), rects[0].x);
    try std.testing.expectEqual(@as(u16, 30), rects[0].width);
}

test "FlexBox.layout flex_end" {
    const flex = FlexBox.init(.horizontal).withJustifyContent(.flex_end);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 30 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 1), rects.len);
    try std.testing.expectEqual(@as(i32, 70), rects[0].x);
}

test "FlexBox.layout center" {
    const flex = FlexBox.init(.horizontal).withJustifyContent(.center);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 30 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 1), rects.len);
    try std.testing.expectEqual(@as(i32, 35), rects[0].x);
}

test "FlexBox.layout space_between" {
    const flex = FlexBox.init(.horizontal).withJustifyContent(.space_between);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 20 },
        .{ .flex_basis = 20 },
        .{ .flex_basis = 20 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 3), rects.len);
    try std.testing.expectEqual(@as(i32, 0), rects[0].x);
    // Middle item should be centered
    try std.testing.expect(rects[1].x > 20);
    try std.testing.expect(rects[1].x < 60);
    // Last item should be at end
    try std.testing.expectEqual(@as(i32, 80), rects[2].x);
}

test "FlexBox.layout with gap" {
    const flex = FlexBox.init(.horizontal).withGap(5);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 20 },
        .{ .flex_basis = 20 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 2), rects.len);
    try std.testing.expectEqual(@as(i32, 0), rects[0].x);
    try std.testing.expectEqual(@as(i32, 25), rects[1].x); // 20 + 5 gap
}

test "FlexBox.layout flex_grow" {
    const flex = FlexBox.init(.horizontal);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 20, .flex_grow = 1 },
        .{ .flex_basis = 20, .flex_grow = 2 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 2), rects.len);
    // First item gets 1/3 of extra space (60 / 3 = 20)
    try std.testing.expectEqual(@as(u16, 40), rects[0].width);
    // Second item gets 2/3 of extra space (60 * 2 / 3 = 40)
    try std.testing.expectEqual(@as(u16, 60), rects[1].width);
}

test "FlexBox.layout flex_shrink" {
    const flex = FlexBox.init(.horizontal);
    const container = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 40, .flex_shrink = 1 },
        .{ .flex_basis = 40, .flex_shrink = 2 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 2), rects.len);
    // Total basis = 80, available = 50, deficit = 30
    // First item shrinks 1/3 * 30 = 10
    try std.testing.expectEqual(@as(u16, 30), rects[0].width);
    // Second item shrinks 2/3 * 30 = 20
    try std.testing.expectEqual(@as(u16, 20), rects[1].width);
}

test "FlexBox.layout min/max constraints" {
    const flex = FlexBox.init(.horizontal);
    const container = Rect{ .x = 0, .y = 0, .width = 200, .height = 20 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 20, .flex_grow = 1, .min_size = 50, .max_size = 80 },
        .{ .flex_basis = 20, .flex_grow = 1 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 2), rects.len);
    // First item should be clamped by max
    try std.testing.expectEqual(@as(u16, 80), rects[0].width);
}

test "FlexBox.layout vertical direction" {
    const flex = FlexBox.init(.vertical);
    const container = Rect{ .x = 0, .y = 0, .width = 20, .height = 100 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 30 },
        .{ .flex_basis = 30 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 2), rects.len);
    try std.testing.expectEqual(@as(i32, 0), rects[0].y);
    try std.testing.expectEqual(@as(u16, 30), rects[0].height);
    try std.testing.expectEqual(@as(i32, 30), rects[1].y);
}

test "FlexBox.layout align_items center" {
    const flex = FlexBox.init(.horizontal).withAlignItems(.center);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 20 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 1), rects.len);
    // Should be centered on cross axis (height 40, item height 20)
    try std.testing.expectEqual(@as(i32, 10), rects[0].y);
}

test "FlexBox.layout align_items stretch" {
    const flex = FlexBox.init(.horizontal).withAlignItems(.stretch);
    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 20 },
    };

    const rects = try flex.layout(std.testing.allocator, container, &items);
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 1), rects.len);
    // Should stretch to fill cross axis
    try std.testing.expectEqual(@as(u16, 40), rects[0].height);
}
