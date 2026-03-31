//! Timer System for Async Animation Scheduling
//!
//! Provides time-based event triggering for UI updates, animation scheduling,
//! and complex animation timelines. Supports one-shot and repeating timers,
//! callbacks with context passing, pause/resume, and time scaling.
//!
//! NOTE: Due to Zig language limitations, the repeating timer factory function
//! is named `interval()` instead of `repeating()` to avoid namespace conflict
//! with the `repeating: bool` field. Tests may need adjustment.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Callback function type for timer expiration events
pub const TimerCallback = *const fn (ctx: *anyopaque, elapsed_ms: u64) void;

/// Individual timer with lifecycle management
pub const Timer = struct {
    delay_ms: u64,
    elapsed_ms: u64 = 0,
    repeating: bool = false,
    cancelled: bool = false,
    paused: bool = false,
    fired: bool = false,
    time_scale: f32 = 1.0,
    callback: ?TimerCallback = null,
    callback_context: ?*anyopaque = null,

    /// Create a one-shot timer that fires once after delay_ms
    pub fn oneShot(delay_ms: u64) Timer {
        return .{
            .delay_ms = delay_ms,
            .repeating = false,
        };
    }

    /// Create a repeating timer that fires every interval_ms
    /// Named `interval` to avoid conflict with `repeating` field
    pub fn interval(interval_ms: u64) Timer {
        return .{
            .delay_ms = interval_ms,
            .repeating = true,
        };
    }

    /// Create a one-shot timer with callback
    pub fn oneShotWithCallback(
        delay_ms: u64,
        cb: TimerCallback,
        context: *anyopaque,
    ) Timer {
        return .{
            .delay_ms = delay_ms,
            .repeating = false,
            .callback = cb,
            .callback_context = context,
        };
    }

    /// Create a repeating timer with callback
    pub fn intervalWithCallback(
        interval_ms: u64,
        cb: TimerCallback,
        context: *anyopaque,
    ) Timer {
        return .{
            .delay_ms = interval_ms,
            .repeating = true,
            .callback = cb,
            .callback_context = context,
        };
    }

    /// Update timer by delta_ms and fire callback if expired
    pub fn update(self: *Timer, delta_ms: u64) void {
        if (self.cancelled or self.paused) return;

        // One-shot timers that have already fired don't update anymore
        if (!self.repeating and self.fired) return;

        // Only use float conversion if time_scale != 1.0 to avoid precision loss
        const scaled_delta = if (self.time_scale == 1.0)
            delta_ms
        else
            @as(u64, @intFromFloat(@as(f32, @floatFromInt(delta_ms)) * self.time_scale));
        self.elapsed_ms += scaled_delta;

        if (self.elapsed_ms >= self.delay_ms) {
            if (self.callback) |cb| {
                if (self.callback_context) |ctx| {
                    cb(ctx, self.elapsed_ms);
                }
            }

            if (self.repeating) {
                self.elapsed_ms = self.elapsed_ms - self.delay_ms;
            } else {
                self.fired = true;
            }
        }
    }

    /// Returns true if the timer has reached its delay threshold (false if cancelled)
    pub fn isExpired(self: Timer) bool {
        if (self.cancelled) return false;
        return self.elapsed_ms >= self.delay_ms;
    }

    /// Returns true if the timer has been cancelled
    pub fn isCancelled(self: Timer) bool {
        return self.cancelled;
    }

    /// Cancels the timer, preventing further updates and callbacks
    pub fn cancel(self: *Timer) void {
        self.cancelled = true;
    }

    /// Resets the timer to its initial state (clears elapsed time, cancelled, paused, and fired flags)
    pub fn reset(self: *Timer) void {
        self.elapsed_ms = 0;
        self.cancelled = false;
        self.paused = false;
        self.fired = false;
    }

    /// Pauses the timer, preventing elapsed time from advancing during updates
    pub fn pause(self: *Timer) void {
        self.paused = true;
    }

    /// Resumes a paused timer, allowing elapsed time to advance again
    pub fn unpause(self: *Timer) void {
        self.paused = false;
    }

    /// Returns true if the timer is currently paused
    pub fn isPaused(self: Timer) bool {
        return self.paused;
    }

    /// Sets the time scale multiplier for this timer (e.g., 0.5 = half speed, 2.0 = double speed)
    pub fn setTimeScale(self: *Timer, scale: f32) void {
        self.time_scale = scale;
    }
};

