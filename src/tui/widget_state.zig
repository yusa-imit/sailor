//! Widget state persistence — save/restore widget state.
//!
//! Provides mechanisms for widgets to save and restore their state.
//! This is useful for session persistence, undo/redo, and state snapshots.
//!
//! ## Features
//! - Type-safe state save/restore
//! - Comptime validation
//! - No allocations for simple states
//! - Structured state types for each widget
//!
//! ## Usage
//! ```zig
//! // Table widget
//! const table_state = table.saveState(allocator, area.width);
//! defer allocator.free(table_state.column_widths);
//! // ... later ...
//! const restored_table = table.restoreState(table_state);
//!
//! // List widget
//! const list_state = list.saveState();
//! const restored_list = list.restoreState(list_state);
//! ```

const std = @import("std");

/// State snapshot for debugging and inspection
pub fn StateSnapshot(comptime T: type) type {
    return struct {
        timestamp: i64,
        state: T,

        pub fn now(state: T) @This() {
            return .{
                .timestamp = std.time.timestamp(),
                .state = state,
            };
        }
    };
}

/// State history for undo/redo functionality
pub fn StateHistory(comptime T: type, comptime max_size: usize) type {
    return struct {
        states: [max_size]T = undefined,
        count: usize = 0,
        current: usize = 0,

        const Self = @This();

        /// Add a new state to history
        pub fn push(self: *Self, state: T) void {
            // If we're not at the end, truncate forward history
            if (self.count > 0 and self.current < self.count - 1) {
                self.count = self.current + 1;
            }

            // Add new state
            if (self.count < max_size) {
                self.states[self.count] = state;
                self.count += 1;
                self.current = self.count - 1;
            } else {
                // Shift left and add at end
                var i: usize = 0;
                while (i < max_size - 1) : (i += 1) {
                    self.states[i] = self.states[i + 1];
                }
                self.states[max_size - 1] = state;
                self.current = max_size - 1;
            }
        }

        /// Undo to previous state
        pub fn undo(self: *Self) ?T {
            if (self.current > 0) {
                self.current -= 1;
                return self.states[self.current];
            }
            return null;
        }

        /// Redo to next state
        pub fn redo(self: *Self) ?T {
            if (self.current < self.count - 1) {
                self.current += 1;
                return self.states[self.current];
            }
            return null;
        }

        /// Get current state
        pub fn current_state(self: Self) ?T {
            if (self.count > 0) {
                return self.states[self.current];
            }
            return null;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "StateSnapshot: create with timestamp" {
    const State = struct {
        value: u32,
        selected: bool,
    };

    const state = State{ .value = 42, .selected = true };
    const snapshot = StateSnapshot(State).now(state);

    try std.testing.expectEqual(@as(u32, 42), snapshot.state.value);
    try std.testing.expectEqual(true, snapshot.state.selected);
    try std.testing.expect(snapshot.timestamp > 0);
}

test "StateHistory: push and current" {
    const State = struct { value: u32 };
    var history = StateHistory(State, 10){};

    history.push(.{ .value = 1 });
    history.push(.{ .value = 2 });
    history.push(.{ .value = 3 });

    try std.testing.expectEqual(@as(usize, 3), history.count);
    try std.testing.expectEqual(@as(u32, 3), history.current_state().?.value);
}

test "StateHistory: undo" {
    const State = struct { value: u32 };
    var history = StateHistory(State, 10){};

    history.push(.{ .value = 1 });
    history.push(.{ .value = 2 });
    history.push(.{ .value = 3 });

    const undone = history.undo();
    try std.testing.expectEqual(@as(u32, 2), undone.?.value);
    try std.testing.expectEqual(@as(u32, 2), history.current_state().?.value);
}

test "StateHistory: redo" {
    const State = struct { value: u32 };
    var history = StateHistory(State, 10){};

    history.push(.{ .value = 1 });
    history.push(.{ .value = 2 });
    history.push(.{ .value = 3 });

    _ = history.undo();
    const redone = history.redo();
    try std.testing.expectEqual(@as(u32, 3), redone.?.value);
}

test "StateHistory: undo past beginning returns null" {
    const State = struct { value: u32 };
    var history = StateHistory(State, 10){};

    history.push(.{ .value = 1 });
    _ = history.undo();

    const result = history.undo();
    try std.testing.expectEqual(@as(?State, null), result);
}

test "StateHistory: redo past end returns null" {
    const State = struct { value: u32 };
    var history = StateHistory(State, 10){};

    history.push(.{ .value = 1 });
    history.push(.{ .value = 2 });

    const result = history.redo();
    try std.testing.expectEqual(@as(?State, null), result);
}

test "StateHistory: push after undo truncates forward" {
    const State = struct { value: u32 };
    var history = StateHistory(State, 10){};

    history.push(.{ .value = 1 });
    history.push(.{ .value = 2 });
    history.push(.{ .value = 3 });

    _ = history.undo(); // Back to 2
    history.push(.{ .value = 4 }); // Replaces 3

    try std.testing.expectEqual(@as(usize, 3), history.count);
    try std.testing.expectEqual(@as(u32, 4), history.current_state().?.value);

    const redo_result = history.redo();
    try std.testing.expectEqual(@as(?State, null), redo_result); // No forward history
}

test "StateHistory: max size circular buffer" {
    const State = struct { value: u32 };
    var history = StateHistory(State, 3){};

    history.push(.{ .value = 1 });
    history.push(.{ .value = 2 });
    history.push(.{ .value = 3 });
    history.push(.{ .value = 4 }); // Should evict 1

    try std.testing.expectEqual(@as(usize, 3), history.count);
    try std.testing.expectEqual(@as(u32, 4), history.current_state().?.value);

    _ = history.undo();
    try std.testing.expectEqual(@as(u32, 3), history.current_state().?.value);

    _ = history.undo();
    try std.testing.expectEqual(@as(u32, 2), history.current_state().?.value);

    const result = history.undo(); // Can't go further back
    try std.testing.expectEqual(@as(?State, null), result);
}
