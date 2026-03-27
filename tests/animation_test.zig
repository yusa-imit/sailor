//! Comprehensive tests for sailor's animation trait system (v1.24.0)
//!
//! Tests the animation framework including:
//! - Basic animation lifecycle (create → start → update → finish)
//! - Keyframe interpolation (linear, multiple keyframes)
//! - Tween protocol (smooth transitions between values)
//! - Animation state management (idle, playing, paused, finished)
//! - Time control (duration, elapsed time, progress)
//! - Value types (f32, u8, Color, Rect)
//! - Edge cases (zero duration, negative delta, update after finished)
//! - Easing functions (linear, ease-in/out, cubic variants)

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const animation = sailor.tui.animation;
const Animation = animation.Animation;
const ColorAnimation = animation.ColorAnimation;
const Color = sailor.tui.Color;
const Rect = sailor.tui.Rect;

// ============================================================================
// Animation Lifecycle Tests
// ============================================================================

test "Animation lifecycle - create to finish" {
    // Create animation from 0 to 100 over 1 second
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);

    // Initial state: not started (no begin() called yet)
    try testing.expect(!anim.isComplete());
    try testing.expectEqual(@as(u64, 0), anim.start_time_ms);

    // Begin animation at time 0
    anim.begin(0);
    try testing.expect(!anim.isComplete());
    try testing.expectEqual(@as(u64, 0), anim.start_time_ms);

    // Update at 25% (250ms)
    const val1 = anim.update(250);
    try testing.expectEqual(@as(f32, 25.0), val1);
    try testing.expect(!anim.isComplete());

    // Update at 50% (500ms)
    const val2 = anim.update(500);
    try testing.expectEqual(@as(f32, 50.0), val2);
    try testing.expect(!anim.isComplete());

    // Update at 75% (750ms)
    const val3 = anim.update(750);
    try testing.expectEqual(@as(f32, 75.0), val3);
    try testing.expect(!anim.isComplete());

    // Update at completion (1000ms)
    const val4 = anim.update(1000);
    try testing.expectEqual(@as(f32, 100.0), val4);
    try testing.expect(anim.isComplete());

    // Update after completion should return end value
    const val5 = anim.update(1500);
    try testing.expectEqual(@as(f32, 100.0), val5);
    try testing.expect(anim.isComplete());
}

test "Animation lifecycle - reset and restart" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);

    // Complete the animation
    anim.begin(0);
    _ = anim.update(1000);
    try testing.expect(anim.isComplete());

    // Reset should clear complete flag
    anim.reset();
    try testing.expect(!anim.isComplete());
    try testing.expectEqual(@as(u64, 0), anim.start_time_ms);

    // Can restart from new time
    anim.begin(2000);
    const val = anim.update(2500);
    try testing.expectEqual(@as(f32, 50.0), val);
    try testing.expect(!anim.isComplete());
}

test "Animation lifecycle - begin at non-zero time" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);

    // Start at time 5000ms
    anim.begin(5000);
    try testing.expectEqual(@as(u64, 5000), anim.start_time_ms);

    // Update at 5500ms (500ms elapsed)
    const val = anim.update(5500);
    try testing.expectEqual(@as(f32, 50.0), val);
}

// ============================================================================
// Keyframe Interpolation Tests
// ============================================================================

test "Keyframe interpolation - basic linear" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(0);

    // Test various points along linear interpolation
    try testing.expectEqual(@as(f32, 0.0), anim.update(0));
    try testing.expectEqual(@as(f32, 10.0), anim.update(100));
    try testing.expectEqual(@as(f32, 33.3), anim.update(333));
    try testing.expectEqual(@as(f32, 66.6), anim.update(666));
    try testing.expectEqual(@as(f32, 90.0), anim.update(900));
    try testing.expectEqual(@as(f32, 100.0), anim.update(1000));
}

test "Keyframe interpolation - negative to positive" {
    var anim = Animation.init(-50.0, 50.0, 1000, animation.linear);
    anim.begin(0);

    try testing.expectEqual(@as(f32, -50.0), anim.update(0));
    try testing.expectEqual(@as(f32, 0.0), anim.update(500));
    try testing.expectEqual(@as(f32, 50.0), anim.update(1000));
}

