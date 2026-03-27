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

    pub fn isExpired(self: Timer) bool {
        if (self.cancelled) return false;
        return self.elapsed_ms >= self.delay_ms;
    }

    pub fn isCancelled(self: Timer) bool {
        return self.cancelled;
    }

    pub fn cancel(self: *Timer) void {
        self.cancelled = true;
    }

    pub fn reset(self: *Timer) void {
        self.elapsed_ms = 0;
        self.cancelled = false;
        self.paused = false;
        self.fired = false;
    }

    pub fn pause(self: *Timer) void {
        self.paused = true;
    }

    pub fn unpause(self: *Timer) void {
        self.paused = false;
    }

    pub fn isPaused(self: Timer) bool {
        return self.paused;
    }

    pub fn setTimeScale(self: *Timer, scale: f32) void {
        self.time_scale = scale;
    }
};

/// Central pool for managing multiple timers
pub const TimerManager = struct {
    timers: std.ArrayList(Timer),
    allocator: Allocator,

    pub fn init(allocator: Allocator) TimerManager {
        return .{
            .timers = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TimerManager) void {
        self.timers.deinit(self.allocator);
    }

    pub fn addTimer(self: *TimerManager, timer: Timer) !usize {
        const id = self.timers.items.len;
        try self.timers.append(self.allocator, timer);
        return id;
    }

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

    pub fn cancelTimer(self: *TimerManager, id: usize) void {
        if (id < self.timers.items.len) {
            self.timers.items[id].cancel();
        }
    }

    pub fn isExpired(self: TimerManager, id: usize) bool {
        if (id >= self.timers.items.len) return false;
        return self.timers.items[id].isExpired();
    }

    pub fn isCancelled(self: TimerManager, id: usize) bool {
        if (id >= self.timers.items.len) return false;
        return self.timers.items[id].isCancelled();
    }
};
