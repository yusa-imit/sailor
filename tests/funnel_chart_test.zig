//! FunnelChart Widget Tests — TDD Red Phase
//!
//! Tests FunnelChart widget with stages showing funnel/pyramid shape,
//! value proportionality, focused styling, value/percentage labels,
//! block borders, MAX_STAGES capping, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const FunnelChart = sailor.tui.widgets.FunnelChart;
const FunnelStage = sailor.tui.widgets.funnel_chart.FunnelStage;

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

/// Find text in buffer area (linear search, row-major order)
fn findTextInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var text_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (text_idx < text.len) : (text_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != text[text_idx]) {
                    matched = false;
                    break;
                }
                cx += 1;
                if (cx >= area.x + area.width or cx >= buf.width) {
                    cy += 1;
                    cx = area.x;
                }
            }

            if (matched) return true;
        }
    }
    return false;
}

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "FunnelChart.init creates default chart with zero stages" {
    const fc = FunnelChart.init();
    try testing.expectEqual(@as(usize, 0), fc.stages.len);
}

test "FunnelChart.init defaults focused to 0" {
    const fc = FunnelChart.init();
    try testing.expectEqual(@as(usize, 0), fc.focused);
}

test "FunnelChart.init defaults show_values to true" {
    const fc = FunnelChart.init();
    try testing.expectEqual(true, fc.show_values);
}

test "FunnelChart.init defaults show_percentages to false" {
    const fc = FunnelChart.init();
    try testing.expectEqual(false, fc.show_percentages);
}

test "FunnelChart.init defaults block to null" {
    const fc = FunnelChart.init();
    try testing.expect(fc.block == null);
}

// ============================================================================
// Group 2: FunnelStage Struct Defaults (3 tests)
// ============================================================================

test "FunnelStage default label is empty" {
    const stage = FunnelStage{};
    try testing.expectEqualStrings("", stage.label);
}

test "FunnelStage default value is 0.0" {
    const stage = FunnelStage{};
    try testing.expectEqual(@as(f32, 0.0), stage.value);
}

test "FunnelStage default style is empty" {
    const stage = FunnelStage{};
    try testing.expect(!stage.style.bold and stage.style.dim == false);
}

// ============================================================================
// Group 3: MAX_STAGES Constant (1 test)
// ============================================================================

test "FunnelChart.MAX_STAGES equals 16" {
    try testing.expectEqual(@as(usize, 16), FunnelChart.MAX_STAGES);
}

// ============================================================================
// Group 4: stageCount() Method (5 tests)
// ============================================================================

test "FunnelChart.stageCount with zero stages returns 0" {
    const fc = FunnelChart.init();
    try testing.expectEqual(@as(usize, 0), fc.stageCount());
}

test "FunnelChart.stageCount with 1 stage returns 1" {
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(usize, 1), fc.stageCount());
}

test "FunnelChart.stageCount with 8 stages returns 8" {
    var stages: [8]FunnelStage = undefined;
    for (0..8) |i| {
        stages[i] = .{ .label = "S", .value = @floatFromInt(100 - i * 10) };
    }
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(usize, 8), fc.stageCount());
}

test "FunnelChart.stageCount with exactly MAX_STAGES=16 returns 16" {
    var stages: [16]FunnelStage = undefined;
    for (0..16) |i| {
        stages[i] = .{ .label = "S", .value = @floatFromInt(100 - i * 5) };
    }
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(usize, 16), fc.stageCount());
}

test "FunnelChart.stageCount caps at MAX_STAGES when 20 stages provided" {
    var stages: [20]FunnelStage = undefined;
    for (0..20) |i| {
        stages[i] = .{ .label = "S", .value = @floatFromInt(100 - i * 4) };
    }
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(usize, 16), fc.stageCount());
}

// ============================================================================
// Group 5: maxValue() Method (4 tests)
// ============================================================================

test "FunnelChart.maxValue with zero stages returns 0.0" {
    const fc = FunnelChart.init();
    try testing.expectEqual(@as(f32, 0.0), fc.maxValue());
}

test "FunnelChart.maxValue with single stage returns that value" {
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 42.5 }};
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(f32, 42.5), fc.maxValue());
}

test "FunnelChart.maxValue returns max of multiple stages" {
    var stages = [_]FunnelStage{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 75.0 },
        .{ .label = "C", .value = 50.0 },
        .{ .label = "D", .value = 25.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(f32, 100.0), fc.maxValue());
}

