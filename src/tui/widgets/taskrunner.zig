//! TaskRunner widget: displays async task status and progress.
const std = @import("std");
const assert = std.debug.assert;
const maybe = @import("../../stdx.zig").maybe;
const Allocator = std.mem.Allocator;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
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
    tasks: std.ArrayList(TaskInfo),
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
            .tasks = try std.ArrayList(TaskInfo).initCapacity(allocator, 8),
            .block = null,
            .format = .normal,
            .symbols = StatusSymbols.default(),
            .show_progress_bars = true,
            .selected = null,
            .selected_style = Style{ .bold = true },
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

    /// Remove completed/cancelled/failed tasks. The selection is moved back into range.
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
        if (self.selected) |index| {
            if (self.tasks.items.len == 0) {
                self.selected = null;
            } else if (index >= self.tasks.items.len) {
                self.selected = self.tasks.items.len - 1;
            }
        }
        if (self.selected) |index| assert(index < self.tasks.items.len);
        if (self.tasks.items.len == 0) assert(self.selected == null);
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
    fn formatElapsed(elapsed_ms: u64, buf: []u8) error{NoSpaceLeft}![]const u8 {
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

    /// Draw `text` on row `y` from column `x_start`, one cell per character (wide characters
    /// take two, zero-width ones none), never at or past column `x_end`. Returns the column
    /// after the last drawn character. Preconditions: `x_start <= x_end` and `x_end` is within
    /// the buffer width.
    fn drawText(
        buf: *Buffer,
        x_start: u32,
        x_end: u32,
        y: u16,
        text: []const u8,
        style: Style,
    ) u32 {
        assert(x_start <= x_end);
        assert(x_end <= buf.width);

        var x = x_start;
        var i: usize = 0;
        while (i < text.len and x < x_end) {
            const char_len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            if (i + char_len > text.len) break;
            const codepoint = if (char_len == 1)
                @as(u21, text[i])
            else
                std.unicode.utf8Decode(text[i .. i + char_len]) catch @as(u21, text[i]);
            i += char_len;

            const char_width = UnicodeWidth.charWidth(codepoint);
            if (char_width == 0) continue;
            if (x + char_width > x_end) break;
            buf.set(@intCast(x), y, .{ .char = codepoint, .style = style });
            x += char_width;
        }
        assert(x >= x_start);
        assert(x <= x_end);
        return x;
    }

    /// Draw the status line of one task on row `y` inside `clip`.
    fn renderTaskLine(
        self: TaskRunner,
        buf: *Buffer,
        clip: Rect,
        y: u16,
        task: TaskInfo,
        is_selected: bool,
        current_time_ms: u64,
    ) void {
        const x_end: u32 = @as(u32, clip.x) + clip.width;
        const base_style = if (is_selected) self.selected_style else Style{};
        var state_style = base_style;
        state_style.fg = self.getStateColor(task.state);

        var x = drawText(buf, clip.x, x_end, y, self.getStateSymbol(task.state), state_style);
        x = drawText(buf, x, x_end, y, " ", base_style);
        x = drawText(buf, x, x_end, y, task.name, base_style);
        if (self.format == .compact) return;

        if (task.progress) |progress| {
            var progress_buf: [16]u8 = undefined;
            const text = std.fmt.bufPrint(
                &progress_buf,
                " ({d}%)",
                .{@min(progress, progress_percent_max)},
            ) catch |err| switch (err) {
                error.NoSpaceLeft => "",
            };
            x = drawText(buf, x, x_end, y, text, base_style);
        }
        if (self.format == .detailed) {
            var elapsed_buf: [64]u8 = undefined;
            const elapsed_ms = current_time_ms -| task.start_time_ms;
            const text = formatElapsed(elapsed_ms, &elapsed_buf) catch |err| switch (err) {
                error.NoSpaceLeft => "",
            };
            x = drawText(buf, x, x_end, y, " ", base_style);
            x = drawText(buf, x, x_end, y, text, base_style);
        }
        assert(x <= x_end);
    }

    /// Draw the "  Error: message" line of a failed task on row `y` inside `clip`.
    fn renderErrorLine(buf: *Buffer, clip: Rect, y: u16, message: []const u8) void {
        const x_end: u32 = @as(u32, clip.x) + clip.width;
        assert(y >= clip.y);
        assert(y - clip.y < clip.height);

        const error_style = Style{ .fg = .red };
        const x = drawText(buf, clip.x, x_end, y, "  Error: ", error_style);
        _ = drawText(buf, x, x_end, y, message, error_style);
    }

    /// Draw one task (status line, progress bar, error line) starting at row `y`.
    /// Returns the next free row, which may lie at or past the end of `clip`.
    fn renderTask(
        self: TaskRunner,
        buf: *Buffer,
        clip: Rect,
        y_start: u32,
        task: TaskInfo,
        is_selected: bool,
        current_time_ms: u64,
    ) u32 {
        const y_end: u32 = @as(u32, clip.y) + clip.height;
        assert(y_start < y_end);
        assert(y_end <= buf.height);

        var y = y_start;
        self.renderTaskLine(buf, clip, @intCast(y), task, is_selected, current_time_ms);
        y += 1;

        if (self.show_progress_bars and task.state == .running and y < y_end) {
            if (task.progress) |progress| {
                const bar_x: u32 = @as(u32, clip.x) + progress_bar_indent;
                const x_end: u32 = @as(u32, clip.x) + clip.width;
                if (bar_x < x_end) {
                    const gauge = (Gauge{}).withPercent(progress);
                    gauge.render(buf, .{
                        .x = @intCast(bar_x),
                        .y = @intCast(y),
                        .width = @intCast(@min(x_end - bar_x, progress_bar_width_max)),
                        .height = 1,
                    });
                }
                y += 1;
            }
        }

        if (task.state == .failed and y < y_end) {
            if (task.error_msg) |message| {
                renderErrorLine(buf, clip, @intCast(y), message);
                y += 1;
            }
        }
        assert(y > y_start);
        return y;
    }

    /// Render the widget. The area is clipped to the buffer; cells outside it are never touched.
    pub fn render(self: TaskRunner, buf: *Buffer, area: Rect, current_time_ms: u64) void {
        var render_area = area;

        // Draw block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        const buffer_area = Rect{ .x = 0, .y = 0, .width = buf.width, .height = buf.height };
        maybe(render_area.width == 0 or render_area.height == 0);
        const clip = render_area.intersection(buffer_area) orelse return;
        if (clip.width == 0 or clip.height == 0) return;

        const y_end: u32 = @as(u32, clip.y) + clip.height;
        assert(y_end <= buf.height);
        var y: u32 = clip.y;
        for (self.tasks.items, 0..) |task, idx| {
            if (y >= y_end) break;
            const is_selected = if (self.selected) |sel| sel == idx else false;
            y = self.renderTask(buf, clip, y, task, is_selected, current_time_ms);
        }
        assert(y >= clip.y);
    }
};