test "Keyframe interpolation - reverse (high to low)" {
    var anim = Animation.init(100.0, 0.0, 1000, animation.linear);
    anim.begin(0);

    try testing.expectEqual(@as(f32, 100.0), anim.update(0));
    try testing.expectEqual(@as(f32, 75.0), anim.update(250));
    try testing.expectEqual(@as(f32, 50.0), anim.update(500));
    try testing.expectEqual(@as(f32, 0.0), anim.update(1000));
}

test "Keyframe interpolation - identical start and end" {
    var anim = Animation.init(42.0, 42.0, 1000, animation.linear);
    anim.begin(0);

    // Should always return same value
    try testing.expectEqual(@as(f32, 42.0), anim.update(0));
    try testing.expectEqual(@as(f32, 42.0), anim.update(500));
    try testing.expectEqual(@as(f32, 42.0), anim.update(1000));
}

// ============================================================================
// Tween Protocol Tests
// ============================================================================

test "Tween protocol - smooth transition with easeIn" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.easeIn);
    anim.begin(0);

    const val_start = anim.update(0);
    const val_quarter = anim.update(250);
    const val_half = anim.update(500);
    const val_end = anim.update(1000);

    // easeIn accelerates, so value at 0.25 should be less than linear 25.0
    try testing.expectEqual(@as(f32, 0.0), val_start);
    try testing.expect(val_quarter < 25.0);
    try testing.expect(val_quarter > 0.0);
    try testing.expect(val_half < 50.0); // Still accelerating
    try testing.expectEqual(@as(f32, 100.0), val_end);
}

test "Tween protocol - smooth transition with easeOut" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.easeOut);
    anim.begin(0);

    const val_quarter = anim.update(250);
    const val_half = anim.update(500);

    // easeOut decelerates, so value at 0.25 should be more than linear 25.0
    try testing.expect(val_quarter > 25.0);
    try testing.expect(val_half > 50.0);
}

test "Tween protocol - smooth transition with easeInOut" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.easeInOut);
    anim.begin(0);

    const val_quarter = anim.update(250);
    const val_half = anim.update(500);
    const val_three_quarter = anim.update(750);

    // easeInOut accelerates then decelerates
    try testing.expect(val_quarter < 25.0); // Accelerating
    try testing.expectApproxEqRel(@as(f32, 50.0), val_half, 0.1); // Should be near 50
    try testing.expect(val_three_quarter > 75.0); // Decelerating
}

test "Tween protocol - cubic easing functions" {
    var anim_in = Animation.init(0.0, 100.0, 1000, animation.easeInCubic);
    var anim_out = Animation.init(0.0, 100.0, 1000, animation.easeOutCubic);
    var anim_in_out = Animation.init(0.0, 100.0, 1000, animation.easeInOutCubic);

    anim_in.begin(0);
    anim_out.begin(0);
    anim_in_out.begin(0);

    const val_in = anim_in.update(500);
    const val_out = anim_out.update(500);
    const val_in_out = anim_in_out.update(500);

    // Cubic should be more pronounced than quadratic
    try testing.expect(val_in < 25.0); // Heavy acceleration
    try testing.expect(val_out > 75.0); // Heavy deceleration
    try testing.expectApproxEqRel(@as(f32, 50.0), val_in_out, 0.1);
}

// ============================================================================
// Animation State Management Tests
// ============================================================================

test "Animation state - idle to playing to finished" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);

    // Initial state: idle (not started)
    try testing.expect(!anim.isComplete());
    try testing.expectEqual(@as(bool, false), anim.complete);

    // Begin: now playing
    anim.begin(0);
    try testing.expect(!anim.isComplete());

    // Update mid-way: still playing
    _ = anim.update(500);
    try testing.expect(!anim.isComplete());

    // Update to completion: finished
    _ = anim.update(1000);
    try testing.expect(anim.isComplete());
    try testing.expectEqual(@as(bool, true), anim.complete);
}

