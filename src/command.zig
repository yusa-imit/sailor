// command.zig — Command pattern for undo/redo support
//
// Provides a generic command execution and history system for implementing
// undo/redo functionality in stateful widgets.
//
// Example usage:
//   // Define your state type
//   const TextState = struct { text: []const u8, allocator: Allocator };
//
//   // Define a command that modifies the state
//   const InsertTextCommand = struct {
//       position: usize,
//       text: []const u8,
//       old_text: ?[]const u8 = null,
//
//       pub fn toCommand() Command(TextState) {
//           return .{
//               .executeFn = execute,
//               .undoFn = undo,
//               .cloneFn = clone,
//               .destroyFn = destroy,
//           };
//       }
//
//       fn execute(cmd_ptr: *const anyopaque, state: *TextState) !void {
//           const cmd: *const InsertTextCommand = @ptrCast(@alignCast(cmd_ptr));
//           // Insert text at position...
//       }
//
//       fn undo(cmd_ptr: *const anyopaque, state: *TextState) !void {
//           const cmd: *const InsertTextCommand = @ptrCast(@alignCast(cmd_ptr));
//           // Restore old_text...
//       }
//
//       // ... clone and destroy implementations
//   };
//
//   // Use the command history
//   var history = CommandHistory(TextState).init(allocator);
//   defer history.deinit();
//
//   const cmd = InsertTextCommand{ .position = 0, .text = "Hello" };
//   try history.execute(&cmd, &state);
//   try history.undo(&state);    // Undo the insert
//   try history.redo(&state);    // Redo the insert

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Command interface that all commands must implement
pub fn Command(comptime StateType: type) type {
    return struct {
        const Self = @This();

        /// Pointer to the execute function
        executeFn: *const fn (cmd: *const anyopaque, state: *StateType) anyerror!void,

        /// Pointer to the undo function
        undoFn: *const fn (cmd: *const anyopaque, state: *StateType) anyerror!void,

        /// Pointer to the redo function (optional, defaults to execute)
        redoFn: ?*const fn (cmd: *const anyopaque, state: *StateType) anyerror!void = null,

        /// Pointer to the clone function for history storage
        cloneFn: *const fn (cmd: *const anyopaque, allocator: Allocator) anyerror!*anyopaque,

        /// Pointer to the destroy function for cleanup
        destroyFn: *const fn (cmd: *anyopaque, allocator: Allocator) void,

        /// Execute the command
        pub fn execute(self: *const Self, cmd: *const anyopaque, state: *StateType) !void {
            try self.executeFn(cmd, state);
        }

        /// Undo the command
        pub fn undo(self: *const Self, cmd: *const anyopaque, state: *StateType) !void {
            try self.undoFn(cmd, state);
        }

        /// Redo the command (uses execute if redoFn is null)
        pub fn redo(self: *const Self, cmd: *const anyopaque, state: *StateType) !void {
            if (self.redoFn) |redoFn| {
                try redoFn(cmd, state);
            } else {
                try self.executeFn(cmd, state);
            }
        }

        /// Clone the command for history storage
        pub fn clone(self: *const Self, cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            return try self.cloneFn(cmd, allocator);
        }

        /// Destroy the command and free resources
        pub fn destroy(self: *const Self, cmd: *anyopaque, allocator: Allocator) void {
            self.destroyFn(cmd, allocator);
        }
    };
}

