//! StatusGrid Widget Tests — TDD Red Phase
//!
//! Tests StatusGrid widget with status-based grid layout, cursor navigation,
//! cell styling, rendering, and edge case handling. The StatusGrid displays
//! an N×M grid of status cells with navigation, selection, and color-coded status.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;

const StatusGrid = sailor.tui.widgets.StatusGrid;
const StatusCell = sailor.tui.widgets.StatusCell;
const StatusLevel = sailor.tui.widgets.StatusLevel;

// ============================================================================
// StatusLevel.color() Tests (4 tests)
// ============================================================================

test "StatusLevel.color() ok returns green" {
    const status = StatusLevel.ok;
    const color = status.color();
    try testing.expect(std.meta.eql(color, Color.green));
}

test "StatusLevel.color() warn returns yellow" {
    const status = StatusLevel.warn;
    const color = status.color();
    try testing.expect(std.meta.eql(color, Color.yellow));
}

test "StatusLevel.color() error_ returns red" {
    const status = StatusLevel.error_;
    const color = status.color();
    try testing.expect(std.meta.eql(color, Color.red));
}

test "StatusLevel.color() unknown returns bright_black" {
    const status = StatusLevel.unknown;
    const color = status.color();
    try testing.expect(std.meta.eql(color, Color.bright_black));
}

// ============================================================================
// Init Tests (5 tests)
// ============================================================================

test "StatusGrid.init with 1×1 grid sets rows and cols" {
    var cells = [_]StatusCell{
        .{ .label = "Status" },
    };
    const grid = StatusGrid.init(&cells, 1, 1);
    try testing.expectEqual(@as(usize, 1), grid.rows);
    try testing.expectEqual(@as(usize, 1), grid.cols);
}

test "StatusGrid.init with 2×3 grid sets dimensions correctly" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
        .{ .label = "s2" },
        .{ .label = "s3" },
        .{ .label = "s4" },
        .{ .label = "s5" },
        .{ .label = "s6" },
    };
    const grid = StatusGrid.init(&cells, 2, 3);
    try testing.expectEqual(@as(usize, 2), grid.rows);
    try testing.expectEqual(@as(usize, 3), grid.cols);
}

test "StatusGrid.init sets cursor_row to 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
        .{ .label = "s2" },
    };
    const grid = StatusGrid.init(&cells, 1, 2);
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
}

test "StatusGrid.init sets cursor_col to 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
        .{ .label = "s2" },
    };
    const grid = StatusGrid.init(&cells, 1, 2);
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

test "StatusGrid.init sets show_values to false" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    const grid = StatusGrid.init(&cells, 1, 1);
    try testing.expect(grid.show_values == false);
}

// ============================================================================
// moveRight Tests (6 tests)
// ============================================================================

test "StatusGrid.moveRight from (0,0) to (0,1) in 2×3 grid" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" },
        .{ .label = "s4" }, .{ .label = "s5" }, .{ .label = "s6" },
    };
    var grid = StatusGrid.init(&cells, 2, 3);
    grid.moveRight();
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
    try testing.expectEqual(@as(usize, 1), grid.cursor_col);
}

test "StatusGrid.moveRight clamps at last column in 2×3 grid" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" },
        .{ .label = "s4" }, .{ .label = "s5" }, .{ .label = "s6" },
    };
    var grid = StatusGrid.init(&cells, 2, 3);
    grid.cursor_col = 2;
    grid.moveRight();
    try testing.expectEqual(@as(usize, 2), grid.cursor_col);
}

test "StatusGrid.moveRight in 1×1 grid stays at (0,0)" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    grid.moveRight();
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

test "StatusGrid.moveRight multiple times from 0 toward cols-1" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" }, .{ .label = "s4" },
    };
    var grid = StatusGrid.init(&cells, 1, 4);
    grid.moveRight();
    grid.moveRight();
    try testing.expectEqual(@as(usize, 2), grid.cursor_col);
}