/// Largest progress percentage that is displayed; larger values are clamped.
const progress_percent_max: u8 = 100;

/// Columns the progress bar is indented below its task line.
const progress_bar_indent: u32 = 2;

/// Widest progress bar, in columns.
const progress_bar_width_max: u32 = 40;

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
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const handle = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, handle, "Test Task", 1000);

    try std.testing.expectEqual(@as(usize, 1), runner.tasks.items.len);
    try std.testing.expectEqualStrings("Test Task", runner.tasks.items[0].name);
    try std.testing.expectEqual(TaskState.pending, runner.tasks.items[0].state);
}

test "TaskRunner update task state" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const handle = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, handle, "Test Task", 1000);

    runner.updateTask(1, .running, 50);

    try std.testing.expectEqual(TaskState.running, runner.tasks.items[0].state);
    try std.testing.expectEqual(@as(?u8, 50), runner.tasks.items[0].progress);
}

test "TaskRunner fail task" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const handle = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, handle, "Test Task", 1000);

    runner.failTask(1, "Connection timeout");

    try std.testing.expectEqual(TaskState.failed, runner.tasks.items[0].state);
    try std.testing.expectEqualStrings("Connection timeout", runner.tasks.items[0].error_msg.?);
}

test "TaskRunner clear finished tasks" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    const h2 = TaskHandle{ .id = 2, .cancelled = &flag };
    const h3 = TaskHandle{ .id = 3, .cancelled = &flag };

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
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    const h2 = TaskHandle{ .id = 2, .cancelled = &flag };
    const h3 = TaskHandle{ .id = 3, .cancelled = &flag };

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
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    runner.format = .compact;
    runner.show_progress_bars = false;

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, h1, "Download file", 1000);
    runner.updateTask(1, .running, 50);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 2000);

    // First cell should contain the running symbol
    const cell = buffer.getConst(0, 0).?;
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render normal format" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    runner.format = .normal;
    runner.show_progress_bars = true;

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, h1, "Process data", 1000);
    runner.updateTask(1, .running, 75);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 3000);

    // Check that something was rendered (non-empty cells)
    const cell = buffer.getConst(0, 0).?;
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render detailed format" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    runner.format = .detailed;

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, h1, "Compile project", 1000);
    runner.updateTask(1, .running, 50);

    var buffer = try Buffer.init(std.testing.allocator, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    runner.render(&buffer, area, 5000);

    // Check rendering occurred
    const cell = buffer.getConst(0, 0).?;
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render with block border" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    var block = (Block{});
    block.borders = .all;
    block.title = "Background Tasks";
    runner.setBlock(block);

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, h1, "Task 1", 1000);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 2000);

    // Check that border was rendered (corners should be box-drawing chars)
    const top_left = buffer.getConst(0, 0).?;
    try std.testing.expect(top_left.char != ' ');
}

