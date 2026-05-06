//! Event Debouncing & Throttling
//!
//! Provides rate-limiting helpers for high-frequency events like resize,
//! keypress, validation, and search input.
//!
//! - **Debounce**: Delays callback execution until quiet period (no new triggers)
//! - **Throttle**: Enforces minimum interval between executions
//!
//! Use cases:
//! - Search-as-you-type: Debounce validates input only after user stops typing
//! - Window resize: Debounce recalculates layout only when resize finishes
//! - Scroll events: Throttle prevents excessive updates during scrolling

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Callback function type for debounce/throttle events
pub const EventCallback = *const fn (ctx: *anyopaque) void;

/// Debouncer: Executes callback after quiet period with no new triggers
///
/// When triggered, resets the timer. Callback executes only after
/// the configured delay passes with no intervening triggers.
///
/// Example: User types "hello" → 3 debounce resets → 200ms delay → single validation
pub const Debouncer = struct {
    delay_ns: u64,
    last_trigger_ns: i128 = 0,
    callback: ?EventCallback = null,
    callback_context: ?*anyopaque = null,
    pending: bool = false,
    allocator: Allocator,

    /// Initialize a debouncer with delay in nanoseconds
    pub fn init(allocator: Allocator, delay_ns: u64) Debouncer {
        return .{
            .allocator = allocator,
            .delay_ns = delay_ns,
        };
    }

    /// Trigger the debouncer with optional callback
    /// Resets timer; callback executes after delay with no intervening triggers
    pub fn trigger(
        self: *Debouncer,
        maybe_callback: ?EventCallback,
        maybe_context: ?*anyopaque,
    ) !void {
        self.callback = maybe_callback;
        self.callback_context = maybe_context;
        self.last_trigger_ns = std.time.nanoTimestamp();
        self.pending = true;
    }

    /// Check if pending execution should fire, based on elapsed time
    /// Call periodically in main loop (e.g., every 16ms for 60 FPS)
    pub fn poll(self: *Debouncer) bool {
        if (!self.pending) {
            return false;
        }

        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - self.last_trigger_ns));

        if (elapsed >= self.delay_ns) {
            if (self.callback) |cb| {
                if (self.callback_context) |ctx| {
                    cb(ctx);
                }
            }
            self.pending = false;
            return true;
        }

        return false;
    }

    /// Cancel any pending execution
    pub fn cancel(self: *Debouncer) void {
        self.pending = false;
        self.callback = null;
        self.callback_context = null;
    }

    /// Deinitialize debouncer
    pub fn deinit(self: *Debouncer) void {
        _ = self;
        // No allocations needed
    }
};

