//! ColorSwatch Widget Tests — Comprehensive Coverage
//!
//! Tests the ColorSwatch widget's initialization, color selection, navigation,
//! builder API, rendering with colors and labels, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Cell = sailor.tui.buffer.Cell;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const ColorSwatch = sailor.tui.ColorSwatch;

/// Helper: Create a buffer with given dimensions
fn makeBuffer(w: u16, h: u16) !Buffer {
    return try Buffer.init(testing.allocator, w, h);
}

/// Helper: Find first x position in a row where a specific character appears
fn findCharInRow(buf: Buffer, y: u16, char: u21) ?u16 {
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == char) return x;
        }
    }
    return null;
}

/// Helper: Check if row contains a character
fn rowHasChar(buf: Buffer, y: u16, char: u21) bool {
    return findCharInRow(buf, y, char) != null;
}

/// Helper: Check if all cells in a rectangle have a specific background color
fn rectHasBgColor(buf: Buffer, rect: Rect, color: Color) bool {
    var y = rect.y;
    while (y < rect.y + rect.height) : (y += 1) {
        var x = rect.x;
        while (x < rect.x + rect.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (!std.meta.eql(cell.style.bg, color)) {
                    return false;
                }
            }
        }
    }
    return true;
}

// ============================================================================
// INITIALIZATION TESTS (6 tests)
// ============================================================================

test "ColorSwatch init with empty colors" {
    const cs = ColorSwatch.init(&.{});
    try testing.expectEqual(@as(usize, 0), cs.colors.len);
}

test "ColorSwatch init stores colors slice" {
    const colors = [_]Color{ .red, .green, .blue };
    const cs = ColorSwatch.init(&colors);
    try testing.expectEqual(@as(usize, 3), cs.colors.len);
    try testing.expect(std.meta.eql(cs.colors[0], Color.red));
}

test "ColorSwatch init defaults selected to 0" {
    const colors = [_]Color{ .red, .green };
    const cs = ColorSwatch.init(&colors);
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch init defaults columns to 4" {
    const colors = [_]Color{ .red, .green };
    const cs = ColorSwatch.init(&colors);
    try testing.expectEqual(@as(u16, 4), cs.columns);
}

test "ColorSwatch init defaults swatch_width to 3" {
    const colors = [_]Color{ .red };
    const cs = ColorSwatch.init(&colors);
    try testing.expectEqual(@as(u16, 3), cs.swatch_width);
}

test "ColorSwatch init defaults show_labels to false" {
    const colors = [_]Color{ .red };
    const cs = ColorSwatch.init(&colors);
    try testing.expect(!cs.show_labels);
}

// ============================================================================
// SELECTED COLOR TESTS (3 tests)
// ============================================================================

test "ColorSwatch selectedColor on empty colors returns null" {
    const cs = ColorSwatch.init(&.{});
    try testing.expectEqual(@as(?Color, null), cs.selectedColor());
}

test "ColorSwatch selectedColor returns color at selected index" {
    const colors = [_]Color{ .red, .green, .blue };
    const cs = ColorSwatch.init(&colors).withSelected(1);
    try testing.expect(std.meta.eql(cs.selectedColor(), Color.green));
}

test "ColorSwatch selectedColor at last index" {
    const colors = [_]Color{ .red, .green, .blue };
    const cs = ColorSwatch.init(&colors).withSelected(2);
    try testing.expect(std.meta.eql(cs.selectedColor(), Color.blue));
}

// ============================================================================
// SELECT NEXT TESTS (4 tests)
// ============================================================================

test "ColorSwatch selectNext increments selected" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .blue });
    cs.selectNext();
    try testing.expectEqual(@as(usize, 1), cs.selected);
}

test "ColorSwatch selectNext wraps from last to 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    cs.selected = 2;
    cs.selectNext();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectNext on empty colors does not crash" {
    var cs = ColorSwatch.init(&.{});
    cs.selectNext();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectNext with single color stays at 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red });
    cs.selectNext();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

// ============================================================================
// SELECT PREV TESTS (4 tests)
// ============================================================================

test "ColorSwatch selectPrev decrements selected" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    cs.selected = 2;
    cs.selectPrev();
    try testing.expectEqual(@as(usize, 1), cs.selected);
}

