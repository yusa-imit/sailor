const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.Buffer;
const Cell = sailor.Cell;
const Rect = sailor.Rect;
const Viewport = sailor.Viewport;
const Style = sailor.Style;

/// Virtual renderer optimizes rendering by skipping widgets whose area
/// is completely outside the viewport bounds
pub const VirtualRenderer = struct {
    viewport: Viewport,

    /// Initialize virtual renderer with viewport bounds
    pub fn init(viewport: Viewport) VirtualRenderer {
        return .{ .viewport = viewport };
    }

    /// Determine if a widget area should be rendered
    /// Returns true if area intersects or is inside viewport bounds
    /// Returns false if area is completely outside viewport
    pub fn shouldRender(self: VirtualRenderer, area: Rect) bool {
        return self.viewport.intersects(area);
    }

    /// Get the intersection area to render (clipped to viewport)
    /// Returns null if area is completely outside viewport
    pub fn getClippedArea(self: VirtualRenderer, area: Rect) ?Rect {
        return self.viewport.clipRect(area);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "VirtualRenderer.init creates renderer with viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    try std.testing.expectEqual(@as(u16, 0), renderer.viewport.x);
    try std.testing.expectEqual(@as(u16, 0), renderer.viewport.y);
    try std.testing.expectEqual(@as(u16, 80), renderer.viewport.width);
    try std.testing.expectEqual(@as(u16, 24), renderer.viewport.height);
}

test "VirtualRenderer.shouldRender returns true for area inside viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 5, 20, 10);
    try std.testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns true for area at viewport start" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(0, 0, 20, 10);
    try std.testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns true for area at viewport end" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(60, 14, 20, 10);
    try std.testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns false for area completely left of viewport" {
    const vp = Viewport.init(50, 0, 30, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(0, 5, 40, 10);
    try std.testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns false for area completely right of viewport" {
    const vp = Viewport.init(0, 0, 30, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(50, 5, 40, 10);
    try std.testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns false for area completely above viewport" {
    const vp = Viewport.init(0, 50, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 0, 20, 40);
    try std.testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns false for area completely below viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 50, 20, 10);
    try std.testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns true for area partially overlapping left" {
    const vp = Viewport.init(10, 0, 30, 24);
    const renderer = VirtualRenderer.init(vp);

    // Area from 0 to 25, viewport from 10 to 40 → overlap
    const area = Rect.new(0, 5, 25, 10);
    try std.testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns true for area partially overlapping right" {
    const vp = Viewport.init(0, 0, 30, 24);
    const renderer = VirtualRenderer.init(vp);

    // Area from 20 to 50, viewport from 0 to 30 → overlap
    const area = Rect.new(20, 5, 30, 10);
    try std.testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns true for area partially overlapping top" {
    const vp = Viewport.init(0, 10, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    // Area from 0 to 25, viewport from 10 to 34 → overlap
    const area = Rect.new(10, 0, 20, 25);
    try std.testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns true for area partially overlapping bottom" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    // Area from 20 to 40, viewport from 0 to 24 → overlap
    const area = Rect.new(10, 20, 20, 20);
    try std.testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender with zero-size area returns false" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 10, 0, 0);
    try std.testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender with zero-width area returns false" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 10, 0, 10);
    try std.testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender with zero-height area returns false" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 10, 10, 0);
    try std.testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.getClippedArea returns full area when inside viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 5, 20, 10);
    const clipped = renderer.getClippedArea(area);

    try std.testing.expect(clipped != null);
    try std.testing.expectEqual(@as(u16, 10), clipped.?.x);
    try std.testing.expectEqual(@as(u16, 5), clipped.?.y);
    try std.testing.expectEqual(@as(u16, 20), clipped.?.width);
    try std.testing.expectEqual(@as(u16, 10), clipped.?.height);
}

test "VirtualRenderer.getClippedArea clips partially overlapping area left" {
    const vp = Viewport.init(10, 0, 30, 24);
    const renderer = VirtualRenderer.init(vp);

    // Area from x=0 to x=25, viewport from x=10 to x=40
    // Clipped should be from x=10 to x=25
    const area = Rect.new(0, 5, 25, 10);
    const clipped = renderer.getClippedArea(area);

    try std.testing.expect(clipped != null);
    try std.testing.expectEqual(@as(u16, 10), clipped.?.x);
    try std.testing.expectEqual(@as(u16, 5), clipped.?.y);
    try std.testing.expectEqual(@as(u16, 15), clipped.?.width); // 25 - 10
    try std.testing.expectEqual(@as(u16, 10), clipped.?.height);
}

test "VirtualRenderer.getClippedArea clips partially overlapping area right" {
    const vp = Viewport.init(0, 0, 30, 24);
    const renderer = VirtualRenderer.init(vp);

    // Area from x=20 to x=50, viewport from x=0 to x=30
    // Clipped should be from x=20 to x=30
    const area = Rect.new(20, 5, 30, 10);
    const clipped = renderer.getClippedArea(area);

    try std.testing.expect(clipped != null);
    try std.testing.expectEqual(@as(u16, 20), clipped.?.x);
    try std.testing.expectEqual(@as(u16, 5), clipped.?.y);
    try std.testing.expectEqual(@as(u16, 10), clipped.?.width); // 30 - 20
    try std.testing.expectEqual(@as(u16, 10), clipped.?.height);
}

test "VirtualRenderer.getClippedArea returns null for completely outside area" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(100, 100, 20, 10);
    const clipped = renderer.getClippedArea(area);

    try std.testing.expectEqual(null, clipped);
}