test "TaskRunner render failed task with error" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, h1, "Failed operation", 1000);
    runner.failTask(1, "Network error");

    var buffer = try Buffer.init(std.testing.allocator, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    runner.render(&buffer, area, 2000);

    // Check that error message line was rendered
    const cell = buffer.getConst(0, 0).?;
    try std.testing.expect(cell.char != ' ');
}

test "TaskRunner render with selection highlight" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    const h2 = TaskHandle{ .id = 2, .cancelled = &flag };

    try runner.addTask(std.testing.allocator, h1, "Task 1", 1000);
    try runner.addTask(std.testing.allocator, h2, "Task 2", 2000);

    runner.selectNext();

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    runner.render(&buffer, area, 3000);

    // Check that first task is rendered with bold style
    const cell = buffer.getConst(0, 0).?;
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
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    const h1 = TaskHandle{ .id = 1, .cancelled = &flag };
    try runner.addTask(std.testing.allocator, h1, "Task", 1000);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    runner.render(&buffer, area, 1000);

    // Should not crash with zero-size area
    try std.testing.expectEqual(@as(usize, 1), runner.tasks.items.len);
}

// ============================================================================
// Regression tests (bug #75 batch 7)
// ============================================================================

fn expectRow(buffer: Buffer, y: u16, x_start: u16, expected: []const u8) !void {
    for (expected, 0..) |char, offset| {
        const x = x_start + @as(u16, @intCast(offset));
        try std.testing.expectEqual(@as(u21, char), buffer.getChar(x, y));
    }
}

test "TaskRunner render draws multibyte symbol as one cell" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "Job", 0);
    runner.updateTask(1, .running, null);
    var buffer = try Buffer.init(std.testing.allocator, 20, 3);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 3 }, 0);

    try std.testing.expectEqual(@as(u21, '▶'), buffer.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(1, 0));
    try std.testing.expectEqual(Color.blue, buffer.getStyle(0, 0).fg.?);
    try expectRow(buffer, 0, 2, "Job");
    try std.testing.expectEqual(@as(?Color, null), buffer.getStyle(2, 0).fg);
}

test "TaskRunner render ascii symbols with progress and elapsed time" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);
    runner.symbols = StatusSymbols.ascii();
    runner.format = .detailed;
    runner.show_progress_bars = false;

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "Task", 1000);
    runner.updateTask(1, .running, 50);
    var buffer = try Buffer.init(std.testing.allocator, 30, 2);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 30, .height = 2 }, 5000);

    try expectRow(buffer, 0, 0, "> Task (50%) 4s");
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(15, 0));
}

test "TaskRunner render clamps progress above one hundred" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);
    runner.symbols = StatusSymbols.ascii();

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "Task", 0);
    runner.updateTask(1, .running, 250);
    var buffer = try Buffer.init(std.testing.allocator, 30, 3);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 30, .height = 3 }, 0);

    try expectRow(buffer, 0, 0, "> Task (100%)");
    // The gauge is drawn two columns in and is full at one hundred percent.
    try std.testing.expectEqual(@as(u21, '█'), buffer.getChar(2, 1));
    try std.testing.expectEqual(@as(u21, '█'), buffer.getChar(29, 1));
}

test "TaskRunner render failed task shows error line in red" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);
    runner.symbols = StatusSymbols.ascii();

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "Op", 0);
    runner.failTask(1, "Boom");
    var buffer = try Buffer.init(std.testing.allocator, 30, 3);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 30, .height = 3 }, 0);

    try expectRow(buffer, 0, 0, "ERR Op");
    try expectRow(buffer, 1, 0, "  Error: Boom");
    try std.testing.expectEqual(Color.red, buffer.getStyle(9, 1).fg.?);
}