test "ColorSwatch selectPrev from 0 wraps to last" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    cs.selected = 0;
    cs.selectPrev();
    try testing.expectEqual(@as(usize, 2), cs.selected);
}

test "ColorSwatch selectPrev on empty colors does not crash" {
    var cs = ColorSwatch.init(&.{});
    cs.selectPrev();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectPrev with single color stays at 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red });
    cs.selectPrev();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

// ============================================================================
// SELECT RIGHT TESTS (5 tests)
// ============================================================================

test "ColorSwatch selectRight increments within row" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow }).withColumns(4);
    cs.selectRight();
    try testing.expectEqual(@as(usize, 1), cs.selected);
}

test "ColorSwatch selectRight at row end wraps to next row" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta }).withColumns(4);
    cs.selected = 3;
    cs.selectRight();
    try testing.expectEqual(@as(usize, 4), cs.selected);
}

test "ColorSwatch selectRight from last item wraps to 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta, .cyan, .white, .black }).withColumns(4);
    cs.selected = 7;
    cs.selectRight();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectRight at exact last in grid wraps to 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow }).withColumns(4);
    cs.selected = 3;
    cs.selectRight();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectRight with partial last row" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta, .cyan }).withColumns(4);
    cs.selected = 5;
    cs.selectRight();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

// ============================================================================
// SELECT LEFT TESTS (4 tests)
// ============================================================================

test "ColorSwatch selectLeft decrements within row" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    cs.selected = 1;
    cs.selectLeft();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectLeft from row start wraps to end of prev row" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta }).withColumns(4);
    cs.selected = 4;
    cs.selectLeft();
    try testing.expectEqual(@as(usize, 3), cs.selected);
}

test "ColorSwatch selectLeft from 0 wraps to last" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    cs.selected = 0;
    cs.selectLeft();
    try testing.expectEqual(@as(usize, 2), cs.selected);
}

test "ColorSwatch selectLeft with columns=4, from 1 goes to 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow }).withColumns(4);
    cs.selected = 1;
    cs.selectLeft();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

// ============================================================================
// SELECT DOWN TESTS (4 tests)
// ============================================================================

test "ColorSwatch selectDown increments by columns" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta }).withColumns(4);
    cs.selectDown();
    try testing.expectEqual(@as(usize, 4), cs.selected);
}

test "ColorSwatch selectDown from last row clamps to last" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta }).withColumns(4);
    cs.selected = 4;
    cs.selectDown();
    try testing.expectEqual(@as(usize, 4), cs.selected);
}

test "ColorSwatch selectDown with 8 colors and columns=4 from 0 goes to 4" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta, .cyan, .white, .black }).withColumns(4);
    cs.selectDown();
    try testing.expectEqual(@as(usize, 4), cs.selected);
}

test "ColorSwatch selectDown clamped at last valid index" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta }).withColumns(4);
    cs.selected = 1;
    cs.selectDown();
    try testing.expectEqual(@as(usize, 4), cs.selected);
}

// ============================================================================
// SELECT UP TESTS (4 tests)
// ============================================================================

test "ColorSwatch selectUp decrements by columns" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta }).withColumns(4);
    cs.selected = 4;
    cs.selectUp();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectUp from first row clamps to 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    cs.selected = 1;
    cs.selectUp();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectUp from 0 stays at 0" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    cs.selectUp();
    try testing.expectEqual(@as(usize, 0), cs.selected);
}

test "ColorSwatch selectUp with columns=4 from 5 goes to 1" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta, .cyan }).withColumns(4);
    cs.selected = 5;
    cs.selectUp();
    try testing.expectEqual(@as(usize, 1), cs.selected);
}

// ============================================================================
// BUILDER API TESTS (11 tests)
// ============================================================================

test "ColorSwatch withColors returns new instance with colors" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const colors2 = [_]Color{ .green, .blue };
    const cs2 = cs1.withColors(&colors2);
    try testing.expectEqual(@as(usize, 2), cs2.colors.len);
    try testing.expect(std.meta.eql(cs2.colors[0], Color.green));
}

test "ColorSwatch withSelected returns new instance with selected index" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red, .green, .blue });
    const cs2 = cs1.withSelected(2);
    try testing.expectEqual(@as(usize, 2), cs2.selected);
}

