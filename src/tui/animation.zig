const std = @import("std");
const style = @import("style.zig");
const Color = style.Color;

/// Easing function type
pub const EasingFn = *const fn (f32) f32;

/// Linear interpolation (no easing)
pub fn linear(t: f32) f32 {
    return t;
}

/// Ease-in (accelerate from zero velocity)
pub fn easeIn(t: f32) f32 {
    return t * t;
}

/// Ease-out (decelerate to zero velocity)
pub fn easeOut(t: f32) f32 {
    return t * (2.0 - t);
}

/// Ease-in-out (accelerate then decelerate)
pub fn easeInOut(t: f32) f32 {
    if (t < 0.5) {
        return 2.0 * t * t;
    }
    return -1.0 + (4.0 - 2.0 * t) * t;
}

/// Ease-in-cubic
pub fn easeInCubic(t: f32) f32 {
    return t * t * t;
}

/// Ease-out-cubic
pub fn easeOutCubic(t: f32) f32 {
    const t1 = t - 1.0;
    return t1 * t1 * t1 + 1.0;
}

/// Ease-in-out-cubic
pub fn easeInOutCubic(t: f32) f32 {
    if (t < 0.5) {
        return 4.0 * t * t * t;
    }
    const t1 = 2.0 * t - 2.0;
    return 1.0 + t1 * t1 * t1 / 2.0;
}

/// Interpolate between two numeric values
pub fn lerp(start: f32, end: f32, t: f32) f32 {
    return start + (end - start) * t;
}

/// Interpolate between two u8 values (for RGB channels)
pub fn lerpU8(start: u8, end: u8, t: f32) u8 {
    const start_f: f32 = @floatFromInt(start);
    const end_f: f32 = @floatFromInt(end);
    const result = start_f + (end_f - start_f) * t;
    return @intFromFloat(@max(0, @min(255, result)));
}

/// Interpolate between two colors
pub fn lerpColor(start: Color, end: Color, t: f32) Color {
    // Only interpolate RGB colors
    switch (start) {
        .rgb => |s_rgb| {
            switch (end) {
                .rgb => |e_rgb| {
                    return .{
                        .rgb = .{
                            .r = lerpU8(s_rgb.r, e_rgb.r, t),
                            .g = lerpU8(s_rgb.g, e_rgb.g, t),
                            .b = lerpU8(s_rgb.b, e_rgb.b, t),
                        },
                    };
                },
                else => return if (t < 0.5) start else end,
            }
        },
        else => return if (t < 0.5) start else end,
    }
}

/// Animation state manager
pub const Animation = struct {
    /// Start value
    start_value: f32,
    /// End value
    end_value: f32,
    /// Duration in milliseconds
    duration_ms: u64,
    /// Start time (milliseconds since epoch)
    start_time_ms: u64,
    /// Easing function
    easing: EasingFn = linear,
    /// Whether animation is complete
    complete: bool = false,

    /// Create a new animation
    pub fn init(start: f32, end: f32, duration_ms: u64, easing: EasingFn) Animation {
        return .{
            .start_value = start,
            .end_value = end,
            .duration_ms = duration_ms,
            .start_time_ms = 0,
            .easing = easing,
        };
    }

    /// Begin the animation with current timestamp
    pub fn begin(self: *Animation, current_time_ms: u64) void {
        self.start_time_ms = current_time_ms;
        self.complete = false;
    }

    /// Update and get current animated value
    pub fn update(self: *Animation, current_time_ms: u64) f32 {
        if (self.complete) {
            return self.end_value;
        }

        const elapsed = current_time_ms -| self.start_time_ms;
        if (elapsed >= self.duration_ms) {
            self.complete = true;
            return self.end_value;
        }

        const t: f32 = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(self.duration_ms));
        const eased = self.easing(t);
        return lerp(self.start_value, self.end_value, eased);
    }

    /// Check if animation is complete
    pub fn isComplete(self: Animation) bool {
        return self.complete;
    }

    /// Reset animation to start
    pub fn reset(self: *Animation) void {
        self.complete = false;
        self.start_time_ms = 0;
    }
};

/// Color animation state manager
pub const ColorAnimation = struct {
    /// Start color
    start_color: Color,
    /// End color
    end_color: Color,
    /// Duration in milliseconds
    duration_ms: u64,
    /// Start time (milliseconds since epoch)
    start_time_ms: u64,
    /// Easing function
    easing: EasingFn = linear,
    /// Whether animation is complete
    complete: bool = false,

    /// Create a new color animation
    pub fn init(start: Color, end: Color, duration_ms: u64, easing: EasingFn) ColorAnimation {
        return .{
            .start_color = start,
            .end_color = end,
            .duration_ms = duration_ms,
            .start_time_ms = 0,
            .easing = easing,
        };
    }

    /// Begin the animation with current timestamp
    pub fn begin(self: *ColorAnimation, current_time_ms: u64) void {
        self.start_time_ms = current_time_ms;
        self.complete = false;
    }

    /// Update and get current animated color
    pub fn update(self: *ColorAnimation, current_time_ms: u64) Color {
        if (self.complete) {
            return self.end_color;
        }

        const elapsed = current_time_ms -| self.start_time_ms;
        if (elapsed >= self.duration_ms) {
            self.complete = true;
            return self.end_color;
        }

        const t: f32 = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(self.duration_ms));
        const eased = self.easing(t);
        return lerpColor(self.start_color, self.end_color, eased);
    }

    /// Check if animation is complete
    pub fn isComplete(self: ColorAnimation) bool {
        return self.complete;
    }

    /// Reset animation to start
    pub fn reset(self: *ColorAnimation) void {
        self.complete = false;
        self.start_time_ms = 0;
    }
};

