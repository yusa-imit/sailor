const std = @import("std");
const sailor = @import("sailor");

const tui = sailor.tui;
const color = sailor.color;

const LayoutMode = enum {
    vertical,
    horizontal,
    mixed,
    responsive,

    pub fn next(self: LayoutMode) LayoutMode {
        return switch (self) {
            .vertical => .horizontal,
            .horizontal => .mixed,
            .mixed => .responsive,
            .responsive => .vertical,
        };
    }

    pub fn name(self: LayoutMode) []const u8 {
        return switch (self) {
            .vertical => "Vertical Split",
            .horizontal => "Horizontal Split",
            .mixed => "Mixed Layout",
            .responsive => "Responsive",
        };
    }
};

const App = struct {
    mode: LayoutMode = .vertical,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App{};

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

                // Header
                const main_chunks = tui.layout.split(.vertical, &.{
                    .{ .length = 3 },
                    .{ .min = 10 },
                    .{ .length = 5 },
                }, area);

                const title_style = color.Style{
                    .fg = color.Color{ .indexed = 14 },
                    .bold = true,
                };

                var header_buf: [128]u8 = undefined;
                const header_text = try std.fmt.bufPrint(&header_buf, "Layout Showcase - {s}", .{ctx.app.mode.name()});

                var title_block = tui.widgets.Block{
                    .title = header_text,
                    .borders = .all,
                    .border_style = title_style,
                };
                title_block.render(frame.buffer, main_chunks[0]);

                // Content area - changes based on mode
                switch (ctx.app.mode) {
                    .vertical => try drawVertical(frame, main_chunks[1]),
                    .horizontal => try drawHorizontal(frame, main_chunks[1]),
                    .mixed => try drawMixed(frame, main_chunks[1]),
                    .responsive => try drawResponsive(frame, main_chunks[1]),
                }

                // Footer
                var footer_block = tui.widgets.Block{
                    .title = "Controls",
                    .borders = .all,
                };
                footer_block.render(frame.buffer, main_chunks[2]);

                const footer_area = footer_block.innerArea(main_chunks[2]);
                const footer_text =
                    \\Tab/Space - Switch layout mode
                    \\q         - Quit
                ;
                var footer_para = tui.widgets.Paragraph{
                    .text = footer_text,
                    .alignment = .center,
                };
                footer_para.render(frame.buffer, footer_area);
            }

            fn drawVertical(frame: *tui.Frame, area: tui.Rect) !void {
                const chunks = tui.layout.split(.vertical, &.{
                    .{ .percentage = 33 },
                    .{ .percentage = 33 },
                    .{ .percentage = 34 },
                }, area);

                var block1 = tui.widgets.Block{
                    .title = "Section 1 (33%)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 9 } },
                };
                block1.render(frame.buffer, chunks[0]);

                var block2 = tui.widgets.Block{
                    .title = "Section 2 (33%)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 10 } },
                };
                block2.render(frame.buffer, chunks[1]);

                var block3 = tui.widgets.Block{
                    .title = "Section 3 (34%)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 11 } },
                };
                block3.render(frame.buffer, chunks[2]);
            }

            fn drawHorizontal(frame: *tui.Frame, area: tui.Rect) !void {
                const chunks = tui.layout.split(.horizontal, &.{
                    .{ .percentage = 25 },
                    .{ .percentage = 50 },
                    .{ .percentage = 25 },
                }, area);

                var block1 = tui.widgets.Block{
                    .title = "Left (25%)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 12 } },
                };
                block1.render(frame.buffer, chunks[0]);

                var block2 = tui.widgets.Block{
                    .title = "Center (50%)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 13 } },
                };
                block2.render(frame.buffer, chunks[1]);

                var block3 = tui.widgets.Block{
                    .title = "Right (25%)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 14 } },
                };
                block3.render(frame.buffer, chunks[2]);
            }

            fn drawMixed(frame: *tui.Frame, area: tui.Rect) !void {
                const rows = tui.layout.split(.vertical, &.{
                    .{ .percentage = 50 },
                    .{ .percentage = 50 },
                }, area);

                // Top row - horizontal split
                const top_cols = tui.layout.split(.horizontal, &.{
                    .{ .percentage = 60 },
                    .{ .percentage = 40 },
                }, rows[0]);

                var block1 = tui.widgets.Block{
                    .title = "Main (60% width, 50% height)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 9 } },
                };
                block1.render(frame.buffer, top_cols[0]);

                var block2 = tui.widgets.Block{
                    .title = "Sidebar (40%, 50%)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 10 } },
                };
                block2.render(frame.buffer, top_cols[1]);

                // Bottom row - three columns
                const bottom_cols = tui.layout.split(.horizontal, &.{
                    .{ .percentage = 33 },
                    .{ .percentage = 34 },
                    .{ .percentage = 33 },
                }, rows[1]);

                var block3 = tui.widgets.Block{
                    .title = "Footer 1",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 11 } },
                };
                block3.render(frame.buffer, bottom_cols[0]);

                var block4 = tui.widgets.Block{
                    .title = "Footer 2",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 12 } },
                };
                block4.render(frame.buffer, bottom_cols[1]);

                var block5 = tui.widgets.Block{
                    .title = "Footer 3",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 13 } },
                };
                block5.render(frame.buffer, bottom_cols[2]);
            }

            fn drawResponsive(frame: *tui.Frame, area: tui.Rect) !void {
                // Use fixed lengths and min constraints
                const chunks = tui.layout.split(.vertical, &.{
                    .{ .length = 5 },
                    .{ .min = 5 },
                    .{ .length = 3 },
                }, area);

                var block1 = tui.widgets.Block{
                    .title = "Header (fixed 5 lines)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 14 } },
                };
                block1.render(frame.buffer, chunks[0]);

                var block2 = tui.widgets.Block{
                    .title = "Content (minimum 5, flexible)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 10 } },
                };
                block2.render(frame.buffer, chunks[1]);

                var block3 = tui.widgets.Block{
                    .title = "Footer (fixed 3 lines)",
                    .borders = .all,
                    .border_style = color.Style{ .fg = color.Color{ .indexed = 9 } },
                };
                block3.render(frame.buffer, chunks[2]);
            }
        }{ .app = app_const }.draw);

        const event = try terminal.pollEvent(100);
        if (event) |ev| {
            switch (ev) {
                .key => |key| {
                    switch (key.code) {
                        .char => |c| switch (c) {
                            'q' => should_quit = true,
                            ' ' => app.mode = app.mode.next(),
                            else => {},
                        },
                        .tab => app.mode = app.mode.next(),
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
}
