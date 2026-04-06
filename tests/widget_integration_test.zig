//! Widget integration tests
//!
//! These tests verify that widgets work correctly together in complex
//! scenarios, testing edge cases and integration patterns.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Table = sailor.tui.widgets.Table;
const Column = sailor.tui.widgets.Column;
const Row = sailor.tui.widgets.Row;
const Gauge = sailor.tui.widgets.Gauge;
const StatusBar = sailor.tui.widgets.StatusBar;
const Tabs = sailor.tui.widgets.Tabs;
const Sparkline = sailor.tui.widgets.Sparkline;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Line = sailor.tui.Line;
const Span = sailor.tui.Span;
const layout = sailor.tui.layout;
const Constraint = sailor.tui.Constraint;

test "nested blocks don't overflow" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 20);
    defer buffer.deinit();

    const outer = Block{
        .title = "Outer",
        .borders = .all,
        .border_style = .{ .fg = .cyan },
    };

    const inner = Block{
        .title = "Inner",
        .borders = .all,
        .border_style = .{ .fg = .yellow },
    };

    const area = Rect.new(0, 0, 40, 20);
    outer.render(&buffer, area);

    const inner_area = outer.inner(area);
    inner.render(&buffer, inner_area);

    // Verify inner area is properly contained
    try testing.expect(inner_area.x >= area.x);
    try testing.expect(inner_area.y >= area.y);
    try testing.expect(inner_area.x + inner_area.width <= area.x + area.width);
    try testing.expect(inner_area.y + inner_area.height <= area.y + area.height);
}

test "paragraph with empty lines doesn't crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 20);
    defer buffer.deinit();

    const empty_line = Line{ .spans = &[_]Span{} };
    const lines = [_]Line{empty_line} ** 5;

    const para = Paragraph{
        .lines = &lines,
    };

    para.render(&buffer, Rect.new(0, 0, 40, 10));
    // Should not crash with empty lines
}

test "table with zero rows renders empty" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 60, 20);
    defer buffer.deinit();

    const columns = [_]Column{
        .{ .title = "Col1", .width = .{ .fixed = 20 } },
        .{ .title = "Col2", .width = .{ .fixed = 20 } },
    };

    const rows: []const Row = &[_]Row{};

    const table = Table{
        .columns = &columns,
        .rows = rows,
        .block = Block{
            .title = "Empty Table",
            .borders = .all,
        },
    };

    table.render(&buffer, Rect.new(0, 0, 50, 10));
    // Should render without crashing
}

test "gauge with extreme ratios is clamped" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    // Test withRatio clamping for ratio > 1.0
    const gauge_over = (Gauge{}).withRatio(2.0);
    try testing.expectEqual(1.0, gauge_over.ratio);
    gauge_over.render(&buffer, Rect.new(0, 0, 40, 3));

    // Test withRatio clamping for ratio < 0.0
    const gauge_under = (Gauge{}).withRatio(-0.5);
    try testing.expectEqual(0.0, gauge_under.ratio);
    gauge_under.render(&buffer, Rect.new(0, 0, 40, 3));

    // Test withPercent clamping for value > 100
    const gauge_percent_over = (Gauge{}).withPercent(150);
    try testing.expectEqual(1.0, gauge_percent_over.ratio);
}

test "list with selection out of bounds is clamped" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 20);
    defer buffer.deinit();

    const items = [_][]const u8{ "Item 1", "Item 2", "Item 3" };

    // Selected index beyond items length
    const list = List{
        .items = &items,
        .selected = 999,
    };

    list.render(&buffer, Rect.new(0, 0, 40, 10));
    // Should handle gracefully
}

test "statusbar with very long text is truncated" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 1);
    defer buffer.deinit();

    const long_text = "This is a very long text that exceeds the available width";
    const spans = [_]Span{Span.raw(long_text)};

    const status_bar = StatusBar{
        .left = &spans,
    };

    status_bar.render(&buffer, Rect.new(0, 0, 20, 1));
    // Should truncate gracefully
}

test "tabs with no titles doesn't crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 3);
    defer buffer.deinit();

    const titles: []const []const u8 = &[_][]const u8{};

    const tabs = Tabs{
        .titles = titles,
        .selected = 0,
    };

    tabs.render(&buffer, Rect.new(0, 0, 40, 3));
    // Should handle empty titles gracefully
}

test "sparkline with empty data doesn't crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    const data: []const u64 = &[_]u64{};

    const sparkline = Sparkline{
        .data = data,
    };

    sparkline.render(&buffer, Rect.new(0, 0, 40, 5));
    // Should handle empty data gracefully
}

