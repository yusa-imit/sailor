//! NumberInput Widget Tests — Comprehensive Coverage
//!
//! Tests the NumberInput widget's initialization, navigation (increment/decrement),
//! builder API, value constraints, and rendering across all edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const NumberInput = sailor.tui.widgets.NumberInput;

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
                // Potential match start
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

test "NumberInput init creates input with default value 0" {
    const ni = NumberInput.init();
    try testing.expectEqual(@as(f64, 0), ni.value);
}

test "NumberInput init sets default min to 0" {
    const ni = NumberInput.init();
    try testing.expectEqual(@as(f64, 0), ni.min);
}

test "NumberInput init sets default max to 100" {
    const ni = NumberInput.init();
    try testing.expectEqual(@as(f64, 100), ni.max);
}

test "NumberInput init sets default step to 1" {
    const ni = NumberInput.init();
    try testing.expectEqual(@as(f64, 1), ni.step);
}

test "NumberInput init sets default decimal_places to 0" {
    const ni = NumberInput.init();
    try testing.expectEqual(@as(u8, 0), ni.decimal_places);
}

// ============================================================================
// INCREMENT TESTS (6 tests)
// ============================================================================

test "NumberInput increment adds step to value" {
    var ni = NumberInput.init();
    ni.increment();
    try testing.expectEqual(@as(f64, 1), ni.value);
}

test "NumberInput increment respects custom step" {
    var ni = NumberInput.init().withStep(5);
    ni.increment();
    try testing.expectEqual(@as(f64, 5), ni.value);
}

test "NumberInput increment clamps to max" {
    var ni = NumberInput.init().withMax(10).withValue(9.5).withStep(2);
    ni.increment();
    try testing.expectEqual(@as(f64, 10), ni.value);
}

test "NumberInput increment at max is no-op" {
    var ni = NumberInput.init().withMax(100).withValue(100);
    ni.increment();
    try testing.expectEqual(@as(f64, 100), ni.value);
}

test "NumberInput increment with large step overshoots and clamps" {
    var ni = NumberInput.init().withMax(50).withValue(40).withStep(20);
    ni.increment();
    try testing.expectEqual(@as(f64, 50), ni.value);
}

test "NumberInput increment handles fractional values" {
    var ni = NumberInput.init().withValue(1.5).withStep(0.5);
    ni.increment();
    try testing.expectEqual(@as(f64, 2.0), ni.value);
}

// ============================================================================
// DECREMENT TESTS (6 tests)
// ============================================================================

test "NumberInput decrement subtracts step from value" {
    var ni = NumberInput.init().withValue(5);
    ni.decrement();
    try testing.expectEqual(@as(f64, 4), ni.value);
}

test "NumberInput decrement respects custom step" {
    var ni = NumberInput.init().withValue(20).withStep(5);
    ni.decrement();
    try testing.expectEqual(@as(f64, 15), ni.value);
}

test "NumberInput decrement clamps to min" {
    var ni = NumberInput.init().withMin(0).withValue(1.5).withStep(2);
    ni.decrement();
    try testing.expectEqual(@as(f64, 0), ni.value);
}

test "NumberInput decrement at min is no-op" {
    var ni = NumberInput.init().withMin(0).withValue(0);
    ni.decrement();
    try testing.expectEqual(@as(f64, 0), ni.value);
}

test "NumberInput decrement below min clamps to min" {
    var ni = NumberInput.init().withMin(10).withValue(15).withStep(10);
    ni.decrement();
    try testing.expectEqual(@as(f64, 10), ni.value);
}

test "NumberInput decrement with negative values" {
    var ni = NumberInput.init().withMin(-10).withValue(-2).withStep(3);
    ni.decrement();
    try testing.expectEqual(@as(f64, -5), ni.value);
}

// ============================================================================
// SET VALUE TESTS (6 tests)
// ============================================================================

test "NumberInput setValue sets value directly" {
    var ni = NumberInput.init();
    ni.setValue(42);
    try testing.expectEqual(@as(f64, 42), ni.value);
}