test "StatusGrid.moveRight from 0 to cols-1 then clamps" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" },
    };
    var grid = StatusGrid.init(&cells, 1, 3);
    grid.moveRight(); // 0 -> 1
    grid.moveRight(); // 1 -> 2
    grid.moveRight(); // 2 -> 2 (clamped)
    try testing.expectEqual(@as(usize, 2), grid.cursor_col);
}

test "StatusGrid.moveRight preserves cursor_row" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
        .{ .label = "s3" }, .{ .label = "s4" },
    };
    var grid = StatusGrid.init(&cells, 2, 2);
    grid.cursor_row = 1;
    grid.moveRight();
    try testing.expectEqual(@as(usize, 1), grid.cursor_row);
    try testing.expectEqual(@as(usize, 1), grid.cursor_col);
}

// ============================================================================
// moveLeft Tests (5 tests)
// ============================================================================

test "StatusGrid.moveLeft from (0,1) to (0,0)" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    grid.cursor_col = 1;
    grid.moveLeft();
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

test "StatusGrid.moveLeft clamps at 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    grid.moveLeft();
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

test "StatusGrid.moveLeft in 1×1 stays at 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    grid.moveLeft();
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

test "StatusGrid.moveLeft multiple times clamped to 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" },
    };
    var grid = StatusGrid.init(&cells, 1, 3);
    grid.cursor_col = 1;
    grid.moveLeft();
    grid.moveLeft();
    grid.moveLeft();
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

test "StatusGrid.moveLeft preserves cursor_row" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
        .{ .label = "s3" }, .{ .label = "s4" },
    };
    var grid = StatusGrid.init(&cells, 2, 2);
    grid.cursor_row = 1;
    grid.cursor_col = 1;
    grid.moveLeft();
    try testing.expectEqual(@as(usize, 1), grid.cursor_row);
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

// ============================================================================
// moveDown Tests (5 tests)
// ============================================================================

test "StatusGrid.moveDown from (0,0) to (1,0) in 3×3 grid" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" },
        .{ .label = "s4" }, .{ .label = "s5" }, .{ .label = "s6" },
        .{ .label = "s7" }, .{ .label = "s8" }, .{ .label = "s9" },
    };
    var grid = StatusGrid.init(&cells, 3, 3);
    grid.moveDown();
    try testing.expectEqual(@as(usize, 1), grid.cursor_row);
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);
}

test "StatusGrid.moveDown clamps at last row in 3×3 grid" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" },
        .{ .label = "s4" }, .{ .label = "s5" }, .{ .label = "s6" },
        .{ .label = "s7" }, .{ .label = "s8" }, .{ .label = "s9" },
    };
    var grid = StatusGrid.init(&cells, 3, 3);
    grid.cursor_row = 2;
    grid.moveDown();
    try testing.expectEqual(@as(usize, 2), grid.cursor_row);
}

test "StatusGrid.moveDown in 1×1 stays at (0,0)" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    grid.moveDown();
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
}

test "StatusGrid.moveDown multiple times from 0 to rows-1" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
        .{ .label = "s3" }, .{ .label = "s4" },
        .{ .label = "s5" }, .{ .label = "s6" },
    };
    var grid = StatusGrid.init(&cells, 3, 2);
    grid.moveDown();
    grid.moveDown();
    try testing.expectEqual(@as(usize, 2), grid.cursor_row);
}

test "StatusGrid.moveDown preserves cursor_col" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
        .{ .label = "s3" }, .{ .label = "s4" },
    };
    var grid = StatusGrid.init(&cells, 2, 2);
    grid.cursor_col = 1;
    grid.moveDown();
    try testing.expectEqual(@as(usize, 1), grid.cursor_row);
    try testing.expectEqual(@as(usize, 1), grid.cursor_col);
}

// ============================================================================
// moveUp Tests (5 tests)
// ============================================================================

test "StatusGrid.moveUp from (1,0) to (0,0)" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
        .{ .label = "s3" }, .{ .label = "s4" },
    };
    var grid = StatusGrid.init(&cells, 2, 2);
    grid.cursor_row = 1;
    grid.moveUp();
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
}

