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
pub const EventBus = struct {
    allocator: Allocator,
    subscribers: std.StringHashMap(SubscriberList),

    const SubscriberList = std.ArrayList(Subscriber);
    const StringHashMap = std.StringHashMap(SubscriberList);

    const Subscriber = struct {
        callback: *const fn (ctx: ?*anyopaque, event: Event) void,
        context: ?*anyopaque,
        priority: i32, // Higher priority = earlier dispatch

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
        };
    }

    /// Clean up event bus.
    pub fn deinit(self: *EventBus) void {
        var it = self.subscribers.iterator();
        while (it.next()) |entry| {
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
        const gop = try self.subscribers.getOrPut(event_type);
        if (!gop.found_existing) {
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
            if (s.callback == callback and s.context == context) {
                return idx;
            }
        }
        return gop.value_ptr.items.len - 1;
    }

    /// Unsubscribe from an event type by subscription ID.
    pub fn unsubscribe(self: *EventBus, event_type: []const u8, subscription_id: usize) void {
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
    pub fn publish(self: *EventBus, event: Event) void {
        if (self.subscribers.get(event.type)) |list| {
            for (list.items) |sub| {
                sub.callback(sub.context, event);
            }
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

    // Should not crash when publishing to non-existent event type
    const event = EventBus.Event.init("nonexistent.event", null);
    bus.publish(event);
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

    // Should not crash
    bus.unsubscribe("test.event", 999);
    bus.unsubscribe("nonexistent.event", 0);
}
