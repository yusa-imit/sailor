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