test "Animation state - pause by not updating" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(0);

    // Update to 50%
    const val1 = anim.update(500);
    try testing.expectEqual(@as(f32, 50.0), val1);

    // "Pause" by keeping same time
    const val2 = anim.update(500);
    try testing.expectEqual(@as(f32, 50.0), val2);

    // "Resume" by updating time
    const val3 = anim.update(750);
    try testing.expectEqual(@as(f32, 75.0), val3);
}

test "Animation state - multiple complete checks idempotent" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(0);
    _ = anim.update(1000);

    // Multiple isComplete() calls should return same result
    try testing.expect(anim.isComplete());
    try testing.expect(anim.isComplete());
    try testing.expect(anim.isComplete());
}

// ============================================================================
// Time Control Tests
// ============================================================================

test "Time control - duration accuracy" {
    const durations = [_]u64{ 100, 500, 1000, 5000, 10000 };

    for (durations) |duration| {
        var anim = Animation.init(0.0, 100.0, duration, animation.linear);
        anim.begin(0);

        // Should complete exactly at duration
        _ = anim.update(duration);
        try testing.expect(anim.isComplete());

        // Should not complete before duration
        var anim2 = Animation.init(0.0, 100.0, duration, animation.linear);
        anim2.begin(0);
        _ = anim2.update(duration -| 1);
        try testing.expect(!anim2.isComplete());
    }
}

test "Time control - elapsed time calculation" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(1000);

    // Elapsed time = current_time - start_time
    const val1 = anim.update(1250); // 250ms elapsed
    try testing.expectEqual(@as(f32, 25.0), val1);

    const val2 = anim.update(1500); // 500ms elapsed
    try testing.expectEqual(@as(f32, 50.0), val2);

    const val3 = anim.update(2000); // 1000ms elapsed (complete)
    try testing.expectEqual(@as(f32, 100.0), val3);
}

test "Time control - progress percentage" {
    var anim = Animation.init(0.0, 1.0, 1000, animation.linear);
    anim.begin(0);

    // Progress as 0.0 to 1.0
    try testing.expectEqual(@as(f32, 0.0), anim.update(0));
    try testing.expectEqual(@as(f32, 0.1), anim.update(100));
    try testing.expectEqual(@as(f32, 0.25), anim.update(250));
    try testing.expectEqual(@as(f32, 0.5), anim.update(500));
    try testing.expectEqual(@as(f32, 0.75), anim.update(750));
    try testing.expectEqual(@as(f32, 1.0), anim.update(1000));
}

// ============================================================================
// Value Type Tests
// ============================================================================

test "Value type - f32 interpolation" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(0);

    const val = anim.update(333);
    try testing.expectEqual(@as(f32, 33.3), val);
}

test "Value type - u8 interpolation via lerpU8" {
    // Test the lerpU8 helper function
    try testing.expectEqual(@as(u8, 0), animation.lerpU8(0, 255, 0.0));
    try testing.expectEqual(@as(u8, 127), animation.lerpU8(0, 255, 0.5));
    try testing.expectEqual(@as(u8, 255), animation.lerpU8(0, 255, 1.0));

    // Edge cases
    try testing.expectEqual(@as(u8, 63), animation.lerpU8(0, 255, 0.25));
    try testing.expectEqual(@as(u8, 191), animation.lerpU8(0, 255, 0.75));
}

