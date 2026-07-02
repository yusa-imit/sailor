//! GanttChart Widget — Task Timeline Visualization
//!
//! GanttChart displays a list of tasks as horizontal bars on a timeline,
//! with each task positioned and sized according to its start and end times
//! within the overall time range.
//!
//! ## Features
//! - Task visualization as horizontal bars (█ character)
//! - Time-range scaling (configurable start/end time)
//! - Optional task labels
//! - Focused task highlighting with custom styles
//! - Capping at MAX_TASKS (32)
//! - Optional block borders
//! - Builder pattern for configuration
//!
//! ## Usage
//! ```zig
//! var tasks = [_]GanttTask{
//!     .{ .label = "Design", .start = 0.0, .end = 0.3 },
//!     .{ .label = "Build", .start = 0.3, .end = 0.8 },
//! };
//!
//! const gc = GanttChart.init()
//!     .withTasks(&tasks)
//!     .withTimeStart(0.0)
//!     .withTimeEnd(1.0);
//!
//! gc.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

pub const GanttTask = struct {
    label: []const u8 = "",
    start: f32 = 0.0,
    end: f32 = 1.0,
    style: Style = .{},

    /// Initialize a new GanttTask with default values
    pub fn init() GanttTask {
        return .{};
    }

    /// Set task label (builder pattern)
    pub fn withLabel(self: GanttTask, label: []const u8) GanttTask {
        var result = self;
        result.label = label;
        return result;
    }

    /// Set start time (builder pattern)
    pub fn withStart(self: GanttTask, start: f32) GanttTask {
        var result = self;
        result.start = start;
        return result;
    }

    /// Set end time (builder pattern)
    pub fn withEnd(self: GanttTask, end: f32) GanttTask {
        var result = self;
        result.end = end;
        return result;
    }

    /// Set task style (builder pattern)
    pub fn withStyle(self: GanttTask, style: Style) GanttTask {
        var result = self;
        result.style = style;
        return result;
    }
};

pub const GanttChart = struct {
    pub const MAX_TASKS: usize = 32;

    tasks: []const GanttTask = &.{},
    focused: usize = 0,
    time_start: f32 = 0.0,
    time_end: f32 = 1.0,
    show_labels: bool = true,
    style: Style = .{},
    task_style: Style = .{},
    focused_style: Style = .{},
    block: ?Block = null,

    /// Initialize a new GanttChart with default values
    pub fn init() GanttChart {
        return .{};
    }

    /// Return the number of tasks to render (capped at MAX_TASKS)
    pub fn taskCount(self: GanttChart) usize {
        return @min(self.tasks.len, MAX_TASKS);
    }

    /// Set tasks (builder pattern)
    pub fn withTasks(self: GanttChart, tasks: []const GanttTask) GanttChart {
        var result = self;
        result.tasks = tasks;
        return result;
    }

    /// Set focused task index (builder pattern)
    pub fn withFocused(self: GanttChart, idx: usize) GanttChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set time_start (builder pattern)
    pub fn withTimeStart(self: GanttChart, ts: f32) GanttChart {
        var result = self;
        result.time_start = ts;
        return result;
    }

    /// Set time_end (builder pattern)
    pub fn withTimeEnd(self: GanttChart, te: f32) GanttChart {
        var result = self;
        result.time_end = te;
        return result;
    }

    /// Set show_labels (builder pattern)
    pub fn withShowLabels(self: GanttChart, show: bool) GanttChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set base style (builder pattern)
    pub fn withStyle(self: GanttChart, s: Style) GanttChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set task style (builder pattern)
    pub fn withTaskStyle(self: GanttChart, s: Style) GanttChart {
        var result = self;
        result.task_style = s;
        return result;
    }

    /// Set focused style (builder pattern)
    pub fn withFocusedStyle(self: GanttChart, s: Style) GanttChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set optional block border (builder pattern)
    pub fn withBlock(self: GanttChart, b: Block) GanttChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the gantt chart to the buffer
    pub fn render(self: *const GanttChart, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block border if present
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            inner_area = block.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Get actual task count (capped)
        const n = self.taskCount();

        // Fill background with base style
        buf.fill(inner_area, ' ', self.style);

        if (n == 0) return;

        // Calculate time span, clamp to avoid division by zero
        var time_span = self.time_end - self.time_start;
        if (time_span < 0.001) time_span = 0.001;

        // Render each task as a horizontal bar
        for (0..n) |i| {
            if (i >= inner_area.height) break; // Don't render beyond area height

            const task = self.tasks[i];
            const row_y = inner_area.y + @as(u16, @intCast(i));

            // Map task times to x coordinates
            const x_start_f = @as(f32, @floatFromInt(inner_area.width)) * (task.start - self.time_start) / time_span;
            const x_end_f = @as(f32, @floatFromInt(inner_area.width)) * (task.end - self.time_start) / time_span;

            // Convert to u16 with bounds checking
            const x_start_unclamped = @max(0.0, @min(x_start_f, @as(f32, @floatFromInt(inner_area.width))));
            const x_end_unclamped = @max(0.0, @min(x_end_f, @as(f32, @floatFromInt(inner_area.width))));

            const x_start = inner_area.x + @as(u16, @intFromFloat(x_start_unclamped));
            const x_end = inner_area.x + @as(u16, @intFromFloat(x_end_unclamped));

            // Determine style for this task
            const actual_style = if (i == self.focused)
                self.focused_style
            else
                self.style.merge(self.task_style).merge(task.style);

            // Render bar (█ character) for this task
            var x = x_start;
            while (x < x_end and x < inner_area.x + inner_area.width) : (x += 1) {
                buf.set(x, row_y, Cell{ .char = '█', .style = actual_style });
            }

            // Render label if enabled and we have space
            if (self.show_labels and task.label.len > 0 and x_end > x_start) {
                const label_space = x_end - x_start;
                const label_len = @min(task.label.len, label_space);

                for (0..label_len) |j| {
                    buf.set(x_start + @as(u16, @intCast(j)), row_y, Cell{
                        .char = task.label[j],
                        .style = actual_style,
                    });
                }
            }
        }
    }
};
