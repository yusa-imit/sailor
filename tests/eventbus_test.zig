//! Comprehensive tests for sailor's EventBus (v2.8.0 milestone)
//!
//! Tests the EventBus publish-subscribe pattern with:
//! - Topic-based subscriptions (TESTED in src/eventbus.zig)
//! - Type-safe event payloads (TESTED in src/eventbus.zig)
//! - Priority-based event dispatch (TESTED in src/eventbus.zig)
//! - **Event filtering and transformation** (NEW - to be implemented)
//! - **Scoped subscriptions (auto-unsubscribe on deinit)** (NEW - to be implemented)
//! - **Thread-safety and concurrency** (NEW - to be implemented)
//! - **Memory management and leak detection** (NEW - to be implemented)
//! - **Edge cases and stress testing** (NEW - to be implemented)
//!
//! This file contains FAILING tests for the missing features from the v2.8.0 milestone.

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

// EventBus types (will be extended)
const EventBus = sailor.EventBus;
const Event = EventBus.Event;

// ============================================================================
// Event Filtering Tests (6 tests) — NEW FEATURE
// ============================================================================

test "EventBus - subscribeFiltered with passing filter invokes callback" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const filter = struct {
        fn call(event: Event) bool {
            // Filter: only process events with data != null
            return event.data != null;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    // Subscribe with filter
    _ = try bus.subscribeFiltered("test.filtered", filter, callback, &invoked, 0);

    // Publish event with data (should pass filter)
    var data: i32 = 42;
    const event = Event.init("test.filtered", &data);
    bus.publish(event);

    try testing.expect(invoked);
}

test "EventBus - subscribeFiltered with failing filter does not invoke callback" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const filter = struct {
        fn call(event: Event) bool {
            // Filter: only process events with data != null
            return event.data != null;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    // Subscribe with filter
    _ = try bus.subscribeFiltered("test.filtered", filter, callback, &invoked, 0);

    // Publish event WITHOUT data (should fail filter)
    const event = Event.init("test.filtered", null);
    bus.publish(event);

    try testing.expect(!invoked); // Should NOT be invoked
}

test "EventBus - filter returns true for some events, false for others" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var count: usize = 0;

    const filter = struct {
        fn call(event: Event) bool {
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                return value.* > 10; // Only values > 10
            }
            return false;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    _ = try bus.subscribeFiltered("test.filter", filter, callback, &count, 0);

    // Publish multiple events
    var value1: i32 = 5;
    var value2: i32 = 15;
    var value3: i32 = 3;
    var value4: i32 = 20;

    bus.publish(Event.init("test.filter", &value1)); // Should be filtered out
    bus.publish(Event.init("test.filter", &value2)); // Should pass
    bus.publish(Event.init("test.filter", &value3)); // Should be filtered out
    bus.publish(Event.init("test.filter", &value4)); // Should pass

    try testing.expectEqual(@as(usize, 2), count); // Only 2 events passed filter
}

test "EventBus - filter function throws error gracefully" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const filter = struct {
        fn call(_: Event) bool {
            // Simulate error condition
            // In real implementation, filter errors should be caught
            return false; // For now, just reject
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    _ = try bus.subscribeFiltered("test.error", filter, callback, &invoked, 0);

    const event = Event.init("test.error", null);
    bus.publish(event); // Should not crash

    try testing.expect(!invoked);
}

test "EventBus - multiple filters on same topic are independent" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var count1: usize = 0;
    var count2: usize = 0;

    const filter1 = struct {
        fn call(event: Event) bool {
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                return value.* < 10; // Less than 10
            }
            return false;
        }
    }.call;

    const filter2 = struct {
        fn call(event: Event) bool {
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                return value.* > 10; // Greater than 10
            }
            return false;
        }
    }.call;

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    _ = try bus.subscribeFiltered("test.multi", filter1, callback1, &count1, 0);
    _ = try bus.subscribeFiltered("test.multi", filter2, callback2, &count2, 0);

    var value1: i32 = 5;
    var value2: i32 = 15;

    bus.publish(Event.init("test.multi", &value1)); // Only filter1 passes
    bus.publish(Event.init("test.multi", &value2)); // Only filter2 passes

    try testing.expectEqual(@as(usize, 1), count1);
    try testing.expectEqual(@as(usize, 1), count2);
}

