//! Transition helpers for smooth UI effects
//!
//! Built on top of animation.zig primitives, this module provides high-level
//! transition types for common UI animation patterns:
//! - Fade transitions (opacity-based effects)
//! - Slide transitions (position-based movement)
//! - Expand/collapse transitions (size-based growth/shrink)
//!
//! All transitions follow the same lifecycle:
//! 1. init() or convenience constructor (fadeIn, slideIn, expand, etc.)
//! 2. begin(time_ms) — Start animation at timestamp
//! 3. update(time_ms)* — Get current value (called each frame)
//! 4. isComplete() — Check if animation finished
//! 5. reset() — Reset to initial state for replay

const std = @import("std");
const animation = @import("animation.zig");
const layout = @import("layout.zig");

pub const Animation = animation.Animation;
pub const EasingFn = animation.EasingFn;
pub const Rect = layout.Rect;

/// Slide direction
pub const Direction = enum {
    top,
    bottom,
    left,
    right,
};

/// Fade transition (opacity-based)
pub const FadeTransition = struct {
    anim: Animation,

    /// Create a fade transition with custom start/end opacity
    pub fn init(start: f32, end: f32, duration_ms: u64, easing: EasingFn) FadeTransition {
        return .{
            .anim = Animation.init(start, end, duration_ms, easing),
        };
    }

    /// Convenience: fade in from 0% to 100% opacity
    pub fn fadeIn(duration_ms: u64, easing: EasingFn) FadeTransition {
        return init(0.0, 1.0, duration_ms, easing);
    }

    /// Convenience: fade out from 100% to 0% opacity
    pub fn fadeOut(duration_ms: u64, easing: EasingFn) FadeTransition {
        return init(1.0, 0.0, duration_ms, easing);
    }

    /// Begin the fade animation at timestamp
    pub fn begin(self: *FadeTransition, time_ms: u64) void {
        self.anim.begin(time_ms);
    }

    /// Update and get current opacity (0.0-1.0)
    pub fn update(self: *FadeTransition, time_ms: u64) f32 {
        return self.anim.update(time_ms);
    }

    /// Check if animation is complete
    pub fn isComplete(self: FadeTransition) bool {
        return self.anim.isComplete();
    }

    /// Reset animation to initial state
    pub fn reset(self: *FadeTransition) void {
        self.anim.reset();
    }
};

