const std = @import("std");
const sailor = @import("sailor");

const tui = sailor.tui;
const color = sailor.color;

const App = struct {
    counter: i32 = 0,
    step: i32 = 1,
    history: std.ArrayList(i32),

    pub fn init(allocator: std.mem.Allocator) !App {
        return App{
            .history = std.ArrayList(i32).init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.history.deinit();
    }

    pub fn increment(self: *App) !void {
        self.counter += self.step;
        try self.history.append(self.counter);
    }

    pub fn decrement(self: *App) !void {
        self.counter -= self.step;
        try self.history.append(self.counter);
    }

    pub fn reset(self: *App) !void {
        self.counter = 0;
        try self.history.append(self.counter);
    }

    pub fn setStep(self: *App, step: i32) void {
        self.step = step;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize application state
    var app = try App.init(allocator);
    defer app.deinit();

    // Initialize terminal
    var terminal = try tui.Terminal.init(allocator);
    defer terminal.deinit();

    try terminal.enterAlternateScreen();
    defer terminal.leaveAlternateScreen() catch {};

    try terminal.enableRawMode();
    defer terminal.disableRawMode() catch {};

    var should_quit = false;
    while (!should_quit) {
        // Draw UI
        const app_const = app; // Capture app for closure
        try terminal.draw(struct {
            app: App,

            fn draw(ctx: @This(), frame: *tui.Frame) !void {
                const area = frame.size();

                // Split into sections
                const main_chunks = tui.layout.split(.vertical, &.{
                    .{ .length = 5 },
                    .{ .min = 3 },
                    .{ .length = 7 },
                }, area);

                // Counter display
                const counter_style = color.Style{
                    .fg = if (ctx.app.counter >= 0) color.Color{ .indexed = 10 } else color.Color{ .indexed = 9 },
                    .bold = true,
                };

                var counter_block = tui.widgets.Block{
                    .title = "Counter",
                    .borders = .all,
                    .border_style = counter_style,
                };
                counter_block.render(frame.buffer, main_chunks[0]);

                const counter_area = counter_block.innerArea(main_chunks[0]);
                var counter_buf: [32]u8 = undefined;
                const counter_text = try std.fmt.bufPrint(&counter_buf, "Value: {d} (step: {d})", .{ ctx.app.counter, ctx.app.step });
                var counter_para = tui.widgets.Paragraph{
                    .text = counter_text,
                    .alignment = .center,
                    .style = counter_style,
                };
                counter_para.render(frame.buffer, counter_area);

                // History
                var history_block = tui.widgets.Block{
                    .title = "History",
                    .borders = .all,
                };
                history_block.render(frame.buffer, main_chunks[1]);

                const history_area = history_block.innerArea(main_chunks[1]);
                var items = std.ArrayList([]const u8).init(std.heap.page_allocator);
                defer items.deinit();

                const start = if (ctx.app.history.items.len > 10) ctx.app.history.items.len - 10 else 0;
                for (ctx.app.history.items[start..]) |val| {
                    var buf: [32]u8 = undefined;
                    const item = try std.fmt.bufPrint(&buf, "  {d}", .{val});
                    try items.append(item);
                }

                var history_list = tui.widgets.List{
                    .items = items.items,
                };
                history_list.render(frame.buffer, history_area);

                // Controls
                var controls_block = tui.widgets.Block{
                    .title = "Controls",
                    .borders = .all,
                };
                controls_block.render(frame.buffer, main_chunks[2]);

                const controls_area = controls_block.innerArea(main_chunks[2]);
                const controls_text =
                    \\↑/k    Increment
                    \\↓/j    Decrement
                    \\r      Reset to 0
                    \\1-9    Set step size
                    \\q      Quit
                ;
                var controls_para = tui.widgets.Paragraph{
                    .text = controls_text,
                    .alignment = .left,
                };
                controls_para.render(frame.buffer, controls_area);
            }
        }{ .app = app_const }.draw);

        // Handle input
        const event = try terminal.pollEvent(100);
        if (event) |ev| {
            switch (ev) {
                .key => |key| {
                    switch (key.code) {
                        .char => |c| switch (c) {
                            'q' => should_quit = true,
                            'r' => try app.reset(),
                            'k' => try app.increment(),
                            'j' => try app.decrement(),
                            '1'...'9' => app.setStep(@intCast(c - '0')),
                            else => {},
                        },
                        .up => try app.increment(),
                        .down => try app.decrement(),
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
}
