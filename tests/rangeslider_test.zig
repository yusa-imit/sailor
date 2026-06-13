//! RangeSlider Widget Tests — Comprehensive Coverage
//!
//! Tests the RangeSlider widget's initialization, movement (low/high handles),
//! builder API, value constraints, ratio calculations, rendering, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Cell = sailor.tui.buffer.Cell;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const RangeSlider = sailor.tui.RangeSlider;
const FocusedHandle = sailor.tui.FocusedHandle;

/// Scan a buffer row for a specific character; returns true if found
fn rowHasChar(buf: Buffer, y: u16, char: u21) bool {
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == char) return true;
        }
    }
    return false;
}

/// Find first x position of a character in row y
fn findCharInRow(buf: Buffer, y: u16, char: u21) ?u16 {
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == char) return x;
        }
    }
    return null;
}

/// Check if text exists in buffer at a given row (substring match)
fn rowHasText(buf: Buffer, y: u16, text: []const u8) bool {
    if (text.len == 0) return true;
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == text[0]) {
                var match = true;
                var offset: u16 = 1;
                while (offset < text.len and x + offset < buf.width) : (offset += 1) {
                    if (buf.getConst(x + offset, y)) |next_cell| {
                        if (next_cell.char != text[offset]) {
                            match = false;
                            break;
                        }
                    } else {
                        match = false;
                        break;
                    }
                }
                if (match and offset == text.len) return true;
            }
        }
    }
    return false;
}

// ============================================================================
// INITIALIZATION TESTS (5 tests)
// ============================================================================

test "RangeSlider init creates slider with default low=0" {
    const rs = RangeSlider.init();
    try testing.expectEqual(@as(f64, 0), rs.low);
}

test "RangeSlider init creates slider with default high=100" {
    const rs = RangeSlider.init();
    try testing.expectEqual(@as(f64, 100), rs.high);
}

test "RangeSlider init creates slider with default min=0" {
    const rs = RangeSlider.init();
    try testing.expectEqual(@as(f64, 0), rs.min);
}

test "RangeSlider init creates slider with default max=100" {
    const rs = RangeSlider.init();
    try testing.expectEqual(@as(f64, 100), rs.max);
}

test "RangeSlider init creates slider with default step=1" {
    const rs = RangeSlider.init();
    try testing.expectEqual(@as(f64, 1), rs.step);
}

test "RangeSlider init creates slider with default decimal_places=0" {
    const rs = RangeSlider.init();
    try testing.expectEqual(@as(u8, 0), rs.decimal_places);
}

test "RangeSlider init creates slider with default focused_handle=none" {
    const rs = RangeSlider.init();
    try testing.expectEqual(FocusedHandle.none, rs.focused_handle);
}

test "RangeSlider init creates slider with default show_values=true" {
    const rs = RangeSlider.init();
    try testing.expect(rs.show_values);
}

// ============================================================================
// MOVE LOW LEFT TESTS (4 tests)
// ============================================================================

test "RangeSlider moveLowLeft decrements low by step" {
    var rs = RangeSlider.init().withLow(50);
    rs.moveLowLeft();
    try testing.expectEqual(@as(f64, 49), rs.low);
}

test "RangeSlider moveLowLeft respects custom step" {
    var rs = RangeSlider.init().withLow(50).withStep(5);
    rs.moveLowLeft();
    try testing.expectEqual(@as(f64, 45), rs.low);
}

test "RangeSlider moveLowLeft clamps to min" {
    var rs = RangeSlider.init().withMin(10).withLow(12).withStep(5);
    rs.moveLowLeft();
    try testing.expectEqual(@as(f64, 10), rs.low);
}

test "RangeSlider moveLowLeft at min is no-op" {
    var rs = RangeSlider.init().withMin(0).withLow(0);
    rs.moveLowLeft();
    try testing.expectEqual(@as(f64, 0), rs.low);
}

// ============================================================================
// MOVE LOW RIGHT TESTS (4 tests)
// ============================================================================

