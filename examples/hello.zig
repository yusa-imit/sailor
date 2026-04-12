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

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const layout = sailor.tui.layout;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get terminal size
    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 24);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = width, .height = height };

    // Create layout
    const chunks = layout.split(.vertical, &.{
        .{ .length = 3 },
        .{ .min = 8 },
        .{ .length = 5 },
    }, area);

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

    const content_area = content_block.innerArea(chunks[1]);
    var content_para = Paragraph{
        .text = content,
        .alignment = .left,
    };
    content_para.render(&buffer, content_area);

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

    const footer_area = footer_block.innerArea(chunks[2]);
    const footer_text = "Build with: zig build example-hello\n" ++
        "View more examples: zig build example-counter";
    var footer_para = Paragraph{
        .text = footer_text,
        .alignment = .center,
    };
    footer_para.render(&buffer, footer_area);

    // Render buffer to stdout
    const stdout = std.io.getStdOut().writer();
    try buffer.renderTo(stdout);

    std.debug.print("\n✓ Sailor TUI rendering complete!\n", .{});
}