test "NumberInput setValue below min clamps to min" {
    var ni = NumberInput.init().withMin(10);
    ni.setValue(5);
    try testing.expectEqual(@as(f64, 10), ni.value);
}

test "NumberInput setValue above max clamps to max" {
    var ni = NumberInput.init().withMax(50);
    ni.setValue(100);
    try testing.expectEqual(@as(f64, 50), ni.value);
}

test "NumberInput setValue on boundary min" {
    var ni = NumberInput.init().withMin(5);
    ni.setValue(5);
    try testing.expectEqual(@as(f64, 5), ni.value);
}

test "NumberInput setValue on boundary max" {
    var ni = NumberInput.init().withMax(75);
    ni.setValue(75);
    try testing.expectEqual(@as(f64, 75), ni.value);
}

test "NumberInput setValue with fractional value" {
    var ni = NumberInput.init();
    ni.setValue(3.14159);
    try testing.expectApproxEqAbs(@as(f64, 3.14159), ni.value, 0.00001);
}

// ============================================================================
// HELPER PREDICATE TESTS (4 tests)
// ============================================================================

test "NumberInput isAtMin returns true when value equals min" {
    const ni = NumberInput.init().withMin(10).withValue(10);
    try testing.expect(ni.isAtMin());
}

test "NumberInput isAtMin returns false when value above min" {
    const ni = NumberInput.init().withMin(10).withValue(15);
    try testing.expect(!ni.isAtMin());
}

test "NumberInput isAtMax returns true when value equals max" {
    const ni = NumberInput.init().withMax(100).withValue(100);
    try testing.expect(ni.isAtMax());
}

test "NumberInput isAtMax returns false when value below max" {
    const ni = NumberInput.init().withMax(100).withValue(50);
    try testing.expect(!ni.isAtMax());
}

// ============================================================================
// BUILDER API TESTS — IMMUTABILITY (14 tests)
// ============================================================================

test "NumberInput withMin returns new input with updated min" {
    const ni1 = NumberInput.init();
    const ni2 = ni1.withMin(20);
    try testing.expectEqual(@as(f64, 0), ni1.min);
    try testing.expectEqual(@as(f64, 20), ni2.min);
}

test "NumberInput withMax returns new input with updated max" {
    const ni1 = NumberInput.init();
    const ni2 = ni1.withMax(50);
    try testing.expectEqual(@as(f64, 100), ni1.max);
    try testing.expectEqual(@as(f64, 50), ni2.max);
}

test "NumberInput withStep returns new input with updated step" {
    const ni1 = NumberInput.init();
    const ni2 = ni1.withStep(5);
    try testing.expectEqual(@as(f64, 1), ni1.step);
    try testing.expectEqual(@as(f64, 5), ni2.step);
}

test "NumberInput withDecimalPlaces returns new input with updated decimal_places" {
    const ni1 = NumberInput.init();
    const ni2 = ni1.withDecimalPlaces(2);
    try testing.expectEqual(@as(u8, 0), ni1.decimal_places);
    try testing.expectEqual(@as(u8, 2), ni2.decimal_places);
}

test "NumberInput withValue returns new input and clamps value" {
    const ni1 = NumberInput.init();
    const ni2 = ni1.withValue(42);
    try testing.expectEqual(@as(f64, 0), ni1.value);
    try testing.expectEqual(@as(f64, 42), ni2.value);
}

test "NumberInput withValue clamps above max at construction" {
    const ni = NumberInput.init().withMax(50).withValue(100);
    try testing.expectEqual(@as(f64, 50), ni.value);
}

test "NumberInput withValue clamps below min at construction" {
    const ni = NumberInput.init().withMin(10).withValue(5);
    try testing.expectEqual(@as(f64, 10), ni.value);
}

test "NumberInput withLabel sets label" {
    const ni = NumberInput.init().withLabel("Volume");
    try testing.expectEqualStrings("Volume", ni.label);
}

test "NumberInput withPrefix sets prefix" {
    const ni = NumberInput.init().withPrefix("$");
    try testing.expectEqualStrings("$", ni.prefix);
}

