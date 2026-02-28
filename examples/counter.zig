const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Gauge = sailor.tui.widgets.Gauge;
const StatusBar = sailor.tui.widgets.StatusBar;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Line = sailor.tui.Line;
const Span = sailor.tui.Span;
const layout = sailor.tui.layout;
const Constraint = sailor.tui.Constraint;

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

    // Layout
    const chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .length = 3 },
            .{ .min = 1 },
            .{ .length = 1 },
        },
    );
    defer allocator.free(chunks);

    // Title
    const title_block = Block{
        .title = "Counter Example",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 13 } },
    };
    title_block.render(&buffer, chunks[0]);

    // Content
    const content_chunks = try layout.split(
        allocator,
        .vertical,
        chunks[1],
        &[_]Constraint{
            .{ .percentage = 40 },
            .{ .length = 5 },
            .{ .percentage = 40 },
        },
    );
    defer allocator.free(content_chunks);

    // Counter display
    const counter_spans = [_]Span{Span.styled("42 / 100", .{
        .fg = Color{ .indexed = 10 },
        .bold = true,
    })};
    var counter_lines = [_]Line{
        Line{ .spans = &counter_spans },
    };

    const counter_para = Paragraph{
        .block = Block{
            .title = "Current Value",
            .borders = .all,
        },
        .lines = &counter_lines,
        .alignment = .center,
    };
    counter_para.render(&buffer, content_chunks[0]);

    // Gauge
    const gauge = Gauge{
        .block = Block{
            .title = "Progress",
            .borders = .all,
        },
        .ratio = 42.0 / 100.0,
        .filled_style = Style{ .fg = Color{ .indexed = 11 } },
    };
    gauge.render(&buffer, content_chunks[1]);

    // Instructions
    const instr1_spans = [_]Span{Span.styled("Keys:", .{ .bold = true })};
    const instr2_spans = [_]Span{Span.raw("  +/-  : Increment/Decrement")};
    const instr3_spans = [_]Span{Span.raw("  r    : Reset to 0")};
    const instr4_spans = [_]Span{Span.raw("  m    : Set to maximum")};

    var instr_lines = [_]Line{
        Line{ .spans = &instr1_spans },
        Line{ .spans = &instr2_spans },
        Line{ .spans = &instr3_spans },
        Line{ .spans = &instr4_spans },
    };

    const instr_para = Paragraph{
        .block = Block{
            .title = "Instructions",
            .borders = .all,
        },
        .lines = &instr_lines,
    };
    instr_para.render(&buffer, content_chunks[2]);

    // Status bar
    const status_bar = StatusBar{
        .left = " Counter Demo | Step: 1 | Progress: 42% ",
        .normal_style = Style{
            .fg = Color{ .indexed = 0 },
            .bg = Color{ .indexed = 12 },
        },
    };
    status_bar.render(&buffer, chunks[2]);

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