test "Animation - easing functions" {
    // Linear
    try std.testing.expectEqual(@as(f32, 0.0), linear(0.0));
    try std.testing.expectEqual(@as(f32, 0.5), linear(0.5));
    try std.testing.expectEqual(@as(f32, 1.0), linear(1.0));

    // Ease-in
    try std.testing.expectEqual(@as(f32, 0.0), easeIn(0.0));
    try std.testing.expectApproxEqRel(@as(f32, 0.25), easeIn(0.5), 0.01);
    try std.testing.expectEqual(@as(f32, 1.0), easeIn(1.0));

    // Ease-out
    try std.testing.expectEqual(@as(f32, 0.0), easeOut(0.0));
    try std.testing.expectApproxEqRel(@as(f32, 0.75), easeOut(0.5), 0.01);
    try std.testing.expectEqual(@as(f32, 1.0), easeOut(1.0));

    // Ease-in-out
    try std.testing.expectEqual(@as(f32, 0.0), easeInOut(0.0));
    try std.testing.expectApproxEqRel(@as(f32, 0.5), easeInOut(0.5), 0.01);
    try std.testing.expectEqual(@as(f32, 1.0), easeInOut(1.0));
}

test "Animation - lerp" {
    try std.testing.expectEqual(@as(f32, 0.0), lerp(0.0, 10.0, 0.0));
    try std.testing.expectEqual(@as(f32, 5.0), lerp(0.0, 10.0, 0.5));
    try std.testing.expectEqual(@as(f32, 10.0), lerp(0.0, 10.0, 1.0));

    try std.testing.expectEqual(@as(f32, 100.0), lerp(100.0, 200.0, 0.0));
    try std.testing.expectEqual(@as(f32, 150.0), lerp(100.0, 200.0, 0.5));
    try std.testing.expectEqual(@as(f32, 200.0), lerp(100.0, 200.0, 1.0));
}

test "Animation - lerpU8" {
    try std.testing.expectEqual(@as(u8, 0), lerpU8(0, 255, 0.0));
    try std.testing.expectEqual(@as(u8, 127), lerpU8(0, 255, 0.5));
    try std.testing.expectEqual(@as(u8, 255), lerpU8(0, 255, 1.0));
}

test "Animation - lerpColor RGB" {
    const black = Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    const white = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };

    const mid = lerpColor(black, white, 0.5);
    switch (mid) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 127), c.r);
            try std.testing.expectEqual(@as(u8, 127), c.g);
            try std.testing.expectEqual(@as(u8, 127), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

test "Animation - lerpColor non-RGB fallback" {
    const result = lerpColor(.red, .blue, 0.3);
    try std.testing.expectEqual(Color.red, result); // < 0.5 returns start

    const result2 = lerpColor(.red, .blue, 0.6);
    try std.testing.expectEqual(Color.blue, result2); // >= 0.5 returns end
}

test "Animation - basic animation" {
    var anim = Animation.init(0.0, 100.0, 1000, linear);

    // Start at time 0
    anim.begin(0);
    try std.testing.expect(!anim.isComplete());

    // Half-way through (500ms)
    const val1 = anim.update(500);
    try std.testing.expectEqual(@as(f32, 50.0), val1);
    try std.testing.expect(!anim.isComplete());

    // Complete (1000ms)
    const val2 = anim.update(1000);
    try std.testing.expectEqual(@as(f32, 100.0), val2);
    try std.testing.expect(anim.isComplete());

    // After complete
    const val3 = anim.update(1500);
    try std.testing.expectEqual(@as(f32, 100.0), val3);
}

test "Animation - with easing" {
    var anim = Animation.init(0.0, 100.0, 1000, easeInOut);

    anim.begin(0);
    const val1 = anim.update(500);
    // Should be close to 50 with easeInOut
    try std.testing.expectApproxEqRel(@as(f32, 50.0), val1, 0.1);
}

test "Animation - reset" {
    var anim = Animation.init(0.0, 100.0, 1000, linear);

    anim.begin(0);
    _ = anim.update(1000);
    try std.testing.expect(anim.isComplete());

    anim.reset();
    try std.testing.expect(!anim.isComplete());
}

test "ColorAnimation - basic" {
    const black = Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    const white = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };

    var anim = ColorAnimation.init(black, white, 1000, linear);
    anim.begin(0);

    const mid = anim.update(500);
    switch (mid) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 127), c.r);
            try std.testing.expectEqual(@as(u8, 127), c.g);
            try std.testing.expectEqual(@as(u8, 127), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    try std.testing.expect(!anim.isComplete());

    const final = anim.update(1000);
    try std.testing.expectEqual(white, final);
    try std.testing.expect(anim.isComplete());
}

test "ColorAnimation - reset" {
    const red = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const blue = Color{ .rgb = .{ .r = 0, .g = 0, .b = 255 } };

    var anim = ColorAnimation.init(red, blue, 1000, linear);
    anim.begin(0);
    _ = anim.update(1000);
    try std.testing.expect(anim.isComplete());

    anim.reset();
    try std.testing.expect(!anim.isComplete());
}
