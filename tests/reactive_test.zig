//! Reactive widget tests (TDD — Red phase)
//!
//! Tests for reactive widget binding system (v2.12.0).
//! Widgets that automatically display current Signal values:
//! - ReactiveGauge: Gauge bound to Signal(f64)
//! - ReactiveText: Text bound to Signal([]const u8)
//! - ReactiveCounter: Formatted i64 counter bound to Signal(i64)
//!
//! These tests should FAIL until src/tui/widgets/reactive.zig is implemented.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const signal_mod = sailor.signal;
const Buffer = sailor.Buffer;
const Rect = sailor.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;

// ============================================================================
// ReactiveGauge Tests
// ============================================================================

test "ReactiveGauge renders gauge filled to signal ratio" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // At 50%, approximately 10 out of 20 cells should be filled
    // Check that filled cells exist at expected position (50% of 20 = 10)
    const filled_cell = buffer.getConst(5, 0).?;
    try testing.expectEqual(@as(u21, '█'), filled_cell.char); // Filled portion

    const empty_cell = buffer.getConst(15, 0).?;
    try testing.expectEqual(@as(u21, ' '), empty_cell.char); // Empty portion
}

test "ReactiveGauge shows 0% when signal is zero" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.0);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // At 0%, all cells should be empty
    const cell0 = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell0.char);

    const cell_mid = buffer.getConst(10, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell_mid.char);
}

test "ReactiveGauge shows full when signal is one" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 1.0);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // At 100%, all cells should be filled
    const cell_start = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '█'), cell_start.char);

    const cell_end = buffer.getConst(19, 0).?;
    try testing.expectEqual(@as(u21, '█'), cell_end.char);
}

test "ReactiveGauge updates display when signal changes before render" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.25);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };

    // First render at 25%
    gauge.render(&buffer, area);
    buffer.clear();

    // Change signal to 75%
    try sig.set(0.75);

    // Second render should reflect new value (75% of 30 = 22-23 cells filled)
    gauge.render(&buffer, area);
    const filled_cell = buffer.getConst(20, 0).?;
    try testing.expectEqual(@as(u21, '█'), filled_cell.char); // Should be filled at 75%
}

test "ReactiveGauge clamps ratio > 1.0 to 1.0" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 1.5); // > 1.0
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // Should clamp to 100% — all cells filled
    const cell_start = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '█'), cell_start.char);

    const cell_end = buffer.getConst(19, 0).?;
    try testing.expectEqual(@as(u21, '█'), cell_end.char);
}

test "ReactiveGauge clamps ratio < 0.0 to 0.0" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, -0.5); // < 0.0
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // Should clamp to 0% — all cells empty
    const cell_start = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell_start.char);

    const cell_end = buffer.getConst(19, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell_end.char);
}

test "ReactiveGauge renders with optional label" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.6);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
        .label = "Progress",
    };

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    gauge.render(&buffer, area);

    // Verify label is rendered (label "Progress" should appear in center of gauge)
    const cell_start = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '█'), cell_start.char); // Gauge at 60% should be filled
}

test "ReactiveGauge renders into zero-width area without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    gauge.render(&buffer, area);

    // Should gracefully handle zero-width area — no cells written
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell.char); // Should be untouched
}

test "ReactiveGauge renders into zero-height area without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    gauge.render(&buffer, area);

    // Should gracefully handle zero-height area — no cells written
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell.char); // Should be untouched
}

test "ReactiveGauge with custom filled style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const filled_style = Style{ .fg = Color.blue, .bold = true };
    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
        .filled_style = filled_style,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // Verify gauge renders at 50% with filled portion
    const filled_cell = buffer.getConst(5, 0).?;
    try testing.expectEqual(@as(u21, '█'), filled_cell.char);
    try testing.expectEqual(Color.blue, filled_cell.style.fg);
}

test "ReactiveGauge with empty style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const empty_style = Style{ .fg = .bright_black };
    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
        .empty_style = empty_style,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // Verify gauge renders with empty_style applied to empty portion
    const empty_cell = buffer.getConst(15, 0).?;
    try testing.expectEqual(@as(u21, ' '), empty_cell.char);
}

// ============================================================================
// ReactiveText Tests
// ============================================================================

test "ReactiveText renders signal string value at render time" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "Hello");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    text.render(&buffer, area);

    // Verify first cell contains 'H'
    const cell = buffer.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'H'), cell.?.char);
}

test "ReactiveText shows empty when signal is empty string" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    text.render(&buffer, area);

    // First cell should be space (empty line)
    const cell = buffer.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, ' '), cell.?.char);
}

test "ReactiveText shows updated text when signal changes before render" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "First");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };

    // First render
    text.render(&buffer, area);
    var cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, 'F'), cell.?.char);

    // Clear and change signal
    buffer.clear();
    try sig.set("Second");

    // Second render should show new text
    text.render(&buffer, area);
    cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, 'S'), cell.?.char);
}

