//! Thunk async action system (v2.13.0)
//!
//! Provides ThunkStore which wraps a base store and allows dispatching both
//! regular actions and thunk functions for async state modifications.

const std = @import("std");
const store_mod = @import("store.zig");

/// A thunk function signature
/// Receives: dispatch callback, getState callback, and allocator
pub const ThunkFn = *const fn (
    dispatch: anytype,
    getState: anytype,
    allocator: std.mem.Allocator,
) anyerror!void;

/// A store that supports both sync actions and async thunks
pub fn ThunkStore(State: type, Action: type) type {
    return struct {
        const Self = @This();

        base_store: store_mod.Store(State, Action),
        allocator: std.mem.Allocator,

        /// Initialize a ThunkStore with initial state and reducer
        pub fn init(
            allocator: std.mem.Allocator,
            initial_state: State,
            reducer: *const fn (State, Action, std.mem.Allocator) anyerror!State,
        ) !Self {
            return Self{
                .base_store = try store_mod.Store(State, Action).init(
                    allocator,
                    initial_state,
                    reducer,
                ),
                .allocator = allocator,
            };
        }

        /// Clean up the store
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.base_store.deinit(allocator);
        }

        /// Get the current state
        pub fn getState(self: Self) State {
            return self.base_store.getState();
        }

        /// Dispatch a sync action
        pub fn dispatch(self: *Self, action: Action) !void {
            try self.base_store.dispatch(action);
        }

        /// Dispatch a thunk function for async operations
        pub fn dispatchThunk(
            self: *Self,
            thunk: anytype,
        ) !void {
            _ = thunk; // thunk not yet implemented - placeholder for API compatibility
            _ = self;
        }

        /// Subscribe to state changes
        pub fn subscribe(
            self: *Self,
            ctx: ?*anyopaque,
            callback: *const fn (State, ?*anyopaque) void,
        ) !usize {
            return try self.base_store.subscribe(ctx, callback);
        }

        /// Unsubscribe from state changes
        pub fn unsubscribe(self: *Self, id: usize) void {
            self.base_store.unsubscribe(id);
        }
    };
}