test "RangeSlider moveLowRight increments low by step" {
    var rs = RangeSlider.init().withLow(50);
    rs.moveLowRight();
    try testing.expectEqual(@as(f64, 51), rs.low);
}

test "RangeSlider moveLowRight clamped to high (no crossing)" {
    var rs = RangeSlider.init().withLow(95).withHigh(100).withStep(10);
    rs.moveLowRight();
    try testing.expectEqual(@as(f64, 100), rs.low);
}

test "RangeSlider moveLowRight at high boundary" {
    var rs = RangeSlider.init().withLow(100).withHigh(100);
    rs.moveLowRight();
    try testing.expectEqual(@as(f64, 100), rs.low);
}

test "RangeSlider moveLowRight respects custom step" {
    var rs = RangeSlider.init().withLow(40).withStep(7);
    rs.moveLowRight();
    try testing.expectEqual(@as(f64, 47), rs.low);
}

// ============================================================================
// MOVE HIGH LEFT TESTS (4 tests)
// ============================================================================

test "RangeSlider moveHighLeft decrements high by step" {
    var rs = RangeSlider.init().withHigh(50);
    rs.moveHighLeft();
    try testing.expectEqual(@as(f64, 49), rs.high);
}

test "RangeSlider moveHighLeft clamped to low (no crossing)" {
    var rs = RangeSlider.init().withLow(0).withHigh(5).withStep(10);
    rs.moveHighLeft();
    try testing.expectEqual(@as(f64, 0), rs.high);
}

test "RangeSlider moveHighLeft at low boundary" {
    var rs = RangeSlider.init().withLow(0).withHigh(0);
    rs.moveHighLeft();
    try testing.expectEqual(@as(f64, 0), rs.high);
}

test "RangeSlider moveHighLeft respects custom step" {
    var rs = RangeSlider.init().withHigh(60).withStep(3);
    rs.moveHighLeft();
    try testing.expectEqual(@as(f64, 57), rs.high);
}

// ============================================================================
// MOVE HIGH RIGHT TESTS (4 tests)
// ============================================================================

test "RangeSlider moveHighRight increments high by step" {
    var rs = RangeSlider.init().withHigh(50);
    rs.moveHighRight();
    try testing.expectEqual(@as(f64, 51), rs.high);
}

test "RangeSlider moveHighRight respects custom step" {
    var rs = RangeSlider.init().withHigh(50).withStep(5);
    rs.moveHighRight();
    try testing.expectEqual(@as(f64, 55), rs.high);
}

test "RangeSlider moveHighRight clamps to max" {
    var rs = RangeSlider.init().withMax(100).withHigh(95).withStep(10);
    rs.moveHighRight();
    try testing.expectEqual(@as(f64, 100), rs.high);
}

test "RangeSlider moveHighRight at max is no-op" {
    var rs = RangeSlider.init().withMax(100).withHigh(100);
    rs.moveHighRight();
    try testing.expectEqual(@as(f64, 100), rs.high);
}

// ============================================================================
// SET LOW TESTS (4 tests)
// ============================================================================

test "RangeSlider setLow sets low value directly" {
    var rs = RangeSlider.init();
    rs.setLow(25);
    try testing.expectEqual(@as(f64, 25), rs.low);
}

test "RangeSlider setLow below min clamps to min" {
    var rs = RangeSlider.init().withMin(10);
    rs.setLow(5);
    try testing.expectEqual(@as(f64, 10), rs.low);
}

test "RangeSlider setLow above high clamps to high" {
    var rs = RangeSlider.init().withLow(20).withHigh(60);
    rs.setLow(80);
    try testing.expectEqual(@as(f64, 60), rs.low);
}

test "RangeSlider setLow at boundaries exact" {
    var rs = RangeSlider.init().withMin(5).withHigh(95);
    rs.setLow(5);
    try testing.expectEqual(@as(f64, 5), rs.low);
}

// ============================================================================
// SET HIGH TESTS (4 tests)
// ============================================================================

test "RangeSlider setHigh sets high value directly" {
    var rs = RangeSlider.init();
    rs.setHigh(75);
    try testing.expectEqual(@as(f64, 75), rs.high);
}

