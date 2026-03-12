const std = @import("std");
const layout = @import("layout.zig");
const buffer = @import("buffer.zig");
const style = @import("style.zig");
const animation = @import("animation.zig");

const Rect = layout.Rect;
const Buffer = buffer.Buffer;
const Style = style.Style;
const Animation = animation.Animation;
const EasingFn = animation.EasingFn;

/// Transition type for widget animations
pub const TransitionType = enum {
    /// Fade in/out (alpha blending simulation via color dimming)
    fade,
    /// Slide from/to direction
    slide,
    /// Grow/shrink from center
    scale,
};

/// Direction for slide transitions
pub const SlideDirection = enum {
    left,
    right,
    up,
    down,
};

/// Widget transition state
pub const Transition = struct {
    /// Type of transition
    type: TransitionType,
    /// Animation controller
    anim: Animation,
    /// Slide direction (for slide transitions)
    slide_dir: ?SlideDirection = null,
    /// Original rect (for restoring)
    original_rect: Rect,

    /// Create a fade transition
    pub fn fade(duration_ms: u64, easing: EasingFn) Transition {
        return .{
            .type = .fade,
            .anim = Animation.init(0.0, 1.0, duration_ms, easing),
            .original_rect = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
        };
    }

    /// Create a slide transition
    pub fn slide(duration_ms: u64, direction: SlideDirection, easing: EasingFn) Transition {
        return .{
            .type = .slide,
            .anim = Animation.init(0.0, 1.0, duration_ms, easing),
            .slide_dir = direction,
            .original_rect = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
        };
    }

    /// Create a scale (grow/shrink) transition
    pub fn scale(duration_ms: u64, easing: EasingFn) Transition {
        return .{
            .type = .scale,
            .anim = Animation.init(0.0, 1.0, duration_ms, easing),
            .original_rect = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
        };
    }

    /// Begin the transition
    pub fn begin(self: *Transition, current_time_ms: u64, rect: Rect) void {
        self.original_rect = rect;
        self.anim.begin(current_time_ms);
    }

    /// Update transition and return current rect for rendering
    pub fn update(self: *Transition, current_time_ms: u64) Rect {
        const t = self.anim.update(current_time_ms);
        return self.computeRect(t);
    }

    /// Get alpha value for fade transition (0.0 = invisible, 1.0 = opaque)
    pub fn getAlpha(self: *Transition) f32 {
        if (self.type != .fade) return 1.0;
        return self.anim.update(0); // Get current value without updating time
    }

    /// Check if transition is complete
    pub fn isComplete(self: Transition) bool {
        return self.anim.isComplete();
    }

    /// Reset transition
    pub fn reset(self: *Transition) void {
        self.anim.reset();
    }

    /// Compute current rect based on transition type and progress
    fn computeRect(self: Transition, t: f32) Rect {
        const rect = self.original_rect;

        switch (self.type) {
            .fade => {
                // Fade doesn't change rect, only alpha (handled by getAlpha)
                return rect;
            },
            .slide => {
                const dir = self.slide_dir orelse .right;
                const progress_u16: u16 = @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(rect.width)), @as(f32, @floatFromInt(rect.width)) * t)));

                switch (dir) {
                    .left => {
                        // Slide from right to left
                        const offset = rect.width -| progress_u16;
                        return Rect{
                            .x = rect.x +| offset,
                            .y = rect.y,
                            .width = progress_u16,
                            .height = rect.height,
                        };
                    },
                    .right => {
                        // Slide from left to right
                        return Rect{
                            .x = rect.x,
                            .y = rect.y,
                            .width = progress_u16,
                            .height = rect.height,
                        };
                    },
                    .up => {
                        // Slide from bottom to top
                        const offset = rect.height -| @as(u16, @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(rect.height)), @as(f32, @floatFromInt(rect.height)) * t))));
                        return Rect{
                            .x = rect.x,
                            .y = rect.y +| offset,
                            .width = rect.width,
                            .height = @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(rect.height)), @as(f32, @floatFromInt(rect.height)) * t))),
                        };
                    },
                    .down => {
                        // Slide from top to bottom
                        return Rect{
                            .x = rect.x,
                            .y = rect.y,
                            .width = rect.width,
                            .height = @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(rect.height)), @as(f32, @floatFromInt(rect.height)) * t))),
                        };
                    },
                }
            },
            .scale => {
                // Grow/shrink from center
                const scale_w = @as(f32, @floatFromInt(rect.width)) * t;
                const scale_h = @as(f32, @floatFromInt(rect.height)) * t;
                const new_w: u16 = @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(rect.width)), scale_w)));
                const new_h: u16 = @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(rect.height)), scale_h)));

                const offset_x = (rect.width -| new_w) / 2;
                const offset_y = (rect.height -| new_h) / 2;

                return Rect{
                    .x = rect.x +| offset_x,
                    .y = rect.y +| offset_y,
                    .width = new_w,
                    .height = new_h,
                };
            },
        }
    }
};

