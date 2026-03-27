//! Comprehensive tests for sailor's timer system (v1.24.0 item 3/5)
//!
//! Tests the timer framework for async animation scheduling:
//! - Basic timer operations (one-shot, repeating, expiration)
//! - Callback execution with context passing
//! - Animation integration (scheduling transitions and effects)
//! - Time management (delta accumulation, precision, overflow protection)
//! - Timer pool/manager for multiple concurrent timers
//!
//! This timer system enables time-based event triggering for UI updates,
//! animation scheduling, and complex animation timelines.

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

// Timer types (will be implemented)
const Timer = sailor.tui.timer.Timer;
const TimerManager = sailor.tui.timer.TimerManager;
const TimerCallback = sailor.tui.timer.TimerCallback;

// Animation integration
const animation = sailor.tui.animation;
const transition = sailor.tui.transition;
const Animation = animation.Animation;
const FadeTransition = transition.FadeTransition;
const SlideTransition = transition.SlideTransition;
const Rect = sailor.tui.Rect;

// ============================================================================
// Basic Timer Operations Tests (6 tests)
// ============================================================================

test "Timer - create one-shot timer with delay" {
    var timer = Timer.oneShot(500); // 500ms delay

    // Initial state: not expired
    try testing.expect(!timer.isExpired());
    try testing.expectEqual(@as(u64, 500), timer.delay_ms);
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);
    try testing.expectEqual(@as(bool, false), timer.repeating);
}

test "Timer - create repeating timer with interval" {
    var timer = Timer.interval(200); // 200ms interval

    // Initial state: not expired, repeating flag set
    try testing.expect(!timer.isExpired());
    try testing.expectEqual(@as(u64, 200), timer.delay_ms);
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);
    try testing.expectEqual(@as(bool, true), timer.repeating);
}

test "Timer - expiration check after elapsed time" {
    var timer = Timer.oneShot(500);

    // Before delay: not expired
    timer.update(250);
    try testing.expect(!timer.isExpired());
    try testing.expectEqual(@as(u64, 250), timer.elapsed_ms);

    // At exact delay: expired
    timer.update(250);
    try testing.expect(timer.isExpired());
    try testing.expectEqual(@as(u64, 500), timer.elapsed_ms);
}

test "Timer - cancellation" {
    var timer = Timer.oneShot(500);

    // Update partway
    timer.update(300);
    try testing.expect(!timer.isExpired());

    // Cancel
    timer.cancel();
    try testing.expect(timer.isCancelled());

    // Further updates don't affect cancelled timer
    timer.update(500);
    try testing.expect(!timer.isExpired());
    try testing.expect(timer.isCancelled());
}

test "Timer - reset and restart" {
    var timer = Timer.oneShot(500);

    // Complete the timer
    timer.update(500);
    try testing.expect(timer.isExpired());

    // Reset
    timer.reset();
    try testing.expect(!timer.isExpired());
    try testing.expect(!timer.isCancelled());
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);

    // Can run again
    timer.update(250);
    try testing.expectEqual(@as(u64, 250), timer.elapsed_ms);
    try testing.expect(!timer.isExpired());
}

test "Timer - multiple independent timers" {
    var timer1 = Timer.oneShot(300);
    var timer2 = Timer.oneShot(500);
    var timer3 = Timer.interval(200);

    // Update all by 250ms
    timer1.update(250);
    timer2.update(250);
    timer3.update(250);

    // timer1: 250/300 (not expired)
    try testing.expect(!timer1.isExpired());
    try testing.expectEqual(@as(u64, 250), timer1.elapsed_ms);

    // timer2: 250/500 (not expired)
    try testing.expect(!timer2.isExpired());
    try testing.expectEqual(@as(u64, 250), timer2.elapsed_ms);

    // timer3: 250/200 → fired and reset to 50/200 (repeating, not expired in current cycle)
    try testing.expect(!timer3.isExpired());
    try testing.expectEqual(@as(u64, 50), timer3.elapsed_ms);

    // Update all by another 100ms
    timer1.update(100);
    timer2.update(100);
    timer3.update(100);

    // timer1: 350/300 (now expired)
    try testing.expect(timer1.isExpired());

    // timer2: 350/500 (still not expired)
    try testing.expect(!timer2.isExpired());
}