test "VirtualRenderer.getClippedArea returns null for zero-size area" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(10, 10, 0, 0);
    const clipped = renderer.getClippedArea(area);

    try std.testing.expectEqual(null, clipped);
}

test "VirtualRenderer integration: full viewport render with multiple widgets" {
    const allocator = std.testing.allocator;

    // Setup: 80x24 terminal viewport
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    // Create large buffer
    var buffer = try Buffer.init(allocator, 200, 100);
    defer buffer.deinit();

    // Simulate 4 widgets:
    // Widget 1: (10, 5, 20, 10) - visible
    const w1 = Rect.new(10, 5, 20, 10);
    if (renderer.shouldRender(w1)) {
        if (renderer.getClippedArea(w1)) |clipped| {
            buffer.fill(clipped, 'W', .{ .fg = .red });
        }
    }

    // Widget 2: (200, 50, 20, 10) - outside
    const w2 = Rect.new(200, 50, 20, 10);
    if (renderer.shouldRender(w2)) {
        if (renderer.getClippedArea(w2)) |clipped| {
            buffer.fill(clipped, 'X', .{ .fg = .green });
        }
    }

    // Widget 3: (60, 15, 30, 10) - visible
    const w3 = Rect.new(60, 15, 30, 10);
    if (renderer.shouldRender(w3)) {
        if (renderer.getClippedArea(w3)) |clipped| {
            buffer.fill(clipped, 'Y', .{ .fg = .blue });
        }
    }

    // Widget 4: (5, 200, 20, 10) - outside
    const w4 = Rect.new(5, 200, 20, 10);
    if (renderer.shouldRender(w4)) {
        if (renderer.getClippedArea(w4)) |clipped| {
            buffer.fill(clipped, 'Z', .{ .fg = .yellow });
        }
    }

    // Verify only visible widgets were rendered
    try std.testing.expectEqual(@as(u21, 'W'), buffer.getChar(10, 5));
    try std.testing.expectEqual(@as(u21, 'Y'), buffer.getChar(60, 15));

    // Verify invisible widgets were skipped
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(200, 50));
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(5, 200));
}

test "VirtualRenderer performance: skip rendering off-screen widgets" {
    const allocator = std.testing.allocator;

    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    // Count how many widgets would be skipped
    var skipped: u32 = 0;
    var rendered: u32 = 0;

    // Simulate 100 widgets scattered around
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const x = @as(u16, @intCast((i % 20) * 20));
        const y = @as(u16, @intCast((i / 20) * 20));
        const area = Rect.new(x, y, 15, 15);

        if (renderer.shouldRender(area)) {
            rendered += 1;
        } else {
            skipped += 1;
        }
    }

    // Most widgets (off-screen) should be skipped
    // Grid is 20x20 cells per widget, viewport is 80x24
    // Should have roughly (80/20) * (24/20) = 4 * 1 = 4-5 visible widgets max
    try std.testing.expect(skipped > rendered);
    try std.testing.expect(rendered > 0);
}

test "VirtualRenderer with offset viewport" {
    const vp = Viewport.init(50, 40, 40, 30);
    const renderer = VirtualRenderer.init(vp);

    // Widget inside offset viewport
    const inside = Rect.new(60, 50, 15, 10);
    try std.testing.expect(renderer.shouldRender(inside));

    // Widget before viewport
    const before = Rect.new(40, 50, 8, 10);
    try std.testing.expect(!renderer.shouldRender(before));

    // Widget after viewport
    const after = Rect.new(92, 50, 8, 10);
    try std.testing.expect(!renderer.shouldRender(after));
}

test "VirtualRenderer clipping with offset viewport" {
    const vp = Viewport.init(20, 15, 60, 40);
    const renderer = VirtualRenderer.init(vp);

    // Area partially outside right edge
    const area = Rect.new(70, 20, 20, 15);
    const clipped = renderer.getClippedArea(area);

    try std.testing.expect(clipped != null);
    // Viewport right edge is at 20 + 60 = 80
    // Area is from 70 to 90, so clipped to 70-80
    try std.testing.expectEqual(@as(u16, 70), clipped.?.x);
    try std.testing.expectEqual(@as(u16, 20), clipped.?.y);
    try std.testing.expectEqual(@as(u16, 10), clipped.?.width); // 80 - 70
    try std.testing.expectEqual(@as(u16, 15), clipped.?.height);
}

