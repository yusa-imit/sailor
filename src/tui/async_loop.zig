const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const term_mod = @import("../term.zig");
const Event = @import("tui.zig").Event;
const KeyEvent = @import("tui.zig").KeyEvent;
const KeyCode = @import("tui.zig").KeyCode;
const Modifiers = @import("tui.zig").Modifiers;

/// Task handle for background operations
pub const TaskHandle = struct {
    id: u32,
    cancelled: *bool,
};

/// Task completion callback signature
pub const TaskCallback = *const fn (result: anyerror!void, user_data: ?*anyopaque) void;

/// Background task state
pub const TaskState = enum {
    pending,
    running,
    completed,
    cancelled,
    failed,
};

/// Task descriptor
const Task = struct {
    id: u32,
    state: TaskState,
    callback: TaskCallback,
    user_data: ?*anyopaque,
    thread: ?std.Thread,
    cancelled: *bool, // Heap-allocated for stable addressing across array reallocations
    result: anyerror!void,
};

/// Poll mode for event loop
pub const PollMode = enum {
    blocking, // Wait indefinitely for next event
    timeout, // Wait up to timeout_ms for next event
    nonblocking, // Return immediately if no event available
};

/// Async event loop for non-blocking I/O operations
pub const AsyncEventLoop = struct {
    allocator: Allocator,
    tasks: std.ArrayListUnmanaged(Task),
    next_task_id: u32,
    event_queue: std.ArrayListUnmanaged(Event),
    quit_requested: bool,
    mutex: std.Thread.Mutex,

    /// Initialize async event loop
    pub fn init(allocator: Allocator) AsyncEventLoop {
        return .{
            .allocator = allocator,
            .tasks = .{},
            .next_task_id = 1,
            .event_queue = .{},
            .quit_requested = false,
            .mutex = .{},
        };
    }

    /// Clean up event loop and cancel all pending tasks
    pub fn deinit(self: *AsyncEventLoop) void {
        // Lock to safely cancel all tasks and prevent concurrent modifications
        self.mutex.lock();

        // Cancel all tasks
        for (self.tasks.items) |*task| {
            if (task.state == .running or task.state == .pending) {
                task.cancelled.* = true;
                task.state = .cancelled;
            }
        }

        // Unlock before joining threads to prevent deadlock
        // (threads may need to acquire lock during shutdown)
        self.mutex.unlock();

        // Join all threads
        for (self.tasks.items) |*task| {
            if (task.thread) |thread| {
                thread.join();
            }
        }

        // Free all cancelled flags
        for (self.tasks.items) |*task| {
            self.allocator.destroy(task.cancelled);
        }

        self.tasks.deinit(self.allocator);
        self.event_queue.deinit(self.allocator);
    }

    /// Spawn a background task
    pub fn spawnTask(
        self: *AsyncEventLoop,
        context: anytype,
        comptime task_fn: fn (@TypeOf(context), *bool) anyerror!void,
        callback: TaskCallback,
        user_data: ?*anyopaque,
    ) !TaskHandle {
        // Allocate cancelled flag on heap for stable addressing
        const cancelled_ptr = try self.allocator.create(bool);
        errdefer self.allocator.destroy(cancelled_ptr);
        cancelled_ptr.* = false;

        self.mutex.lock();
        defer self.mutex.unlock();

        const task_id = self.next_task_id;
        self.next_task_id += 1;

        var task = Task{
            .id = task_id,
            .state = .pending,
            .callback = callback,
            .user_data = user_data,
            .thread = null,
            .cancelled = cancelled_ptr,
            .result = {},
        };

        // Spawn thread for task execution
        const ThreadContext = struct {
            loop: *AsyncEventLoop,
            task_id: u32,
            task_context: @TypeOf(context),
            task_fn_ptr: *const fn (@TypeOf(context), *bool) anyerror!void,
            cancelled_ptr: *bool, // Stable pointer to cancelled flag

            fn run(ctx: @This()) void {
                // Find task and mark as running
                ctx.loop.mutex.lock();
                var callback_fn: ?TaskCallback = null;
                var callback_data: ?*anyopaque = null;

                for (ctx.loop.tasks.items) |*t| {
                    if (t.id == ctx.task_id) {
                        t.state = .running;
                        // Store callback info while we have the lock
                        callback_fn = t.callback;
                        callback_data = t.user_data;
                        break;
                    }
                }
                ctx.loop.mutex.unlock();

                // Execute task function outside of lock with stable cancelled pointer
                const result = ctx.task_fn_ptr(ctx.task_context, ctx.cancelled_ptr);

                // Update task state - re-find task after re-acquiring lock
                {
                    ctx.loop.mutex.lock();
                    defer ctx.loop.mutex.unlock();

                    for (ctx.loop.tasks.items) |*t| {
                        if (t.id == ctx.task_id) {
                            t.result = result;
                            // cancelled flag is already updated via pointer
                            if (ctx.cancelled_ptr.*) {
                                t.state = .cancelled;
                            } else if (result) |_| {
                                t.state = .completed;
                            } else |_| {
                                t.state = .failed;
                            }
                            break;
                        }
                    }
                }

                // Invoke callback outside of lock to prevent deadlock
                if (callback_fn) |cb| {
                    cb(result, callback_data);
                }
            }
        };

        const thread_ctx = ThreadContext{
            .loop = self,
            .task_id = task_id,
            .task_context = context,
            .task_fn_ptr = &task_fn,
            .cancelled_ptr = cancelled_ptr, // Pass stable heap pointer
        };

        const thread = try std.Thread.spawn(.{}, ThreadContext.run, .{thread_ctx});

        task.thread = thread;
        try self.tasks.append(self.allocator, task);

        // Return stable pointer that won't be invalidated by array reallocation
        return TaskHandle{
            .id = task_id,
            .cancelled = cancelled_ptr,
        };
    }

    /// Cancel a background task
    pub fn cancelTask(self: *AsyncEventLoop, handle: TaskHandle) void {
        // Directly set the cancelled flag via stable pointer
        // No need for mutex since this is an atomic bool write
        handle.cancelled.* = true;

        // Update task state under lock
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.tasks.items) |*task| {
            if (task.id == handle.id) {
                // cancelled pointer already updated above
                if (task.state == .pending or task.state == .running) {
                    task.state = .cancelled;
                }
                break;
            }
        }
    }

    /// Get task state
    pub fn getTaskState(self: *AsyncEventLoop, handle: TaskHandle) ?TaskState {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.tasks.items) |*task| {
            if (task.id == handle.id) {
                return task.state;
            }
        }
        return null;
    }

    /// Push an event to the queue (thread-safe)
    pub fn pushEvent(self: *AsyncEventLoop, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.event_queue.append(self.allocator, event);
    }

    /// Poll for next event with configurable blocking mode
    pub fn pollEvent(
        self: *AsyncEventLoop,
        mode: PollMode,
        timeout_ms: u64,
    ) !?Event {
        // Check event queue first
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.event_queue.items.len > 0) {
                return self.event_queue.orderedRemove(0);
            }
        }

        // If quit requested, return null
        if (self.quit_requested) {
            return null;
        }

        // Try to read terminal event based on mode
        switch (mode) {
            .blocking => {
                // Wait indefinitely for terminal event
                return self.readTerminalEvent(null);
            },
            .timeout => {
                // Wait up to timeout for terminal event
                return self.readTerminalEvent(timeout_ms);
            },
            .nonblocking => {
                // Return immediately if no event
                return null;
            },
        }
    }

    /// Read event from terminal (internal)
    fn readTerminalEvent(self: *AsyncEventLoop, timeout_ms: ?u64) !?Event {
        // For blocking mode, loop with bounded timeouts until quit requested or byte arrives
        if (timeout_ms == null) {
            while (!self.quit_requested) {
                // Use 250ms per iteration to balance responsiveness and CPU usage
                if (try term_mod.readByte(250)) |first_byte| {
                    // Got first byte; try to read more for escape sequences
                    var buffer: [8]u8 = undefined;
                    buffer[0] = first_byte;
                    var len: usize = 1;

                    // If it's an ESC byte, try to read follow-up bytes with short timeout
                    if (first_byte == 0x1b) {
                        while (len < buffer.len) {
                            if (try term_mod.readByte(10)) |byte| {
                                buffer[len] = byte;
                                len += 1;
                                // Check if we have a complete sequence
                                if (decodeEventBytes(buffer[0..len])) |_| {
                                    break;
                                }
                            } else {
                                // Short timeout elapsed, assume complete sequence
                                break;
                            }
                        }
                    }

                    return decodeEventBytes(buffer[0..len]);
                }
            }
            return null;
        }

        // For timeout mode, respect caller's timeout_ms as total budget for first byte
        const timeout_u32 = @min(timeout_ms.?, std.math.maxInt(u32));
        if (try term_mod.readByte(timeout_u32)) |first_byte| {
            // Got first byte; try to read more for escape sequences with remaining time
            var buffer: [8]u8 = undefined;
            buffer[0] = first_byte;
            var len: usize = 1;

            // If it's an ESC byte, try to read follow-up bytes with short timeout
            if (first_byte == 0x1b) {
                while (len < buffer.len) {
                    if (try term_mod.readByte(10)) |byte| {
                        buffer[len] = byte;
                        len += 1;
                        // Check if we have a complete sequence
                        if (decodeEventBytes(buffer[0..len])) |_| {
                            break;
                        }
                    } else {
                        // Short timeout elapsed, assume complete sequence
                        break;
                    }
                }
            }

            return decodeEventBytes(buffer[0..len]);
        }

        return null;
    }

    /// Request event loop to quit
    pub fn requestQuit(self: *AsyncEventLoop) void {
        self.quit_requested = true;
    }

    /// Check if quit was requested
    pub fn shouldQuit(self: AsyncEventLoop) bool {
        return self.quit_requested;
    }

    /// Clean up completed/cancelled tasks
    pub fn cleanupTasks(self: *AsyncEventLoop) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.tasks.items.len) {
            const task = &self.tasks.items[i];
            if (task.state == .completed or task.state == .cancelled or task.state == .failed) {
                if (task.thread) |thread| {
                    thread.join();
                }
                // Free the heap-allocated cancelled flag
                self.allocator.destroy(task.cancelled);
                _ = self.tasks.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get count of active tasks
    pub fn activeTaskCount(self: *AsyncEventLoop) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var count: usize = 0;
        for (self.tasks.items) |*task| {
            if (task.state == .running or task.state == .pending) {
                count += 1;
            }
        }
        return count;
    }

    /// Get count of completed tasks
    pub fn completedTaskCount(self: *AsyncEventLoop) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var count: usize = 0;
        for (self.tasks.items) |*task| {
            if (task.state == .completed) {
                count += 1;
            }
        }
        return count;
    }
};