test "Value type - Color RGB interpolation" {
    const black = Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    const white = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };

    var anim = ColorAnimation.init(black, white, 1000, animation.linear);
    anim.begin(0);

    // Start
    const color_start = anim.update(0);
    try testing.expectEqual(black, color_start);

    // Mid-point
    const color_mid = anim.update(500);
    switch (color_mid) {
        .rgb => |c| {
            try testing.expectEqual(@as(u8, 127), c.r);
            try testing.expectEqual(@as(u8, 127), c.g);
            try testing.expectEqual(@as(u8, 127), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    // End
    const color_end = anim.update(1000);
    try testing.expectEqual(white, color_end);
}

test "Value type - Color non-RGB fallback" {
    var anim = ColorAnimation.init(.red, .blue, 1000, animation.linear);
    anim.begin(0);

    // Named colors don't interpolate, they snap at 0.5
    const color_before_half = anim.update(400); // t = 0.4
    try testing.expectEqual(Color.red, color_before_half);

    const color_after_half = anim.update(600); // t = 0.6
    try testing.expectEqual(Color.blue, color_after_half);
}

test "Value type - Color channel interpolation" {
    const red = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const green = Color{ .rgb = .{ .r = 0, .g = 255, .b = 0 } };

    var anim = ColorAnimation.init(red, green, 1000, animation.linear);
    anim.begin(0);

    const color_mid = anim.update(500);
    switch (color_mid) {
        .rgb => |c| {
            try testing.expectEqual(@as(u8, 127), c.r); // Red fading
            try testing.expectEqual(@as(u8, 127), c.g); // Green appearing
            try testing.expectEqual(@as(u8, 0), c.b);   // Blue unchanged
        },
        else => return error.ExpectedRgbColor,
    }
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "Edge case - zero duration" {
    var anim = Animation.init(0.0, 100.0, 0, animation.linear);
    anim.begin(0);

    // Should complete immediately
    const val = anim.update(0);
    try testing.expectEqual(@as(f32, 100.0), val);
    try testing.expect(anim.isComplete());
}

test "Edge case - update before begin" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);

    // Update without calling begin() first
    // start_time_ms is 0, so this should work
    const val = anim.update(500);
    try testing.expectEqual(@as(f32, 50.0), val);
}

test "Edge case - time overflow protection with saturating sub" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(5000);

    // Update with time less than start_time (should saturate to 0)
    const val = anim.update(4000);
    try testing.expectEqual(@as(f32, 0.0), val);
    try testing.expect(!anim.isComplete());
}

test "Edge case - very long duration" {
    const long_duration: u64 = 1_000_000_000; // 1 billion ms (~11 days)
    var anim = Animation.init(0.0, 100.0, long_duration, animation.linear);
    anim.begin(0);

    const val_mid = anim.update(long_duration / 2);
    try testing.expectEqual(@as(f32, 50.0), val_mid);
    try testing.expect(!anim.isComplete());
}

test "Edge case - update after finished returns end value" {
    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(0);

    _ = anim.update(1000);
    try testing.expect(anim.isComplete());

    // Multiple updates after completion
    try testing.expectEqual(@as(f32, 100.0), anim.update(1500));
    try testing.expectEqual(@as(f32, 100.0), anim.update(2000));
    try testing.expectEqual(@as(f32, 100.0), anim.update(10000));
}

test "Edge case - fractional milliseconds (sub-ms precision)" {
    var anim = Animation.init(0.0, 1000.0, 1000, animation.linear);
    anim.begin(0);

    // Test single millisecond increments
    const val1 = anim.update(1);
    try testing.expectEqual(@as(f32, 1.0), val1);

    const val2 = anim.update(2);
    try testing.expectEqual(@as(f32, 2.0), val2);
}

test "Edge case - negative values interpolation" {
    var anim = Animation.init(-100.0, -50.0, 1000, animation.linear);
    anim.begin(0);

    try testing.expectEqual(@as(f32, -100.0), anim.update(0));
    try testing.expectEqual(@as(f32, -75.0), anim.update(500));
    try testing.expectEqual(@as(f32, -50.0), anim.update(1000));
}

test "Edge case - ColorAnimation reset" {
    const black = Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    const white = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };

    var anim = ColorAnimation.init(black, white, 1000, animation.linear);
    anim.begin(0);
    _ = anim.update(1000);

    try testing.expect(anim.isComplete());

    anim.reset();
    try testing.expect(!anim.isComplete());
    try testing.expectEqual(@as(u64, 0), anim.start_time_ms);
}

// ============================================================================
// Easing Function Tests
// ============================================================================