test "ColorSwatch withColumns returns new instance with columns" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const cs2 = cs1.withColumns(6);
    try testing.expectEqual(@as(u16, 6), cs2.columns);
}

test "ColorSwatch withSwatchWidth returns new instance with swatch_width" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const cs2 = cs1.withSwatchWidth(5);
    try testing.expectEqual(@as(u16, 5), cs2.swatch_width);
}

test "ColorSwatch withSwatchHeight returns new instance with swatch_height" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const cs2 = cs1.withSwatchHeight(2);
    try testing.expectEqual(@as(u16, 2), cs2.swatch_height);
}

test "ColorSwatch withShowLabels returns new instance with show_labels" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const cs2 = cs1.withShowLabels(true);
    try testing.expect(cs2.show_labels);
}

test "ColorSwatch withStyle returns new instance with style" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const style = Style{ .bold = true };
    const cs2 = cs1.withStyle(style);
    try testing.expect(cs2.style.bold);
}

test "ColorSwatch withSelectedStyle returns new instance with selected_style" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const style = Style{ .fg = .yellow };
    const cs2 = cs1.withSelectedStyle(style);
    try testing.expect(std.meta.eql(cs2.selected_style.fg, Color.yellow));
}

test "ColorSwatch withLabelStyle returns new instance with label_style" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const style = Style{ .fg = .cyan };
    const cs2 = cs1.withLabelStyle(style);
    try testing.expect(std.meta.eql(cs2.label_style.fg, Color.cyan));
}

test "ColorSwatch withLabels returns new instance with labels" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const labels = [_][]const u8{ "Red" };
    const cs2 = cs1.withLabels(&labels);
    try testing.expectEqual(@as(usize, 1), cs2.labels.len);
}

test "ColorSwatch withBlock returns new instance with block set" {
    const cs1 = ColorSwatch.init(&[_]Color{ .red });
    const block = Block{};
    const cs2 = cs1.withBlock(block);
    try testing.expect(cs2.block != null);
}

// ============================================================================
// RENDER ZERO AREA TESTS (2 tests)
// ============================================================================

test "ColorSwatch render with zero width area does not crash" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cs = ColorSwatch.init(&[_]Color{ .red });
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 5 };
    cs.render(&buf, area);
}

test "ColorSwatch render with zero height area does not crash" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cs = ColorSwatch.init(&[_]Color{ .red });
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    cs.render(&buf, area);
}

// ============================================================================
// RENDER EMPTY COLORS TESTS (1 test)
// ============================================================================

test "ColorSwatch render with empty colors does not crash" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cs = ColorSwatch.init(&.{});
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    cs.render(&buf, area);
}

// ============================================================================
// RENDER BASIC CELL FILL TESTS (6 tests)
// ============================================================================

test "ColorSwatch render single color fills with correct background" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cs = ColorSwatch.init(&[_]Color{ .red }).withSwatchWidth(3).withSwatchHeight(1);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    cs.render(&buf, area);

    // First 3 cells of row 0 should have red background
    const rect = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    try testing.expect(rectHasBgColor(buf, rect, Color.red));
}

test "ColorSwatch render 4 colors in grid layout" {
    var buf = try makeBuffer(12, 3);
    defer buf.deinit();
    const colors = [_]Color{ .red, .green, .blue, .yellow };
    const cs = ColorSwatch.init(&colors).withColumns(4).withSwatchWidth(3).withSwatchHeight(1);
    const area = Rect{ .x = 0, .y = 0, .width = 12, .height = 3 };
    cs.render(&buf, area);

    // Row 0 should have 4 color regions (3 cells wide each)
    // Red: [0,3), Green: [3,6), Blue: [6,9), Yellow: [9,12)
    var rect = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    try testing.expect(rectHasBgColor(buf, rect, Color.red));

    rect.x = 3;
    try testing.expect(rectHasBgColor(buf, rect, Color.green));

    rect.x = 6;
    try testing.expect(rectHasBgColor(buf, rect, Color.blue));

    rect.x = 9;
    try testing.expect(rectHasBgColor(buf, rect, Color.yellow));
}