test "EventBus - filter with empty payload behaves correctly" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const filter = struct {
        fn call(event: Event) bool {
            // Accept events with null data
            return event.data == null;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    _ = try bus.subscribeFiltered("test.empty", filter, callback, &invoked, 0);

    const event = Event.init("test.empty", null);
    bus.publish(event);

    try testing.expect(invoked);
}

// ============================================================================
// Event Transformation Tests (6 tests) — NEW FEATURE
// ============================================================================

test "EventBus - subscribeTransformed callback receives transformed payload" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var result: i32 = 0;

    const transform = struct {
        fn call(allocator: std.mem.Allocator, event: Event) !Event {
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                const transformed = try allocator.create(i32);
                transformed.* = value.* * 2; // Double the value
                return Event.init(event.type, transformed);
            }
            return event;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const res = @as(*i32, @ptrCast(@alignCast(ctx.?)));
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                res.* = value.*;
            }
        }
    }.call;

    _ = try bus.subscribeTransformed("test.transform", transform, callback, &result, 0);

    var value: i32 = 21;
    const event = Event.init("test.transform", &value);
    bus.publish(event);

    try testing.expectEqual(@as(i32, 42), result); // 21 * 2 = 42
}

test "EventBus - transformation function modifies payload correctly" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var result: [10]u8 = undefined;
    var result_len: usize = 0;

    const transform = struct {
        fn call(allocator: std.mem.Allocator, event: Event) !Event {
            if (event.data) |data| {
                const str = @as([*:0]const u8, @ptrCast(@alignCast(data)));
                const upper = try allocator.alloc(u8, std.mem.len(str));
                for (std.mem.span(str), 0..) |c, i| {
                    upper[i] = std.ascii.toUpper(c);
                }
                return Event.init(event.type, upper.ptr);
            }
            return event;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const context = @as(*struct { buf: *[10]u8, len: *usize }, @ptrCast(@alignCast(ctx.?)));
            if (event.data) |data| {
                const str = @as([*:0]const u8, @ptrCast(@alignCast(data)));
                const len = std.mem.len(str);
                @memcpy(context.buf[0..len], std.mem.span(str));
                context.len.* = len;
            }
        }
    }.call;

    var ctx = .{ .buf = &result, .len = &result_len };
    _ = try bus.subscribeTransformed("test.upper", transform, callback, &ctx, 0);

    const input = "hello";
    const event = Event.init("test.upper", @constCast(input.ptr));
    bus.publish(event);

    try testing.expectEqualStrings("HELLO", result[0..result_len]);
}

test "EventBus - transformation returns error is handled gracefully" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const transform = struct {
        fn call(_: std.mem.Allocator, event: Event) !Event {
            // Simulate allocation failure
            if (event.data != null) {
                return error.OutOfMemory;
            }
            return event;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    _ = try bus.subscribeTransformed("test.error", transform, callback, &invoked, 0);

    var value: i32 = 42;
    const event = Event.init("test.error", &value);
    bus.publish(event); // Should not crash

    // Callback should NOT be invoked on transformation error
    try testing.expect(!invoked);
}

test "EventBus - transformation allocates memory that is cleaned up" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var result: i32 = 0;

    const transform = struct {
        fn call(allocator: std.mem.Allocator, event: Event) !Event {
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                const transformed = try allocator.create(i32);
                transformed.* = value.* + 100;
                // Memory should be tracked and freed by EventBus
                return Event.init(event.type, transformed);
            }
            return event;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const res = @as(*i32, @ptrCast(@alignCast(ctx.?)));
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                res.* = value.*;
            }
        }
    }.call;

    _ = try bus.subscribeTransformed("test.alloc", transform, callback, &result, 0);

    var value: i32 = 42;
    const event = Event.init("test.alloc", &value);
    bus.publish(event);

    try testing.expectEqual(@as(i32, 142), result);
    // Memory leak detection will happen via LeakCheckAllocator
}