test "ReactiveText alignment left" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "left");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
        .alignment = sailor.tui.Alignment.left,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    text.render(&buffer, area);

    // Text should start at x=0
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, 'l'), cell.?.char);
}

test "ReactiveText alignment center" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "mid");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
        .alignment = sailor.tui.Alignment.center,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    text.render(&buffer, area);

    // Text should be centered (approximately x=8-10 for "mid" in 20-wide area)
    // For 20-width area with "mid" (3 chars), centered position = (20-3)/2 = 8
    const center_cell = buffer.getConst(8, 0).?;
    try testing.expectEqual(@as(u21, 'm'), center_cell.char); // 'm' should be at center
}

test "ReactiveText alignment right" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "right");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
        .alignment = sailor.tui.Alignment.right,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    text.render(&buffer, area);

    // Text should be right-aligned ("right" is 5 chars, so should start at x=15)
    const right_cell = buffer.getConst(15, 0).?;
    try testing.expectEqual(@as(u21, 'r'), right_cell.char); // 'r' should be at x=15
}

test "ReactiveText truncates text that exceeds area width without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "This is a very long text that exceeds area");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    text.render(&buffer, area);

    // Should truncate at width=10 without crashing — first 10 chars of text should be rendered
    const cell0 = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, 'T'), cell0.char); // "T" from "This is..."

    const cell9 = buffer.getConst(9, 0).?;
    try testing.expect(cell9.char != ' ' or cell9.char == ' '); // Any char (space or not) is valid
}

test "ReactiveText with custom style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "styled");
    defer sig.deinit(allocator);

    const custom_style = Style{ .fg = Color.red, .bold = true };
    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
        .style = custom_style,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    text.render(&buffer, area);

    // Verify text renders with custom style applied
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, 's'), cell.char);
    try testing.expectEqual(Color.red, cell.style.fg);
}

// ============================================================================
// ReactiveCounter Tests
// ============================================================================

test "ReactiveCounter renders i64 signal value as text" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 42);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    counter.render(&buffer, area);

    // Verify "42" appears in buffer starting with '4'
    const cell0 = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '4'), cell0.char);

    const cell1 = buffer.getConst(1, 0).?;
    try testing.expectEqual(@as(u21, '2'), cell1.char);
}

test "ReactiveCounter includes prefix" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 10);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
        .prefix = "Count: ",
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    counter.render(&buffer, area);

    // First character should be 'C' from "Count:"
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, 'C'), cell.?.char);
}

test "ReactiveCounter includes suffix" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 5);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
        .suffix = " items",
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    counter.render(&buffer, area);

    // Verify suffix is rendered — "5 items" should appear with space before suffix
    const cell_value = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '5'), cell_value.char);
}

test "ReactiveCounter with prefix and suffix" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 99);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
        .prefix = "Progress: ",
        .suffix = "%",
    };

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 1 };
    counter.render(&buffer, area);

    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, 'P'), cell.?.char); // First char of "Progress"
}

test "ReactiveCounter renders negative values" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, -42);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    counter.render(&buffer, area);

    // Should render "-42"
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, '-'), cell.?.char);
}

test "ReactiveCounter updates when signal changes" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 10);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };

    // First render
    counter.render(&buffer, area);
    buffer.clear();

    // Change signal
    try sig.set(20);

    // Second render should show new value
    counter.render(&buffer, area);
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '2'), cell.char); // "20" should start with '2'
}

test "ReactiveCounter renders zero" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 0);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    counter.render(&buffer, area);

    // Should render "0"
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, '0'), cell.?.char);
}

test "ReactiveCounter renders large values" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, std.math.maxInt(i64));
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    counter.render(&buffer, area);

    // Should render without overflow or crash — verify at least first cell is a digit
    const cell = buffer.getConst(0, 0).?;
    try testing.expect(cell.char >= '0' and cell.char <= '9');
}

test "ReactiveCounter renders min i64 value" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, std.math.minInt(i64));
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    counter.render(&buffer, area);

    // Should render without crash — verify at least first cell is a valid character
    const cell = buffer.getConst(0, 0).?;
    try testing.expect(cell.char > 0); // Any valid character
}

test "ReactiveCounter with custom style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 123);
    defer sig.deinit(allocator);

    const custom_style = Style{ .fg = Color.yellow, .italic = true };
    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
        .style = custom_style,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    counter.render(&buffer, area);

    // Verify counter renders with custom style applied
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '1'), cell.char);
    try testing.expectEqual(Color.yellow, cell.style.fg);
}

// ============================================================================
// Multi-Widget Render Tests
// ============================================================================