/// Decode raw terminal byte(s) into a single Event
/// Returns null for empty input or unrecognized sequences
pub fn decodeEventBytes(bytes: []const u8) ?Event {
    if (bytes.len == 0) {
        return null;
    }

    const first = bytes[0];

    // Single-byte special characters
    if (bytes.len == 1) {
        switch (first) {
            0x0D => return .{ .key = .{ .code = .enter } }, // \r
            0x0A => return .{ .key = .{ .code = .enter } }, // \n
            0x09 => return .{ .key = .{ .code = .tab } }, // \t
            0x08, 0x7F => return .{ .key = .{ .code = .backspace } }, // backspace / delete
            0x1B => return .{ .key = .{ .code = .esc } }, // ESC alone
            0x01...0x07, 0x0B...0x0C, 0x0E...0x1A => {
                // Ctrl+letter: 0x01 = Ctrl+A, 0x02 = Ctrl+B, ..., 0x1A = Ctrl+Z
                // (excluding 0x08 backspace, 0x09 tab, 0x0A newline, 0x0D carriage return)
                const char_code = first + 0x60; // 0x01 + 0x60 = 0x61 ('a')
                return .{ .key = .{ .code = .{ .char = char_code }, .modifiers = .{ .ctrl = true } } };
            },
            0x20...0x7E => return .{ .key = .{ .code = .{ .char = first } } }, // printable ASCII
            else => return null,
        }
    }

    // Multi-byte sequences
    if (first == 0x1B) {
        // Escape sequence

        if (bytes.len >= 2) {
            const second = bytes[1];

            // Alt+letter: ESC + letter
            if (second >= 0x41 and second <= 0x7E) {
                // ESC followed by printable ASCII
                if (bytes.len == 2) {
                    // Only if we have exactly 2 bytes (ESC + letter)
                    // To avoid matching incomplete CSI sequences, verify it's not CSI
                    if (second != '[' and second != 'O') {
                        return .{ .key = .{ .code = .{ .char = second }, .modifiers = .{ .alt = true } } };
                    }
                }
            }

            // CSI sequences: ESC [
            if (second == '[') {
                if (bytes.len >= 3) {
                    const third = bytes[2];

                    // CSI arrow keys (single letter)
                    if (bytes.len == 3) {
                        switch (third) {
                            'A' => return .{ .key = .{ .code = .up } },
                            'B' => return .{ .key = .{ .code = .down } },
                            'C' => return .{ .key = .{ .code = .right } },
                            'D' => return .{ .key = .{ .code = .left } },
                            'H' => return .{ .key = .{ .code = .home } },
                            'F' => return .{ .key = .{ .code = .end } },
                            else => return null,
                        }
                    }

                    // CSI digit sequences (ending with ~ or letter)
                    if (third >= '0' and third <= '9') {
                        var num: u32 = 0;
                        var idx: usize = 2;

                        // Parse digits
                        while (idx < bytes.len and bytes[idx] >= '0' and bytes[idx] <= '9') {
                            num = num * 10 + (bytes[idx] - '0');
                            idx += 1;
                        }

                        // Check if we have the terminator
                        if (idx < bytes.len) {
                            const term = bytes[idx];
                            if (term == '~' and idx + 1 == bytes.len) {
                                // CSI number~ format
                                switch (num) {
                                    1 => return .{ .key = .{ .code = .home } },
                                    2 => return .{ .key = .{ .code = .insert } },
                                    3 => return .{ .key = .{ .code = .delete } },
                                    4 => return .{ .key = .{ .code = .end } },
                                    5 => return .{ .key = .{ .code = .page_up } },
                                    6 => return .{ .key = .{ .code = .page_down } },
                                    15 => return .{ .key = .{ .code = .{ .f = 5 } } },
                                    17 => return .{ .key = .{ .code = .{ .f = 6 } } },
                                    18 => return .{ .key = .{ .code = .{ .f = 7 } } },
                                    19 => return .{ .key = .{ .code = .{ .f = 8 } } },
                                    20 => return .{ .key = .{ .code = .{ .f = 9 } } },
                                    21 => return .{ .key = .{ .code = .{ .f = 10 } } },
                                    23 => return .{ .key = .{ .code = .{ .f = 11 } } },
                                    24 => return .{ .key = .{ .code = .{ .f = 12 } } },
                                    else => return null,
                                }
                            }
                        }
                        return null;
                    }
                }
                return null;
            }

            // SS3 sequences: ESC O (Function keys F1-F4)
            if (second == 'O') {
                if (bytes.len == 3) {
                    const third = bytes[2];
                    switch (third) {
                        'P' => return .{ .key = .{ .code = .{ .f = 1 } } },
                        'Q' => return .{ .key = .{ .code = .{ .f = 2 } } },
                        'R' => return .{ .key = .{ .code = .{ .f = 3 } } },
                        'S' => return .{ .key = .{ .code = .{ .f = 4 } } },
                        else => return null,
                    }
                }
            }
        }
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "AsyncEventLoop init and deinit" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.shouldQuit());
    try std.testing.expectEqual(@as(usize, 0), loop.activeTaskCount());
}

