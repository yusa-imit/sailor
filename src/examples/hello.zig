const std = @import("std");
const sailor = @import("sailor");

const tui = sailor.tui;
const color = sailor.color;
const term = sailor.term;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var terminal = try tui.Terminal.init(allocator);
    defer terminal.deinit();

    // Enter alternate screen
    try terminal.enterAlternateScreen();
    defer terminal.leaveAlternateScreen() catch {};

    // Enable raw mode for input handling
    try terminal.enableRawMode();
    defer terminal.disableRawMode() catch {};

    // Main application loop
    var should_quit = false;
    while (!should_quit) {
        // Draw the UI
        try terminal.draw(struct {
            fn draw(frame: *tui.Frame) !void {
                const area = frame.size();

                // Create a centered layout
                const chunks = tui.layout.split(.vertical, &.{
                    .{ .percentage = 40 },
                    .{ .length = 3 },
                    .{ .percentage = 60 },
                }, area);

                // Title block
                const title_style = color.Style{
                    .fg = color.Color{ .indexed = 14 }, // Cyan
                    .bold = true,
                };

                var title_block = tui.widgets.Block{
                    .title = "Welcome to Sailor TUI",
                    .borders = .all,
                    .border_style = title_style,
                };
                title_block.render(frame.buffer, chunks[0]);

                // Content paragraph
                const content =
                    \\This is a simple example demonstrating:
                    \\  • Terminal initialization and raw mode
                    \\  • Layout system with vertical splits
                    \\  • Styled text and borders
                    \\  • Event handling (press 'q' to quit)
                    \\
                    \\Sailor is a Zig TUI framework and CLI toolkit
                    \\providing everything you need to build modern
                    \\terminal applications.
                ;

                var content_para = tui.widgets.Paragraph{
                    .text = content,
                    .alignment = .left,
                    .wrap = true,
                };
                content_para.render(frame.buffer, chunks[1]);

                // Footer with instructions
                const footer_style = color.Style{
                    .fg = color.Color{ .indexed = 10 }, // Green
                };

                var footer_block = tui.widgets.Block{
                    .title = "Controls",
                    .borders = .all,
                    .border_style = footer_style,
                };
                footer_block.render(frame.buffer, chunks[2]);

                // Footer content
                const footer_area = footer_block.innerArea(chunks[2]);
                const footer_text = "Press 'q' to quit | Press 'h' for help";
                var footer_para = tui.widgets.Paragraph{
                    .text = footer_text,
                    .alignment = .center,
                };
                footer_para.render(frame.buffer, footer_area);
            }
        }.draw);

        // Poll for events
        const event = try terminal.pollEvent(100);
        if (event) |ev| {
            switch (ev) {
                .key => |key| {
                    if (key.code == .char and key.char == 'q') {
                        should_quit = true;
                    }
                },
                else => {},
            }
        }
    }
}