test "ColorSwatch render selected index 0 contains marker" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const colors = [_]Color{ .red, .green };
    const cs = ColorSwatch.init(&colors).withSelected(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    cs.render(&buf, area);

    // First cell should contain the selection marker '●' (U+25CF)
    try testing.expect(rowHasChar(buf, 0, 0x25CF));
}

test "ColorSwatch render selected index 1 contains marker" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const colors = [_]Color{ .red, .green, .blue };
    const cs = ColorSwatch.init(&colors).withColumns(4).withSwatchWidth(3).withSelected(1);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    cs.render(&buf, area);

    // Second cell (at x=3) should contain marker
    try testing.expect(rowHasChar(buf, 0, 0x25CF));
}

test "ColorSwatch render non-selected cell does not have marker" {
    var buf = try makeBuffer(20, 5);
    defer buf.deinit();
    const colors = [_]Color{ .red, .green, .blue };
    const cs = ColorSwatch.init(&colors).withColumns(3).withSwatchWidth(6).withSelected(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    cs.render(&buf, area);

    // Only first cell should have marker; second cell (x=6-11) should not
    // Check that marker is in first cell area [0,6)
    if (findCharInRow(buf, 0, 0x25CF)) |x| {
        try testing.expect(x < 6);
    }
}

test "ColorSwatch render cell background fills full width and height" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cs = ColorSwatch.init(&[_]Color{ .red }).withSwatchWidth(4).withSwatchHeight(2);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    cs.render(&buf, area);

    // First cell should be 4x2 with red background
    const rect = Rect{ .x = 0, .y = 0, .width = 4, .height = 2 };
    try testing.expect(rectHasBgColor(buf, rect, Color.red));
}

// ============================================================================
// RENDER LABELS TESTS (4 tests)
// ============================================================================

test "ColorSwatch render with show_labels=false has no label text" {
    var buf = try makeBuffer(10, 10);
    defer buf.deinit();
    const colors = [_]Color{ .red };
    const labels = [_][]const u8{ "Red" };
    const cs = ColorSwatch.init(&colors).withLabels(&labels).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    cs.render(&buf, area);

    // Row 1 should be empty (swatch at row 0, labels not shown)
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, 1)) |cell| {
            try testing.expect(cell.char == ' ');
        }
    }
}

test "ColorSwatch render with show_labels=true and labels renders text" {
    var buf = try makeBuffer(20, 10);
    defer buf.deinit();
    const colors = [_]Color{ .red };
    const labels = [_][]const u8{ "RED" };
    const cs = ColorSwatch.init(&colors)
        .withLabels(&labels)
        .withShowLabels(true)
        .withSwatchWidth(3)
        .withSwatchHeight(1);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    cs.render(&buf, area);

    // Row 1 should have label text "RED"
    try testing.expect(rowHasChar(buf, 1, 'R'));
}

test "ColorSwatch render with show_labels=true and empty labels does not crash" {
    var buf = try makeBuffer(10, 10);
    defer buf.deinit();
    const colors = [_]Color{ .red };
    const labels = [_][]const u8{ "" };
    const cs = ColorSwatch.init(&colors)
        .withLabels(&labels)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    cs.render(&buf, area);
}

test "ColorSwatch render with narrow area and labels does not crash" {
    var buf = try makeBuffer(5, 10);
    defer buf.deinit();
    const colors = [_]Color{ .red };
    const labels = [_][]const u8{ "RED" };
    const cs = ColorSwatch.init(&colors)
        .withLabels(&labels)
        .withShowLabels(true)
        .withSwatchWidth(4);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    cs.render(&buf, area);
}

// ============================================================================
// RENDER BLOCK TESTS (2 tests)
// ============================================================================

test "ColorSwatch render with block renders border" {
    var buf = try makeBuffer(10, 10);
    defer buf.deinit();
    const colors = [_]Color{ .red };
    const block = Block{};
    const cs = ColorSwatch.init(&colors).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    cs.render(&buf, area);

    // Block should be rendered (border visible)
    // Top-left corner should have a non-space border character
    if (buf.getConst(0, 0)) |cell| {
        try testing.expect(cell.char != ' ');
    }
}

test "ColorSwatch render with block and small area does not crash" {
    var buf = try makeBuffer(6, 6);
    defer buf.deinit();
    const colors = [_]Color{ .red };
    const block = Block{};
    const cs = ColorSwatch.init(&colors).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 6, .height = 6 };
    cs.render(&buf, area);
}

