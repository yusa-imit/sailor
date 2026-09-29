//! Layout Showcase Example - Layout System Demo
//!
//! Demonstrates:
//! - Vertical and horizontal splits
//! - Nested layouts
//! - Percentage, length, and min constraints
//! - Complex multi-panel layouts
//!
//! Run with: zig build example-layout_showcase

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

    // Main layout: header + content
    const main_chunks = try layout.split(allocator, .vertical, area, &.{
        .{ .length = 3 },
        .{ .min = 10 },
    });
    defer allocator.free(main_chunks);

    // Header
    const header_style = Style{
        .fg = Color{ .indexed = 14 },
        .bold = true,
    };
    var header_block = Block{
        .title = "Layout Showcase - Demonstrating Split Constraints",
        .borders = .all,
        .border_style = header_style,
    };
    header_block.render(&buffer, main_chunks[0]);

    // Content: top half + bottom half
    const content_rows = try layout.split(allocator, .vertical, main_chunks[1], &.{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    });
    defer allocator.free(content_rows);

    // Top row: horizontal split (60/40)
    const top_cols = try layout.split(allocator, .horizontal, content_rows[0], &.{
        .{ .percentage = 60 },
        .{ .percentage = 40 },
    });
    defer allocator.free(top_cols);

    var block1 = Block{
        .title = "Main Panel (60% width, 50% height)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 10 } },
    };
    block1.render(&buffer, top_cols[0]);

    const area1 = block1.inner(top_cols[0]);
    const text1 = "This panel uses:\n  • percentage = 60 (width)\n  • percentage = 50 (height)";
    support.renderText(&buffer, area1, text1, .left, .{});

    var block2 = Block{
        .title = "Sidebar (40% width, 50% height)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 11 } },
    };
    block2.render(&buffer, top_cols[1]);

    const area2 = block2.inner(top_cols[1]);
    const text2 = "Sidebar with:\n  • percentage = 40\n  • percentage = 50";
    support.renderText(&buffer, area2, text2, .left, .{});

    // Bottom row: three equal columns (33/34/33)
    const bottom_cols = try layout.split(allocator, .horizontal, content_rows[1], &.{
        .{ .percentage = 33 },
        .{ .percentage = 34 },
        .{ .percentage = 33 },
    });
    defer allocator.free(bottom_cols);

    var block3 = Block{
        .title = "Footer 1 (33%)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 12 } },
    };
    block3.render(&buffer, bottom_cols[0]);

    var block4 = Block{
        .title = "Footer 2 (34%)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 13 } },
    };
    block4.render(&buffer, bottom_cols[1]);

    const area4 = block4.inner(bottom_cols[1]);
    const text4 =
        \\Layout constraints:
        \\
        \\  • percentage - % of space
        \\  • length - fixed size
        \\  • min - minimum size
        \\  • max - maximum size
    ;
    support.renderText(&buffer, area4, text4, .left, .{});

    var block5 = Block{
        .title = "Footer 3 (33%)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 9 } },
    };
    block5.render(&buffer, bottom_cols[2]);

    // Render
    var out_buf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(io, &out_buf);
    const stdout = &fw.interface;
    try support.renderBuffer(allocator, buffer, stdout);
    try stdout.flush();

    std.debug.print("\n✓ Layout showcase rendered successfully!\n", .{});
}