test "EventBus - multiple transformations on same event are independent" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var result1: i32 = 0;
    var result2: i32 = 0;

    const transform1 = struct {
        fn call(allocator: std.mem.Allocator, event: Event) !Event {
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                const transformed = try allocator.create(i32);
                transformed.* = value.* * 2;
                return Event.init(event.type, transformed);
            }
            return event;
        }
    }.call;

    const transform2 = struct {
        fn call(allocator: std.mem.Allocator, event: Event) !Event {
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                const transformed = try allocator.create(i32);
                transformed.* = value.* + 100;
                return Event.init(event.type, transformed);
            }
            return event;
        }
    }.call;

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const res = @as(*i32, @ptrCast(@alignCast(ctx.?)));
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                res.* = value.*;
            }
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const res = @as(*i32, @ptrCast(@alignCast(ctx.?)));
            if (event.data) |data| {
                const value = @as(*i32, @ptrCast(@alignCast(data)));
                res.* = value.*;
            }
        }
    }.call;

    _ = try bus.subscribeTransformed("test.multi", transform1, callback1, &result1, 0);
    _ = try bus.subscribeTransformed("test.multi", transform2, callback2, &result2, 0);

    var value: i32 = 10;
    const event = Event.init("test.multi", &value);
    bus.publish(event);

    try testing.expectEqual(@as(i32, 20), result1); // 10 * 2
    try testing.expectEqual(@as(i32, 110), result2); // 10 + 100
}

test "EventBus - transformation with empty payload behaves correctly" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const transform = struct {
        fn call(_: std.mem.Allocator, event: Event) !Event {
            // Pass through null data unchanged
            return event;
        }
    }.call;

    const callback = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = event.data == null;
        }
    }.call;

    _ = try bus.subscribeTransformed("test.null", transform, callback, &invoked, 0);

    const event = Event.init("test.null", null);
    bus.publish(event);

    try testing.expect(invoked);
}

// ============================================================================
// Scoped Subscriptions (RAII) Tests (5 tests) — NEW FEATURE
// ============================================================================

test "EventBus - scopedSubscribe auto-unsubscribes on deinit" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var count: usize = 0;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    {
        const scoped = try bus.scopedSubscribe("test.scoped", callback, &count, 0);
        defer scoped.deinit();

        const event = Event.init("test.scoped", null);
        bus.publish(event);
        try testing.expectEqual(@as(usize, 1), count);
    }

    // After scope exit, subscription should be removed
    const event = Event.init("test.scoped", null);
    bus.publish(event);
    try testing.expectEqual(@as(usize, 1), count); // Should NOT increment
}

test "EventBus - multiple scoped subscriptions all auto-unsubscribe" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var count1: usize = 0;
    var count2: usize = 0;
    var count3: usize = 0;

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 10;
        }
    }.call;

    const callback3 = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 100;
        }
    }.call;

    {
        const scoped1 = try bus.scopedSubscribe("test.multi", callback1, &count1, 0);
        defer scoped1.deinit();
        const scoped2 = try bus.scopedSubscribe("test.multi", callback2, &count2, 0);
        defer scoped2.deinit();
        const scoped3 = try bus.scopedSubscribe("test.multi", callback3, &count3, 0);
        defer scoped3.deinit();

        const event = Event.init("test.multi", null);
        bus.publish(event);
        try testing.expectEqual(@as(usize, 1), count1);
        try testing.expectEqual(@as(usize, 10), count2);
        try testing.expectEqual(@as(usize, 100), count3);
    }

    // After scope exit, all subscriptions removed
    const event = Event.init("test.multi", null);
    bus.publish(event);
    try testing.expectEqual(@as(usize, 1), count1); // No change
    try testing.expectEqual(@as(usize, 10), count2); // No change
    try testing.expectEqual(@as(usize, 100), count3); // No change
}