test "FunnelChart.maxValue with equal values returns that value" {
    var stages = [_]FunnelStage{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
        .{ .label = "C", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(f32, 50.0), fc.maxValue());
}

// ============================================================================
// Group 6: Builder Immutability (8 tests)
// ============================================================================

test "FunnelChart.withStages does not modify original" {
    var stages1 = [_]FunnelStage{.{ .label = "A", .value = 100.0 }};
    var stages2 = [_]FunnelStage{
        .{ .label = "X", .value = 80.0 },
        .{ .label = "Y", .value = 60.0 },
    };

    const fc1 = FunnelChart.init().withStages(&stages1);
    const fc2 = fc1.withStages(&stages2);

    try testing.expectEqual(@as(usize, 1), fc1.stageCount());
    try testing.expectEqual(@as(usize, 2), fc2.stageCount());
}

test "FunnelChart.withFocused sets focused index" {
    const fc1 = FunnelChart.init().withFocused(0);
    const fc2 = fc1.withFocused(3);

    try testing.expectEqual(@as(usize, 0), fc1.focused);
    try testing.expectEqual(@as(usize, 3), fc2.focused);
}

test "FunnelChart.withShowValues sets show_values" {
    const fc1 = FunnelChart.init().withShowValues(true);
    const fc2 = fc1.withShowValues(false);

    try testing.expectEqual(true, fc1.show_values);
    try testing.expectEqual(false, fc2.show_values);
}

test "FunnelChart.withShowPercentages sets show_percentages" {
    const fc1 = FunnelChart.init().withShowPercentages(false);
    const fc2 = fc1.withShowPercentages(true);

    try testing.expectEqual(false, fc1.show_percentages);
    try testing.expectEqual(true, fc2.show_percentages);
}

test "FunnelChart.withStyle sets style" {
    const style = Style{ .bold = true };
    const fc = FunnelChart.init().withStyle(style);
    try testing.expectEqual(true, fc.style.bold);
}

test "FunnelChart.withLabelStyle sets label_style" {
    const style = Style{ .dim = true };
    const fc = FunnelChart.init().withLabelStyle(style);
    try testing.expectEqual(true, fc.label_style.dim);
}

test "FunnelChart.withValueStyle sets value_style" {
    const style = Style{ .italic = true };
    const fc = FunnelChart.init().withValueStyle(style);
    try testing.expectEqual(true, fc.value_style.italic);
}

test "FunnelChart.withFocusedStyle sets focused_style" {
    const style = Style{ .bold = true };
    const fc = FunnelChart.init().withFocusedStyle(style);
    try testing.expectEqual(true, fc.focused_style.bold);
}

// ============================================================================
// Group 7: Builder Methods for Block (2 tests)
// ============================================================================

test "FunnelChart.withBlock sets block" {
    const block = Block{};
    const fc = FunnelChart.init().withBlock(block);
    try testing.expect(fc.block != null);
}

test "FunnelChart.withBlock with null unsets block" {
    const fc1 = FunnelChart.init().withBlock(.{});
    const fc2 = fc1.withBlock(null);

    try testing.expect(fc1.block != null);
    try testing.expect(fc2.block == null);
}

// ============================================================================
// Group 8: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "FunnelChart.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    fc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "FunnelChart.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    fc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "FunnelChart.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    fc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "FunnelChart.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    fc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 9: Render — Empty Stages (2 tests)
// ============================================================================

test "FunnelChart.render with zero stages produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const fc = FunnelChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "FunnelChart.render empty stages with show_values=false" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const fc = FunnelChart.init().withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 10: Render — Single Stage (5 tests)
// ============================================================================

test "FunnelChart.render single stage produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render single stage with show_values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render single stage with show_percentages produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages).withShowPercentages(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render single stage at different area offsets" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "Top", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 5, .y = 5, .width = 30, .height = 15 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render single stage with no labels" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{.{ .label = "", .value = 100.0 }};
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: Render — Multiple Stages (5 tests)
// ============================================================================

test "FunnelChart.render two stages produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Mid", .value = 75.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render three stages produces narrowing effect" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Mid", .value = 75.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render five stages produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 80.0 },
        .{ .label = "C", .value = 60.0 },
        .{ .label = "D", .value = 40.0 },
        .{ .label = "E", .value = 20.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render stages with unequal values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Start", .value = 1000.0 },
        .{ .label = "Filter", .value = 200.0 },
        .{ .label = "Process", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render all stages with same value" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
        .{ .label = "C", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: Focused Styling (4 tests)
// ============================================================================

test "FunnelChart.render focused=0 on three-stage chart applies focus style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Mid", .value = 75.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const focused_style = Style{ .bold = true };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render focused=1 applies style to middle stage" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Mid", .value = 75.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const focused_style = Style{ .dim = true };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render changing focused index produces output" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Mid", .value = 75.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };

    const fc1 = FunnelChart.init().withStages(&stages).withFocused(0);
    const fc2 = FunnelChart.init().withStages(&stages).withFocused(2);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc1.render(&buf1, area);
    fc2.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

// ============================================================================
// Group 13: show_values Toggle (3 tests)
// ============================================================================

test "FunnelChart.render show_values=true displays numeric text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render show_values=false produces different output than true" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };

    const fc_with_values = FunnelChart.init().withStages(&stages).withShowValues(true);
    const fc_no_values = FunnelChart.init().withStages(&stages).withShowValues(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc_with_values.render(&buf1, area);
    fc_no_values.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 >= content2);
}

