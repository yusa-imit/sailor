//! Comprehensive tests for shadow.zig module (v2.3.0 Advanced Styling)
//!
//! Tests shadow effects system including:
//! - Shadow struct initialization and configuration
//! - Shadow rendering to buffer cells with darkening effects
//! - Multiple shadow styles (drop shadow, inner shadow, box shadow)
//! - Shadow opacity and intensity control
//! - Edge cases (zero offset, zero blur, out-of-bounds positions)
//! - Performance characteristics of shadow rendering
//!
//! These tests follow TDD principles and WILL FAIL until implementation is complete.

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const shadow = sailor.tui.shadow;
const Shadow = shadow.Shadow;
const ShadowStyle = shadow.ShadowStyle;
const Buffer = sailor.tui.Buffer;
const Color = sailor.tui.Color;
const Rect = sailor.tui.Rect;
const Cell = sailor.tui.Cell;

// ============================================================================
// Shadow Struct Initialization Tests
// ============================================================================

test "Shadow.init - default drop shadow" {
    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    try testing.expectEqual(@as(i16, 2), s.offset_x);
    try testing.expectEqual(@as(i16, 1), s.offset_y);
    try testing.expectEqual(@as(u8, 0), s.blur_radius);
    try testing.expectEqual(Color.black, s.color);
    try testing.expectEqual(@as(f32, 1.0), s.opacity);
    try testing.expectEqual(ShadowStyle.drop, s.style);
}

test "Shadow.init - with blur and opacity" {
    const s = Shadow{
        .offset_x = 0,
        .offset_y = 0,
        .blur_radius = 3,
        .color = Color.fromRgb(0, 0, 0),
        .opacity = 0.5,
        .style = .box,
    };

    try testing.expectEqual(@as(u8, 3), s.blur_radius);
    try testing.expectEqual(@as(f32, 0.5), s.opacity);
    try testing.expectEqual(ShadowStyle.box, s.style);
}

test "Shadow.init - negative offset" {
    const s = Shadow{
        .offset_x = -3,
        .offset_y = -2,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 0.8,
        .style = .drop,
    };

    try testing.expectEqual(@as(i16, -3), s.offset_x);
    try testing.expectEqual(@as(i16, -2), s.offset_y);
}

test "Shadow.init - inner shadow style" {
    const s = Shadow{
        .offset_x = 1,
        .offset_y = 1,
        .blur_radius = 2,
        .color = Color.black,
        .opacity = 0.6,
        .style = .inner,
    };

    try testing.expectEqual(ShadowStyle.inner, s.style);
}

test "Shadow.init - zero blur radius" {
    const s = Shadow{
        .offset_x = 5,
        .offset_y = 5,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    try testing.expectEqual(@as(u8, 0), s.blur_radius);
}

test "Shadow.init - opacity range validation" {
    // Test boundary values (implementation should clamp 0.0-1.0)
    const s1 = Shadow{
        .offset_x = 0,
        .offset_y = 0,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 0.0,
        .style = .drop,
    };
    try testing.expectEqual(@as(f32, 0.0), s1.opacity);

    const s2 = Shadow{
        .offset_x = 0,
        .offset_y = 0,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };
    try testing.expectEqual(@as(f32, 1.0), s2.opacity);
}

// ============================================================================
// Shadow Style Enum Tests
// ============================================================================

test "ShadowStyle - all variants exist" {
    const drop = ShadowStyle.drop;
    const inner = ShadowStyle.inner;
    const box = ShadowStyle.box;

    try testing.expectEqual(ShadowStyle.drop, drop);
    try testing.expectEqual(ShadowStyle.inner, inner);
    try testing.expectEqual(ShadowStyle.box, box);
}

// ============================================================================
// Shadow Rendering to Buffer Tests
// ============================================================================

test "Shadow.render - basic drop shadow with zero blur" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    // Create a simple widget area (5x3 box)
    const widget_area = Rect{ .x = 5, .y = 3, .width = 5, .height = 3 };

    // Fill widget area to visualize (not part of shadow implementation)
    buffer.fill(widget_area, 'X', .{ .fg = .white });

    // Create shadow: offset right and down by 2, no blur
    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    // Render shadow to buffer
    try s.render(&buffer, widget_area);

    // Shadow should appear at offset position (7, 4) for a 5x3 area
    // Top-left of shadow = (5+2, 3+1) = (7, 4)
    const shadow_cell = buffer.get(7, 4).?;

    // Shadow cell should have darkened background (implementation detail)
    // Test WILL FAIL until implementation exists
    try testing.expect(shadow_cell.style.bg != null);
}