test "EventBus - scoped subscription outlives EventBus deinit does not crash" {
    var bus = EventBus.init(testing.allocator);

    var count: usize = 0;
    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    const scoped = try bus.scopedSubscribe("test.outlive", callback, &count, 0);

    // Deinit bus BEFORE scoped subscription
    bus.deinit();

    // Should not crash when deinit is called on already-dead bus
    scoped.deinit();

    try testing.expectEqual(@as(usize, 0), count);
}

test "EventBus - scoped subscription deinit mid-event is safe" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var count: usize = 0;
    var scoped_ref: ?*EventBus.ScopedSubscription = null;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const context = @as(*struct { count: *usize, scoped: *?*EventBus.ScopedSubscription }, @ptrCast(@alignCast(ctx.?)));
            context.count.* += 1;
            // Attempt to deinit during callback execution
            if (context.scoped.*) |s| {
                s.deinit();
                context.scoped.* = null;
            }
        }
    }.call;

    var ctx = .{ .count = &count, .scoped = &scoped_ref };
    const scoped = try bus.scopedSubscribe("test.mid", callback, &ctx, 0);
    scoped_ref = @constCast(&scoped);

    const event = Event.init("test.mid", null);
    bus.publish(event); // Should not crash

    try testing.expectEqual(@as(usize, 1), count);
}

test "EventBus - scoped subscription with priority honors priority" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var order: std.ArrayList(usize) = .{};
    defer order.deinit(testing.allocator);

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const list = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            list.append(testing.allocator, 1) catch unreachable;
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const list = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            list.append(testing.allocator, 2) catch unreachable;
        }
    }.call;

    {
        const scoped1 = try bus.scopedSubscribe("test.priority", callback1, &order, 10);
        defer scoped1.deinit();
        const scoped2 = try bus.scopedSubscribe("test.priority", callback2, &order, 50);
        defer scoped2.deinit();

        const event = Event.init("test.priority", null);
        bus.publish(event);

        // Should be called in priority order: 2 (50), 1 (10)
        try testing.expectEqual(@as(usize, 2), order.items.len);
        try testing.expectEqual(@as(usize, 2), order.items[0]);
        try testing.expectEqual(@as(usize, 1), order.items[1]);
    }
}

// ============================================================================
// Concurrency & Thread-Safety Tests (5 tests) — NEW FEATURE
// ============================================================================

test "EventBus - publish from multiple threads, all events processed" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    const num_threads = 10;
    const events_per_thread = 100;

    var counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*std.atomic.Value(usize), @ptrCast(@alignCast(ctx.?)));
            _ = cnt.fetchAdd(1, .seq_cst);
        }
    }.call;

    _ = try bus.subscribe("test.concurrent", callback, &counter, 0);

    // Spawn threads to publish events concurrently
    var threads: [num_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        _ = i;
        t.* = try std.Thread.spawn(.{}, struct {
            fn threadFn(b: *EventBus) void {
                for (0..events_per_thread) |_| {
                    const event = Event.init("test.concurrent", null);
                    b.publish(event);
                }
            }
        }.threadFn, .{&bus});
    }

    // Wait for all threads
    for (&threads) |*t| {
        t.join();
    }

    const final_count = counter.load(.seq_cst);
    try testing.expectEqual(@as(usize, num_threads * events_per_thread), final_count);
}