/// Central pool for managing multiple timers
pub const TimerManager = struct {
    timers: std.ArrayList(Timer),
    allocator: Allocator,

    /// Initializes a new timer manager with the specified allocator
    pub fn init(allocator: Allocator) TimerManager {
        return .{
            .timers = .{},
            .allocator = allocator,
        };
    }

    /// Deinitializes the timer manager and frees all resources
    pub fn deinit(self: *TimerManager) void {
        self.timers.deinit(self.allocator);
    }

    /// Adds a timer to the manager and returns its unique ID
    pub fn addTimer(self: *TimerManager, timer: Timer) !usize {
        const id = self.timers.items.len;
        try self.timers.append(self.allocator, timer);
        return id;
    }

    /// Updates all managed timers by the specified delta, firing callbacks as needed
    pub fn updateAll(self: *TimerManager, delta_ms: u64) !void {
        const Context = struct {
            pub fn lessThan(_: void, a: Timer, b: Timer) bool {
                if (a.cancelled) return false;
                if (b.cancelled) return true;
                const a_remaining = if (a.delay_ms > a.elapsed_ms) a.delay_ms - a.elapsed_ms else 0;
                const b_remaining = if (b.delay_ms > b.elapsed_ms) b.delay_ms - b.elapsed_ms else 0;
                return a_remaining < b_remaining;
            }
        };
        std.mem.sort(Timer, self.timers.items, {}, Context.lessThan);

        for (self.timers.items) |*timer| {
            timer.update(delta_ms);
        }
    }

    /// Removes all cancelled timers and expired one-shot timers from the manager
    pub fn removeCompleted(self: *TimerManager) void {
        var i: usize = 0;
        while (i < self.timers.items.len) {
            const timer = self.timers.items[i];
            if (timer.cancelled or (!timer.repeating and timer.isExpired())) {
                _ = self.timers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Returns the count of active timers (excludes cancelled and expired one-shot timers)
    pub fn activeCount(self: TimerManager) usize {
        var count: usize = 0;
        for (self.timers.items) |timer| {
            if (!timer.cancelled) {
                if (timer.repeating or !timer.isExpired()) {
                    count += 1;
                }
            }
        }
        return count;
    }

    /// Cancels the timer with the specified ID (safe to call with invalid ID)
    pub fn cancelTimer(self: *TimerManager, id: usize) void {
        if (id < self.timers.items.len) {
            self.timers.items[id].cancel();
        }
    }

    /// Returns true if the timer with the specified ID has expired (returns false for invalid ID)
    pub fn isExpired(self: TimerManager, id: usize) bool {
        if (id >= self.timers.items.len) return false;
        return self.timers.items[id].isExpired();
    }

    /// Returns true if the timer with the specified ID has been cancelled (returns false for invalid ID)
    pub fn isCancelled(self: TimerManager, id: usize) bool {
        if (id >= self.timers.items.len) return false;
        return self.timers.items[id].isCancelled();
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

// Helper context for callback tests
const CallbackContext = struct {
    fired_count: u32 = 0,
    last_elapsed_ms: u64 = 0,

    /// Test callback that records fire count and elapsed time.
    pub fn callback(ctx: *anyopaque, elapsed_ms: u64) void {
        const self: *CallbackContext = @ptrCast(@alignCast(ctx));
        self.fired_count += 1;
        self.last_elapsed_ms = elapsed_ms;
    }
};

// ============================================================================
// Timer Tests
// ============================================================================

test "Timer: oneShot fires after exact delay" {
    var timer = Timer.oneShot(100);
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);
    try testing.expect(!timer.fired);

    timer.update(50);
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);
    try testing.expect(!timer.fired);

    timer.update(50);
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);
    try testing.expect(timer.fired);
}

test "Timer: oneShot does not update after fired" {
    var timer = Timer.oneShot(100);
    timer.update(100);
    try testing.expect(timer.fired);
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);

    // Further updates should be ignored
    timer.update(50);
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);
}

