//! Comprehensive tests for sailor's transition helpers (v1.24.0)
//!
//! Tests the transition framework including:
//! - Fade transitions (opacity-based effects)
//! - Slide transitions (position-based movement from all directions)
//! - Expand/collapse transitions (size-based growth/shrink)
//! - Transition composition (combining multiple effects)
//! - Integration with Rect/Layout (position and size interpolation)

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

const transition = sailor.tui.transition;
const FadeTransition = transition.FadeTransition;
const SlideTransition = transition.SlideTransition;
const ExpandTransition = transition.ExpandTransition;
const Direction = transition.Direction;
const animation = sailor.tui.animation;
const Rect = sailor.tui.Rect;

// ============================================================================
// Fade Transition Tests (6 tests)
// ============================================================================

test "FadeTransition - fade in from 0% to 100% opacity" {
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    // Start fade-in at time 0
    fade.begin(0);

    // At start: opacity should be 0
    const opacity_start = fade.update(0);
    try testing.expectEqual(@as(f32, 0.0), opacity_start);

    // At 25% (250ms): opacity should be 0.25
    const opacity_25 = fade.update(250);
    try testing.expectEqual(@as(f32, 0.25), opacity_25);

    // At 50% (500ms): opacity should be 0.5
    const opacity_50 = fade.update(500);
    try testing.expectEqual(@as(f32, 0.5), opacity_50);

    // At 75% (750ms): opacity should be 0.75
    const opacity_75 = fade.update(750);
    try testing.expectEqual(@as(f32, 0.75), opacity_75);

    // At 100% (1000ms): opacity should be 1.0
    const opacity_100 = fade.update(1000);
    try testing.expectEqual(@as(f32, 1.0), opacity_100);

    // Complete
    try testing.expect(fade.isComplete());
}

test "FadeTransition - fade out from 100% to 0% opacity" {
    var fade = FadeTransition.fadeOut(1000, animation.linear);

    // Start fade-out at time 0
    fade.begin(0);

    // At start: opacity should be 1.0
    const opacity_start = fade.update(0);
    try testing.expectEqual(@as(f32, 1.0), opacity_start);

    // At 50% (500ms): opacity should be 0.5
    const opacity_50 = fade.update(500);
    try testing.expectEqual(@as(f32, 0.5), opacity_50);

    // At 100% (1000ms): opacity should be 0.0
    const opacity_100 = fade.update(1000);
    try testing.expectEqual(@as(f32, 0.0), opacity_100);

    // Complete
    try testing.expect(fade.isComplete());
}

test "FadeTransition - partial fade to 50% opacity" {
    var fade = FadeTransition.init(0.0, 0.5, 1000, animation.linear);

    fade.begin(0);

    // At 50% progress (500ms): opacity should be 0.25
    const opacity_half = fade.update(500);
    try testing.expectEqual(@as(f32, 0.25), opacity_half);

    // At 100% progress (1000ms): opacity should be 0.5
    const opacity_end = fade.update(1000);
    try testing.expectEqual(@as(f32, 0.5), opacity_end);
}

test "FadeTransition - state at various time points" {
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    fade.begin(1000); // Start at time 1000ms

    // Before start: should be at start value (not meaningful but shouldn't crash)
    const before = fade.update(500);
    try testing.expectEqual(@as(f32, 0.0), before);

    // At exact start: should be 0.0
    const at_start = fade.update(1000);
    try testing.expectEqual(@as(f32, 0.0), at_start);

    // After start: should interpolate
    const mid = fade.update(1500);
    try testing.expectEqual(@as(f32, 0.5), mid);

    // After end: should clamp to end value
    const after = fade.update(3000);
    try testing.expectEqual(@as(f32, 1.0), after);
}

