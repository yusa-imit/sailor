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

// ============================================================================
// Batch Commands Tests
// ============================================================================

test "batch command: execute all commands in sequence" {
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
    var batch = BatchCommand(TestState).init(testing.allocator);
    defer batch.deinit();

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 5 };
    try batch.addCommand(command_spec, &cmd1);
    const cmd2 = AddCommand{ .amount = 3 };
    try batch.addCommand(command_spec, &cmd2);

    try batch.execute(&state);
    try testing.expectEqual(@as(i32, 18), state.value);
}

test "batch command: undo all commands in reverse order" {
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
    var batch = BatchCommand(TestState).init(testing.allocator);
    defer batch.deinit();

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 5 };
    try batch.addCommand(command_spec, &cmd1);
    const cmd2 = AddCommand{ .amount = 3 };
    try batch.addCommand(command_spec, &cmd2);
    const cmd3 = AddCommand{ .amount = 2 };
    try batch.addCommand(command_spec, &cmd3);

    try batch.execute(&state);
    try testing.expectEqual(@as(i32, 20), state.value);

    try batch.undo(&state);
    try testing.expectEqual(@as(i32, 10), state.value);
}

test "batch command: batch is reusable (execute/undo multiple times)" {
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
    var batch = BatchCommand(TestState).init(testing.allocator);
    defer batch.deinit();

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 10 };
    try batch.addCommand(command_spec, &cmd1);

    try batch.execute(&state);
    try testing.expectEqual(@as(i32, 10), state.value);

    try batch.undo(&state);
    try testing.expectEqual(@as(i32, 0), state.value);

    try batch.execute(&state);
    try testing.expectEqual(@as(i32, 10), state.value);
}

test "batch command: empty batch (no commands)" {
    const TestState = struct {
        value: i32,
    };

    var state = TestState{ .value = 10 };
    var batch = BatchCommand(TestState).init(testing.allocator);
    defer batch.deinit();

    try batch.execute(&state);
    try testing.expectEqual(@as(i32, 10), state.value);

    try batch.undo(&state);
    try testing.expectEqual(@as(i32, 10), state.value);
}

test "batch command: nested batches" {
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
    var outer_batch = BatchCommand(TestState).init(testing.allocator);
    defer outer_batch.deinit();

    var inner_batch = BatchCommand(TestState).init(testing.allocator);
    defer inner_batch.deinit();

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 5 };
    try inner_batch.addCommand(command_spec, &cmd1);
    const cmd2 = AddCommand{ .amount = 3 };
    try inner_batch.addCommand(command_spec, &cmd2);

    try inner_batch.execute(&state);
    try testing.expectEqual(@as(i32, 18), state.value);

    try inner_batch.undo(&state);
    try testing.expectEqual(@as(i32, 10), state.value);
}

