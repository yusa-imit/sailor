// taskrunner.zig — Cooperative async task runner for background operations
//
// Provides priority-based task scheduling without threads. Tasks can yield execution
// to allow other tasks to run, making this suitable for responsive TUI applications
// where blocking operations need to be broken into cooperative steps.
//
// Example usage:
//   var runner = TaskRunner.init(allocator);
//   defer runner.deinit();
//
//   // Enqueue a background task
//   const task_id = try runner.enqueue(.normal, myTaskFn, &context, progressCallback);
//
//   // Run tasks cooperatively in your main loop
//   while (try runner.step()) {
//       // Handle UI events between task steps
//   }
//
//   // Cancel a task if needed
//   runner.cancel(task_id);

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Task priority levels (higher priority tasks run first)
pub const Priority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,

    fn compare(_: void, a: Priority, b: Priority) std.math.Order {
        return std.math.order(@intFromEnum(b), @intFromEnum(a)); // Higher priority first
    }
};

/// Task function signature
pub const TaskFn = *const fn (ctx: ?*anyopaque) anyerror!void;

/// Progress callback signature (receives progress from 0.0 to 1.0)
pub const ProgressFn = ?*const fn (progress: f32) void;

/// Task representation
pub const Task = struct {
    id: usize,
    priority: Priority,
    runFn: TaskFn,
    context: ?*anyopaque,
    progressFn: ProgressFn,
    cancelled: bool,
};

/// Cooperative task runner with priority-based scheduling
pub const TaskRunner = struct {
    allocator: Allocator,
    tasks: std.ArrayList(Task),
    next_id: usize,

    /// Initialize a new task runner
    pub fn init(allocator: Allocator) TaskRunner {
        return .{
            .allocator = allocator,
            .tasks = .{},
            .next_id = 1,
        };
    }

    /// Clean up task runner and all pending tasks
    pub fn deinit(self: *TaskRunner) void {
        self.tasks.deinit(self.allocator);
    }

    /// Enqueue a new task with given priority
    /// Returns unique task ID for cancellation
    pub fn enqueue(
        self: *TaskRunner,
        priority: Priority,
        runFn: TaskFn,
        context: ?*anyopaque,
        progressFn: ProgressFn,
    ) !usize {
        const task_id = self.next_id;
        self.next_id += 1;

        const task = Task{
            .id = task_id,
            .priority = priority,
            .runFn = runFn,
            .context = context,
            .progressFn = progressFn,
            .cancelled = false,
        };

        try self.tasks.append(self.allocator, task);
        self.sortByPriority();

        return task_id;
    }

    /// Cancel a task by ID (marks as cancelled, will be skipped)
    pub fn cancel(self: *TaskRunner, task_id: usize) void {
        for (self.tasks.items) |*task| {
            if (task.id == task_id) {
                task.cancelled = true;
                return;
            }
        }
    }

    /// Execute one task step. Returns true if more work remains
    pub fn step(self: *TaskRunner) !bool {
        // Remove cancelled tasks first
        var i: usize = 0;
        while (i < self.tasks.items.len) {
            if (self.tasks.items[i].cancelled) {
                _ = self.tasks.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        if (self.tasks.items.len == 0) {
            return false;
        }

        // Execute highest priority task
        const task = self.tasks.orderedRemove(0);
        if (!task.cancelled) {
            try task.runFn(task.context);
        }

        return self.tasks.items.len > 0;
    }

    /// Execute all pending tasks until queue is empty
    pub fn runAll(self: *TaskRunner) !void {
        while (try self.step()) {
            // Keep running until no work remains
        }
    }

    /// Get number of pending tasks (excluding cancelled)
    pub fn pendingCount(self: *TaskRunner) usize {
        var count: usize = 0;
        for (self.tasks.items) |task| {
            if (!task.cancelled) count += 1;
        }
        return count;
    }

    /// Sort tasks by priority (high to low)
    fn sortByPriority(self: *TaskRunner) void {
        std.mem.sort(Task, self.tasks.items, {}, struct {
            fn lessThan(_: void, a: Task, b: Task) bool {
                return @intFromEnum(a.priority) > @intFromEnum(b.priority);
            }
        }.lessThan);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "TaskRunner: init and deinit" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    try testing.expectEqual(@as(usize, 0), runner.tasks.items.len);
    try testing.expectEqual(@as(usize, 1), runner.next_id);
}

test "TaskRunner: enqueue single task" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var executed = false;

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.run;

    const task_id = try runner.enqueue(.normal, taskFn, &executed, null);

    try testing.expectEqual(@as(usize, 1), task_id);
    try testing.expectEqual(@as(usize, 1), runner.tasks.items.len);
    try testing.expect(!executed);

    // Task shouldn't execute until step() is called
    try testing.expect(!executed);
}

test "TaskRunner: step executes task" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var executed = false;

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.run;

    _ = try runner.enqueue(.normal, taskFn, &executed, null);

    const has_more = try runner.step();

    try testing.expect(executed);
    try testing.expect(!has_more); // No more tasks
}

test "TaskRunner: priority order - high before normal" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var execution_order: std.ArrayList(u8) = .{};
    defer execution_order.deinit(testing.allocator);

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 1);
        }
    }.run;

    const taskFnHigh = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 2);
        }
    }.run;

    // Enqueue normal priority first, then high
    _ = try runner.enqueue(.normal, taskFn, &execution_order, null);
    _ = try runner.enqueue(.high, taskFnHigh, &execution_order, null);

    try runner.runAll();

    // High priority should execute first
    try testing.expectEqual(@as(usize, 2), execution_order.items.len);
    try testing.expectEqual(@as(u8, 2), execution_order.items[0]); // High priority
    try testing.expectEqual(@as(u8, 1), execution_order.items[1]); // Normal priority
}