test "AsyncEventLoop spawn task" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const TestContext = struct {
        value: *u32,
    };

    var test_value: u32 = 0;
    const ctx = TestContext{ .value = &test_value };

    var completed = false;
    const callback = struct {
        fn call(result: anyerror!void, user_data: ?*anyopaque) void {
            _ = result catch unreachable;
            const flag = @as(*bool, @ptrCast(@alignCast(user_data.?)));
            flag.* = true;
        }
    }.call;

    const task_fn = struct {
        fn run(context: TestContext, cancelled: *bool) anyerror!void {
            _ = cancelled;
            context.value.* = 42;
            // Short sleep to ensure task completes before deinit
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }.run;

    const handle = try loop.spawnTask(ctx, task_fn, callback, &completed);
    try std.testing.expect(handle.id > 0);

    // Wait for task to complete with timeout
    var retries: usize = 0;
    while (retries < 100 and !completed) : (retries += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    try std.testing.expect(completed);
    try std.testing.expectEqual(@as(u32, 42), test_value);

    // Clean up completed tasks before deinit
    loop.cleanupTasks();
}

test "AsyncEventLoop cancel task" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const TestContext = struct {
        value: *u32,
    };

    var test_value: u32 = 0;
    const ctx = TestContext{ .value = &test_value };

    var completed = false;
    const callback = struct {
        fn call(result: anyerror!void, user_data: ?*anyopaque) void {
            result catch {};
            const flag = @as(*bool, @ptrCast(@alignCast(user_data.?)));
            flag.* = true;
        }
    }.call;

    const task_fn = struct {
        fn run(context: TestContext, cancelled: *bool) anyerror!void {
            var i: u32 = 0;
            while (i < 100 and !cancelled.*) : (i += 1) {
                context.value.* = i;
                std.Thread.sleep(1 * std.time.ns_per_ms);
            }
        }
    }.run;

    const handle = try loop.spawnTask(ctx, task_fn, callback, &completed);

    // Give task time to start
    std.Thread.sleep(5 * std.time.ns_per_ms);

    // Cancel the task
    loop.cancelTask(handle);

    // Wait for callback
    var retries: usize = 0;
    while (retries < 200 and !completed) : (retries += 1) {
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    try std.testing.expect(completed);
    try std.testing.expect(test_value < 100); // Task should have been cancelled before completion

    // Clean up
    loop.cleanupTasks();
}

test "AsyncEventLoop push and poll event" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const event = Event{ .key = .{ .code = .{ .char = 'a' } } };
    try loop.pushEvent(event);

    const polled = try loop.pollEvent(.nonblocking, 0);
    try std.testing.expect(polled != null);
    if (polled) |e| {
        try std.testing.expectEqual(@as(u8, 'a'), e.key.code.char);
    }

    // Queue should be empty now
    const empty = try loop.pollEvent(.nonblocking, 0);
    try std.testing.expect(empty == null);
}