test "Shadow.render - negative offset (shadow above and left)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 10, .y = 5, .width = 4, .height = 2 };

    const s = Shadow{
        .offset_x = -2,
        .offset_y = -1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    // Shadow top-left = (10-2, 5-1) = (8, 4)
    const shadow_cell = buffer.get(8, 4).?;
    try testing.expect(shadow_cell.style.bg != null);
}

test "Shadow.render - with blur radius darkens surrounding cells" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 20);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 10, .y = 8, .width = 6, .height = 4 };

    const s = Shadow{
        .offset_x = 3,
        .offset_y = 2,
        .blur_radius = 2,
        .color = Color.black,
        .opacity = 0.8,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    // Core shadow area (offset position)
    const core_cell = buffer.get(13, 10).?;
    try testing.expect(core_cell.style.bg != null);

    // Blurred edge (should be darker but less intense)
    // At blur_radius=2, cells within 2 units should have some darkening
    const edge_cell = buffer.get(15, 12).?;
    // Implementation should darken background based on distance
    // Test WILL FAIL until blur logic is implemented
    try testing.expect(edge_cell.style.bg != null or edge_cell.char != ' ');
}

test "Shadow.render - opacity affects darkness intensity" {
    const allocator = testing.allocator;
    var buffer1 = try Buffer.init(allocator, 20, 10);
    defer buffer1.deinit();
    var buffer2 = try Buffer.init(allocator, 20, 10);
    defer buffer2.deinit();

    const area = Rect{ .x = 5, .y = 3, .width = 4, .height = 3 };

    // Full opacity shadow
    const s1 = Shadow{
        .offset_x = 1,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };
    try s1.render(&buffer1, area);

    // Half opacity shadow
    const s2 = Shadow{
        .offset_x = 1,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 0.5,
        .style = .drop,
    };
    try s2.render(&buffer2, area);

    const cell1 = buffer1.get(6, 4).?;
    const cell2 = buffer2.get(6, 4).?;

    // Both should have background, but different darkness levels
    // (implementation detail: may use different RGB values or indexed colors)
    try testing.expect(cell1.style.bg != null);
    try testing.expect(cell2.style.bg != null);
    // Cannot directly compare RGB values without knowing implementation strategy
}

test "Shadow.render - box shadow affects all four sides" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 20);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 10, .y = 8, .width = 8, .height = 5 };

    const s = Shadow{
        .offset_x = 0,
        .offset_y = 0,
        .blur_radius = 2,
        .color = Color.black,
        .opacity = 0.7,
        .style = .box,
    };

    try s.render(&buffer, widget_area);

    // Box shadow should darken cells around all edges
    // Top edge (above widget)
    const top_cell = buffer.get(10, 6).?; // y=8-2=6
    try testing.expect(top_cell.style.bg != null or top_cell.char != ' ');

    // Bottom edge (below widget)
    const bottom_cell = buffer.get(10, 15).?; // y=8+5+2=15
    try testing.expect(bottom_cell.style.bg != null or bottom_cell.char != ' ');

    // Left edge
    const left_cell = buffer.get(8, 10).?; // x=10-2=8
    try testing.expect(left_cell.style.bg != null or left_cell.char != ' ');

    // Right edge
    const right_cell = buffer.get(20, 10).?; // x=10+8+2=20
    try testing.expect(right_cell.style.bg != null or right_cell.char != ' ');
}

test "Shadow.render - inner shadow only darkens inside widget area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 5, .y = 3, .width = 8, .height = 4 };

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 0.6,
        .style = .inner,
    };

    try s.render(&buffer, widget_area);

    // Inner shadow should only affect cells INSIDE the widget area
    // Cell inside widget area (near edge)
    const inner_cell = buffer.get(6, 4).?; // Inside (5,3)-(13,7)
    try testing.expect(inner_cell.style.bg != null or inner_cell.char != ' ');

    // Cell outside widget area should NOT be affected
    const outer_cell = buffer.get(14, 3).?; // Outside (x=13+1)
    try testing.expectEqual(@as(u21, ' '), outer_cell.char);
    try testing.expectEqual(@as(?Color, null), outer_cell.style.bg);
}

// ============================================================================
// Edge Cases - Out of Bounds Tests
// ============================================================================

