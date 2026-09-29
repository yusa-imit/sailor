//! Hello World Example - Basic Sailor TUI Demo
//!
//! Demonstrates:
//! - Buffer initialization
//! - Layout system (vertical splits)
//! - Block and Paragraph widgets
//! - Styled text and borders
//!
//! Run with: zig build example-hello

const std = @import("std");
const sailor = @import("sailor");
const support = @import("support.zig");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const layout = sailor.tui.layout;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Get terminal size
    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 24);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = width, .height = height };

    // Create layout
    const chunks = try layout.split(allocator, .vertical, area, &.{
        .{ .length = 3 },
        .{ .min = 8 },
        .{ .length = 5 },
    });
    defer allocator.free(chunks);

    // Title block
    const title_style = Style{
        .fg = Color{ .indexed = 14 }, // Cyan
        .bold = true,
    };

    var title_block = Block{
        .title = "Welcome to Sailor TUI",
        .borders = .all,
        .border_style = title_style,
    };
    title_block.render(&buffer, chunks[0]);

    // Content paragraph
    const content =
        \\Sailor is a Zig TUI framework and CLI toolkit
        \\providing everything you need to build modern
        \\terminal applications.
        \\
        \\This example demonstrates:
        \\  • Buffer initialization and rendering
        \\  • Layout system with vertical splits
        \\  • Styled text and borders
        \\  • Widget rendering
    ;

    var content_block = Block{
        .title = "About",
        .borders = .all,
    };
    content_block.render(&buffer, chunks[1]);

    const content_area = content_block.inner(chunks[1]);
    support.renderText(&buffer, content_area, content, .left, .{});

    // Footer
    const footer_style = Style{
        .fg = Color{ .indexed = 10 }, // Green
    };

    var footer_block = Block{
        .title = "Get Started",
        .borders = .all,
        .border_style = footer_style,
    };
    footer_block.render(&buffer, chunks[2]);

    const footer_area = footer_block.inner(chunks[2]);
    const footer_text = "Build with: zig build example-hello\n" ++
        "View more examples: zig build example-counter";
    support.renderText(&buffer, footer_area, footer_text, .center, .{});

    // Render buffer to stdout
    var out_buf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(io, &out_buf);
    const stdout = &fw.interface;
    try support.renderBuffer(allocator, buffer, stdout);
    try stdout.flush();

    std.debug.print("\n✓ Sailor TUI rendering complete!\n", .{});
}
