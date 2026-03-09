const std = @import("std");
const Allocator = std.mem.Allocator;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const Gauge = @import("gauge.zig").Gauge;
const TaskState = @import("../async_loop.zig").TaskState;
const TaskHandle = @import("../async_loop.zig").TaskHandle;

/// Display format for task information
pub const TaskDisplayFormat = enum {
    /// Show only task name and status
    compact,
    /// Show task name, status, and progress percentage
    normal,
    /// Show task name, status, progress, and elapsed time
    detailed,
};

/// Status symbol set for task states
pub const StatusSymbols = struct {
    pending: []const u8,
    running: []const u8,
    completed: []const u8,
    cancelled: []const u8,
    failed: []const u8,

    /// Default symbols using Unicode characters
    pub fn default() StatusSymbols {
        return .{
            .pending = "⏳",
            .running = "▶",
            .completed = "✓",
            .cancelled = "✗",
            .failed = "✗",
        };
    }

    /// ASCII-safe symbols
    pub fn ascii() StatusSymbols {
        return .{
            .pending = "...",
            .running = ">",
            .completed = "OK",
            .cancelled = "X",
            .failed = "ERR",
        };
    }
};

/// Task information for display
pub const TaskInfo = struct {
    /// Task identifier (from AsyncEventLoop)
    handle: TaskHandle,
    /// Task name for display
    name: []const u8,
    /// Current state
    state: TaskState,
    /// Progress percentage (0-100), null if unknown
    progress: ?u8,
    /// Error message (only valid when state is failed)
    error_msg: ?[]const u8,
    /// Start timestamp (milliseconds)
    start_time_ms: u64,
};