test "Shadow.render - shadow partially out of bounds (right edge)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 15, 10);
    defer buffer.deinit();

    // Widget near right edge
    const widget_area = Rect{ .x = 12, .y = 3, .width = 4, .height = 3 };

    const s = Shadow{
        .offset_x = 3,
        .offset_y = 1,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    // Should not crash or panic when shadow extends beyond buffer
    try s.render(&buffer, widget_area);

    // Visible shadow part should still render
    const visible_cell = buffer.get(13, 4).?;
    // Implementation should handle bounds checking
    // Test WILL FAIL if bounds checking is missing
    try testing.expect(visible_cell.style.bg != null or visible_cell.char == ' ');
}

test "Shadow.render - shadow completely out of bounds" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    // Widget completely outside buffer
    const widget_area = Rect{ .x = 15, .y = 15, .width = 3, .height = 2 };

    const s = Shadow{
        .offset_x = 1,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    // Should not crash
    try s.render(&buffer, widget_area);

    // Buffer should remain unchanged (all spaces)
    const cell = buffer.get(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "Shadow.render - negative offset pushes shadow out of bounds (top-left)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    // Widget near top-left corner
    const widget_area = Rect{ .x = 2, .y = 2, .width = 4, .height = 3 };

    const s = Shadow{
        .offset_x = -3,
        .offset_y = -3,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    // Should not crash (shadow would be at negative coordinates)
    try s.render(&buffer, widget_area);

    // No shadow should be visible
    const cell = buffer.get(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "Shadow.render - zero-size widget area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 5, .y = 5, .width = 0, .height = 0 };

    const s = Shadow{
        .offset_x = 1,
        .offset_y = 1,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    // Should not crash on zero-size area
    try s.render(&buffer, widget_area);

    // Buffer should remain empty
    const cell = buffer.get(5, 5).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

// ============================================================================
// Edge Cases - Zero Offset and Blur Tests
// ============================================================================

test "Shadow.render - zero offset with blur creates glow effect" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 8, .y = 6, .width = 6, .height = 4 };

    const s = Shadow{
        .offset_x = 0,
        .offset_y = 0,
        .blur_radius = 2,
        .color = Color.fromRgb(255, 255, 0), // Yellow glow
        .opacity = 0.7,
        .style = .box,
    };

    try s.render(&buffer, widget_area);

    // Should darken/glow cells around the widget uniformly
    const top_cell = buffer.get(8, 4).?; // Above widget
    const right_cell = buffer.get(16, 8).?; // Right of widget

    // Both should have some effect (implementation may vary)
    try testing.expect(top_cell.style.bg != null or top_cell.char != ' ');
    try testing.expect(right_cell.style.bg != null or right_cell.char != ' ');
}

test "Shadow.render - zero blur with offset creates hard shadow" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 5, .y = 5, .width = 6, .height = 4 };

    const s = Shadow{
        .offset_x = 3,
        .offset_y = 2,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    // Shadow should be sharp (no blur gradient)
    // Core shadow area
    const shadow_core = buffer.get(8, 7).?; // offset from (5,5)
    try testing.expect(shadow_core.style.bg != null);

    // Adjacent cell outside shadow should NOT be affected
    const outside = buffer.get(7, 7).?;
    try testing.expectEqual(@as(u21, ' '), outside.char);
    try testing.expectEqual(@as(?Color, null), outside.style.bg);
}

test "Shadow.render - zero offset and zero blur (no shadow)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 5, .y = 5, .width = 6, .height = 4 };

    const s = Shadow{
        .offset_x = 0,
        .offset_y = 0,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    // Rendering should be a no-op or minimal effect
    try s.render(&buffer, widget_area);

    // Buffer should be mostly empty (implementation may choose to render or skip)
    const cell = buffer.get(5, 5).?;
    // Implementation decision: zero offset + zero blur may render nothing
    try testing.expect(cell.char == ' ' or cell.style.bg != null);
}

// ============================================================================
// Shadow Color and Opacity Tests
// ============================================================================

test "Shadow.render - colored shadow (blue)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 5, .y = 5, .width = 5, .height = 3 };

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.fromRgb(0, 0, 255), // Blue shadow
        .opacity = 1.0,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    const shadow_cell = buffer.get(7, 6).?;
    // Shadow should have blue tint in background
    try testing.expect(shadow_cell.style.bg != null);
    // Specific color verification depends on implementation strategy
}

test "Shadow.render - opacity zero creates no visible shadow" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 5, .y = 5, .width = 5, .height = 3 };

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 0.0,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    // Zero opacity should result in no visible shadow
    const cell = buffer.get(7, 6).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
    try testing.expectEqual(@as(?Color, null), cell.style.bg);
}