// ============================================================================
// Callback Execution Tests (6 tests)
// ============================================================================

test "Callback - one-shot callback fires once at correct time" {
    const CallbackContext = struct {
        fired_count: u32 = 0,
        last_elapsed: u64 = 0,

        fn callback(ctx: *anyopaque, elapsed_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.fired_count += 1;
            self.last_elapsed = elapsed_ms;
        }
    };

    var ctx = CallbackContext{};
    var timer = Timer.oneShotWithCallback(500, CallbackContext.callback, &ctx);

    // Before delay: callback not fired
    timer.update(250);
    try testing.expectEqual(@as(u32, 0), ctx.fired_count);

    // At delay: callback fires
    timer.update(250);
    try testing.expectEqual(@as(u32, 1), ctx.fired_count);
    try testing.expectEqual(@as(u64, 500), ctx.last_elapsed);

    // Further updates don't fire callback again
    timer.update(100);
    try testing.expectEqual(@as(u32, 1), ctx.fired_count);
}

test "Callback - repeating callback fires multiple times" {
    const CallbackContext = struct {
        fired_count: u32 = 0,
        elapsed_times: [5]u64 = [_]u64{0} ** 5,

        fn callback(ctx: *anyopaque, elapsed_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (self.fired_count < 5) {
                self.elapsed_times[self.fired_count] = elapsed_ms;
            }
            self.fired_count += 1;
        }
    };

    var ctx = CallbackContext{};
    var timer = Timer.intervalWithCallback(200, CallbackContext.callback, &ctx);

    // First fire at 200ms
    timer.update(200);
    try testing.expectEqual(@as(u32, 1), ctx.fired_count);
    try testing.expectEqual(@as(u64, 200), ctx.elapsed_times[0]);

    // Second fire at 400ms (200ms since reset)
    timer.update(200);
    try testing.expectEqual(@as(u32, 2), ctx.fired_count);

    // Third fire at 600ms
    timer.update(200);
    try testing.expectEqual(@as(u32, 3), ctx.fired_count);

    // Verify repeating timers reset after firing
    try testing.expect(!timer.isExpired()); // Should be running again
}

test "Callback - callback receives correct elapsed time" {
    const CallbackContext = struct {
        captured_elapsed: u64 = 0,

        fn callback(ctx: *anyopaque, elapsed_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.captured_elapsed = elapsed_ms;
        }
    };

    var ctx = CallbackContext{};
    var timer = Timer.oneShotWithCallback(750, CallbackContext.callback, &ctx);

    timer.update(750);
    try testing.expectEqual(@as(u64, 750), ctx.captured_elapsed);
}

test "Callback - context state passing between fires" {
    const CallbackContext = struct {
        counter: i32 = 0,

        fn callback(ctx: *anyopaque, _: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.counter += 10;
        }
    };

    var ctx = CallbackContext{};
    var timer = Timer.intervalWithCallback(100, CallbackContext.callback, &ctx);

    // Fire 5 times
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        timer.update(100);
    }

    try testing.expectEqual(@as(i32, 50), ctx.counter); // 10 * 5
}

test "Callback - multiple callbacks with different delays" {
    const CallbackContext = struct {
        id: u8,
        fired: bool = false,

        fn callback(ctx: *anyopaque, _: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.fired = true;
        }
    };

    var ctx1 = CallbackContext{ .id = 1 };
    var ctx2 = CallbackContext{ .id = 2 };
    var ctx3 = CallbackContext{ .id = 3 };

    var timer1 = Timer.oneShotWithCallback(100, CallbackContext.callback, &ctx1);
    var timer2 = Timer.oneShotWithCallback(300, CallbackContext.callback, &ctx2);
    var timer3 = Timer.oneShotWithCallback(500, CallbackContext.callback, &ctx3);

    // Update to 250ms
    timer1.update(250);
    timer2.update(250);
    timer3.update(250);

    // Only timer1 should have fired
    try testing.expect(ctx1.fired);
    try testing.expect(!ctx2.fired);
    try testing.expect(!ctx3.fired);

    // Update to 600ms total
    timer2.update(350);
    timer3.update(350);

    // All should have fired
    try testing.expect(ctx2.fired);
    try testing.expect(ctx3.fired);
}