test "FadeTransition - easing curve effects on fade" {
    var fade_linear = FadeTransition.fadeIn(1000, animation.linear);
    var fade_easeIn = FadeTransition.fadeIn(1000, animation.easeIn);
    var fade_easeOut = FadeTransition.fadeIn(1000, animation.easeOut);

    fade_linear.begin(0);
    fade_easeIn.begin(0);
    fade_easeOut.begin(0);

    // At 50% time, easing should produce different opacity values
    const linear_50 = fade_linear.update(500);
    const easeIn_50 = fade_easeIn.update(500);
    const easeOut_50 = fade_easeOut.update(500);

    // Linear should be exactly 0.5
    try testing.expectEqual(@as(f32, 0.5), linear_50);

    // Ease-in should be slower at start (< 0.5)
    try testing.expect(easeIn_50 < 0.5);

    // Ease-out should be faster at start (> 0.5)
    try testing.expect(easeOut_50 > 0.5);
}

test "FadeTransition - reset and restart" {
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    // Complete first animation
    fade.begin(0);
    _ = fade.update(1000);
    try testing.expect(fade.isComplete());

    // Reset
    fade.reset();
    try testing.expect(!fade.isComplete());

    // Restart from new time
    fade.begin(2000);
    const opacity = fade.update(2500);
    try testing.expectEqual(@as(f32, 0.5), opacity);
}

// ============================================================================
// Slide Transition Tests (8 tests)
// ============================================================================

test "SlideTransition - slide in from top (Y position)" {
    const start_rect = Rect.new(10, 0, 50, 20); // Start at Y=0 (off-screen top)
    const end_rect = Rect.new(10, 30, 50, 20);  // End at Y=30

    var slide = SlideTransition.slideIn(.top, start_rect, end_rect, 1000, animation.linear);
    slide.begin(0);

    // At start: should be at Y=0
    const rect_start = slide.update(0);
    try testing.expectEqual(@as(u16, 0), rect_start.y);

    // At 50%: should be at Y=15
    const rect_mid = slide.update(500);
    try testing.expectEqual(@as(u16, 15), rect_mid.y);

    // At 100%: should be at Y=30
    const rect_end = slide.update(1000);
    try testing.expectEqual(@as(u16, 30), rect_end.y);

    // X, width, height should remain constant
    try testing.expectEqual(@as(u16, 10), rect_end.x);
    try testing.expectEqual(@as(u16, 50), rect_end.width);
    try testing.expectEqual(@as(u16, 20), rect_end.height);
}

test "SlideTransition - slide in from bottom (Y position)" {
    const start_rect = Rect.new(10, 100, 50, 20); // Start at Y=100 (off-screen bottom)
    const end_rect = Rect.new(10, 30, 50, 20);    // End at Y=30

    var slide = SlideTransition.slideIn(.bottom, start_rect, end_rect, 1000, animation.linear);
    slide.begin(0);

    // At start: should be at Y=100
    const rect_start = slide.update(0);
    try testing.expectEqual(@as(u16, 100), rect_start.y);

    // At 50%: should be at Y=65
    const rect_mid = slide.update(500);
    try testing.expectEqual(@as(u16, 65), rect_mid.y);

    // At 100%: should be at Y=30
    const rect_end = slide.update(1000);
    try testing.expectEqual(@as(u16, 30), rect_end.y);
}

test "SlideTransition - slide in from left (X position)" {
    const start_rect = Rect.new(0, 10, 50, 20);  // Start at X=0 (off-screen left)
    const end_rect = Rect.new(40, 10, 50, 20);   // End at X=40

    var slide = SlideTransition.slideIn(.left, start_rect, end_rect, 1000, animation.linear);
    slide.begin(0);

    // At start: should be at X=0
    const rect_start = slide.update(0);
    try testing.expectEqual(@as(u16, 0), rect_start.x);

    // At 50%: should be at X=20
    const rect_mid = slide.update(500);
    try testing.expectEqual(@as(u16, 20), rect_mid.x);

    // At 100%: should be at X=40
    const rect_end = slide.update(1000);
    try testing.expectEqual(@as(u16, 40), rect_end.x);

    // Y, width, height should remain constant
    try testing.expectEqual(@as(u16, 10), rect_end.y);
    try testing.expectEqual(@as(u16, 50), rect_end.width);
    try testing.expectEqual(@as(u16, 20), rect_end.height);
}