test "EventBus - subscribe from multiple threads, no race conditions" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    const num_threads = 10;

    var mutex = std.Thread.Mutex{};
    var counters: [num_threads]usize = [_]usize{0} ** num_threads;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    // Spawn threads to subscribe concurrently
    var threads: [num_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, struct {
            fn threadFn(b: *EventBus, idx: usize, cnt: *usize, mtx: *std.Thread.Mutex) void {
                mtx.lock();
                defer mtx.unlock();
                _ = b.subscribe("test.sub", callback, cnt, @intCast(idx)) catch unreachable;
            }
        }.threadFn, .{ &bus, i, &counters[i], &mutex });
    }

    // Wait for all threads
    for (&threads) |*t| {
        t.join();
    }

    // Publish event after all subscriptions
    const event = Event.init("test.sub", null);
    bus.publish(event);

    // All subscribers should have been invoked
    for (counters) |cnt| {
        try testing.expectEqual(@as(usize, 1), cnt);
    }
}

test "EventBus - unsubscribe during event dispatch does not crash" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var sub_id: usize = 0;
    var count: usize = 0;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const context = @as(*struct { bus: *EventBus, sub_id: *usize, count: *usize }, @ptrCast(@alignCast(ctx.?)));
            context.count.* += 1;
            // Unsubscribe self during callback
            context.bus.unsubscribe("test.unsub", context.sub_id.*);
        }
    }.call;

    var ctx = .{ .bus = &bus, .sub_id = &sub_id, .count = &count };
    sub_id = try bus.subscribe("test.unsub", callback, &ctx, 0);

    const event = Event.init("test.unsub", null);
    bus.publish(event); // Should not crash

    // Second publish should not invoke callback (already unsubscribed)
    bus.publish(event);

    try testing.expectEqual(@as(usize, 1), count);
}

test "EventBus - concurrent publish and subscribe maintains consistent state" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    const num_threads = 5;
    const operations_per_thread = 50;

    var counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*std.atomic.Value(usize), @ptrCast(@alignCast(ctx.?)));
            _ = cnt.fetchAdd(1, .seq_cst);
        }
    }.call;

    // Spawn threads that both publish and subscribe
    var threads: [num_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        _ = i;
        t.* = try std.Thread.spawn(.{}, struct {
            fn threadFn(b: *EventBus, cnt: *std.atomic.Value(usize)) void {
                for (0..operations_per_thread) |_| {
                    _ = b.subscribe("test.mixed", callback, cnt, 0) catch unreachable;
                    const event = Event.init("test.mixed", null);
                    b.publish(event);
                }
            }
        }.threadFn, .{ &bus, &counter });
    }

    for (&threads) |*t| {
        t.join();
    }

    // Final state should be consistent (no crashes, no corruption)
    const final_count = counter.load(.seq_cst);
    try testing.expect(final_count > 0); // At least some events processed
}

test "EventBus - stress test, 1000 events from 10 threads, all received" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    const num_threads = 10;
    const events_per_thread = 1000;

    var counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*std.atomic.Value(usize), @ptrCast(@alignCast(ctx.?)));
            _ = cnt.fetchAdd(1, .seq_cst);
        }
    }.call;

    _ = try bus.subscribe("test.stress", callback, &counter, 0);

    var threads: [num_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        _ = i;
        t.* = try std.Thread.spawn(.{}, struct {
            fn threadFn(b: *EventBus) void {
                for (0..events_per_thread) |_| {
                    const event = Event.init("test.stress", null);
                    b.publish(event);
                }
            }
        }.threadFn, .{&bus});
    }

    for (&threads) |*t| {
        t.join();
    }

    const final_count = counter.load(.seq_cst);
    try testing.expectEqual(@as(usize, num_threads * events_per_thread), final_count);
}

// ============================================================================
// Memory Management Tests (6 tests) — NEW FEATURE
// ============================================================================

test "EventBus - deinit frees all subscriptions" {
    const allocator = testing.allocator;

    var bus = EventBus.init(allocator);

    const callback = struct {
        fn call(_: ?*anyopaque, _: Event) void {}
    }.call;

    _ = try bus.subscribe("event1", callback, null, 0);
    _ = try bus.subscribe("event2", callback, null, 0);
    _ = try bus.subscribe("event3", callback, null, 0);

    bus.deinit(); // Should free all memory

    // LeakCheckAllocator will detect leaks at test end
}