test "AsyncEventLoop quit request" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.shouldQuit());
    loop.requestQuit();
    try std.testing.expect(loop.shouldQuit());
}

test "AsyncEventLoop cleanup tasks" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const ctx = struct {
        value: u32 = 0,
    }{};

    var completed1 = false;
    var completed2 = false;

    const callback = struct {
        fn call(result: anyerror!void, user_data: ?*anyopaque) void {
            _ = result catch unreachable;
            const flag = @as(*bool, @ptrCast(@alignCast(user_data.?)));
            flag.* = true;
        }
    }.call;

    const quick_task = struct {
        fn run(context: @TypeOf(ctx), cancelled: *bool) anyerror!void {
            _ = context;
            _ = cancelled;
            std.Thread.sleep(5 * std.time.ns_per_ms);
        }
    }.run;

    _ = try loop.spawnTask(ctx, quick_task, callback, &completed1);
    _ = try loop.spawnTask(ctx, quick_task, callback, &completed2);

    try std.testing.expectEqual(@as(usize, 2), loop.activeTaskCount());

    // Wait for tasks to complete
    var retries: usize = 0;
    while (retries < 100 and (!completed1 or !completed2)) : (retries += 1) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    try std.testing.expect(completed1);
    try std.testing.expect(completed2);

    // Tasks should still be in list before cleanup
    try std.testing.expectEqual(@as(usize, 2), loop.completedTaskCount());

    // Cleanup should remove completed tasks
    loop.cleanupTasks();
    try std.testing.expectEqual(@as(usize, 0), loop.activeTaskCount());
    try std.testing.expectEqual(@as(usize, 0), loop.completedTaskCount());
}

