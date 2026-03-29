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

    const area = Rect.new(0, 0, width, height);

    // Main layout: header + content
    const main_chunks = layout.split(.vertical, &.{
        .{ .length = 3 },
        .{ .min = 10 },
    }, area);

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
    const content_rows = layout.split(.vertical, &.{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    }, main_chunks[1]);

    // Top row: horizontal split (60/40)
    const top_cols = layout.split(.horizontal, &.{
        .{ .percentage = 60 },
        .{ .percentage = 40 },
    }, content_rows[0]);

    var block1 = Block{
        .title = "Main Panel (60% width, 50% height)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 10 } },
    };
    block1.render(&buffer, top_cols[0]);

    const area1 = block1.innerArea(top_cols[0]);
    const text1 = "This panel uses:\n  • percentage = 60 (width)\n  • percentage = 50 (height)";
    var para1 = Paragraph{
        .text = text1,
        .alignment = .left,
    };
    para1.render(&buffer, area1);

    var block2 = Block{
        .title = "Sidebar (40% width, 50% height)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 11 } },
    };
    block2.render(&buffer, top_cols[1]);

    const area2 = block2.innerArea(top_cols[1]);
    const text2 = "Sidebar with:\n  • percentage = 40\n  • percentage = 50";
    var para2 = Paragraph{
        .text = text2,
        .alignment = .left,
    };
    para2.render(&buffer, area2);

    // Bottom row: three equal columns (33/34/33)
    const bottom_cols = layout.split(.horizontal, &.{
        .{ .percentage = 33 },
        .{ .percentage = 34 },
        .{ .percentage = 33 },
    }, content_rows[1]);

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

    const area4 = block4.innerArea(bottom_cols[1]);
    const text4 =
        \\Layout constraints:
        \\
        \\  • percentage - % of space
        \\  • length - fixed size
        \\  • min - minimum size
        \\  • max - maximum size
    ;
    var para4 = Paragraph{
        .text = text4,
        .alignment = .left,
    };
    para4.render(&buffer, area4);

    var block5 = Block{
        .title = "Footer 3 (33%)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 9 } },
    };
    block5.render(&buffer, bottom_cols[2]);

    // Render
    const stdout = std.io.getStdOut().writer();
    try buffer.renderTo(stdout);

    std.debug.print("\n✓ Layout showcase rendered successfully!\n", .{});
}
