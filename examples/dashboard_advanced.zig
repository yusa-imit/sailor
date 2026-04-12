//! Advanced Dashboard Example - v1.32.0 Features Showcase
//!
//! Demonstrates v1.32.0 Advanced Layout Features:
//! - Nested grid layouts (grid-within-grid)
//! - Aspect ratio constraints (video preview, charts)
//! - Min/max size propagation (responsive panels)
//! - Auto-margin/padding (smart spacing)
//! - Layout debugging (visual tree inspection)
//!
//! This example shows a complex multi-panel dashboard with:
//! - Video preview panel (16:9 aspect ratio)
//! - Performance charts (4:3 aspect ratio)
//! - Metrics sidebar (min width constraint)
//! - Status bar (fixed height)
//! - Nested content grids with margins
//!
//! Run with: zig build example-dashboard-advanced

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
const Margin = layout.Margin;
const Padding = layout.Padding;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get terminal size
    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 120);
    const height = @min(term_size.rows, 40);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = width, .height = height };

    // ======================
    // LEVEL 1: Main Layout
    // ======================
    // Header (3 lines) + Content + Footer (1 line)
    const main_constraints = [_]layout.Constraint{
        .{ .length = 3 },   // Header
        .{ .min = 20 },     // Content (min height constraint)
        .{ .length = 1 },   // Footer
    };
    const main_chunks = try layout.split(allocator, .vertical, area, &main_constraints);
    defer allocator.free(main_chunks);

    // Header
    const header_style = Style{ .fg = Color{ .indexed = 14 }, .bold = true };
    var header_block = Block{
        .title = "Advanced Dashboard - v1.32.0 Features",
        .borders = .all,
        .border_style = header_style,
    };
    header_block.render(&buffer, main_chunks[0]);

    // Footer
    const footer_area = main_chunks[2];
    buffer.setString(footer_area.x, footer_area.y, "Press 'q' to quit | Layout: nested grids + aspect ratios + margins + min/max constraints", Style{});

    // ======================
    // LEVEL 2: Content Layout
    // ======================
    // Left sidebar (min 30 cols) + Main content
    const content_margin = Margin.all(1);  // 1-cell margin around content
    const content_area = main_chunks[1].withMargin(content_margin);

    const content_constraints = [_]layout.Constraint{
        .{ .min = 30 },     // Sidebar (min width constraint)
        .{ .percentage = 75 }, // Main content (takes remaining space)
    };
    const content_chunks = try layout.split(allocator, .horizontal, content_area, &content_constraints);
    defer allocator.free(content_chunks);

    // ======================
    // LEVEL 3a: Sidebar Layout
    // ======================
    // Metrics stack with padding
    const sidebar_padding = Padding.symmetric(1, 2); // vertical=1, horizontal=2
    const sidebar_area = content_chunks[0].withPadding(sidebar_padding);

    const sidebar_constraints = [_]layout.Constraint{
        .{ .length = 3 },  // CPU gauge
        .{ .length = 3 },  // Memory gauge
        .{ .length = 3 },  // Disk gauge
        .{ .min = 5 },     // Network info (min height)
    };
    const sidebar_chunks = try layout.split(allocator, .vertical, sidebar_area, &sidebar_constraints);
    defer allocator.free(sidebar_chunks);

    // Render gauges
    var cpu_gauge = Gauge{
        .ratio = 0.67,
        .label = "CPU 67%",
        .filled_style = Style{ .fg = Color{ .indexed = 11 } },
    };
    cpu_gauge.render(&buffer, sidebar_chunks[0]);

    var memory_gauge = Gauge{
        .ratio = 0.82,
        .label = "Memory 82%",
        .filled_style = Style{ .fg = Color{ .indexed = 9 } },
    };
    memory_gauge.render(&buffer, sidebar_chunks[1]);

    var disk_gauge = Gauge{
        .ratio = 0.45,
        .label = "Disk 45%",
        .filled_style = Style{ .fg = Color{ .indexed = 10 } },
    };
    disk_gauge.render(&buffer, sidebar_chunks[2]);

    var network_block = Block{
        .title = "Network",
        .borders = .all,
    };
    network_block.render(&buffer, sidebar_chunks[3]);
    const network_area = network_block.inner(sidebar_chunks[3]);
    buffer.setString(network_area.x, network_area.y, "RX: 512 KB/s", Style{});
    buffer.setString(network_area.x, network_area.y + 1, "TX: 256 KB/s", Style{});
    buffer.setString(network_area.x, network_area.y + 2, "Latency: 12ms", Style{});

    // ======================
    // LEVEL 3b: Main Content Layout
    // ======================
    // Video preview (top, 16:9 aspect ratio) + Performance charts (bottom, nested grid)
    const main_content_constraints = [_]layout.Constraint{
        .{ .percentage = 40 },  // Video preview
        .{ .percentage = 60 },  // Charts grid
    };
    const main_content_chunks = try layout.split(allocator, .vertical, content_chunks[1], &main_content_constraints);
    defer allocator.free(main_content_chunks);

    // ======================
    // LEVEL 4a: Video Preview (Aspect Ratio Constraint)
    // ======================
    // Apply 16:9 aspect ratio to video preview
    const video_area = main_content_chunks[0];
    const video_aspect = video_area.withAspectRatio(.{ .width = 16, .height = 9 });
    const video_margin = Margin{ .top = 0, .right = 2, .bottom = 1, .left = 2 };
    const video_final = video_aspect.withMargin(video_margin);

    var video_block = Block{
        .title = "Video Preview (16:9 aspect ratio)",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 13 } },
    };
    video_block.render(&buffer, video_final);
    const video_inner = video_block.inner(video_final);
    if (video_inner.height >= 3) {
        const center_y = video_inner.y + video_inner.height / 2;
        buffer.setString(video_inner.x + 2, center_y - 1, "█ LIVE STREAM █", Style{ .bold = true });
        buffer.setString(video_inner.x + 2, center_y, "16:9 aspect ratio", Style{});
        buffer.setString(video_inner.x + 2, center_y + 1, "with margins", Style{});
    }

    // ======================
    // LEVEL 4b: Charts Grid (Nested Grid Layout)
    // ======================
    const charts_area = main_content_chunks[1];

    // Nested grid: 2x2 chart panels
    const charts_rows = [_]layout.Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const charts_row_chunks = try layout.split(allocator, .vertical, charts_area, &charts_rows);
    defer allocator.free(charts_row_chunks);

    // Top row: CPU chart + Memory chart
    const top_row_cols = [_]layout.Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const top_row_chunks = try layout.split(allocator, .horizontal, charts_row_chunks[0], &top_row_cols);
    defer allocator.free(top_row_chunks);

    // Bottom row: Disk chart + Network chart
    const bottom_row_cols = [_]layout.Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const bottom_row_chunks = try layout.split(allocator, .horizontal, charts_row_chunks[1], &bottom_row_cols);
    defer allocator.free(bottom_row_chunks);

    // Render charts with 4:3 aspect ratio and margins
    const chart_margin = Margin.symmetric(1, 1);

    const chart_areas = [_]Rect{
        top_row_chunks[0].withAspectRatio(.{ .width = 4, .height = 3 }).withMargin(chart_margin),
        top_row_chunks[1].withAspectRatio(.{ .width = 4, .height = 3 }).withMargin(chart_margin),
        bottom_row_chunks[0].withAspectRatio(.{ .width = 4, .height = 3 }).withMargin(chart_margin),
        bottom_row_chunks[1].withAspectRatio(.{ .width = 4, .height = 3 }).withMargin(chart_margin),
    };

    const chart_titles = [_][]const u8{
        "CPU History (4:3)",
        "Memory History (4:3)",
        "Disk I/O (4:3)",
        "Network Traffic (4:3)",
    };

    const chart_colors = [_]Color{
        Color{ .indexed = 11 },
        Color{ .indexed = 9 },
        Color{ .indexed = 10 },
        Color{ .indexed = 14 },
    };

    for (chart_areas, chart_titles, chart_colors) |chart_area, title, color| {
        var chart_block = Block{
            .title = title,
            .borders = .all,
            .border_style = Style{ .fg = color },
        };
        chart_block.render(&buffer, chart_area);

        const chart_inner = chart_block.inner(chart_area);
        if (chart_inner.height >= 2) {
            buffer.setString(chart_inner.x + 1, chart_inner.y, "▁▂▃▅▇", Style{});
            buffer.setString(chart_inner.x, chart_inner.y + 1, "4:3 + margin", Style{});
        }
    }

    // ======================
    // Layout Debugging
    // ======================
    // Dump layout tree for inspection
    var debugger = layout.LayoutDebugger.init(allocator);
    defer debugger.deinit();

    // Debug main layout
    _ = try debugger.splitDebug(.vertical, area, &main_constraints);

    std.debug.print("\n=== Layout Debug Tree ===\n", .{});
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try debugger.print(stream.writer());
    std.debug.print("{s}\n", .{stream.getWritten()});

    // ======================
    // Render
    // ======================
    const stdout = std.io.getStdOut().writer();
    try buffer.renderTo(stdout);

    std.debug.print("\n✓ Advanced dashboard rendered successfully!\n", .{});
    std.debug.print("\nv1.32.0 Features Demonstrated:\n", .{});
    std.debug.print("  [x] Nested grid layouts (2x2 charts grid)\n", .{});
    std.debug.print("  [x] Aspect ratio constraints (16:9 video, 4:3 charts)\n", .{});
    std.debug.print("  [x] Min/max propagation (sidebar min=30, content min=20)\n", .{});
    std.debug.print("  [x] Auto-margin/padding (symmetric, asymmetric)\n", .{});
    std.debug.print("  [x] Layout debugging (tree printed to stderr)\n", .{});
}
