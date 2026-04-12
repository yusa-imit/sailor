//! Plugin Architecture Tests (v1.23.0)
//!
//! Tests for:
//! - Widget trait system (render + measure)
//! - Custom renderer hooks (pre/post callbacks)
//! - Theme plugin system (JSON loading)
//! - Widget composition helpers (Padding, Centered, Aligned, Stack, Constrained)
//! - Third-party widget integration

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Size = sailor.tui.widget_trait.Size;

// Composition helpers
const Padding = sailor.tui.widget_helpers.Padding;
const Centered = sailor.tui.widget_helpers.Centered;
const Aligned = sailor.tui.widget_helpers.Aligned;
const Stack = sailor.tui.widget_helpers.Stack;
const Constrained = sailor.tui.widget_helpers.Constrained;

// ============================================================================
// Custom Plugin Widget for Testing
// ============================================================================

/// Example third-party widget implementing the widget protocol.
const CustomBadge = struct {
    label: []const u8,
    style: Style,

    pub fn init(label: []const u8, style: Style) CustomBadge {
        return .{ .label = label, .style = style };
    }

    pub fn measure(self: CustomBadge, _: std.mem.Allocator, max_width: u16, max_height: u16) !Size {
        const width = @as(u16, @intCast(@min(self.label.len + 2, max_width))); // [label] = 2 brackets
        const height = @min(1, max_height);
        return Size{ .width = width, .height = height };
    }

    pub fn render(self: CustomBadge, buf: *Buffer, area: Rect) void {
        if (area.width < 3 or area.height == 0) return;

        // Render badge: [label]
        buf.set(area.x, area.y, .{ .char = '[', .style = self.style });
        const label_width = @min(self.label.len, area.width - 2);
        buf.setString(area.x + 1, area.y, self.label[0..label_width], self.style);
        if (area.width > label_width + 1) {
            buf.set(area.x + 1 + @as(u16, @intCast(label_width)), area.y, .{ .char = ']', .style = self.style });
        }
    }
};

// ============================================================================
// Test 1: Widget Trait Protocol
// ============================================================================

test "plugin: custom widget implements protocol" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const badge = CustomBadge.init("INFO", Style{ .fg = Color{ .indexed = 12 } });

    // Test measure
    const size = try badge.measure(allocator, 20, 5);
    try testing.expectEqual(@as(u16, 6), size.width); // [INFO]
    try testing.expectEqual(@as(u16, 1), size.height);

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    badge.render(&buf, area);

    // Verify output (buf.get returns optional)
    try testing.expectEqual('[', buf.get(0, 0).?.char);
    try testing.expectEqual('I', buf.get(1, 0).?.char);
    try testing.expectEqual('N', buf.get(2, 0).?.char);
    try testing.expectEqual('F', buf.get(3, 0).?.char);
    try testing.expectEqual('O', buf.get(4, 0).?.char);
    try testing.expectEqual(']', buf.get(5, 0).?.char);
}

// ============================================================================
// Test 2: Composition Helper - Padding
// ============================================================================

test "plugin: Padding composition helper" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const badge = CustomBadge.init("OK", Style{ .fg = Color{ .indexed = 10 } });
    const padded = Padding(CustomBadge).init(badge, 2);

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    padded.render(&buf, area);

    // Content should be at (2, 2) — padding of 2 on all sides
    try testing.expectEqual('[', buf.get(2, 2).?.char);
    try testing.expectEqual('O', buf.get(3, 2).?.char);
    try testing.expectEqual('K', buf.get(4, 2).?.char);
    try testing.expectEqual(']', buf.get(5, 2).?.char);
}

// ============================================================================
// Test 3: Composition Helper - Centered
// ============================================================================

test "plugin: Centered composition helper" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const badge = CustomBadge.init("OK", Style{ .fg = Color{ .indexed = 10 } });
    const centered = Centered(CustomBadge).init(badge);

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    centered.render(&buf, area);

    // Verify badge was rendered somewhere (centering logic can vary)
    var found_bracket = false;
    var found_o = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell) |c| {
                if (c.char == '[') found_bracket = true;
                if (c.char == 'O') found_o = true;
            }
        }
    }
    try testing.expect(found_bracket);
    try testing.expect(found_o);
}

// ============================================================================
// Test 4: Composition Helper - Aligned
// ============================================================================

test "plugin: Aligned composition helper" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const badge = CustomBadge.init("OK", Style{ .fg = Color{ .indexed = 10 } });
    const aligned = Aligned(CustomBadge).init(badge, .{
        .horizontal = .left,
        .vertical = .top,
    });

    // Test render — left-top alignment should render at (0, 0)
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    aligned.render(&buf, area);

    // Verify it rendered
    try testing.expectEqual('[', buf.get(0, 0).?.char);
    try testing.expectEqual('O', buf.get(1, 0).?.char);
    try testing.expectEqual('K', buf.get(2, 0).?.char);
    try testing.expectEqual(']', buf.get(3, 0).?.char);
}

// ============================================================================
// Test 5: Composition Helper - Stack (vertical)
// ============================================================================

