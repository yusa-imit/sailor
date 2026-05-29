//! Undo/Redo middleware (v2.13.0)
//!
//! Provides UndoStore which wraps a base store and manages undo/redo history
//! with a configurable history limit.

const std = @import("std");
const store_mod = @import("store.zig");

/// A store with undo/redo capability
pub fn UndoStore(State: type, Action: type) type {
    return struct {
        const Self = @This();

        base_store: store_mod.Store(State, Action),
        history: std.ArrayList(State),
        redo_history: std.ArrayList(State),
        allocator: std.mem.Allocator,
        history_limit: usize,
        current_index: usize = 0,

        /// Initialize an UndoStore with initial state, reducer, and history limit
        pub fn init(
            allocator: std.mem.Allocator,
            initial_state: State,
            reducer: *const fn (State, Action, std.mem.Allocator) anyerror!State,
            history_limit: usize,
        ) !Self {
            var history: std.ArrayList(State) = .{};
            try history.append(allocator, initial_state);

            return Self{
                .base_store = try store_mod.Store(State, Action).init(
                    allocator,
                    initial_state,
                    reducer,
                ),
                .history = history,
                .redo_history = std.ArrayList(State){},
                .allocator = allocator,
                .history_limit = history_limit,
                .current_index = 0,
            };
        }

        /// Clean up the store
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.base_store.deinit(allocator);
            self.history.deinit(allocator);
            self.redo_history.deinit(allocator);
        }

        /// Get the current state
        pub fn getState(self: Self) State {
            return self.base_store.getState();
        }

        /// Dispatch an action (records in history and clears redo)
        pub fn dispatch(self: *Self, action: Action) !void {
            try self.base_store.dispatch(action);

            // Add new state to history
            if (self.history.items.len > self.history_limit) {
                // Remove oldest state
                _ = self.history.orderedRemove(0);
            } else {
                self.current_index += 1;
            }

            try self.history.append(self.allocator, self.base_store.getState());

            // Clear redo history on new dispatch
            self.redo_history.clearRetainingCapacity();
        }

        /// Undo the last action
        /// Returns true if undo was successful, false if at initial state
        pub fn undo(self: *Self) bool {
            if (self.current_index == 0) return false;

            // Save current state to redo history
            const current = self.base_store.getState();
            self.redo_history.append(self.allocator, current) catch return false;

            self.current_index -= 1;
            self.base_store.state = self.history.items[self.current_index];

            // Notify listeners
            self.notifyListeners() catch return false;
            return true;
        }

        /// Redo the last undone action
        /// Returns true if redo was successful, false if at latest state
        pub fn redo(self: *Self) bool {
            if (self.redo_history.items.len == 0) return false;

            // Get state from redo history (LIFO)
            const next_state = self.redo_history.pop() orelse return false;

            self.current_index += 1;
            self.base_store.state = next_state;

            // Notify listeners
            self.notifyListeners() catch return false;
            return true;
        }

        /// Check if undo is available
        pub fn canUndo(self: Self) bool {
            return self.current_index > 0;
        }

        /// Check if redo is available
        pub fn canRedo(self: Self) bool {
            return self.redo_history.items.len > 0;
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

        /// Notify all listeners
        fn notifyListeners(self: Self) !void {
            for (self.base_store.listeners.items) |listener| {
                listener.callback(self.base_store.getState(), listener.ctx);
            }
        }
    };
}