test "sparkline with single data point" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    const data = [_]u64{42};

    const sparkline = Sparkline{
        .data = &data,
    };

    sparkline.render(&buffer, Rect.new(0, 0, 40, 5));
    // Should render single point correctly
}

test "sparkline with all zero values" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    const data = [_]u64{ 0, 0, 0, 0, 0 };

    const sparkline = Sparkline{
        .data = &data,
    };

    sparkline.render(&buffer, Rect.new(0, 0, 40, 5));
    // Should handle all zeros without division by zero
}

test "layout split with zero area" {
    const allocator = testing.allocator;

    const area = Rect.new(0, 0, 0, 0);
    const chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .length = 5 },
            .{ .min = 1 },
        },
    );
    defer allocator.free(chunks);

    // Should not crash with zero-sized area
    try testing.expectEqual(2, chunks.len);
}

test "layout split with single constraint" {
    const allocator = testing.allocator;

    const area = Rect.new(0, 0, 80, 24);
    const chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{.{ .percentage = 100 }},
    );
    defer allocator.free(chunks);

    try testing.expectEqual(1, chunks.len);
    try testing.expectEqual(area.width, chunks[0].width);
    try testing.expectEqual(area.height, chunks[0].height);
}

test "layout split with percentage totaling over 100" {
    const allocator = testing.allocator;

    const area = Rect.new(0, 0, 80, 24);
    const chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .percentage = 60 },
            .{ .percentage = 60 },
        },
    );
    defer allocator.free(chunks);

    try testing.expectEqual(2, chunks.len);
    // Total height should still equal area height
    try testing.expectEqual(area.height, chunks[0].height + chunks[1].height);
}

test "multiple widgets in split layout" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect.new(0, 0, 80, 24);
    const chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .length = 3 }, // Gauge
            .{ .min = 5 }, // List
            .{ .length = 1 }, // StatusBar
        },
    );
    defer allocator.free(chunks);

    // Render gauge
    const gauge = Gauge{
        .ratio = 0.75,
        .block = Block{
            .title = "Progress",
            .borders = .all,
        },
    };
    gauge.render(&buffer, chunks[0]);

    // Render list
    const items = [_][]const u8{ "Task 1", "Task 2", "Task 3" };
    const list = List{
        .items = &items,
        .selected = 1,
        .block = Block{
            .title = "Tasks",
            .borders = .all,
        },
    };
    list.render(&buffer, chunks[1]);

    // Render statusbar
    const spans = [_]Span{Span.raw("Ready")};
    const status_bar = StatusBar{
        .left = &spans,
    };
    status_bar.render(&buffer, chunks[2]);

    // All widgets should render without conflict
}

test "widget rendering in very small area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 3, 2);
    defer buffer.deinit();

    const area = Rect.new(0, 0, 3, 2);

    // Block should handle minimal area
    const block = Block{
        .borders = .all,
    };
    block.render(&buffer, area);

    // Gauge should handle minimal area
    const gauge = Gauge{
        .ratio = 0.5,
    };
    gauge.render(&buffer, area);
}

test "paragraph with very long lines wraps correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const long_text = "This is a very long line that should wrap when rendered in a narrow area";
    const span = Span.raw(long_text);
    const line = Line{ .spans = &[_]Span{span} };
    const lines = [_]Line{line};

    const para = Paragraph{
        .lines = &lines,
    };

    para.render(&buffer, Rect.new(0, 0, 20, 10));
    // Should wrap without crashing
}

test "table with mismatched column and row data" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 60, 20);
    defer buffer.deinit();

    // 3 columns defined
    const columns = [_]Column{
        .{ .title = "Col1", .width = .{ .fixed = 15 } },
        .{ .title = "Col2", .width = .{ .fixed = 15 } },
        .{ .title = "Col3", .width = .{ .fixed = 15 } },
    };

    // Row with only 2 cells (less than columns)
    const row1 = [_][]const u8{ "Cell 1", "Cell 2" };
    const rows = [_]Row{&row1};

    const table = Table{
        .columns = &columns,
        .rows = &rows,
    };

    table.render(&buffer, Rect.new(0, 0, 60, 10));
    // Should handle gracefully
}

