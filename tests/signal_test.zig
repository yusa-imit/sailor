//! Comprehensive tests for sailor's reactive signal system (v2.12.0)
//!
//! Tests for Signal(T), Computed(T,S), Effect(T), and Scope batch updates.
//!
//! Coverage:
//! - Signal lifecycle (init, deinit, memory safety)
//! - Signal.get() returns current value
//! - Signal.set() updates value and notifies subscribers
//! - Multiple subscribers to same signal
//! - Subscriber removal (unsubscribe)
//! - Computed values derived from signals
//! - Computed auto-updates on signal changes
//! - Effect callbacks (immediate, reactive)
//! - Effect auto-unsubscribe on deinit
//! - Batch updates (Scope) defer notifications
//! - String signals ([]const u8)
//! - Struct signals (custom types)
//! - Edge cases (zero subscribers, deinit during callback)

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const signal = sailor.signal;

// ============================================================================
// Helper: Callback Counter
// ============================================================================

/// Tracks how many times a callback has been invoked
const CallbackCounter = struct {
    count: i32 = 0,

    fn increment(_: i32, ctx: ?*anyopaque) void {
        const ptr: *CallbackCounter = @ptrCast(@alignCast(ctx.?));
        ptr.count += 1;
    }
};

// ============================================================================
// Signal(T) Lifecycle Tests
// ============================================================================

test "Signal init with initial value" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 42);
    defer sig.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), sig.get());
}

test "Signal.get() returns current value" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 10);
    defer sig.deinit(allocator);

    try testing.expectEqual(@as(i32, 10), sig.get());

    try sig.set(20);
    try testing.expectEqual(@as(i32, 20), sig.get());

    try sig.set(99);
    try testing.expectEqual(@as(i32, 99), sig.get());
}

test "Signal.set() updates value" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    try sig.set(5);
    try testing.expectEqual(@as(i32, 5), sig.get());

    try sig.set(-10);
    try testing.expectEqual(@as(i32, -10), sig.get());

    try sig.set(0);
    try testing.expectEqual(@as(i32, 0), sig.get());
}

test "Signal deinit cleans up memory" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 42);
    var counter: CallbackCounter = .{};
    const id = try sig.subscribe(allocator, &counter, CallbackCounter.increment);
    // Verify subscription was registered
    try testing.expectEqual(@as(usize, 1), sig.subscribers.items.len);
    sig.unsubscribe(id);
    // After unsubscribe, no subscribers remain
    try testing.expectEqual(@as(usize, 0), sig.subscribers.items.len);
    sig.deinit(allocator);
    // testing.allocator will catch any leaks automatically
}

// ============================================================================
// Signal Subscription Tests
// ============================================================================

test "Signal subscriber called on set()" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    var counter: CallbackCounter = .{};
    _ = try sig.subscribe(allocator, &counter, CallbackCounter.increment);

    try sig.set(1);
    try testing.expectEqual(@as(i32, 1), counter.count);

    try sig.set(2);
    try testing.expectEqual(@as(i32, 2), counter.count);
}

test "Signal multiple subscribers all notified" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    var counter1: CallbackCounter = .{};
    var counter2: CallbackCounter = .{};
    var counter3: CallbackCounter = .{};

    _ = try sig.subscribe(allocator, &counter1, CallbackCounter.increment);
    _ = try sig.subscribe(allocator, &counter2, CallbackCounter.increment);
    _ = try sig.subscribe(allocator, &counter3, CallbackCounter.increment);

    try sig.set(10);

    try testing.expectEqual(@as(i32, 1), counter1.count);
    try testing.expectEqual(@as(i32, 1), counter2.count);
    try testing.expectEqual(@as(i32, 1), counter3.count);

    try sig.set(20);
    try testing.expectEqual(@as(i32, 2), counter1.count);
    try testing.expectEqual(@as(i32, 2), counter2.count);
    try testing.expectEqual(@as(i32, 2), counter3.count);
}

test "Signal unsubscribe prevents callback" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    var counter: CallbackCounter = .{};
    const subscription_id = try sig.subscribe(allocator, &counter, CallbackCounter.increment);

    try sig.set(1);
    try testing.expectEqual(@as(i32, 1), counter.count);

    sig.unsubscribe(subscription_id);

    try sig.set(2);
    // Count should not increment because we unsubscribed
    try testing.expectEqual(@as(i32, 1), counter.count);
}

test "Signal no crash with zero subscribers" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    // Set without any subscribers
    try sig.set(1);
    try testing.expectEqual(@as(i32, 1), sig.get());

    try sig.set(2);
    try testing.expectEqual(@as(i32, 2), sig.get());
}

