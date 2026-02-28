const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Line = sailor.tui.Line;
const Span = sailor.tui.Span;

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

    // Create a centered block
    const block_width = 50;
    const block_height = 5;
    const x = (width -| block_width) / 2;
    const y = (height -| block_height) / 2;

    const centered = Rect{
        .x = x,
        .y = y,
        .width = block_width,
        .height = block_height,
    };

    // Create a styled block
    const block = Block{
        .title = "Hello, Sailor!",
        .borders = .all,
        .border_style = Style{
            .fg = Color{ .indexed = 12 }, // Bright blue
        },
    };

    // Create content with styled text
    const line1_spans = [_]Span{
        Span.styled("Welcome to ", .{}),
        Span.styled("Sailor", .{ .fg = Color{ .indexed = 14 } }), // Bright cyan
        Span.styled(" TUI Framework!", .{}),
    };
    const line2_spans = [_]Span{Span.raw("")};
    const line3_spans = [_]Span{Span.styled("A comprehensive TUI library for Zig", .{ .fg = Color{ .indexed = 8 } })};

    var lines = [_]Line{
        Line{ .spans = &line1_spans },
        Line{ .spans = &line2_spans },
        Line{ .spans = &line3_spans },
    };

    const paragraph = Paragraph{
        .block = block,
        .lines = &lines,
    };

    // Render to buffer
    paragraph.render(&buffer, centered);

    // Create empty previous buffer for diff
    var previous = try Buffer.init(allocator, width, height);
    defer previous.deinit();

    // Compute diff and render to stdout
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    const writer = output_buf.writer(allocator);

    const diff_ops = try sailor.tui.buffer.diff(allocator, previous, buffer);
    defer allocator.free(diff_ops);
    try sailor.tui.buffer.renderDiff(diff_ops, writer);

    // Write to stdout using posix
    _ = try std.posix.write(std.posix.STDOUT_FILENO, output_buf.items);
}