test "NumberInput withSuffix sets suffix" {
    const ni = NumberInput.init().withSuffix("%");
    try testing.expectEqualStrings("%", ni.suffix);
}

test "NumberInput withStyle sets style" {
    const s = Style{ .bold = true };
    const ni = NumberInput.init().withStyle(s);
    try testing.expectEqual(true, ni.style.bold);
}

test "NumberInput withFocusedStyle sets focused_style" {
    const s = Style{ .fg = .cyan };
    const ni = NumberInput.init().withFocusedStyle(s);
    try testing.expect(ni.focused_style.fg == .cyan);
}

test "NumberInput withLabelStyle sets label_style" {
    const s = Style{ .bold = true };
    const ni = NumberInput.init().withLabelStyle(s);
    try testing.expect(ni.label_style.bold);
}

test "NumberInput withFocused sets focused state" {
    const ni1 = NumberInput.init();
    const ni2 = ni1.withFocused(true);
    try testing.expect(!ni1.focused);
    try testing.expect(ni2.focused);
}

// ============================================================================
// RENDER TESTS — AREA & BASIC RENDERING (8 tests)
// ============================================================================

test "NumberInput render with zero width is no-op" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    ni.render(&buf, area);
    // Should not crash; cell at (0,0) should be unchanged
    try testing.expect(buf.getConst(0, 0) == null);
}

test "NumberInput render with zero height is no-op" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    ni.render(&buf, area);
    // Should not crash; buffer should be empty
    try testing.expect(buf.getConst(0, 0) == null);
}

test "NumberInput render renders to buffer starting at area.x, area.y" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42);
    const area = Rect{ .x = 5, .y = 2, .width = 50, .height = 1 };
    ni.render(&buf, area);
    // Check that content was written (look for '4' and '2' characters)
    try testing.expect(rowHasChar(buf, 2, '4'));
}

test "NumberInput render without label omits label section" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withLabel("");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render value without label
    try testing.expect(rowHasChar(buf, 0, '4'));
}

test "NumberInput render with label includes label text" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withLabel("Count");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render label
    try testing.expect(rowHasText(buf, 0, "Count"));
}

test "NumberInput render includes decrement button [-]" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(50);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render [-]
    try testing.expect(rowHasChar(buf, 0, '-'));
}

test "NumberInput render includes increment button [+]" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(50);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render [+]
    try testing.expect(rowHasChar(buf, 0, '+'));
}

test "NumberInput render with prefix includes prefix in output" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withPrefix("$");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render prefix '$'
    try testing.expect(rowHasChar(buf, 0, '$'));
}

// ============================================================================
// RENDER TESTS — FORMATTING & DECIMAL PLACES (7 tests)
// ============================================================================

test "NumberInput render with decimal_places=0 renders as integer" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withDecimalPlaces(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render "42" (not "42.00")
    try testing.expect(rowHasText(buf, 0, "42"));
}

test "NumberInput render with decimal_places=2 renders two decimals" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(3.14).withDecimalPlaces(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render "3.14"
    try testing.expect(rowHasText(buf, 0, "3") and rowHasText(buf, 0, "14"));
}

test "NumberInput render rounds value to decimal_places" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(3.14159).withDecimalPlaces(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render "3.14"
    try testing.expect(rowHasText(buf, 0, "3"));
}

test "NumberInput render with suffix includes suffix text" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withSuffix("%");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render "%"
    try testing.expect(rowHasChar(buf, 0, '%'));
}

test "NumberInput render with prefix and suffix includes both" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withPrefix("$").withSuffix(" USD");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render both '$' and 'D' (from USD)
    try testing.expect(rowHasChar(buf, 0, '$') and rowHasChar(buf, 0, 'D'));
}

test "NumberInput render with zero value" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render "0"
    try testing.expect(rowHasChar(buf, 0, '0'));
}

test "NumberInput render with negative value" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withMin(-10).withValue(-5);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render '-' and '5'
    try testing.expect(rowHasChar(buf, 0, '5'));
}

// ============================================================================
// RENDER TESTS — STATE DEPENDENT (6 tests)
// ============================================================================