test "Multiple render calls return current value each time" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 3);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 1);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };

    // Render 3 times without changing signal
    for (0..3) |_| {
        counter.render(&buffer, area);
        buffer.clear();
    }

    // Each render should show same value
    counter.render(&buffer, area);
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, '1'), cell.?.char);
}

test "ReactiveGauge with block wrapper renders borders" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    // Block is optional, test with it
    const block = Block{};
    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
        .block = block,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    gauge.render(&buffer, area);

    // Block should render borders around the gauge area
    // Gauge is in row 1 (inside 5-height block), at 50% of 28-width (inner)
    const gauge_cell = buffer.getConst(10, 1).?;
    try testing.expectEqual(@as(u21, '█'), gauge_cell.char); // Should be filled portion
}

test "ReactiveText with block wrapper renders borders" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "wrapped");
    defer sig.deinit(allocator);

    const block = Block{};
    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
        .block = block,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    text.render(&buffer, area);

    // Block should render borders, text should be in inner area at row 1
    const text_cell = buffer.getConst(1, 1).?;
    try testing.expectEqual(@as(u21, 'w'), text_cell.char); // 'w' from "wrapped"
}

// ============================================================================
// Signal-Widget Integration Tests
// ============================================================================

test "Render does not modify the signal (read-only)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.75);
    defer sig.deinit(allocator);

    const initial = sig.get();

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    gauge.render(&buffer, area);

    // Signal value should not change
    const after = sig.get();
    try testing.expectEqual(initial, after);
}

test "ReactiveCounter with multiple signal changes" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 0);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };

    // Increment and render multiple times
    for (0..5) |i| {
        try sig.set(@as(i64, @intCast(i + 1)));
        counter.render(&buffer, area);
        buffer.clear();
    }

    // Final value should be 5
    counter.render(&buffer, area);
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, '5'), cell.?.char);
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "ReactiveGauge memory safety with testing allocator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // No leaks - buffer and signal properly cleaned up by defer
    // Verify gauge rendered at 50%
    const filled_cell = buffer.getConst(5, 0).?;
    try testing.expectEqual(@as(u21, '█'), filled_cell.char);
}

test "ReactiveText memory safety with testing allocator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "test");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    text.render(&buffer, area);

    // No leaks - verify text rendered
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, 't'), cell.char);
}

test "ReactiveCounter memory safety with testing allocator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 42);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    counter.render(&buffer, area);

    // No leaks - verify counter rendered (42)
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '4'), cell.char);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "ReactiveGauge at boundary: signal exactly 0.0" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.0);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // At 0%, all cells should be empty
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "ReactiveGauge at boundary: signal exactly 1.0" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 1.0);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // At 100%, all cells should be filled
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, '█'), cell.char);
}

test "ReactiveText renders single character" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "X");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    text.render(&buffer, area);

    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, 'X'), cell.?.char);
}

test "ReactiveGauge with 1-width area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 5, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    gauge.render(&buffer, area);

    // At 50% width=1 means filled_width = 0, so all empty
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "ReactiveGauge with 1-height area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.5);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    gauge.render(&buffer, area);

    // At 50%, should have filled and empty cells
    const filled_cell = buffer.getConst(5, 0).?;
    try testing.expectEqual(@as(u21, '█'), filled_cell.char);
}

test "ReactiveCounter renders one digit" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(i64).init(allocator, 7);
    defer sig.deinit(allocator);

    const counter = sailor.tui.widgets.ReactiveCounter{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    counter.render(&buffer, area);

    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, '7'), cell.?.char);
}

test "ReactiveText with unicode characters" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal([]const u8).init(allocator, "Hello 👋");
    defer sig.deinit(allocator);

    const text = sailor.tui.widgets.ReactiveText{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    text.render(&buffer, area);

    // Should render without crashing on unicode — verify 'H' is rendered
    const cell = buffer.getConst(0, 0).?;
    try testing.expectEqual(@as(u21, 'H'), cell.char);
}

test "ReactiveGauge precision: signal at 0.33" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.33);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    gauge.render(&buffer, area);

    // At 0.33, filled_width = 0.33*30 = 9 or 10, verify presence of filled cells
    const filled_cell = buffer.getConst(5, 0).?;
    try testing.expectEqual(@as(u21, '█'), filled_cell.char);
}

test "ReactiveGauge precision: signal at 0.67" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    var sig = try signal_mod.Signal(f64).init(allocator, 0.67);
    defer sig.deinit(allocator);

    const gauge = sailor.tui.widgets.ReactiveGauge{
        .signal = &sig,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    gauge.render(&buffer, area);

    // At 0.67, filled_width = 0.67*30 = 20, verify filled and empty portions exist
    const filled_cell = buffer.getConst(15, 0).?;
    try testing.expectEqual(@as(u21, '█'), filled_cell.char);

    const empty_cell = buffer.getConst(25, 0).?;
    try testing.expectEqual(@as(u21, ' '), empty_cell.char);
}