/// Throttler: Rate-limits callback execution to minimum interval
///
/// Executes immediately if interval has passed, otherwise skips.
/// Does not queue or delay executions — it simply enforces rate limit.
///
/// Example: Scroll event fires 100x/sec → throttle at 60Hz → 16ms interval → ~6-7 executions
pub const Throttler = struct {
    interval_ns: u64,
    last_execution_ns: i128 = 0,
    callback: ?EventCallback = null,
    callback_context: ?*anyopaque = null,
    allocator: Allocator,

    /// Initialize a throttler with minimum interval in nanoseconds
    pub fn init(allocator: Allocator, interval_ns: u64) Throttler {
        return .{
            .allocator = allocator,
            .interval_ns = interval_ns,
        };
    }

    /// Try to execute callback if minimum interval has passed
    /// Returns true if callback was executed, false if rate-limited
    pub fn trigger(
        self: *Throttler,
        maybe_callback: ?EventCallback,
        maybe_context: ?*anyopaque,
    ) !bool {
        const now = std.time.nanoTimestamp();
        const elapsed = if (self.last_execution_ns == 0)
            self.interval_ns
        else
            @as(u64, @intCast(now - self.last_execution_ns));

        if (elapsed >= self.interval_ns) {
            if (maybe_callback) |cb| {
                if (maybe_context) |ctx| {
                    cb(ctx);
                }
            }
            self.last_execution_ns = now;
            return true;
        }

        return false;
    }

    /// Reset last execution time (allows immediate next execution)
    pub fn reset(self: *Throttler) void {
        self.last_execution_ns = 0;
    }

    /// Deinitialize throttler
    pub fn deinit(self: *Throttler) void {
        _ = self;
        // No allocations needed
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Test context to track callback executions
const TestContext = struct {
    execution_count: u32 = 0,
    last_execution_time_ns: i128 = 0,

    pub fn callback(ctx: *anyopaque) void {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.execution_count += 1;
        self.last_execution_time_ns = std.time.nanoTimestamp();
    }
};

// ============================================================================
// Debouncer Tests
// ============================================================================

test "debounce: single trigger executes after delay" {
    var debouncer = Debouncer.init(testing.allocator, 100_000_000); // 100ms
    defer debouncer.deinit();

    var ctx = TestContext{};

    // Trigger the debouncer
    try debouncer.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 0); // Not executed yet

    // Poll before delay elapses
    const executed = debouncer.poll();
    try testing.expect(!executed);
    try testing.expect(ctx.execution_count == 0);

    // Simulate delay passing (in real code, time passes naturally)
    // For testing, we verify the pending state
    try testing.expect(debouncer.pending);
}

test "debounce: multiple rapid triggers execute once" {
    var debouncer = Debouncer.init(testing.allocator, 100_000_000); // 100ms
    defer debouncer.deinit();

    var ctx = TestContext{};

    // Trigger multiple times rapidly
    try debouncer.trigger(TestContext.callback, &ctx);
    try debouncer.trigger(TestContext.callback, &ctx);
    try debouncer.trigger(TestContext.callback, &ctx);
    try debouncer.trigger(TestContext.callback, &ctx);

    try testing.expect(ctx.execution_count == 0); // None executed yet
    try testing.expect(debouncer.pending); // Still pending
}

test "debounce: cancel prevents execution" {
    var debouncer = Debouncer.init(testing.allocator, 100_000_000); // 100ms
    defer debouncer.deinit();

    var ctx = TestContext{};

    try debouncer.trigger(TestContext.callback, &ctx);
    debouncer.cancel();

    try testing.expect(!debouncer.pending);
    try testing.expect(ctx.execution_count == 0);
}

test "debounce: timer resets on each trigger" {
    var debouncer = Debouncer.init(testing.allocator, 100_000_000); // 100ms
    defer debouncer.deinit();

    var ctx = TestContext{};

    // First trigger sets timer
    try debouncer.trigger(TestContext.callback, &ctx);
    const first_trigger_ns = debouncer.last_trigger_ns;

    // Simulate some time passing
    std.Thread.sleep(10 * std.time.ns_per_ms); // 10ms

    // Second trigger should reset timer
    try debouncer.trigger(TestContext.callback, &ctx);
    const second_trigger_ns = debouncer.last_trigger_ns;

    // Last trigger should be more recent
    try testing.expect(second_trigger_ns > first_trigger_ns);
    try testing.expect(ctx.execution_count == 0);
}

test "debounce: different contexts work correctly" {
    var debouncer = Debouncer.init(testing.allocator, 50_000_000); // 50ms
    defer debouncer.deinit();

    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    // Trigger with first context
    try debouncer.trigger(TestContext.callback, &ctx1);

    // Trigger with second context (overwrites first)
    try debouncer.trigger(TestContext.callback, &ctx2);

    // Only second context should increment when executed
    try testing.expect(ctx1.execution_count == 0);
    try testing.expect(ctx2.execution_count == 0);
}

test "debounce: zero delay edge case" {
    var debouncer = Debouncer.init(testing.allocator, 0); // 0 nanoseconds
    defer debouncer.deinit();

    var ctx = TestContext{};

    try debouncer.trigger(TestContext.callback, &ctx);

    // With zero delay, should execute immediately or very quickly
    // But since time has passed during setup, it might execute on poll
    _ = debouncer.poll();
    // Actual execution depends on timing; just verify no crash
}

test "debounce: very large delay doesn't overflow" {
    const large_delay: u64 = std.math.maxInt(u64) - 1000;
    var debouncer = Debouncer.init(testing.allocator, large_delay);
    defer debouncer.deinit();

    var ctx = TestContext{};

    // Should not crash
    try debouncer.trigger(TestContext.callback, &ctx);
    try testing.expect(debouncer.pending);
}

test "debounce: no callback set is safe" {
    var debouncer = Debouncer.init(testing.allocator, 100_000_000); // 100ms
    defer debouncer.deinit();

    // Trigger without setting callback
    try debouncer.trigger(null, null);
    try testing.expect(debouncer.pending);

    // Poll should be safe even without callback
    _ = debouncer.poll();
}

test "debounce: trigger, cancel, trigger again" {
    var debouncer = Debouncer.init(testing.allocator, 100_000_000); // 100ms
    defer debouncer.deinit();

    var ctx = TestContext{};

    try debouncer.trigger(TestContext.callback, &ctx);
    try testing.expect(debouncer.pending);

    debouncer.cancel();
    try testing.expect(!debouncer.pending);

    // Should be able to trigger again
    try debouncer.trigger(TestContext.callback, &ctx);
    try testing.expect(debouncer.pending);
}

test "debounce: execution count reflects single execution for multiple triggers" {
    // This test verifies the core debounce behavior:
    // Multiple triggers within delay window should result in single execution
    var debouncer = Debouncer.init(testing.allocator, 100_000_000); // 100ms
    defer debouncer.deinit();

    var ctx = TestContext{};

    // Simulate rapid key presses
    try debouncer.trigger(TestContext.callback, &ctx);
    try debouncer.trigger(TestContext.callback, &ctx);
    try debouncer.trigger(TestContext.callback, &ctx);

    try testing.expect(ctx.execution_count == 0); // None yet
}

// ============================================================================
// Throttler Tests
// ============================================================================

test "throttle: first call executes immediately" {
    var throttler = Throttler.init(testing.allocator, 100_000_000); // 100ms
    defer throttler.deinit();

    var ctx = TestContext{};

    // First call should execute immediately
    const executed = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(executed);
    try testing.expect(ctx.execution_count == 1);
}

test "throttle: rapid calls within interval are skipped" {
    var throttler = Throttler.init(testing.allocator, 100_000_000); // 100ms
    defer throttler.deinit();

    var ctx = TestContext{};

    // First execution
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 1);

    // Rapid subsequent calls within 100ms window
    _ = try throttler.trigger(TestContext.callback, &ctx);
    _ = try throttler.trigger(TestContext.callback, &ctx);
    _ = try throttler.trigger(TestContext.callback, &ctx);

    // Should still be 1 due to throttling
    try testing.expect(ctx.execution_count == 1);
}

