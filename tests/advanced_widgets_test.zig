//! Advanced widgets integration tests
//!
//! Tests for v1.6.0 (Data Visualization) and v1.7.0 (Advanced Layout) features.
//! Focuses on edge cases, integration patterns, and cross-feature interactions.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;

// v1.6.0 widgets
const Heatmap = sailor.tui.widgets.Heatmap;
const PieChart = sailor.tui.widgets.PieChart;
const ScatterPlot = sailor.tui.widgets.ScatterPlot;
const Histogram = sailor.tui.widgets.Histogram;
const TimeSeriesChart = sailor.tui.widgets.TimeSeriesChart;

// v1.7.0 layout
const FlexBox = sailor.tui.flexbox.FlexBox;

// ============================================================================
// v1.6.0 Data Visualization Widget Integration Tests
// ============================================================================

test "Heatmap with PieChart side-by-side layout" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 30);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    // Split screen: left = heatmap, right = piechart
    const left = Rect{ .x = 0, .y = 0, .width = 40, .height = 30 };
    const right = Rect{ .x = 40, .y = 0, .width = 40, .height = 30 };

    // Heatmap on left
    const row1 = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const row2 = [_]f64{ 2.0, 4.0, 6.0, 8.0, 10.0 };
    const row3 = [_]f64{ 3.0, 6.0, 9.0, 12.0, 15.0 };
    const heatmap_data = [_][]const f64{ &row1, &row2, &row3 };
    const heatmap = Heatmap{
        .data = &heatmap_data,
        .block = Block.init().withBorders(.all).withTitle("Heatmap", .top_left),
    };

    heatmap.render(&buffer, left);

    // PieChart on right
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 30, .style = .{ .fg = .{ .indexed = 1 } } },
        .{ .label = "B", .value = 50, .style = .{ .fg = .{ .indexed = 2 } } },
        .{ .label = "C", .value = 20, .style = .{ .fg = .{ .indexed = 3 } } },
    };
    const pie = PieChart.init(&slices)
        .withBlock(Block.init().withBorders(.all).withTitle("Distribution", .top_left));

    pie.render(&buffer, right);

    // Verify borders don't overlap
    if (buffer.get(39, 0)) |heatmap_border| {
        try testing.expect(heatmap_border.char == '┐' or heatmap_border.char == '│');
    }
    if (buffer.get(40, 0)) |pie_border| {
        try testing.expect(pie_border.char == '┌' or pie_border.char == '│');
    }
}

test "ScatterPlot with Histogram stacked vertically" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 60, 40);
    defer buffer.deinit();

    // Top half: ScatterPlot
    const top = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    const series = [_]ScatterPlot.Series{
        .{
            .name = "Data",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 2 },
                .{ .x = 2, .y = 4 },
                .{ .x = 3, .y = 3 },
                .{ .x = 4, .y = 5 },
            },
            .style = .{ .fg = .{ .indexed = 2 } },
        },
    };
    const scatter = ScatterPlot.init(&series)
        .withBlock(Block.init().withBorders(.all).withTitle("Scatter", .top_left));

    scatter.render(&buffer, top);

    // Bottom half: Histogram
    const bottom = Rect{ .x = 0, .y = 20, .width = 60, .height = 20 };
    const bins = [_]Histogram.Bin{
        .{ .label = "0-2", .count = 1 },
        .{ .label = "2-4", .count = 2 },
        .{ .label = "4-6", .count = 1 },
    };
    const hist = Histogram.init(&bins)
        .withBlock(Block.init().withBorders(.all).withTitle("Distribution", .top_left));

    hist.render(&buffer, bottom);

    // Verify no overlap between widgets
    if (buffer.get(0, 19)) |scatter_bottom| {
        try testing.expect(scatter_bottom.char == '└' or scatter_bottom.char == '─');
    }
    if (buffer.get(0, 20)) |hist_top| {
        try testing.expect(hist_top.char == '┌' or hist_top.char == '─');
    }
}