test "SlideTransition - slide in from right (X position)" {
    const start_rect = Rect.new(100, 10, 50, 20); // Start at X=100 (off-screen right)
    const end_rect = Rect.new(40, 10, 50, 20);    // End at X=40

    var slide = SlideTransition.slideIn(.right, start_rect, end_rect, 1000, animation.linear);
    slide.begin(0);

    // At start: should be at X=100
    const rect_start = slide.update(0);
    try testing.expectEqual(@as(u16, 100), rect_start.x);

    // At 50%: should be at X=70
    const rect_mid = slide.update(500);
    try testing.expectEqual(@as(u16, 70), rect_mid.x);

    // At 100%: should be at X=40
    const rect_end = slide.update(1000);
    try testing.expectEqual(@as(u16, 40), rect_end.x);
}

test "SlideTransition - slide out transitions (reverse)" {
    const start_rect = Rect.new(40, 30, 50, 20);
    const end_rect = Rect.new(40, 0, 50, 20); // Slide out to top

    var slide = SlideTransition.slideOut(.top, start_rect, end_rect, 1000, animation.linear);
    slide.begin(0);

    // At start: should be at Y=30
    const rect_start = slide.update(0);
    try testing.expectEqual(@as(u16, 30), rect_start.y);

    // At 100%: should be at Y=0
    const rect_end = slide.update(1000);
    try testing.expectEqual(@as(u16, 0), rect_end.y);
}

test "SlideTransition - easing curves for smooth movement" {
    const start_rect = Rect.new(0, 10, 50, 20);
    const end_rect = Rect.new(100, 10, 50, 20);

    var slide_linear = SlideTransition.slideIn(.left, start_rect, end_rect, 1000, animation.linear);
    var slide_easeOut = SlideTransition.slideIn(.left, start_rect, end_rect, 1000, animation.easeOut);

    slide_linear.begin(0);
    slide_easeOut.begin(0);

    // At 50% time, linear should be at X=50
    const rect_linear = slide_linear.update(500);
    try testing.expectEqual(@as(u16, 50), rect_linear.x);

    // Ease-out should be further along (> 50)
    const rect_easeOut = slide_easeOut.update(500);
    try testing.expect(rect_easeOut.x > 50);
}

test "SlideTransition - diagonal slide (multi-axis)" {
    const start_rect = Rect.new(0, 0, 50, 20);    // Top-left corner
    const end_rect = Rect.new(50, 30, 50, 20);    // Diagonal destination

    var slide = SlideTransition.init(start_rect, end_rect, 1000, animation.linear);
    slide.begin(0);

    // At 50%: both X and Y should interpolate
    const rect_mid = slide.update(500);
    try testing.expectEqual(@as(u16, 25), rect_mid.x); // X: 0 → 50, mid=25
    try testing.expectEqual(@as(u16, 15), rect_mid.y); // Y: 0 → 30, mid=15

    // At 100%: should reach destination
    const rect_end = slide.update(1000);
    try testing.expectEqual(@as(u16, 50), rect_end.x);
    try testing.expectEqual(@as(u16, 30), rect_end.y);
}

test "SlideTransition - zero distance slide (no movement)" {
    const rect = Rect.new(40, 30, 50, 20);

    var slide = SlideTransition.init(rect, rect, 1000, animation.linear);
    slide.begin(0);

    // At any time: should remain at original position
    const rect_start = slide.update(0);
    const rect_mid = slide.update(500);
    const rect_end = slide.update(1000);

    try testing.expectEqual(@as(u16, 40), rect_start.x);
    try testing.expectEqual(@as(u16, 40), rect_mid.x);
    try testing.expectEqual(@as(u16, 40), rect_end.x);

    try testing.expectEqual(@as(u16, 30), rect_start.y);
    try testing.expectEqual(@as(u16, 30), rect_mid.y);
    try testing.expectEqual(@as(u16, 30), rect_end.y);
}