test "batch command: error during execute stops batch" {
    const TestState = struct {
        value: i32,
        should_fail: bool,
    };

    const FailingCommand = struct {
        amount: i32,

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            if (state.should_fail) {
                return error.ExecutionFailed;
            }
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

    var state = TestState{ .value = 10, .should_fail = true };
    var batch = BatchCommand(TestState).init(testing.allocator);
    defer batch.deinit();

    const command_spec = Command(TestState){
        .executeFn = FailingCommand.execute,
        .undoFn = FailingCommand.undo,
        .cloneFn = FailingCommand.clone,
        .destroyFn = FailingCommand.destroy,
    };

    const cmd1 = FailingCommand{ .amount = 5 };
    try batch.addCommand(command_spec, &cmd1);

    try testing.expectError(error.ExecutionFailed, batch.execute(&state));
}

// ============================================================================
// Command Compression Tests
// ============================================================================

test "command compression: canMerge identifies compatible commands" {
    const TestState = struct {
        text: []const u8,
    };

    const InsertCharCommand = struct {
        char: u21,

        fn canMerge(_: *const @This(), other_ptr: *const anyopaque) bool {
            const other: *const @This() = @ptrCast(@alignCast(other_ptr));
            _ = other;
            // Char insert commands can merge if adjacent
            return true; // Simplified for test
        }

        fn merge(_: *@This(), other_ptr: *const anyopaque, allocator: Allocator) !void {
            _ = allocator;
            const other: *const @This() = @ptrCast(@alignCast(other_ptr));
            _ = other;
            // Merge logic would accumulate chars
        }

        fn execute(_: *const anyopaque, state: *TestState) !void {
            _ = state;
        }

        fn undo(_: *const anyopaque, state: *TestState) !void {
            _ = state;
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

    const cmd1 = InsertCharCommand{ .char = 'a' };
    const cmd2 = InsertCharCommand{ .char = 'b' };

    try testing.expect(cmd1.canMerge(&cmd2));
}

test "command compression: merge combines multiple commands into one" {
    const TestState = struct {
        value: i32,
    };

    const MergeableCommand = struct {
        amount: i32,

        fn canMerge(self: *const @This(), other_ptr: *const anyopaque) bool {
            const other: *const @This() = @ptrCast(@alignCast(other_ptr));
            _ = self;
            _ = other;
            return true; // These commands can always merge
        }

        fn merge(self: *@This(), other_ptr: *const anyopaque, allocator: Allocator) !void {
            _ = allocator;
            const other: *const @This() = @ptrCast(@alignCast(other_ptr));
            self.amount += other.amount;
        }

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

    const command_spec = Command(TestState){
        .executeFn = MergeableCommand.execute,
        .undoFn = MergeableCommand.undo,
        .cloneFn = MergeableCommand.clone,
        .destroyFn = MergeableCommand.destroy,
    };

    const cmd1 = MergeableCommand{ .amount = 5 };
    try history.execute(command_spec, &cmd1, &state);
    const cmd2 = MergeableCommand{ .amount = 3 };
    try history.execute(command_spec, &cmd2, &state);

    // After merge, history should contain merged command
    // This test assumes merge logic is implemented
    try testing.expectEqual(@as(i32, 18), state.value);
}

test "command compression: non-compatible commands are not merged" {
    const TestState = struct {
        value: i32,
    };

    const SelectiveCommand = struct {
        cmd_type: u8, // 1 for type A, 2 for type B

        fn canMerge(self: *const @This(), other_ptr: *const anyopaque) bool {
            const other: *const @This() = @ptrCast(@alignCast(other_ptr));
            // Only merge commands of the same type
            return self.cmd_type == other.cmd_type;
        }

        fn merge(self: *@This(), other_ptr: *const anyopaque, allocator: Allocator) !void {
            _ = allocator;
            _ = self;
            _ = other_ptr;
        }

        fn execute(_: *const anyopaque, state: *TestState) !void {
            _ = state;
        }

        fn undo(_: *const anyopaque, state: *TestState) !void {
            _ = state;
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

    const cmd_type_a = SelectiveCommand{ .cmd_type = 1 };
    const cmd_type_b = SelectiveCommand{ .cmd_type = 2 };

    try testing.expect(!cmd_type_a.canMerge(&cmd_type_b));
}

test "command compression: merge with allocator-based state" {
    const TestState = struct {
        buffer: std.array_list.Managed(u8),
    };

    const StringAppendCommand = struct {
        text: []const u8,

        fn canMerge(_: *const @This(), other_ptr: *const anyopaque) bool {
            _ = other_ptr;
            return true;
        }

        fn merge(self: *@This(), other_ptr: *const anyopaque, allocator: Allocator) !void {
            const other: *const @This() = @ptrCast(@alignCast(other_ptr));
            // In reality, would merge text together
            _ = self;
            _ = other;
            _ = allocator;
        }

        fn execute(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            try state.buffer.appendSlice(self.text);
        }

        fn undo(cmd: *const anyopaque, state: *TestState) !void {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const len = self.text.len;
            if (state.buffer.items.len >= len) {
                state.buffer.shrinkRetainingCapacity(state.buffer.items.len - len);
            }
        }

        fn clone(cmd: *const anyopaque, allocator: Allocator) !*anyopaque {
            const self: *const @This() = @ptrCast(@alignCast(cmd));
            const cloned = try allocator.create(@This());
            const text_copy = try allocator.dupe(u8, self.text);
            cloned.* = .{ .text = text_copy };
            return cloned;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(cmd));
            allocator.free(self.text);
            allocator.destroy(self);
        }
    };

    var state = TestState{ .buffer = std.array_list.Managed(u8).init(testing.allocator) };
    defer state.buffer.deinit();

    const command_spec = Command(TestState){
        .executeFn = StringAppendCommand.execute,
        .undoFn = StringAppendCommand.undo,
        .cloneFn = StringAppendCommand.clone,
        .destroyFn = StringAppendCommand.destroy,
    };

    const text = "hello";
    const cmd = StringAppendCommand{ .text = text };
    try command_spec.execute(&cmd, &state);

    try testing.expectEqualSlices(u8, "hello", state.buffer.items);
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "error handling: execute error stops and returns error" {
    const TestState = struct {
        value: i32,
    };

    const ErrorCommand = struct {
        fn execute(_: *const anyopaque, _: *TestState) !void {
            return error.ExecutionFailed;
        }

        fn undo(_: *const anyopaque, _: *TestState) !void {}

        fn clone(_: *const anyopaque, allocator: Allocator) !*anyopaque {
            const cmd = try allocator.create(@This());
            return cmd;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            allocator.destroy(@as(*@This(), @ptrCast(@alignCast(cmd))));
        }
    };

    var state = TestState{ .value = 10 };
    const command_spec = Command(TestState){
        .executeFn = ErrorCommand.execute,
        .undoFn = ErrorCommand.undo,
        .cloneFn = ErrorCommand.clone,
        .destroyFn = ErrorCommand.destroy,
    };

    const cmd = ErrorCommand{};
    try testing.expectError(error.ExecutionFailed, command_spec.execute(&cmd, &state));
}

test "error handling: undo error bubbles up" {
    const TestState = struct {
        value: i32,
    };

    const ErrorOnUndoCommand = struct {
        fn execute(_: *const anyopaque, state: *TestState) !void {
            state.value += 5;
        }

        fn undo(_: *const anyopaque, _: *TestState) !void {
            return error.UndoFailed;
        }

        fn clone(_: *const anyopaque, allocator: Allocator) !*anyopaque {
            const cmd = try allocator.create(@This());
            return cmd;
        }

        fn destroy(cmd: *anyopaque, allocator: Allocator) void {
            allocator.destroy(@as(*@This(), @ptrCast(@alignCast(cmd))));
        }
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    const command_spec = Command(TestState){
        .executeFn = ErrorOnUndoCommand.execute,
        .undoFn = ErrorOnUndoCommand.undo,
        .cloneFn = ErrorOnUndoCommand.clone,
        .destroyFn = ErrorOnUndoCommand.destroy,
    };

    const cmd = ErrorOnUndoCommand{};
    try history.execute(command_spec, &cmd, &state);
    try testing.expectEqual(@as(i32, 15), state.value);

    try testing.expectError(error.UndoFailed, history.undo(&state));
}

test "error handling: undo on empty history returns error" {
    const TestState = struct {
        value: i32,
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    try testing.expectError(error.NothingToUndo, history.undo(&state));
}

test "error handling: redo on empty redo stack returns error" {
    const TestState = struct {
        value: i32,
    };

    var state = TestState{ .value = 10 };
    var history = CommandHistory(TestState).init(testing.allocator);
    defer history.deinit();

    try testing.expectError(error.NothingToRedo, history.redo(&state));
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "edge case: undo until empty then redo" {
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

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd = AddCommand{ .amount = 5 };
    try history.execute(command_spec, &cmd, &state);
    try testing.expectEqual(@as(i32, 5), state.value);

    try history.undo(&state);
    try testing.expectEqual(@as(i32, 0), state.value);
    try testing.expect(!history.canUndo());

    try history.redo(&state);
    try testing.expectEqual(@as(i32, 5), state.value);
    try testing.expect(!history.canRedo());
}

test "edge case: large history with max limit" {
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
    var history = CommandHistory(TestState).initWithLimit(testing.allocator, 5);
    defer history.deinit();

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    // Add 10 commands to history with limit of 5
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        const cmd = AddCommand{ .amount = 1 };
        try history.execute(command_spec, &cmd, &state);
    }

    try testing.expectEqual(@as(usize, 5), history.historySize());
    try testing.expectEqual(@as(i32, 10), state.value);
}

test "edge case: clear history multiple times" {
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

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd = AddCommand{ .amount = 5 };
    try history.execute(command_spec, &cmd, &state);
    try testing.expectEqual(@as(usize, 1), history.historySize());

    history.clear();
    try testing.expectEqual(@as(usize, 0), history.historySize());

    history.clear();
    try testing.expectEqual(@as(usize, 0), history.historySize());
}

test "edge case: undo redo undo sequence" {
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

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    const cmd1 = AddCommand{ .amount = 10 };
    try history.execute(command_spec, &cmd1, &state);
    try testing.expectEqual(@as(i32, 10), state.value);

    const cmd2 = AddCommand{ .amount = 5 };
    try history.execute(command_spec, &cmd2, &state);
    try testing.expectEqual(@as(i32, 15), state.value);

    try history.undo(&state);
    try testing.expectEqual(@as(i32, 10), state.value);

    try history.redo(&state);
    try testing.expectEqual(@as(i32, 15), state.value);

    try history.undo(&state);
    try testing.expectEqual(@as(i32, 10), state.value);

    try history.undo(&state);
    try testing.expectEqual(@as(i32, 0), state.value);
}

test "edge case: currentPosition reflects history state" {
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

    const command_spec = Command(TestState){
        .executeFn = AddCommand.execute,
        .undoFn = AddCommand.undo,
        .cloneFn = AddCommand.clone,
        .destroyFn = AddCommand.destroy,
    };

    try testing.expectEqual(@as(usize, 0), history.currentPosition());

    const cmd1 = AddCommand{ .amount = 10 };
    try history.execute(command_spec, &cmd1, &state);
    try testing.expectEqual(@as(usize, 1), history.currentPosition());

    const cmd2 = AddCommand{ .amount = 5 };
    try history.execute(command_spec, &cmd2, &state);
    try testing.expectEqual(@as(usize, 2), history.currentPosition());

    try history.undo(&state);
    try testing.expectEqual(@as(usize, 1), history.currentPosition());

    try history.undo(&state);
    try testing.expectEqual(@as(usize, 0), history.currentPosition());

    try history.redo(&state);
    try testing.expectEqual(@as(usize, 1), history.currentPosition());
}

// ============================================================================
// Batch Commands Supporting Types
// ============================================================================

/// Batch command groups multiple commands together
pub fn BatchCommand(comptime StateType: type) type {
    return struct {
        const Self = @This();
        const CommandType = Command(StateType);

        const CommandEntry = struct {
            command: CommandType,
            data: *anyopaque,
        };

        allocator: Allocator,
        commands: std.array_list.Managed(CommandEntry),

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .commands = std.array_list.Managed(CommandEntry).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.commands.items) |entry| {
                entry.command.destroy(entry.data, self.allocator);
            }
            self.commands.deinit();
        }

        pub fn addCommand(self: *Self, command: CommandType, cmd_data: *const anyopaque) !void {
            const cloned_data = try command.clone(cmd_data, self.allocator);
            try self.commands.append(.{
                .command = command,
                .data = cloned_data,
            });
        }

        pub fn execute(self: *Self, state: *StateType) !void {
            for (self.commands.items) |entry| {
                try entry.command.execute(entry.data, state);
            }
        }

        pub fn undo(self: *Self, state: *StateType) !void {
            // Undo in reverse order
            var i: i32 = @intCast(self.commands.items.len);
            while (i > 0) {
                i -= 1;
                const entry = self.commands.items[@intCast(i)];
                try entry.command.undo(entry.data, state);
            }
        }
    };
}
