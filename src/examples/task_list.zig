const std = @import("std");
const sailor = @import("sailor");

const tui = sailor.tui;
const color = sailor.color;

const Task = struct {
    title: []const u8,
    done: bool = false,
};

const App = struct {
    tasks: std.ArrayList(Task),
    selected: usize = 0,
    input_mode: bool = false,
    input_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !App {
        var tasks = std.ArrayList(Task).init(allocator);
        try tasks.append(.{ .title = "Learn Zig", .done = true });
        try tasks.append(.{ .title = "Build a TUI app with Sailor", .done = false });
        try tasks.append(.{ .title = "Read the docs", .done = false });

        return App{
            .tasks = tasks,
            .input_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.tasks.deinit();
        self.input_buffer.deinit();
    }

    pub fn toggleTask(self: *App) void {
        if (self.selected < self.tasks.items.len) {
            self.tasks.items[self.selected].done = !self.tasks.items[self.selected].done;
        }
    }

    pub fn deleteTask(self: *App) void {
        if (self.tasks.items.len > 0 and self.selected < self.tasks.items.len) {
            _ = self.tasks.orderedRemove(self.selected);
            if (self.selected >= self.tasks.items.len and self.tasks.items.len > 0) {
                self.selected = self.tasks.items.len - 1;
            }
        }
    }

    pub fn moveUp(self: *App) void {
        if (self.selected > 0) {
            self.selected -= 1;
        }
    }

    pub fn moveDown(self: *App) void {
        if (self.selected + 1 < self.tasks.items.len) {
            self.selected += 1;
        }
    }

    pub fn addTask(self: *App, allocator: std.mem.Allocator) !void {
        if (self.input_buffer.items.len > 0) {
            const title = try allocator.dupe(u8, self.input_buffer.items);
            try self.tasks.append(.{ .title = title, .done = false });
            self.input_buffer.clearRetainingCapacity();
            self.input_mode = false;
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    var terminal = try tui.Terminal.init(allocator);
    defer terminal.deinit();

    try terminal.enterAlternateScreen();
    defer terminal.leaveAlternateScreen() catch {};

    try terminal.enableRawMode();
    defer terminal.disableRawMode() catch {};

    var should_quit = false;
    while (!should_quit) {
        const app_const = app;
        try terminal.draw(struct {
            app: App,

            fn draw(ctx: @This(), frame: *tui.Frame) !void {
                const area = frame.size();

                const chunks = tui.layout.split(.vertical, &.{
                    .{ .length = 3 },
                    .{ .min = 5 },
                    .{ .length = 3 },
                    .{ .length = 6 },
                }, area);

                // Title
                const title_style = color.Style{
                    .fg = color.Color{ .indexed = 14 },
                    .bold = true,
                };
                var title_block = tui.widgets.Block{
                    .title = "Task List Manager",
                    .borders = .all,
                    .border_style = title_style,
                };
                title_block.render(frame.buffer, chunks[0]);

                // Task list
                var task_block = tui.widgets.Block{
                    .title = "Tasks",
                    .borders = .all,
                };
                task_block.render(frame.buffer, chunks[1]);

                const task_area = task_block.innerArea(chunks[1]);
                var items = std.ArrayList([]const u8).init(std.heap.page_allocator);
                defer items.deinit();

                for (ctx.app.tasks.items, 0..) |task, i| {
                    const marker = if (task.done) "[✓]" else "[ ]";
                    const prefix = if (i == ctx.app.selected) "> " else "  ";

                    var buf: [256]u8 = undefined;
                    const item = try std.fmt.bufPrint(&buf, "{s}{s} {s}", .{ prefix, marker, task.title });
                    try items.append(item);
                }

                var task_list = tui.widgets.List{
                    .items = items.items,
                };
                task_list.render(frame.buffer, task_area);

                // Input area
                const input_title = if (ctx.app.input_mode) "New Task (Enter to add, Esc to cancel)" else "New Task (Press 'a' to add)";
                var input_block = tui.widgets.Block{
                    .title = input_title,
                    .borders = .all,
                    .border_style = if (ctx.app.input_mode) color.Style{ .fg = color.Color{ .indexed = 11 } } else color.Style{},
                };
                input_block.render(frame.buffer, chunks[2]);

                if (ctx.app.input_mode) {
                    const input_area = input_block.innerArea(chunks[2]);
                    var input_widget = tui.widgets.Input{
                        .value = ctx.app.input_buffer.items,
                        .placeholder = "Enter task description...",
                        .focused = true,
                    };
                    input_widget.render(frame.buffer, input_area);
                }

                // Controls
                var controls_block = tui.widgets.Block{
                    .title = "Controls",
                    .borders = .all,
                };
                controls_block.render(frame.buffer, chunks[3]);

                const controls_area = controls_block.innerArea(chunks[3]);
                const controls_text =
                    \\↑/k    Move up        Space  Toggle done
                    \\↓/j    Move down      d      Delete task
                    \\a      Add new task   q      Quit
                ;
                var controls_para = tui.widgets.Paragraph{
                    .text = controls_text,
                    .alignment = .left,
                };
                controls_para.render(frame.buffer, controls_area);
            }
        }{ .app = app_const }.draw);

        const event = try terminal.pollEvent(100);
        if (event) |ev| {
            switch (ev) {
                .key => |key| {
                    if (app.input_mode) {
                        switch (key.code) {
                            .char => |c| try app.input_buffer.append(c),
                            .enter => try app.addTask(allocator),
                            .backspace => {
                                if (app.input_buffer.items.len > 0) {
                                    _ = app.input_buffer.pop();
                                }
                            },
                            .esc => {
                                app.input_buffer.clearRetainingCapacity();
                                app.input_mode = false;
                            },
                            else => {},
                        }
                    } else {
                        switch (key.code) {
                            .char => |c| switch (c) {
                                'q' => should_quit = true,
                                'k' => app.moveUp(),
                                'j' => app.moveDown(),
                                'a' => app.input_mode = true,
                                'd' => app.deleteTask(),
                                ' ' => app.toggleTask(),
                                else => {},
                            },
                            .up => app.moveUp(),
                            .down => app.moveDown(),
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }
    }
}
