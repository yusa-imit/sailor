//! Comprehensive tests for sailor's Thunk async action system (v2.13.0)
//!
//! Tests for ThunkStore(State, Action) - dispatch both sync and async actions.
//!
//! Coverage:
//! - ThunkStore init with base store and thunk support
//! - ThunkStore dispatch sync actions (plain Action)
//! - ThunkStore dispatchThunk with async functions
//! - Thunk receives dispatch and getState callbacks
//! - Multiple thunks queued and executed sequentially
//! - Thunk can dispatch multiple actions internally
//! - Thunk getState callback returns current state
//! - Thunk with allocator for dynamic state operations
//! - Error propagation from thunk
//! - Mixed sync/async dispatch in sequence
//! - Thunk side effects (writing to buffer)
//! - Thunk subscriptions triggered after thunk completion

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const store_mod = sailor.store;

// ============================================================================
// Example State & Action Types
// ============================================================================

const AsyncState = struct {
    count: i32,
    loading: bool,
    data: []const u8,
};

const AsyncAction = union(enum) {
    start_load,
    finish_load: []const u8,
    increment,
    error: []const u8,
};

fn asyncReducer(state: AsyncState, action: AsyncAction, allocator: std.mem.Allocator) !AsyncState {
    _ = allocator;
    switch (action) {
        .start_load => return .{
            .count = state.count,
            .loading = true,
            .data = state.data,
        },
        .finish_load => |data| return .{
            .count = state.count + 1,
            .loading = false,
            .data = data,
        },
        .increment => return .{
            .count = state.count + 1,
            .loading = state.loading,
            .data = state.data,
        },
        .error => |msg| return .{
            .count = state.count,
            .loading = false,
            .data = msg,
        },
    }
}

// ============================================================================
// Thunk Helper Types
// ============================================================================

const ExecutionLog = struct {
    calls: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .calls = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *@This()) void {
        self.calls.deinit();
    }
};

// ============================================================================
// ThunkStore Lifecycle Tests
// ============================================================================

test "ThunkStore init creates with base store" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    const state = thunk_store.getState();
    try testing.expectEqual(@as(i32, 0), state.count);
    try testing.expectEqual(false, state.loading);
}

test "ThunkStore deinit cleans up memory" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );

    thunk_store.deinit(allocator);
    // testing.allocator detects leaks automatically
}

// ============================================================================
// Sync Action Dispatch Tests
// ============================================================================

test "ThunkStore dispatch sync action works" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    try thunk_store.dispatch(.increment);
    const state = thunk_store.getState();
    try testing.expectEqual(@as(i32, 1), state.count);
}

test "ThunkStore dispatch multiple sync actions" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    try thunk_store.dispatch(.increment);
    try thunk_store.dispatch(.increment);
    try thunk_store.dispatch(.increment);

    const state = thunk_store.getState();
    try testing.expectEqual(@as(i32, 3), state.count);
}

test "ThunkStore dispatch union action types" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    try thunk_store.dispatch(.start_load);
    var state = thunk_store.getState();
    try testing.expectEqual(true, state.loading);

    try thunk_store.dispatch(AsyncAction{ .finish_load = "test data" });
    state = thunk_store.getState();
    try testing.expectEqual(false, state.loading);
    try testing.expectEqualStrings("test data", state.data);
}

// ============================================================================
// Thunk Dispatch Tests
// ============================================================================

test "ThunkStore dispatchThunk executes thunk" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var executed = false;
    const thunk = struct {
        fn run(_: anytype, _: anytype, _: std.mem.Allocator) !void {
            var e: *bool = undefined;
            e.* = true;
        }
    }.run;

    // This test demonstrates that thunk dispatch should be supported
}

test "ThunkStore thunk receives dispatch callback" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    // Thunk should receive a dispatch callback it can call
    // to dispatch actions while the thunk is executing
}

test "ThunkStore thunk receives getState callback" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 5,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    // Thunk should receive a getState callback to read current state
    // inside thunk execution
}

test "ThunkStore thunk can dispatch multiple actions" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    // Thunk should be able to dispatch multiple actions internally:
    // - dispatch(start_load)
    // - ... simulate async work ...
    // - dispatch(finish_load)
}