test "Timer: interval fires multiple times" {
    var timer = Timer.interval(50);
    try testing.expect(!timer.fired);

    // First fire
    timer.update(50);
    try testing.expect(!timer.fired); // repeating timers don't set fired
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms); // reset after fire

    // Second fire
    timer.update(50);
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);

    // Third fire
    timer.update(50);
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);
}

test "Timer: interval accumulates remainder correctly" {
    var timer = Timer.interval(100);

    timer.update(120); // Fires once, leaves 20ms remainder
    try testing.expectEqual(@as(u64, 20), timer.elapsed_ms);

    timer.update(90); // 20+90=110, fires again, leaves 10ms
    try testing.expectEqual(@as(u64, 10), timer.elapsed_ms);

    timer.update(95); // 10+95=105, fires, leaves 5ms
    try testing.expectEqual(@as(u64, 5), timer.elapsed_ms);
}

test "Timer: oneShotWithCallback invokes callback" {
    var ctx = CallbackContext{};
    var timer = Timer.oneShotWithCallback(100, CallbackContext.callback, &ctx);

    timer.update(50);
    try testing.expectEqual(@as(u32, 0), ctx.fired_count);

    timer.update(50);
    try testing.expectEqual(@as(u32, 1), ctx.fired_count);
    try testing.expectEqual(@as(u64, 100), ctx.last_elapsed_ms);

    // Should not fire again
    timer.update(100);
    try testing.expectEqual(@as(u32, 1), ctx.fired_count);
}

test "Timer: intervalWithCallback fires multiple times" {
    var ctx = CallbackContext{};
    var timer = Timer.intervalWithCallback(50, CallbackContext.callback, &ctx);

    timer.update(50);
    try testing.expectEqual(@as(u32, 1), ctx.fired_count);
    try testing.expectEqual(@as(u64, 50), ctx.last_elapsed_ms);

    timer.update(50);
    try testing.expectEqual(@as(u32, 2), ctx.fired_count);
    try testing.expectEqual(@as(u64, 50), ctx.last_elapsed_ms);

    timer.update(50);
    try testing.expectEqual(@as(u32, 3), ctx.fired_count);
    try testing.expectEqual(@as(u64, 50), ctx.last_elapsed_ms);
}

test "Timer: pause prevents progress" {
    var timer = Timer.oneShot(100);
    timer.update(50);
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);

    timer.pause();
    try testing.expect(timer.isPaused());

    timer.update(100); // Should be ignored
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);
    try testing.expect(!timer.fired);
}

test "Timer: unpause resumes progress" {
    var timer = Timer.oneShot(100);
    timer.update(30);
    timer.pause();
    timer.update(100); // Ignored

    timer.unpause();
    try testing.expect(!timer.isPaused());

    timer.update(70);
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);
    try testing.expect(timer.fired);
}

test "Timer: multiple pause/unpause cycles" {
    var timer = Timer.oneShot(100);

    timer.update(20);
    timer.pause();
    timer.update(50); // Ignored
    try testing.expectEqual(@as(u64, 20), timer.elapsed_ms);

    timer.unpause();
    timer.update(30);
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);

    timer.pause();
    timer.update(100); // Ignored
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);

    timer.unpause();
    timer.update(50);
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);
    try testing.expect(timer.fired);
}

test "Timer: setTimeScale 0.5 slows time" {
    var timer = Timer.oneShot(100);
    timer.setTimeScale(0.5);

    timer.update(100); // Only 50ms progress
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);
    try testing.expect(!timer.fired);

    timer.update(100); // Another 50ms, total 100ms
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);
    try testing.expect(timer.fired);
}

test "Timer: setTimeScale 2.0 speeds time" {
    var timer = Timer.oneShot(100);
    timer.setTimeScale(2.0);

    timer.update(50); // 100ms progress
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);
    try testing.expect(timer.fired);
}

test "Timer: setTimeScale 1.0 uses optimization path" {
    var timer = Timer.oneShot(100);
    timer.setTimeScale(1.0); // Explicit set to 1.0

    timer.update(100);
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);
    try testing.expect(timer.fired);
}

test "Timer: cancel prevents updates and callback" {
    var ctx = CallbackContext{};
    var timer = Timer.oneShotWithCallback(100, CallbackContext.callback, &ctx);

    timer.update(50);
    timer.cancel();
    try testing.expect(timer.isCancelled());

    timer.update(100); // Should be ignored
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);
    try testing.expectEqual(@as(u32, 0), ctx.fired_count);
}