// ============================================================================
// Computed(T,S) Tests
// ============================================================================

test "Computed derives value from signal" {
    const allocator = testing.allocator;
    var source = try signal.Signal(i32).init(allocator, 5);
    defer source.deinit(allocator);

    const double = struct {
        fn transform(value: i32) i32 {
            return value * 2;
        }
    }.transform;

    var computed = try signal.Computed(i32, i32).init(allocator, &source, double);
    defer computed.deinit(allocator);

    try testing.expectEqual(@as(i32, 10), computed.get());
}

test "Computed.get() reflects signal updates" {
    const allocator = testing.allocator;
    var source = try signal.Signal(i32).init(allocator, 3);
    defer source.deinit(allocator);

    const triple = struct {
        fn transform(value: i32) i32 {
            return value * 3;
        }
    }.transform;

    var computed = try signal.Computed(i32, i32).init(allocator, &source, triple);
    defer computed.deinit(allocator);

    try testing.expectEqual(@as(i32, 9), computed.get());

    try source.set(4);
    try testing.expectEqual(@as(i32, 12), computed.get());

    try source.set(10);
    try testing.expectEqual(@as(i32, 30), computed.get());
}

test "Computed with integer transformation" {
    const allocator = testing.allocator;
    var source = try signal.Signal(i32).init(allocator, 42);
    defer source.deinit(allocator);

    const addOne = struct {
        fn transform(value: i32) i32 {
            return value + 1;
        }
    }.transform;

    var computed = try signal.Computed(i32, i32).init(allocator, &source, addOne);
    defer computed.deinit(allocator);

    try testing.expectEqual(@as(i32, 43), computed.get());

    try source.set(99);
    try testing.expectEqual(@as(i32, 100), computed.get());
}

// ============================================================================
// Effect(T) Tests
// ============================================================================

test "Effect callback called on signal change" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    var counter: CallbackCounter = .{};

    var effect = try signal.Effect(i32).init(allocator, &sig, &counter, CallbackCounter.increment);
    defer effect.deinit(allocator);

    // Effect should call callback immediately on init OR on first change
    // Implementation detail - test that changes trigger callback
    try sig.set(1);
    try testing.expectEqual(@as(i32, 1), counter.count);

    try sig.set(2);
    try testing.expectEqual(@as(i32, 2), counter.count);
}

test "Effect deinit auto-unsubscribes from signal" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    var counter: CallbackCounter = .{};

    {
        var effect = try signal.Effect(i32).init(allocator, &sig, &counter, CallbackCounter.increment);
        try sig.set(1);
        try testing.expectEqual(@as(i32, 1), counter.count);
        // effect goes out of scope and deinits
        effect.deinit(allocator);
    }

    // After effect is destroyed, signal set should not call counter
    const old_count = counter.count;
    try sig.set(2);
    try testing.expectEqual(old_count, counter.count);
}

test "Effect receives updated signal value" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 5);
    defer sig.deinit(allocator);

    var last_value: i32 = 0;
    const store_value = struct {
        fn callback(value: i32, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* = value;
        }
    }.callback;

    var effect = try signal.Effect(i32).init(allocator, &sig, &last_value, store_value);
    defer effect.deinit(allocator);

    try sig.set(10);
    try testing.expectEqual(@as(i32, 10), last_value);

    try sig.set(20);
    try testing.expectEqual(@as(i32, 20), last_value);
}

// ============================================================================
// Scope / Batch Update Tests
// ============================================================================

test "Scope batch updates defer notifications" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    var counter: CallbackCounter = .{};
    _ = try sig.subscribe(allocator, &counter, CallbackCounter.increment);

    var scope = signal.Scope.init();
    defer scope.deinit();

    try scope.batch(allocator, &sig, struct {
        fn fn_body(s: *signal.Signal(i32)) !void {
            try s.set(1);
            try s.set(2);
            try s.set(3);
        }
    }.fn_body);

    // Batch should coalesce 3 set() calls into exactly 1 notification
    try testing.expectEqual(@as(i32, 1), counter.count);
    try testing.expectEqual(@as(i32, 3), sig.get());
}

// ============================================================================
// String Signal Tests
// ============================================================================

test "Signal with string type ([]const u8)" {
    const allocator = testing.allocator;
    var sig = try signal.Signal([]const u8).init(allocator, "hello");
    defer sig.deinit(allocator);

    try testing.expectEqualStrings("hello", sig.get());

    try sig.set("world");
    try testing.expectEqualStrings("world", sig.get());

    try sig.set("test");
    try testing.expectEqualStrings("test", sig.get());
}

