//! State management store with reducer pattern (v2.12.0)
//!
//! Provides a centralized state container with actions and reducer functions.

const std = @import("std");

/// A state container with a reducer function
pub fn Store(State: type, Action: type) type {
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

        /// Initialize a Store with initial state and a reducer function
        pub fn init(
            allocator: std.mem.Allocator,
            initial_state: State,
            reducer: *const fn (State, Action, std.mem.Allocator) anyerror!State,
        ) !Self {
            return Self{
                .state = initial_state,
                .reducer = reducer,
                .listeners = std.ArrayList(Listener).init(allocator),
                .allocator = allocator,
            };
        }

        /// Clean up the store and free all listener memory
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.listeners.deinit();
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

            try self.listeners.append(Listener{
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