test "Callback - error in callback doesn't crash timer" {
    const CallbackContext = struct {
        fn callback(_: *anyopaque, _: u64) void {
            // Simulate a callback that might have issues but doesn't crash
            // In real code, errors would be handled gracefully
            _ = 1 + 1; // Dummy operation
        }
    };

    var ctx: u32 = 0;
    var timer = Timer.oneShotWithCallback(100, CallbackContext.callback, &ctx);

    // Should not crash even if callback has issues
    timer.update(100);
    try testing.expect(timer.isExpired());
}

// ============================================================================
// Animation Integration Tests (6 tests)
// ============================================================================

test "Animation integration - schedule animation start via timer" {
    const AnimContext = struct {
        anim: Animation,
        started: bool = false,

        fn startAnimation(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.anim.begin(time_ms);
            self.started = true;
        }
    };

    var ctx = AnimContext{
        .anim = Animation.init(0.0, 100.0, 1000, animation.linear),
    };

    var timer = Timer.oneShotWithCallback(500, AnimContext.startAnimation, &ctx);

    // Before timer fires: animation not started
    timer.update(250);
    try testing.expect(!ctx.started);

    // Timer fires: animation starts
    timer.update(250);
    try testing.expect(ctx.started);
    try testing.expectEqual(@as(u64, 500), ctx.anim.start_time_ms);
}

test "Animation integration - chain animations sequentially with timer delays" {
    const ChainContext = struct {
        anim1: Animation,
        anim2: Animation,
        timer1: Timer,
        timer2: Timer,
        phase: u8 = 0,

        fn startPhase1(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.anim1.begin(time_ms);
            self.phase = 1;
        }

        fn startPhase2(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.anim2.begin(time_ms);
            self.phase = 2;
        }
    };

    var ctx = ChainContext{
        .anim1 = Animation.init(0.0, 50.0, 500, animation.linear),
        .anim2 = Animation.init(50.0, 100.0, 500, animation.linear),
        .timer1 = Timer.oneShotWithCallback(0, ChainContext.startPhase1, undefined),
        .timer2 = Timer.oneShotWithCallback(600, ChainContext.startPhase2, undefined),
    };

    // Fix self-references
    ctx.timer1.callback_context = &ctx;
    ctx.timer2.callback_context = &ctx;

    // Phase 1 starts immediately
    ctx.timer1.update(0);
    try testing.expectEqual(@as(u8, 1), ctx.phase);

    // Phase 2 starts after 600ms delay
    ctx.timer2.update(600);
    try testing.expectEqual(@as(u8, 2), ctx.phase);
}

test "Animation integration - schedule fade effect after delay" {
    const FadeContext = struct {
        fade: FadeTransition,
        triggered: bool = false,

        fn triggerFade(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.fade.begin(time_ms);
            self.triggered = true;
        }
    };

    var ctx = FadeContext{
        .fade = FadeTransition.fadeIn(1000, animation.easeOut),
    };

    var timer = Timer.oneShotWithCallback(300, FadeContext.triggerFade, &ctx);

    // Wait 300ms
    timer.update(300);
    try testing.expect(ctx.triggered);

    // Fade animation should now be running
    const opacity = ctx.fade.update(800); // 500ms into fade (800-300)
    try testing.expect(opacity > 0.0);
    try testing.expect(opacity < 1.0);
}

