//! Counter Example - State Management Demo
//!
//! Demonstrates:
//! - Application state management
//! - Dynamic content rendering
//! - List widget for history
//! - Conditional styling
//!
//! Run with: zig build example-counter

const std = @import("std");
const sailor = @import("sailor");
const support = @import("support.zig");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const layout = sailor.tui.layout;

const App = struct {
    counter: i32 = 42,
    step: i32 = 5,
    history: [5]i32 = [_]i32{ 10, 20, 30, 35, 42 },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const app = App{};

    // Get terminal size
    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 24);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = width, .height = height };

    // Layout
    const chunks = try layout.split(allocator, .vertical, area, &.{
        .{ .length = 3 },
        .{ .length = 5 },
        .{ .min = 5 },
        .{ .length = 8 },
    });
    defer allocator.free(chunks);

    // Title
    const title_style = Style{
        .fg = Color{ .indexed = 14 },
        .bold = true,
    };
    var title_block = Block{
        .title = "Counter Application",
        .borders = .all,
        .border_style = title_style,
    };
    title_block.render(&buffer, chunks[0]);

    // Counter display
    const counter_style = Style{
        .fg = if (app.counter >= 0) Color{ .indexed = 10 } else Color{ .indexed = 9 },
        .bold = true,
    };
    var counter_block = Block{
        .title = "Current Value",
        .borders = .all,
        .border_style = counter_style,
    };
    counter_block.render(&buffer, chunks[1]);

    const counter_area = counter_block.inner(chunks[1]);
    var counter_buf: [64]u8 = undefined;
    const counter_text = try std.fmt.bufPrint(&counter_buf, "Value: {d} (step: {d})\nStatus: {s}", .{
        app.counter,
        app.step,
        if (app.counter >= 0) "Positive" else "Negative",
    });
    support.renderText(&buffer, counter_area, counter_text, .center, counter_style);

    // History
    var history_block = Block{
        .title = "History (last 5 values)",
        .borders = .all,
    };
    history_block.render(&buffer, chunks[2]);

    const history_area = history_block.inner(chunks[2]);
    var items_buf: [5][32]u8 = undefined;
    var items: [5][]const u8 = undefined;
    for (app.history, 0..) |val, i| {
        items[i] = try std.fmt.bufPrint(&items_buf[i], "  {d}", .{val});
    }
    var history_list = List{
        .items = &items,
    };
    history_list.render(&buffer, history_area);

    // Instructions
    var inst_block = Block{
        .title = "About This Example",
        .borders = .all,
    };
    inst_block.render(&buffer, chunks[3]);

    const inst_area = inst_block.inner(chunks[3]);
    const inst_text =
        \\This example shows state management patterns:
        \\
        \\  • App struct holding application state
        \\  • Conditional styling (green/red based on value)
        \\  • History tracking with List widget
        \\  • Dynamic text formatting with bufPrint
    ;
    support.renderText(&buffer, inst_area, inst_text, .left, .{});

    // Render
    var out_buf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(io, &out_buf);
    const stdout = &fw.interface;
    try support.renderBuffer(allocator, buffer, stdout);
    try stdout.flush();

    std.debug.print("\n✓ Counter state rendered successfully!\n", .{});
}