/// Command history manager with undo/redo stack
pub fn CommandHistory(comptime StateType: type) type {
    return struct {
        const Self = @This();
        const CommandType = Command(StateType);

        /// Entry in the command history
        const Entry = struct {
            command: CommandType,
            data: *anyopaque,
        };

        allocator: Allocator,
        history: std.array_list.Managed(Entry),
        current: usize, // Index of the next command to execute (after undos)
        max_history: ?usize, // Optional history size limit

        /// Initialize a new command history
        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .history = std.array_list.Managed(Entry).init(allocator),
                .current = 0,
                .max_history = null,
            };
        }

        /// Initialize with a maximum history size
        pub fn initWithLimit(allocator: Allocator, max_history: usize) Self {
            var self = init(allocator);
            self.max_history = max_history;
            return self;
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            for (self.history.items) |entry| {
                entry.command.destroy(entry.data, self.allocator);
            }
            self.history.deinit();
        }

        /// Execute a command and add it to history
        pub fn execute(self: *Self, command: CommandType, cmd_data: *const anyopaque, state: *StateType) !void {
            // Execute the command
            try command.execute(cmd_data, state);

            // Clear any commands after the current position (redo history)
            while (self.current < self.history.items.len) {
                const entry = self.history.pop() orelse break;
                entry.command.destroy(entry.data, self.allocator);
            }

            // Clone the command for history storage
            const cloned_data = try command.clone(cmd_data, self.allocator);

            // Add to history
            try self.history.append(.{
                .command = command,
                .data = cloned_data,
            });
            self.current = self.history.items.len;

            // Enforce max history limit if set
            if (self.max_history) |max| {
                while (self.history.items.len > max) {
                    const entry = self.history.orderedRemove(0);
                    entry.command.destroy(entry.data, self.allocator);
                    self.current -|= 1;
                }
            }
        }

        /// Undo the last command
        pub fn undo(self: *Self, state: *StateType) !void {
            if (self.current == 0) return error.NothingToUndo;

            self.current -= 1;
            const entry = self.history.items[self.current];
            try entry.command.undo(entry.data, state);
        }

        /// Redo the next command
        pub fn redo(self: *Self, state: *StateType) !void {
            if (self.current >= self.history.items.len) return error.NothingToRedo;

            const entry = self.history.items[self.current];
            try entry.command.redo(entry.data, state);
            self.current += 1;
        }

        /// Check if undo is available
        pub fn canUndo(self: *const Self) bool {
            return self.current > 0;
        }

        /// Check if redo is available
        pub fn canRedo(self: *const Self) bool {
            return self.current < self.history.items.len;
        }

        /// Get the number of commands in history
        pub fn historySize(self: *const Self) usize {
            return self.history.items.len;
        }

        /// Get the current position in history
        pub fn currentPosition(self: *const Self) usize {
            return self.current;
        }

        /// Clear all history
        pub fn clear(self: *Self) void {
            for (self.history.items) |entry| {
                entry.command.destroy(entry.data, self.allocator);
            }
            self.history.clearRetainingCapacity();
            self.current = 0;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "command: basic execute" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(_: *const anyopaque, state: *TestState) !void {
            state.value += 5;
        }

        fn undo(_: *const anyopaque, state: *TestState) !void {
            state.value -= 5;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    const cmd = AddCommand{ .amount = 5 };
    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    try command.execute(&cmd, &state);
    try testing.expectEqual(15, state.value);
}

test "command: basic undo" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(_: *const anyopaque, state: *TestState) !void {
            state.value += 5;
        }

        fn undo(_: *const anyopaque, state: *TestState) !void {
            state.value -= 5;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    const cmd = AddCommand{ .amount = 5 };
    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    try command.execute(&cmd, &state);
    try testing.expectEqual(15, state.value);

    try command.undo(&cmd, &state);
    try testing.expectEqual(10, state.value);
}

test "command: history execute and undo" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 5 };
    try history.execute(command, &cmd1, &state);
    try testing.expectEqual(15, state.value);

    const cmd2 = AddCommand{ .amount = 3 };
    try history.execute(command, &cmd2, &state);
    try testing.expectEqual(18, state.value);

    try history.undo(&state);
    try testing.expectEqual(15, state.value);

    try history.undo(&state);
    try testing.expectEqual(10, state.value);
}

test "command: history redo" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 5 };
    try history.execute(command, &cmd1, &state);
    try testing.expectEqual(15, state.value);

    try history.undo(&state);
    try testing.expectEqual(10, state.value);

    try history.redo(&state);
    try testing.expectEqual(15, state.value);
}