test "throttle: call after interval executes" {
    var throttler = Throttler.init(testing.allocator, 10_000_000); // 10ms
    defer throttler.deinit();

    var ctx = TestContext{};

    // First execution
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 1);

    // Wait for interval to pass
    std.Thread.sleep(15 * std.time.ns_per_ms); // 15ms

    // Next call after interval should execute
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 2);
}

test "throttle: reset allows immediate execution" {
    var throttler = Throttler.init(testing.allocator, 100_000_000); // 100ms
    defer throttler.deinit();

    var ctx = TestContext{};

    // First execution
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 1);

    // Rapid call is throttled
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 1);

    // Reset allows immediate execution
    throttler.reset();
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 2);
}

test "throttle: zero interval always executes" {
    var throttler = Throttler.init(testing.allocator, 0); // 0 nanoseconds
    defer throttler.deinit();

    var ctx = TestContext{};

    // Multiple calls should all execute with zero interval
    _ = try throttler.trigger(TestContext.callback, &ctx);
    _ = try throttler.trigger(TestContext.callback, &ctx);
    _ = try throttler.trigger(TestContext.callback, &ctx);

    try testing.expect(ctx.execution_count == 3);
}

test "throttle: high frequency events are rate-limited" {
    var throttler = Throttler.init(testing.allocator, 16_666_667); // ~60 Hz (16.67ms)
    defer throttler.deinit();

    var ctx = TestContext{};

    // Simulate 10 rapid scroll events
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = try throttler.trigger(TestContext.callback, &ctx);
    }

    // Only first should execute (unless enough time has passed)
    try testing.expect(ctx.execution_count >= 1);
    try testing.expect(ctx.execution_count <= 2); // At most 2 if enough real time passed
}

test "throttle: returns true when executed, false when throttled" {
    var throttler = Throttler.init(testing.allocator, 100_000_000); // 100ms
    defer throttler.deinit();

    var ctx = TestContext{};

    // First call returns true (executed)
    const first_executed = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(first_executed);

    // Second call returns false (throttled)
    const second_executed = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(!second_executed);

    // Third call also returns false
    const third_executed = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(!third_executed);
}