test "Animation integration - schedule slide transition on interval" {
    const SlideContext = struct {
        slide: SlideTransition,
        fire_count: u32 = 0,

        fn triggerSlide(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.slide.begin(time_ms);
            self.fire_count += 1;
        }
    };

    const start_rect = Rect.new(0, 10, 50, 20);
    const end_rect = Rect.new(40, 10, 50, 20);

    var ctx = SlideContext{
        .slide = SlideTransition.slideIn(.left, start_rect, end_rect, 200, animation.linear),
    };

    var timer = Timer.intervalWithCallback(500, SlideContext.triggerSlide, &ctx);

    // First trigger at 500ms
    timer.update(500);
    try testing.expectEqual(@as(u32, 1), ctx.fire_count);

    // Second trigger at 1000ms
    timer.update(500);
    try testing.expectEqual(@as(u32, 2), ctx.fire_count);
}

test "Animation integration - cancel scheduled animation before it starts" {
    const AnimContext = struct {
        anim: Animation,
        started: bool = false,

        fn startAnimation(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.anim.begin(time_ms);
            self.started = true;
        }
    };

    var ctx = AnimContext{
        .anim = Animation.init(0.0, 100.0, 1000, animation.linear),
    };

    var timer = Timer.oneShotWithCallback(500, AnimContext.startAnimation, &ctx);

    // Cancel before timer fires
    timer.update(250);
    timer.cancel();
    try testing.expect(!ctx.started);

    // Continue updating (should not fire)
    timer.update(500);
    try testing.expect(!ctx.started);
}

test "Animation integration - complex timeline with multiple animations at different start times" {
    const TimelineContext = struct {
        fade: FadeTransition,
        slide: SlideTransition,
        fade_started: bool = false,
        slide_started: bool = false,

        fn startFade(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.fade.begin(time_ms);
            self.fade_started = true;
        }

        fn startSlide(ctx: *anyopaque, time_ms: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.slide.begin(time_ms);
            self.slide_started = true;
        }
    };

    var ctx = TimelineContext{
        .fade = FadeTransition.fadeIn(500, animation.linear),
        .slide = SlideTransition.slideIn(.top, Rect.new(40, 0, 20, 10), Rect.new(40, 30, 20, 10), 500, animation.linear),
    };

    var timer_fade = Timer.oneShotWithCallback(0, TimelineContext.startFade, &ctx);
    var timer_slide = Timer.oneShotWithCallback(300, TimelineContext.startSlide, &ctx);

    // Fade starts immediately
    timer_fade.update(0);
    try testing.expect(ctx.fade_started);
    try testing.expect(!ctx.slide_started);

    // Slide starts at 300ms
    timer_slide.update(300);
    try testing.expect(ctx.slide_started);

    // Both animations running at 400ms
    const opacity = ctx.fade.update(400);
    const rect = ctx.slide.update(400);

    // Fade is 400/500 = 80% complete
    try testing.expectApproxEqRel(@as(f32, 0.8), opacity, 0.01);

    // Slide is 100/500 = 20% complete (400ms - 300ms start)
    try testing.expectEqual(@as(u16, 6), rect.y); // 0 + (30-0)*0.2 = 6
}

// ============================================================================
// Time Management Tests (6 tests)
// ============================================================================

test "Time management - delta time accumulation frame-by-frame" {
    var timer = Timer.oneShot(1000);

    // Simulate frame updates at varying delta times
    timer.update(16); // ~60fps
    try testing.expectEqual(@as(u64, 16), timer.elapsed_ms);

    timer.update(17);
    try testing.expectEqual(@as(u64, 33), timer.elapsed_ms);

    timer.update(16);
    try testing.expectEqual(@as(u64, 49), timer.elapsed_ms);

    timer.update(18);
    try testing.expectEqual(@as(u64, 67), timer.elapsed_ms);
}

test "Time management - timer precision (accurate delay timing)" {
    const delays = [_]u64{ 10, 50, 100, 500, 1000, 5000 };

    for (delays) |delay| {
        var timer = Timer.oneShot(delay);

        // Should not expire before delay
        timer.update(delay -| 1);
        try testing.expect(!timer.isExpired());

        // Should expire at exact delay
        timer.update(1);
        try testing.expect(timer.isExpired());
        try testing.expectEqual(delay, timer.elapsed_ms);
    }
}