// ============================================================================
// Expand/Collapse Transition Tests (8 tests)
// ============================================================================

test "ExpandTransition - expand width (horizontal growth)" {
    const start_rect = Rect.new(10, 10, 0, 20);   // Zero width
    const end_rect = Rect.new(10, 10, 100, 20);   // Full width

    var expand = ExpandTransition.expandWidth(start_rect, end_rect, 1000, animation.linear);
    expand.begin(0);

    // At start: width should be 0
    const rect_start = expand.update(0);
    try testing.expectEqual(@as(u16, 0), rect_start.width);

    // At 50%: width should be 50
    const rect_mid = expand.update(500);
    try testing.expectEqual(@as(u16, 50), rect_mid.width);

    // At 100%: width should be 100
    const rect_end = expand.update(1000);
    try testing.expectEqual(@as(u16, 100), rect_end.width);

    // X, Y, height should remain constant
    try testing.expectEqual(@as(u16, 10), rect_end.x);
    try testing.expectEqual(@as(u16, 10), rect_end.y);
    try testing.expectEqual(@as(u16, 20), rect_end.height);
}

test "ExpandTransition - expand height (vertical growth)" {
    const start_rect = Rect.new(10, 10, 50, 0);   // Zero height
    const end_rect = Rect.new(10, 10, 50, 60);    // Full height

    var expand = ExpandTransition.expandHeight(start_rect, end_rect, 1000, animation.linear);
    expand.begin(0);

    // At start: height should be 0
    const rect_start = expand.update(0);
    try testing.expectEqual(@as(u16, 0), rect_start.height);

    // At 50%: height should be 30
    const rect_mid = expand.update(500);
    try testing.expectEqual(@as(u16, 30), rect_mid.height);

    // At 100%: height should be 60
    const rect_end = expand.update(1000);
    try testing.expectEqual(@as(u16, 60), rect_end.height);

    // X, Y, width should remain constant
    try testing.expectEqual(@as(u16, 10), rect_end.x);
    try testing.expectEqual(@as(u16, 10), rect_end.y);
    try testing.expectEqual(@as(u16, 50), rect_end.width);
}

test "ExpandTransition - expand both dimensions (area growth)" {
    const start_rect = Rect.new(25, 25, 0, 0);    // Point (no area)
    const end_rect = Rect.new(25, 25, 50, 50);    // Square

    var expand = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);
    expand.begin(0);

    // At start: should be a point
    const rect_start = expand.update(0);
    try testing.expectEqual(@as(u16, 0), rect_start.width);
    try testing.expectEqual(@as(u16, 0), rect_start.height);

    // At 50%: should be 25x25
    const rect_mid = expand.update(500);
    try testing.expectEqual(@as(u16, 25), rect_mid.width);
    try testing.expectEqual(@as(u16, 25), rect_mid.height);

    // At 100%: should be 50x50
    const rect_end = expand.update(1000);
    try testing.expectEqual(@as(u16, 50), rect_end.width);
    try testing.expectEqual(@as(u16, 50), rect_end.height);

    // Position should remain constant
    try testing.expectEqual(@as(u16, 25), rect_end.x);
    try testing.expectEqual(@as(u16, 25), rect_end.y);
}

test "ExpandTransition - collapse width (horizontal shrink)" {
    const start_rect = Rect.new(10, 10, 100, 20); // Full width
    const end_rect = Rect.new(10, 10, 0, 20);     // Zero width

    var collapse = ExpandTransition.collapseWidth(start_rect, end_rect, 1000, animation.linear);
    collapse.begin(0);

    // At start: width should be 100
    const rect_start = collapse.update(0);
    try testing.expectEqual(@as(u16, 100), rect_start.width);

    // At 50%: width should be 50
    const rect_mid = collapse.update(500);
    try testing.expectEqual(@as(u16, 50), rect_mid.width);

    // At 100%: width should be 0
    const rect_end = collapse.update(1000);
    try testing.expectEqual(@as(u16, 0), rect_end.width);
}

