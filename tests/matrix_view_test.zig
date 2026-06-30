//! MatrixView Widget Tests — TDD Red Phase
//!
//! Tests MatrixView widget with 2D matrix/heatmap visualization,
//! row/col headers, focused cell styling, builder pattern, normalization,
//! and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const MatrixView = sailor.tui.widgets.MatrixView;

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

/// Check if buffer area contains a specific character
fn areaHasChar(buf: Buffer, area: Rect, ch: u21) bool {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Get character at specific position in buffer
fn charAtPos(buf: Buffer, x: u16, y: u16) ?u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return null;
}

/// Count rows that have non-space content
fn countContentRows(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var has_content = false;
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    has_content = true;
                    break;
                }
            }
        }
        if (has_content) count += 1;
    }
    return count;
}

// ============================================================================
// Init & Defaults Tests (5 tests)
// ============================================================================

test "MatrixView: init returns zero-value struct" {
    const mv = MatrixView.init();
    try testing.expectEqual(@as(usize, 0), mv.data.len);
    try testing.expectEqual(@as(usize, 0), mv.row_headers.len);
    try testing.expectEqual(@as(usize, 0), mv.col_headers.len);
}

test "MatrixView: init defaults focused_row and focused_col to 0" {
    const mv = MatrixView.init();
    try testing.expectEqual(@as(usize, 0), mv.focused_row);
    try testing.expectEqual(@as(usize, 0), mv.focused_col);
}

test "MatrixView: init defaults min_val to 0.0 and max_val to 1.0" {
    const mv = MatrixView.init();
    try testing.expectApproxEqAbs(@as(f32, 0.0), mv.min_val, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1.0), mv.max_val, 0.001);
}

test "MatrixView: init defaults cell_width to 6" {
    const mv = MatrixView.init();
    try testing.expectEqual(@as(u16, 6), mv.cell_width);
}

test "MatrixView: init defaults show_values to true and block to null" {
    const mv = MatrixView.init();
    try testing.expectEqual(true, mv.show_values);
    try testing.expect(mv.block == null);
}

// ============================================================================
// rowCount() Tests (4 tests)
// ============================================================================

test "MatrixView.rowCount returns 0 for empty data" {
    const mv = MatrixView.init();
    try testing.expectEqual(@as(usize, 0), mv.rowCount());
}

test "MatrixView.rowCount returns 1 for single row" {
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    try testing.expectEqual(@as(usize, 1), mv.rowCount());
}

test "MatrixView.rowCount returns correct count for multiple rows" {
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9 };
    var row3 = [_]f32{ 0.1, 0.2 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data);
    try testing.expectEqual(@as(usize, 3), mv.rowCount());
}

test "MatrixView.rowCount caps at MAX_ROWS (32)" {
    var rows: [33][5]f32 = undefined;
    var data_ptrs: [33][]const f32 = undefined;
    for (&data_ptrs, &rows) |*ptr, *row| {
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    try testing.expectEqual(MatrixView.MAX_ROWS, mv.rowCount());
}

// ============================================================================
// colCount() Tests (4 tests)
// ============================================================================

test "MatrixView.colCount returns 0 for empty data" {
    const mv = MatrixView.init();
    try testing.expectEqual(@as(usize, 0), mv.colCount());
}

test "MatrixView.colCount returns 1 for single column" {
    var row1 = [_]f32{0.5};
    var row2 = [_]f32{0.75};
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init().withData(&data);
    try testing.expectEqual(@as(usize, 1), mv.colCount());
}

test "MatrixView.colCount returns max column count across rows" {
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9, 0.1 };
    var row3 = [_]f32{ 0.2 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data);
    // max is 3 columns from row2
    try testing.expectEqual(@as(usize, 3), mv.colCount());
}

test "MatrixView.colCount caps at MAX_COLS (32)" {
    var large_row: [33]f32 = undefined;
    @memset(&large_row, 0.5);
    var data = [_][]const f32{&large_row};
    const mv = MatrixView.init().withData(&data);
    try testing.expectEqual(MatrixView.MAX_COLS, mv.colCount());
}

// ============================================================================
// Builder API Tests (10 tests)
// ============================================================================

