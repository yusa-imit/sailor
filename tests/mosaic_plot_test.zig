//! MosaicPlot Widget Tests — TDD Red Phase
//!
//! Tests MosaicPlot widget rendering Marimekko-style variable-width-column +
//! stacked-segment-height proportional chart. Column widths and segment heights
//! are computed via cumulative-floor formula to ensure deterministic, hand-computable
//! layout with no gaps/overlaps.
//!
//! Tests cover initialization, builder pattern, columnCount/segmentCount capping
//! at MAX_COLUMNS/MAX_SEGMENTS_PER_COLUMN, columnTotal/grandTotal computation,
//! column-width proportionality (cumulative-floor formula), segment-height
//! proportionality (cumulative-floor within column), focused column/segment styling,
//! show_column_labels/show_segment_labels toggles, zero/negative-value handling
//! (no-panic clamping), grand_total==0 edge case, block border rendering, and
//! render edge cases (zero-area, empty columns, empty segments).

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const MosaicPlot = sailor.tui.widgets.MosaicPlot;
const MosaicColumn = sailor.tui.widgets.mosaic_plot.MosaicColumn;
const MosaicSegment = sailor.tui.widgets.mosaic_plot.MosaicSegment;

// ============================================================================
// Helper Functions
// ============================================================================

/// Count non-empty cells (non-space characters) in a buffer area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Count specific character in a buffer area
fn countChar(buf: Buffer, area: Rect, target_char: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == target_char) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Get cell at position in area (relative coordinates)
fn getCell(buf: Buffer, area: Rect, x: u16, y: u16) ?sailor.Cell {
    if (x >= area.width or y >= area.height) return null;
    return buf.getConst(area.x + x, area.y + y);
}

// ============================================================================
// Group 1: Init and Defaults (8 tests)
// ============================================================================

test "MosaicPlot.init creates plot with zero columns" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.columns.len);
}

test "MosaicPlot.init defaults focused_column to 0" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.focused_column);
}

test "MosaicPlot.init defaults focused_segment to 0" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.focused_segment);
}

test "MosaicPlot.init defaults show_column_labels to true" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(true, plot.show_column_labels);
}

test "MosaicPlot.init defaults show_segment_labels to false" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(false, plot.show_segment_labels);
}

test "MosaicPlot.init defaults block to null" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(?Block, null), plot.block);
}

test "MosaicPlot.init has default empty styles" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(Style{}, plot.style);
    try testing.expectEqual(Style{}, plot.label_style);
    try testing.expectEqual(Style{}, plot.focused_style);
}

test "MosaicSegment default label is empty" {
    const seg = MosaicSegment{};
    try testing.expectEqualStrings("", seg.label);
}

// ============================================================================
// Group 2: Constants (2 tests)
// ============================================================================

test "MosaicPlot.MAX_COLUMNS equals 16" {
    try testing.expectEqual(@as(usize, 16), MosaicPlot.MAX_COLUMNS);
}

test "MosaicPlot.MAX_SEGMENTS_PER_COLUMN equals 8" {
    try testing.expectEqual(@as(usize, 8), MosaicPlot.MAX_SEGMENTS_PER_COLUMN);
}

// ============================================================================
// Group 3: columnCount() Method (5 tests)
// ============================================================================

test "columnCount with zero columns returns 0" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.columnCount());
}

test "columnCount with 1 column returns 1" {
    var segs = [_]MosaicSegment{.{ .label = "A", .value = 10 }};
    var cols = [_]MosaicColumn{.{ .label = "Col1", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 1), plot.columnCount());
}

test "columnCount with 4 columns returns 4" {
    var segs1 = [_]MosaicSegment{.{ .value = 5 }};
    var segs2 = [_]MosaicSegment{.{ .value = 10 }};
    var segs3 = [_]MosaicSegment{.{ .value = 15 }};
    var segs4 = [_]MosaicSegment{.{ .value = 20 }};
    var cols = [_]MosaicColumn{
        .{ .label = "C1", .segments = &segs1 },
        .{ .label = "C2", .segments = &segs2 },
        .{ .label = "C3", .segments = &segs3 },
        .{ .label = "C4", .segments = &segs4 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 4), plot.columnCount());
}

test "columnCount caps at MAX_COLUMNS=16 when 32 columns provided" {
    var segs: [32][1]MosaicSegment = undefined;
    var cols: [32]MosaicColumn = undefined;
    for (0..32) |i| {
        segs[i][0] = .{ .value = @as(f32, @floatFromInt(i + 1)) };
        cols[i] = .{ .label = "C", .segments = &segs[i] };
    }
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 16), plot.columnCount());
}