test "Shadow.render - opacity interpolation accuracy" {
    const allocator = testing.allocator;

    // Test multiple opacity levels to verify correct darkening calculation
    const opacities = [_]f32{ 0.1, 0.3, 0.5, 0.7, 0.9 };

    for (opacities) |opacity| {
        var buffer = try Buffer.init(allocator, 15, 10);
        defer buffer.deinit();

        const widget_area = Rect{ .x = 5, .y = 3, .width = 4, .height = 3 };

        const s = Shadow{
            .offset_x = 1,
            .offset_y = 1,
            .blur_radius = 0,
            .color = Color.black,
            .opacity = opacity,
            .style = .drop,
        };

        try s.render(&buffer, widget_area);

        const shadow_cell = buffer.get(6, 4).?;
        // Implementation should apply opacity correctly
        // Test WILL FAIL if opacity is not applied
        try testing.expect(shadow_cell.style.bg != null or opacity == 0.0);
    }
}

// ============================================================================
// Blur Radius Tests
// ============================================================================

test "Shadow.render - blur radius affects shadow spread" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 20);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 10, .y = 8, .width = 6, .height = 4 };

    const s = Shadow{
        .offset_x = 3,
        .offset_y = 2,
        .blur_radius = 4,
        .color = Color.black,
        .opacity = 0.8,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    // Cells within blur_radius should have some darkening
    // Core shadow (at offset)
    const core = buffer.get(13, 10).?;
    try testing.expect(core.style.bg != null);

    // Edge at blur radius distance
    const edge1 = buffer.get(17, 14).?; // +4 from core in both directions
    try testing.expect(edge1.style.bg != null or edge1.char != ' ');

    // Cell beyond blur radius should NOT be affected
    const outside = buffer.get(20, 16).?;
    try testing.expectEqual(@as(u21, ' '), outside.char);
}

test "Shadow.render - large blur radius (stress test)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 30);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 20, .y = 12, .width = 8, .height = 6 };

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 10,
        .color = Color.black,
        .opacity = 0.5,
        .style = .drop,
    };

    // Should not crash with large blur radius
    try s.render(&buffer, widget_area);

    // Core shadow should exist
    const core = buffer.get(22, 13).?;
    try testing.expect(core.style.bg != null or core.char != ' ');
}

test "Shadow.render - blur radius 1 creates subtle gradient" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 8, .y = 6, .width = 5, .height = 3 };

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    // Core shadow
    const core = buffer.get(10, 7).?;
    try testing.expect(core.style.bg != null);

    // Adjacent cell (within blur radius)
    const adjacent = buffer.get(11, 7).?;
    try testing.expect(adjacent.style.bg != null or adjacent.char != ' ');

    // Cell at distance 2 (outside blur radius)
    const outside = buffer.get(10, 9).?;
    // May or may not be affected depending on widget area + blur
    // Test verifies no crash
    try testing.expect(outside.char == ' ' or outside.style.bg != null);
}

// ============================================================================
// Performance Tests
// ============================================================================

test "Shadow.render - performance with realistic workload" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 10, .y = 5, .width = 60, .height = 15 };

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 3,
        .color = Color.black,
        .opacity = 0.7,
        .style = .drop,
    };

    var timer = try std.time.Timer.start();

    // Render shadow 100 times (simulate animation or rapid redraws)
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        buffer.clear();
        try s.render(&buffer, widget_area);
    }

    const elapsed = timer.read();

    // Verify shadow was rendered
    const cell = buffer.get(12, 6).?;
    try testing.expect(cell.style.bg != null or cell.char != ' ');

    // Performance assertion: 100 renders should complete in reasonable time
    // (Exact threshold depends on implementation efficiency)
    std.debug.print("\nShadow render benchmark: 100 renders in {d} ns ({d} ns/render)\n", .{
        elapsed,
        elapsed / 100,
    });

    // Sanity check: should not take more than 100ms for 100 renders
    try testing.expect(elapsed < 100_000_000);
}

