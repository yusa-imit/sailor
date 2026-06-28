//! GanttChart Widget — timeline visualization for project tasks
//!
//! The GanttChart widget displays a list of tasks with visual bars representing
//! their timeline, progress, and duration. Each task is rendered on its own row
//! with a label and progress bar.
//!
//! ## Features
//! - Task rendering with name labels and timeline bars
//! - Progress visualization with filled (█) and empty (░) characters
//! - Auto-scaling bars based on maximum task end time
//! - Focused task highlighting
//! - Customizable label width and progress display
//! - Block border support
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var tasks = [_]Task{
//!     .{ .name = "Design", .start = 0, .end = 5, .progress = 100 },
//!     .{ .name = "Development", .start = 5, .end = 15, .progress = 50 },
//! };
//! var chart = GanttChart.init()
//!     .withTasks(&tasks)
//!     .withLabelWidth(20);
//! chart.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// A single task in the Gantt chart
pub const Task = struct {
    name: []const u8 = "",
    start: u16 = 0,
    end: u16 = 0,
    progress: u8 = 0,          // 0-100
    style: ?Style = null,
};

/// GanttChart widget for visualizing tasks and timelines
pub const GanttChart = struct {
    /// Maximum number of tasks to display
    pub const MAX_TASKS: usize = 64;

    /// Array of tasks to display
    tasks: []const Task = &.{},

    /// Index of the focused task
    focused: usize = 0,

    /// Base style for the entire widget
    style: Style = .{},

    /// Style for incomplete (empty) bar portions
    bar_style: Style = .{},

    /// Style for focused task row
    focused_style: Style = .{},

    /// Style for completed (filled) bar portions
    complete_style: Style = .{},

    /// Width allocated for task labels (in characters)
    label_width: u16 = 20,

    /// Whether to show progress (true = partial fill, false = full bar)
    show_progress: bool = true,

    /// Optional border block
    block: ?Block = null,

    /// Initialize a new GanttChart with defaults
    pub fn init() GanttChart {
        return .{};
    }

    /// Create a copy with different tasks
    pub fn withTasks(self: GanttChart, tasks: []const Task) GanttChart {
        var result = self;
        result.tasks = tasks;
        return result;
    }

    /// Create a copy with different focused index
    pub fn withFocused(self: GanttChart, focused: usize) GanttChart {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: GanttChart, style: Style) GanttChart {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different bar style
    pub fn withBarStyle(self: GanttChart, style: Style) GanttChart {
        var result = self;
        result.bar_style = style;
        return result;
    }

    /// Create a copy with different focused style
    pub fn withFocusedStyle(self: GanttChart, style: Style) GanttChart {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Create a copy with different complete style
    pub fn withCompleteStyle(self: GanttChart, style: Style) GanttChart {
        var result = self;
        result.complete_style = style;
        return result;
    }

    /// Create a copy with different label width
    pub fn withLabelWidth(self: GanttChart, width: u16) GanttChart {
        var result = self;
        result.label_width = width;
        return result;
    }

    /// Create a copy with progress display toggled
    pub fn withShowProgress(self: GanttChart, show: bool) GanttChart {
        var result = self;
        result.show_progress = show;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: GanttChart, block: Block) GanttChart {
        var result = self;
        result.block = block;
        return result;
    }

    /// Get the number of tasks (clamped to MAX_TASKS)
    pub fn taskCount(self: GanttChart) usize {
        return @min(self.tasks.len, MAX_TASKS);
    }

    /// Render the Gantt chart to the buffer
    pub fn render(self: GanttChart, buf: *Buffer, area: Rect) void {
        // Early exit for zero-area
        if (area.width == 0 or area.height == 0) {
            return;
        }

        // Determine the render area (handle block border if present)
        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        // Early exit if inner area is zero
        if (inner.width == 0 or inner.height == 0) {
            return;
        }

        // Get count of tasks to render
        const count = self.taskCount();
        if (count == 0) {
            return;
        }

        // Find maximum end time for scaling
        var max_end: u16 = 0;
        for (0..count) |i| {
            if (self.tasks[i].end > max_end) {
                max_end = self.tasks[i].end;
            }
        }
        // Default to 1 if all tasks have end=0 to avoid division by zero
        if (max_end == 0) {
            max_end = 1;
        }

        // Render each task row
        var row: u16 = 0;
        while (row < inner.height and row < count) : (row += 1) {
            const task = self.tasks[row];
            const y = inner.y + row;
            const is_focused = (row == self.focused);

            // Compute label area width (min of label_width or available inner.width)
            const label_width = @min(self.label_width, inner.width);

            // If focused, fill entire row with focused style background
            if (is_focused) {
                var col: u16 = 0;
                while (col < inner.width) : (col += 1) {
                    buf.set(inner.x + col, y, buffer_mod.Cell.init(' ', self.focused_style));
                }
            }

            // Render label
            {
                var col: u16 = 0;
                while (col < label_width and col < inner.width and col < @as(u16, @intCast(task.name.len))) : (col += 1) {
                    const char = if (task.name.len > col)
                        blk: {
                            const byte = task.name[col];
                            const len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
                            const codepoint = if (len == 1)
                                @as(u21, byte)
                            else
                                std.unicode.utf8Decode(task.name[col .. col + len]) catch byte;
                            break :blk codepoint;
                        }
                    else
                        ' ';

                    const label_style = if (is_focused) self.focused_style else self.style;
                    buf.set(inner.x + col, y, buffer_mod.Cell.init(char, label_style));
                }

                // Pad label with spaces to label_width
                while (col < label_width and col < inner.width) : (col += 1) {
                    const label_style = if (is_focused) self.focused_style else self.style;
                    buf.set(inner.x + col, y, buffer_mod.Cell.init(' ', label_style));
                }
            }

            // Render separator if we have room
            if (label_width < inner.width) {
                const sep_style = if (is_focused) self.focused_style else self.style;
                buf.set(inner.x + label_width, y, buffer_mod.Cell.init('│', sep_style));
            }

            // Render bar area
            {
                // Bar starts after label + separator
                const bar_start_col: u16 = label_width + @intFromBool(label_width < inner.width);
                if (bar_start_col < inner.width) {
                    const bar_width: u16 = inner.width - bar_start_col;

                    // Calculate bar position and width in timeline
                    const bar_start_pixel: u16 = @intCast((@as(u32, task.start) * @as(u32, bar_width)) / @as(u32, max_end));
                    const bar_end_pixel: u16 = @intCast((@as(u32, task.end) * @as(u32, bar_width)) / @as(u32, max_end));

                    // Calculate how much of the bar is filled based on progress
                    const bar_actual_width = if (bar_end_pixel > bar_start_pixel)
                        bar_end_pixel - bar_start_pixel
                    else
                        0;
                    const complete_chars: u16 = if (self.show_progress and bar_actual_width > 0)
                        @intCast((@as(u32, bar_actual_width) * @as(u32, task.progress)) / 100)
                    else if (!self.show_progress)
                        bar_actual_width
                    else
                        0;

                    // Render each column in the bar area
                    var col: u16 = 0;
                    while (col < bar_width) : (col += 1) {
                        const px = bar_start_col + col;
                        if (px < inner.width) {
                            const char: u21 = if (col >= bar_start_pixel and col < bar_end_pixel)
                                // Inside bar range
                                if (col < bar_start_pixel + complete_chars)
                                    '█'  // Filled
                                else
                                    '░'  // Empty
                            else
                                ' ';  // Outside bar range

                            const cell_style = if (is_focused)
                                self.focused_style
                            else if (char == '█')
                                task.style orelse self.complete_style
                            else if (char == '░')
                                task.style orelse self.bar_style
                            else
                                self.style;

                            buf.set(inner.x + px, y, buffer_mod.Cell.init(char, cell_style));
                        }
                    }
                }
            }
        }
    }
};