test "Time management - overflow protection with very large delays" {
    // Use a large but realistic delay (1 billion ms ≈ 11.5 days)
    // This is large enough to test overflow protection but small enough
    // to avoid float precision issues in time scaling
    const large_delay: u64 = 1_000_000_000;
    var timer = Timer.oneShot(large_delay);

    // Should handle large delays without overflow
    timer.update(1000);
    try testing.expectEqual(@as(u64, 1000), timer.elapsed_ms);
    try testing.expect(!timer.isExpired());

    // Update with remaining time
    timer.update(large_delay - 1000);
    try testing.expect(timer.isExpired());
}

test "Time management - negative/zero delta time handling" {
    var timer = Timer.oneShot(500);

    // Zero delta should be harmless
    timer.update(0);
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);

    // Normal update
    timer.update(250);
    try testing.expectEqual(@as(u64, 250), timer.elapsed_ms);

    // Another zero delta
    timer.update(0);
    try testing.expectEqual(@as(u64, 250), timer.elapsed_ms);
}

test "Time management - paused timers (skip updates)" {
    var timer = Timer.oneShot(500);

    timer.update(250);
    try testing.expectEqual(@as(u64, 250), timer.elapsed_ms);

    // Pause
    timer.pause();
    try testing.expect(timer.isPaused());

    // Updates while paused don't accumulate
    timer.update(100);
    try testing.expectEqual(@as(u64, 250), timer.elapsed_ms);

    timer.update(200);
    try testing.expectEqual(@as(u64, 250), timer.elapsed_ms);

    // Resume
    timer.unpause();
    try testing.expect(!timer.isPaused());

    // Updates now accumulate again
    timer.update(100);
    try testing.expectEqual(@as(u64, 350), timer.elapsed_ms);
}

test "Time management - time scaling for slow-motion and fast-forward" {
    var timer = Timer.oneShot(1000);

    // Set time scale to 0.5 (slow-motion, half speed)
    timer.setTimeScale(0.5);

    timer.update(200); // Actual elapsed = 200 * 0.5 = 100ms
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);

    timer.update(400); // Actual elapsed = 100 + 400*0.5 = 300ms
    try testing.expectEqual(@as(u64, 300), timer.elapsed_ms);

    // Set time scale to 2.0 (fast-forward, double speed)
    timer.setTimeScale(2.0);

    timer.update(200); // Actual elapsed = 300 + 200*2.0 = 700ms
    try testing.expectEqual(@as(u64, 700), timer.elapsed_ms);

    timer.update(200); // Actual elapsed = 700 + 200*2.0 = 1100ms (expired)
    try testing.expect(timer.isExpired());
}

// ============================================================================
// Timer Pool/Manager Tests (6 tests)
// ============================================================================

test "Timer pool - add multiple timers to pool" {
    const allocator = testing.allocator;
    var manager = TimerManager.init(allocator);
    defer manager.deinit();

    // Add 3 timers with different delays
    const timer1_id = try manager.addTimer(Timer.oneShot(100));
    const timer2_id = try manager.addTimer(Timer.oneShot(300));
    const timer3_id = try manager.addTimer(Timer.interval(200));

    // Verify timer count
    try testing.expectEqual(@as(usize, 3), manager.activeCount());

    // Verify IDs are unique
    try testing.expect(timer1_id != timer2_id);
    try testing.expect(timer2_id != timer3_id);
    try testing.expect(timer1_id != timer3_id);
}

test "Timer pool - update all timers with single update call" {
    const allocator = testing.allocator;
    var manager = TimerManager.init(allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShot(100));
    _ = try manager.addTimer(Timer.oneShot(300));
    _ = try manager.addTimer(Timer.oneShot(500));

    // Update all timers by 250ms
    try manager.updateAll(250);

    // First timer should be expired
    try testing.expect(manager.isExpired(0));

    // Second and third timers should not be expired
    try testing.expect(!manager.isExpired(1));
    try testing.expect(!manager.isExpired(2));
}