test "AsyncEventLoop task state transitions" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const ctx = struct {
        value: u32 = 0,
    }{};

    var completed = false;
    const callback = struct {
        fn call(result: anyerror!void, user_data: ?*anyopaque) void {
            _ = result catch unreachable;
            const flag = @as(*bool, @ptrCast(@alignCast(user_data.?)));
            flag.* = true;
        }
    }.call;

    const task_fn = struct {
        fn run(context: @TypeOf(ctx), cancelled: *bool) anyerror!void {
            _ = context;
            _ = cancelled;
            std.Thread.sleep(20 * std.time.ns_per_ms);
        }
    }.run;

    const handle = try loop.spawnTask(ctx, task_fn, callback, &completed);

    // Task should start in pending state (may transition to running quickly)
    const initial_state = loop.getTaskState(handle);
    try std.testing.expect(initial_state == .pending or initial_state == .running);

    // Wait for task to start running (or complete if very fast). Poll with
    // retries instead of a single fixed sleep — a loaded scheduler (observed
    // on Windows CI) can take longer than 5ms to dispatch the spawned thread.
    var running_state: ?TaskState = null;
    var start_retries: usize = 0;
    while (start_retries < 100) : (start_retries += 1) {
        running_state = loop.getTaskState(handle);
        if (running_state == .running or running_state == .completed) break;
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(running_state == .running or running_state == .completed);

    // Wait for completion
    var retries: usize = 0;
    while (retries < 100 and !completed) : (retries += 1) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    const final_state = loop.getTaskState(handle);
    try std.testing.expectEqual(TaskState.completed, final_state.?);

    loop.cleanupTasks();
}

