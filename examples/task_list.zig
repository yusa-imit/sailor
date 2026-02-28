const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const List = sailor.tui.widgets.List;
const StatusBar = sailor.tui.widgets.StatusBar;
const Gauge = sailor.tui.widgets.Gauge;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Constraint = sailor.tui.Constraint;
const layout = sailor.tui.layout;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 24);

    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect.new(0, 0, width, height);

    // Main layout: progress bar + task list + status bar
    const main_chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .length = 3 }, // Progress gauge
            .{ .min = 1 }, // Task list
            .{ .length = 1 }, // Status bar
        },
    );
    defer allocator.free(main_chunks);

    // Task data
    const tasks = [_]struct {
        name: []const u8,
        done: bool,
    }{
        .{ .name = "Design API", .done = true },
        .{ .name = "Implement core modules", .done = true },
        .{ .name = "Write comprehensive tests", .done = true },
        .{ .name = "Add documentation", .done = true },
        .{ .name = "Release v1.0", .done = true },
        .{ .name = "Gather user feedback", .done = false },
        .{ .name = "Plan v2.0 features", .done = false },
    };

    // Calculate progress
    var completed: usize = 0;
    for (tasks) |task| {
        if (task.done) completed += 1;
    }
    const ratio = @as(f64, @floatFromInt(completed)) / @as(f64, @floatFromInt(tasks.len));

    // Progress gauge
    var progress_label_buf: [64]u8 = undefined;
    const progress_label = try std.fmt.bufPrint(&progress_label_buf, "{d}/{d} Tasks Complete ({d}%)", .{ completed, tasks.len, @as(usize, @intFromFloat(ratio * 100)) });

    const gauge = Gauge{
        .block = Block{
            .title = "Project Progress",
            .borders = .all,
            .border_style = Style{ .fg = Color{ .indexed = 12 } },
        },
        .ratio = ratio,
        .label = progress_label,
        .filled_style = Style{
            .fg = Color{ .indexed = 0 },
            .bg = Color{ .indexed = 10 }, // Green
        },
    };
    gauge.render(&buffer, main_chunks[0]);

    // Task list with checkboxes
    const list_block = Block{
        .title = "Task List",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 14 } },
    };

    var items_buf: [tasks.len][]const u8 = undefined;
    var item_bufs: [tasks.len][128]u8 = undefined;
    for (tasks, 0..) |task, i| {
        const checkbox = if (task.done) "[✓]" else "[ ]";
        const style_char = if (task.done) "" else "";
        items_buf[i] = try std.fmt.bufPrint(&item_bufs[i], "{s} {s}{s}", .{ checkbox, style_char, task.name });
    }

    const list = List{
        .items = &items_buf,
        .selected = 0,
        .block = list_block,
        .selected_style = Style{
            .fg = Color{ .indexed = 0 },
            .bg = Color{ .indexed = 14 },
        },
    };
    list.render(&buffer, main_chunks[1]);

    // Status bar
    const Span = sailor.tui.Span;
    var status_buf: [128]u8 = undefined;
    const status_text = try std.fmt.bufPrint(&status_buf, " {d}% Complete | {d} tasks remaining ", .{
        @as(usize, @intFromFloat(ratio * 100)),
        tasks.len - completed,
    });

    const left_spans = [_]Span{Span.raw(status_text)};
    const right_spans = [_]Span{Span.raw(" Sailor Task Manager Demo ")};

    const status_bar = StatusBar{
        .left = &left_spans,
        .right = &right_spans,
        .style = Style{
            .fg = Color{ .indexed = 0 },
            .bg = Color{ .indexed = 12 },
        },
    };
    status_bar.render(&buffer, main_chunks[2]);

    // Render
    var previous = try Buffer.init(allocator, width, height);
    defer previous.deinit();

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    const writer = output_buf.writer(allocator);

    const diff_ops = try sailor.tui.buffer.diff(allocator, previous, buffer);
    defer allocator.free(diff_ops);
    try sailor.tui.buffer.renderDiff(diff_ops, writer);

    _ = try std.posix.write(std.posix.STDOUT_FILENO, output_buf.items);
}