/// Background task runner widget for parallel operation visualization
pub const TaskRunner = struct {
    /// List of tasks to display
    tasks: std.ArrayListUnmanaged(TaskInfo),
    /// Block widget for border and title
    block: ?Block,
    /// Display format
    format: TaskDisplayFormat,
    /// Status symbols
    symbols: StatusSymbols,
    /// Show progress bars for running tasks
    show_progress_bars: bool,
    /// Highlight selected task (null = no selection)
    selected: ?usize,
    /// Style for selected task
    selected_style: Style,
    /// Color scheme for states
    pending_color: Color,
    running_color: Color,
    completed_color: Color,
    cancelled_color: Color,
    failed_color: Color,

    /// Create a new task runner widget
    pub fn init(allocator: Allocator) !TaskRunner {
        return .{
            .tasks = try std.ArrayListUnmanaged(TaskInfo).initCapacity(allocator, 8),
            .block = null,
            .format = .normal,
            .symbols = StatusSymbols.default(),
            .show_progress_bars = true,
            .selected = null,
            .selected_style = Style.init().setBold(true),
            .pending_color = .yellow,
            .running_color = .blue,
            .completed_color = .green,
            .cancelled_color = .gray,
            .failed_color = .red,
        };
    }

    /// Clean up task list
    pub fn deinit(self: *TaskRunner, allocator: Allocator) void {
        self.tasks.deinit(allocator);
    }

    /// Set block border/title
    pub fn setBlock(self: *TaskRunner, block: Block) void {
        self.block = block;
    }

    /// Add a task to the widget
    pub fn addTask(
        self: *TaskRunner,
        allocator: Allocator,
        handle: TaskHandle,
        name: []const u8,
        start_time_ms: u64,
    ) !void {
        try self.tasks.append(allocator, .{
            .handle = handle,
            .name = name,
            .state = .pending,
            .progress = null,
            .error_msg = null,
            .start_time_ms = start_time_ms,
        });
    }

    /// Update task state and progress
    pub fn updateTask(
        self: *TaskRunner,
        task_id: u32,
        state: TaskState,
        progress: ?u8,
    ) void {
        for (self.tasks.items) |*task| {
            if (task.handle.id == task_id) {
                task.state = state;
                task.progress = progress;
                break;
            }
        }
    }

    /// Update task with error message
    pub fn failTask(self: *TaskRunner, task_id: u32, error_msg: []const u8) void {
        for (self.tasks.items) |*task| {
            if (task.handle.id == task_id) {
                task.state = .failed;
                task.error_msg = error_msg;
                break;
            }
        }
    }

    /// Remove completed/cancelled/failed tasks
    pub fn clearFinishedTasks(self: *TaskRunner) void {
        var i: usize = 0;
        while (i < self.tasks.items.len) {
            const task = &self.tasks.items[i];
            if (task.state == .completed or task.state == .cancelled or task.state == .failed) {
                _ = self.tasks.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Select next task
    pub fn selectNext(self: *TaskRunner) void {
        if (self.tasks.items.len == 0) {
            self.selected = null;
            return;
        }
        if (self.selected) |idx| {
            self.selected = (idx + 1) % self.tasks.items.len;
        } else {
            self.selected = 0;
        }
    }

    /// Select previous task
    pub fn selectPrev(self: *TaskRunner) void {
        if (self.tasks.items.len == 0) {
            self.selected = null;
            return;
        }
        if (self.selected) |idx| {
            self.selected = if (idx == 0) self.tasks.items.len - 1 else idx - 1;
        } else {
            self.selected = 0;
        }
    }

    /// Get color for task state
    fn getStateColor(self: TaskRunner, state: TaskState) Color {
        return switch (state) {
            .pending => self.pending_color,
            .running => self.running_color,
            .completed => self.completed_color,
            .cancelled => self.cancelled_color,
            .failed => self.failed_color,
        };
    }

    /// Get symbol for task state
    fn getStateSymbol(self: TaskRunner, state: TaskState) []const u8 {
        return switch (state) {
            .pending => self.symbols.pending,
            .running => self.symbols.running,
            .completed => self.symbols.completed,
            .cancelled => self.symbols.cancelled,
            .failed => self.symbols.failed,
        };
    }

    /// Format elapsed time
    fn formatElapsed(elapsed_ms: u64, buf: []u8) ![]const u8 {
        const seconds = elapsed_ms / 1000;
        if (seconds < 60) {
            return std.fmt.bufPrint(buf, "{d}s", .{seconds});
        } else if (seconds < 3600) {
            const mins = seconds / 60;
            const secs = seconds % 60;
            return std.fmt.bufPrint(buf, "{d}m{d}s", .{ mins, secs });
        } else {
            const hours = seconds / 3600;
            const mins = (seconds % 3600) / 60;
            return std.fmt.bufPrint(buf, "{d}h{d}m", .{ hours, mins });
        }
    }

    /// Render the widget
    pub fn render(self: TaskRunner, buf: *Buffer, area: Rect, current_time_ms: u64) void {
        var render_area = area;

        // Draw block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.height == 0 or render_area.width == 0) return;

        var y = render_area.y;
        const max_y = render_area.y + render_area.height;

        for (self.tasks.items, 0..) |task, idx| {
            if (y >= max_y) break;

            const is_selected = if (self.selected) |sel| sel == idx else false;
            const base_style = if (is_selected) self.selected_style else Style.init();
            const color = self.getStateColor(task.state);
            const symbol = self.getStateSymbol(task.state);
            const state_style = base_style.setFg(color);

            var line_buf: [256]u8 = undefined;
            var line_pos: usize = 0;

            // Symbol
            for (symbol) |c| {
                if (line_pos >= line_buf.len) break;
                line_buf[line_pos] = c;
                line_pos += 1;
            }
            if (line_pos < line_buf.len) {
                line_buf[line_pos] = ' ';
                line_pos += 1;
            }

            // Task name
            for (task.name) |c| {
                if (line_pos >= line_buf.len) break;
                line_buf[line_pos] = c;
                line_pos += 1;
            }

            // Add state info based on format
            if (self.format != .compact) {
                // Add progress percentage
                if (task.progress) |prog| {
                    const progress_str = std.fmt.bufPrint(
                        line_buf[line_pos..],
                        " ({d}%)",
                        .{prog},
                    ) catch "";
                    line_pos += progress_str.len;
                }

                // Add elapsed time in detailed mode
                if (self.format == .detailed) {
                    const elapsed = current_time_ms -| task.start_time_ms;
                    const time_str = formatElapsed(elapsed, line_buf[line_pos..]) catch "";
                    if (time_str.len > 0) {
                        if (line_pos < line_buf.len - 1) {
                            line_buf[line_pos] = ' ';
                            line_pos += 1;
                        }
                        for (time_str) |c| {
                            if (line_pos >= line_buf.len) break;
                            line_buf[line_pos] = c;
                            line_pos += 1;
                        }
                    }
                }
            }

            // Render task line
            const line = line_buf[0..line_pos];
            for (line, 0..) |c, x| {
                if (x >= render_area.width) break;
                const style = if (x < symbol.len) state_style else base_style;
                buf.setCell(render_area.x + @as(u16, @intCast(x)), y, c, style);
            }

            y += 1;
            if (y >= max_y) break;

            // Show progress bar for running tasks
            if (self.show_progress_bars and task.state == .running and task.progress != null) {
                if (y >= max_y) break;

                const gauge = Gauge.init(task.progress.? * 10); // 0-100 to 0-1000
                gauge.render(buf, .{
                    .x = render_area.x + 2,
                    .y = y,
                    .width = @min(render_area.width -| 2, 40),
                    .height = 1,
                });

                y += 1;
            }

            // Show error message for failed tasks
            if (task.state == .failed and task.error_msg != null) {
                if (y >= max_y) break;

                const error_style = Style.init().setFg(.red);
                const prefix = "  Error: ";
                for (prefix, 0..) |c, x| {
                    if (x >= render_area.width) break;
                    buf.setCell(render_area.x + @as(u16, @intCast(x)), y, c, error_style);
                }

                if (prefix.len < render_area.width) {
                    const msg = task.error_msg.?;
                    for (msg, 0..) |c, x| {
                        const cell_x = prefix.len + x;
                        if (cell_x >= render_area.width) break;
                        buf.setCell(render_area.x + @as(u16, @intCast(cell_x)), y, c, error_style);
                    }
                }

                y += 1;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TaskRunner init and deinit" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), runner.tasks.items.len);
    try std.testing.expectEqual(TaskDisplayFormat.normal, runner.format);
}

test "TaskRunner add task" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const handle = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, handle, "Test Task", 1000);

    try std.testing.expectEqual(@as(usize, 1), runner.tasks.items.len);
    try std.testing.expectEqualStrings("Test Task", runner.tasks.items[0].name);
    try std.testing.expectEqual(TaskState.pending, runner.tasks.items[0].state);
}

test "TaskRunner update task state" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const handle = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, handle, "Test Task", 1000);

    runner.updateTask(1, .running, 50);

    try std.testing.expectEqual(TaskState.running, runner.tasks.items[0].state);
    try std.testing.expectEqual(@as(?u8, 50), runner.tasks.items[0].progress);
}

test "TaskRunner fail task" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const handle = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, handle, "Test Task", 1000);

    runner.failTask(1, "Connection timeout");

    try std.testing.expectEqual(TaskState.failed, runner.tasks.items[0].state);
    try std.testing.expectEqualStrings("Connection timeout", runner.tasks.items[0].error_msg.?);
}