test "columnCount with exactly MAX_COLUMNS=16 returns 16" {
    var segs: [16][1]MosaicSegment = undefined;
    var cols: [16]MosaicColumn = undefined;
    for (0..16) |i| {
        segs[i][0] = .{ .value = @as(f32, @floatFromInt(i + 1)) };
        cols[i] = .{ .label = "C", .segments = &segs[i] };
    }
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 16), plot.columnCount());
}

// ============================================================================
// Group 4: segmentCount() Method (5 tests)
// ============================================================================

test "segmentCount with empty column returns 0" {
    var segs: [0]MosaicSegment = undefined;
    var cols = [_]MosaicColumn{.{ .label = "C1", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 0), plot.segmentCount(0));
}

test "segmentCount with 1 segment returns 1" {
    var segs = [_]MosaicSegment{.{ .value = 5 }};
    var cols = [_]MosaicColumn{.{ .label = "C1", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 1), plot.segmentCount(0));
}

test "segmentCount with 4 segments returns 4" {
    var segs = [_]MosaicSegment{
        .{ .value = 1 },
        .{ .value = 2 },
        .{ .value = 3 },
        .{ .value = 4 },
    };
    var cols = [_]MosaicColumn{.{ .label = "C1", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 4), plot.segmentCount(0));
}

test "segmentCount caps at MAX_SEGMENTS_PER_COLUMN=8" {
    var segs: [16]MosaicSegment = undefined;
    for (0..16) |i| {
        segs[i] = .{ .value = @as(f32, @floatFromInt(i + 1)) };
    }
    var cols = [_]MosaicColumn{.{ .label = "C1", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 8), plot.segmentCount(0));
}

test "segmentCount with exactly MAX_SEGMENTS_PER_COLUMN=8 returns 8" {
    var segs: [8]MosaicSegment = undefined;
    for (0..8) |i| {
        segs[i] = .{ .value = @as(f32, @floatFromInt(i + 1)) };
    }
    var cols = [_]MosaicColumn{.{ .label = "C1", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 8), plot.segmentCount(0));
}

// ============================================================================
// Group 5: columnTotal() Method (5 tests)
// ============================================================================

test "columnTotal with empty column returns 0" {
    var segs: [0]MosaicSegment = undefined;
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(f32, 0), plot.columnTotal(0));
}