test "ExpandTransition - collapse height (vertical shrink)" {
    const start_rect = Rect.new(10, 10, 50, 60);  // Full height
    const end_rect = Rect.new(10, 10, 50, 0);     // Zero height

    var collapse = ExpandTransition.collapseHeight(start_rect, end_rect, 1000, animation.linear);
    collapse.begin(0);

    // At start: height should be 60
    const rect_start = collapse.update(0);
    try testing.expectEqual(@as(u16, 60), rect_start.height);

    // At 50%: height should be 30
    const rect_mid = collapse.update(500);
    try testing.expectEqual(@as(u16, 30), rect_mid.height);

    // At 100%: height should be 0
    const rect_end = collapse.update(1000);
    try testing.expectEqual(@as(u16, 0), rect_end.height);
}

test "ExpandTransition - collapse both dimensions" {
    const start_rect = Rect.new(25, 25, 50, 50);  // Square
    const end_rect = Rect.new(25, 25, 0, 0);      // Point

    var collapse = ExpandTransition.collapse(start_rect, end_rect, 1000, animation.linear);
    collapse.begin(0);

    // At start: should be 50x50
    const rect_start = collapse.update(0);
    try testing.expectEqual(@as(u16, 50), rect_start.width);
    try testing.expectEqual(@as(u16, 50), rect_start.height);

    // At 50%: should be 25x25
    const rect_mid = collapse.update(500);
    try testing.expectEqual(@as(u16, 25), rect_mid.width);
    try testing.expectEqual(@as(u16, 25), rect_mid.height);

    // At 100%: should be a point
    const rect_end = collapse.update(1000);
    try testing.expectEqual(@as(u16, 0), rect_end.width);
    try testing.expectEqual(@as(u16, 0), rect_end.height);
}

test "ExpandTransition - easing curves for organic feel" {
    const start_rect = Rect.new(10, 10, 0, 0);
    const end_rect = Rect.new(10, 10, 100, 100);

    var expand_linear = ExpandTransition.expand(start_rect, end_rect, 1000, animation.linear);
    var expand_easeOut = ExpandTransition.expand(start_rect, end_rect, 1000, animation.easeOutCubic);

    expand_linear.begin(0);
    expand_easeOut.begin(0);

    // At 50% time
    const rect_linear = expand_linear.update(500);
    const rect_easeOut = expand_easeOut.update(500);

    // Linear should be exactly 50x50
    try testing.expectEqual(@as(u16, 50), rect_linear.width);
    try testing.expectEqual(@as(u16, 50), rect_linear.height);

    // Ease-out cubic should be larger (faster growth at start)
    try testing.expect(rect_easeOut.width > 50);
    try testing.expect(rect_easeOut.height > 50);
}

test "ExpandTransition - zero-sized start/end" {
    const rect = Rect.new(10, 10, 0, 0);

    var expand = ExpandTransition.expand(rect, rect, 1000, animation.linear);
    expand.begin(0);

    // At any time: should remain zero-sized
    const rect_start = expand.update(0);
    const rect_mid = expand.update(500);
    const rect_end = expand.update(1000);

    try testing.expectEqual(@as(u16, 0), rect_start.width);
    try testing.expectEqual(@as(u16, 0), rect_mid.width);
    try testing.expectEqual(@as(u16, 0), rect_end.width);

    try testing.expectEqual(@as(u16, 0), rect_start.height);
    try testing.expectEqual(@as(u16, 0), rect_mid.height);
    try testing.expectEqual(@as(u16, 0), rect_end.height);
}

// ============================================================================
// Transition Composition Tests (6 tests)
// ============================================================================