test "Timer pool - remove completed timers automatically" {
    const allocator = testing.allocator;
    var manager = TimerManager.init(allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShot(100));
    _ = try manager.addTimer(Timer.oneShot(200));
    _ = try manager.addTimer(Timer.oneShot(300));

    try testing.expectEqual(@as(usize, 3), manager.activeCount());

    // Update to expire first timer
    try manager.updateAll(150);
    manager.removeCompleted();

    try testing.expectEqual(@as(usize, 2), manager.activeCount());

    // Update to expire second timer
    try manager.updateAll(100);
    manager.removeCompleted();

    try testing.expectEqual(@as(usize, 1), manager.activeCount());

    // Update to expire third timer
    try manager.updateAll(100);
    manager.removeCompleted();

    try testing.expectEqual(@as(usize, 0), manager.activeCount());
}

test "Timer pool - query active timer count" {
    const allocator = testing.allocator;
    var manager = TimerManager.init(allocator);
    defer manager.deinit();

    try testing.expectEqual(@as(usize, 0), manager.activeCount());

    _ = try manager.addTimer(Timer.oneShot(100));
    try testing.expectEqual(@as(usize, 1), manager.activeCount());

    _ = try manager.addTimer(Timer.oneShot(200));
    try testing.expectEqual(@as(usize, 2), manager.activeCount());

    _ = try manager.addTimer(Timer.oneShot(300));
    try testing.expectEqual(@as(usize, 3), manager.activeCount());

    // Cancel one timer
    manager.cancelTimer(1);
    manager.removeCompleted();
    try testing.expectEqual(@as(usize, 2), manager.activeCount());
}

test "Timer pool - priority ordering (earliest fires first)" {
    const PriorityContext = struct {
        fire_order: [3]u8 = [_]u8{0} ** 3,
        fire_index: u8 = 0,
    };

    const Callback1 = struct {
        fn callback(ctx: *anyopaque, _: u64) void {
            const self: *PriorityContext = @ptrCast(@alignCast(ctx));
            self.fire_order[self.fire_index] = 1;
            self.fire_index += 1;
        }
    };

    const Callback2 = struct {
        fn callback(ctx: *anyopaque, _: u64) void {
            const self: *PriorityContext = @ptrCast(@alignCast(ctx));
            self.fire_order[self.fire_index] = 2;
            self.fire_index += 1;
        }
    };

    const Callback3 = struct {
        fn callback(ctx: *anyopaque, _: u64) void {
            const self: *PriorityContext = @ptrCast(@alignCast(ctx));
            self.fire_order[self.fire_index] = 3;
            self.fire_index += 1;
        }
    };

    const allocator = testing.allocator;
    var manager = TimerManager.init(allocator);
    defer manager.deinit();

    var ctx = PriorityContext{};

    // Add timers in non-sorted order
    _ = try manager.addTimer(Timer.oneShotWithCallback(300, Callback2.callback, &ctx));
    _ = try manager.addTimer(Timer.oneShotWithCallback(100, Callback1.callback, &ctx));
    _ = try manager.addTimer(Timer.oneShotWithCallback(500, Callback3.callback, &ctx));

    // Update to fire all timers
    try manager.updateAll(600);

    // Verify they fired in delay order (shortest first)
    try testing.expectEqual(@as(u8, 1), ctx.fire_order[0]);
    try testing.expectEqual(@as(u8, 2), ctx.fire_order[1]);
    try testing.expectEqual(@as(u8, 3), ctx.fire_order[2]);
}

test "Timer pool - memory management (no leaks with allocator)" {
    const allocator = testing.allocator;

    // Scope for manager lifetime
    {
        var manager = TimerManager.init(allocator);
        defer manager.deinit();

        // Add many timers
        var i: u32 = 0;
        while (i < 100) : (i += 1) {
            _ = try manager.addTimer(Timer.oneShot(100 + i * 10));
        }

        try testing.expectEqual(@as(usize, 100), manager.activeCount());

        // Update and remove all
        try manager.updateAll(2000);
        manager.removeCompleted();

        try testing.expectEqual(@as(usize, 0), manager.activeCount());
    }

    // No leaks should be detected by testing.allocator
}