test "TaskRunner clear finished tasks" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    const h2 = TaskHandle{ .id = 2, .cancelled = undefined };
    const h3 = TaskHandle{ .id = 3, .cancelled = undefined };

    try runner.addTask(std.testing.allocator, h1, "Task 1", 1000);
    try runner.addTask(std.testing.allocator, h2, "Task 2", 2000);
    try runner.addTask(std.testing.allocator, h3, "Task 3", 3000);

    runner.updateTask(1, .completed, 100);
    runner.updateTask(2, .running, 50);
    runner.updateTask(3, .failed, null);
    runner.failTask(3, "Error");

    runner.clearFinishedTasks();

    try std.testing.expectEqual(@as(usize, 1), runner.tasks.items.len);
    try std.testing.expectEqual(@as(u32, 2), runner.tasks.items[0].handle.id);
}

test "TaskRunner selection navigation" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    const h2 = TaskHandle{ .id = 2, .cancelled = undefined };
    const h3 = TaskHandle{ .id = 3, .cancelled = undefined };

    try runner.addTask(std.testing.allocator, h1, "Task 1", 1000);
    try runner.addTask(std.testing.allocator, h2, "Task 2", 2000);
    try runner.addTask(std.testing.allocator, h3, "Task 3", 3000);

    try std.testing.expectEqual(@as(?usize, null), runner.selected);

    runner.selectNext();
    try std.testing.expectEqual(@as(?usize, 0), runner.selected);

    runner.selectNext();
    try std.testing.expectEqual(@as(?usize, 1), runner.selected);

    runner.selectNext();
    try std.testing.expectEqual(@as(?usize, 2), runner.selected);

    runner.selectNext(); // Wrap around
    try std.testing.expectEqual(@as(?usize, 0), runner.selected);

    runner.selectPrev();
    try std.testing.expectEqual(@as(?usize, 2), runner.selected);
}