test "Composition - fade + slide combined (slide in while fading)" {
    // Fade from transparent to opaque
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    // Slide from top to center
    const start_rect = Rect.new(40, 0, 20, 10);
    const end_rect = Rect.new(40, 30, 20, 10);
    var slide = SlideTransition.slideIn(.top, start_rect, end_rect, 1000, animation.linear);

    fade.begin(0);
    slide.begin(0);

    // At 50%: should be half-transparent and half-way down
    const opacity_mid = fade.update(500);
    const rect_mid = slide.update(500);

    try testing.expectEqual(@as(f32, 0.5), opacity_mid);
    try testing.expectEqual(@as(u16, 15), rect_mid.y);

    // At 100%: should be fully opaque and at final position
    const opacity_end = fade.update(1000);
    const rect_end = slide.update(1000);

    try testing.expectEqual(@as(f32, 1.0), opacity_end);
    try testing.expectEqual(@as(u16, 30), rect_end.y);
}

test "Composition - slide + expand combined (growing while moving)" {
    // Slide from left
    const slide_start = Rect.new(0, 30, 10, 10);   // Small, at left
    const slide_end = Rect.new(50, 30, 10, 10);    // Same size, at center
    var slide = SlideTransition.slideIn(.left, slide_start, slide_end, 1000, animation.linear);

    // Expand size
    const expand_start = Rect.new(0, 30, 10, 10);  // Small
    const expand_end = Rect.new(0, 30, 50, 50);    // Large
    var expand = ExpandTransition.expand(expand_start, expand_end, 1000, animation.linear);

    slide.begin(0);
    expand.begin(0);

    // At 50%: halfway in position and size
    const slide_mid = slide.update(500);
    const expand_mid = expand.update(500);

    try testing.expectEqual(@as(u16, 25), slide_mid.x); // X: 0→50, mid=25
    try testing.expectEqual(@as(u16, 30), expand_mid.width);  // W: 10→50, mid=30
    try testing.expectEqual(@as(u16, 30), expand_mid.height); // H: 10→50, mid=30

    // Combined effect: widget slides while growing
    // (Application layer would combine these rect updates)
}

test "Composition - sequential transitions (fade then slide)" {
    var fade = FadeTransition.fadeIn(500, animation.linear);

    const start_rect = Rect.new(40, 0, 20, 10);
    const end_rect = Rect.new(40, 30, 20, 10);
    var slide = SlideTransition.slideIn(.top, start_rect, end_rect, 500, animation.linear);

    // First phase: fade only (0-500ms)
    fade.begin(0);

    const opacity_mid_phase1 = fade.update(250);
    try testing.expectEqual(@as(f32, 0.5), opacity_mid_phase1);

    const opacity_end_phase1 = fade.update(500);
    try testing.expectEqual(@as(f32, 1.0), opacity_end_phase1);
    try testing.expect(fade.isComplete());

    // Second phase: slide only (500-1000ms)
    slide.begin(500);

    const rect_start_phase2 = slide.update(500);
    try testing.expectEqual(@as(u16, 0), rect_start_phase2.y);

    const rect_mid_phase2 = slide.update(750);
    try testing.expectEqual(@as(u16, 15), rect_mid_phase2.y);

    const rect_end_phase2 = slide.update(1000);
    try testing.expectEqual(@as(u16, 30), rect_end_phase2.y);
    try testing.expect(slide.isComplete());
}

test "Composition - parallel transitions (multiple effects at once)" {
    // Three simultaneous effects:
    // 1. Fade in
    var fade = FadeTransition.fadeIn(1000, animation.linear);

    // 2. Slide from left
    const slide_start = Rect.new(0, 25, 20, 10);
    const slide_end = Rect.new(50, 25, 20, 10);
    var slide = SlideTransition.slideIn(.left, slide_start, slide_end, 1000, animation.linear);

    // 3. Expand size
    const expand_start = Rect.new(0, 25, 20, 10);
    const expand_end = Rect.new(0, 25, 60, 30);
    var expand = ExpandTransition.expand(expand_start, expand_end, 1000, animation.linear);

    fade.begin(0);
    slide.begin(0);
    expand.begin(0);

    // At 50%: all three should be halfway
    const opacity_mid = fade.update(500);
    const slide_mid = slide.update(500);
    const expand_mid = expand.update(500);

    try testing.expectEqual(@as(f32, 0.5), opacity_mid);
    try testing.expectEqual(@as(u16, 25), slide_mid.x);
    try testing.expectEqual(@as(u16, 40), expand_mid.width);  // 20→60, mid=40
    try testing.expectEqual(@as(u16, 20), expand_mid.height); // 10→30, mid=20
}