test "AsyncEventLoop multiple concurrent tasks" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const TestContext = struct {
        counter: *std.atomic.Value(u32),
    };

    var counter = std.atomic.Value(u32).init(0);
    const ctx = TestContext{ .counter = &counter };

    var completed_flags = [_]bool{false} ** 5;

    const callback = struct {
        fn call(result: anyerror!void, user_data: ?*anyopaque) void {
            _ = result catch unreachable;
            const flag = @as(*bool, @ptrCast(@alignCast(user_data.?)));
            flag.* = true;
        }
    }.call;

    const task_fn = struct {
        fn run(context: TestContext, cancelled: *bool) anyerror!void {
            _ = cancelled;
            _ = context.counter.fetchAdd(1, .seq_cst);
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }.run;

    // Spawn 5 concurrent tasks
    for (&completed_flags) |*flag| {
        _ = try loop.spawnTask(ctx, task_fn, callback, flag);
    }

    try std.testing.expectEqual(@as(usize, 5), loop.activeTaskCount());

    // Wait for all tasks to complete
    var all_done = false;
    var retries: usize = 0;
    while (!all_done and retries < 200) : (retries += 1) {
        all_done = true;
        for (completed_flags) |flag| {
            if (!flag) all_done = false;
        }
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    try std.testing.expect(all_done);
    try std.testing.expectEqual(@as(u32, 5), counter.load(.seq_cst));

    loop.cleanupTasks();
}

test "AsyncEventLoop error handling in tasks" {
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const ctx = struct {
        value: u32 = 0,
    }{};

    var completed = false;
    const callback = struct {
        fn call(result: anyerror!void, user_data: ?*anyopaque) void {
            _ = result catch {}; // Error is expected
            const flag = @as(*bool, @ptrCast(@alignCast(user_data.?)));
            flag.* = true;
        }
    }.call;

    const failing_task = struct {
        fn run(context: @TypeOf(ctx), cancelled: *bool) anyerror!void {
            _ = context;
            _ = cancelled;
            std.Thread.sleep(10 * std.time.ns_per_ms);
            return error.TaskFailed;
        }
    }.run;

    const handle = try loop.spawnTask(ctx, failing_task, callback, &completed);

    // Wait for task to fail
    var retries: usize = 0;
    while (retries < 100 and !completed) : (retries += 1) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    try std.testing.expect(completed);

    const state = loop.getTaskState(handle);
    try std.testing.expectEqual(TaskState.failed, state.?);

    loop.cleanupTasks();
}

test "AsyncEventLoop dangling pointer safety after array reallocation" {
    // This test ensures TaskHandle.cancelled pointer remains valid
    // even after tasks array reallocates
    var loop = AsyncEventLoop.init(std.testing.allocator);
    defer loop.deinit();

    const ctx = struct {
        value: u32 = 0,
    }{};

    var completed_flags: [20]bool = undefined;
    @memset(&completed_flags, false);

    const callback = struct {
        fn call(result: anyerror!void, user_data: ?*anyopaque) void {
            _ = result catch unreachable;
            const flag = @as(*bool, @ptrCast(@alignCast(user_data.?)));
            flag.* = true;
        }
    }.call;

    const long_task = struct {
        fn run(context: @TypeOf(ctx), cancelled: *bool) anyerror!void {
            _ = context;
            // Check cancelled flag multiple times during execution
            var i: usize = 0;
            while (i < 50 and !cancelled.*) : (i += 1) {
                std.Thread.sleep(1 * std.time.ns_per_ms);
            }
        }
    }.run;

    // Spawn many tasks to force array reallocation
    // This should expose dangling pointer bug if present
    var handles: [20]TaskHandle = undefined;
    for (&handles, 0..) |*handle, i| {
        handle.* = try loop.spawnTask(ctx, long_task, callback, &completed_flags[i]);
    }

    // Cancel first task - if its cancelled pointer is dangling, this could crash
    loop.cancelTask(handles[0]);

    // Wait for tasks
    var retries: usize = 0;
    while (retries < 200) : (retries += 1) {
        var all_done = true;
        for (completed_flags) |flag| {
            if (!flag) all_done = false;
        }
        if (all_done) break;
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // First task should have been cancelled
    try std.testing.expectEqual(TaskState.cancelled, loop.getTaskState(handles[0]).?);

    loop.cleanupTasks();
}

// ============================================================================
// decodeEventBytes Tests
// ============================================================================

test "decodeEventBytes: plain ASCII printable character 'a'" {
    const bytes = "a";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 'a'), result.?.key.code.char);
    try std.testing.expectEqual(false, result.?.key.modifiers.ctrl);
    try std.testing.expectEqual(false, result.?.key.modifiers.alt);
    try std.testing.expectEqual(false, result.?.key.modifiers.shift);
}