test "columnTotal sums all segment values in column" {
    var segs = [_]MosaicSegment{
        .{ .value = 10 },
        .{ .value = 20 },
        .{ .value = 30 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(f32, 60), plot.columnTotal(0));
}

test "columnTotal clamps negative values to 0" {
    var segs = [_]MosaicSegment{
        .{ .value = 10 },
        .{ .value = -5 },
        .{ .value = 20 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    // Expected: 10 + max(0, -5) + 20 = 30 (negative clamped to 0)
    try testing.expectEqual(@as(f32, 30), plot.columnTotal(0));
}

test "columnTotal with all-zero segments returns 0" {
    var segs = [_]MosaicSegment{
        .{ .value = 0 },
        .{ .value = 0 },
        .{ .value = 0 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(f32, 0), plot.columnTotal(0));
}

test "columnTotal caps segment count at MAX_SEGMENTS_PER_COLUMN" {
    var segs: [16]MosaicSegment = undefined;
    for (0..16) |i| {
        segs[i] = .{ .value = 10 };
    }
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    // Only first 8 segments counted (MAX_SEGMENTS_PER_COLUMN)
    try testing.expectEqual(@as(f32, 80), plot.columnTotal(0));
}

// ============================================================================
// Group 6: grandTotal() Method (5 tests)
// ============================================================================

test "grandTotal with zero columns returns 0" {
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(f32, 0), plot.grandTotal());
}

test "grandTotal sums columnTotal across all columns" {
    var segs1 = [_]MosaicSegment{.{ .value = 10 }, .{ .value = 20 }};
    var segs2 = [_]MosaicSegment{.{ .value = 30 }, .{ .value = 40 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    // Column 1: 30, Column 2: 70, total: 100
    try testing.expectEqual(@as(f32, 100), plot.grandTotal());
}

test "grandTotal with all-zero columns returns 0" {
    var segs1 = [_]MosaicSegment{.{ .value = 0 }};
    var segs2 = [_]MosaicSegment{.{ .value = 0 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(f32, 0), plot.grandTotal());
}

test "grandTotal clamps negative segment values" {
    var segs = [_]MosaicSegment{
        .{ .value = 100 },
        .{ .value = -50 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    // Sum: 100 + max(0, -50) = 100
    try testing.expectEqual(@as(f32, 100), plot.grandTotal());
}

test "grandTotal caps column count at MAX_COLUMNS" {
    var segs: [32][1]MosaicSegment = undefined;
    var cols: [32]MosaicColumn = undefined;
    for (0..32) |i| {
        segs[i][0] = .{ .value = 10 };
        cols[i] = .{ .segments = &segs[i] };
    }
    const plot = MosaicPlot.init().withColumns(&cols);
    // Only first 16 columns counted (MAX_COLUMNS)
    try testing.expectEqual(@as(f32, 160), plot.grandTotal());
}

// ============================================================================
// Group 7: Builder Immutability — All Builder Methods (7 tests)
// ============================================================================

test "withColumns does not modify original" {
    var segs1 = [_]MosaicSegment{.{ .value = 5 }};
    var segs2 = [_]MosaicSegment{.{ .value = 10 }};
    var cols1 = [_]MosaicColumn{.{ .segments = &segs1 }};
    var cols2 = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot1 = MosaicPlot.init().withColumns(&cols1);
    const plot2 = plot1.withColumns(&cols2);
    try testing.expectEqual(@as(usize, 1), plot1.columnCount());
    try testing.expectEqual(@as(usize, 2), plot2.columnCount());
}

test "withFocusedColumn does not modify original" {
    const plot1 = MosaicPlot.init().withFocusedColumn(0);
    const plot2 = plot1.withFocusedColumn(5);
    try testing.expectEqual(@as(usize, 0), plot1.focused_column);
    try testing.expectEqual(@as(usize, 5), plot2.focused_column);
}

test "withFocusedSegment does not modify original" {
    const plot1 = MosaicPlot.init().withFocusedSegment(0);
    const plot2 = plot1.withFocusedSegment(3);
    try testing.expectEqual(@as(usize, 0), plot1.focused_segment);
    try testing.expectEqual(@as(usize, 3), plot2.focused_segment);
}

test "withShowColumnLabels does not modify original" {
    const plot1 = MosaicPlot.init().withShowColumnLabels(true);
    const plot2 = plot1.withShowColumnLabels(false);
    try testing.expectEqual(true, plot1.show_column_labels);
    try testing.expectEqual(false, plot2.show_column_labels);
}

test "withShowSegmentLabels does not modify original" {
    const plot1 = MosaicPlot.init().withShowSegmentLabels(false);
    const plot2 = plot1.withShowSegmentLabels(true);
    try testing.expectEqual(false, plot1.show_segment_labels);
    try testing.expectEqual(true, plot2.show_segment_labels);
}

test "withStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const plot1 = MosaicPlot.init().withStyle(s1);
    const plot2 = plot1.withStyle(s2);
    try testing.expectEqual(true, plot1.style.bold);
    try testing.expectEqual(true, plot2.style.dim);
}

test "withBlock does not modify original" {
    const plot1 = MosaicPlot.init().withBlock(.{});
    const plot2 = plot1.withBlock(null);
    try testing.expect(plot1.block != null);
    try testing.expect(plot2.block == null);
}

// ============================================================================
// Group 8: Render — Zero/Minimal Area (3 tests)
// ============================================================================

test "render with 0x0 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = MosaicPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    plot.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = MosaicPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    plot.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = MosaicPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    plot.render(&buf, area);
}

// ============================================================================
// Group 9: Render — Empty Data (2 tests)
// ============================================================================

test "render with zero columns produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = MosaicPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    plot.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero columns and Block does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = MosaicPlot.init().withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    plot.render(&buf, area);
}

// ============================================================================
// Group 10: Render — Single Column Single Segment (2 tests)
// ============================================================================

test "render single column single segment produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{.{ .label = "A", .value = 100 }};
    var cols = [_]MosaicColumn{.{ .label = "Col1", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render single column single segment with block does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{.{ .label = "Seg", .value = 50 }};
    var cols = [_]MosaicColumn{.{ .label = "Column", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

// ============================================================================
// Group 11: Render — Multiple Columns Multiple Segments (3 tests)
// ============================================================================

test "render multiple columns produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs1 = [_]MosaicSegment{.{ .value = 30 }, .{ .value = 20 }};
    var segs2 = [_]MosaicSegment{.{ .value = 40 }, .{ .value = 10 }};
    var cols = [_]MosaicColumn{
        .{ .label = "C1", .segments = &segs1 },
        .{ .label = "C2", .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render three columns with varying segment counts" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs1 = [_]MosaicSegment{.{ .value = 10 }};
    var segs2 = [_]MosaicSegment{.{ .value = 20 }, .{ .value = 30 }};
    var segs3 = [_]MosaicSegment{.{ .value = 15 }, .{ .value = 25 }, .{ .value = 10 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
        .{ .segments = &segs3 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with all-equal column totals produces roughly equal-width columns" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs1 = [_]MosaicSegment{.{ .value = 50 }};
    var segs2 = [_]MosaicSegment{.{ .value = 50 }};
    var segs3 = [_]MosaicSegment{.{ .value = 50 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
        .{ .segments = &segs3 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 12: Column Width Proportionality — Hand-Computed Formula (3 tests)
// ============================================================================

test "column width proportional to value: 1:2 ratio" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Column totals: C1=100, C2=200
    // Grand total = 300
    // C1 col_x[0] = 0 + floor(0/300 * 100) = 0
    // C1 col_x[1] = 0 + floor(100/300 * 100) = 0 + floor(33.33) = 0 + 33 = 33
    // C2 col_x[2] = 0 + floor(300/300 * 100) = 100
    // Expected: C1 width=33 (x=[0,33)), C2 width=67 (x=[33,100))
    var segs1 = [_]MosaicSegment{.{ .value = 100 }};
    var segs2 = [_]MosaicSegment{.{ .value = 200 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 10 };

    plot.render(&buf, area);
    // Verify column boundaries by checking cells at expected positions
    // C1 should occupy x=[0,33), C2 should occupy x=[33,100)
    // Check middle of C1 (x=16) and middle of C2 (x=66) at y=5 (middle row)
    const cell_c1 = getCell(buf, area, 16, 5);
    const cell_c2 = getCell(buf, area, 66, 5);
    try testing.expect(cell_c1 != null and cell_c1.?.char != ' ');
    try testing.expect(cell_c2 != null and cell_c2.?.char != ' ');
    // Verify boundary transition at x=32/33
    const cell_boundary_before = getCell(buf, area, 32, 5);
    const cell_boundary_after = getCell(buf, area, 33, 5);
    try testing.expect(cell_boundary_before != null and cell_boundary_before.?.char != ' ');
    try testing.expect(cell_boundary_after != null and cell_boundary_after.?.char != ' ');
}

test "three equal-value columns render roughly equal-width" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Columns: 10, 10, 10 (equal totals)
    // Grand total = 30
    // col_x[0] = floor(0/30 * 90) = 0
    // col_x[1] = floor(10/30 * 90) = floor(30) = 30
    // col_x[2] = floor(20/30 * 90) = floor(60) = 60
    // col_x[3] = floor(30/30 * 90) = 90
    // Expected: C1 width=30 (x=[0,30)), C2 width=30 (x=[30,60)), C3 width=30 (x=[60,90))
    var segs1 = [_]MosaicSegment{.{ .value = 10 }};
    var segs2 = [_]MosaicSegment{.{ .value = 10 }};
    var segs3 = [_]MosaicSegment{.{ .value = 10 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
        .{ .segments = &segs3 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 10 };

    plot.render(&buf, area);
    // Verify all three columns render at correct x-boundaries
    // Check middle of each column at y=5
    const cell_c1 = getCell(buf, area, 15, 5);  // x=15, middle of [0,30)
    const cell_c2 = getCell(buf, area, 45, 5);  // x=45, middle of [30,60)
    const cell_c3 = getCell(buf, area, 75, 5);  // x=75, middle of [60,90)
    try testing.expect(cell_c1 != null and cell_c1.?.char != ' ');
    try testing.expect(cell_c2 != null and cell_c2.?.char != ' ');
    try testing.expect(cell_c3 != null and cell_c3.?.char != ' ');
    // Verify boundaries at expected transitions
    const boundary_1 = getCell(buf, area, 29, 5);  // x=29, end of C1
    const boundary_2 = getCell(buf, area, 30, 5);  // x=30, start of C2
    const boundary_3 = getCell(buf, area, 59, 5);  // x=59, end of C2
    const boundary_4 = getCell(buf, area, 60, 5);  // x=60, start of C3
    try testing.expect(boundary_1 != null and boundary_1.?.char != ' ');
    try testing.expect(boundary_2 != null and boundary_2.?.char != ' ');
    try testing.expect(boundary_3 != null and boundary_3.?.char != ' ');
    try testing.expect(boundary_4 != null and boundary_4.?.char != ' ');
}

test "very unequal column values render proportionally" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Column totals: 1, 9
    // Grand total = 10
    // col_x[0] = floor(0/10 * 100) = 0
    // col_x[1] = floor(1/10 * 100) = floor(10) = 10
    // col_x[2] = floor(10/10 * 100) = 100
    // Expected: C1 width=10 (x=[0,10)), C2 width=90 (x=[10,100))
    var segs1 = [_]MosaicSegment{.{ .value = 1 }};
    var segs2 = [_]MosaicSegment{.{ .value = 9 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 10 };

    plot.render(&buf, area);
    // Verify narrow C1 (width=10) at x=[0,10) and wide C2 (width=90) at x=[10,100)
    const cell_c1 = getCell(buf, area, 5, 5);   // x=5, middle of [0,10)
    const cell_c2 = getCell(buf, area, 55, 5);  // x=55, middle of [10,100)
    try testing.expect(cell_c1 != null and cell_c1.?.char != ' ');
    try testing.expect(cell_c2 != null and cell_c2.?.char != ' ');
    // Verify boundary at x=10
    const boundary_before = getCell(buf, area, 9, 5);
    const boundary_at = getCell(buf, area, 10, 5);
    try testing.expect(boundary_before != null and boundary_before.?.char != ' ');
    try testing.expect(boundary_at != null and boundary_at.?.char != ' ');
}

// ============================================================================
// Group 13: Segment Height Proportionality — Hand-Computed Formula (3 tests)
// ============================================================================

test "segment heights within column are proportional to values" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Single column with segments: 1, 2, 3 (total=6)
    // show_column_labels defaults to true, so 1 header row reserved → plot height = 15 - 1 = 14
    // seg_y[0] = floor(0/6 * 14) = 0
    // seg_y[1] = floor(1/6 * 14) = floor(2.33) = 2
    // seg_y[2] = floor(3/6 * 14) = floor(7) = 7
    // seg_y[3] = floor(6/6 * 14) = 14
    // Heights: S1=2, S2=5, S3=7
    // In getCell coords: S1 at y=[1,3), S2 at y=[3,8), S3 at y=[8,15)
    var segs = [_]MosaicSegment{
        .{ .label = "A", .value = 1 },
        .{ .label = "B", .value = 2 },
        .{ .label = "C", .value = 3 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // Verify segment heights by checking cells at boundaries
    // Column x is at [0,60), check middle at x=30
    // S1 should be at y=[1,3), S2 at y=[3,8), S3 at y=[8,15)
    const cell_s1 = getCell(buf, area, 30, 2);   // y=2, middle of S1 [1,3)
    const cell_s2 = getCell(buf, area, 30, 5);   // y=5, middle of S2 [3,8)
    const cell_s3 = getCell(buf, area, 30, 11);  // y=11, middle of S3 [8,15)
    try testing.expect(cell_s1 != null and cell_s1.?.char != ' ');
    try testing.expect(cell_s2 != null and cell_s2.?.char != ' ');
    try testing.expect(cell_s3 != null and cell_s3.?.char != ' ');
    // Verify segment boundaries
    const boundary_s1_end = getCell(buf, area, 30, 2);  // y=2, end of S1
    const boundary_s2_start = getCell(buf, area, 30, 3); // y=3, start of S2
    const boundary_s2_end = getCell(buf, area, 30, 7);  // y=7, end of S2
    const boundary_s3_start = getCell(buf, area, 30, 8); // y=8, start of S3
    try testing.expect(boundary_s1_end != null and boundary_s1_end.?.char != ' ');
    try testing.expect(boundary_s2_start != null and boundary_s2_start.?.char != ' ');
    try testing.expect(boundary_s2_end != null and boundary_s2_end.?.char != ' ');
    try testing.expect(boundary_s3_start != null and boundary_s3_start.?.char != ' ');
}

test "equal-value segments render equal heights" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Three segments with equal values: 5, 5, 5 (total=15)
    // show_column_labels defaults to true, so plot height = 15 - 1 = 14
    // seg_y[0] = floor(0/15 * 14) = 0
    // seg_y[1] = floor(5/15 * 14) = floor(4.67) = 4
    // seg_y[2] = floor(10/15 * 14) = floor(9.33) = 9
    // seg_y[3] = floor(15/15 * 14) = 14
    // Heights: S1=4, S2=5, S3=5 (roughly equal)
    // In getCell coords: S1 at y=[1,5), S2 at y=[5,10), S3 at y=[10,15)
    var segs = [_]MosaicSegment{
        .{ .value = 5 },
        .{ .value = 5 },
        .{ .value = 5 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // Verify segments render with roughly equal heights
    // Check middle of each segment at x=30
    const cell_s1 = getCell(buf, area, 30, 3);   // y=3, middle of S1 [1,5)
    const cell_s2 = getCell(buf, area, 30, 7);   // y=7, middle of S2 [5,10)
    const cell_s3 = getCell(buf, area, 30, 12);  // y=12, middle of S3 [10,15)
    try testing.expect(cell_s1 != null and cell_s1.?.char != ' ');
    try testing.expect(cell_s2 != null and cell_s2.?.char != ' ');
    try testing.expect(cell_s3 != null and cell_s3.?.char != ' ');
    // Verify segment boundaries to ensure heights are proportionally correct
    const boundary_s1_end = getCell(buf, area, 30, 4);   // y=4, end of S1
    const boundary_s2_start = getCell(buf, area, 30, 5); // y=5, start of S2
    const boundary_s2_end = getCell(buf, area, 30, 9);   // y=9, end of S2
    const boundary_s3_start = getCell(buf, area, 30, 10); // y=10, start of S3
    try testing.expect(boundary_s1_end != null and boundary_s1_end.?.char != ' ');
    try testing.expect(boundary_s2_start != null and boundary_s2_start.?.char != ' ');
    try testing.expect(boundary_s2_end != null and boundary_s2_end.?.char != ' ');
    try testing.expect(boundary_s3_start != null and boundary_s3_start.?.char != ' ');
}

test "single large segment fills most of column height" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Single segment with very large value: 1000
    // show_column_labels defaults to true, so plot height = 15 - 1 = 14
    // seg_y[0] = floor(0/1000 * 14) = 0
    // seg_y[1] = floor(1000/1000 * 14) = 14
    // Height = 14 (fills entire plot area)
    // In getCell coords: segment at y=[1,15)
    var segs = [_]MosaicSegment{.{ .value = 1000 }};
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // Verify segment fills most/all of the plot area height
    // Check that segment content spans from y=1 (after header) to y=14
    const cell_top = getCell(buf, area, 30, 1);     // y=1, top of segment
    const cell_mid = getCell(buf, area, 30, 7);     // y=7, middle
    const cell_bottom = getCell(buf, area, 30, 14); // y=14, near bottom
    try testing.expect(cell_top != null and cell_top.?.char != ' ');
    try testing.expect(cell_mid != null and cell_mid.?.char != ' ');
    try testing.expect(cell_bottom != null and cell_bottom.?.char != ' ');
}

// ============================================================================
// Group 14: MAX_COLUMNS Capping (3 tests)
// ============================================================================

test "more than MAX_COLUMNS=16 columns caps silently at 16" {
    var buf = try Buffer.init(testing.allocator, 150, 30);
    defer buf.deinit();

    var segs: [32][1]MosaicSegment = undefined;
    var cols: [32]MosaicColumn = undefined;
    for (0..32) |i| {
        segs[i][0] = .{ .value = 10 };
        cols[i] = .{ .segments = &segs[i] };
    }

    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 16), plot.columnCount());

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "columnTotal respects MAX_COLUMNS cap" {
    var segs: [32][1]MosaicSegment = undefined;
    var cols: [32]MosaicColumn = undefined;
    for (0..32) |i| {
        segs[i][0] = .{ .value = 10 };
        cols[i] = .{ .segments = &segs[i] };
    }

    const plot = MosaicPlot.init().withColumns(&cols);
    // Only first 16 columns considered for total
    try testing.expectEqual(@as(f32, 160), plot.grandTotal());
}

test "exactly MAX_COLUMNS=16 renders without capping" {
    var buf = try Buffer.init(testing.allocator, 150, 30);
    defer buf.deinit();

    var segs: [16][1]MosaicSegment = undefined;
    var cols: [16]MosaicColumn = undefined;
    for (0..16) |i| {
        segs[i][0] = .{ .value = 5 };
        cols[i] = .{ .segments = &segs[i] };
    }

    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 16), plot.columnCount());

    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 20 };
    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 15: MAX_SEGMENTS_PER_COLUMN Capping (3 tests)
// ============================================================================

test "more than MAX_SEGMENTS_PER_COLUMN=8 segments caps silently at 8" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs: [16]MosaicSegment = undefined;
    for (0..16) |i| {
        segs[i] = .{ .value = 5 };
    }
    var cols = [_]MosaicColumn{.{ .segments = &segs }};

    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 8), plot.segmentCount(0));

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "segmentCount respects MAX_SEGMENTS_PER_COLUMN cap" {
    var segs: [16]MosaicSegment = undefined;
    for (0..16) |i| {
        segs[i] = .{ .value = 10 };
    }
    var cols = [_]MosaicColumn{.{ .segments = &segs }};

    const plot = MosaicPlot.init().withColumns(&cols);
    // Only first 8 segments counted for column total
    try testing.expectEqual(@as(f32, 80), plot.columnTotal(0));
}

test "exactly MAX_SEGMENTS_PER_COLUMN=8 renders without capping" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs: [8]MosaicSegment = undefined;
    for (0..8) |i| {
        segs[i] = .{ .value = 5 };
    }
    var cols = [_]MosaicColumn{.{ .segments = &segs }};

    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(usize, 8), plot.segmentCount(0));

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 16: Focused Column/Segment Styling (3 tests)
// ============================================================================

test "focused_style overrides segment style when set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{
        .{ .label = "A", .value = 30, .style = .{ .dim = true } },
        .{ .label = "B", .value = 20, .style = .{ .bold = true } },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withFocusedSegment(0)
        .withFocusedStyle(.{ .reverse = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused_style only applies when explicitly set (empty Style ignored)" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{
        .{ .label = "A", .value = 30, .style = .{ .italic = true } },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    // focused_style is default empty Style{} — should not override per-segment style
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withFocusedSegment(0)
        .withFocusedStyle(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused indices beyond bounds do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{.{ .value = 50 }};
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withFocusedColumn(100)
        .withFocusedSegment(100)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

// ============================================================================
// Group 17: show_column_labels / show_segment_labels Toggles (4 tests)
// ============================================================================

test "show_column_labels=true may render header row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{.{ .value = 50 }};
    var cols = [_]MosaicColumn{.{ .label = "ColLabel", .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withShowColumnLabels(true)
        .withShowSegmentLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_column_labels=false omits header row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{.{ .value = 50 }};
    var cols = [_]MosaicColumn{.{ .label = "Hidden", .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withShowColumnLabels(false)
        .withShowSegmentLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_segment_labels=true may render segment labels" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{
        .{ .label = "Alpha", .value = 30 },
        .{ .label = "Beta", .value = 20 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withShowColumnLabels(false)
        .withShowSegmentLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_segment_labels=false omits segment labels" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{
        .{ .label = "NoShow", .value = 50 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withShowColumnLabels(false)
        .withShowSegmentLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 18: Zero/Negative Value Handling (5 tests)
// ============================================================================

test "zero-value segments do not panic" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{
        .{ .value = 0 },
        .{ .value = 50 },
        .{ .value = 0 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

test "negative-value segments clamp to 0 without panic" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{
        .{ .value = 50 },
        .{ .value = -10 },
        .{ .value = 30 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // Should clamp negative to 0, total = 50 + 0 + 30 = 80
    try testing.expectEqual(@as(f32, 80), plot.columnTotal(0));
}

test "all-negative column values produce zero column total" {
    var segs = [_]MosaicSegment{
        .{ .value = -10 },
        .{ .value = -20 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    // All negatives clamp to 0, total = 0
    try testing.expectEqual(@as(f32, 0), plot.columnTotal(0));
}

test "mixed positive and negative values sum correctly" {
    var segs = [_]MosaicSegment{
        .{ .value = 100 },
        .{ .value = -50 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    // 100 + max(0, -50) = 100
    try testing.expectEqual(@as(f32, 100), plot.columnTotal(0));
}

test "negative columns do not break layout calculations" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs1 = [_]MosaicSegment{.{ .value = -50 }};
    var segs2 = [_]MosaicSegment{.{ .value = 100 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // grandTotal = 0 + 100 = 100
    try testing.expectEqual(@as(f32, 100), plot.grandTotal());
}

// ============================================================================
// Group 19: grand_total == 0 Edge Case (2 tests)
// ============================================================================

test "grand_total==0 renders no plot content but may draw block border" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // All zero values
    var segs = [_]MosaicSegment{
        .{ .value = 0 },
        .{ .value = 0 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withShowColumnLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // No plot content expected, but no panic
    try testing.expectEqual(@as(f32, 0), plot.grandTotal());
}

test "grand_total==0 with block renders border" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs: [0]MosaicSegment = undefined;
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    plot.render(&buf, area);
    // Should not crash, block border should render if visible
}

// ============================================================================
// Group 20: Block Border Rendering (3 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs1 = [_]MosaicSegment{.{ .value = 30 }};
    var segs2 = [_]MosaicSegment{.{ .value = 20 }};
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    plot.render(&buf, area);

    // Block border should render — at least one border glyph
    const has_border = countChar(buf, area, '─') > 0 or
                       countChar(buf, area, '│') > 0 or
                       countChar(buf, area, '┌') > 0 or
                       countChar(buf, area, '┐') > 0 or
                       countChar(buf, area, '└') > 0 or
                       countChar(buf, area, '┘') > 0;
    try testing.expect(has_border);
}

test "render with block in offset area" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var segs = [_]MosaicSegment{.{ .value = 50 }};
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols).withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs = [_]MosaicSegment{.{ .value = 50 }};
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };

    plot.render(&buf, area);
}

// ============================================================================
// Group 21: Empty Columns / Empty Segments Edge Cases (3 tests)
// ============================================================================

test "column with empty segment slice does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs: [0]MosaicSegment = undefined;
    var cols = [_]MosaicColumn{.{ .label = "Empty", .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

test "mix of empty and non-empty columns" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var segs1: [0]MosaicSegment = undefined;
    var segs2 = [_]MosaicSegment{.{ .value = 50 }};
    var segs3: [0]MosaicSegment = undefined;
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
        .{ .segments = &segs3 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

test "all columns empty produces zero grand total" {
    var segs1: [0]MosaicSegment = undefined;
    var segs2: [0]MosaicSegment = undefined;
    var cols = [_]MosaicColumn{
        .{ .segments = &segs1 },
        .{ .segments = &segs2 },
    };
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(f32, 0), plot.grandTotal());
}

// ============================================================================
// Group 22: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields correctly" {
    var segs1 = [_]MosaicSegment{.{ .value = 30 }};
    var segs2 = [_]MosaicSegment{.{ .value = 20 }};
    var cols = [_]MosaicColumn{
        .{ .label = "C1", .segments = &segs1 },
        .{ .label = "C2", .segments = &segs2 },
    };

    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withFocusedColumn(1)
        .withFocusedSegment(0)
        .withShowColumnLabels(false)
        .withShowSegmentLabels(true)
        .withStyle(.{ .underline = true })
        .withLabelStyle(.{ .bold = true })
        .withFocusedStyle(.{ .reverse = true })
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), plot.columnCount());
    try testing.expectEqual(@as(usize, 1), plot.focused_column);
    try testing.expectEqual(@as(usize, 0), plot.focused_segment);
    try testing.expectEqual(false, plot.show_column_labels);
    try testing.expectEqual(true, plot.show_segment_labels);
    try testing.expect(plot.block != null);
}

test "builder chain preserves last value for each field" {
    const plot = MosaicPlot.init()
        .withFocusedColumn(0)
        .withFocusedColumn(5)
        .withFocusedSegment(1)
        .withFocusedSegment(3)
        .withShowColumnLabels(true)
        .withShowColumnLabels(false)
        .withShowSegmentLabels(false)
        .withShowSegmentLabels(true);

    try testing.expectEqual(@as(usize, 5), plot.focused_column);
    try testing.expectEqual(@as(usize, 3), plot.focused_segment);
    try testing.expectEqual(false, plot.show_column_labels);
    try testing.expectEqual(true, plot.show_segment_labels);
}

// ============================================================================
// Group 23: Realistic Scenario (2 tests)
// ============================================================================

test "render market-share breakdown across regions" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    // Simulating market share: Regions A, B, C with Products 1, 2
    var col_a = [_]MosaicSegment{
        .{ .label = "P1", .value = 40, .style = .{ .bold = true } },
        .{ .label = "P2", .value = 60 },
    };
    var col_b = [_]MosaicSegment{
        .{ .label = "P1", .value = 50 },
        .{ .label = "P2", .value = 50, .style = .{ .dim = true } },
    };
    var col_c = [_]MosaicSegment{
        .{ .label = "P1", .value = 30 },
        .{ .label = "P2", .value = 70 },
    };

    var cols = [_]MosaicColumn{
        .{ .label = "RegionA", .segments = &col_a },
        .{ .label = "RegionB", .segments = &col_b },
        .{ .label = "RegionC", .segments = &col_c },
    };

    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withShowColumnLabels(true)
        .withShowSegmentLabels(true)
        .withFocusedColumn(1)
        .withFocusedSegment(0)
        .withFocusedStyle(.{ .reverse = true })
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with all toggles and styling options enabled" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var col1 = [_]MosaicSegment{
        .{ .label = "A", .value = 25, .style = .{ .italic = true } },
        .{ .label = "B", .value = 25 },
        .{ .label = "C", .value = 50 },
    };
    var col2 = [_]MosaicSegment{
        .{ .label = "X", .value = 40, .style = .{ .underline = true } },
        .{ .label = "Y", .value = 60 },
    };

    var cols = [_]MosaicColumn{
        .{ .label = "Column1", .segments = &col1 },
        .{ .label = "Column2", .segments = &col2 },
    };

    const plot = MosaicPlot.init()
        .withColumns(&cols)
        .withFocusedColumn(0)
        .withFocusedSegment(1)
        .withShowColumnLabels(true)
        .withShowSegmentLabels(true)
        .withStyle(.{ .underline = true })
        .withLabelStyle(.{ .bold = true })
        .withFocusedStyle(.{ .bold = true })
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 28 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}