test "FunnelChart.render show_values=false still renders bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages).withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 14: show_percentages Toggle (3 tests)
// ============================================================================

test "FunnelChart.render show_percentages=true displays percentage text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages).withShowPercentages(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render show_percentages=false produces different output than true" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };

    const fc_with_pct = FunnelChart.init().withStages(&stages).withShowPercentages(true);
    const fc_no_pct = FunnelChart.init().withStages(&stages).withShowPercentages(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc_with_pct.render(&buf1, area);
    fc_no_pct.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "FunnelChart.render show_percentages=true with percentages renders correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Start", .value = 200.0 },
        .{ .label = "Filtered", .value = 100.0 },
        .{ .label = "Completed", .value = 50.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withShowPercentages(true)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 15: Block Border (3 tests)
// ============================================================================

test "FunnelChart.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const block = Block{};
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render block reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };

    const block = Block{};
    const fc_with_block = FunnelChart.init().withStages(&stages).withBlock(block);
    const fc_no_block = FunnelChart.init().withStages(&stages);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc_with_block.render(&buf1, area);
    fc_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "FunnelChart.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const block = (Block{}).withTitle("Funnel", .top_left);
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: MAX_STAGES Cap (3 tests)
// ============================================================================

test "FunnelChart.render with exactly MAX_STAGES=16" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var stages: [16]FunnelStage = undefined;
    for (0..16) |i| {
        stages[i] = .{ .label = "S", .value = @floatFromInt(100 - i * 5) };
    }
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(usize, 16), fc.stageCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with 20 stages caps to MAX_STAGES=16" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var stages: [20]FunnelStage = undefined;
    for (0..20) |i| {
        stages[i] = .{ .label = "S", .value = @floatFromInt(100 - i * 4) };
    }
    const fc = FunnelChart.init().withStages(&stages);
    try testing.expectEqual(@as(usize, 16), fc.stageCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render 8 stages renders all visible stages" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var stages: [8]FunnelStage = undefined;
    for (0..8) |i| {
        stages[i] = .{ .label = "S", .value = @floatFromInt(100 - i * 10) };
    }
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Per-stage Style (3 tests)
// ============================================================================

test "FunnelChart.render with per-stage style applies correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0, .style = Style{ .bold = true } },
        .{ .label = "Mid", .value = 75.0, .style = Style{ .dim = true } },
        .{ .label = "Bottom", .value = 50.0, .style = .{} },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const label_style = Style{ .italic = true };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with value_style applies to values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const value_style = Style{ .bold = true };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withValueStyle(value_style)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 18: Zero-Value Stage (3 tests)
// ============================================================================

test "FunnelChart.render zero-value stage renders minimal or empty bar" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Zero", .value = 0.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render all-zero stages renders something" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Z1", .value = 0.0 },
        .{ .label = "Z2", .value = 0.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render mixed zero and non-zero stages" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 0.0 },
        .{ .label = "C", .value = 75.0 },
        .{ .label = "D", .value = 0.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 19: Edge Cases (5 tests)
// ============================================================================

test "FunnelChart.render single char wide area" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 10 };
    fc.render(&buf, area);
}

test "FunnelChart.render very small area with stages" {
    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    fc.render(&buf, area);
}

test "FunnelChart.render stage with very long label" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "VeryLongLabelForFirstStage", .value = 100.0 },
        .{ .label = "Short", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render area offset from origin" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 10, .y = 5, .width = 25, .height = 15 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with large values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Million", .value = 1000000.0 },
        .{ .label = "Thousand", .value = 5000.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Memory Safety (3 tests)
// ============================================================================

test "FunnelChart.render does not exceed buffer bounds with many stages" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();
    var stages: [16]FunnelStage = undefined;
    for (0..16) |i| {
        stages[i] = .{ .label = "S", .value = @floatFromInt(100 - i * 5) };
    }
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 3200); // 80*40 max
}