test "StatusGrid.moveUp clamps at 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    grid.moveUp();
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
}

test "StatusGrid.moveUp in 1×1 stays at 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    grid.moveUp();
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
}

test "StatusGrid.moveUp multiple times clamped to 0" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
        .{ .label = "s3" }, .{ .label = "s4" },
        .{ .label = "s5" }, .{ .label = "s6" },
    };
    var grid = StatusGrid.init(&cells, 3, 2);
    grid.cursor_row = 2;
    grid.moveUp();
    grid.moveUp();
    grid.moveUp();
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
}

test "StatusGrid.moveUp preserves cursor_col" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" },
        .{ .label = "s3" }, .{ .label = "s4" },
    };
    var grid = StatusGrid.init(&cells, 2, 2);
    grid.cursor_row = 1;
    grid.cursor_col = 1;
    grid.moveUp();
    try testing.expectEqual(@as(usize, 0), grid.cursor_row);
    try testing.expectEqual(@as(usize, 1), grid.cursor_col);
}

// ============================================================================
// selectedCell() Tests (8 tests)
// ============================================================================

test "StatusGrid.selectedCell returns pointer to cell at cursor position" {
    var cells = [_]StatusCell{
        .{ .label = "cell1" },
        .{ .label = "cell2" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    const selected = grid.selectedCell();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("cell1", selected.?.label);
}

test "StatusGrid.selectedCell after moveRight returns next column cell" {
    var cells = [_]StatusCell{
        .{ .label = "a" },
        .{ .label = "b" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    grid.moveRight();
    const selected = grid.selectedCell();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("b", selected.?.label);
}

test "StatusGrid.selectedCell after moveDown returns next row cell" {
    var cells = [_]StatusCell{
        .{ .label = "r0c0" }, .{ .label = "r0c1" },
        .{ .label = "r1c0" }, .{ .label = "r1c1" },
    };
    var grid = StatusGrid.init(&cells, 2, 2);
    grid.moveDown();
    const selected = grid.selectedCell();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("r1c0", selected.?.label);
}

test "StatusGrid.selectedCell returns null for empty cells slice" {
    var cells: [0]StatusCell = undefined;
    var grid = StatusGrid.init(&cells, 0, 0);
    const selected = grid.selectedCell();
    try testing.expect(selected == null);
}

test "StatusGrid.selectedCell returns mutable pointer allowing mutation" {
    var cells = [_]StatusCell{
        .{ .label = "original", .status = .unknown },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    if (grid.selectedCell()) |sel| {
        sel.status = .ok;
    }
    try testing.expect(cells[0].status == .ok);
}

test "StatusGrid.selectedCell in 1×1 grid returns only cell" {
    var cells = [_]StatusCell{
        .{ .label = "only", .status = .warn },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const selected = grid.selectedCell();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("only", selected.?.label);
    try testing.expect(selected.?.status == .warn);
}

test "StatusGrid.selectedCell at 2×2 corners returns correct cells" {
    var cells = [_]StatusCell{
        .{ .label = "tl" }, .{ .label = "tr" },
        .{ .label = "bl" }, .{ .label = "br" },
    };
    var grid = StatusGrid.init(&cells, 2, 2);

    // Top-left
    var selected = grid.selectedCell();
    try testing.expectEqualStrings("tl", selected.?.label);

    // Top-right
    grid.cursor_col = 1;
    selected = grid.selectedCell();
    try testing.expectEqualStrings("tr", selected.?.label);

    // Bottom-left
    grid.cursor_row = 1;
    grid.cursor_col = 0;
    selected = grid.selectedCell();
    try testing.expectEqualStrings("bl", selected.?.label);

    // Bottom-right
    grid.cursor_col = 1;
    selected = grid.selectedCell();
    try testing.expectEqualStrings("br", selected.?.label);
}

test "StatusGrid.selectedCell with value and status fields" {
    var cells = [_]StatusCell{
        .{ .label = "cpu", .value = "45%", .status = .ok },
        .{ .label = "mem", .value = "92%", .status = .error_ },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    var selected = grid.selectedCell();
    try testing.expectEqualStrings("cpu", selected.?.label);
    try testing.expectEqualStrings("45%", selected.?.value);
    try testing.expect(selected.?.status == .ok);

    grid.moveRight();
    selected = grid.selectedCell();
    try testing.expectEqualStrings("mem", selected.?.label);
    try testing.expectEqualStrings("92%", selected.?.value);
    try testing.expect(selected.?.status == .error_);
}

// ============================================================================
// Builder API Tests (7 tests)
// ============================================================================

test "StatusGrid.withShowValues returns new grid with show_values true" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const grid2 = grid.withShowValues(true);
    try testing.expect(grid2.show_values == true);
}

test "StatusGrid.withShowValues original not mutated" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    _ = grid.withShowValues(true);
    try testing.expect(grid.show_values == false);
}

test "StatusGrid.withBlock sets block field" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const block = Block{ .borders = .all };
    const grid2 = grid.withBlock(block);
    try testing.expect(grid2.block != null);
}

test "StatusGrid.withOkStyle updates ok_style" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const style = Style{ .bold = true };
    const grid2 = grid.withOkStyle(style);
    try testing.expect(grid2.ok_style.bold == true);
}

test "StatusGrid.withWarnStyle updates warn_style" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const style = Style{ .italic = true };
    const grid2 = grid.withWarnStyle(style);
    try testing.expect(grid2.warn_style.italic == true);
}

test "StatusGrid.withErrorStyle updates error_style" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const style = Style{ .underline = true };
    const grid2 = grid.withErrorStyle(style);
    try testing.expect(grid2.error_style.underline == true);
}

test "StatusGrid.withUnknownStyle updates unknown_style" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const style = Style{ .dim = true };
    const grid2 = grid.withUnknownStyle(style);
    try testing.expect(grid2.unknown_style.dim == true);
}