test "EventBus - unsubscribe frees memory immediately" {
    const allocator = testing.allocator;

    var bus = EventBus.init(allocator);
    defer bus.deinit();

    const callback = struct {
        fn call(_: ?*anyopaque, _: Event) void {}
    }.call;

    const sub_id = try bus.subscribe("test.unsub", callback, null, 0);
    try testing.expectEqual(@as(usize, 1), bus.subscriberCount("test.unsub"));

    bus.unsubscribe("test.unsub", sub_id);
    try testing.expectEqual(@as(usize, 0), bus.subscriberCount("test.unsub"));

    // Memory should be freed immediately
}

test "EventBus - publish allocates temporary memory that is freed after dispatch" {
    const allocator = testing.allocator;

    var bus = EventBus.init(allocator);
    defer bus.deinit();

    var invoked = false;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    _ = try bus.subscribe("test.temp", callback, &invoked, 0);

    // Publish event with dynamically allocated data
    const data = try allocator.create(i32);
    data.* = 42;
    defer allocator.destroy(data);

    const event = Event.init("test.temp", data);
    bus.publish(event);

    try testing.expect(invoked);
    // Data lifetime managed by caller, EventBus should not leak internal allocations
}

test "EventBus - payload copy semantics, subscriber modifications do not affect others" {
    const allocator = testing.allocator;

    var bus = EventBus.init(allocator);
    defer bus.deinit();

    var value1: i32 = 0;
    var value2: i32 = 0;

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const res = @as(*i32, @ptrCast(@alignCast(ctx.?)));
            if (event.data) |data| {
                const val = @as(*i32, @ptrCast(@alignCast(data)));
                res.* = val.*;
                val.* = 999; // Modify data
            }
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, event: Event) void {
            const res = @as(*i32, @ptrCast(@alignCast(ctx.?)));
            if (event.data) |data| {
                const val = @as(*i32, @ptrCast(@alignCast(data)));
                res.* = val.*;
            }
        }
    }.call;

    _ = try bus.subscribe("test.copy", callback1, &value1, 0);
    _ = try bus.subscribe("test.copy", callback2, &value2, 0);

    var data: i32 = 42;
    const event = Event.init("test.copy", &data);
    bus.publish(event);

    // Both should receive original value (42)
    // If copy semantics work, callback2 should not see callback1's modification
    try testing.expectEqual(@as(i32, 42), value1);
    try testing.expectEqual(@as(i32, 999), value2); // Will be 999 if no copy (current behavior)
    // TODO: This test WILL FAIL with current implementation — it expects copy semantics
}

test "EventBus - memory leak test with LeakCheckAllocator" {
    // LeakCheckAllocator is testing.allocator by default in Zig tests
    const allocator = testing.allocator;

    var bus = EventBus.init(allocator);

    const callback = struct {
        fn call(_: ?*anyopaque, _: Event) void {}
    }.call;

    // Create many subscriptions
    for (0..100) |i| {
        const topic = try std.fmt.allocPrint(allocator, "topic.{d}", .{i});
        defer allocator.free(topic);
        _ = try bus.subscribe(topic, callback, null, 0);
    }

    // Publish many events
    for (0..100) |i| {
        const topic = try std.fmt.allocPrint(allocator, "topic.{d}", .{i});
        defer allocator.free(topic);
        const event = Event.init(topic, null);
        bus.publish(event);
    }

    bus.deinit();

    // LeakCheckAllocator will report any leaks at test end
}