test "Composition - custom easing per transition type" {
    // Fast fade (ease-in), slow slide (ease-out)
    var fade = FadeTransition.fadeIn(1000, animation.easeInCubic);

    const start_rect = Rect.new(0, 25, 20, 10);
    const end_rect = Rect.new(100, 25, 20, 10);
    var slide = SlideTransition.slideIn(.left, start_rect, end_rect, 1000, animation.easeOutCubic);

    fade.begin(0);
    slide.begin(0);

    // At 50% time, ease-in-cubic should be slower, ease-out-cubic faster
    const opacity_mid = fade.update(500);
    const slide_mid = slide.update(500);

    // Ease-in-cubic at t=0.5 should be < 0.5 (slower)
    try testing.expect(opacity_mid < 0.5);

    // Ease-out-cubic at t=0.5 should result in X > 50 (faster)
    try testing.expect(slide_mid.x > 50);
}

test "Composition - complex multi-stage transition" {
    // Stage 1 (0-300ms): Fade in only
    var fade = FadeTransition.fadeIn(300, animation.linear);

    // Stage 2 (300-700ms): Slide while maintaining opacity
    const slide_start = Rect.new(0, 25, 20, 10);
    const slide_end = Rect.new(50, 25, 20, 10);
    var slide = SlideTransition.slideIn(.left, slide_start, slide_end, 400, animation.linear);

    // Stage 3 (700-1000ms): Expand while maintaining position and opacity
    const expand_start = Rect.new(50, 25, 20, 10);
    const expand_end = Rect.new(50, 25, 50, 30);
    var expand = ExpandTransition.expand(expand_start, expand_end, 300, animation.linear);

    // Stage 1: Fade in (0-300ms)
    fade.begin(0);
    const opacity_stage1_mid = fade.update(150);
    try testing.expectEqual(@as(f32, 0.5), opacity_stage1_mid);

    const opacity_stage1_end = fade.update(300);
    try testing.expectEqual(@as(f32, 1.0), opacity_stage1_end);
    try testing.expect(fade.isComplete());

    // Stage 2: Slide (300-700ms)
    slide.begin(300);
    const slide_stage2_mid = slide.update(500); // 200ms elapsed
    try testing.expectEqual(@as(u16, 25), slide_stage2_mid.x); // Halfway: 0→50, 200/400=0.5

    const slide_stage2_end = slide.update(700);
    try testing.expectEqual(@as(u16, 50), slide_stage2_end.x);
    try testing.expect(slide.isComplete());

    // Stage 3: Expand (700-1000ms)
    expand.begin(700);
    const expand_stage3_mid = expand.update(850); // 150ms elapsed
    try testing.expectEqual(@as(u16, 35), expand_stage3_mid.width);  // 20→50, 150/300=0.5
    try testing.expectEqual(@as(u16, 20), expand_stage3_mid.height); // 10→30, 150/300=0.5

    const expand_stage3_end = expand.update(1000);
    try testing.expectEqual(@as(u16, 50), expand_stage3_end.width);
    try testing.expectEqual(@as(u16, 30), expand_stage3_end.height);
    try testing.expect(expand.isComplete());
}

// ============================================================================
// Integration with Rect/Layout Tests (4 tests)
// ============================================================================

test "Integration - Rect position interpolation for slides" {
    // Test that slide transitions properly interpolate Rect position fields
    const start = Rect.new(10, 20, 30, 40);
    const end = Rect.new(50, 60, 30, 40);

    var slide = SlideTransition.init(start, end, 1000, animation.linear);
    slide.begin(0);

    // Verify linear interpolation of position
    const positions = [_]struct { time: u64, x: u16, y: u16 }{
        .{ .time = 0, .x = 10, .y = 20 },
        .{ .time = 250, .x = 20, .y = 30 },
        .{ .time = 500, .x = 30, .y = 40 },
        .{ .time = 750, .x = 40, .y = 50 },
        .{ .time = 1000, .x = 50, .y = 60 },
    };

    for (positions) |pos| {
        const rect = slide.update(pos.time);
        try testing.expectEqual(pos.x, rect.x);
        try testing.expectEqual(pos.y, rect.y);
    }
}