test "VirtualRenderer all edges clipped together" {
    const vp = Viewport.init(10, 10, 60, 40);
    const renderer = VirtualRenderer.init(vp);

    // Large area partially overlapping all edges
    const area = Rect.new(0, 0, 100, 100);
    const clipped = renderer.getClippedArea(area);

    try std.testing.expect(clipped != null);
    // Should be clipped to viewport bounds
    try std.testing.expectEqual(@as(u16, 10), clipped.?.x);
    try std.testing.expectEqual(@as(u16, 10), clipped.?.y);
    try std.testing.expectEqual(@as(u16, 60), clipped.?.width);
    try std.testing.expectEqual(@as(u16, 40), clipped.?.height);
}

test "VirtualRenderer render decision matches clipping result" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    // Test 10 random areas
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const x = @as(u16, @intCast((i * 7) % 150));
        const y = @as(u16, @intCast((i * 11) % 100));
        const w = @as(u16, @intCast((i + 1) * 5));
        const h = @as(u16, @intCast((i + 1) * 3));
        const area = Rect.new(x, y, w, h);

        const should_render = renderer.shouldRender(area);
        const clipped = renderer.getClippedArea(area);

        // If shouldRender is true, clipping should produce a non-null result
        if (should_render) {
            try std.testing.expect(clipped != null);
        } else {
            try std.testing.expect(clipped == null);
        }
    }
}

test "VirtualRenderer memory safety: no leaks with multiple renderers" {
    const allocator = std.testing.allocator;

    var renderers = try allocator.alloc(VirtualRenderer, 10);
    defer allocator.free(renderers);

    // Create 10 renderers with different viewports
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        renderers[i] = VirtualRenderer.init(
            Viewport.init(@as(u16, @intCast(i * 10)), @as(u16, @intCast(i * 5)), 80, 24),
        );
    }

    // Verify all were created with correct state
    try std.testing.expectEqual(@as(u16, 0), renderers[0].viewport.x);
    try std.testing.expectEqual(@as(u16, 90), renderers[9].viewport.x);

    // All should render areas in their respective viewports
    var count: u32 = 0;
    for (renderers) |renderer| {
        const area = Rect.new(renderer.viewport.x + 10, renderer.viewport.y + 5, 20, 10);
        if (renderer.shouldRender(area)) {
            count += 1;
        }
    }

    try std.testing.expectEqual(@as(u32, 10), count);
}

test "VirtualRenderer edge case: single-cell viewport" {
    const vp = Viewport.init(5, 5, 1, 1);
    const renderer = VirtualRenderer.init(vp);

    // Exactly at viewport
    try std.testing.expect(renderer.shouldRender(Rect.new(5, 5, 1, 1)));

    // Adjacent to viewport
    try std.testing.expect(!renderer.shouldRender(Rect.new(4, 5, 1, 1)));
    try std.testing.expect(!renderer.shouldRender(Rect.new(6, 5, 1, 1)));
    try std.testing.expect(!renderer.shouldRender(Rect.new(5, 4, 1, 1)));
    try std.testing.expect(!renderer.shouldRender(Rect.new(5, 6, 1, 1)));
}

test "VirtualRenderer edge case: very large viewport" {
    const vp = Viewport.init(0, 0, 65535, 65535);
    const renderer = VirtualRenderer.init(vp);

    // Everything should render
    try std.testing.expect(renderer.shouldRender(Rect.new(0, 0, 100, 100)));
    try std.testing.expect(renderer.shouldRender(Rect.new(60000, 60000, 100, 100)));
    try std.testing.expect(renderer.shouldRender(Rect.new(65400, 65400, 100, 100)));
}

test "VirtualRenderer decision consistency: same area yields same result" {
    const vp = Viewport.init(10, 10, 50, 50);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect.new(20, 20, 15, 15);

    // Call shouldRender multiple times
    const first = renderer.shouldRender(area);
    const second = renderer.shouldRender(area);
    const third = renderer.shouldRender(area);

    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(second, third);

    // Same with clipping
    const clip1 = renderer.getClippedArea(area);
    const clip2 = renderer.getClippedArea(area);

    if (clip1 == null) {
        try std.testing.expectEqual(null, clip2);
    } else {
        try std.testing.expect(clip2 != null);
        try std.testing.expectEqual(clip1.?.x, clip2.?.x);
        try std.testing.expectEqual(clip1.?.y, clip2.?.y);
        try std.testing.expectEqual(clip1.?.width, clip2.?.width);
        try std.testing.expectEqual(clip1.?.height, clip2.?.height);
    }
}
