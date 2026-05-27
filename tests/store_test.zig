//! Comprehensive tests for sailor's Store state management (v2.12.0)
//!
//! Tests for Store(State, Action) - centralized state with reducer pattern.
//!
//! Coverage:
//! - Store lifecycle (init, deinit)
//! - Store.getState() returns current state
//! - Store.dispatch(action) calls reducer, updates state
//! - Multiple action types (increment, decrement, reset, etc.)
//! - Multiple subscribers to store
//! - Subscriber removal (unsubscribe)
//! - State immutability (state changes create new values)
//! - Sequential dispatches produce correct final state
//! - Dispatch with zero subscribers (no crash)
//! - Custom action enums
//! - Struct-based states with multiple fields
//! - Error handling in reducers

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const store_mod = sailor; // store.zig will be exported from sailor.zig

// ============================================================================
// Example State & Action Types
// ============================================================================

const CounterState = struct {
    count: i32,
    name: []const u8,
};

const CounterAction = union(enum) {
    increment,
    decrement,
    reset,
    add: i32,
};

fn counterReducer(state: CounterState, action: CounterAction, allocator: std.mem.Allocator) !CounterState {
    _ = allocator; // May be needed for string allocation
    switch (action) {
        .increment => return .{ .count = state.count + 1, .name = state.name },
        .decrement => return .{ .count = state.count - 1, .name = state.name },
        .reset => return .{ .count = 0, .name = state.name },
        .add => |n| return .{ .count = state.count + n, .name = state.name },
    }
}

// ============================================================================
// Store Lifecycle Tests
// ============================================================================

test "Store init creates with initial state" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    const state = store.getState();
    try testing.expectEqual(@as(i32, 0), state.count);
    try testing.expectEqualStrings("test", state.name);
}

test "Store.getState() returns current state" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 5, .name = "counter" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    const state = store.getState();
    try testing.expectEqual(@as(i32, 5), state.count);
    try testing.expectEqualStrings("counter", state.name);
}

test "Store deinit cleans up memory" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );

    var listener_count: i32 = 0;
    const listener = struct {
        fn callback(_: CounterState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    const sub_id = try store.subscribe(&listener_count, listener);
    // Verify listener was registered
    try testing.expectEqual(@as(usize, 1), store.listeners.items.len);
    store.unsubscribe(sub_id);
    // After unsubscribe, no listeners remain
    try testing.expectEqual(@as(usize, 0), store.listeners.items.len);
    store.deinit(allocator);
    // testing.allocator will catch any leaks automatically
}

// ============================================================================
// Store Dispatch Tests
// ============================================================================

test "Store.dispatch updates state via reducer" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    try store.dispatch(.increment);
    const state1 = store.getState();
    try testing.expectEqual(@as(i32, 1), state1.count);

    try store.dispatch(.increment);
    const state2 = store.getState();
    try testing.expectEqual(@as(i32, 2), state2.count);

    try store.dispatch(.decrement);
    const state3 = store.getState();
    try testing.expectEqual(@as(i32, 1), state3.count);
}

test "Store.dispatch with payload action" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    try store.dispatch(.{ .add = 5 });
    try testing.expectEqual(@as(i32, 5), store.getState().count);

    try store.dispatch(.{ .add = 10 });
    try testing.expectEqual(@as(i32, 15), store.getState().count);

    try store.dispatch(.{ .add = -3 });
    try testing.expectEqual(@as(i32, 12), store.getState().count);
}

test "Store.dispatch reset action" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 42, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    try store.dispatch(.reset);
    try testing.expectEqual(@as(i32, 0), store.getState().count);
}

test "Store sequential dispatches produce correct state" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    try store.dispatch(.increment);
    try store.dispatch(.increment);
    try store.dispatch(.{ .add = 5 });
    try store.dispatch(.decrement);
    try store.dispatch(.reset);

    try testing.expectEqual(@as(i32, 0), store.getState().count);
}

test "Store dispatch with zero subscribers" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    // Dispatch without any subscribers (should not crash)
    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), store.getState().count);

    try store.dispatch(.{ .add = 10 });
    try testing.expectEqual(@as(i32, 11), store.getState().count);
}

// ============================================================================
// Store Subscriber Tests
// ============================================================================

test "Store.subscribe calls listener after dispatch" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    var listener_calls: i32 = 0;
    const listener = struct {
        fn callback(_: CounterState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try store.subscribe(&listener_calls, listener);

    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), listener_calls);

    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 2), listener_calls);
}

test "Store multiple subscribers all called" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    var calls1: i32 = 0;
    var calls2: i32 = 0;
    var calls3: i32 = 0;

    const listener = struct {
        fn callback(_: CounterState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try store.subscribe(&calls1, listener);
    _ = try store.subscribe(&calls2, listener);
    _ = try store.subscribe(&calls3, listener);

    try store.dispatch(.increment);

    try testing.expectEqual(@as(i32, 1), calls1);
    try testing.expectEqual(@as(i32, 1), calls2);
    try testing.expectEqual(@as(i32, 1), calls3);
}

test "Store subscriber receives new state" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    var last_count: i32 = 0;
    const store_count = struct {
        fn callback(state: CounterState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* = state.count;
        }
    }.callback;

    _ = try store.subscribe(&last_count, store_count);

    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), last_count);

    try store.dispatch(.{ .add = 5 });
    try testing.expectEqual(@as(i32, 6), last_count);
}