/// Slide transition (position-based)
pub const SlideTransition = struct {
    anim_x: Animation,
    anim_y: Animation,
    anim_width: Animation,
    anim_height: Animation,

    /// Create a slide transition with custom start/end positions
    pub fn init(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) SlideTransition {
        return .{
            .anim_x = Animation.init(@floatFromInt(start_rect.x), @floatFromInt(end_rect.x), duration_ms, easing),
            .anim_y = Animation.init(@floatFromInt(start_rect.y), @floatFromInt(end_rect.y), duration_ms, easing),
            .anim_width = Animation.init(@floatFromInt(start_rect.width), @floatFromInt(end_rect.width), duration_ms, easing),
            .anim_height = Animation.init(@floatFromInt(start_rect.height), @floatFromInt(end_rect.height), duration_ms, easing),
        };
    }

    /// Convenience: slide in from specified direction
    pub fn slideIn(direction: Direction, start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) SlideTransition {
        _ = direction; // Direction is implicit in start_rect vs end_rect
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Convenience: slide out to specified direction
    pub fn slideOut(direction: Direction, start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) SlideTransition {
        _ = direction; // Direction is implicit in start_rect vs end_rect
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Begin the slide animation at timestamp
    pub fn begin(self: *SlideTransition, time_ms: u64) void {
        self.anim_x.begin(time_ms);
        self.anim_y.begin(time_ms);
        self.anim_width.begin(time_ms);
        self.anim_height.begin(time_ms);
    }

    /// Update and get current Rect position
    pub fn update(self: *SlideTransition, time_ms: u64) Rect {
        const x = self.anim_x.update(time_ms);
        const y = self.anim_y.update(time_ms);
        const width = self.anim_width.update(time_ms);
        const height = self.anim_height.update(time_ms);

        return Rect.new(
            @intFromFloat(x),
            @intFromFloat(y),
            @intFromFloat(width),
            @intFromFloat(height),
        );
    }

    /// Check if animation is complete
    pub fn isComplete(self: SlideTransition) bool {
        return self.anim_x.isComplete();
    }

    /// Reset animation to initial state
    pub fn reset(self: *SlideTransition) void {
        self.anim_x.reset();
        self.anim_y.reset();
        self.anim_width.reset();
        self.anim_height.reset();
    }
};

/// Expand/collapse transition (size-based)
pub const ExpandTransition = struct {
    anim_x: Animation,
    anim_y: Animation,
    anim_width: Animation,
    anim_height: Animation,

    /// Create an expand/collapse transition with custom start/end sizes
    pub fn init(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) ExpandTransition {
        return .{
            .anim_x = Animation.init(@floatFromInt(start_rect.x), @floatFromInt(end_rect.x), duration_ms, easing),
            .anim_y = Animation.init(@floatFromInt(start_rect.y), @floatFromInt(end_rect.y), duration_ms, easing),
            .anim_width = Animation.init(@floatFromInt(start_rect.width), @floatFromInt(end_rect.width), duration_ms, easing),
            .anim_height = Animation.init(@floatFromInt(start_rect.height), @floatFromInt(end_rect.height), duration_ms, easing),
        };
    }

    /// Convenience: expand from small to large (both dimensions)
    pub fn expand(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) ExpandTransition {
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Convenience: collapse from large to small (both dimensions)
    pub fn collapse(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) ExpandTransition {
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Convenience: expand width only
    pub fn expandWidth(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) ExpandTransition {
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Convenience: expand height only
    pub fn expandHeight(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) ExpandTransition {
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Convenience: collapse width only
    pub fn collapseWidth(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) ExpandTransition {
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Convenience: collapse height only
    pub fn collapseHeight(start_rect: Rect, end_rect: Rect, duration_ms: u64, easing: EasingFn) ExpandTransition {
        return init(start_rect, end_rect, duration_ms, easing);
    }

    /// Begin the expand/collapse animation at timestamp
    pub fn begin(self: *ExpandTransition, time_ms: u64) void {
        self.anim_x.begin(time_ms);
        self.anim_y.begin(time_ms);
        self.anim_width.begin(time_ms);
        self.anim_height.begin(time_ms);
    }

    /// Update and get current Rect size
    pub fn update(self: *ExpandTransition, time_ms: u64) Rect {
        const x = self.anim_x.update(time_ms);
        const y = self.anim_y.update(time_ms);
        const width = self.anim_width.update(time_ms);
        const height = self.anim_height.update(time_ms);

        return Rect.new(
            @intFromFloat(x),
            @intFromFloat(y),
            @intFromFloat(width),
            @intFromFloat(height),
        );
    }

    /// Check if animation is complete
    pub fn isComplete(self: ExpandTransition) bool {
        return self.anim_x.isComplete();
    }

    /// Reset animation to initial state
    pub fn reset(self: *ExpandTransition) void {
        self.anim_x.reset();
        self.anim_y.reset();
        self.anim_width.reset();
        self.anim_height.reset();
    }
};

// ============================================================================
// Tests
// ============================================================================

// ===== FadeTransition Tests =====

test "FadeTransition - fadeIn lifecycle" {
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    // Before begin
    try std.testing.expect(!fade.isComplete());

    // Begin at time 0
    fade.begin(0);
    try std.testing.expect(!fade.isComplete());

    // Start: t=0, opacity should be 0.0
    const val0 = fade.update(0);
    try std.testing.expectEqual(@as(f32, 0.0), val0);
    try std.testing.expect(!fade.isComplete());

    // Middle: t=0.5, opacity should be 0.5
    const val_mid = fade.update(500);
    try std.testing.expectEqual(@as(f32, 0.5), val_mid);
    try std.testing.expect(!fade.isComplete());

    // End: t=1.0, opacity should be 1.0
    const val_end = fade.update(1000);
    try std.testing.expectEqual(@as(f32, 1.0), val_end);
    try std.testing.expect(fade.isComplete());

    // After completion, should return end value
    const val_after = fade.update(1500);
    try std.testing.expectEqual(@as(f32, 1.0), val_after);
}

test "FadeTransition - fadeOut lifecycle" {
    var fade = FadeTransition.fadeOut(1000, animation.linear);

    fade.begin(0);

    // Start: t=0, opacity should be 1.0
    const val0 = fade.update(0);
    try std.testing.expectEqual(@as(f32, 1.0), val0);

    // Middle: t=0.5, opacity should be 0.5
    const val_mid = fade.update(500);
    try std.testing.expectEqual(@as(f32, 0.5), val_mid);

    // End: t=1.0, opacity should be 0.0
    const val_end = fade.update(1000);
    try std.testing.expectEqual(@as(f32, 0.0), val_end);
    try std.testing.expect(fade.isComplete());
}

test "FadeTransition - custom opacity range" {
    var fade = FadeTransition.init(0.2, 0.8, 1000, animation.linear);

    fade.begin(0);

    const val0 = fade.update(0);
    try std.testing.expectEqual(@as(f32, 0.2), val0);

    const val_mid = fade.update(500);
    try std.testing.expectEqual(@as(f32, 0.5), val_mid);

    const val_end = fade.update(1000);
    try std.testing.expectEqual(@as(f32, 0.8), val_end);
}

test "FadeTransition - zero duration completes immediately" {
    var fade = FadeTransition.fadeIn(0, animation.linear);

    fade.begin(0);
    try std.testing.expect(!fade.isComplete());

    const val = fade.update(0);
    try std.testing.expectEqual(@as(f32, 1.0), val);
    try std.testing.expect(fade.isComplete());
}

test "FadeTransition - reset restarts animation" {
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    fade.begin(0);
    _ = fade.update(1000);
    try std.testing.expect(fade.isComplete());

    // Reset should clear completion state
    fade.reset();
    try std.testing.expect(!fade.isComplete());

    // Should be able to restart from beginning
    fade.begin(2000);
    const val = fade.update(2500);
    try std.testing.expectEqual(@as(f32, 0.5), val);
}

test "FadeTransition - multiple begin calls restart animation" {
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    fade.begin(0);
    _ = fade.update(500); // Half-way

    // Restart animation at new time
    fade.begin(1000);
    const val = fade.update(1000);
    try std.testing.expectEqual(@as(f32, 0.0), val); // Should be at start again
}

test "FadeTransition - multiple reset calls are safe" {
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    fade.begin(0);
    _ = fade.update(1000);

    fade.reset();
    fade.reset(); // Should not cause issues
    try std.testing.expect(!fade.isComplete());
}

test "FadeTransition - isComplete before begin" {
    const fade = FadeTransition.fadeIn(1000, animation.linear);
    try std.testing.expect(!fade.isComplete());
}

test "FadeTransition - opacity boundaries at 0.0 and 1.0" {
    var fade = FadeTransition.init(0.0, 1.0, 1000, animation.linear);

    fade.begin(0);

    const val_start = fade.update(0);
    try std.testing.expectEqual(@as(f32, 0.0), val_start);

    const val_end = fade.update(1000);
    try std.testing.expectEqual(@as(f32, 1.0), val_end);
}

test "FadeTransition - inverted opacity range" {
    var fade = FadeTransition.init(1.0, 0.0, 1000, animation.linear);

    fade.begin(0);

    const val_start = fade.update(0);
    try std.testing.expectEqual(@as(f32, 1.0), val_start);

    const val_end = fade.update(1000);
    try std.testing.expectEqual(@as(f32, 0.0), val_end);
}

// ===== SlideTransition Tests =====

test "SlideTransition - slideIn lifecycle" {
    const start_rect = Rect.new(0, 0, 10, 10);
    const end_rect = Rect.new(50, 50, 10, 10);
    var slide = SlideTransition.slideIn(.right, start_rect, end_rect, 1000, animation.linear);

    slide.begin(0);
    try std.testing.expect(!slide.isComplete());

    // Start: should be at start_rect
    const rect0 = slide.update(0);
    try std.testing.expectEqual(@as(u16, 0), rect0.x);
    try std.testing.expectEqual(@as(u16, 0), rect0.y);

    // Middle: should be halfway
    const rect_mid = slide.update(500);
    try std.testing.expectEqual(@as(u16, 25), rect_mid.x);
    try std.testing.expectEqual(@as(u16, 25), rect_mid.y);

    // End: should be at end_rect
    const rect_end = slide.update(1000);
    try std.testing.expectEqual(@as(u16, 50), rect_end.x);
    try std.testing.expectEqual(@as(u16, 50), rect_end.y);
    try std.testing.expect(slide.isComplete());
}

test "SlideTransition - slideOut lifecycle" {
    const start_rect = Rect.new(50, 50, 10, 10);
    const end_rect = Rect.new(0, 0, 10, 10);
    var slide = SlideTransition.slideOut(.left, start_rect, end_rect, 1000, animation.linear);

    slide.begin(0);

    const rect0 = slide.update(0);
    try std.testing.expectEqual(@as(u16, 50), rect0.x);
    try std.testing.expectEqual(@as(u16, 50), rect0.y);

    const rect_end = slide.update(1000);
    try std.testing.expectEqual(@as(u16, 0), rect_end.x);
    try std.testing.expectEqual(@as(u16, 0), rect_end.y);
}

test "SlideTransition - multi-axis animation" {
    const start_rect = Rect.new(10, 20, 30, 40);
    const end_rect = Rect.new(100, 200, 50, 60);
    var slide = SlideTransition.init(start_rect, end_rect, 1000, animation.linear);

    slide.begin(0);

    const rect_mid = slide.update(500);
    try std.testing.expectEqual(@as(u16, 55), rect_mid.x); // (10+100)/2
    try std.testing.expectEqual(@as(u16, 110), rect_mid.y); // (20+200)/2
    try std.testing.expectEqual(@as(u16, 40), rect_mid.width); // (30+50)/2
    try std.testing.expectEqual(@as(u16, 50), rect_mid.height); // (40+60)/2
}

test "SlideTransition - zero duration completes immediately" {
    const start_rect = Rect.new(0, 0, 10, 10);
    const end_rect = Rect.new(50, 50, 10, 10);
    var slide = SlideTransition.init(start_rect, end_rect, 0, animation.linear);

    slide.begin(0);
    const rect = slide.update(0);
    try std.testing.expectEqual(@as(u16, 50), rect.x);
    try std.testing.expectEqual(@as(u16, 50), rect.y);
    try std.testing.expect(slide.isComplete());
}

test "SlideTransition - reset restarts animation" {
    const start_rect = Rect.new(0, 0, 10, 10);
    const end_rect = Rect.new(50, 50, 10, 10);
    var slide = SlideTransition.init(start_rect, end_rect, 1000, animation.linear);

    slide.begin(0);
    _ = slide.update(1000);
    try std.testing.expect(slide.isComplete());

    slide.reset();
    try std.testing.expect(!slide.isComplete());

    slide.begin(2000);
    const rect = slide.update(2500);
    try std.testing.expectEqual(@as(u16, 25), rect.x); // Half-way
}

test "SlideTransition - zero-sized rect" {
    const start_rect = Rect.new(10, 10, 0, 0);
    const end_rect = Rect.new(50, 50, 0, 0);
    var slide = SlideTransition.init(start_rect, end_rect, 1000, animation.linear);

    slide.begin(0);
    const rect = slide.update(500);
    try std.testing.expectEqual(@as(u16, 30), rect.x);
    try std.testing.expectEqual(@as(u16, 30), rect.y);
    try std.testing.expectEqual(@as(u16, 0), rect.width);
    try std.testing.expectEqual(@as(u16, 0), rect.height);
}

test "SlideTransition - large coordinates" {
    const start_rect = Rect.new(0, 0, 10, 10);
    const end_rect = Rect.new(10000, 10000, 10, 10);
    var slide = SlideTransition.init(start_rect, end_rect, 1000, animation.linear);

    slide.begin(0);
    const rect_mid = slide.update(500);
    try std.testing.expectEqual(@as(u16, 5000), rect_mid.x);
    try std.testing.expectEqual(@as(u16, 5000), rect_mid.y);
}

test "SlideTransition - multiple begin calls restart" {
    const start_rect = Rect.new(0, 0, 10, 10);
    const end_rect = Rect.new(50, 50, 10, 10);
    var slide = SlideTransition.init(start_rect, end_rect, 1000, animation.linear);

    slide.begin(0);
    _ = slide.update(500);

    slide.begin(1000);
    const rect = slide.update(1000);
    try std.testing.expectEqual(@as(u16, 0), rect.x); // Should restart from beginning
}

test "SlideTransition - isComplete before begin" {
    const start_rect = Rect.new(0, 0, 10, 10);
    const end_rect = Rect.new(50, 50, 10, 10);
    const slide = SlideTransition.init(start_rect, end_rect, 1000, animation.linear);
    try std.testing.expect(!slide.isComplete());
}

// ===== ExpandTransition Tests =====

test "ExpandTransition - expand lifecycle" {
    const start_rect = Rect.new(50, 50, 10, 10);
    const end_rect = Rect.new(50, 50, 100, 100);
    var expand_anim = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);
    try std.testing.expect(!expand_anim.isComplete());

    // Start: should be at start_rect
    const rect0 = expand_anim.update(0);
    try std.testing.expectEqual(@as(u16, 10), rect0.width);
    try std.testing.expectEqual(@as(u16, 10), rect0.height);

    // Middle: should be halfway expanded
    const rect_mid = expand_anim.update(500);
    try std.testing.expectEqual(@as(u16, 55), rect_mid.width);
    try std.testing.expectEqual(@as(u16, 55), rect_mid.height);

    // End: should be at end_rect
    const rect_end = expand_anim.update(1000);
    try std.testing.expectEqual(@as(u16, 100), rect_end.width);
    try std.testing.expectEqual(@as(u16, 100), rect_end.height);
    try std.testing.expect(expand_anim.isComplete());
}

test "ExpandTransition - collapse lifecycle" {
    const start_rect = Rect.new(50, 50, 100, 100);
    const end_rect = Rect.new(50, 50, 10, 10);
    var collapse_anim = ExpandTransition.collapse(start_rect, end_rect, 1000, animation.linear);

    collapse_anim.begin(0);

    const rect0 = collapse_anim.update(0);
    try std.testing.expectEqual(@as(u16, 100), rect0.width);
    try std.testing.expectEqual(@as(u16, 100), rect0.height);

    const rect_end = collapse_anim.update(1000);
    try std.testing.expectEqual(@as(u16, 10), rect_end.width);
    try std.testing.expectEqual(@as(u16, 10), rect_end.height);
}

test "ExpandTransition - expandWidth only" {
    const start_rect = Rect.new(50, 50, 10, 50);
    const end_rect = Rect.new(50, 50, 100, 50);
    var expand_anim = ExpandTransition.expandWidth(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);

    const rect_mid = expand_anim.update(500);
    try std.testing.expectEqual(@as(u16, 55), rect_mid.width); // Width expands
    try std.testing.expectEqual(@as(u16, 50), rect_mid.height); // Height stays same
}

test "ExpandTransition - expandHeight only" {
    const start_rect = Rect.new(50, 50, 50, 10);
    const end_rect = Rect.new(50, 50, 50, 100);
    var expand_anim = ExpandTransition.expandHeight(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);

    const rect_mid = expand_anim.update(500);
    try std.testing.expectEqual(@as(u16, 50), rect_mid.width); // Width stays same
    try std.testing.expectEqual(@as(u16, 55), rect_mid.height); // Height expands
}

test "ExpandTransition - collapseWidth only" {
    const start_rect = Rect.new(50, 50, 100, 50);
    const end_rect = Rect.new(50, 50, 10, 50);
    var collapse_anim = ExpandTransition.collapseWidth(start_rect, end_rect, 1000, animation.linear);

    collapse_anim.begin(0);

    const rect_mid = collapse_anim.update(500);
    try std.testing.expectEqual(@as(u16, 55), rect_mid.width); // Width collapses
    try std.testing.expectEqual(@as(u16, 50), rect_mid.height); // Height stays same
}

test "ExpandTransition - collapseHeight only" {
    const start_rect = Rect.new(50, 50, 50, 100);
    const end_rect = Rect.new(50, 50, 50, 10);
    var collapse_anim = ExpandTransition.collapseHeight(start_rect, end_rect, 1000, animation.linear);

    collapse_anim.begin(0);

    const rect_mid = collapse_anim.update(500);
    try std.testing.expectEqual(@as(u16, 50), rect_mid.width); // Width stays same
    try std.testing.expectEqual(@as(u16, 55), rect_mid.height); // Height collapses
}

test "ExpandTransition - zero duration completes immediately" {
    const start_rect = Rect.new(50, 50, 10, 10);
    const end_rect = Rect.new(50, 50, 100, 100);
    var expand_anim = ExpandTransition.expand(start_rect, end_rect, 0, animation.linear);

    expand_anim.begin(0);
    const rect = expand_anim.update(0);
    try std.testing.expectEqual(@as(u16, 100), rect.width);
    try std.testing.expectEqual(@as(u16, 100), rect.height);
    try std.testing.expect(expand_anim.isComplete());
}

test "ExpandTransition - reset restarts animation" {
    const start_rect = Rect.new(50, 50, 10, 10);
    const end_rect = Rect.new(50, 50, 100, 100);
    var expand_anim = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);
    _ = expand_anim.update(1000);
    try std.testing.expect(expand_anim.isComplete());

    expand_anim.reset();
    try std.testing.expect(!expand_anim.isComplete());

    expand_anim.begin(2000);
    const rect = expand_anim.update(2500);
    try std.testing.expectEqual(@as(u16, 55), rect.width); // Half-way
}

test "ExpandTransition - zero-sized start rect" {
    const start_rect = Rect.new(50, 50, 0, 0);
    const end_rect = Rect.new(50, 50, 100, 100);
    var expand_anim = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);

    const rect0 = expand_anim.update(0);
    try std.testing.expectEqual(@as(u16, 0), rect0.width);
    try std.testing.expectEqual(@as(u16, 0), rect0.height);

    const rect_mid = expand_anim.update(500);
    try std.testing.expectEqual(@as(u16, 50), rect_mid.width);
    try std.testing.expectEqual(@as(u16, 50), rect_mid.height);
}

test "ExpandTransition - large dimensions" {
    const start_rect = Rect.new(0, 0, 1000, 1000);
    const end_rect = Rect.new(0, 0, 10000, 10000);
    var expand_anim = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);
    const rect_mid = expand_anim.update(500);
    try std.testing.expectEqual(@as(u16, 5500), rect_mid.width);
    try std.testing.expectEqual(@as(u16, 5500), rect_mid.height);
}

test "ExpandTransition - multiple begin calls restart" {
    const start_rect = Rect.new(50, 50, 10, 10);
    const end_rect = Rect.new(50, 50, 100, 100);
    var expand_anim = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);
    _ = expand_anim.update(500);

    expand_anim.begin(1000);
    const rect = expand_anim.update(1000);
    try std.testing.expectEqual(@as(u16, 10), rect.width); // Should restart from beginning
}

test "ExpandTransition - isComplete before begin" {
    const start_rect = Rect.new(50, 50, 10, 10);
    const end_rect = Rect.new(50, 50, 100, 100);
    const expand_anim = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);
    try std.testing.expect(!expand_anim.isComplete());
}

test "ExpandTransition - position changes with size" {
    const start_rect = Rect.new(10, 20, 30, 40);
    const end_rect = Rect.new(100, 200, 50, 60);
    var expand_anim = ExpandTransition.init(start_rect, end_rect, 1000, animation.linear);

    expand_anim.begin(0);

    const rect_mid = expand_anim.update(500);
    try std.testing.expectEqual(@as(u16, 55), rect_mid.x); // Position animates too
    try std.testing.expectEqual(@as(u16, 110), rect_mid.y);
    try std.testing.expectEqual(@as(u16, 40), rect_mid.width);
    try std.testing.expectEqual(@as(u16, 50), rect_mid.height);
}