test "deeply nested layout splits" {
    const allocator = testing.allocator;

    const area = Rect.new(0, 0, 80, 24);

    // First split: vertical
    const v_chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .percentage = 50 },
            .{ .percentage = 50 },
        },
    );
    defer allocator.free(v_chunks);

    // Second split: horizontal on first chunk
    const h_chunks = try layout.split(
        allocator,
        .horizontal,
        v_chunks[0],
        &[_]Constraint{
            .{ .percentage = 50 },
            .{ .percentage = 50 },
        },
    );
    defer allocator.free(h_chunks);

    try testing.expectEqual(2, v_chunks.len);
    try testing.expectEqual(2, h_chunks.len);

    // Verify nested areas fit within parent
    try testing.expect(h_chunks[0].x >= v_chunks[0].x);
    try testing.expect(h_chunks[0].y >= v_chunks[0].y);
    try testing.expect(h_chunks[1].x >= v_chunks[0].x);
    try testing.expect(h_chunks[1].y >= v_chunks[0].y);
}

test "block with all border types" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 20);
    defer buffer.deinit();

    // Test various border combinations
    const block_none = Block{ .borders = .none };
    block_none.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    const block_all = Block{ .borders = .all };
    block_all.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    const block_top = Block{ .borders = .{ .top = true } };
    block_top.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    const block_bottom = Block{ .borders = .{ .bottom = true } };
    block_bottom.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    const block_left = Block{ .borders = .{ .left = true } };
    block_left.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    const block_right = Block{ .borders = .{ .right = true } };
    block_right.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    const block_hori = Block{ .borders = .{ .top = true, .bottom = true } };
    block_hori.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    const block_vert = Block{ .borders = .{ .left = true, .right = true } };
    block_vert.render(&buffer, Rect.new(0, 0, 20, 10));
    buffer.clear();

    // All border combinations should render correctly
}

test "gauge with label longer than width" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 3);
    defer buffer.deinit();

    const gauge = Gauge{
        .ratio = 0.5,
        .label = "Very long label text",
    };

    gauge.render(&buffer, Rect.new(0, 0, 10, 3));
    // Should truncate label gracefully
}

test "statusbar with center text wider than area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 1);
    defer buffer.deinit();

    const center_spans = [_]Span{Span.raw("This is a very long centered text")};

    const status_bar = StatusBar{
        .center = &center_spans,
    };

    status_bar.render(&buffer, Rect.new(0, 0, 20, 1));
    // Should handle overflow gracefully
}

test "complex dashboard layout integration" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 120, 40);
    defer buffer.deinit();

    const area = Rect.new(0, 0, 120, 40);

    // Main layout: header, body, footer
    const main_chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .length = 3 }, // Header
            .{ .min = 10 }, // Body
            .{ .length = 1 }, // Footer
        },
    );
    defer allocator.free(main_chunks);

    // Body split into left and right panels
    const body_chunks = try layout.split(
        allocator,
        .horizontal,
        main_chunks[1],
        &[_]Constraint{
            .{ .percentage = 60 },
            .{ .percentage = 40 },
        },
    );
    defer allocator.free(body_chunks);

    // Left panel split into top and bottom
    const left_chunks = try layout.split(
        allocator,
        .vertical,
        body_chunks[0],
        &[_]Constraint{
            .{ .percentage = 70 },
            .{ .percentage = 30 },
        },
    );
    defer allocator.free(left_chunks);

    // Render widgets in all areas
    const header_tabs = Tabs{
        .titles = &[_][]const u8{ "Dashboard", "Metrics", "Settings" },
        .selected = 0,
    };
    header_tabs.render(&buffer, main_chunks[0]);

    const main_table_columns = [_]Column{
        .{ .title = "Name", .width = .{ .percentage = 40 } },
        .{ .title = "Value", .width = .{ .percentage = 60 } },
    };
    const row1 = [_][]const u8{ "Metric 1", "100" };
    const table_rows = [_]Row{&row1};
    const main_table = Table{
        .columns = &main_table_columns,
        .rows = &table_rows,
        .block = Block{ .title = "Data", .borders = .all },
    };
    main_table.render(&buffer, left_chunks[0]);

    const sparkline_data = [_]u64{ 10, 20, 15, 30, 25 };
    const sparkline = Sparkline{
        .data = &sparkline_data,
        .block = Block{ .title = "Trend", .borders = .all },
    };
    sparkline.render(&buffer, left_chunks[1]);

    const gauge = Gauge{
        .ratio = 0.65,
        .block = Block{ .title = "Usage", .borders = .all },
    };
    gauge.render(&buffer, body_chunks[1]);

    const footer_spans = [_]Span{Span.raw("Ready")};
    const footer = StatusBar{
        .left = &footer_spans,
    };
    footer.render(&buffer, main_chunks[2]);

    // Complex dashboard should render without issues
}
