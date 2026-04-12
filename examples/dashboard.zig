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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
        .title = "System Dashboard",
        .borders = .all,
        .border_style = header_style,
    };
    header_block.render(&buffer, main_chunks[0]);

    // Content: metrics (left) + info (right)
    const content_chunks = layout.split(.horizontal, &.{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    }, main_chunks[1]);

    // Left: metrics
    const metric_chunks = layout.split(.vertical, &.{
        .{ .length = 3 },
        .{ .length = 3 },
        .{ .length = 3 },
        .{ .min = 3 },
    }, content_chunks[0]);

    // CPU Gauge
    var cpu_gauge = Gauge{
        .percent = @intFromFloat(stats.cpu),
        .label = "CPU",
        .style = Style{
            .fg = if (stats.cpu > 80) Color{ .indexed = 9 } else if (stats.cpu > 50) Color{ .indexed = 11 } else Color{ .indexed = 10 },
        },
    };
    cpu_gauge.render(&buffer, metric_chunks[0]);

    // Memory Gauge
    var memory_gauge = Gauge{
        .percent = @intFromFloat(stats.memory),
        .label = "Memory",
        .style = Style{
            .fg = if (stats.memory > 80) Color{ .indexed = 9 } else if (stats.memory > 50) Color{ .indexed = 11 } else Color{ .indexed = 10 },
        },
    };
    memory_gauge.render(&buffer, metric_chunks[1]);

    // Disk Gauge
    var disk_gauge = Gauge{
        .percent = @intFromFloat(stats.disk),
        .label = "Disk",
        .style = Style{
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

    const network_area = network_block.innerArea(metric_chunks[3]);
    var network_buf: [256]u8 = undefined;
    const network_text = try std.fmt.bufPrint(&network_buf, "RX: {d} KB\nTX: {d} KB", .{
        stats.network_rx / 1024,
        stats.network_tx / 1024,
    });
    var network_para = Paragraph{
        .text = network_text,
        .alignment = .left,
    };
    network_para.render(&buffer, network_area);

    // Right: system info
    var info_block = Block{
        .title = "System Information",
        .borders = .all,
    };
    info_block.render(&buffer, content_chunks[1]);

    const info_area = info_block.innerArea(content_chunks[1]);
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

    var info_para = Paragraph{
        .text = info_text,
        .alignment = .left,
    };
    info_para.render(&buffer, info_area);

    // Render
    const stdout = std.io.getStdOut().writer();
    try buffer.renderTo(stdout);

    std.debug.print("\n✓ Dashboard rendered successfully!\n", .{});
}