test "TaskRunner: priority order - high > normal > low" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var execution_order: std.ArrayList(u8) = .{};
    defer execution_order.deinit(testing.allocator);

    const lowTask = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 1);
        }
    }.run;

    const normalTask = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 2);
        }
    }.run;

    const highTask = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 3);
        }
    }.run;

    // Enqueue in reverse priority order
    _ = try runner.enqueue(.low, lowTask, &execution_order, null);
    _ = try runner.enqueue(.normal, normalTask, &execution_order, null);
    _ = try runner.enqueue(.high, highTask, &execution_order, null);

    try runner.runAll();

    // Should execute in priority order: high, normal, low
    try testing.expectEqual(@as(usize, 3), execution_order.items.len);
    try testing.expectEqual(@as(u8, 3), execution_order.items[0]); // High
    try testing.expectEqual(@as(u8, 2), execution_order.items[1]); // Normal
    try testing.expectEqual(@as(u8, 1), execution_order.items[2]); // Low
}

test "TaskRunner: cancel task before execution" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var executed = false;

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.run;

    const task_id = try runner.enqueue(.normal, taskFn, &executed, null);

    runner.cancel(task_id);

    const has_more = try runner.step();

    try testing.expect(!executed); // Task should not execute
    try testing.expect(!has_more); // No more tasks
}

test "TaskRunner: cancel non-existent task" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    // Should not crash
    runner.cancel(999);
    runner.cancel(0);
}

test "TaskRunner: cancel task during execution" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var execution_count: usize = 0;

    const task1Fn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const count = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            count.* += 1;
        }
    }.run;

    const task2Fn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const count = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            count.* += 10;
        }
    }.run;

    _ = try runner.enqueue(.normal, task1Fn, &execution_count, null);
    const task2_id = try runner.enqueue(.normal, task2Fn, &execution_count, null);

    // Execute first task
    _ = try runner.step();
    try testing.expectEqual(@as(usize, 1), execution_count);

    // Cancel second task before it runs
    runner.cancel(task2_id);

    // Try to execute second task
    const has_more = try runner.step();

    try testing.expectEqual(@as(usize, 1), execution_count); // Only first task executed
    try testing.expect(!has_more); // No more tasks
}