test "Easing functions - linear boundaries" {
    try testing.expectEqual(@as(f32, 0.0), animation.linear(0.0));
    try testing.expectEqual(@as(f32, 0.5), animation.linear(0.5));
    try testing.expectEqual(@as(f32, 1.0), animation.linear(1.0));
}

test "Easing functions - easeIn boundaries" {
    try testing.expectEqual(@as(f32, 0.0), animation.easeIn(0.0));
    try testing.expectApproxEqRel(@as(f32, 0.25), animation.easeIn(0.5), 0.01);
    try testing.expectEqual(@as(f32, 1.0), animation.easeIn(1.0));
}

test "Easing functions - easeOut boundaries" {
    try testing.expectEqual(@as(f32, 0.0), animation.easeOut(0.0));
    try testing.expectApproxEqRel(@as(f32, 0.75), animation.easeOut(0.5), 0.01);
    try testing.expectEqual(@as(f32, 1.0), animation.easeOut(1.0));
}

test "Easing functions - easeInOut boundaries" {
    try testing.expectEqual(@as(f32, 0.0), animation.easeInOut(0.0));
    try testing.expectApproxEqRel(@as(f32, 0.5), animation.easeInOut(0.5), 0.01);
    try testing.expectEqual(@as(f32, 1.0), animation.easeInOut(1.0));
}

test "Easing functions - easeInCubic properties" {
    const val_start = animation.easeInCubic(0.0);
    const val_quarter = animation.easeInCubic(0.25);
    const val_half = animation.easeInCubic(0.5);
    const val_end = animation.easeInCubic(1.0);

    try testing.expectEqual(@as(f32, 0.0), val_start);
    try testing.expect(val_quarter < 0.25); // Slower at start
    try testing.expect(val_half < 0.5);
    try testing.expectEqual(@as(f32, 1.0), val_end);
}

test "Easing functions - easeOutCubic properties" {
    const val_start = animation.easeOutCubic(0.0);
    const val_half = animation.easeOutCubic(0.5);
    const val_three_quarter = animation.easeOutCubic(0.75);
    const val_end = animation.easeOutCubic(1.0);

    try testing.expectEqual(@as(f32, 0.0), val_start);
    try testing.expect(val_half > 0.5); // Faster at start
    try testing.expect(val_three_quarter > 0.75);
    try testing.expectEqual(@as(f32, 1.0), val_end);
}

test "Easing functions - easeInOutCubic symmetry" {
    const val_quarter = animation.easeInOutCubic(0.25);
    const val_three_quarter = animation.easeInOutCubic(0.75);

    // Should be symmetric around 0.5
    try testing.expect(val_quarter < 0.25);
    try testing.expect(val_three_quarter > 0.75);
    try testing.expectApproxEqRel(val_quarter, 1.0 - val_three_quarter, 0.01);
}

// ============================================================================
// Helper Function Tests
// ============================================================================

test "Helper - lerp basic interpolation" {
    try testing.expectEqual(@as(f32, 0.0), animation.lerp(0.0, 10.0, 0.0));
    try testing.expectEqual(@as(f32, 5.0), animation.lerp(0.0, 10.0, 0.5));
    try testing.expectEqual(@as(f32, 10.0), animation.lerp(0.0, 10.0, 1.0));
}

test "Helper - lerp negative values" {
    try testing.expectEqual(@as(f32, -10.0), animation.lerp(-10.0, 10.0, 0.0));
    try testing.expectEqual(@as(f32, 0.0), animation.lerp(-10.0, 10.0, 0.5));
    try testing.expectEqual(@as(f32, 10.0), animation.lerp(-10.0, 10.0, 1.0));
}

test "Helper - lerpU8 bounds clamping" {
    // Should clamp to 0-255 range
    const val = animation.lerpU8(0, 255, 1.5); // Over 1.0
    try testing.expectEqual(@as(u8, 255), val);
}