test "TaskRunner state colors" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    try std.testing.expectEqual(Color.yellow, runner.getStateColor(.pending));
    try std.testing.expectEqual(Color.blue, runner.getStateColor(.running));
    try std.testing.expectEqual(Color.green, runner.getStateColor(.completed));
    try std.testing.expectEqual(Color.gray, runner.getStateColor(.cancelled));
    try std.testing.expectEqual(Color.red, runner.getStateColor(.failed));
}

test "TaskRunner state symbols" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const symbols = StatusSymbols.default();
    runner.symbols = symbols;

    try std.testing.expectEqualStrings(symbols.pending, runner.getStateSymbol(.pending));
    try std.testing.expectEqualStrings(symbols.running, runner.getStateSymbol(.running));
    try std.testing.expectEqualStrings(symbols.completed, runner.getStateSymbol(.completed));
    try std.testing.expectEqualStrings(symbols.cancelled, runner.getStateSymbol(.cancelled));
    try std.testing.expectEqualStrings(symbols.failed, runner.getStateSymbol(.failed));
}

test "TaskRunner ASCII symbols" {
    const symbols = StatusSymbols.ascii();

    try std.testing.expectEqualStrings("...", symbols.pending);
    try std.testing.expectEqualStrings(">", symbols.running);
    try std.testing.expectEqualStrings("OK", symbols.completed);
    try std.testing.expectEqualStrings("X", symbols.cancelled);
    try std.testing.expectEqualStrings("ERR", symbols.failed);
}

test "TaskRunner format elapsed time" {
    var buf: [64]u8 = undefined;

    // Seconds
    const result1 = try TaskRunner.formatElapsed(5000, &buf);
    try std.testing.expectEqualStrings("5s", result1);

    // Minutes and seconds
    const result2 = try TaskRunner.formatElapsed(125000, &buf);
    try std.testing.expectEqualStrings("2m5s", result2);

    // Hours and minutes
    const result3 = try TaskRunner.formatElapsed(7320000, &buf);
    try std.testing.expectEqualStrings("2h2m", result3);
}

test "TaskRunner render compact format" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    runner.format = .compact;
    runner.show_progress_bars = false;

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, h1, "Download file", 1000);
    runner.updateTask(1, .running, 50);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 2000);

    // First cell should contain the running symbol
    const cell = buffer.getCell(0, 0);
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render normal format" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    runner.format = .normal;
    runner.show_progress_bars = true;

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, h1, "Process data", 1000);
    runner.updateTask(1, .running, 75);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 3000);

    // Check that something was rendered (non-empty cells)
    const cell = buffer.getCell(0, 0);
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render detailed format" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    runner.format = .detailed;

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, h1, "Compile project", 1000);
    runner.updateTask(1, .running, 50);

    var buffer = try Buffer.init(std.testing.allocator, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    runner.render(&buffer, area, 5000);

    // Check rendering occurred
    const cell = buffer.getCell(0, 0);
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render with block border" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    var block = Block.init();
    block.setBorder(true);
    block.setTitle("Background Tasks");
    runner.setBlock(block);

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, h1, "Task 1", 1000);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 2000);

    // Check that border was rendered (corners should be box-drawing chars)
    const top_left = buffer.getCell(0, 0);
    try std.testing.expect(top_left.char != ' ');
}

test "TaskRunner render failed task with error" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, h1, "Failed operation", 1000);
    runner.failTask(1, "Network error");

    var buffer = try Buffer.init(std.testing.allocator, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    runner.render(&buffer, area, 2000);

    // Check that error message line was rendered
    const cell = buffer.getCell(0, 0);
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render with selection highlight" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    const h2 = TaskHandle{ .id = 2, .cancelled = undefined };

    try runner.addTask(std.testing.allocator, h1, "Task 1", 1000);
    try runner.addTask(std.testing.allocator, h2, "Task 2", 2000);

    runner.selectNext();

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 3000);

    // Check that first task is rendered with bold style
    const cell = buffer.getCell(0, 0);
    try std.testing.expect(cell.style.bold);
}

test "TaskRunner render empty task list" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 1000);

    // Empty widget should not crash
    try std.testing.expectEqual(@as(usize, 0), runner.tasks.items.len);
}

test "TaskRunner render zero-size area" {
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = undefined };
    try runner.addTask(std.testing.allocator, h1, "Task", 1000);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    runner.render(&buffer, area, 1000);

    // Should not crash with zero-size area
    try std.testing.expectEqual(@as(usize, 1), runner.tasks.items.len);
}