test "TaskRunner render keeps long names and clips to the area" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);
    runner.symbols = StatusSymbols.ascii();
    runner.format = .compact;
    const name = "a" ** 290;

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, name, 0);
    runner.updateTask(1, .running, null);
    var buffer = try Buffer.init(std.testing.allocator, 300, 1);
    defer buffer.deinit();
    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 300, .height = 1 }, 0);

    try std.testing.expectEqual(@as(u21, 'a'), buffer.getChar(291, 0));
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(292, 0));

    var narrow = try Buffer.init(std.testing.allocator, 10, 1);
    defer narrow.deinit();
    runner.render(&narrow, .{ .x = 0, .y = 0, .width = 4, .height = 1 }, 0);
    try expectRow(narrow, 0, 0, "> aa");
    try std.testing.expectEqual(@as(u21, ' '), narrow.getChar(4, 0));
}

test "TaskRunner render stops at the last row of the area" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);
    runner.symbols = StatusSymbols.ascii();

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "One", 0);
    try runner.addTask(std.testing.allocator, .{ .id = 2, .cancelled = &flag }, "Two", 0);
    runner.updateTask(1, .running, 40);
    var buffer = try Buffer.init(std.testing.allocator, 20, 4);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 1 }, 0);

    try expectRow(buffer, 0, 0, "> One (40%)");
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(2, 1));
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(0, 1));
}

test "TaskRunner render inside block leaves the border intact" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);
    runner.symbols = StatusSymbols.ascii();
    runner.format = .compact;
    runner.setBlock(Block{});

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "LongTaskName", 0);
    try runner.addTask(std.testing.allocator, .{ .id = 2, .cancelled = &flag }, "Two", 0);
    var buffer = try Buffer.init(std.testing.allocator, 8, 3);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 8, .height = 3 }, 0);

    try std.testing.expectEqual(@as(u21, '┌'), buffer.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, '│'), buffer.getChar(0, 1));
    try std.testing.expectEqual(@as(u21, '│'), buffer.getChar(7, 1));
    try std.testing.expectEqual(@as(u21, '└'), buffer.getChar(0, 2));
    try expectRow(buffer, 1, 1, "... Lo");
}

test "TaskRunner render far or oversized area does not overflow" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);
    runner.symbols = StatusSymbols.ascii();

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "Task", 0);
    runner.updateTask(1, .running, 10);
    try runner.addTask(std.testing.allocator, .{ .id = 2, .cancelled = &flag }, "Bad", 0);
    runner.failTask(2, "Err");
    var buffer = try Buffer.init(std.testing.allocator, 20, 6);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 65530, .y = 65530, .width = 100, .height = 100 }, 0);
    runner.render(&buffer, .{ .x = 3, .y = 65534, .width = 65535, .height = 65535 }, 0);
    runner.render(&buffer, .{ .x = 65534, .y = 0, .width = 65535, .height = 65535 }, 0);
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), buffer.getChar(5, 3));

    runner.render(&buffer, .{ .x = 2, .y = 1, .width = 65535, .height = 65535 }, 0);
    try expectRow(buffer, 1, 2, "> Task (10%)");
    try expectRow(buffer, 4, 4, "Error: Err");
}

test "TaskRunner clear finished tasks keeps selection in range" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "A", 0);
    try runner.addTask(std.testing.allocator, .{ .id = 2, .cancelled = &flag }, "B", 0);
    try runner.addTask(std.testing.allocator, .{ .id = 3, .cancelled = &flag }, "C", 0);
    runner.selected = 2;
    runner.updateTask(2, .completed, null);
    runner.updateTask(3, .completed, null);

    runner.clearFinishedTasks();
    try std.testing.expectEqual(@as(usize, 1), runner.tasks.items.len);
    try std.testing.expectEqual(@as(?usize, 0), runner.selected);

    runner.updateTask(1, .cancelled, null);
    runner.clearFinishedTasks();
    try std.testing.expectEqual(@as(usize, 0), runner.tasks.items.len);
    try std.testing.expectEqual(@as(?usize, null), runner.selected);
}

test "TaskRunner render does not highlight unselected rows" {
    var flag = false;
    var runner = try TaskRunner.init(std.testing.allocator);
    defer runner.deinit(std.testing.allocator);

    try runner.addTask(std.testing.allocator, .{ .id = 1, .cancelled = &flag }, "A", 0);
    try runner.addTask(std.testing.allocator, .{ .id = 2, .cancelled = &flag }, "B", 0);
    runner.selectNext();
    runner.selectNext();
    var buffer = try Buffer.init(std.testing.allocator, 20, 3);
    defer buffer.deinit();

    runner.render(&buffer, .{ .x = 0, .y = 0, .width = 20, .height = 3 }, 0);

    try std.testing.expect(!buffer.getStyle(0, 0).bold);
    try std.testing.expect(buffer.getStyle(0, 1).bold);
}