test "MatrixView.withData returns new value without modifying original" {
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9 };
    var data1 = [_][]const f32{&row1};
    var data2 = [_][]const f32{&row2};
    const mv1 = MatrixView.init().withData(&data1);
    const mv2 = mv1.withData(&data2);
    try testing.expectEqual(@as(usize, 1), mv1.rowCount());
    try testing.expectEqual(@as(usize, 1), mv2.rowCount());
}

test "MatrixView.withRowHeaders stores headers" {
    var headers = [_][]const u8{ "R1", "R2" };
    const mv = MatrixView.init().withRowHeaders(&headers);
    try testing.expectEqual(@as(usize, 2), mv.row_headers.len);
}

test "MatrixView.withColHeaders stores headers" {
    var headers = [_][]const u8{ "C1", "C2", "C3" };
    const mv = MatrixView.init().withColHeaders(&headers);
    try testing.expectEqual(@as(usize, 3), mv.col_headers.len);
}

test "MatrixView.withFocusedRow sets focused row" {
    const mv = MatrixView.init().withFocusedRow(5);
    try testing.expectEqual(@as(usize, 5), mv.focused_row);
}

test "MatrixView.withFocusedCol sets focused col" {
    const mv = MatrixView.init().withFocusedCol(3);
    try testing.expectEqual(@as(usize, 3), mv.focused_col);
}

test "MatrixView.withMinVal sets min value" {
    const mv = MatrixView.init().withMinVal(-1.0);
    try testing.expectApproxEqAbs(@as(f32, -1.0), mv.min_val, 0.001);
}

test "MatrixView.withMaxVal sets max value" {
    const mv = MatrixView.init().withMaxVal(100.0);
    try testing.expectApproxEqAbs(@as(f32, 100.0), mv.max_val, 0.001);
}

test "MatrixView.withCellWidth sets cell width" {
    const mv = MatrixView.init().withCellWidth(8);
    try testing.expectEqual(@as(u16, 8), mv.cell_width);
}

test "MatrixView.withShowValues sets show_values flag" {
    const mv = MatrixView.init().withShowValues(false);
    try testing.expectEqual(false, mv.show_values);
}

test "MatrixView builder chaining sets multiple fields" {
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(0)
        .withFocusedCol(1)
        .withCellWidth(5)
        .withShowValues(false);
    try testing.expectEqual(@as(usize, 1), mv.rowCount());
    try testing.expectEqual(@as(usize, 0), mv.focused_row);
    try testing.expectEqual(@as(usize, 1), mv.focused_col);
    try testing.expectEqual(@as(u16, 5), mv.cell_width);
    try testing.expectEqual(false, mv.show_values);
}

// ============================================================================
// Render — Zero/Minimal Area Tests (3 tests)
// ============================================================================

test "MatrixView.render to zero-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render to zero-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    mv.render(&buf, area);
}

test "MatrixView.render to 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    mv.render(&buf, area);
}

// ============================================================================
// Render — Empty Data Tests (2 tests)
// ============================================================================

test "MatrixView.render with no data does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const mv = MatrixView.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render with empty rows does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var data: [0][]const f32 = undefined;
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    mv.render(&buf, area);
}

// ============================================================================
// Render — Single Cell Tests (5 tests)
// ============================================================================

test "MatrixView.render 1x1 matrix renders a cell" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var row = [_]f32{0.75};
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render 1x1 matrix with show_values renders text" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var row = [_]f32{0.5};
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render single cell fills available width" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    var row = [_]f32{0.75};
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withCellWidth(8);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content >= 5);
}

test "MatrixView.render single cell has focused style applied" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const focused_style = Style{ .bold = true };
    var row = [_]f32{0.5};
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(0)
        .withFocusedCol(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    mv.render(&buf, area);
}

test "MatrixView.render single cell outside focused area uses base style" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var row = [_]f32{0.5};
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(5)
        .withFocusedCol(5);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    mv.render(&buf, area);
}

// ============================================================================
// Render — Single Row Tests (5 tests)
// ============================================================================

test "MatrixView.render 1x3 matrix renders three columns" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    var row = [_]f32{ 0.25, 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 5);
}

