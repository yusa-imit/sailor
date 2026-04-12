//! Virtual widget rendering — skip off-screen widgets for performance
//!
//! The VirtualRenderer optimizes TUI rendering by determining which widgets
//! are visible in the current viewport. Widgets completely outside the viewport
//! can be skipped, reducing CPU usage in applications with many widgets or
//! scrollable content.
//!
//! ## Example Usage
//!
//! ```zig
//! const viewport = Viewport.init(0, 0, 80, 24); // Full terminal size
//! const renderer = VirtualRenderer.init(viewport);
//!
//! // In your render loop:
//! for (widgets) |widget| {
//!     const widget_area = Rect{ .x = widget.x, .y = widget.y, .width = widget.width, .height = widget.height };
//!
//!     if (!renderer.shouldRender(widget_area)) {
//!         continue; // Skip rendering this widget — it's off-screen
//!     }
//!
//!     // Optionally get the clipped area to render only visible portion
//!     if (renderer.getClippedArea(widget_area)) |clipped| {
//!         widget.render(buffer, clipped);
//!     }
//! }
//! ```
//!
//! ## Performance Impact
//!
//! In a typical scenario with 100 widgets spread across a 200x100 virtual space
//! but only a 80x24 terminal viewport:
//! - Without VirtualRenderer: 100 widgets rendered
//! - With VirtualRenderer: ~10 widgets rendered (90% skip rate)
//!
//! This optimization is especially valuable for:
//! - Scrollable lists with hundreds of items
//! - Grid layouts with many cells
//! - Dashboard applications with numerous widgets
//! - Split panes where most widgets are in non-visible panes

const viewport_mod = @import("viewport.zig");
const Viewport = viewport_mod.Viewport;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;

/// Virtual renderer optimizes rendering by skipping widgets whose area
/// is completely outside the viewport bounds
pub const VirtualRenderer = struct {
    viewport: Viewport,

    /// Initialize virtual renderer with viewport bounds
    ///
    /// The viewport defines the visible region of the screen. Widgets outside
    /// this region will be skipped during rendering.
    ///
    /// Example:
    /// ```zig
    /// const vp = Viewport.init(0, 0, 80, 24); // Full terminal
    /// const renderer = VirtualRenderer.init(vp);
    /// ```
    pub fn init(viewport: Viewport) VirtualRenderer {
        return .{ .viewport = viewport };
    }

    /// Determine if a widget area should be rendered
    ///
    /// Returns true if the area intersects or is inside viewport bounds.
    /// Returns false if the area is completely outside the viewport, meaning
    /// the widget can be safely skipped without visual impact.
    ///
    /// Zero-size areas (width or height == 0) always return false, as they
    /// have no visible content to render.
    ///
    /// This method uses the viewport's intersection test which is highly
    /// optimized for quick rejection of off-screen widgets.
    ///
    /// Example:
    /// ```zig
    /// const area = Rect{ .x = 100, .y = 50, .width = 20, .height = 10 };
    /// if (renderer.shouldRender(area)) {
    ///     widget.render(buffer, area);
    /// }
    /// ```
    pub fn shouldRender(self: VirtualRenderer, area: Rect) bool {
        // Zero-size areas have no visible content
        if (area.width == 0 or area.height == 0) {
            return false;
        }
        return self.viewport.intersects(area);
    }

    /// Get the intersection area to render (clipped to viewport)
    ///
    /// Returns the portion of the area that overlaps with the viewport,
    /// or null if the area is completely outside the viewport.
    ///
    /// Use this method when you need to render only the visible portion
    /// of a widget, which is useful for:
    /// - Large widgets that extend beyond the viewport
    /// - Precise cell-level clipping
    /// - Memory-efficient rendering
    ///
    /// Example:
    /// ```zig
    /// if (renderer.getClippedArea(widget_area)) |clipped| {
    ///     widget.render(buffer, clipped); // Render only visible portion
    /// } else {
    ///     // Widget is off-screen, skip entirely
    /// }
    /// ```
    pub fn getClippedArea(self: VirtualRenderer, area: Rect) ?Rect {
        const clipped = self.viewport.clipRect(area);
        // clipRect returns zero-size rect for no intersection
        if (clipped.width == 0 or clipped.height == 0) {
            return null;
        }
        return clipped;
    }
};

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "VirtualRenderer.init creates renderer with viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    try testing.expectEqual(@as(u16, 0), renderer.viewport.x);
    try testing.expectEqual(@as(u16, 0), renderer.viewport.y);
    try testing.expectEqual(@as(u16, 80), renderer.viewport.width);
    try testing.expectEqual(@as(u16, 24), renderer.viewport.height);
}

test "VirtualRenderer.shouldRender returns true for area inside viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect{ .x = 10, .y = 5, .width = 20, .height = 10 };
    try testing.expect(renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns false for area completely left of viewport" {
    const vp = Viewport.init(50, 0, 30, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect{ .x = 0, .y = 5, .width = 40, .height = 10 }; // x: 0-40, viewport starts at x: 50
    try testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.shouldRender returns false for zero-size area" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect{ .x = 10, .y = 10, .width = 0, .height = 0 };
    try testing.expect(!renderer.shouldRender(area));
}

test "VirtualRenderer.getClippedArea returns full area when inside viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect{ .x = 10, .y = 5, .width = 20, .height = 10 };
    const clipped = renderer.getClippedArea(area);

    try testing.expect(clipped != null);
    try testing.expectEqual(@as(u16, 10), clipped.?.x);
    try testing.expectEqual(@as(u16, 5), clipped.?.y);
    try testing.expectEqual(@as(u16, 20), clipped.?.width);
    try testing.expectEqual(@as(u16, 10), clipped.?.height);
}

test "VirtualRenderer.getClippedArea returns null for area completely outside" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect{ .x = 100, .y = 50, .width = 20, .height = 10 }; // Far outside viewport
    const clipped = renderer.getClippedArea(area);

    try testing.expect(clipped == null);
}

test "VirtualRenderer.getClippedArea clips area extending beyond viewport" {
    const vp = Viewport.init(0, 0, 80, 24);
    const renderer = VirtualRenderer.init(vp);

    const area = Rect{ .x = 70, .y = 10, .width = 20, .height = 10 }; // Extends beyond x: 80
    const clipped = renderer.getClippedArea(area);

    try testing.expect(clipped != null);
    try testing.expectEqual(@as(u16, 70), clipped.?.x);
    try testing.expectEqual(@as(u16, 10), clipped.?.width); // Clipped from 20 to 10
}
