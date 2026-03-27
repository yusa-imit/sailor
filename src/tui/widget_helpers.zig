//! Widget composition helpers — generic decorators, wrappers, and containers.
//!
//! This module provides composable widget utilities that work with ANY widget type
//! implementing the widget protocol (render method, optional measure method).
//!
//! Helpers:
//! - Padding(T): adds padding around a widget
//! - Centered(T): centers a widget in available area
//! - Aligned(T): aligns widget with horizontal/vertical control
//! - Stack: stacks multiple widgets vertically or horizontally
//! - Constrained(T): enforces min/max size constraints

const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Rect = @import("layout.zig").Rect;
const widget_trait = @import("widget_trait.zig");
const Size = widget_trait.Size;
const WidgetList = widget_trait.WidgetList;

// ============================================================================
// Padding — Decorator adding padding around any widget
// ============================================================================

/// Padding decorator adds uniform or custom padding around any widget.
/// The inner widget is rendered in a smaller area with padding space left empty.
pub fn Padding(comptime T: type) type {
    return struct {
        widget: T,
        top: u16,
        right: u16,
        bottom: u16,
        left: u16,

        const Self = @This();

        /// Create padding with uniform padding on all sides.
        pub fn init(widget: T, uniform: u16) Self {
            return .{
                .widget = widget,
                .top = uniform,
                .right = uniform,
                .bottom = uniform,
                .left = uniform,
            };
        }

        /// Create padding with custom values per side.
        pub fn initCustom(widget: T, top: u16, right: u16, bottom: u16, left: u16) Self {
            return .{
                .widget = widget,
                .top = top,
                .right = right,
                .bottom = bottom,
                .left = left,
            };
        }

        /// Render widget with padding. Padding area is left empty (default buffer content).
        pub fn render(self: Self, buf: *Buffer, area: Rect) void {
            // Calculate inner area after removing padding
            const total_horizontal = self.left + self.right;
            const total_vertical = self.top + self.bottom;

            // If padding exceeds area, render nothing (all padding)
            if (total_horizontal >= area.width or total_vertical >= area.height) {
                return;
            }

            const inner_area = Rect{
                .x = area.x + self.left,
                .y = area.y + self.top,
                .width = area.width - total_horizontal,
                .height = area.height - total_vertical,
            };

            // Render inner widget in padded area
            self.widget.render(buf, inner_area);
        }
    };
}

// ============================================================================
// Centered — Wrapper centering a widget in available area
// ============================================================================

/// Centered wrapper centers a widget within the available area.
/// If widget has measure(), uses preferred size for centering.
/// If widget lacks measure(), renders at full area (no centering).
pub fn Centered(comptime T: type) type {
    return struct {
        widget: T,

        const Self = @This();

        pub fn init(widget: T) Self {
            return .{ .widget = widget };
        }

        pub fn render(self: Self, buf: *Buffer, area: Rect) void {
            // Check if widget implements measure()
            if (@hasDecl(T, "measure")) {
                // Widget has measure() — get preferred size and center it
                const allocator = std.heap.page_allocator;
                const size = self.widget.measure(allocator, area.width, area.height) catch |err| {
                    _ = err;
                    // Measure failed — render at full area
                    self.widget.render(buf, area);
                    return;
                };

                // Clamp to area dimensions
                const widget_width = @min(size.width, area.width);
                const widget_height = @min(size.height, area.height);

                // Calculate centered position
                const offset_x = if (area.width > widget_width) (area.width - widget_width) / 2 else 0;
                const offset_y = if (area.height > widget_height) (area.height - widget_height) / 2 else 0;

                const centered_area = Rect{
                    .x = area.x + offset_x,
                    .y = area.y + offset_y,
                    .width = widget_width,
                    .height = widget_height,
                };

                self.widget.render(buf, centered_area);
            } else {
                // No measure() — render at full area
                self.widget.render(buf, area);
            }
        }
    };
}

// ============================================================================
// Aligned — Wrapper with alignment control
// ============================================================================

/// Alignment specification for horizontal and vertical positioning.
pub const Alignment = struct {
    horizontal: HAlign,
    vertical: VAlign,

    pub const HAlign = enum {
        left,
        center,
        right,
    };

    pub const VAlign = enum {
        top,
        middle,
        bottom,
    };
};