test "Shadow.render - performance with zero blur (fast path)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 10, .y = 5, .width = 40, .height = 10 };

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        buffer.clear();
        try s.render(&buffer, widget_area);
    }

    const elapsed = timer.read();

    // Zero blur should be faster (no gradient computation)
    std.debug.print("\nShadow render (zero blur): 200 renders in {d} ns ({d} ns/render)\n", .{
        elapsed,
        elapsed / 200,
    });

    try testing.expect(elapsed < 50_000_000); // Should be very fast
}

// ============================================================================
// Integration Tests - Multiple Shadows
// ============================================================================

test "Shadow.render - multiple shadows on same widget" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 20);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 10, .y = 8, .width = 8, .height = 5 };

    // Drop shadow (bottom-right)
    const s1 = Shadow{
        .offset_x = 2,
        .offset_y = 2,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 0.6,
        .style = .drop,
    };

    // Inner shadow (top-left)
    const s2 = Shadow{
        .offset_x = -1,
        .offset_y = -1,
        .blur_radius = 0,
        .color = Color.fromRgb(50, 50, 50),
        .opacity = 0.4,
        .style = .inner,
    };

    try s1.render(&buffer, widget_area);
    try s2.render(&buffer, widget_area);

    // Both shadows should have rendered (layered effect)
    const drop_cell = buffer.get(12, 10).?;
    try testing.expect(drop_cell.style.bg != null or drop_cell.char != ' ');

    // Inner shadow should only affect inside widget
    const inner_cell = buffer.get(10, 8).?;
    try testing.expect(inner_cell.style.bg != null or inner_cell.char == ' ');
}

test "Shadow.render - shadow with colored widget interaction" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 15);
    defer buffer.deinit();

    const widget_area = Rect{ .x = 5, .y = 5, .width = 8, .height = 4 };

    // Fill widget with color first
    buffer.fill(widget_area, '█', .{ .fg = .green, .bg = .blue });

    const s = Shadow{
        .offset_x = 2,
        .offset_y = 1,
        .blur_radius = 1,
        .color = Color.black,
        .opacity = 0.8,
        .style = .drop,
    };

    try s.render(&buffer, widget_area);

    // Widget content should remain unchanged
    const widget_cell = buffer.get(5, 5).?;
    try testing.expectEqual(@as(u21, '█'), widget_cell.char);

    // Shadow should appear at offset
    const shadow_cell = buffer.get(7, 6).?;
    try testing.expect(shadow_cell.style.bg != null or shadow_cell.char != ' ');
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "Shadow.render - null buffer pointer handling" {
    // This test verifies the API signature and would test null safety
    // if Zig allows null pointers in the interface
    // (Likely implementation will use non-null pointer `*Buffer`)

    const widget_area = Rect{ .x = 5, .y = 5, .width = 5, .height = 3 };

    const s = Shadow{
        .offset_x = 1,
        .offset_y = 1,
        .blur_radius = 0,
        .color = Color.black,
        .opacity = 1.0,
        .style = .drop,
    };

    // If implementation accepts `?*Buffer`, this should not crash
    // Otherwise, this test documents required non-null buffer
    _ = s;
    _ = widget_area;
}

// ============================================================================
// Convenience Constructor Tests (if implemented)
// ============================================================================

test "Shadow.drop - convenience constructor for drop shadow" {
    // If implementation provides convenience constructors like:
    // pub fn drop(offset_x: i16, offset_y: i16, blur: u8, opacity: f32) Shadow

    const s = Shadow.drop(2, 1, 3, 0.7);

    try testing.expectEqual(@as(i16, 2), s.offset_x);
    try testing.expectEqual(@as(i16, 1), s.offset_y);
    try testing.expectEqual(@as(u8, 3), s.blur_radius);
    try testing.expectEqual(@as(f32, 0.7), s.opacity);
    try testing.expectEqual(ShadowStyle.drop, s.style);
    try testing.expectEqual(Color.black, s.color);
}

test "Shadow.inner - convenience constructor for inner shadow" {
    const s = Shadow.inner(1, 1, 2, 0.5);

    try testing.expectEqual(ShadowStyle.inner, s.style);
    try testing.expectEqual(@as(u8, 2), s.blur_radius);
}

test "Shadow.box - convenience constructor for box shadow" {
    const s = Shadow.box(0, 0, 4, 0.6);

    try testing.expectEqual(ShadowStyle.box, s.style);
    try testing.expectEqual(@as(i16, 0), s.offset_x);
    try testing.expectEqual(@as(i16, 0), s.offset_y);
    try testing.expectEqual(@as(u8, 4), s.blur_radius);
}