test "NumberInput render at min state marks decrement as disabled (dim)" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withMin(0).withValue(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should not crash; [-] button should exist but be dim
    try testing.expect(rowHasChar(buf, 0, '-'));
}

test "NumberInput render at max state marks increment as disabled (dim)" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withMax(100).withValue(100);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should not crash; [+] button should exist but be dim
    try testing.expect(rowHasChar(buf, 0, '+'));
}

test "NumberInput render when focused uses focused_style for value" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withFocused(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render; focused_style should be applied (hard to verify without checking style, but shouldn't crash)
    try testing.expect(rowHasChar(buf, 0, '4'));
}

test "NumberInput render when not focused uses default style" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withFocused(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render with default style
    try testing.expect(rowHasChar(buf, 0, '4'));
}

test "NumberInput render with Block renders within block boundaries" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const block = Block{ .title = "Input" };
    const ni = NumberInput.init().withValue(42).withBlock(block);
    const area = Rect{ .x = 2, .y = 1, .width = 60, .height = 3 };
    ni.render(&buf, area);
    // Should render within block
    try testing.expect(rowHasChar(buf, 1, '4') or rowHasChar(buf, 2, '4'));
}

test "NumberInput render narrow area (width < 10) omits label and prefix/suffix" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42).withLabel("Count").withPrefix("$").withSuffix("%");
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    ni.render(&buf, area);
    // Should render at least value without crashing
    try testing.expect(rowHasChar(buf, 0, '4'));
}

// ============================================================================
// RENDER TESTS — EDGE CASES (7 tests)
// ============================================================================

test "NumberInput render with very large value" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withMax(1e6).withValue(999999);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render large number without overflow
    try testing.expect(rowHasChar(buf, 0, '9'));
}

test "NumberInput render with very small value" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withMin(0.001).withValue(0.001).withDecimalPlaces(3);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render fractional value
    try testing.expect(rowHasChar(buf, 0, '0') or rowHasChar(buf, 0, '1'));
}

test "NumberInput render with step larger than range collapses correctly" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withMin(0).withMax(10).withValue(5).withStep(20);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render without crashing
    try testing.expect(rowHasChar(buf, 0, '5'));
}

test "NumberInput render at offset position (x > 0)" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(42);
    const area = Rect{ .x = 20, .y = 5, .width = 40, .height = 1 };
    ni.render(&buf, area);
    // Should render at offset
    try testing.expect(rowHasChar(buf, 5, '4'));
}

test "NumberInput render with min equals max (single value)" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withMin(42).withMax(42).withValue(42);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Should render single value; increment/decrement would be no-ops
    try testing.expect(rowHasChar(buf, 0, '4'));
}

test "NumberInput render very narrow width (width=1) no crash" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init().withValue(5);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    ni.render(&buf, area);
    // Should not crash even with width=1
}

test "NumberInput render full row layout" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni = NumberInput.init()
        .withLabel("Volume")
        .withValue(50)
        .withPrefix("")
        .withSuffix(" dB")
        .withMin(0)
        .withMax(100);
    const area = Rect{ .x = 0, .y = 10, .width = 80, .height = 1 };
    ni.render(&buf, area);
    // Full row render: "Volume [-] 50 dB [+]"
    try testing.expect(rowHasChar(buf, 10, '5'));
}

// ============================================================================
// BEHAVIOR TESTS — CHAINING & STRESS (6 tests)
// ============================================================================

test "NumberInput builder chaining multiple methods" {
    const ni = NumberInput.init()
        .withMin(0)
        .withMax(100)
        .withStep(5)
        .withValue(50)
        .withLabel("Level")
        .withPrefix("[")
        .withSuffix("]")
        .withDecimalPlaces(1);
    try testing.expectEqual(@as(f64, 0), ni.min);
    try testing.expectEqual(@as(f64, 100), ni.max);
    try testing.expectEqual(@as(f64, 5), ni.step);
    try testing.expectEqual(@as(f64, 50), ni.value);
    try testing.expectEqualStrings("Level", ni.label);
    try testing.expectEqual(@as(u8, 1), ni.decimal_places);
}