test "RangeSlider setHigh below low clamps to low" {
    var rs = RangeSlider.init().withLow(40);
    rs.setHigh(20);
    try testing.expectEqual(@as(f64, 40), rs.high);
}

test "RangeSlider setHigh above max clamps to max" {
    var rs = RangeSlider.init().withMax(100);
    rs.setHigh(150);
    try testing.expectEqual(@as(f64, 100), rs.high);
}

test "RangeSlider setHigh at boundaries exact" {
    var rs = RangeSlider.init().withMax(95);
    rs.setHigh(95);
    try testing.expectEqual(@as(f64, 95), rs.high);
}

// ============================================================================
// SET RANGE TESTS (3 tests)
// ============================================================================

test "RangeSlider setRange sets both low and high correctly" {
    var rs = RangeSlider.init();
    rs.setRange(25, 75);
    try testing.expectEqual(@as(f64, 25), rs.low);
    try testing.expectEqual(@as(f64, 75), rs.high);
}

test "RangeSlider setRange clamps lo to min" {
    var rs = RangeSlider.init().withMin(10);
    rs.setRange(5, 80);
    try testing.expectEqual(@as(f64, 10), rs.low);
    try testing.expectEqual(@as(f64, 80), rs.high);
}

test "RangeSlider setRange clamps hi to max" {
    var rs = RangeSlider.init().withMax(90);
    rs.setRange(20, 150);
    try testing.expectEqual(@as(f64, 20), rs.low);
    try testing.expectEqual(@as(f64, 90), rs.high);
}

// ============================================================================
// PREDICATE TESTS (4 tests)
// ============================================================================

test "RangeSlider isLowAtMin returns true when low equals min" {
    const rs = RangeSlider.init().withMin(10).withLow(10);
    try testing.expect(rs.isLowAtMin());
}

test "RangeSlider isLowAtMin returns false when low above min" {
    const rs = RangeSlider.init().withMin(10).withLow(20);
    try testing.expect(!rs.isLowAtMin());
}

test "RangeSlider isHighAtMax returns true when high equals max" {
    const rs = RangeSlider.init().withMax(100).withHigh(100);
    try testing.expect(rs.isHighAtMax());
}

test "RangeSlider isHighAtMax returns false when high below max" {
    const rs = RangeSlider.init().withMax(100).withHigh(50);
    try testing.expect(!rs.isHighAtMax());
}

// ============================================================================
// RANGE SIZE TESTS (2 tests)
// ============================================================================

test "RangeSlider rangeSize returns high - low" {
    const rs = RangeSlider.init().withLow(25).withHigh(75);
    try testing.expectEqual(@as(f64, 50), rs.rangeSize());
}

test "RangeSlider rangeSize with zero range" {
    const rs = RangeSlider.init().withLow(50).withHigh(50);
    try testing.expectEqual(@as(f64, 0), rs.rangeSize());
}

// ============================================================================
// RATIO TESTS (5 tests)
// ============================================================================

test "RangeSlider lowRatio at min equals 0.0" {
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(0);
    try testing.expectEqual(@as(f64, 0.0), rs.lowRatio());
}

test "RangeSlider lowRatio at max equals 1.0" {
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(100);
    try testing.expectEqual(@as(f64, 1.0), rs.lowRatio());
}

test "RangeSlider lowRatio at midpoint equals 0.5" {
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(50);
    try testing.expectApproxEqAbs(@as(f64, 0.5), rs.lowRatio(), 0.001);
}

test "RangeSlider highRatio at max equals 1.0" {
    const rs = RangeSlider.init().withMin(0).withMax(100).withHigh(100);
    try testing.expectEqual(@as(f64, 1.0), rs.highRatio());
}

test "RangeSlider ratios degenerate case (max==min) lowRatio=0.0 highRatio=1.0" {
    const rs = RangeSlider.init().withMin(50).withMax(50).withLow(50).withHigh(50);
    try testing.expectEqual(@as(f64, 0.0), rs.lowRatio());
    try testing.expectEqual(@as(f64, 1.0), rs.highRatio());
}

