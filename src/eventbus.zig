// eventbus.zig — Event bus for pub/sub cross-widget communication
//
// Provides a type-safe publish-subscribe system for decoupled widget communication.
// Supports priority-based dispatch, multiple subscribers per event type, and custom data payloads.
//
// Example usage:
//   var bus = EventBus.init(allocator);
//   defer bus.deinit();
//
//   // Subscribe to an event
//   const id = try bus.subscribe("button.clicked", handleButtonClick, &context, 0);
//
//   // Publish an event with data
//   var data = ButtonData{ .label = "OK" };
//   try bus.publish(Event.init("button.clicked", &data));
//
//   // Unsubscribe when done
//   bus.unsubscribe("button.clicked", id);

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Event bus for pub/sub cross-widget communication.
/// Supports typed events, multiple subscribers per event type, and priority-based dispatch.
/// Thread-safe for concurrent publish/subscribe operations.
pub const EventBus = struct {
    allocator: Allocator,
    subscribers: std.StringHashMap(SubscriberList),
    mutex: std.Thread.Mutex,
    alive: bool,

    const SubscriberList = std.ArrayList(Subscriber);
    const StringHashMap = std.StringHashMap(SubscriberList);

    /// Subscriber with optional filter and transformation functions
    const Subscriber = struct {
        callback: *const fn (ctx: ?*anyopaque, event: Event) void,
        context: ?*anyopaque,
        priority: i32, // Higher priority = earlier dispatch
        filter: ?*const fn (event: Event) bool = null,
        transform: ?*const fn (allocator: Allocator, event: Event) anyerror!Event = null,

        fn compare(_: void, a: Subscriber, b: Subscriber) bool {
            return a.priority > b.priority; // Descending order
        }
    };

    /// Event payload.
    pub const Event = struct {
        type: []const u8,
        data: ?*anyopaque = null,

        pub fn init(event_type: []const u8, data: ?*anyopaque) Event {
            return .{ .type = event_type, .data = data };
        }
    };

    /// Initialize event bus.
    pub fn init(allocator: Allocator) EventBus {
        return .{
            .allocator = allocator,
            .subscribers = StringHashMap.init(allocator),
            .mutex = .{},
            .alive = true,
        };
    }

    /// Clean up event bus.
    pub fn deinit(self: *EventBus) void {
        self.mutex.lock();
        self.alive = false;
        self.mutex.unlock();

        var it = self.subscribers.iterator();
        while (it.next()) |entry| {
            // Free the copied event type string
            self.allocator.free(entry.key_ptr.*);
            // Free the subscriber list
            entry.value_ptr.deinit(self.allocator);
        }
        self.subscribers.deinit();
    }

    /// Subscribe to an event type.
    /// Returns subscription ID (index in subscriber list).
    pub fn subscribe(
        self: *EventBus,
        event_type: []const u8,
        callback: *const fn (ctx: ?*anyopaque, event: Event) void,
        context: ?*anyopaque,
        priority: i32,
    ) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const gop = try self.subscribers.getOrPut(event_type);
        if (!gop.found_existing) {
            // Copy the event type string (caller doesn't need to keep it alive)
            const event_type_copy = try self.allocator.dupe(u8, event_type);
            gop.key_ptr.* = event_type_copy;
            gop.value_ptr.* = .{};
        }

        const sub = Subscriber{
            .callback = callback,
            .context = context,
            .priority = priority,
        };

        try gop.value_ptr.append(self.allocator, sub);

        // Sort by priority (descending)
        std.mem.sort(Subscriber, gop.value_ptr.items, {}, Subscriber.compare);

        // Return index after sorting
        for (gop.value_ptr.items, 0..) |s, idx| {
            if (s.callback == callback and s.context == context and s.filter == null and s.transform == null) {
                return idx;
            }
        }
        return gop.value_ptr.items.len - 1;
    }

    /// Subscribe with event filter.
    /// Returns subscription ID (index in subscriber list).
    pub fn subscribeFiltered(
        self: *EventBus,
        event_type: []const u8,
        filter: *const fn (event: Event) bool,
        callback: *const fn (ctx: ?*anyopaque, event: Event) void,
        context: ?*anyopaque,
        priority: i32,
    ) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const gop = try self.subscribers.getOrPut(event_type);
        if (!gop.found_existing) {
            // Copy the event type string (caller doesn't need to keep it alive)
            const event_type_copy = try self.allocator.dupe(u8, event_type);
            gop.key_ptr.* = event_type_copy;
            gop.value_ptr.* = .{};
        }

        const sub = Subscriber{
            .callback = callback,
            .context = context,
            .priority = priority,
            .filter = filter,
        };

        try gop.value_ptr.append(self.allocator, sub);

        // Sort by priority (descending)
        std.mem.sort(Subscriber, gop.value_ptr.items, {}, Subscriber.compare);

        // Return index after sorting
        for (gop.value_ptr.items, 0..) |s, idx| {
            if (s.callback == callback and s.context == context and s.filter == filter) {
                return idx;
            }
        }
        return gop.value_ptr.items.len - 1;
    }

    /// Subscribe with event transformation.
    /// Returns subscription ID (index in subscriber list).
    pub fn subscribeTransformed(
        self: *EventBus,
        event_type: []const u8,
        transform: *const fn (allocator: Allocator, event: Event) anyerror!Event,
        callback: *const fn (ctx: ?*anyopaque, event: Event) void,
        context: ?*anyopaque,
        priority: i32,
    ) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const gop = try self.subscribers.getOrPut(event_type);
        if (!gop.found_existing) {
            // Copy the event type string (caller doesn't need to keep it alive)
            const event_type_copy = try self.allocator.dupe(u8, event_type);
            gop.key_ptr.* = event_type_copy;
            gop.value_ptr.* = .{};
        }

        const sub = Subscriber{
            .callback = callback,
            .context = context,
            .priority = priority,
            .transform = transform,
        };

        try gop.value_ptr.append(self.allocator, sub);

        // Sort by priority (descending)
        std.mem.sort(Subscriber, gop.value_ptr.items, {}, Subscriber.compare);

        // Return index after sorting
        for (gop.value_ptr.items, 0..) |s, idx| {
            if (s.callback == callback and s.context == context and s.transform == transform) {
                return idx;
            }
        }
        return gop.value_ptr.items.len - 1;
    }

    /// Scoped subscription that auto-unsubscribes on deinit (RAII)
    pub const ScopedSubscription = struct {
        bus: *EventBus,
        event_type: []const u8,
        id: usize,

        pub fn deinit(self: ScopedSubscription) void {
            // Check if bus is still alive before trying to unsubscribe
            self.bus.mutex.lock();
            const alive = self.bus.alive;
            self.bus.mutex.unlock();

            if (alive) {
                self.bus.unsubscribe(self.event_type, self.id);
            }
        }
    };

    /// Subscribe with scoped subscription (RAII auto-unsubscribe)
    pub fn scopedSubscribe(
        self: *EventBus,
        event_type: []const u8,
        callback: *const fn (ctx: ?*anyopaque, event: Event) void,
        context: ?*anyopaque,
        priority: i32,
    ) !ScopedSubscription {
        const id = try self.subscribe(event_type, callback, context, priority);
        return ScopedSubscription{
            .bus = self,
            .event_type = event_type,
            .id = id,
        };
    }

    /// Unsubscribe from an event type by subscription ID.
    pub fn unsubscribe(self: *EventBus, event_type: []const u8, subscription_id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.subscribers.getPtr(event_type)) |list| {
            if (subscription_id < list.items.len) {
                _ = list.orderedRemove(subscription_id);
            }
        }
    }

    /// Unsubscribe all subscribers for an event type.
    pub fn unsubscribeAll(self: *EventBus, event_type: []const u8) void {
        if (self.subscribers.getPtr(event_type)) |list| {
            list.clearRetainingCapacity();
        }
    }

    /// Publish an event to all subscribers.
    /// Handles filtering and transformation.
    pub fn publish(self: *EventBus, event: Event) void {
        // Use arena allocator for temporary allocations (transformations + subscriber list copy)
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        // Copy subscriber list under lock to avoid iterator invalidation
        // when callbacks modify subscriptions
        const subscribers_copy = blk: {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.subscribers.get(event.type)) |list| {
                const copy = temp_allocator.alloc(Subscriber, list.items.len) catch return;
                @memcpy(copy, list.items);
                break :blk copy;
            } else {
                break :blk &[_]Subscriber{};
            }
        };

        // Dispatch events without holding lock (callbacks may call subscribe/unsubscribe)
        for (subscribers_copy) |sub| {
            // Apply filter if present
            if (sub.filter) |filter| {
                if (!filter(event)) {
                    continue; // Skip this subscriber
                }
            }

            // Apply transformation if present
            var transformed_event = event;
            if (sub.transform) |transform| {
                transformed_event = transform(temp_allocator, event) catch {
                    // Transformation failed, skip this subscriber
                    continue;
                };
            }

            // Invoke callback with (potentially transformed) event
            sub.callback(sub.context, transformed_event);
        }
    }

    /// Get subscriber count for an event type.
    pub fn subscriberCount(self: *EventBus, event_type: []const u8) usize {
        if (self.subscribers.get(event_type)) |list| {
            return list.items.len;
        }
        return 0;
    }

    /// Check if an event type has any subscribers.
    pub fn hasSubscribers(self: *EventBus, event_type: []const u8) bool {
        return self.subscriberCount(event_type) > 0;
    }

    /// Get all registered event types.
    pub fn eventTypes(self: *EventBus, allocator: Allocator) ![][]const u8 {
        var types: std.ArrayList([]const u8) = .{};
        var it = self.subscribers.keyIterator();
        while (it.next()) |key| {
            try types.append(allocator, key.*);
        }
        return types.toOwnedSlice(allocator);
    }
};