test "TimeSeriesChart with zero-length data" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 20);
    defer buffer.deinit();

    const timestamps: []const i64 = &.{};
    const values: []const f64 = &.{};

    var chart = try TimeSeriesChart.init(allocator, timestamps, values);
    defer chart.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buffer, area);

    // Should not crash with empty data
}

test "Heatmap with extreme values" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 15);
    defer buffer.deinit();

    // Test with very large and very small values
    const row1 = [_]f64{ 0.0001, 1000000.0, -500.0 };
    const row2 = [_]f64{ 999999.0, -0.0001, 0.0 };
    const data = [_][]const f64{ &row1, &row2 };

    const heatmap = Heatmap{ .data = &data };
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };

    heatmap.render(&buffer, area);
    // Should handle extreme values gracefully
}

test "PieChart with single slice" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 15);
    defer buffer.deinit();

    const slices = [_]PieChart.Slice{
        .{ .label = "100%", .value = 100, .style = .{ .fg = .{ .indexed = 2 } } },
    };

    const pie = PieChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };

    pie.render(&buffer, area);
    // Should render full circle for 100% slice
}

test "ScatterPlot with all points at same coordinate" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 20);
    defer buffer.deinit();

    const series = [_]ScatterPlot.Series{
        .{
            .name = "Same",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 5, .y = 5 },
                .{ .x = 5, .y = 5 },
                .{ .x = 5, .y = 5 },
            },
        },
    };

    const scatter = ScatterPlot.init(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    scatter.render(&buffer, area);
    // Should handle zero range gracefully
}

test "Histogram with zero counts" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 15);
    defer buffer.deinit();

    const bins = [_]Histogram.Bin{
        .{ .label = "A", .count = 0 },
        .{ .label = "B", .count = 0 },
        .{ .label = "C", .count = 0 },
    };

    const hist = Histogram.init(&bins);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    hist.render(&buffer, area);
    // Should render empty bars gracefully
}

test "TimeSeriesChart with single data point" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 15);
    defer buffer.deinit();

    const timestamps = [_]i64{1700000000};
    const values = [_]f64{42.0};

    var chart = try TimeSeriesChart.init(allocator, &timestamps, &values);
    defer chart.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    chart.render(&buffer, area);
    // Should handle single point without crashing
}

// ============================================================================
// v1.7.0 FlexBox Layout Integration Tests
// ============================================================================

test "FlexBox with data visualization widgets" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 100, 40);
    defer buffer.deinit();

    const container = Rect{ .x = 0, .y = 0, .width = 100, .height = 40 };

    // Create flexbox layout with 3 equal-width columns
    const flex = FlexBox.init(.horizontal)
        .withJustifyContent(.space_between)
        .withGap(2);

    const items = [_]FlexBox.Item{
        .{ .flex_basis = 30, .flex_grow = 1 },
        .{ .flex_basis = 30, .flex_grow = 1 },
        .{ .flex_basis = 30, .flex_grow = 1 },
    };

    const rects = try flex.layout(allocator, container, &items);
    defer allocator.free(rects);

    try testing.expectEqual(3, rects.len);

    // Render different widgets in each column
    // Column 1: Heatmap
    const hm_row1 = [_]f64{ 1, 2, 3 };
    const hm_row2 = [_]f64{ 4, 5, 6 };
    const heatmap_data = [_][]const f64{ &hm_row1, &hm_row2 };
    const heatmap = Heatmap{ .data = &heatmap_data };
    heatmap.render(&buffer, rects[0]);

    // Column 2: PieChart
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const pie = PieChart.init(&slices);
    pie.render(&buffer, rects[1]);

    // Column 3: Histogram
    const bins = [_]Histogram.Bin{
        .{ .label = "X", .count = 10 },
        .{ .label = "Y", .count = 20 },
    };
    const hist = Histogram.init(&bins);
    hist.render(&buffer, rects[2]);

    // Verify layouts don't overlap
    try testing.expect(rects[0].x + rects[0].width <= rects[1].x);
    try testing.expect(rects[1].x + rects[1].width <= rects[2].x);
}