test "Integration - Rect size interpolation for expand/collapse" {
    // Test that expand/collapse transitions properly interpolate Rect size fields
    const start = Rect.new(25, 25, 10, 10);
    const end = Rect.new(25, 25, 100, 100);

    var expand = ExpandTransition.expand(start, end, 1000, animation.linear);
    expand.begin(0);

    // Verify linear interpolation of size
    const sizes = [_]struct { time: u64, w: u16, h: u16 }{
        .{ .time = 0, .w = 10, .h = 10 },
        .{ .time = 250, .w = 32, .h = 32 },   // 10 + (100-10)*0.25 = 32.5 → 32
        .{ .time = 500, .w = 55, .h = 55 },   // 10 + (100-10)*0.5 = 55
        .{ .time = 750, .w = 77, .h = 77 },   // 10 + (100-10)*0.75 = 77.5 → 77
        .{ .time = 1000, .w = 100, .h = 100 },
    };

    for (sizes) |size| {
        const rect = expand.update(size.time);
        try testing.expectEqual(size.w, rect.width);
        try testing.expectEqual(size.h, rect.height);
    }
}

test "Integration - clipping to parent bounds during transitions" {
    // Simulate a widget sliding into view within a parent container
    const parent = Rect.new(0, 0, 80, 24); // Terminal area

    // Widget slides from above (off-screen) into view
    const start = Rect.new(10, 0, 60, 10);  // Top edge at Y=0 (partially visible)
    const end = Rect.new(10, 7, 60, 10);    // Fully visible at Y=7

    var slide = SlideTransition.slideIn(.top, start, end, 1000, animation.linear);
    slide.begin(0);

    // At each frame, check if widget rect intersects parent
    const times = [_]u64{ 0, 250, 500, 750, 1000 };

    for (times) |time| {
        const widget_rect = slide.update(time);

        // Widget should always be within or intersecting parent bounds
        const clipped = parent.intersection(widget_rect);
        try testing.expect(clipped != null); // Should intersect at all times

        // At end, widget should be fully within parent
        if (time == 1000) {
            const final_clipped = clipped.?;
            try testing.expectEqual(@as(u16, 60), final_clipped.width);  // Full width visible
            try testing.expectEqual(@as(u16, 10), final_clipped.height); // Full height visible
        }
    }
}

test "Integration - full-screen widget transitions" {
    // Test transition of a widget that occupies the full terminal
    const small = Rect.new(30, 10, 20, 4);   // Small widget in center
    const fullscreen = Rect.new(0, 0, 80, 24); // Full terminal

    var expand = ExpandTransition.expand(small, fullscreen, 500, animation.easeOutCubic);
    expand.begin(0);

    // At start: small
    const rect_start = expand.update(0);
    try testing.expectEqual(@as(u16, 30), rect_start.x);
    try testing.expectEqual(@as(u16, 10), rect_start.y);
    try testing.expectEqual(@as(u16, 20), rect_start.width);
    try testing.expectEqual(@as(u16, 4), rect_start.height);

    // At end: fullscreen
    const rect_end = expand.update(500);
    try testing.expectEqual(@as(u16, 0), rect_end.x);
    try testing.expectEqual(@as(u16, 0), rect_end.y);
    try testing.expectEqual(@as(u16, 80), rect_end.width);
    try testing.expectEqual(@as(u16, 24), rect_end.height);

    // Verify area growth
    try testing.expectEqual(@as(u32, 80), rect_start.area());   // 20*4
    try testing.expectEqual(@as(u32, 1920), rect_end.area());   // 80*24
}