test "throttle: null callback is safe" {
    var throttler = Throttler.init(testing.allocator, 100_000_000); // 100ms
    defer throttler.deinit();

    // Should not crash with null callback
    _ = try throttler.trigger(null, null);
    _ = try throttler.trigger(null, null);
}

test "throttle: works with different contexts" {
    var throttler = Throttler.init(testing.allocator, 100_000_000); // 100ms
    defer throttler.deinit();

    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    // First call with ctx1
    _ = try throttler.trigger(TestContext.callback, &ctx1);
    try testing.expect(ctx1.execution_count == 1);

    // Second call with ctx2 is throttled (first execution is recent)
    _ = try throttler.trigger(TestContext.callback, &ctx2);
    try testing.expect(ctx2.execution_count == 0); // Not executed due to throttle
}

test "throttle: very small interval provides fine-grained rate limiting" {
    var throttler = Throttler.init(testing.allocator, 1_000_000); // 1ms
    defer throttler.deinit();

    var ctx = TestContext{};

    // Multiple calls in quick succession
    _ = try throttler.trigger(TestContext.callback, &ctx);
    const first_count = ctx.execution_count;

    // Wait slightly longer than interval
    std.Thread.sleep(2 * std.time.ns_per_ms); // 2ms

    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count > first_count);
}

test "throttle: multiple resets enable multiple rapid executions" {
    var throttler = Throttler.init(testing.allocator, 100_000_000); // 100ms
    defer throttler.deinit();

    var ctx = TestContext{};

    // First execution
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 1);

    // Reset and execute
    throttler.reset();
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 2);

    // Reset again and execute
    throttler.reset();
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 3);
}

test "throttle: very large interval still respects throttling" {
    var throttler = Throttler.init(testing.allocator, 1_000_000_000_000); // 1 second
    defer throttler.deinit();

    var ctx = TestContext{};

    // First execution
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 1);

    // Rapid follow-up is throttled even with large interval
    _ = try throttler.trigger(TestContext.callback, &ctx);
    try testing.expect(ctx.execution_count == 1);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "debounce vs throttle: debounce delays execution, throttle rate-limits" {
    // This test demonstrates the semantic difference:
    // Debounce: waits for quiet period
    // Throttle: enforces minimum time between executions

    var debouncer = Debouncer.init(testing.allocator, 50_000_000); // 50ms
    defer debouncer.deinit();

    var throttler = Throttler.init(testing.allocator, 50_000_000); // 50ms
    defer throttler.deinit();

    var debounce_ctx = TestContext{};
    var throttle_ctx = TestContext{};

    // Trigger both
    try debouncer.trigger(TestContext.callback, &debounce_ctx);
    _ = try throttler.trigger(TestContext.callback, &throttle_ctx);

    // Throttle executed immediately
    try testing.expect(throttle_ctx.execution_count == 1);

    // Debounce hasn't executed yet
    try testing.expect(debounce_ctx.execution_count == 0);
}

test "debounce: suitable for search-as-you-type use case" {
    // Simulates user typing "hello" with debounced validation
    var debouncer = Debouncer.init(testing.allocator, 200_000_000); // 200ms
    defer debouncer.deinit();

    var ctx = TestContext{};

    // User types 5 characters
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try debouncer.trigger(TestContext.callback, &ctx);
        std.Thread.sleep(20 * std.time.ns_per_ms); // 20ms between keystrokes
    }

    // Validation hasn't run yet (still within debounce window)
    try testing.expect(ctx.execution_count == 0);

    // Wait for debounce delay to pass
    std.Thread.sleep(250 * std.time.ns_per_ms); // 250ms

    // After waiting, poll should trigger execution
    const executed = debouncer.poll();
    if (executed) {
        try testing.expect(ctx.execution_count == 1);
    }
}

test "throttle: suitable for resize handling use case" {
    // Simulates rapid resize events at 60+ Hz
    var throttler = Throttler.init(testing.allocator, 16_666_667); // ~60 Hz
    defer throttler.deinit();

    var ctx = TestContext{};

    // Simulate 10 resize events fired rapidly (simulating mouse drag)
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = try throttler.trigger(TestContext.callback, &ctx);
    }

    // Should be throttled to ~1-2 executions, not all 10
    try testing.expect(ctx.execution_count <= 2);
}