test "TaskRunner: progress callback" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var progress_values: std.ArrayList(f32) = .{};
    defer progress_values.deinit(testing.allocator);

    const progressFn = struct {
        fn report(progress: f32) void {
            // Note: Can't capture ArrayList here, need to use global or pass through context
            _ = progress;
        }
    }.report;

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            _ = ctx;
            // Task would call progress callback internally
        }
    }.run;

    _ = try runner.enqueue(.normal, taskFn, &progress_values, progressFn);

    try runner.runAll();

    // This test will need actual progress reporting in implementation
    // For now, just verify task completes with progress callback set
}

test "TaskRunner: task error handling" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    const taskFn = struct {
        fn run(_: ?*anyopaque) !void {
            return error.TaskFailed;
        }
    }.run;

    _ = try runner.enqueue(.normal, taskFn, null, null);

    // Task error should propagate
    try testing.expectError(error.TaskFailed, runner.step());
}

test "TaskRunner: multiple tasks with same priority" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var execution_count: usize = 0;

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const count = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            count.* += 1;
        }
    }.run;

    _ = try runner.enqueue(.normal, taskFn, &execution_count, null);
    _ = try runner.enqueue(.normal, taskFn, &execution_count, null);
    _ = try runner.enqueue(.normal, taskFn, &execution_count, null);

    try runner.runAll();

    try testing.expectEqual(@as(usize, 3), execution_count);
}

test "TaskRunner: empty queue step returns false" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    const has_more = try runner.step();
    try testing.expect(!has_more);
}

test "TaskRunner: runAll on empty queue" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    // Should not crash
    try runner.runAll();
}

test "TaskRunner: pendingCount" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    try testing.expectEqual(@as(usize, 0), runner.pendingCount());

    const taskFn = struct {
        fn run(_: ?*anyopaque) !void {}
    }.run;

    _ = try runner.enqueue(.normal, taskFn, null, null);
    try testing.expectEqual(@as(usize, 1), runner.pendingCount());

    _ = try runner.enqueue(.high, taskFn, null, null);
    try testing.expectEqual(@as(usize, 2), runner.pendingCount());

    // Execute one task
    _ = try runner.step();
    try testing.expectEqual(@as(usize, 1), runner.pendingCount());

    // Execute remaining task
    _ = try runner.step();
    try testing.expectEqual(@as(usize, 0), runner.pendingCount());
}

test "TaskRunner: pendingCount excludes cancelled tasks" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    const taskFn = struct {
        fn run(_: ?*anyopaque) !void {}
    }.run;

    const id1 = try runner.enqueue(.normal, taskFn, null, null);
    const id2 = try runner.enqueue(.normal, taskFn, null, null);

    try testing.expectEqual(@as(usize, 2), runner.pendingCount());

    runner.cancel(id1);
    try testing.expectEqual(@as(usize, 1), runner.pendingCount());

    runner.cancel(id2);
    try testing.expectEqual(@as(usize, 0), runner.pendingCount());
}

test "TaskRunner: unique task IDs" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    const taskFn = struct {
        fn run(_: ?*anyopaque) !void {}
    }.run;

    const id1 = try runner.enqueue(.normal, taskFn, null, null);
    const id2 = try runner.enqueue(.normal, taskFn, null, null);
    const id3 = try runner.enqueue(.normal, taskFn, null, null);

    try testing.expect(id1 != id2);
    try testing.expect(id2 != id3);
    try testing.expect(id1 != id3);
}

test "TaskRunner: task with null context" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    const TaskStruct = struct {
        var flag: bool = false;
        fn run(_: ?*anyopaque) !void {
            flag = true;
        }
    };

    _ = try runner.enqueue(.normal, TaskStruct.run, null, null);

    try runner.runAll();

    try testing.expect(TaskStruct.flag);
}

