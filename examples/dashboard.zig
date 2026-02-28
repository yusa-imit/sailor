const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Gauge = sailor.tui.widgets.Gauge;
const Sparkline = sailor.tui.widgets.Sparkline;
const StatusBar = sailor.tui.widgets.StatusBar;
const Tabs = sailor.tui.widgets.Tabs;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Span = sailor.tui.Span;
const Constraint = sailor.tui.Constraint;
const layout = sailor.tui.layout;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 100);
    const height = @min(term_size.rows, 30);

    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect.new(0, 0, width, height);

    // Main layout
    const main_chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .length = 3 }, // Title
            .{ .length = 3 }, // Tabs
            .{ .min = 1 }, // Content
            .{ .length = 1 }, // Status
        },
    );
    defer allocator.free(main_chunks);

    // Title
    const title_block = Block{
        .title = "Sailor Dashboard - Multi-Widget Demo",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 14 } },
    };
    title_block.render(&buffer, main_chunks[0]);

    // Tabs
    const tab_names = [_][]const u8{ "Overview", "Processes", "Network" };
    const tabs = Tabs{
        .titles = &tab_names,
        .selected = 0,
        .block = Block{
            .borders = .all,
        },
        .normal_style = Style{ .fg = Color{ .indexed = 7 } },
        .selected_style = Style{
            .fg = Color{ .indexed = 0 },
            .bg = Color{ .indexed = 11 },
            .bold = true,
        },
    };
    tabs.render(&buffer, main_chunks[1]);

    // Content - simple gauges
    const content_chunks = try layout.split(
        allocator,
        .vertical,
        main_chunks[2],
        &[_]Constraint{
            .{ .percentage = 25 },
            .{ .percentage = 25 },
            .{ .percentage = 25 },
            .{ .percentage = 25 },
        },
    );
    defer allocator.free(content_chunks);

    // CPU Gauge
    const cpu_gauge = Gauge{
        .block = Block{
            .title = "CPU Usage",
            .borders = .all,
        },
        .ratio = 45.0 / 100.0,
        .filled_style = Style{ .fg = Color{ .indexed = 10 } },
    };
    cpu_gauge.render(&buffer, content_chunks[0]);

    // Memory Gauge
    const mem_gauge = Gauge{
        .block = Block{
            .title = "Memory Usage",
            .borders = .all,
        },
        .ratio = 62.0 / 100.0,
        .filled_style = Style{ .fg = Color{ .indexed = 11 } },
    };
    mem_gauge.render(&buffer, content_chunks[1]);

    // Disk Gauge
    const disk_gauge = Gauge{
        .block = Block{
            .title = "Disk Usage",
            .borders = .all,
        },
        .ratio = 78.0 / 100.0,
        .filled_style = Style{ .fg = Color{ .indexed = 12 } },
    };
    disk_gauge.render(&buffer, content_chunks[2]);

    // CPU Sparkline
    const cpu_data = [_]u64{ 30, 35, 40, 38, 42, 45, 48, 50, 47, 45, 43, 45, 48, 52, 50, 48, 45, 43, 42, 40 };
    const cpu_sparkline = Sparkline{
        .block = Block{
            .title = "CPU History",
            .borders = .all,
        },
        .data = &cpu_data,
        .style = Style{ .fg = Color{ .indexed = 10 } },
    };
    cpu_sparkline.render(&buffer, content_chunks[3]);

    // Status bar
    const status_spans = [_]Span{Span.raw(" Sailor Dashboard | Tab 1/3: Overview | Demonstrating multiple widgets ")};
    const status_bar = StatusBar{
        .left = &status_spans,
        .style = Style{
            .fg = Color{ .indexed = 15 },
            .bg = Color{ .indexed = 8 },
        },
    };
    status_bar.render(&buffer, main_chunks[3]);

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