test "command: clear redo history on new command" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 5 };
    try history.execute(command, &cmd1, &state);
    const cmd2 = AddCommand{ .amount = 3 };
    try history.execute(command, &cmd2, &state);
    try testing.expectEqual(18, state.value);

    try history.undo(&state);
    try testing.expectEqual(15, state.value);

    // Execute new command should clear redo history
    const cmd3 = AddCommand{ .amount = 7 };
    try history.execute(command, &cmd3, &state);
    try testing.expectEqual(22, state.value);

    // Redo should fail (history cleared)
    try testing.expectError(error.NothingToRedo, history.redo(&state));
}

test "command: canUndo and canRedo" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    try testing.expectEqual(false, history.canUndo());
    try testing.expectEqual(false, history.canRedo());

    const cmd1 = AddCommand{ .amount = 5 };
    try history.execute(command, &cmd1, &state);
    try testing.expectEqual(true, history.canUndo());
    try testing.expectEqual(false, history.canRedo());

    try history.undo(&state);
    try testing.expectEqual(false, history.canUndo());
    try testing.expectEqual(true, history.canRedo());
}

test "command: max history limit" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).initWithLimit(testing.allocator, 2);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 1 };
    try history.execute(command, &cmd1, &state);
    const cmd2 = AddCommand{ .amount = 2 };
    try history.execute(command, &cmd2, &state);
    const cmd3 = AddCommand{ .amount = 3 };
    try history.execute(command, &cmd3, &state);

    // History should only keep last 2 commands
    try testing.expectEqual(2, history.historySize());
    try testing.expectEqual(16, state.value); // 10 + 2 + 3 (first command dropped)

    try history.undo(&state);
    try testing.expectEqual(13, state.value); // Undo cmd3

    try history.undo(&state);
    try testing.expectEqual(11, state.value); // Undo cmd2

    // Can't undo further (cmd1 was dropped)
    try testing.expectError(error.NothingToUndo, history.undo(&state));
}

test "command: clear history" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 5 };
    try history.execute(command, &cmd1, &state);
    try testing.expectEqual(1, history.historySize());

    history.clear();
    try testing.expectEqual(0, history.historySize());
    try testing.expectEqual(false, history.canUndo());
    try testing.expectEqual(false, history.canRedo());
}

test "command: multiple undos and redos" {
    const TestState = struct {
        value: i32,
    };

    const AddCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 0 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    // Execute 3 commands
    const cmd1 = AddCommand{ .amount = 10 };
    try history.execute(command, &cmd1, &state);
    const cmd2 = AddCommand{ .amount = 20 };
    try history.execute(command, &cmd2, &state);
    const cmd3 = AddCommand{ .amount = 30 };
    try history.execute(command, &cmd3, &state);
    try testing.expectEqual(60, state.value);

    // Undo all
    try history.undo(&state);
    try testing.expectEqual(30, state.value);
    try history.undo(&state);
    try testing.expectEqual(10, state.value);
    try history.undo(&state);
    try testing.expectEqual(0, state.value);

    // Redo all
    try history.redo(&state);
    try testing.expectEqual(10, state.value);
    try history.redo(&state);
    try testing.expectEqual(30, state.value);
    try history.redo(&state);
    try testing.expectEqual(60, state.value);
}

test "command: custom redo function" {
    const TestState = struct {
        value: i32,
        redo_count: i32,
    };

    const CustomCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value -= self.amount;
        }

        fn redo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            state.value += self.amount;
            state.redo_count += 1;
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            cloned.* = self.*;
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.destroy(self);
        }
    };

    var state = TestState{ .value = 10, .redo_count = 0 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command = Command(TestState){
        .executeFn = CustomCommand.execute,
        .undoFn = CustomCommand.undo,
        .redoFn = CustomCommand.redo,
        .cloneFn = CustomCommand.clone,
        .destroyFn = CustomCommand.destroy,
    };

    const cmd1 = CustomCommand{ .amount = 5 };
    try history.execute(command, &cmd1, &state);
    try testing.expectEqual(15, state.value);
    try testing.expectEqual(0, state.redo_count);

    try history.undo(&state);
    try testing.expectEqual(10, state.value);

    try history.redo(&state);
    try testing.expectEqual(15, state.value);
    try testing.expectEqual(1, state.redo_count); // Custom redo function was called
}