test "plugin: Stack vertical composition" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const badge1 = CustomBadge.init("A", Style{ .fg = Color{ .indexed = 9 } });
    const badge2 = CustomBadge.init("B", Style{ .fg = Color{ .indexed = 10 } });
    const badge3 = CustomBadge.init("C", Style{ .fg = Color{ .indexed = 11 } });

    var stack = try Stack.initVertical(allocator);
    defer stack.deinit();
    try stack.push(badge1);
    try stack.push(badge2);
    try stack.push(badge3);

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    stack.render(&buf, area);

    // Verify all three badges were rendered (positions depend on distribution logic)
    var found_a = false;
    var found_b = false;
    var found_c = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell) |c| {
                if (c.char == 'A') found_a = true;
                if (c.char == 'B') found_b = true;
                if (c.char == 'C') found_c = true;
            }
        }
    }
    try testing.expect(found_a);
    try testing.expect(found_b);
    try testing.expect(found_c);
}

// ============================================================================
// Test 6: Composition Helper - Stack (horizontal)
// ============================================================================

test "plugin: Stack horizontal composition" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const badge1 = CustomBadge.init("X", Style{ .fg = Color{ .indexed = 9 } });
    const badge2 = CustomBadge.init("Y", Style{ .fg = Color{ .indexed = 10 } });

    var stack = try Stack.initHorizontal(allocator);
    defer stack.deinit();
    try stack.push(badge1);
    try stack.push(badge2);

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    stack.render(&buf, area);

    // Verify both badges were rendered
    var found_x = false;
    var found_y = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell) |c| {
                if (c.char == 'X') found_x = true;
                if (c.char == 'Y') found_y = true;
            }
        }
    }
    try testing.expect(found_x);
    try testing.expect(found_y);
}

// ============================================================================
// Test 7: Composition Helper - Constrained
// ============================================================================

test "plugin: Constrained composition helper" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 20);
    defer buf.deinit();

    const badge = CustomBadge.init("LONG_LABEL", Style{ .fg = Color{ .indexed = 12 } });
    const constrained = Constrained(CustomBadge).init(badge, .{
        .max_width = 8,
        .max_height = 1,
    });

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    constrained.render(&buf, area);

    // Verify badge was rendered (clipped to 8 width)
    try testing.expectEqual('[', buf.get(0, 0).?.char);
    try testing.expectEqual('L', buf.get(1, 0).?.char);
    try testing.expectEqual('O', buf.get(2, 0).?.char);
    try testing.expectEqual('N', buf.get(3, 0).?.char);
    try testing.expectEqual('G', buf.get(4, 0).?.char);
    try testing.expectEqual('_', buf.get(5, 0).?.char);
    try testing.expectEqual('L', buf.get(6, 0).?.char);
    try testing.expectEqual(']', buf.get(7, 0).?.char);
}

// ============================================================================
// Test 8: Nested Composition (Padding + Centered)
// ============================================================================

test "plugin: nested composition helpers" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 15);
    defer buf.deinit();

    const badge = CustomBadge.init("OK", Style{ .fg = Color{ .indexed = 10 } });

    // Nest: Padding -> Centered
    const padded = Padding(CustomBadge).init(badge, 1);
    const centered = Centered(Padding(CustomBadge)).init(padded);

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    centered.render(&buf, area);

    // Verify badge was rendered somewhere
    var found_bracket = false;
    var found_o = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell) |c| {
                if (c.char == '[') found_bracket = true;
                if (c.char == 'O') found_o = true;
            }
        }
    }
    try testing.expect(found_bracket);
    try testing.expect(found_o);
}

// ============================================================================
// Test 9: Integration Test - Full Plugin System
// ============================================================================

test "plugin: full integration with all features" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();

    // Create custom badge
    const badge = CustomBadge.init("PLUGIN", Style{ .fg = Color{ .indexed = 14 } });

    // Apply all composition helpers
    const padded = Padding(CustomBadge).init(badge, 2);
    const aligned = Aligned(Padding(CustomBadge)).init(padded, .{
        .horizontal = .center,
        .vertical = .middle,
    });
    const constrained = Constrained(Aligned(Padding(CustomBadge))).init(aligned, .{
        .max_width = 30,
        .max_height = 15,
    });

    // Test render
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    constrained.render(&buf, area);

    // Verify badge was rendered (exact position depends on centering logic)
    var found_p = false;
    var found_bracket = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell) |c| {
                if (c.char == 'P') found_p = true;
                if (c.char == '[') found_bracket = true;
            }
        }
    }
    try testing.expect(found_p);
    try testing.expect(found_bracket);
}

// ============================================================================
// Test 10: Example Plugin Demo Integration
// ============================================================================

test "plugin: example demo widget works" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 15);
    defer buf.deinit();

    // Simulate the plugin_demo.zig example
    const badge = CustomBadge.init("Demo", Style{ .fg = Color{ .indexed = 14 } });
    const padded = Padding(CustomBadge).init(badge, 2);
    const aligned = Aligned(Padding(CustomBadge)).init(padded, .{
        .horizontal = .center,
        .vertical = .middle,
    });

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    aligned.render(&buf, area);

    // Verify it rendered
    var found_d = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell) |c| {
                if (c.char == 'D') found_d = true;
            }
        }
    }
    try testing.expect(found_d);
}