test "Store.unsubscribe prevents listener from being called" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    var listener_calls: i32 = 0;
    const listener = struct {
        fn callback(_: CounterState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    const sub_id = try store.subscribe(&listener_calls, listener);

    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), listener_calls);

    store.unsubscribe(sub_id);

    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), listener_calls);
}

// ============================================================================
// Custom Action & State Tests
// ============================================================================

const TodoItem = struct {
    id: u32,
    text: []const u8,
    completed: bool,
};

const TodoState = struct {
    items: std.ArrayList(TodoItem),
    next_id: u32,
};

const TodoAction = union(enum) {
    add: []const u8,
    toggle: u32,
    clear_completed,
};

fn todoReducer(state: TodoState, action: TodoAction, allocator: std.mem.Allocator) !TodoState {
    var new_state = state;
    switch (action) {
        .add => |text| {
            // Note: Real implementation would allocate string copy
            // For test, we use the provided slice
            try new_state.items.append(allocator, .{
                .id = state.next_id,
                .text = text,
                .completed = false,
            });
            new_state.next_id += 1;
        },
        .toggle => |id| {
            for (new_state.items.items) |*item| {
                if (item.id == id) {
                    item.completed = !item.completed;
                }
            }
        },
        .clear_completed => {
            var i: usize = 0;
            while (i < new_state.items.items.len) {
                if (new_state.items.items[i].completed) {
                    _ = new_state.items.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        },
    }
    return new_state;
}

test "Store with complex state type" {
    const allocator = testing.allocator;

    var items: std.ArrayList(TodoItem) = .{};
    defer items.deinit(allocator);

    const initial_state: TodoState = .{
        .items = items,
        .next_id = 0,
    };

    var store = try store_mod.Store(TodoState, TodoAction).init(
        allocator,
        initial_state,
        todoReducer,
    );
    defer store.deinit(allocator);

    const state = store.getState();
    try testing.expectEqual(@as(u32, 0), state.next_id);
    try testing.expectEqual(@as(usize, 0), state.items.items.len);
}

// ============================================================================
// Reducer Error Handling Tests
// ============================================================================

const SimpleState = struct {
    value: i32,
};

const SimpleAction = union(enum) {
    increment,
    error_action,
};

fn errorReducer(state: SimpleState, action: SimpleAction, _: std.mem.Allocator) !SimpleState {
    switch (action) {
        .increment => return .{ .value = state.value + 1 },
        .error_action => return error.TestError,
    }
}

test "Store handles reducer errors gracefully" {
    const allocator = testing.allocator;
    const initial_state: SimpleState = .{ .value = 0 };

    var store = try store_mod.Store(SimpleState, SimpleAction).init(
        allocator,
        initial_state,
        errorReducer,
    );
    defer store.deinit(allocator);

    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), store.getState().value);

    // Dispatch an error action - store should handle it gracefully
    _ = store.dispatch(.error_action) catch {};
    // Result will be an error, or state may remain unchanged
    // Verify old state is still there
    try testing.expectEqual(@as(i32, 1), store.getState().value);
}

// ============================================================================
// Performance & Stress Tests
// ============================================================================

test "Store handles many sequential operations" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "stress" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        try store.dispatch(.increment);
    }

    try testing.expectEqual(@as(i32, 100), store.getState().count);
}

test "Store with many subscribers" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    var counts: [10]i32 = [_]i32{0} ** 10;

    const listener = struct {
        fn callback(_: CounterState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = try store.subscribe(&counts[i], listener);
    }

    try store.dispatch(.increment);

    i = 0;
    while (i < 10) : (i += 1) {
        try testing.expectEqual(@as(i32, 1), counts[i]);
    }
}

// ============================================================================
// Edge Cases Tests
// ============================================================================

test "Store state name field preserved across dispatches" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "my_counter" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    try store.dispatch(.increment);
    try testing.expectEqualStrings("my_counter", store.getState().name);

    try store.dispatch(.{ .add = 5 });
    try testing.expectEqualStrings("my_counter", store.getState().name);

    try store.dispatch(.reset);
    try testing.expectEqualStrings("my_counter", store.getState().name);
}

test "Store with negative state values" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = -10, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    try testing.expectEqual(@as(i32, -10), store.getState().count);

    try store.dispatch(.decrement);
    try testing.expectEqual(@as(i32, -11), store.getState().count);

    try store.dispatch(.{ .add = 20 });
    try testing.expectEqual(@as(i32, 9), store.getState().count);
}

test "Store multiple subscribe/unsubscribe cycles" {
    const allocator = testing.allocator;
    const initial_state: CounterState = .{ .count = 0, .name = "test" };

    var store = try store_mod.Store(CounterState, CounterAction).init(
        allocator,
        initial_state,
        counterReducer,
    );
    defer store.deinit(allocator);

    var count: i32 = 0;
    const listener = struct {
        fn callback(_: CounterState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    const sub1 = try store.subscribe(&count, listener);
    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), count);

    store.unsubscribe(sub1);
    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), count); // Not incremented after unsubscribe

    const sub2 = try store.subscribe(&count, listener);
    try store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 2), count);

    store.unsubscribe(sub2);
}