// Tests
test "EventBus: init and deinit" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    try std.testing.expectEqual(@as(usize, 0), bus.subscribers.count());
}

test "EventBus: subscribe and publish" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    var counter: usize = 0;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    _ = try bus.subscribe("test.event", callback, &counter, 0);

    const event = EventBus.Event.init("test.event", null);
    bus.publish(event);

    try std.testing.expectEqual(@as(usize, 1), counter);
}

test "EventBus: multiple subscribers" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    var counter1: usize = 0;
    var counter2: usize = 0;

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 10;
        }
    }.call;

    _ = try bus.subscribe("test.event", callback1, &counter1, 0);
    _ = try bus.subscribe("test.event", callback2, &counter2, 0);

    const event = EventBus.Event.init("test.event", null);
    bus.publish(event);

    try std.testing.expectEqual(@as(usize, 1), counter1);
    try std.testing.expectEqual(@as(usize, 10), counter2);
}

test "EventBus: priority ordering" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    var order: std.ArrayList(usize) = .{};
    defer order.deinit(std.testing.allocator);

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const list = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            list.append(std.testing.allocator, 1) catch unreachable;
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const list = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            list.append(std.testing.allocator, 2) catch unreachable;
        }
    }.call;

    const callback3 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const list = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            list.append(std.testing.allocator, 3) catch unreachable;
        }
    }.call;

    // Subscribe in reverse priority order
    _ = try bus.subscribe("test.event", callback1, &order, 10); // Low priority
    _ = try bus.subscribe("test.event", callback2, &order, 50); // High priority
    _ = try bus.subscribe("test.event", callback3, &order, 30); // Medium priority

    const event = EventBus.Event.init("test.event", null);
    bus.publish(event);

    // Should be called in priority order: 2 (50), 3 (30), 1 (10)
    try std.testing.expectEqual(@as(usize, 3), order.items.len);
    try std.testing.expectEqual(@as(usize, 2), order.items[0]);
    try std.testing.expectEqual(@as(usize, 3), order.items[1]);
    try std.testing.expectEqual(@as(usize, 1), order.items[2]);
}