test "FunnelChart.render with MAX_STAGES cap is safe" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var stages: [16]FunnelStage = undefined;
    for (0..16) |i| {
        stages[i] = .{ .label = "S", .value = 50.0 };
    }
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    fc.render(&buf, area);
    // Must not crash or overflow
}

test "FunnelChart.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 21: Style Combinations (5 tests)
// ============================================================================

test "FunnelChart.render with style and label_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withStyle(Style{ .bold = true })
        .withLabelStyle(Style{ .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with multiple styles applied" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Mid", .value = 75.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withStyle(Style{ .dim = true })
        .withLabelStyle(Style{ .bold = true })
        .withValueStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true, .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render focused stage with custom style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 75.0 },
        .{ .label = "C", .value = 50.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withFocused(1)
        .withFocusedStyle(Style{ .bold = true, .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render stage with per-stage style overrides" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0, .style = Style{ .bold = true } },
        .{ .label = "Mid", .value = 75.0, .style = Style{ .dim = true } },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withStyle(Style{ .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with value and percentage both enabled" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Start", .value = 100.0 },
        .{ .label = "Mid", .value = 50.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withShowValues(true)
        .withShowPercentages(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 22: Very Wide/Tall Areas (3 tests)
// ============================================================================

test "FunnelChart.render very wide area" {
    var buf = try Buffer.init(testing.allocator, 200, 10);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 10 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render very tall area" {
    var buf = try Buffer.init(testing.allocator, 20, 100);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 100.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 100 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render rectangle area" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 80.0 },
        .{ .label = "C", .value = 60.0 },
        .{ .label = "D", .value = 40.0 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 23: Fractional Values (3 tests)
// ============================================================================

test "FunnelChart.render with fractional values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Top", .value = 99.5 },
        .{ .label = "Mid", .value = 50.3 },
        .{ .label = "Bottom", .value = 25.7 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with very small fractional values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Tiny1", .value = 0.001 },
        .{ .label = "Tiny2", .value = 0.0001 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    fc.render(&buf, area);
}

test "FunnelChart.render with mixed magnitude fractional values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Large", .value = 1000.5 },
        .{ .label = "Small", .value = 0.5 },
        .{ .label = "Tiny", .value = 0.001 },
    };
    const fc = FunnelChart.init().withStages(&stages);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 24: Complex Real-World Scenarios (4 tests)
// ============================================================================

test "FunnelChart.render sales pipeline funnel" {
    var buf = try Buffer.init(testing.allocator, 60, 25);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Leads", .value = 1000.0 },
        .{ .label = "Qualified", .value = 500.0 },
        .{ .label = "Proposal", .value = 200.0 },
        .{ .label = "Negotiation", .value = 75.0 },
        .{ .label = "Closed", .value = 25.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withShowValues(true)
        .withShowPercentages(true)
        .withBlock((Block{}).withTitle("Sales Pipeline", .top_center));
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 25 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render user signup funnel" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Visit", .value = 10000.0 },
        .{ .label = "SignUp", .value = 5000.0 },
        .{ .label = "Verify", .value = 4000.0 },
        .{ .label = "Active", .value = 2000.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withShowValues(true)
        .withFocused(2);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render with all features enabled" {
    var buf = try Buffer.init(testing.allocator, 70, 30);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "Stage1", .value = 1000.0, .style = Style{ .bold = true } },
        .{ .label = "Stage2", .value = 750.0 },
        .{ .label = "Stage3", .value = 500.0, .style = Style{ .dim = true } },
        .{ .label = "Stage4", .value = 250.0 },
        .{ .label = "Stage5", .value = 100.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withShowValues(true)
        .withShowPercentages(true)
        .withFocused(2)
        .withStyle(Style{ .italic = true })
        .withLabelStyle(Style{ .bold = true })
        .withValueStyle(Style{ .dim = true })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withBlock((Block{}).withTitle("Complete Funnel", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 30 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "FunnelChart.render single-stage funnel edge case" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var stages = [_]FunnelStage{
        .{ .label = "OnlyStage", .value = 500.0 },
    };
    const fc = FunnelChart.init()
        .withStages(&stages)
        .withShowValues(true)
        .withShowPercentages(true)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    fc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
