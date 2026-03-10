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
    const width = @min(term_size.cols, 100);
    const height = @min(term_size.cols, 50);

    // Create buffer
    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    // Title
    const title_spans = [_]Span{
        Span.styled("Sailor Widget Gallery", .{ .fg = Color{ .indexed = 14 }, .bold = true }),
    };
    const title_line = [_]Line{Line{ .spans = &title_spans }};

    const widgets_text =
        \\
        \\BASIC WIDGETS (Phase 4)
        \\  • Block      — Container with borders and title
        \\  • Paragraph  — Text display with wrapping and alignment
        \\  • List       — Selectable item list with highlighting
        \\  • Table      — Tabular data display with headers
        \\  • Input      — Single-line text input field
        \\  • Tabs       — Tab navigation widget
        \\  • StatusBar  — Status line at screen bottom
        \\  • Gauge      — Progress bar with percentage
        \\
        \\ADVANCED WIDGETS (Phase 5)
        \\  • Tree       — Hierarchical tree view
        \\  • TextArea   — Multi-line text editor
        \\  • Sparkline  — Inline line chart
        \\  • BarChart   — Vertical/horizontal bar charts
        \\  • LineChart  — Multi-series line plots
        \\  • Canvas     — Braille-dot precision drawing
        \\  • Dialog     — Modal confirmation dialogs
        \\  • Popup      — Floating overlay windows
        \\  • Notification — Toast messages (4 levels, 6 positions)
        \\
        \\LAYOUT & COMPOSITION (v1.2.0)
        \\  • ScrollView — Virtual scrolling for large content
        \\  • Grid       — CSS Grid-inspired 2D layout
        \\  • Overlay    — Z-index system for layered widgets
        \\
        \\INPUT & FORMS (v1.4.0)
        \\  • Form       — Field collection with validation
        \\  • Select     — Dropdown selection widget
        \\  • Checkbox   — Boolean toggle widgets
        \\  • RadioGroup — Mutually exclusive selection
        \\
        \\DATA VISUALIZATION (v1.6.0)
        \\  • Heatmap    — 2D data grid with color gradients
        \\  • PieChart   — Circular percentage display
        \\  • ScatterPlot — X-Y coordinate plotting
        \\  • Histogram  — Frequency distribution bars
        \\  • TimeSeriesChart — Time-based data visualization
        \\
        \\NETWORK & ASYNC (v1.8.0)
        \\  • HttpClient — Download progress visualization
        \\  • WebSocket  — Live data feed with auto-scroll
        \\  • TaskRunner — Parallel operation status
        \\  • LogViewer  — Tail -f style log display
        \\
        \\DEVELOPER TOOLS (v1.9.0)
        \\  • DebugOverlay — Layout rect visualization
        \\  • WidgetDebugger — Widget tree inspector
        \\  • PerformanceProfiler — Frame timing & memory stats
        \\  • ThemeEditor — Live theme customization
        \\  • CompletionPopup — REPL tab completion
        \\
        \\TOTAL: 40+ widgets across 7 categories
        \\Tests: 827+ passing | Cross-platform: Linux, macOS, Windows
        \\Zero dependencies — Pure Zig stdlib
        \\
        \\See examples/ for usage: hello.zig, counter.zig, dashboard.zig
    ;

    var text_lines = [_]Line{Line{ .spans = title_line[0].spans }};
    const content_paragraph = Paragraph{
        .lines = &text_lines,
    };

    const text_paragraph = Paragraph{
        .text = widgets_text,
        .style = .{ .fg = Color{ .indexed = 7 } },
    };

    // Render
    const title_area = Rect{ .x = 0, .y = 0, .width = width, .height = 1 };
    const content_area = Rect{ .x = 0, .y = 2, .width = width, .height = height -| 2 };

    content_paragraph.render(&buffer, title_area);
    text_paragraph.render(&buffer, content_area);

    // Output
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