test "EventBus: unsubscribe" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    var counter: usize = 0;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    const sub_id = try bus.subscribe("test.event", callback, &counter, 0);

    const event = EventBus.Event.init("test.event", null);
    bus.publish(event);
    try std.testing.expectEqual(@as(usize, 1), counter);

    bus.unsubscribe("test.event", sub_id);
    bus.publish(event);
    try std.testing.expectEqual(@as(usize, 1), counter); // Should not increment
}

test "EventBus: unsubscribeAll" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    var counter1: usize = 0;
    var counter2: usize = 0;

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 10;
        }
    }.call;

    _ = try bus.subscribe("test.event", callback1, &counter1, 0);
    _ = try bus.subscribe("test.event", callback2, &counter2, 0);

    const event = EventBus.Event.init("test.event", null);
    bus.publish(event);
    try std.testing.expectEqual(@as(usize, 1), counter1);
    try std.testing.expectEqual(@as(usize, 10), counter2);

    bus.unsubscribeAll("test.event");
    bus.publish(event);
    try std.testing.expectEqual(@as(usize, 1), counter1); // Should not increment
    try std.testing.expectEqual(@as(usize, 10), counter2); // Should not increment
}

test "EventBus: subscriberCount" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    try std.testing.expectEqual(@as(usize, 0), bus.subscriberCount("test.event"));

    const callback = struct {
        fn call(_: ?*anyopaque, _: EventBus.Event) void {}
    }.call;

    _ = try bus.subscribe("test.event", callback, null, 0);
    try std.testing.expectEqual(@as(usize, 1), bus.subscriberCount("test.event"));

    _ = try bus.subscribe("test.event", callback, null, 0);
    try std.testing.expectEqual(@as(usize, 2), bus.subscriberCount("test.event"));
}

