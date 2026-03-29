const std = @import("std");
const sailor = @import("sailor");

const tui = sailor.tui;
const color = sailor.color;

const Stats = struct {
    cpu: f32 = 45.3,
    memory: f32 = 62.1,
    disk: f32 = 78.9,
    network_rx: u64 = 1024 * 512,
    network_tx: u64 = 1024 * 256,
    uptime_seconds: u64 = 0,

    pub fn update(self: *Stats) void {
        // Simulate changing stats
        self.cpu = @mod(self.cpu + 2.5, 100.0);
        self.memory = @mod(self.memory + 1.2, 100.0);
        self.disk = @mod(self.disk + 0.5, 100.0);
        self.network_rx += 1024 * 10;
        self.network_tx += 1024 * 5;
        self.uptime_seconds += 1;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = Stats{};

    var terminal = try tui.Terminal.init(allocator);
    defer terminal.deinit();

    try terminal.enterAlternateScreen();
    defer terminal.leaveAlternateScreen() catch {};

    try terminal.enableRawMode();
    defer terminal.disableRawMode() catch {};

    var should_quit = false;
    var tick_count: u32 = 0;

    while (!should_quit) {
        // Update stats every 10 ticks (1 second)
        if (tick_count % 10 == 0) {
            stats.update();
        }
        tick_count += 1;

        const stats_const = stats;
        try terminal.draw(struct {
            stats: Stats,

            fn draw(ctx: @This(), frame: *tui.Frame) !void {
                const area = frame.size();

                // Main layout: header + content
                const main_chunks = tui.layout.split(.vertical, &.{
                    .{ .length = 3 },
                    .{ .min = 10 },
                }, area);

                // Header
                const header_style = color.Style{
                    .fg = color.Color{ .indexed = 14 },
                    .bold = true,
                };
                var header_block = tui.widgets.Block{
                    .title = "System Dashboard",
                    .borders = .all,
                    .border_style = header_style,
                };
                header_block.render(frame.buffer, main_chunks[0]);

                // Content: left column (gauges) + right column (info)
                const content_chunks = tui.layout.split(.horizontal, &.{
                    .{ .percentage = 50 },
                    .{ .percentage = 50 },
                }, main_chunks[1]);

                // Left column: metrics
                const metric_chunks = tui.layout.split(.vertical, &.{
                    .{ .length = 3 },
                    .{ .length = 3 },
                    .{ .length = 3 },
                    .{ .min = 3 },
                }, content_chunks[0]);

                // CPU Gauge
                var cpu_gauge = tui.widgets.Gauge{
                    .percent = @intFromFloat(ctx.stats.cpu),
                    .label = "CPU",
                    .style = color.Style{
                        .fg = if (ctx.stats.cpu > 80) color.Color{ .indexed = 9 } else if (ctx.stats.cpu > 50) color.Color{ .indexed = 11 } else color.Color{ .indexed = 10 },
                    },
                };
                cpu_gauge.render(frame.buffer, metric_chunks[0]);

                // Memory Gauge
                var memory_gauge = tui.widgets.Gauge{
                    .percent = @intFromFloat(ctx.stats.memory),
                    .label = "Memory",
                    .style = color.Style{
                        .fg = if (ctx.stats.memory > 80) color.Color{ .indexed = 9 } else if (ctx.stats.memory > 50) color.Color{ .indexed = 11 } else color.Color{ .indexed = 10 },
                    },
                };
                memory_gauge.render(frame.buffer, metric_chunks[1]);

                // Disk Gauge
                var disk_gauge = tui.widgets.Gauge{
                    .percent = @intFromFloat(ctx.stats.disk),
                    .label = "Disk",
                    .style = color.Style{
                        .fg = if (ctx.stats.disk > 80) color.Color{ .indexed = 9 } else if (ctx.stats.disk > 50) color.Color{ .indexed = 11 } else color.Color{ .indexed = 10 },
                    },
                };
                disk_gauge.render(frame.buffer, metric_chunks[2]);

                // Network info
                var network_block = tui.widgets.Block{
                    .title = "Network",
                    .borders = .all,
                };
                network_block.render(frame.buffer, metric_chunks[3]);

                const network_area = network_block.innerArea(metric_chunks[3]);
                var network_buf: [256]u8 = undefined;
                const network_text = try std.fmt.bufPrint(&network_buf, "RX: {d} KB\nTX: {d} KB", .{ ctx.stats.network_rx / 1024, ctx.stats.network_tx / 1024 });
                var network_para = tui.widgets.Paragraph{
                    .text = network_text,
                    .alignment = .left,
                };
                network_para.render(frame.buffer, network_area);

                // Right column: system info
                var info_block = tui.widgets.Block{
                    .title = "System Information",
                    .borders = .all,
                };
                info_block.render(frame.buffer, content_chunks[1]);

                const info_area = info_block.innerArea(content_chunks[1]);
                const hours = ctx.stats.uptime_seconds / 3600;
                const minutes = (ctx.stats.uptime_seconds % 3600) / 60;
                const seconds = ctx.stats.uptime_seconds % 60;

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
                    \\Press 'q' to quit
                    \\Press 'r' to reset stats
                , .{ hours, minutes, seconds });

                var info_para = tui.widgets.Paragraph{
                    .text = info_text,
                    .alignment = .left,
                };
                info_para.render(frame.buffer, info_area);
            }
        }{ .stats = stats_const }.draw);

        const event = try terminal.pollEvent(100);
        if (event) |ev| {
            switch (ev) {
                .key => |key| {
                    if (key.code == .char) {
                        switch (key.char) {
                            'q' => should_quit = true,
                            'r' => stats = Stats{},
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }
    }
}