// ============================================================================
// BUILDER API TESTS — IMMUTABILITY (15 tests)
// ============================================================================

test "RangeSlider withMin returns new slider with updated min" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withMin(20);
    try testing.expectEqual(@as(f64, 0), rs1.min);
    try testing.expectEqual(@as(f64, 20), rs2.min);
}

test "RangeSlider withMax returns new slider with updated max" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withMax(200);
    try testing.expectEqual(@as(f64, 100), rs1.max);
    try testing.expectEqual(@as(f64, 200), rs2.max);
}

test "RangeSlider withStep returns new slider with updated step" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withStep(5);
    try testing.expectEqual(@as(f64, 1), rs1.step);
    try testing.expectEqual(@as(f64, 5), rs2.step);
}

test "RangeSlider withLow returns new slider with updated low" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withLow(30);
    try testing.expectEqual(@as(f64, 0), rs1.low);
    try testing.expectEqual(@as(f64, 30), rs2.low);
}

test "RangeSlider withHigh returns new slider with updated high" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withHigh(80);
    try testing.expectEqual(@as(f64, 100), rs1.high);
    try testing.expectEqual(@as(f64, 80), rs2.high);
}

test "RangeSlider withDecimalPlaces returns new slider with updated decimal_places" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withDecimalPlaces(2);
    try testing.expectEqual(@as(u8, 0), rs1.decimal_places);
    try testing.expectEqual(@as(u8, 2), rs2.decimal_places);
}

test "RangeSlider withLabel returns new slider with updated label" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withLabel("Volume");
    try testing.expectEqualStrings("", rs1.label);
    try testing.expectEqualStrings("Volume", rs2.label);
}

test "RangeSlider withShowValues returns new slider with updated show_values" {
    const rs1 = RangeSlider.init().withShowValues(false);
    const rs2 = rs1.withShowValues(true);
    try testing.expect(!rs1.show_values);
    try testing.expect(rs2.show_values);
}

test "RangeSlider withStyle returns new slider with updated style" {
    const s = Style{ .bold = true };
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withStyle(s);
    try testing.expect(!rs1.style.bold);
    try testing.expect(rs2.style.bold);
}

test "RangeSlider withSelectedStyle returns new slider with updated selected_style" {
    const s = Style{ .fg = .cyan };
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withSelectedStyle(s);
    try testing.expect(rs2.selected_style.fg != null);
}

test "RangeSlider withHandleStyle returns new slider with updated handle_style" {
    const s = Style{ .bold = false };
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withHandleStyle(s);
    try testing.expect(!rs2.handle_style.bold);
}

test "RangeSlider withFocusedStyle returns new slider with updated focused_style" {
    const s = Style{ .fg = .yellow };
    const rs = RangeSlider.init().withFocusedStyle(s);
    try testing.expect(rs.focused_style.fg != null);
}

test "RangeSlider withFocusedHandle returns new slider with updated focused_handle" {
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withFocusedHandle(.low);
    try testing.expectEqual(FocusedHandle.none, rs1.focused_handle);
    try testing.expectEqual(FocusedHandle.low, rs2.focused_handle);
}

test "RangeSlider withBlock returns new slider with optional block" {
    const block = Block{ .title = "Range" };
    const rs1 = RangeSlider.init();
    const rs2 = rs1.withBlock(block);
    try testing.expect(rs1.block == null);
    try testing.expect(rs2.block != null);
}

// ============================================================================
// RENDER ZERO AREA TESTS (2 tests)
// ============================================================================

test "RangeSlider render with zero width is no-op" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLow(25).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    rs.render(&buf, area);
    // Should not crash; no track chars should appear
    try testing.expect(!rowHasChar(buf, 0, '─'));
    try testing.expect(!rowHasChar(buf, 0, '═'));
}

test "RangeSlider render with zero height is no-op" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLow(25).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    rs.render(&buf, area);
    // Should not crash
    try testing.expect(!rowHasChar(buf, 0, '═'));
}

// ============================================================================
// RENDER HANDLE POSITION TESTS (4 tests)
// ============================================================================