test "EventBus: hasSubscribers" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    try std.testing.expectEqual(false, bus.hasSubscribers("test.event"));

    const callback = struct {
        fn call(_: ?*anyopaque, _: EventBus.Event) void {}
    }.call;

    _ = try bus.subscribe("test.event", callback, null, 0);
    try std.testing.expectEqual(true, bus.hasSubscribers("test.event"));
}

test "EventBus: eventTypes" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    const callback = struct {
        fn call(_: ?*anyopaque, _: EventBus.Event) void {}
    }.call;

    _ = try bus.subscribe("event1", callback, null, 0);
    _ = try bus.subscribe("event2", callback, null, 0);
    _ = try bus.subscribe("event3", callback, null, 0);

    const types = try bus.eventTypes(std.testing.allocator);
    defer std.testing.allocator.free(types);

    try std.testing.expectEqual(@as(usize, 3), types.len);
}

test "EventBus: event with data" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    var result: i32 = 0;

    const callback = struct {
        fn call(ctx: ?*anyopaque, event: EventBus.Event) void {
            const res = @as(*i32, @ptrCast(@alignCast(ctx.?)));
            const data = @as(*i32, @ptrCast(@alignCast(event.data.?)));
            res.* = data.*;
        }
    }.call;

    _ = try bus.subscribe("data.event", callback, &result, 0);

    var value: i32 = 42;
    const event = EventBus.Event.init("data.event", &value);
    bus.publish(event);

    try std.testing.expectEqual(@as(i32, 42), result);
}

test "EventBus: no subscribers for event type" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    // Assert bus is empty before publish
    try std.testing.expectEqual(@as(usize, 0), bus.subscribers.count());
    try std.testing.expectEqual(@as(usize, 0), bus.subscriberCount("nonexistent.event"));

    // Should not crash when publishing to non-existent event type
    const event = EventBus.Event.init("nonexistent.event", null);
    bus.publish(event);

    // Assert bus remains empty after publish (true no-op)
    try std.testing.expectEqual(@as(usize, 0), bus.subscribers.count());
    try std.testing.expectEqual(@as(usize, 0), bus.subscriberCount("nonexistent.event"));
}

test "EventBus: multiple event types" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    var counter1: usize = 0;
    var counter2: usize = 0;

    const callback1 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.call;

    const callback2 = struct {
        fn call(ctx: ?*anyopaque, _: EventBus.Event) void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 10;
        }
    }.call;

    _ = try bus.subscribe("event1", callback1, &counter1, 0);
    _ = try bus.subscribe("event2", callback2, &counter2, 0);

    const event1 = EventBus.Event.init("event1", null);
    const event2 = EventBus.Event.init("event2", null);

    bus.publish(event1);
    try std.testing.expectEqual(@as(usize, 1), counter1);
    try std.testing.expectEqual(@as(usize, 0), counter2);

    bus.publish(event2);
    try std.testing.expectEqual(@as(usize, 1), counter1);
    try std.testing.expectEqual(@as(usize, 10), counter2);
}

test "EventBus: unsubscribe invalid ID" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    const callback = struct {
        fn call(_: ?*anyopaque, _: EventBus.Event) void {}
    }.call;

    _ = try bus.subscribe("test.event", callback, null, 0);
    try std.testing.expectEqual(@as(usize, 1), bus.subscriberCount("test.event"));

    // Unsubscribe with invalid IDs (should not crash or corrupt state)
    bus.unsubscribe("test.event", 999);
    try std.testing.expectEqual(@as(usize, 1), bus.subscriberCount("test.event")); // Still there

    bus.unsubscribe("nonexistent.event", 0);
    try std.testing.expectEqual(@as(usize, 0), bus.subscriberCount("nonexistent.event")); // Nonexistent stays empty
    try std.testing.expectEqual(@as(usize, 1), bus.subscriberCount("test.event")); // Real subscriber unchanged
}