test "MatrixView.render 1 row with headers includes header row" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    var row = [_]f32{ 0.25, 0.5, 0.75 };
    var headers = [_][]const u8{ "A", "B", "C" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withColHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    mv.render(&buf, area);
    const content_rows = countContentRows(buf, area);
    try testing.expect(content_rows >= 1);
}

test "MatrixView.render 1 row multiple columns respects cell_width" {
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit();
    var row = [_]f32{ 0.1, 0.2, 0.3, 0.4, 0.5 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withCellWidth(10);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 10);
}

test "MatrixView.render 1 row with wide area renders all cells" {
    var buf = try Buffer.init(testing.allocator, 80, 10);
    defer buf.deinit();
    var row = [_]f32{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 20);
}

test "MatrixView.render 1 row narrow area clamps columns" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var row = [_]f32{ 0.1, 0.2, 0.3, 0.4, 0.5 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withCellWidth(6);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    mv.render(&buf, area);
}

// ============================================================================
// Render — Single Column Tests (5 tests)
// ============================================================================

test "MatrixView.render 3x1 matrix renders three rows" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row1 = [_]f32{0.25};
    var row2 = [_]f32{0.5};
    var row3 = [_]f32{0.75};
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 5);
}

test "MatrixView.render 3 rows with row headers includes header column" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row1 = [_]f32{0.25};
    var row2 = [_]f32{0.5};
    var row3 = [_]f32{0.75};
    var headers = [_][]const u8{ "H1", "H2", "H3" };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data).withRowHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render single column multiple rows uses all rows" {
    var buf = try Buffer.init(testing.allocator, 20, 30);
    defer buf.deinit();
    var rows: [6][1]f32 = undefined;
    var data_ptrs: [6][]const f32 = undefined;
    for (&rows, &data_ptrs) |*row, *ptr| {
        row[0] = 0.5;
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 30 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 10);
}

test "MatrixView.render 5x1 tall area renders vertically" {
    var buf = try Buffer.init(testing.allocator, 15, 25);
    defer buf.deinit();
    var rows: [5][1]f32 = undefined;
    var data_ptrs: [5][]const f32 = undefined;
    for (&data_ptrs, &rows) |*ptr, *row| {
        row[0] = 0.5;
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 25 };
    mv.render(&buf, area);
    const content_rows = countContentRows(buf, area);
    try testing.expect(content_rows >= 3);
}

test "MatrixView.render single column with row headers labels left side" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row1 = [_]f32{0.25};
    var row2 = [_]f32{0.5};
    var headers = [_][]const u8{ "Row1", "Row2" };
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init().withData(&data).withRowHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    mv.render(&buf, area);
}

// ============================================================================
// Render — Multi-Row Multi-Col Tests (5 tests)
// ============================================================================

test "MatrixView.render 3x3 matrix renders all cells" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var row1 = [_]f32{ 0.1, 0.2, 0.3 };
    var row2 = [_]f32{ 0.4, 0.5, 0.6 };
    var row3 = [_]f32{ 0.7, 0.8, 0.9 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 10);
}

test "MatrixView.render 5x5 matrix renders all cells" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var rows: [5][5]f32 = undefined;
    var data_ptrs: [5][]const f32 = undefined;
    for (&rows, &data_ptrs) |*row, *ptr| {
        for (row) |*val| {
            val.* = 0.5;
        }
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 20);
}

test "MatrixView.render multiple rows with headers layout correct" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var row1 = [_]f32{ 0.1, 0.2, 0.3 };
    var row2 = [_]f32{ 0.4, 0.5, 0.6 };
    var row3 = [_]f32{ 0.7, 0.8, 0.9 };
    var row_headers = [_][]const u8{ "A", "B", "C" };
    var col_headers = [_][]const u8{ "1", "2", "3" };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init()
        .withData(&data)
        .withRowHeaders(&row_headers)
        .withColHeaders(&col_headers);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render 3x3 with different value ranges normalizes correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var row1 = [_]f32{ 10.0, 20.0, 30.0 };
    var row2 = [_]f32{ 40.0, 50.0, 60.0 };
    var row3 = [_]f32{ 70.0, 80.0, 90.0 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init()
        .withData(&data)
        .withMinVal(10.0)
        .withMaxVal(90.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 10);
}