/// Aligned wrapper positions a widget according to alignment settings.
/// If widget has measure(), uses preferred size for alignment.
/// If widget lacks measure(), renders at area origin (no alignment calculation).
pub fn Aligned(comptime T: type) type {
    return struct {
        widget: T,
        h_align: Alignment.HAlign,
        v_align: Alignment.VAlign,

        const Self = @This();

        pub fn init(widget: T, alignment: Alignment) Self {
            return .{
                .widget = widget,
                .h_align = alignment.horizontal,
                .v_align = alignment.vertical,
            };
        }

        pub fn measure(self: Self, allocator: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
            if (@hasDecl(T, "measure")) {
                return try self.widget.measure(allocator, max_width, max_height);
            } else {
                return Size{ .width = max_width, .height = max_height };
            }
        }

        pub fn render(self: Self, buf: *Buffer, area: Rect) void {
            if (@hasDecl(T, "measure")) {
                // Widget has measure() — calculate aligned position
                const allocator = std.heap.page_allocator; // Use page allocator for measure
                const size = self.widget.measure(allocator, area.width, area.height) catch |err| {
                    _ = err;
                    // Measure failed — render at full area
                    self.widget.render(buf, area);
                    return;
                };

                const widget_width = @min(size.width, area.width);
                const widget_height = @min(size.height, area.height);

                // Calculate horizontal offset
                const offset_x = switch (self.h_align) {
                    .left => 0,
                    .center => if (area.width > widget_width) (area.width - widget_width) / 2 else 0,
                    .right => if (area.width > widget_width) area.width - widget_width else 0,
                };

                // Calculate vertical offset
                const offset_y = switch (self.v_align) {
                    .top => 0,
                    .middle => if (area.height > widget_height) (area.height - widget_height) / 2 else 0,
                    .bottom => if (area.height > widget_height) area.height - widget_height else 0,
                };

                const aligned_area = Rect{
                    .x = area.x + offset_x,
                    .y = area.y + offset_y,
                    .width = widget_width,
                    .height = widget_height,
                };

                self.widget.render(buf, aligned_area);
            } else {
                // No measure() — render at full area
                self.widget.render(buf, area);
            }
        }
    };
}

// ============================================================================
// Stack — Container for stacking widgets
// ============================================================================

/// Direction for stack layout.
pub const Direction = enum {
    vertical,
    horizontal,
};

