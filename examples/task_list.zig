//! Task List Example - Data Management Demo
//!
//! Demonstrates:
//! - Data structure modeling
//! - List widget with items
//! - Selection highlighting
//! - Task completion tracking
//!
//! Run with: zig build example-task_list

const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const layout = sailor.tui.layout;

const Task = struct {
    title: []const u8,
    done: bool,
};

const App = struct {
    tasks: []const Task = &[_]Task{
        .{ .title = "Learn Zig", .done = true },
        .{ .title = "Build a TUI app with Sailor", .done = true },
        .{ .title = "Read the docs", .done = false },
        .{ .title = "Write more examples", .done = false },
        .{ .title = "Deploy to production", .done = false },
    },
    selected: usize = 2,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const app = App{};

    // Get terminal size
    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 24);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = width, .height = height };

    const chunks = layout.split(.vertical, &.{
        .{ .length = 3 },
        .{ .min = 8 },
        .{ .length = 8 },
    }, area);

    // Title
    const title_style = Style{
        .fg = Color{ .indexed = 14 },
        .bold = true,
    };
    var title_block = Block{
        .title = "Task List Manager",
        .borders = .all,
        .border_style = title_style,
    };
    title_block.render(&buffer, chunks[0]);

    // Task list
    var task_block = Block{
        .title = "Tasks",
        .borders = .all,
    };
    task_block.render(&buffer, chunks[1]);

    const task_area = task_block.innerArea(chunks[1]);

    // Format task items
    var items_buf: [10][256]u8 = undefined;
    var items: [10][]const u8 = undefined;
    for (app.tasks, 0..) |task, i| {
        const marker = if (task.done) "[✓]" else "[ ]";
        const prefix = if (i == app.selected) "> " else "  ";
        items[i] = try std.fmt.bufPrint(&items_buf[i], "{s}{s} {s}", .{ prefix, marker, task.title });
    }

    var task_list = List{
        .items = items[0..app.tasks.len],
    };
    task_list.render(&buffer, task_area);

    // Stats and instructions
    var info_block = Block{
        .title = "Information",
        .borders = .all,
    };
    info_block.render(&buffer, chunks[2]);

    const info_area = info_block.innerArea(chunks[2]);

    const completed = blk: {
        var count: usize = 0;
        for (app.tasks) |task| {
            if (task.done) count += 1;
        }
        break :blk count;
    };

    var info_buf: [512]u8 = undefined;
    const info_text = try std.fmt.bufPrint(&info_buf,
        \\Progress: {d}/{d} tasks completed ({d}%)
        \\Selected: {s}
        \\
        \\This example demonstrates:
        \\  • Data modeling (Task struct)
        \\  • Selection state (> marker)
        \\  • List widget usage
        \\  • Computed statistics
    , .{
        completed,
        app.tasks.len,
        (completed * 100) / app.tasks.len,
        app.tasks[app.selected].title,
    });

    var info_para = Paragraph{
        .text = info_text,
        .alignment = .left,
    };
    info_para.render(&buffer, info_area);

    // Render
    const stdout = std.io.getStdOut().writer();
    try buffer.renderTo(stdout);

    std.debug.print("\n✓ Task list rendered successfully!\n", .{});
}