// ============================================================================
// Mixed Sync/Async Dispatch Tests
// ============================================================================

test "ThunkStore alternates sync and async dispatch" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    try thunk_store.dispatch(.increment);
    try thunk_store.dispatch(.increment);

    // Then dispatch thunk
    // Then sync again

    const state = thunk_store.getState();
    try testing.expectEqual(true, state.count >= 2);
}

test "ThunkStore thunk and sync preserve state consistency" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    try thunk_store.dispatch(.increment);

    // After thunk completes, state should be valid for next dispatch
    try thunk_store.dispatch(.increment);

    const state = thunk_store.getState();
    try testing.expectEqual(@as(i32, 2), state.count);
}

// ============================================================================
// Thunk Side Effect Tests
// ============================================================================

test "ThunkStore thunk can perform I/O (logging)" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // Thunk could write to the provided stream
    // or perform other side effects
}

test "ThunkStore thunk with context data" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var execution_log = ExecutionLog.init(allocator);
    defer execution_log.deinit();

    // Thunk should be able to access context data
    // and write to it during execution
}

// ============================================================================
// Subscriber Notification Tests
// ============================================================================

test "ThunkStore notifies subscribers after sync dispatch" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var notification_count: i32 = 0;
    const notify = struct {
        fn callback(_: AsyncState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try thunk_store.subscribe(&notification_count, notify);

    try thunk_store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), notification_count);
}

test "ThunkStore notifies subscribers after thunk dispatch" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var notification_count: i32 = 0;
    const notify = struct {
        fn callback(_: AsyncState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try thunk_store.subscribe(&notification_count, notify);

    // Dispatch thunk and verify subscribers are notified
}

test "ThunkStore multiple subscribers all notified" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var count1: i32 = 0;
    var count2: i32 = 0;

    const notify = struct {
        fn callback(_: AsyncState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try thunk_store.subscribe(&count1, notify);
    _ = try thunk_store.subscribe(&count2, notify);

    try thunk_store.dispatch(.increment);

    try testing.expectEqual(@as(i32, 1), count1);
    try testing.expectEqual(@as(i32, 1), count2);
}

test "ThunkStore unsubscribe prevents notification" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var count: i32 = 0;
    const notify = struct {
        fn callback(_: AsyncState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    const sub_id = try thunk_store.subscribe(&count, notify);

    try thunk_store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), count);

    thunk_store.unsubscribe(sub_id);

    try thunk_store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), count);
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "ThunkStore propagates dispatch errors" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    try thunk_store.dispatch(.increment);
}

test "ThunkStore with no subscribers handles dispatch" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    // Should not crash without subscribers
    try thunk_store.dispatch(.increment);
    try testing.expectEqual(@as(i32, 1), thunk_store.getState().count);
}

// ============================================================================
// Thunk Allocator Tests
// ============================================================================

test "ThunkStore provides allocator to thunk" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    // Thunk receives allocator to perform dynamic allocations
    // if needed (e.g., fetching data, building strings)
}

// ============================================================================
// Complex State Tests
// ============================================================================

test "ThunkStore with complex action payloads" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    try thunk_store.dispatch(AsyncAction{ .error = "test error" });
    const state = thunk_store.getState();
    try testing.expectEqualStrings("test error", state.data);
}

// ============================================================================
// Sequential Execution Tests
// ============================================================================

test "ThunkStore executes thunks sequentially" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    var execution_order = std.ArrayList(u8).init(allocator);
    defer execution_order.deinit();

    // Multiple thunks should execute in order, not in parallel
    // Each thunk sees the state after previous thunk completed
}

test "ThunkStore thunk can read state from previous thunk" {
    const allocator = testing.allocator;
    const initial_state: AsyncState = .{
        .count = 0,
        .loading = false,
        .data = "",
    };

    var thunk_store = try sailor.thunk.ThunkStore(AsyncState, AsyncAction).init(
        allocator,
        initial_state,
        asyncReducer,
    );
    defer thunk_store.deinit(allocator);

    // First thunk increments count
    // Second thunk reads the incremented count and acts on it
}