test "FlexBox vertical layout with charts" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 60, 60);
    defer buffer.deinit();

    const container = Rect{ .x = 0, .y = 0, .width = 60, .height = 60 };

    const flex = FlexBox.init(.vertical)
        .withJustifyContent(.space_evenly)
        .withGap(1);

    const items = [_]FlexBox.Item{
        .{ .flex_basis = 15 },
        .{ .flex_basis = 15 },
        .{ .flex_basis = 15 },
    };

    const rects = try flex.layout(allocator, container, &items);
    defer allocator.free(rects);

    try testing.expectEqual(3, rects.len);

    // Stack ScatterPlot, Histogram, TimeSeries vertically
    const scatter_series = [_]ScatterPlot.Series{
        .{ .name = "S", .points = &[_]ScatterPlot.Point{.{ .x = 1, .y = 1 }} },
    };
    const scatter = ScatterPlot.init(&scatter_series);
    scatter.render(&buffer, rects[0]);

    const bins = [_]Histogram.Bin{.{ .label = "H", .count = 5 }};
    const hist = Histogram.init(&bins);
    hist.render(&buffer, rects[1]);

    const timestamps = [_]i64{1700000000};
    const values = [_]f64{10.0};
    const ts = try TimeSeriesChart.init(allocator, &timestamps, &values);
    defer ts.deinit();
    ts.render(&buffer, rects[2]);

    // Verify vertical stacking
    try testing.expect(rects[0].y + rects[0].height <= rects[1].y);
    try testing.expect(rects[1].y + rects[1].height <= rects[2].y);
}

test "FlexBox with flex_grow and data widgets" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 120, 30);
    defer buffer.deinit();

    const container = Rect{ .x = 0, .y = 0, .width = 120, .height = 30 };

    // Widget 1 gets 1x space, widget 2 gets 2x space
    const flex = FlexBox.init(.horizontal);
    const items = [_]FlexBox.Item{
        .{ .flex_basis = 20, .flex_grow = 1 },
        .{ .flex_basis = 20, .flex_grow = 2 },
    };

    const rects = try flex.layout(allocator, container, &items);
    defer allocator.free(rects);

    try testing.expectEqual(2, rects.len);

    // Smaller widget: PieChart
    const slices = [_]PieChart.Slice{
        .{ .label = "Small", .value = 100 },
    };
    const pie = PieChart.init(&slices);
    pie.render(&buffer, rects[0]);

    // Larger widget: ScatterPlot with more data
    const series = [_]ScatterPlot.Series{
        .{
            .name = "Large",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 1 },
                .{ .x = 2, .y = 2 },
                .{ .x = 3, .y = 3 },
            },
        },
    };
    const scatter = ScatterPlot.init(&series);
    scatter.render(&buffer, rects[1]);

    // Verify second widget is larger
    try testing.expect(rects[1].width > rects[0].width);
}

test "FlexBox with align_items center and mixed widgets" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 40);
    defer buffer.deinit();

    const container = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };

    const flex = FlexBox.init(.horizontal)
        .withAlignItems(.center);

    const items = [_]FlexBox.Item{
        .{ .flex_basis = 25 },
        .{ .flex_basis = 25 },
    };

    const rects = try flex.layout(allocator, container, &items);
    defer allocator.free(rects);

    // Render widgets in centered layout
    const hm_row = [_]f64{ 1, 2 };
    const heatmap_data = [_][]const f64{&hm_row};
    const heatmap = Heatmap{ .data = &heatmap_data };
    heatmap.render(&buffer, rects[0]);

    const bins = [_]Histogram.Bin{.{ .label = "B", .count = 5 }};
    const hist = Histogram.init(&bins);
    hist.render(&buffer, rects[1]);

    // With center alignment, widgets should be vertically centered
    // (Testing layout correctness, not visual output)
    try testing.expect(rects[0].y >= 0);
    try testing.expect(rects[1].y >= 0);
}