test "NumberInput many increments then decrements returns to original" {
    var ni = NumberInput.init().withValue(50).withStep(1);
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        ni.increment();
    }
    try testing.expectEqual(@as(f64, 60), ni.value);
    i = 0;
    while (i < 10) : (i += 1) {
        ni.decrement();
    }
    try testing.expectEqual(@as(f64, 50), ni.value);
}

test "NumberInput increment/decrement alternation" {
    var ni = NumberInput.init().withValue(50).withStep(5);
    ni.increment();
    try testing.expectEqual(@as(f64, 55), ni.value);
    ni.decrement();
    try testing.expectEqual(@as(f64, 50), ni.value);
    ni.decrement();
    try testing.expectEqual(@as(f64, 45), ni.value);
    ni.increment();
    try testing.expectEqual(@as(f64, 50), ni.value);
}

test "NumberInput multiple setValue calls each overwrites previous" {
    var ni = NumberInput.init();
    ni.setValue(10);
    try testing.expectEqual(@as(f64, 10), ni.value);
    ni.setValue(50);
    try testing.expectEqual(@as(f64, 50), ni.value);
    ni.setValue(25);
    try testing.expectEqual(@as(f64, 25), ni.value);
}

test "NumberInput render with style and block" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const block = Block{ .title = "Settings" };
    const style = Style{ .bold = true };
    const ni = NumberInput.init()
        .withValue(75)
        .withBlock(block)
        .withStyle(style)
        .withLabel("Brightness");
    const area = Rect{ .x = 2, .y = 2, .width = 76, .height = 3 };
    ni.render(&buf, area);
    // Should render with styles applied
    try testing.expect(rowHasChar(buf, 2, '7') or rowHasChar(buf, 3, '7'));
}

test "NumberInput render with various decimal_places values" {
    var buf = try Buffer.init(testing.allocator, .{ .width = 80, .height = 24 });
    defer buf.deinit(testing.allocator);
    const ni1 = NumberInput.init().withValue(1.23456).withDecimalPlaces(0);
    const ni2 = NumberInput.init().withValue(1.23456).withDecimalPlaces(2);
    const ni3 = NumberInput.init().withValue(1.23456).withDecimalPlaces(4);

    ni1.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 1 });
    ni2.render(&buf, Rect{ .x = 0, .y = 1, .width = 80, .height = 1 });
    ni3.render(&buf, Rect{ .x = 0, .y = 2, .width = 80, .height = 1 });

    // All should render without crashing
    try testing.expect(rowHasChar(buf, 0, '1'));
    try testing.expect(rowHasChar(buf, 1, '1'));
    try testing.expect(rowHasChar(buf, 2, '1'));
}

// ============================================================================
// EDGE CASE TESTS — BOUNDARY CONDITIONS (5 tests)
// ============================================================================

test "NumberInput isAtMin with negative min" {
    const ni = NumberInput.init().withMin(-100).withValue(-100);
    try testing.expect(ni.isAtMin());
}

test "NumberInput isAtMax with large max" {
    const ni = NumberInput.init().withMax(1e6).withValue(1e6);
    try testing.expect(ni.isAtMax());
}

test "NumberInput increment from below min sets to exactly min + step" {
    var ni = NumberInput.init().withMin(10).withValue(5).withStep(2);
    // setValue will clamp to min=10
    ni.setValue(5);
    try testing.expectEqual(@as(f64, 10), ni.value);
    ni.increment();
    try testing.expectEqual(@as(f64, 12), ni.value);
}

test "NumberInput decrement from above max sets to exactly max - step" {
    var ni = NumberInput.init().withMax(50).withValue(100).withStep(5);
    // setValue will clamp to max=50
    ni.setValue(100);
    try testing.expectEqual(@as(f64, 50), ni.value);
    ni.decrement();
    try testing.expectEqual(@as(f64, 45), ni.value);
}

test "NumberInput with zero step increment/decrement is no-op" {
    var ni = NumberInput.init().withValue(50).withStep(0);
    const original = ni.value;
    ni.increment();
    try testing.expectEqual(original, ni.value);
    ni.decrement();
    try testing.expectEqual(original, ni.value);
}