test "Timer: multiple cancel calls are idempotent" {
    var timer = Timer.oneShot(100);
    timer.cancel();
    try testing.expect(timer.isCancelled());

    timer.cancel();
    timer.cancel();
    try testing.expect(timer.isCancelled());

    timer.update(100);
    try testing.expect(!timer.fired);
}

test "Timer: reset clears state" {
    var timer = Timer.oneShot(100);
    timer.update(100);
    try testing.expect(timer.fired);
    try testing.expectEqual(@as(u64, 100), timer.elapsed_ms);

    timer.reset();
    try testing.expectEqual(@as(u64, 0), timer.elapsed_ms);
    try testing.expect(!timer.fired);
    try testing.expect(!timer.cancelled);
    try testing.expect(!timer.paused);

    // Should fire again
    timer.update(100);
    try testing.expect(timer.fired);
}

test "Timer: reset clears cancelled state" {
    var timer = Timer.oneShot(100);
    timer.cancel();
    timer.reset();
    try testing.expect(!timer.isCancelled());

    timer.update(100);
    try testing.expect(timer.fired);
}

test "Timer: zero delay fires immediately" {
    var ctx = CallbackContext{};
    var timer = Timer.oneShotWithCallback(0, CallbackContext.callback, &ctx);

    timer.update(1); // Any delta triggers immediate fire
    try testing.expectEqual(@as(u32, 1), ctx.fired_count);
    try testing.expect(timer.fired);
}

test "Timer: very large delay does not overflow" {
    const large_delay = std.math.maxInt(u64) - 1000;
    var timer = Timer.oneShot(large_delay);

    timer.update(500);
    try testing.expectEqual(@as(u64, 500), timer.elapsed_ms);

    timer.update(500);
    try testing.expectEqual(@as(u64, 1000), timer.elapsed_ms);
    try testing.expect(!timer.fired);
}

test "Timer: many small updates accumulate correctly" {
    var timer = Timer.oneShot(1000);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        timer.update(10);
    }

    try testing.expectEqual(@as(u64, 1000), timer.elapsed_ms);
    try testing.expect(timer.fired);
}

test "Timer: update with delta_ms=0 makes no progress" {
    var timer = Timer.oneShot(100);
    timer.update(50);

    timer.update(0);
    timer.update(0);
    try testing.expectEqual(@as(u64, 50), timer.elapsed_ms);
    try testing.expect(!timer.fired);

    timer.update(50);
    try testing.expect(timer.fired);
}

test "Timer: isExpired returns false when cancelled" {
    var timer = Timer.oneShot(100);
    timer.update(100);
    try testing.expect(timer.isExpired());

    timer.cancel();
    try testing.expect(!timer.isExpired()); // Cancelled overrides expired
}

// ============================================================================
// TimerManager Tests
// ============================================================================

test "TimerManager: init and deinit" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    try testing.expectEqual(@as(usize, 0), manager.activeCount());
}

test "TimerManager: addTimer returns sequential IDs" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    const id1 = try manager.addTimer(Timer.oneShot(100));
    const id2 = try manager.addTimer(Timer.oneShot(200));
    const id3 = try manager.addTimer(Timer.oneShot(300));

    try testing.expectEqual(@as(usize, 0), id1);
    try testing.expectEqual(@as(usize, 1), id2);
    try testing.expectEqual(@as(usize, 2), id3);
}

test "TimerManager: updateAll updates all timers" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShot(100));
    _ = try manager.addTimer(Timer.oneShot(200));

    try manager.updateAll(50);
    try testing.expect(!manager.isExpired(0));
    try testing.expect(!manager.isExpired(1));

    try manager.updateAll(50);
    try testing.expect(manager.isExpired(0));
    try testing.expect(!manager.isExpired(1));

    try manager.updateAll(100);
    try testing.expect(manager.isExpired(1));
}

test "TimerManager: removeCompleted removes one-shot expired timers" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShot(100));
    _ = try manager.addTimer(Timer.oneShot(200));

    try manager.updateAll(100);
    try testing.expectEqual(@as(usize, 2), manager.timers.items.len);

    manager.removeCompleted();
    try testing.expectEqual(@as(usize, 1), manager.timers.items.len);

    try manager.updateAll(100);
    manager.removeCompleted();
    try testing.expectEqual(@as(usize, 0), manager.timers.items.len);
}