test "String signal subscribers called on change" {
    const allocator = testing.allocator;
    var sig = try signal.Signal([]const u8).init(allocator, "");
    defer sig.deinit(allocator);

    var count: i32 = 0;
    const increment = struct {
        fn callback(_: []const u8, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try sig.subscribe(allocator, &count, increment);

    try sig.set("a");
    try testing.expectEqual(@as(i32, 1), count);

    try sig.set("b");
    try testing.expectEqual(@as(i32, 2), count);
}

// ============================================================================
// Struct Signal Tests
// ============================================================================

test "Signal with struct type" {
    const allocator = testing.allocator;

    const Point = struct {
        x: i32,
        y: i32,
    };

    var sig = try signal.Signal(Point).init(allocator, .{ .x = 1, .y = 2 });
    defer sig.deinit(allocator);

    try testing.expectEqual(@as(i32, 1), sig.get().x);
    try testing.expectEqual(@as(i32, 2), sig.get().y);

    try sig.set(.{ .x = 10, .y = 20 });
    try testing.expectEqual(@as(i32, 10), sig.get().x);
    try testing.expectEqual(@as(i32, 20), sig.get().y);
}

test "Struct signal subscribers called on mutation" {
    const allocator = testing.allocator;

    const Point = struct {
        x: i32,
        y: i32,
    };

    var sig = try signal.Signal(Point).init(allocator, .{ .x = 0, .y = 0 });
    defer sig.deinit(allocator);

    var count: i32 = 0;
    const increment = struct {
        fn callback(_: Point, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try sig.subscribe(allocator, &count, increment);

    try sig.set(.{ .x = 5, .y = 5 });
    try testing.expectEqual(@as(i32, 1), count);

    try sig.set(.{ .x = 10, .y = 10 });
    try testing.expectEqual(@as(i32, 2), count);
}

// ============================================================================
// Edge Cases & Stress Tests
// ============================================================================

test "Signal set to same value still notifies" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 5);
    defer sig.deinit(allocator);

    var counter: CallbackCounter = .{};
    _ = try sig.subscribe(allocator, &counter, CallbackCounter.increment);

    try sig.set(5);
    try sig.set(5);
    try sig.set(5);

    // Subscribers should be called regardless of value equality
    try testing.expectEqual(@as(i32, 3), counter.count);
}

test "Signal handles negative numbers" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, -100);
    defer sig.deinit(allocator);

    try testing.expectEqual(@as(i32, -100), sig.get());

    try sig.set(-50);
    try testing.expectEqual(@as(i32, -50), sig.get());

    try sig.set(0);
    try testing.expectEqual(@as(i32, 0), sig.get());
}

test "Computed with chain of transformations" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 2);
    defer sig.deinit(allocator);

    const double = struct {
        fn transform(v: i32) i32 {
            return v * 2;
        }
    }.transform;

    var comp1 = try signal.Computed(i32, i32).init(allocator, &sig, double);
    defer comp1.deinit(allocator);

    try testing.expectEqual(@as(i32, 4), comp1.get());

    try sig.set(5);
    try testing.expectEqual(@as(i32, 10), comp1.get());
}

test "Multiple effects on same signal" {
    const allocator = testing.allocator;
    var sig = try signal.Signal(i32).init(allocator, 0);
    defer sig.deinit(allocator);

    var count1: i32 = 0;
    var count2: i32 = 0;

    const increment1 = struct {
        fn callback(_: i32, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    const increment2 = struct {
        fn callback(_: i32, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 10;
        }
    }.callback;

    var effect1 = try signal.Effect(i32).init(allocator, &sig, &count1, increment1);
    var effect2 = try signal.Effect(i32).init(allocator, &sig, &count2, increment2);
    defer {
        effect1.deinit(allocator);
        effect2.deinit(allocator);
    }

    try sig.set(1);
    try testing.expectEqual(@as(i32, 1), count1);
    try testing.expectEqual(@as(i32, 10), count2);

    try sig.set(2);
    try testing.expectEqual(@as(i32, 2), count1);
    try testing.expectEqual(@as(i32, 20), count2);
}

test "Signal large value type (array)" {
    const allocator = testing.allocator;

    const Data = [16]u8;
    var initial: Data = undefined;
    @memset(&initial, 42);

    var sig = try signal.Signal(Data).init(allocator, initial);
    defer sig.deinit(allocator);

    const val = sig.get();
    try testing.expectEqual(@as(u8, 42), val[0]);
    try testing.expectEqual(@as(u8, 42), val[15]);

    var new_val: Data = undefined;
    @memset(&new_val, 99);
    try sig.set(new_val);

    const val2 = sig.get();
    try testing.expectEqual(@as(u8, 99), val2[0]);
    try testing.expectEqual(@as(u8, 99), val2[15]);
}
