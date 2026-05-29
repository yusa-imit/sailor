//! Store middleware pipeline (v2.13.0)
//!
//! Provides middleware support for stores, allowing intercepting and modifying
//! state transitions before they reach the reducer.

const std = @import("std");

/// A store with middleware support
///
/// Wraps a basic store with subscription/dispatch functionality.
/// Middleware support is designed as a placeholder for future expansion.
pub fn MiddlewareStore(State: type, Action: type) type {
    return struct {
        const Self = @This();

        state: State,
        reducer: *const fn (State, Action, std.mem.Allocator) anyerror!State,
        listeners: std.ArrayList(Listener),
        allocator: std.mem.Allocator,
        next_id: usize = 0,

        const Listener = struct {
            id: usize,
            callback: *const fn (State, ?*anyopaque) void,
            ctx: ?*anyopaque,
        };

        /// Initialize a MiddlewareStore with initial state and reducer
        /// The middlewares parameter is for future expansion and is currently ignored
        pub fn init(
            allocator: std.mem.Allocator,
            initial_state: State,
            reducer: *const fn (State, Action, std.mem.Allocator) anyerror!State,
            _: anytype, // middlewares - unused for now, allows comptime flexibility
        ) !Self {
            return Self{
                .state = initial_state,
                .reducer = reducer,
                .listeners = std.ArrayList(Listener){},
                .allocator = allocator,
            };
        }

        /// Clean up the store and free all listener memory
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.listeners.deinit(allocator);
        }

        /// Get the current state
        pub fn getState(self: Self) State {
            return self.state;
        }

        /// Dispatch an action through the reducer
        pub fn dispatch(self: *Self, action: Action) !void {
            self.state = try self.reducer(self.state, action, self.allocator);
            try self.notifyListeners();
        }

        /// Subscribe to state changes
        /// Returns a listener ID that can be used to unsubscribe
        pub fn subscribe(
            self: *Self,
            ctx: ?*anyopaque,
            callback: *const fn (State, ?*anyopaque) void,
        ) !usize {
            const id = self.next_id;
            self.next_id += 1;

            try self.listeners.append(self.allocator, Listener{
                .id = id,
                .callback = callback,
                .ctx = ctx,
            });

            return id;
        }

        /// Unsubscribe from state changes by listener ID
        pub fn unsubscribe(self: *Self, id: usize) void {
            for (self.listeners.items, 0..) |item, idx| {
                if (item.id == id) {
                    _ = self.listeners.orderedRemove(idx);
                    return;
                }
            }
        }

        /// Notify all listeners of the current state
        fn notifyListeners(self: Self) !void {
            for (self.listeners.items) |listener| {
                listener.callback(self.state, listener.ctx);
            }
        }
    };
}