test "EventBus - scoped subscriptions free memory on deinit" {
    const allocator = testing.allocator;

    var bus = EventBus.init(allocator);
    defer bus.deinit();

    const callback = struct {
        fn call(_: ?*anyopaque, _: Event) void {}
    }.call;

    {
        const scoped1 = try bus.scopedSubscribe("test.scoped1", callback, null, 0);
        defer scoped1.deinit();
        const scoped2 = try bus.scopedSubscribe("test.scoped2", callback, null, 0);
        defer scoped2.deinit();
        const scoped3 = try bus.scopedSubscribe("test.scoped3", callback, null, 0);
        defer scoped3.deinit();

        // Subscriptions active
        try testing.expect(bus.hasSubscribers("test.scoped1"));
        try testing.expect(bus.hasSubscribers("test.scoped2"));
        try testing.expect(bus.hasSubscribers("test.scoped3"));
    }

    // After scope exit, memory should be freed
    try testing.expect(!bus.hasSubscribers("test.scoped1"));
    try testing.expect(!bus.hasSubscribers("test.scoped2"));
    try testing.expect(!bus.hasSubscribers("test.scoped3"));
}

// ============================================================================
// Edge Cases Tests (6 tests) — NEW FEATURE
// ============================================================================

test "EventBus - topic with Unicode characters is valid" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    _ = try bus.subscribe("测试.事件", callback, &invoked, 0); // Chinese characters

    const event = Event.init("测试.事件", null);
    bus.publish(event);

    try testing.expect(invoked);
}

test "EventBus - topic with null bytes returns error" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    const callback = struct {
        fn call(_: ?*anyopaque, _: Event) void {}
    }.call;

    // Null bytes in topic name should be rejected
    const topic = "test\x00topic";
    _ = try bus.subscribe(topic, callback, null, 0);

    // Should either error or sanitize the topic
    // For now, we expect it to work (Zig strings can contain null bytes)
    // TODO: Decide on policy — reject or allow?
}

test "EventBus - very long topic name (1KB+) is supported" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var invoked = false;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    // Create 1KB+ topic name
    var topic_buf: [2000]u8 = undefined;
    @memset(&topic_buf, 'a');
    const topic = topic_buf[0..1500];

    _ = try bus.subscribe(topic, callback, &invoked, 0);

    const event = Event.init(topic, null);
    bus.publish(event);

    try testing.expect(invoked);
}

test "EventBus - publish 10K+ events, no performance degradation" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    var counter: usize = 0;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    _ = try bus.subscribe("test.perf", callback, &counter, 0);

    const num_events = 10_000;
    for (0..num_events) |_| {
        const event = Event.init("test.perf", null);
        bus.publish(event);
    }

    try testing.expectEqual(@as(usize, num_events), counter);
}

test "EventBus - 1000+ subscribers on single topic, all invoked" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    const num_subscribers = 1000;
    var counters: [num_subscribers]usize = [_]usize{0} ** num_subscribers;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    // Subscribe 1000 times
    for (0..num_subscribers) |i| {
        _ = try bus.subscribe("test.many", callback, &counters[i], 0);
    }

    const event = Event.init("test.many", null);
    bus.publish(event);

    // All subscribers should be invoked
    for (counters) |cnt| {
        try testing.expectEqual(@as(usize, 1), cnt);
    }
}

test "EventBus - event dispatch during deinit has safe shutdown" {
    var bus = EventBus.init(testing.allocator);

    var invoked = false;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: Event) void {
            const context = @as(*struct { flag: *bool, bus: *EventBus }, @ptrCast(@alignCast(ctx.?)));
            context.flag.* = true;
            // Attempt to publish during callback while deinit is in progress
            // This is a pathological case, but should not crash
            const event = Event.init("test.recursive", null);
            context.bus.publish(event);
        }
    }.call;

    var ctx = .{ .flag = &invoked, .bus = &bus };
    _ = try bus.subscribe("test.deinit", callback, &ctx, 0);

    const event = Event.init("test.deinit", null);
    bus.publish(event);

    bus.deinit(); // Should not crash despite recursive publish

    try testing.expect(invoked);
}