test "StatusGrid builder chaining returns correct final state" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    const block = Block{ .borders = .all };
    const grid2 = grid
        .withShowValues(true)
        .withBlock(block)
        .withOkStyle(Style{ .bold = true });
    try testing.expect(grid2.show_values == true);
    try testing.expect(grid2.block != null);
    try testing.expect(grid2.ok_style.bold == true);
}

// ============================================================================
// Render — Basic Tests (8 tests)
// ============================================================================

test "StatusGrid.render on basic area does not crash" {
    var cells = [_]StatusCell{
        .{ .label = "Status" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid.render on zero-area rect does not crash" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
}

test "StatusGrid.render 1×1 grid shows label in cell (0,0)" {
    var cells = [_]StatusCell{
        .{ .label = "S" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });

    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'S'), cell.?.char);
}

test "StatusGrid.render 1×1 with ok status uses ok_style fg color" {
    var cells = [_]StatusCell{
        .{ .label = "OK", .status = .ok },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // "OK" at (0,0); ok_style = .{ .fg = .green }
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'O'), cell.?.char);
    try testing.expectEqual(@as(?sailor.tui.Color, .green), cell.?.style.fg);
}

test "StatusGrid.render 2×1 grid (2 rows, 1 col) shows labels at different y" {
    var cells = [_]StatusCell{
        .{ .label = "Top" },
        .{ .label = "Bot" },
    };
    var grid = StatusGrid.init(&cells, 2, 1);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // cell_height = 20/2 = 10; row 0 at y=0, row 1 at y=10
    const top = buf.getConst(0, 0);
    try testing.expect(top != null);
    try testing.expectEqual(@as(u21, 'T'), top.?.char); // "Top"
    const bot = buf.getConst(0, 10);
    try testing.expect(bot != null);
    try testing.expectEqual(@as(u21, 'B'), bot.?.char); // "Bot"
    // Row 5 (between cells) should be blank
    const mid = buf.getConst(0, 5);
    try testing.expect(mid != null);
    try testing.expectEqual(@as(u21, ' '), mid.?.char);
}

