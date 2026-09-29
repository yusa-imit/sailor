//! Dashboard Example - Multiple Widgets Demo
//!
//! Demonstrates:
//! - Complex layouts (nested splits)
//! - Gauge widgets for metrics
//! - Multiple simultaneous widgets
//! - Real-world dashboard patterns
//!
//! Run with: zig build example-dashboard

const std = @import("std");
const sailor = @import("sailor");
const support = @import("support.zig");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Gauge = sailor.tui.widgets.Gauge;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const layout = sailor.tui.layout;

const Stats = struct {
    cpu: f32 = 45.3,
    memory: f32 = 62.1,
    disk: f32 = 78.9,
    network_rx: u64 = 1024 * 512,
    network_tx: u64 = 1024 * 256,
    uptime_seconds: u64 = 3665, // 1h 1m 5s
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const stats = Stats{};

    // Get terminal size
    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 24);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = width, .height = height };

    // Main layout
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
        .title = "System Dashboard",
        .borders = .all,
        .border_style = header_style,
    };
    header_block.render(&buffer, main_chunks[0]);

    // Content: metrics (left) + info (right)
    const content_chunks = try layout.split(allocator, .horizontal, main_chunks[1], &.{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    });
    defer allocator.free(content_chunks);

    // Left: metrics
    const metric_chunks = try layout.split(allocator, .vertical, content_chunks[0], &.{
        .{ .length = 3 },
        .{ .length = 3 },
        .{ .length = 3 },
        .{ .min = 3 },
    });
    defer allocator.free(metric_chunks);

    // CPU Gauge
    var cpu_gauge = Gauge{
        .ratio = stats.cpu / 100.0,
        .label = "CPU",
        .filled_style = Style{
            .fg = if (stats.cpu > 80) Color{ .indexed = 9 } else if (stats.cpu > 50) Color{ .indexed = 11 } else Color{ .indexed = 10 },
        },
    };
    cpu_gauge.render(&buffer, metric_chunks[0]);

    // Memory Gauge
    var memory_gauge = Gauge{
        .ratio = stats.memory / 100.0,
        .label = "Memory",
        .filled_style = Style{
            .fg = if (stats.memory > 80) Color{ .indexed = 9 } else if (stats.memory > 50) Color{ .indexed = 11 } else Color{ .indexed = 10 },
        },
    };
    memory_gauge.render(&buffer, metric_chunks[1]);

    // Disk Gauge
    var disk_gauge = Gauge{
        .ratio = stats.disk / 100.0,
        .label = "Disk",
        .filled_style = Style{
            .fg = if (stats.disk > 80) Color{ .indexed = 9 } else if (stats.disk > 50) Color{ .indexed = 11 } else Color{ .indexed = 10 },
        },
    };
    disk_gauge.render(&buffer, metric_chunks[2]);

    // Network info
    var network_block = Block{
        .title = "Network",
        .borders = .all,
    };
    network_block.render(&buffer, metric_chunks[3]);

    const network_area = network_block.inner(metric_chunks[3]);
    var network_buf: [256]u8 = undefined;
    const network_text = try std.fmt.bufPrint(&network_buf, "RX: {d} KB\nTX: {d} KB", .{
        stats.network_rx / 1024,
        stats.network_tx / 1024,
    });
    support.renderText(&buffer, network_area, network_text, .left, .{});

    // Right: system info
    var info_block = Block{
        .title = "System Information",
        .borders = .all,
    };
    info_block.render(&buffer, content_chunks[1]);

    const info_area = info_block.inner(content_chunks[1]);
    const hours = stats.uptime_seconds / 3600;
    const minutes = (stats.uptime_seconds % 3600) / 60;
    const seconds = stats.uptime_seconds % 60;

    var info_buf: [512]u8 = undefined;
    const info_text = try std.fmt.bufPrint(&info_buf,
        \\Hostname: localhost
        \\OS: Zig OS
        \\Kernel: 5.15.0
        \\Uptime: {d}h {d}m {d}s
        \\
        \\Processes: 245
        \\Load Avg: 1.23, 0.98, 0.76
        \\
        \\This example demonstrates:
        \\  • Nested layouts
        \\  • Gauge widgets
        \\  • Conditional coloring
        \\  • Multiple widget types
    , .{ hours, minutes, seconds });

    support.renderText(&buffer, info_area, info_text, .left, .{});

    // Render
    var out_buf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(io, &out_buf);
    const stdout = &fw.interface;
    try support.renderBuffer(allocator, buffer, stdout);
    try stdout.flush();

    std.debug.print("\n✓ Dashboard rendered successfully!\n", .{});
}