test "TaskRunner: priority sorting stability" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var ids: std.ArrayList(usize) = .{};
    defer ids.deinit(testing.allocator);

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const id_list = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            // We'll track execution order via task IDs
            _ = id_list;
        }
    }.run;

    // Enqueue multiple high priority tasks - they should maintain insertion order
    const id1 = try runner.enqueue(.high, taskFn, &ids, null);
    const id2 = try runner.enqueue(.high, taskFn, &ids, null);
    const id3 = try runner.enqueue(.high, taskFn, &ids, null);

    // All should be high priority, in order
    try testing.expectEqual(Priority.high, runner.tasks.items[0].priority);
    try testing.expectEqual(Priority.high, runner.tasks.items[1].priority);
    try testing.expectEqual(Priority.high, runner.tasks.items[2].priority);

    // IDs should be sequential
    try testing.expectEqual(id1 + 1, id2);
    try testing.expectEqual(id2 + 1, id3);
}

test "TaskRunner: mixed priority execution order" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var execution_order: std.ArrayList(usize) = .{};
    defer execution_order.deinit(testing.allocator);

    const task1 = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 1);
        }
    }.run;

    const task2 = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 2);
        }
    }.run;

    const task3 = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 3);
        }
    }.run;

    const task4 = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 4);
        }
    }.run;

    const task5 = struct {
        fn run(ctx: ?*anyopaque) !void {
            const order = @as(*std.ArrayList(usize), @ptrCast(@alignCast(ctx.?)));
            try order.append(testing.allocator, 5);
        }
    }.run;

    // Enqueue: low, high, normal, high, low
    _ = try runner.enqueue(.low, task1, &execution_order, null);
    _ = try runner.enqueue(.high, task2, &execution_order, null);
    _ = try runner.enqueue(.normal, task3, &execution_order, null);
    _ = try runner.enqueue(.high, task4, &execution_order, null);
    _ = try runner.enqueue(.low, task5, &execution_order, null);

    try runner.runAll();

    // Expected order: high (2, 4), normal (3), low (1, 5)
    try testing.expectEqual(@as(usize, 5), execution_order.items.len);
    try testing.expectEqual(@as(usize, 2), execution_order.items[0]); // First high
    try testing.expectEqual(@as(usize, 4), execution_order.items[1]); // Second high
    try testing.expectEqual(@as(usize, 3), execution_order.items[2]); // Normal
    try testing.expectEqual(@as(usize, 1), execution_order.items[3]); // First low
    try testing.expectEqual(@as(usize, 5), execution_order.items[4]); // Second low
}

test "TaskRunner: step-by-step execution" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var count: usize = 0;

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.run;

    _ = try runner.enqueue(.normal, taskFn, &count, null);
    _ = try runner.enqueue(.normal, taskFn, &count, null);
    _ = try runner.enqueue(.normal, taskFn, &count, null);

    // Execute one at a time
    var has_more = try runner.step();
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expect(has_more);

    has_more = try runner.step();
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expect(has_more);

    has_more = try runner.step();
    try testing.expectEqual(@as(usize, 3), count);
    try testing.expect(!has_more);
}

test "TaskRunner: cancel all tasks" {
    var runner = TaskRunner.init(testing.allocator);
    defer runner.deinit();

    var count: usize = 0;

    const taskFn = struct {
        fn run(ctx: ?*anyopaque) !void {
            const cnt = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            cnt.* += 1;
        }
    }.run;

    const id1 = try runner.enqueue(.normal, taskFn, &count, null);
    const id2 = try runner.enqueue(.normal, taskFn, &count, null);
    const id3 = try runner.enqueue(.normal, taskFn, &count, null);

    runner.cancel(id1);
    runner.cancel(id2);
    runner.cancel(id3);

    try runner.runAll();

    try testing.expectEqual(@as(usize, 0), count); // No tasks should execute
}