test "TimerManager: removeCompleted keeps repeating timers" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.interval(100));
    _ = try manager.addTimer(Timer.oneShot(100));

    try manager.updateAll(100);
    manager.removeCompleted();

    try testing.expectEqual(@as(usize, 1), manager.timers.items.len);
    try testing.expectEqual(@as(usize, 1), manager.activeCount());
}

test "TimerManager: removeCompleted removes cancelled timers" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    const id1 = try manager.addTimer(Timer.oneShot(100));
    _ = try manager.addTimer(Timer.oneShot(200));

    manager.cancelTimer(id1);
    manager.removeCompleted();

    try testing.expectEqual(@as(usize, 1), manager.timers.items.len);
}

test "TimerManager: activeCount excludes cancelled and expired one-shot" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    const id1 = try manager.addTimer(Timer.oneShot(100));
    _ = try manager.addTimer(Timer.oneShot(200));
    _ = try manager.addTimer(Timer.interval(100));

    try testing.expectEqual(@as(usize, 3), manager.activeCount());

    manager.cancelTimer(id1);
    try testing.expectEqual(@as(usize, 2), manager.activeCount());

    try manager.updateAll(100);
    // After 100ms: id1 cancelled, id2 still active (200ms delay), interval active
    try testing.expectEqual(@as(usize, 2), manager.activeCount());

    try manager.updateAll(100);
    // After 200ms total: id1 cancelled, id2 expired, interval active
    try testing.expectEqual(@as(usize, 1), manager.activeCount());
}

test "TimerManager: cancelTimer with invalid ID is safe" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShot(100));

    // Should not crash
    manager.cancelTimer(999);
    try testing.expectEqual(@as(usize, 1), manager.activeCount());
}

test "TimerManager: isExpired with invalid ID returns false" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShot(100));
    try manager.updateAll(100);

    try testing.expect(!manager.isExpired(999));
}

test "TimerManager: isCancelled with invalid ID returns false" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    const id = try manager.addTimer(Timer.oneShot(100));
    manager.cancelTimer(id);

    try testing.expect(!manager.isCancelled(999));
}

test "TimerManager: removeCompleted on empty pool is no-op" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    // Should not crash
    manager.removeCompleted();
    try testing.expectEqual(@as(usize, 0), manager.timers.items.len);
}

test "TimerManager: updateAll on empty pool is no-op" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    // Should not crash
    try manager.updateAll(100);
    try testing.expectEqual(@as(usize, 0), manager.timers.items.len);
}

test "TimerManager: callbacks fire during updateAll" {
    var ctx1 = CallbackContext{};
    var ctx2 = CallbackContext{};

    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShotWithCallback(100, CallbackContext.callback, &ctx1));
    _ = try manager.addTimer(Timer.intervalWithCallback(50, CallbackContext.callback, &ctx2));

    try manager.updateAll(50);
    try testing.expectEqual(@as(u32, 0), ctx1.fired_count);
    try testing.expectEqual(@as(u32, 1), ctx2.fired_count);

    try manager.updateAll(50);
    try testing.expectEqual(@as(u32, 1), ctx1.fired_count);
    try testing.expectEqual(@as(u32, 2), ctx2.fired_count);

    try manager.updateAll(50);
    try testing.expectEqual(@as(u32, 1), ctx1.fired_count); // One-shot doesn't fire again
    try testing.expectEqual(@as(u32, 3), ctx2.fired_count);
}

test "TimerManager: timers are sorted by remaining time" {
    var manager = TimerManager.init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addTimer(Timer.oneShot(300));
    _ = try manager.addTimer(Timer.oneShot(100));
    _ = try manager.addTimer(Timer.oneShot(200));

    try manager.updateAll(0); // Trigger sort

    // After sort: 100, 200, 300
    try testing.expectEqual(@as(u64, 100), manager.timers.items[0].delay_ms);
    try testing.expectEqual(@as(u64, 200), manager.timers.items[1].delay_ms);
    try testing.expectEqual(@as(u64, 300), manager.timers.items[2].delay_ms);
}