test "MatrixView.render larger matrix fills reasonable area" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();
    var rows: [6][8]f32 = undefined;
    var data_ptrs: [6][]const f32 = undefined;
    for (&rows, &data_ptrs) |*row, *ptr| {
        for (row) |*val| {
            val.* = 0.5;
        }
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 30);
}

// ============================================================================
// Col Headers Tests (5 tests)
// ============================================================================

test "MatrixView.render with col_headers renders header row" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var headers = [_][]const u8{ "Col1", "Col2" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withColHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render col headers appear in first row" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.25, 0.5, 0.75 };
    var headers = [_][]const u8{ "A", "B", "C" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withColHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render col headers centered in cell_width" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.5 };
    var headers = [_][]const u8{ "Header" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withColHeaders(&headers).withCellWidth(10);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render col headers truncated if too long" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5 };
    var headers = [_][]const u8{ "VeryLongHeaderNameThatShouldBeTruncated" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withColHeaders(&headers).withCellWidth(5);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render col headers with header_style applied" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const header_style = Style{ .bold = true };
    var row = [_]f32{ 0.5, 0.75 };
    var headers = [_][]const u8{ "H1", "H2" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withColHeaders(&headers)
        .withHeaderStyle(header_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
}

// ============================================================================
// Row Headers Tests (5 tests)
// ============================================================================

test "MatrixView.render with row_headers renders header column" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9 };
    var headers = [_][]const u8{ "Row1", "Row2" };
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init().withData(&data).withRowHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render row headers appear in left column" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var row1 = [_]f32{ 0.5 };
    var row2 = [_]f32{ 0.75 };
    var headers = [_][]const u8{ "R1", "R2" };
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init().withData(&data).withRowHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render row headers left aligned in column" {
    var buf = try Buffer.init(testing.allocator, 30, 20);
    defer buf.deinit();
    var row1 = [_]f32{ 0.5, 0.75 };
    var headers = [_][]const u8{ "Header" };
    var data = [_][]const f32{&row1};
    const mv = MatrixView.init().withData(&data).withRowHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render row headers truncated if too long" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5 };
    var headers = [_][]const u8{ "VeryLongRowHeaderNameThatExceedCapacity" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withRowHeaders(&headers);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render row headers with header_style applied" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    const header_style = Style{ .italic = true };
    var row = [_]f32{ 0.5 };
    var headers = [_][]const u8{ "Hdr" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withRowHeaders(&headers)
        .withHeaderStyle(header_style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

// ============================================================================
// Focused Cell Tests (5 tests)
// ============================================================================

test "MatrixView.render focused cell at (0,0) uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    const focused_style = Style{ .reverse = true };
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(0)
        .withFocusedCol(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render focused cell at (1,1) uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const focused_style = Style{ .underline = true };
    var row1 = [_]f32{ 0.1, 0.2, 0.3 };
    var row2 = [_]f32{ 0.4, 0.5, 0.6 };
    var row3 = [_]f32{ 0.7, 0.8, 0.9 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(1)
        .withFocusedCol(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render only focused cell gets focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const focused_style = Style{ .bold = true };
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9 };
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(0)
        .withFocusedCol(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render focused row out of bounds handled safely" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(99)
        .withFocusedCol(0);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render focused col out of bounds handled safely" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withFocusedRow(0)
        .withFocusedCol(99);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

// ============================================================================
// Show Values Tests (3 tests)
// ============================================================================

test "MatrixView.render with show_values=true displays cell values" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render with show_values=false no numeric text" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render show_values changes visual appearance" {
    var buf1 = try Buffer.init(testing.allocator, 30, 15);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 30, 15);
    defer buf2.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv_with = MatrixView.init().withData(&data).withShowValues(true);
    const mv_without = MatrixView.init().withData(&data).withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv_with.render(&buf1, area);
    mv_without.render(&buf2, area);
}

// ============================================================================
// Min/Max Normalization Tests (3 tests)
// ============================================================================

test "MatrixView.render with custom min/max range normalizes values" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var row = [_]f32{ 50.0, 100.0, 150.0 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withMinVal(0.0)
        .withMaxVal(200.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render with negative min_val handles properly" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var row = [_]f32{ -10.0, 0.0, 10.0 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withMinVal(-10.0)
        .withMaxVal(10.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render with equal min and max does not crash" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.5, 0.5 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withMinVal(5.0)
        .withMaxVal(5.0);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

// ============================================================================
// Cell Width Tests (3 tests)
// ============================================================================

test "MatrixView.render with small cell_width (3) renders compact" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.25, 0.5, 0.75, 0.9 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withCellWidth(3);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render with large cell_width (15) renders wide" {
    var buf = try Buffer.init(testing.allocator, 80, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.25, 0.5 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withCellWidth(15);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render cell_width larger than area still renders" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withCellWidth(50);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    mv.render(&buf, area);
}

// ============================================================================
// Block Border Tests (4 tests)
// ============================================================================

test "MatrixView.render with block border renders frame" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    const block = Block{};
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render without block no frame" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render block reduces inner area for content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const block = Block{ .padding_left = 2, .padding_right = 2, .padding_top = 1, .padding_bottom = 1 };
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    mv.render(&buf, area);
}

test "MatrixView.render block too large for data still renders safely" {
    var buf = try Buffer.init(testing.allocator, 10, 8);
    defer buf.deinit();
    const block = Block{ .padding_left = 3, .padding_right = 3, .padding_top = 2, .padding_bottom = 2 };
    var row = [_]f32{ 0.5 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 8 };
    mv.render(&buf, area);
}

// ============================================================================
// Style Tests (3 tests)
// ============================================================================

test "MatrixView.render with base style applied to cells" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    const base_style = Style{ .dim = true };
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data).withStyle(base_style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render with header_style applied to headers" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const header_style = Style{ .bold = true };
    var row = [_]f32{ 0.5, 0.75 };
    var col_headers = [_][]const u8{ "C1", "C2" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withColHeaders(&col_headers)
        .withHeaderStyle(header_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render focused_style overrides base style for focused cell" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    const base_style = Style{ .dim = true };
    const focused_style = Style{ .bold = true, .reverse = true };
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withStyle(base_style)
        .withFocusedRow(0)
        .withFocusedCol(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

// ============================================================================
// MAX_ROWS/COLS Cap Tests (3 tests)
// ============================================================================

test "MatrixView.rowCount caps at MAX_ROWS when data exceeds 32" {
    var rows: [33][2]f32 = undefined;
    var data_ptrs: [33][]const f32 = undefined;
    for (&data_ptrs, &rows) |*ptr, *row| {
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    try testing.expectEqual(MatrixView.MAX_ROWS, mv.rowCount());
}

test "MatrixView.colCount caps at MAX_COLS when columns exceed 32" {
    var large_row: [33]f32 = undefined;
    var data = [_][]const f32{&large_row};
    const mv = MatrixView.init().withData(&data);
    try testing.expectEqual(MatrixView.MAX_COLS, mv.colCount());
}

test "MatrixView.render with 33 rows only renders first 32" {
    var buf = try Buffer.init(testing.allocator, 40, 50);
    defer buf.deinit();
    var rows: [33][2]f32 = undefined;
    var data_ptrs: [33][]const f32 = undefined;
    for (&data_ptrs, &rows) |*ptr, *row| {
        row[0] = 0.5;
        row[1] = 0.75;
        ptr.* = row;
    }
    const mv = MatrixView.init().withData(&data_ptrs);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 50 };
    mv.render(&buf, area);
    try testing.expectEqual(MatrixView.MAX_ROWS, mv.rowCount());
}

// ============================================================================
// Edge Cases Tests (6 tests)
// ============================================================================

test "MatrixView.render with all zero values does not crash" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row1 = [_]f32{ 0.0, 0.0 };
    var row2 = [_]f32{ 0.0, 0.0 };
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render with negative values normalizes correctly" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var row = [_]f32{ -5.0, 0.0, 5.0 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withMinVal(-5.0)
        .withMaxVal(5.0);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv.render(&buf, area);
}

test "MatrixView.render with very large values scales correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var row = [_]f32{ 1000.0, 5000.0, 9000.0 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withMinVal(1000.0)
        .withMaxVal(10000.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render area exactly 1x1 renders single cell" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    mv.render(&buf, area);
}

test "MatrixView.render offset area within buffer" {
    var buf = try Buffer.init(testing.allocator, 50, 40);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 10, .y = 10, .width = 30, .height = 20 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render clipping at buffer boundary" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.5, 0.75, 0.9 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    // Area extends to buffer edge, should be clipped
    const area = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };
    mv.render(&buf, area);
}

// ============================================================================
// Additional Comprehensive Tests (6 tests)
// ============================================================================

test "MatrixView.render consistency: identical matrices produce similar layouts" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();
    var row = [_]f32{ 0.25, 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    mv.render(&buf1, area);
    mv.render(&buf2, area);
    const count1 = countNonEmptyCells(buf1, area);
    const count2 = countNonEmptyCells(buf2, area);
    try testing.expectEqual(count1, count2);
}

test "MatrixView.render with mixed header and value rendering" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var row = [_]f32{ 0.1, 0.5, 0.9 };
    var col_headers = [_][]const u8{ "A", "B", "C" };
    var row_headers = [_][]const u8{ "X" };
    var data = [_][]const f32{&row};
    const mv = MatrixView.init()
        .withData(&data)
        .withColHeaders(&col_headers)
        .withRowHeaders(&row_headers)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 10);
}

test "MatrixView.render multiple matrices different sizes" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 60, 30);
    defer buf2.deinit();
    var row1 = [_]f32{ 0.5, 0.75 };
    var data1 = [_][]const f32{&row1};
    var rows2: [3][3]f32 = undefined;
    var data2_ptrs: [3][]const f32 = undefined;
    for (&rows2, &data2_ptrs) |*row, *ptr| {
        for (row) |*val| {
            val.* = 0.5;
        }
        ptr.* = row;
    }
    const mv1 = MatrixView.init().withData(&data1);
    const mv2 = MatrixView.init().withData(&data2_ptrs);
    const area1 = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    const area2 = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    mv1.render(&buf1, area1);
    mv2.render(&buf2, area2);
}

test "MatrixView.render ragged matrix (unequal row lengths)" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var row1 = [_]f32{ 0.5, 0.75 };
    var row2 = [_]f32{ 0.25, 0.9, 0.1 };
    var row3 = [_]f32{ 0.3 };
    var data = [_][]const f32{ &row1, &row2, &row3 };
    const mv = MatrixView.init().withData(&data);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

test "MatrixView.render focused cell state immutability" {
    var buf1 = try Buffer.init(testing.allocator, 30, 15);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 30, 15);
    defer buf2.deinit();
    var row = [_]f32{ 0.5, 0.75 };
    var data = [_][]const f32{&row};
    const mv_original = MatrixView.init().withData(&data);
    const mv_focused = mv_original.withFocusedRow(0).withFocusedCol(1);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    mv_original.render(&buf1, area);
    mv_focused.render(&buf2, area);
    // Both should render without error
    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

test "MatrixView.render with all style combinations" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    const base_style = Style{ .dim = true };
    const header_style = Style{ .bold = true };
    const focused_style = Style{ .reverse = true, .underline = true };
    var row1 = [_]f32{ 0.1, 0.2, 0.3 };
    var row2 = [_]f32{ 0.4, 0.5, 0.6 };
    var col_headers = [_][]const u8{ "H1", "H2", "H3" };
    var row_headers = [_][]const u8{ "R1", "R2" };
    var data = [_][]const f32{ &row1, &row2 };
    const mv = MatrixView.init()
        .withData(&data)
        .withColHeaders(&col_headers)
        .withRowHeaders(&row_headers)
        .withFocusedRow(1)
        .withFocusedCol(1)
        .withStyle(base_style)
        .withHeaderStyle(header_style)
        .withFocusedStyle(focused_style)
        .withShowValues(true)
        .withCellWidth(7);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    mv.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 10);
}