test "decodeEventBytes: plain ASCII printable character 'Z'" {
    const bytes = "Z";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 'Z'), result.?.key.code.char);
}

test "decodeEventBytes: carriage return (0x0d) decodes to enter" {
    const bytes = "\r";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.enter, result.?.key.code);
}

test "decodeEventBytes: newline (0x0a) decodes to enter" {
    const bytes = "\n";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.enter, result.?.key.code);
}

test "decodeEventBytes: tab (0x09) decodes to tab" {
    const bytes = "\t";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.tab, result.?.key.code);
}

test "decodeEventBytes: backspace (0x08) decodes to backspace" {
    const bytes = "\x08";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.backspace, result.?.key.code);
}

test "decodeEventBytes: delete (0x7f) decodes to backspace" {
    const bytes = "\x7f";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.backspace, result.?.key.code);
}

test "decodeEventBytes: Ctrl+C (0x03) decodes to char 'c' with ctrl=true" {
    const bytes = "\x03";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 'c'), result.?.key.code.char);
    try std.testing.expectEqual(true, result.?.key.modifiers.ctrl);
    try std.testing.expectEqual(false, result.?.key.modifiers.alt);
}

test "decodeEventBytes: Ctrl+W (0x17) decodes to char 'w' with ctrl=true" {
    const bytes = "\x17";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 'w'), result.?.key.code.char);
    try std.testing.expectEqual(true, result.?.key.modifiers.ctrl);
}

test "decodeEventBytes: Ctrl+A (0x01) decodes to char 'a' with ctrl=true" {
    const bytes = "\x01";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 'a'), result.?.key.code.char);
    try std.testing.expectEqual(true, result.?.key.modifiers.ctrl);
}

test "decodeEventBytes: lone ESC (0x1b) decodes to esc" {
    const bytes = "\x1b";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.esc, result.?.key.code);
}

test "decodeEventBytes: Alt+B (ESC followed by 'b') decodes to char 'b' with alt=true" {
    const bytes = "\x1bb";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 'b'), result.?.key.code.char);
    try std.testing.expectEqual(false, result.?.key.modifiers.ctrl);
    try std.testing.expectEqual(true, result.?.key.modifiers.alt);
}

test "decodeEventBytes: Alt+F (ESC followed by 'f') decodes to char 'f' with alt=true" {
    const bytes = "\x1bf";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 'f'), result.?.key.code.char);
    try std.testing.expectEqual(true, result.?.key.modifiers.alt);
}

test "decodeEventBytes: arrow up (CSI A) decodes to up" {
    const bytes = "\x1b[A";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.up, result.?.key.code);
}

test "decodeEventBytes: arrow down (CSI B) decodes to down" {
    const bytes = "\x1b[B";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.down, result.?.key.code);
}

test "decodeEventBytes: arrow right (CSI C) decodes to right" {
    const bytes = "\x1b[C";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.right, result.?.key.code);
}