// ============================================================================
// RENDER NARROW/SINGLE TESTS (3 tests)
// ============================================================================

test "ColorSwatch render with swatch_width=1 single column" {
    var buf = try makeBuffer(5, 5);
    defer buf.deinit();
    const cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue }).withSwatchWidth(1).withColumns(1);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    cs.render(&buf, area);

    // First column should have red background at row 0
    const rect = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    try testing.expect(rectHasBgColor(buf, rect, Color.red));
}

test "ColorSwatch render with area exactly one swatch" {
    var buf = try makeBuffer(3, 1);
    defer buf.deinit();
    const cs = ColorSwatch.init(&[_]Color{ .red }).withSwatchWidth(3).withSwatchHeight(1);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    cs.render(&buf, area);

    const rect = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    try testing.expect(rectHasBgColor(buf, rect, Color.red));
}

test "ColorSwatch render with very small area" {
    var buf = try makeBuffer(2, 2);
    defer buf.deinit();
    const cs = ColorSwatch.init(&[_]Color{ .red }).withSwatchWidth(2);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    cs.render(&buf, area);
}

// ============================================================================
// EDGE CASES & COMPLEX SCENARIOS (8 tests)
// ============================================================================

test "ColorSwatch selected clamped when exceeds colors length" {
    const colors = [_]Color{ .red, .green };
    const cs = ColorSwatch.init(&colors).withSelected(10);
    // Should clamp to last valid index (1)
    try testing.expectEqual(@as(usize, 1), cs.selected);
}

test "ColorSwatch navigation with columns=1 vertically" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue }).withColumns(1);
    cs.selectDown();
    try testing.expectEqual(@as(usize, 1), cs.selected);
}

test "ColorSwatch builder chaining withColors and withSelected" {
    const colors = [_]Color{ .red, .green, .blue };
    const cs = ColorSwatch.init(&colors)
        .withSelected(1)
        .withColumns(2);
    try testing.expectEqual(@as(usize, 1), cs.selected);
    try testing.expectEqual(@as(u16, 2), cs.columns);
}

test "ColorSwatch selectRight followed by selectNext" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta }).withColumns(2);
    cs.selectRight();  // 0 -> 1
    try testing.expectEqual(@as(usize, 1), cs.selected);
    cs.selectNext();   // 1 -> 2
    try testing.expectEqual(@as(usize, 2), cs.selected);
}

test "ColorSwatch render with rgb colors" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const colors = [_]Color{ Color.fromRgb(255, 0, 0), Color.fromRgb(0, 255, 0) };
    const cs = ColorSwatch.init(&colors).withSwatchWidth(5);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    cs.render(&buf, area);
}

test "ColorSwatch render with indexed colors" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const colors = [_]Color{ Color.fromIndexed(196), Color.fromIndexed(46) };
    const cs = ColorSwatch.init(&colors).withSwatchWidth(5);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    cs.render(&buf, area);
}

test "ColorSwatch multi-row grid with 8 colors, columns=4" {
    var buf = try makeBuffer(12, 6);
    defer buf.deinit();
    const colors = [_]Color{ .red, .green, .blue, .yellow, .magenta, .cyan, .white, .black };
    const cs = ColorSwatch.init(&colors).withColumns(4).withSwatchWidth(3).withSwatchHeight(1);
    const area = Rect{ .x = 0, .y = 0, .width = 12, .height = 6 };
    cs.render(&buf, area);

    // Row 0 should have colors 0-3
    var rect = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    try testing.expect(rectHasBgColor(buf, rect, Color.red));

    // Row 1 should have colors 4-7
    rect.y = 1;
    rect.x = 0;
    try testing.expect(rectHasBgColor(buf, rect, Color.magenta));
}

test "ColorSwatch selectDown at edge of partial last row" {
    var cs = ColorSwatch.init(&[_]Color{ .red, .green, .blue, .yellow, .magenta, .cyan }).withColumns(4);
    cs.selected = 2;  // Row 0, col 2
    cs.selectDown();  // 2 + 4 = 6 >= len(6), clamps to last index 5
    try testing.expectEqual(@as(usize, 5), cs.selected);
}