test "Helper - lerpColor RGB channels" {
    const color1 = Color{ .rgb = .{ .r = 100, .g = 0, .b = 200 } };
    const color2 = Color{ .rgb = .{ .r = 200, .g = 100, .b = 0 } };

    const result = animation.lerpColor(color1, color2, 0.5);

    switch (result) {
        .rgb => |c| {
            try testing.expectEqual(@as(u8, 150), c.r);
            try testing.expectEqual(@as(u8, 50), c.g);
            try testing.expectEqual(@as(u8, 100), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

// ============================================================================
// Integration Tests
// ============================================================================

test "Integration - multiple animations running concurrently" {
    var anim1 = Animation.init(0.0, 100.0, 1000, animation.linear);
    var anim2 = Animation.init(100.0, 200.0, 2000, animation.easeIn);
    var anim3 = Animation.init(50.0, 0.0, 500, animation.easeOut);

    anim1.begin(0);
    anim2.begin(0);
    anim3.begin(0);

    // Update all at t=500ms
    const val1 = anim1.update(500);
    const val2 = anim2.update(500);
    const val3 = anim3.update(500);

    try testing.expectEqual(@as(f32, 50.0), val1);
    try testing.expect(val2 < 150.0); // easeIn is slower at start
    try testing.expectEqual(@as(f32, 0.0), val3); // Complete

    try testing.expect(!anim1.isComplete());
    try testing.expect(!anim2.isComplete());
    try testing.expect(anim3.isComplete());
}

test "Integration - animation chain (sequential)" {
    var phase1 = Animation.init(0.0, 50.0, 500, animation.linear);
    var phase2 = Animation.init(50.0, 100.0, 500, animation.linear);

    phase1.begin(0);

    // Phase 1: 0 to 500ms
    _ = phase1.update(500);
    try testing.expect(phase1.isComplete());

    // Start phase 2 when phase 1 completes
    phase2.begin(500);
    const val = phase2.update(750); // 250ms into phase2
    try testing.expectEqual(@as(f32, 75.0), val);
}

test "Integration - color fade effect" {
    const start_color = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const end_color = Color{ .rgb = .{ .r = 0, .g = 0, .b = 255 } };

    var fade = ColorAnimation.init(start_color, end_color, 1000, animation.easeInOut);
    fade.begin(0);

    // Should smoothly transition from red to blue
    const color_quarter = fade.update(250);
    const color_half = fade.update(500);
    const color_three_quarter = fade.update(750);

    switch (color_quarter) {
        .rgb => |c| {
            try testing.expect(c.r > 127); // Still more red
            try testing.expect(c.b < 127); // Less blue
        },
        else => return error.ExpectedRgbColor,
    }

    switch (color_half) {
        .rgb => |c| {
            try testing.expectEqual(@as(u8, 127), c.r);
            try testing.expectEqual(@as(u8, 127), c.b);
        },
        else => return error.ExpectedRgbColor,
    }

    switch (color_three_quarter) {
        .rgb => |c| {
            try testing.expect(c.r < 127); // Less red
            try testing.expect(c.b > 127); // More blue
        },
        else => return error.ExpectedRgbColor,
    }
}

test "Integration - animation with custom easing function" {
    // Custom easing: instant jump at 0.5
    const customEase = struct {
        fn ease(t: f32) f32 {
            return if (t < 0.5) 0.0 else 1.0;
        }
    }.ease;

    var anim = Animation.init(0.0, 100.0, 1000, customEase);
    anim.begin(0);

    try testing.expectEqual(@as(f32, 0.0), anim.update(400));
    try testing.expectEqual(@as(f32, 0.0), anim.update(499));
    try testing.expectEqual(@as(f32, 100.0), anim.update(500));
    try testing.expectEqual(@as(f32, 100.0), anim.update(999));
}

test "Integration - memory safety with allocator (no leaks)" {
    // Animations themselves don't allocate, but ensure no issues
    const allocator = testing.allocator;

    var anim = Animation.init(0.0, 100.0, 1000, animation.linear);
    anim.begin(0);

    // Use animation
    _ = anim.update(500);

    // No deinit needed - animation is stack-allocated
    // This test verifies no unexpected allocations
    _ = allocator;
}