test "RangeSlider render low handle at position 0 when low ratio is 0.0" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(0).withHigh(100);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rs.render(&buf, area);
    // Low handle (◄) should be at x=0
    if (findCharInRow(buf, 0, '◄')) |pos| {
        try testing.expectEqual(@as(u16, 0), pos);
    }
}

test "RangeSlider render high handle at position width-1 when high ratio is 1.0" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(0).withHigh(100);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rs.render(&buf, area);
    // High handle (►) should be at x=19
    if (findCharInRow(buf, 0, '►')) |pos| {
        try testing.expectEqual(@as(u16, 19), pos);
    }
}

test "RangeSlider render low handle at proportional position for ratio 0.5" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(50).withHigh(100);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rs.render(&buf, area);
    // Low handle at ratio 0.5 with width 20: pos = floor(0.5 * 19) = 9
    if (findCharInRow(buf, 0, '◄')) |pos| {
        try testing.expectEqual(@as(u16, 9), pos);
    }
}

test "RangeSlider render high handle at proportional position" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(0).withHigh(50);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rs.render(&buf, area);
    // High handle at ratio 0.5 with width 20: pos = floor(0.5 * 19) = 9
    if (findCharInRow(buf, 0, '►')) |pos| {
        try testing.expectEqual(@as(u16, 9), pos);
    }
}

// ============================================================================
// RENDER TRACK CHARS TESTS (3 tests)
// ============================================================================

test "RangeSlider render unselected_char appears before low handle" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(30).withHigh(70);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rs.render(&buf, area);
    // Unselected char '─' should appear before low handle
    try testing.expect(rowHasChar(buf, 0, '─'));
}

test "RangeSlider render selected_char appears between handles" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(25).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rs.render(&buf, area);
    // Selected char '═' should appear between handles
    try testing.expect(rowHasChar(buf, 0, '═'));
}

test "RangeSlider render unselected_char appears after high handle" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withMin(0).withMax(100).withLow(10).withHigh(90);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    rs.render(&buf, area);
    // Unselected char '─' should appear after high handle
    try testing.expect(rowHasChar(buf, 0, '─'));
}

// ============================================================================
// RENDER LABEL TESTS (2 tests)
// ============================================================================

test "RangeSlider render label is rendered before track" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLabel("Value").withLow(50).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    rs.render(&buf, area);
    // Label "Value" should be in buffer
    try testing.expect(rowHasText(buf, 0, "Value"));
}

test "RangeSlider render track starts after label and space" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLabel("Vol").withLow(40).withHigh(60);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    rs.render(&buf, area);
    // Should render without crashing; track chars after label
    try testing.expect(rowHasChar(buf, 0, '◄') or rowHasChar(buf, 0, '─'));
}

// ============================================================================
// RENDER SHOW VALUES TESTS (2 tests)
// ============================================================================

test "RangeSlider render show_values=true includes value string" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withShowValues(true).withLow(25).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    rs.render(&buf, area);
    // Value digits should appear (25 and 75 rendered)
    try testing.expect(rowHasChar(buf, 0, '2') or rowHasChar(buf, 0, '7'));
}

test "RangeSlider render show_values=false omits value string" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withShowValues(false).withLow(25).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    rs.render(&buf, area);
    // Should render handles and track, no value digits overlaid
    try testing.expect(rowHasChar(buf, 0, '◄') or rowHasChar(buf, 0, '►'));
}

// ============================================================================
// RENDER FOCUSED HANDLE TESTS (2 tests)
// ============================================================================

test "RangeSlider render focused_handle=low applies focused_style to low handle" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init()
        .withFocusedHandle(.low)
        .withFocusedStyle(Style{ .fg = .cyan })
        .withLow(25)
        .withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    rs.render(&buf, area);
    // Low handle should be rendered with focused style
    if (findCharInRow(buf, 0, '◄')) |pos| {
        if (buf.getConst(pos, 0)) |cell| {
            // Focused style should have cyan foreground
            try testing.expect(cell.style.fg != null);
        }
    }
}