/// Transition manager for multiple concurrent transitions
pub const TransitionManager = struct {
    transitions: std.ArrayList(TransitionState),
    allocator: std.mem.Allocator,

    const TransitionState = struct {
        id: u64,
        transition: Transition,
        active: bool,
    };

    /// Initialize transition manager
    pub fn init(allocator: std.mem.Allocator) TransitionManager {
        return .{
            .transitions = .{},
            .allocator = allocator,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *TransitionManager) void {
        self.transitions.deinit(self.allocator);
    }

    /// Add a transition
    pub fn add(self: *TransitionManager, id: u64, transition: Transition) !void {
        try self.transitions.append(self.allocator, .{
            .id = id,
            .transition = transition,
            .active = false,
        });
    }

    /// Start a transition by ID
    pub fn start(self: *TransitionManager, id: u64, current_time_ms: u64, rect: Rect) void {
        for (self.transitions.items) |*state| {
            if (state.id == id) {
                state.transition.begin(current_time_ms, rect);
                state.active = true;
                return;
            }
        }
    }

    /// Update all active transitions
    pub fn update(self: *TransitionManager, current_time_ms: u64) void {
        for (self.transitions.items) |*state| {
            if (state.active) {
                _ = state.transition.update(current_time_ms);
                if (state.transition.isComplete()) {
                    state.active = false;
                }
            }
        }
    }

    /// Get current rect for a transition ID (returns original if not active)
    pub fn getRect(self: *TransitionManager, id: u64, default_rect: Rect) Rect {
        for (self.transitions.items) |*state| {
            if (state.id == id and state.active) {
                return state.transition.original_rect;
            }
        }
        return default_rect;
    }

    /// Get alpha value for a fade transition
    pub fn getAlpha(self: *TransitionManager, id: u64) f32 {
        for (self.transitions.items) |*state| {
            if (state.id == id and state.active) {
                return state.transition.getAlpha();
            }
        }
        return 1.0;
    }

    /// Remove completed transitions
    pub fn cleanup(self: *TransitionManager) void {
        var i: usize = 0;
        while (i < self.transitions.items.len) {
            if (!self.transitions.items[i].active and self.transitions.items[i].transition.isComplete()) {
                _ = self.transitions.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Transition - fade init" {
    const trans = Transition.fade(1000, animation.linear);
    try std.testing.expectEqual(TransitionType.fade, trans.type);
    try std.testing.expectEqual(@as(f32, 0.0), trans.anim.start_value);
    try std.testing.expectEqual(@as(f32, 1.0), trans.anim.end_value);
    try std.testing.expectEqual(@as(u64, 1000), trans.anim.duration_ms);
}

test "Transition - slide init" {
    const trans = Transition.slide(500, .left, animation.easeIn);
    try std.testing.expectEqual(TransitionType.slide, trans.type);
    try std.testing.expectEqual(SlideDirection.left, trans.slide_dir.?);
    try std.testing.expectEqual(@as(u64, 500), trans.anim.duration_ms);
}

test "Transition - scale init" {
    const trans = Transition.scale(2000, animation.easeOut);
    try std.testing.expectEqual(TransitionType.scale, trans.type);
    try std.testing.expectEqual(@as(u64, 2000), trans.anim.duration_ms);
}

test "Transition - fade progress" {
    var trans = Transition.fade(1000, animation.linear);
    const rect = Rect{ .x = 10, .y = 10, .width = 50, .height = 20 };

    trans.begin(0, rect);
    try std.testing.expect(!trans.isComplete());

    // Fade doesn't change rect
    const rect1 = trans.update(500);
    try std.testing.expectEqual(rect, rect1);

    const rect2 = trans.update(1000);
    try std.testing.expectEqual(rect, rect2);
    try std.testing.expect(trans.isComplete());
}

test "Transition - slide right progress" {
    var trans = Transition.slide(1000, .right, animation.linear);
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    trans.begin(0, rect);

    // At t=0.5, width should be 50
    const rect1 = trans.update(500);
    try std.testing.expectEqual(@as(u16, 0), rect1.x);
    try std.testing.expectEqual(@as(u16, 0), rect1.y);
    try std.testing.expectEqual(@as(u16, 50), rect1.width);
    try std.testing.expectEqual(@as(u16, 50), rect1.height);

    // At t=1.0, full width
    const rect2 = trans.update(1000);
    try std.testing.expectEqual(rect, rect2);
    try std.testing.expect(trans.isComplete());
}

test "Transition - slide left progress" {
    var trans = Transition.slide(1000, .left, animation.linear);
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    trans.begin(0, rect);

    // At t=0.5, should be offset to the right
    const rect1 = trans.update(500);
    try std.testing.expectEqual(@as(u16, 50), rect1.x); // offset by half
    try std.testing.expectEqual(@as(u16, 50), rect1.width);

    // At t=1.0, back to original position
    const rect2 = trans.update(1000);
    try std.testing.expectEqual(rect, rect2);
}

test "Transition - slide down progress" {
    var trans = Transition.slide(1000, .down, animation.linear);
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    trans.begin(0, rect);

    const rect1 = trans.update(500);
    try std.testing.expectEqual(@as(u16, 0), rect1.x);
    try std.testing.expectEqual(@as(u16, 0), rect1.y);
    try std.testing.expectEqual(@as(u16, 100), rect1.width);
    try std.testing.expectEqual(@as(u16, 25), rect1.height);

    const rect2 = trans.update(1000);
    try std.testing.expectEqual(rect, rect2);
}

test "Transition - slide up progress" {
    var trans = Transition.slide(1000, .up, animation.linear);
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    trans.begin(0, rect);

    const rect1 = trans.update(500);
    try std.testing.expectEqual(@as(u16, 0), rect1.x);
    try std.testing.expectEqual(@as(u16, 25), rect1.y); // offset
    try std.testing.expectEqual(@as(u16, 100), rect1.width);
    try std.testing.expectEqual(@as(u16, 25), rect1.height);

    const rect2 = trans.update(1000);
    try std.testing.expectEqual(rect, rect2);
}

test "Transition - scale progress" {
    var trans = Transition.scale(1000, animation.linear);
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    trans.begin(0, rect);

    // At t=0.5, should be half size and centered
    const rect1 = trans.update(500);
    try std.testing.expectEqual(@as(u16, 25), rect1.x); // centered horizontally
    try std.testing.expectEqual(@as(u16, 12), rect1.y); // centered vertically (rounded)
    try std.testing.expectEqual(@as(u16, 50), rect1.width);
    try std.testing.expectEqual(@as(u16, 25), rect1.height);

    // At t=1.0, full size
    const rect2 = trans.update(1000);
    try std.testing.expectEqual(rect, rect2);
}

test "Transition - reset" {
    var trans = Transition.fade(1000, animation.linear);
    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    trans.begin(0, rect);
    _ = trans.update(1000);
    try std.testing.expect(trans.isComplete());

    trans.reset();
    try std.testing.expect(!trans.isComplete());
}

test "TransitionManager - init and deinit" {
    var mgr = TransitionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 0), mgr.transitions.items.len);
}

test "TransitionManager - add transition" {
    var mgr = TransitionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const trans = Transition.fade(1000, animation.linear);
    try mgr.add(1, trans);

    try std.testing.expectEqual(@as(usize, 1), mgr.transitions.items.len);
    try std.testing.expectEqual(@as(u64, 1), mgr.transitions.items[0].id);
    try std.testing.expect(!mgr.transitions.items[0].active);
}

test "TransitionManager - start and update" {
    var mgr = TransitionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const trans = Transition.slide(1000, .right, animation.linear);
    try mgr.add(1, trans);

    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    mgr.start(1, 0, rect);

    try std.testing.expect(mgr.transitions.items[0].active);

    mgr.update(500);
    try std.testing.expect(mgr.transitions.items[0].active);

    mgr.update(1000);
    try std.testing.expect(!mgr.transitions.items[0].active);
}

test "TransitionManager - getRect" {
    var mgr = TransitionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const trans = Transition.fade(1000, animation.linear);
    try mgr.add(1, trans);

    const rect = Rect{ .x = 10, .y = 10, .width = 100, .height = 50 };
    const default_rect = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };

    // Not started - should return default
    const r1 = mgr.getRect(1, default_rect);
    try std.testing.expectEqual(default_rect, r1);

    mgr.start(1, 0, rect);

    // Started - should return original rect
    const r2 = mgr.getRect(1, default_rect);
    try std.testing.expectEqual(rect, r2);
}

test "TransitionManager - getAlpha" {
    var mgr = TransitionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const trans = Transition.fade(1000, animation.linear);
    try mgr.add(1, trans);

    // Not started
    const alpha1 = mgr.getAlpha(1);
    try std.testing.expectEqual(@as(f32, 1.0), alpha1);

    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    mgr.start(1, 0, rect);

    // Started
    const alpha2 = mgr.getAlpha(1);
    try std.testing.expect(alpha2 >= 0.0 and alpha2 <= 1.0);
}

test "TransitionManager - cleanup" {
    var mgr = TransitionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const trans = Transition.fade(100, animation.linear);
    try mgr.add(1, trans);

    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    mgr.start(1, 0, rect);
    mgr.update(100); // Complete transition

    try std.testing.expectEqual(@as(usize, 1), mgr.transitions.items.len);

    mgr.cleanup();

    try std.testing.expectEqual(@as(usize, 0), mgr.transitions.items.len);
}

test "TransitionManager - multiple transitions" {
    var mgr = TransitionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const trans1 = Transition.fade(1000, animation.linear);
    const trans2 = Transition.slide(500, .left, animation.easeIn);
    const trans3 = Transition.scale(2000, animation.easeOut);

    try mgr.add(1, trans1);
    try mgr.add(2, trans2);
    try mgr.add(3, trans3);

    try std.testing.expectEqual(@as(usize, 3), mgr.transitions.items.len);

    const rect = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    mgr.start(1, 0, rect);
    mgr.start(2, 0, rect);
    mgr.start(3, 0, rect);

    mgr.update(500);
    // trans2 should be complete
    try std.testing.expect(!mgr.transitions.items[1].active);
    // trans1 and trans3 still active
    try std.testing.expect(mgr.transitions.items[0].active);
    try std.testing.expect(mgr.transitions.items[2].active);

    mgr.update(1000);
    // trans1 should be complete now
    try std.testing.expect(!mgr.transitions.items[0].active);
    // trans3 still active
    try std.testing.expect(mgr.transitions.items[2].active);

    mgr.update(2000);
    // All should be complete
    try std.testing.expect(!mgr.transitions.items[0].active);
    try std.testing.expect(!mgr.transitions.items[1].active);
    try std.testing.expect(!mgr.transitions.items[2].active);
}