/// Stack container arranges multiple widgets in vertical or horizontal layout.
/// Uses WidgetList for type-erased heterogeneous widget storage.
/// Widgets are distributed evenly across available space.
pub const Stack = struct {
    direction: Direction,
    widgets: WidgetList,

    const Self = @This();

    /// Create vertical stack.
    pub fn initVertical(allocator: std.mem.Allocator) !Self {
        return .{
            .direction = .vertical,
            .widgets = WidgetList.init(allocator),
        };
    }

    /// Create horizontal stack.
    pub fn initHorizontal(allocator: std.mem.Allocator) !Self {
        return .{
            .direction = .horizontal,
            .widgets = WidgetList.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.widgets.deinit();
    }

    /// Add a widget to the stack (type-specific).
    pub fn push(self: *Self, widget: anytype) !void {
        const T = @TypeOf(widget);
        try self.widgets.add(T, widget);
    }

    /// Add a widget to the stack (type-erased, for composition).
    pub fn pushAny(self: *Self, widget: anytype) !void {
        const T = @TypeOf(widget);
        try self.widgets.add(T, widget);
    }

    /// Render all widgets in stack layout.
    pub fn render(self: Self, buf: *Buffer, area: Rect) void {
        const count = self.widgets.count();
        if (count == 0) return;

        switch (self.direction) {
            .vertical => self.renderVertical(buf, area),
            .horizontal => self.renderHorizontal(buf, area),
        }
    }

    fn renderVertical(self: Self, buf: *Buffer, area: Rect) void {
        const count = self.widgets.count();
        const height_per_widget = area.height / @as(u16, @intCast(count));

        var y: u16 = area.y;
        for (0..count) |i| {
            const is_last = (i == count - 1);

            // Last widget gets remaining height to handle rounding
            const widget_height = if (is_last)
                area.y + area.height - y
            else
                height_per_widget;

            if (widget_height == 0) break;

            const widget_area = Rect{
                .x = area.x,
                .y = y,
                .width = area.width,
                .height = widget_height,
            };

            self.widgets.renderAt(i, buf, widget_area) catch {};
            y += widget_height;
        }
    }

    fn renderHorizontal(self: Self, buf: *Buffer, area: Rect) void {
        const count = self.widgets.count();
        const width_per_widget = area.width / @as(u16, @intCast(count));

        var x: u16 = area.x;
        for (0..count) |i| {
            const is_last = (i == count - 1);

            // Last widget gets remaining width to handle rounding
            const widget_width = if (is_last)
                area.x + area.width - x
            else
                width_per_widget;

            if (widget_width == 0) break;

            const widget_area = Rect{
                .x = x,
                .y = area.y,
                .width = widget_width,
                .height = area.height,
            };

            self.widgets.renderAt(i, buf, widget_area) catch {};
            x += widget_width;
        }
    }
};

// ============================================================================
// Constrained — Enforces min/max size constraints
// ============================================================================

/// Constraint configuration.
pub const Constraints = struct {
    min_width: ?u16 = null,
    max_width: ?u16 = null,
    min_height: ?u16 = null,
    max_height: ?u16 = null,
};

/// Constrained wrapper enforces minimum and maximum size constraints.
/// Widget is rendered within the constrained dimensions.
pub fn Constrained(comptime T: type) type {
    return struct {
        widget: T,
        min_width: ?u16,
        max_width: ?u16,
        min_height: ?u16,
        max_height: ?u16,

        const Self = @This();

        pub fn init(widget: T, constraints: Constraints) Self {
            return .{
                .widget = widget,
                .min_width = constraints.min_width,
                .max_width = constraints.max_width,
                .min_height = constraints.min_height,
                .max_height = constraints.max_height,
            };
        }

        pub fn measure(self: Self, allocator: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
            // Get widget's preferred size
            var width = max_width;
            var height = max_height;

            if (@hasDecl(T, "measure")) {
                const widget_size = try self.widget.measure(allocator, max_width, max_height);
                width = widget_size.width;
                height = widget_size.height;
            }

            // Apply max constraints first
            if (self.max_width) |max_w| {
                width = @min(width, max_w);
            }
            if (self.max_height) |max_h| {
                height = @min(height, max_h);
            }

            // Apply min constraints
            if (self.min_width) |min_w| {
                width = @max(width, min_w);
            }
            if (self.min_height) |min_h| {
                height = @max(height, min_h);
            }

            return Size{ .width = width, .height = height };
        }

        pub fn render(self: Self, buf: *Buffer, area: Rect) void {
            // Apply constraints to area dimensions
            var constrained_width = area.width;
            var constrained_height = area.height;

            // Apply max constraints first
            if (self.max_width) |max_w| {
                constrained_width = @min(constrained_width, max_w);
            }
            if (self.max_height) |max_h| {
                constrained_height = @min(constrained_height, max_h);
            }

            // Apply min constraints
            if (self.min_width) |min_w| {
                constrained_width = @max(constrained_width, min_w);
            }
            if (self.min_height) |min_h| {
                constrained_height = @max(constrained_height, min_h);
            }

            const constrained_area = Rect{
                .x = area.x,
                .y = area.y,
                .width = constrained_width,
                .height = constrained_height,
            };

            self.widget.render(buf, constrained_area);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

// Mock widget for testing
const MockWidget = struct {
    content: u8,

    pub fn render(self: MockWidget, buf: *Buffer, area: Rect) void {
        for (0..area.height) |dy| {
            for (0..area.width) |dx| {
                buf.setChar(
                    @intCast(area.x + @as(u16, @intCast(dx))),
                    @intCast(area.y + @as(u16, @intCast(dy))),
                    self.content,
                    .{},
                );
            }
        }
    }

    pub fn measure(_: MockWidget, _: std.mem.Allocator, _: u16, _: u16) !Size {
        return Size{ .width = 10, .height = 5 };
    }
};

test "Padding - uniform padding" {
    const PaddedWidget = Padding(MockWidget);
    const mock = MockWidget{ .content = 'X' };
    const padded = PaddedWidget.init(mock, 2);

    try std.testing.expectEqual(@as(u16, 2), padded.top);
    try std.testing.expectEqual(@as(u16, 2), padded.right);
    try std.testing.expectEqual(@as(u16, 2), padded.bottom);
    try std.testing.expectEqual(@as(u16, 2), padded.left);
}

test "Padding - custom padding" {
    const PaddedWidget = Padding(MockWidget);
    const mock = MockWidget{ .content = 'X' };
    const padded = PaddedWidget.initCustom(mock, 1, 2, 3, 4);

    try std.testing.expectEqual(@as(u16, 1), padded.top);
    try std.testing.expectEqual(@as(u16, 2), padded.right);
    try std.testing.expectEqual(@as(u16, 3), padded.bottom);
    try std.testing.expectEqual(@as(u16, 4), padded.left);
}

test "Padding - render with padding" {
    const PaddedWidget = Padding(MockWidget);
    const mock = MockWidget{ .content = 'X' };
    const padded = PaddedWidget.init(mock, 2);

    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    padded.render(&buf, area);

    // Check that padding area is NOT filled
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(0, 1).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(1, 0).?.char);

    // Check that inner area IS filled
    try std.testing.expectEqual(@as(u21, 'X'), buf.getConst(2, 2).?.char);
    try std.testing.expectEqual(@as(u21, 'X'), buf.getConst(10, 10).?.char);
}

test "Padding - excessive padding renders nothing" {
    const PaddedWidget = Padding(MockWidget);
    const mock = MockWidget{ .content = 'X' };
    const padded = PaddedWidget.init(mock, 100); // Excessive padding

    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    padded.render(&buf, area);

    // All cells should remain empty (space)
    for (0..20) |y| {
        for (0..20) |x| {
            try std.testing.expectEqual(@as(u21, ' '), buf.getConst(@intCast(x), @intCast(y)).?.char);
        }
    }
}

test "Centered - centers widget with measure" {
    const CenteredWidget = Centered(MockWidget);
    const mock = MockWidget{ .content = 'C' };
    const centered = CenteredWidget.init(mock);

    var buf = try Buffer.init(std.testing.allocator, 30, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    centered.render(&buf, area);

    // Widget should be centered: (30-10)/2 = 10, (20-5)/2 = 7.5 ≈ 7
    // Check centered position (offset_x = 10, offset_y = 7)
    try std.testing.expectEqual(@as(u21, 'C'), buf.getConst(10, 7).?.char);
    try std.testing.expectEqual(@as(u21, 'C'), buf.getConst(19, 11).?.char); // 10+9, 7+4
}

test "Alignment - horizontal left, vertical top" {
    const AlignedWidget = Aligned(MockWidget);
    const mock = MockWidget{ .content = 'A' };
    const aligned = AlignedWidget.init(mock, .{
        .horizontal = .left,
        .vertical = .top,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    aligned.render(&buf, area);

    // Should align to top-left (0, 0)
    try std.testing.expectEqual(@as(u21, 'A'), buf.getConst(0, 0).?.char);
}

test "Alignment - horizontal right, vertical bottom" {
    const AlignedWidget = Aligned(MockWidget);
    const mock = MockWidget{ .content = 'A' };
    const aligned = AlignedWidget.init(mock, .{
        .horizontal = .right,
        .vertical = .bottom,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    aligned.render(&buf, area);

    // Should align to bottom-right: x = 30-10 = 20, y = 20-5 = 15
    try std.testing.expectEqual(@as(u21, 'A'), buf.getConst(20, 15).?.char);
}

test "Alignment - horizontal center, vertical middle" {
    const AlignedWidget = Aligned(MockWidget);
    const mock = MockWidget{ .content = 'A' };
    const aligned = AlignedWidget.init(mock, .{
        .horizontal = .center,
        .vertical = .middle,
    });

    var buf = try Buffer.init(std.testing.allocator, 30, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    aligned.render(&buf, area);

    // Should center: x = (30-10)/2 = 10, y = (20-5)/2 = 7
    try std.testing.expectEqual(@as(u21, 'A'), buf.getConst(10, 7).?.char);
}

test "Alignment - measure passthrough" {
    const AlignedWidget = Aligned(MockWidget);
    const mock = MockWidget{ .content = 'A' };
    const aligned = AlignedWidget.init(mock, .{
        .horizontal = .center,
        .vertical = .middle,
    });

    const size = try aligned.measure(std.testing.allocator, 100, 100);
    try std.testing.expectEqual(@as(u16, 10), size.width);
    try std.testing.expectEqual(@as(u16, 5), size.height);
}

test "Stack - vertical layout" {
    var stack = try Stack.initVertical(std.testing.allocator);
    defer stack.deinit();

    try stack.push(MockWidget{ .content = '1' });
    try stack.push(MockWidget{ .content = '2' });
    try stack.push(MockWidget{ .content = '3' });

    var buf = try Buffer.init(std.testing.allocator, 20, 30);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 30 };
    stack.render(&buf, area);

    // Each widget gets 30/3 = 10 rows
    try std.testing.expectEqual(@as(u21, '1'), buf.getConst(0, 0).?.char); // First widget
    try std.testing.expectEqual(@as(u21, '2'), buf.getConst(0, 10).?.char); // Second widget
    try std.testing.expectEqual(@as(u21, '3'), buf.getConst(0, 20).?.char); // Third widget
}

test "Stack - horizontal layout" {
    var stack = try Stack.initHorizontal(std.testing.allocator);
    defer stack.deinit();

    try stack.push(MockWidget{ .content = 'A' });
    try stack.push(MockWidget{ .content = 'B' });

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    stack.render(&buf, area);

    // Each widget gets 20/2 = 10 columns
    try std.testing.expectEqual(@as(u21, 'A'), buf.getConst(0, 0).?.char); // First widget
    try std.testing.expectEqual(@as(u21, 'B'), buf.getConst(10, 0).?.char); // Second widget
}

test "Stack - empty stack renders nothing" {
    var stack = try Stack.initVertical(std.testing.allocator);
    defer stack.deinit();

    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    stack.render(&buf, area);

    // Should remain empty
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(0, 0).?.char);
}

test "Constrained - min/max width" {
    const ConstrainedWidget = Constrained(MockWidget);
    const mock = MockWidget{ .content = 'C' };
    const constrained = ConstrainedWidget.init(mock, .{
        .min_width = 5,
        .max_width = 15,
    });

    const size1 = try constrained.measure(std.testing.allocator, 100, 100);
    try std.testing.expectEqual(@as(u16, 10), size1.width); // Widget prefers 10, within [5, 15]

    const constrained_max = ConstrainedWidget.init(mock, .{
        .min_width = 5,
        .max_width = 8,
    });
    const size2 = try constrained_max.measure(std.testing.allocator, 100, 100);
    try std.testing.expectEqual(@as(u16, 8), size2.width); // Forced to max_width (widget wants 10)

    const constrained_min = ConstrainedWidget.init(mock, .{
        .min_width = 15,
        .max_width = 20,
    });
    const size3 = try constrained_min.measure(std.testing.allocator, 100, 100);
    try std.testing.expectEqual(@as(u16, 15), size3.width); // Forced to min_width (widget wants 10)
}

test "Constrained - min/max height" {
    const ConstrainedWidget = Constrained(MockWidget);
    const mock = MockWidget{ .content = 'C' };
    const constrained = ConstrainedWidget.init(mock, .{
        .min_height = 3,
        .max_height = 8,
    });

    const size1 = try constrained.measure(std.testing.allocator, 100, 100);
    try std.testing.expectEqual(@as(u16, 5), size1.height); // Widget prefers 5, within [3, 8]

    const constrained_max = ConstrainedWidget.init(mock, .{
        .min_height = 1,
        .max_height = 3,
    });
    const size2 = try constrained_max.measure(std.testing.allocator, 100, 100);
    try std.testing.expectEqual(@as(u16, 3), size2.height); // Forced to max_height (widget wants 5)

    const constrained_min = ConstrainedWidget.init(mock, .{
        .min_height = 8,
        .max_height = 10,
    });
    const size3 = try constrained_min.measure(std.testing.allocator, 100, 100);
    try std.testing.expectEqual(@as(u16, 8), size3.height); // Forced to min_height (widget wants 5)
}

test "Constrained - render with constraints" {
    const ConstrainedWidget = Constrained(MockWidget);
    const mock = MockWidget{ .content = 'C' };
    const constrained = ConstrainedWidget.init(mock, .{
        .max_width = 10,
        .max_height = 10,
    });

    var buf = try Buffer.init(std.testing.allocator, 50, 50);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 50 };
    constrained.render(&buf, area);

    // Widget should be constrained to 10x10
    try std.testing.expectEqual(@as(u21, 'C'), buf.getConst(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'C'), buf.getConst(9, 9).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(10, 10).?.char); // Outside constraint
}

test "Constraints - all fields optional" {
    const c1 = Constraints{};
    try std.testing.expectEqual(@as(?u16, null), c1.min_width);
    try std.testing.expectEqual(@as(?u16, null), c1.max_width);

    const c2 = Constraints{ .min_width = 10 };
    try std.testing.expectEqual(@as(?u16, 10), c2.min_width);
    try std.testing.expectEqual(@as(?u16, null), c2.max_width);
}