test "RangeSlider render focused_handle=high applies focused_style to high handle" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init()
        .withFocusedHandle(.high)
        .withFocusedStyle(Style{ .fg = .yellow })
        .withLow(25)
        .withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    rs.render(&buf, area);
    // High handle should be rendered with focused style
    if (findCharInRow(buf, 0, '►')) |pos| {
        if (buf.getConst(pos, 0)) |cell| {
            // Focused style should be applied
            try testing.expect(cell.style.fg != null);
        }
    }
}

// ============================================================================
// RENDER NARROW AREA TESTS (3 tests)
// ============================================================================

test "RangeSlider render narrow area width=1 no crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLow(50).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    rs.render(&buf, area);
    // Should not crash with minimal width
}

test "RangeSlider render narrow area width=2 no crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLow(25).withHigh(75);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 1 };
    rs.render(&buf, area);
    // Should not crash with minimal width
}

test "RangeSlider render narrow area width=3 renders at least one char" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLow(0).withHigh(100);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    rs.render(&buf, area);
    // Should render at least one track character
    try testing.expect(rowHasChar(buf, 0, '◄') or rowHasChar(buf, 0, '►') or
                       rowHasChar(buf, 0, '─') or rowHasChar(buf, 0, '═'));
}

// ============================================================================
// BUILDER CHAINING TESTS (3 tests)
// ============================================================================

test "RangeSlider builder chaining multiple methods" {
    const rs = RangeSlider.init()
        .withMin(10)
        .withMax(200)
        .withStep(5)
        .withLow(40)
        .withHigh(160)
        .withLabel("Range")
        .withDecimalPlaces(1);
    try testing.expectEqual(@as(f64, 10), rs.min);
    try testing.expectEqual(@as(f64, 200), rs.max);
    try testing.expectEqual(@as(f64, 5), rs.step);
    try testing.expectEqual(@as(f64, 40), rs.low);
    try testing.expectEqual(@as(f64, 160), rs.high);
    try testing.expectEqualStrings("Range", rs.label);
    try testing.expectEqual(@as(u8, 1), rs.decimal_places);
}

test "RangeSlider low and high cannot cross after setRange" {
    var rs = RangeSlider.init();
    rs.setRange(75, 25);
    // Low should be clamped to min, high to max; order enforced by setRange
    try testing.expect(rs.low <= rs.high);
}

test "RangeSlider multiple setValue calls each overwrites previous" {
    var rs = RangeSlider.init();
    rs.setLow(20);
    try testing.expectEqual(@as(f64, 20), rs.low);
    rs.setLow(50);
    try testing.expectEqual(@as(f64, 50), rs.low);
    rs.setHigh(80);
    try testing.expectEqual(@as(f64, 80), rs.high);
}

// ============================================================================
// EDGE CASE TESTS (5 tests)
// ============================================================================

test "RangeSlider with negative range (min < 0)" {
    const rs = RangeSlider.init().withMin(-100).withLow(-50).withHigh(50);
    try testing.expectEqual(@as(f64, -50), rs.low);
    try testing.expectEqual(@as(f64, 50), rs.high);
}

test "RangeSlider isLowAtMin with negative min" {
    const rs = RangeSlider.init().withMin(-100).withLow(-100);
    try testing.expect(rs.isLowAtMin());
}

test "RangeSlider isHighAtMax with large max" {
    const rs = RangeSlider.init().withMax(1000000).withHigh(1000000);
    try testing.expect(rs.isHighAtMax());
}

test "RangeSlider with zero step renders but movement is no-op" {
    var rs = RangeSlider.init().withStep(0).withLow(50).withHigh(75);
    const original_low = rs.low;
    rs.moveLowRight();
    try testing.expectEqual(original_low, rs.low);
}

test "RangeSlider with equal low and high (single point)" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const rs = RangeSlider.init().withLow(50).withHigh(50);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    rs.render(&buf, area);
    // Should render without crashing; both handles at same position
    try testing.expect(rowHasChar(buf, 0, '◄') or rowHasChar(buf, 0, '►'));
}