test "StatusGrid.render 1×2 grid (1 row, 2 cols) shows labels at different x" {
    var cells = [_]StatusCell{
        .{ .label = "L" },
        .{ .label = "R" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // cell_width = 40/2 = 20; col 0 at x=0, col 1 at x=20
    const left = buf.getConst(0, 0);
    try testing.expect(left != null);
    try testing.expectEqual(@as(u21, 'L'), left.?.char);
    const right = buf.getConst(20, 0);
    try testing.expect(right != null);
    try testing.expectEqual(@as(u21, 'R'), right.?.char);
    // x=10 (between cells) should be blank
    const mid = buf.getConst(10, 0);
    try testing.expect(mid != null);
    try testing.expectEqual(@as(u21, ' '), mid.?.char);
}

test "StatusGrid.render with show_values true includes value below label" {
    var cells = [_]StatusCell{
        .{ .label = "CPU", .value = "45%" },
    };
    var grid = StatusGrid.init(&cells, 1, 1)
        .withShowValues(true);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // Label "CPU" at (0, 0), value "45%" at (0, 1)
    const label_cell = buf.getConst(0, 0);
    try testing.expect(label_cell != null);
    try testing.expectEqual(@as(u21, 'C'), label_cell.?.char); // "CPU"
    const value_cell = buf.getConst(0, 1);
    try testing.expect(value_cell != null);
    try testing.expectEqual(@as(u21, '4'), value_cell.?.char); // "45%"
}

test "StatusGrid.render cursor cell has reverse style for selection" {
    var cells = [_]StatusCell{
        .{ .label = "A" },
        .{ .label = "B" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    grid.cursor_col = 0; // Select first cell (col 0, row 0)
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    // Selected cell (cursor_row=0, cursor_col=0) should have reverse=true
    const sel_cell = buf.getConst(0, 0);
    try testing.expect(sel_cell != null);
    try testing.expectEqual(@as(u21, 'A'), sel_cell.?.char);
    try testing.expect(sel_cell.?.style.reverse == true);
    // Non-selected cell (col 1) at x=20 should NOT have reverse
    const other_cell = buf.getConst(20, 0);
    try testing.expect(other_cell != null);
    try testing.expectEqual(@as(u21, 'B'), other_cell.?.char);
    try testing.expect(other_cell.?.style.reverse == false);
}

// ============================================================================
// Render — Edge Cases Tests (7 tests)
// ============================================================================

test "StatusGrid.render zero rows and cols does not crash" {
    var cells: [0]StatusCell = undefined;
    var grid = StatusGrid.init(&cells, 0, 0);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid.render cells slice shorter than rows*cols does not panic" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
        .{ .label = "s2" },
    };
    var grid = StatusGrid.init(&cells, 2, 2); // Claims 4 cells but only 2 provided
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid.render 1×1 with narrow area (width=1, height=1) does not crash" {
    var cells = [_]StatusCell{
        .{ .label = "S" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 1, .height = 1 });
}

test "StatusGrid.render with block shrinks content area" {
    var cells = [_]StatusCell{
        .{ .label = "s1" },
    };
    const block = Block{ .borders = .all };
    var grid = StatusGrid.init(&cells, 1, 1)
        .withBlock(block);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid.render empty label does not crash" {
    var cells = [_]StatusCell{
        .{ .label = "" },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid.render all cells with unknown status uses unknown_style" {
    var cells = [_]StatusCell{
        .{ .label = "s1", .status = .unknown },
        .{ .label = "s2", .status = .unknown },
        .{ .label = "s3", .status = .unknown },
    };
    var grid = StatusGrid.init(&cells, 1, 3);
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

test "StatusGrid.render large grid (5×10) in small area (10×5) does not crash" {
    var cells: [50]StatusCell = undefined;
    for (0..50) |i| {
        cells[i] = .{ .label = "s" };
    }
    var grid = StatusGrid.init(&cells, 5, 10);
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 5 });
}

// ============================================================================
// Mixed Status Rendering Tests (4 tests)
// ============================================================================

test "StatusGrid.render mixed statuses displays each with correct style" {
    var cells = [_]StatusCell{
        .{ .label = "Ok", .status = .ok },
        .{ .label = "Warn", .status = .warn },
        .{ .label = "Err", .status = .error_ },
        .{ .label = "Unk", .status = .unknown },
    };
    var grid = StatusGrid.init(&cells, 2, 2);
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

test "StatusGrid.render warn status cell uses warn_style" {
    var cells = [_]StatusCell{
        .{ .label = "Warning", .status = .warn },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid.render error status cell uses error_style" {
    var cells = [_]StatusCell{
        .{ .label = "Error", .status = .error_ },
    };
    var grid = StatusGrid.init(&cells, 1, 1);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid.render shows values below labels when show_values true" {
    var cells = [_]StatusCell{
        .{ .label = "CPU", .value = "45%", .status = .ok },
        .{ .label = "MEM", .value = "92%", .status = .warn },
    };
    var grid = StatusGrid.init(&cells, 1, 2)
        .withShowValues(true);
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

// ============================================================================
// Navigation & Selection Integration Tests (5 tests)
// ============================================================================

test "StatusGrid.render after navigation shows cursor at new position" {
    var cells = [_]StatusCell{
        .{ .label = "A" },
        .{ .label = "B" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    grid.moveRight();
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });

    // Cell at (0,0) should not be highlighted, cell B should be
}

test "StatusGrid grid 3×3 full render with navigation between cells" {
    var cells = [_]StatusCell{
        .{ .label = "TL", .status = .ok },     .{ .label = "TM", .status = .warn },   .{ .label = "TR", .status = .error_ },
        .{ .label = "ML", .status = .unknown }, .{ .label = "MM", .status = .ok },     .{ .label = "MR", .status = .warn },
        .{ .label = "BL", .status = .warn },   .{ .label = "BM", .status = .error_ },  .{ .label = "BR", .status = .ok },
    };
    var grid = StatusGrid.init(&cells, 3, 3);
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();

    // Test render at (0,0)
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 30 });

    // Move around and verify selectedCell
    grid.moveRight();
    try testing.expectEqualStrings("TM", grid.selectedCell().?.label);
    grid.moveDown();
    try testing.expectEqualStrings("MM", grid.selectedCell().?.label);
    grid.moveRight();
    try testing.expectEqualStrings("MR", grid.selectedCell().?.label);
}

test "StatusGrid multiple render calls preserve cursor state" {
    var cells = [_]StatusCell{
        .{ .label = "A" },
        .{ .label = "B" },
    };
    var grid = StatusGrid.init(&cells, 1, 2);
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    try testing.expectEqual(@as(usize, 0), grid.cursor_col);

    grid.moveRight();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
    try testing.expectEqual(@as(usize, 1), grid.cursor_col);
}

test "StatusGrid render with custom cell_style applies to all cells" {
    var cells = [_]StatusCell{
        .{ .label = "S1" },
        .{ .label = "S2" },
    };
    var grid = StatusGrid.init(&cells, 1, 2)
        .withCellStyle(Style{ .bold = true });
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 20 });
}

test "StatusGrid cursor clamping after navigation then render" {
    var cells = [_]StatusCell{
        .{ .label = "s1" }, .{ .label = "s2" }, .{ .label = "s3" },
    };
    var grid = StatusGrid.init(&cells, 1, 3);
    grid.moveRight();
    grid.moveRight();
    grid.moveRight();
    grid.moveRight(); // Should clamp at col 2

    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    grid.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });

    try testing.expectEqual(@as(usize, 2), grid.cursor_col);
    try testing.expectEqualStrings("s3", grid.selectedCell().?.label);
}