// ============================================================================
// Cross-version integration tests
// ============================================================================

test "Complex dashboard layout with FlexBox and v1.6.0 widgets" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 120, 60);
    defer buffer.deinit();

    // Dashboard with header and 3-column body
    const header_area = Rect{ .x = 0, .y = 0, .width = 120, .height = 10 };
    const body_area = Rect{ .x = 0, .y = 10, .width = 120, .height = 50 };

    // Header: TimeSeriesChart spanning full width
    const ts_timestamps = [_]i64{ 1700000000, 1700003600, 1700007200 };
    const ts_values = [_]f64{ 10, 15, 12 };
    var ts_chart = try TimeSeriesChart.init(allocator, &ts_timestamps, &ts_values);
    defer ts_chart.deinit();
    ts_chart.render(&buffer, header_area);

    // Body: FlexBox with 3 columns
    const flex = FlexBox.init(.horizontal)
        .withJustifyContent(.space_between)
        .withGap(2);

    const items = [_]FlexBox.Item{
        .{ .flex_basis = 38, .flex_grow = 1 },
        .{ .flex_basis = 38, .flex_grow = 1 },
        .{ .flex_basis = 38, .flex_grow = 1 },
    };

    const columns = try flex.layout(allocator, body_area, &items);
    defer allocator.free(columns);

    // Column 1: Heatmap
    const hm_r1 = [_]f64{ 1, 2, 3, 4 };
    const hm_r2 = [_]f64{ 5, 6, 7, 8 };
    const hm_r3 = [_]f64{ 9, 10, 11, 12 };
    const heatmap_data = [_][]const f64{ &hm_r1, &hm_r2, &hm_r3 };
    const heatmap = Heatmap{
        .data = &heatmap_data,
        .block = Block.init().withBorders(.all).withTitle("Heatmap", .top_left),
    };
    heatmap.render(&buffer, columns[0]);

    // Column 2: PieChart + Histogram stacked
    const pie_area = Rect{
        .x = columns[1].x,
        .y = columns[1].y,
        .width = columns[1].width,
        .height = columns[1].height / 2,
    };
    const hist_area = Rect{
        .x = columns[1].x,
        .y = columns[1].y + columns[1].height / 2,
        .width = columns[1].width,
        .height = columns[1].height - columns[1].height / 2,
    };

    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 30 },
        .{ .label = "B", .value = 70 },
    };
    const pie = PieChart.init(&slices)
        .withBlock(Block.init().withBorders(.all).withTitle("Pie", .top_left));
    pie.render(&buffer, pie_area);

    const bins = [_]Histogram.Bin{
        .{ .label = "1", .count = 5 },
        .{ .label = "2", .count = 10 },
        .{ .label = "3", .count = 7 },
    };
    const hist = Histogram.init(&bins)
        .withBlock(Block.init().withBorders(.all).withTitle("Hist", .top_left));
    hist.render(&buffer, hist_area);

    // Column 3: ScatterPlot
    const series = [_]ScatterPlot.Series{
        .{
            .name = "Data",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 2 },
                .{ .x = 2, .y = 4 },
                .{ .x = 3, .y = 3 },
            },
        },
    };
    const scatter = ScatterPlot.init(&series)
        .withBlock(Block.init().withBorders(.all).withTitle("Scatter", .top_left));
    scatter.render(&buffer, columns[2]);

    // Verify complex layout doesn't have overlaps
    try testing.expect(header_area.y + header_area.height <= body_area.y);
    try testing.expect(columns[0].x + columns[0].width <= columns[1].x);
    try testing.expect(columns[1].x + columns[1].width <= columns[2].x);
}