test "decodeEventBytes: arrow left (CSI D) decodes to left" {
    const bytes = "\x1b[D";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.left, result.?.key.code);
}

test "decodeEventBytes: home (CSI H) decodes to home" {
    const bytes = "\x1b[H";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.home, result.?.key.code);
}

test "decodeEventBytes: home (CSI 1 tilde) decodes to home" {
    const bytes = "\x1b[1~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.home, result.?.key.code);
}

test "decodeEventBytes: end (CSI F) decodes to end" {
    const bytes = "\x1b[F";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.end, result.?.key.code);
}

test "decodeEventBytes: end (CSI 4 tilde) decodes to end" {
    const bytes = "\x1b[4~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.end, result.?.key.code);
}

test "decodeEventBytes: insert (CSI 2 tilde) decodes to insert" {
    const bytes = "\x1b[2~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.insert, result.?.key.code);
}

test "decodeEventBytes: delete (CSI 3 tilde) decodes to delete" {
    const bytes = "\x1b[3~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.delete, result.?.key.code);
}

test "decodeEventBytes: page up (CSI 5 tilde) decodes to page_up" {
    const bytes = "\x1b[5~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.page_up, result.?.key.code);
}

test "decodeEventBytes: page down (CSI 6 tilde) decodes to page_down" {
    const bytes = "\x1b[6~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(KeyCode.page_down, result.?.key.code);
}

test "decodeEventBytes: F1 (SS3 P) decodes to f=1" {
    const bytes = "\x1bOP";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 1), result.?.key.code.f);
}

test "decodeEventBytes: F2 (SS3 Q) decodes to f=2" {
    const bytes = "\x1bOQ";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 2), result.?.key.code.f);
}

test "decodeEventBytes: F3 (SS3 R) decodes to f=3" {
    const bytes = "\x1bOR";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 3), result.?.key.code.f);
}

test "decodeEventBytes: F4 (SS3 S) decodes to f=4" {
    const bytes = "\x1bOS";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 4), result.?.key.code.f);
}

test "decodeEventBytes: F5 (CSI 15 tilde) decodes to f=5" {
    const bytes = "\x1b[15~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 5), result.?.key.code.f);
}

test "decodeEventBytes: F6 (CSI 17 tilde) decodes to f=6" {
    const bytes = "\x1b[17~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 6), result.?.key.code.f);
}

test "decodeEventBytes: F7 (CSI 18 tilde) decodes to f=7" {
    const bytes = "\x1b[18~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 7), result.?.key.code.f);
}

test "decodeEventBytes: F8 (CSI 19 tilde) decodes to f=8" {
    const bytes = "\x1b[19~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 8), result.?.key.code.f);
}

test "decodeEventBytes: F9 (CSI 20 tilde) decodes to f=9" {
    const bytes = "\x1b[20~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 9), result.?.key.code.f);
}

test "decodeEventBytes: F10 (CSI 21 tilde) decodes to f=10" {
    const bytes = "\x1b[21~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 10), result.?.key.code.f);
}

test "decodeEventBytes: F11 (CSI 23 tilde) decodes to f=11" {
    const bytes = "\x1b[23~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 11), result.?.key.code.f);
}

test "decodeEventBytes: F12 (CSI 24 tilde) decodes to f=12" {
    const bytes = "\x1b[24~";
    const result = decodeEventBytes(bytes);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 12), result.?.key.code.f);
}

test "decodeEventBytes: empty byte slice returns null" {
    const bytes = "";
    const result = decodeEventBytes(bytes);
    try std.testing.expectEqual(@as(?Event, null), result);
}

test "decodeEventBytes: unrecognized CSI sequence (CSI 99 tilde) returns null" {
    const bytes = "\x1b[99~";
    const result = decodeEventBytes(bytes);
    // Unrecognized sequences return null (fail-safe behavior — don't crash on garbage)
    try std.testing.expectEqual(@as(?Event, null), result);
}

test "decodeEventBytes: unrecognized CSI sequence (CSI Z) returns null" {
    const bytes = "\x1b[Z";
    const result = decodeEventBytes(bytes);
    // Unrecognized sequences return null (fail-safe behavior — don't crash on garbage)
    try std.testing.expectEqual(@as(?Event, null), result);
}
