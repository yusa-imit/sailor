const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const ProgressRing = tui.widgets.ProgressRing;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "ProgressRing init with value 0.0" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(@as(f32, 0.0), ring.value);
}

test "ProgressRing init with value 0.5" {
    const ring = ProgressRing.init(0.5);
    try testing.expectEqual(@as(f32, 0.5), ring.value);
}

test "ProgressRing init with value 1.0" {
    const ring = ProgressRing.init(1.0);
    try testing.expectEqual(@as(f32, 1.0), ring.value);
}

test "ProgressRing init defaults filled_char to █" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(@as(u21, '█'), ring.filled_char);
}

test "ProgressRing init defaults empty_char to ░" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(@as(u21, '░'), ring.empty_char);
}

test "ProgressRing init defaults filled_style to empty" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(Style{}, ring.filled_style);
}

test "ProgressRing init defaults empty_style to empty" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(Style{}, ring.empty_style);
}

test "ProgressRing init defaults label to empty string" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqualStrings("", ring.label);
}

test "ProgressRing init defaults label_style to empty" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(Style{}, ring.label_style);
}

test "ProgressRing init defaults show_percentage to true" {
    const ring = ProgressRing.init(0.0);
    try testing.expect(ring.show_percentage);
}

test "ProgressRing init defaults thickness to 2" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(@as(u8, 2), ring.thickness);
}

test "ProgressRing init defaults block to null" {
    const ring = ProgressRing.init(0.0);
    try testing.expect(ring.block == null);
}

// ============================================================================
// SETVALUE TESTS
// ============================================================================

test "ProgressRing setValue sets exact value" {
    var ring = ProgressRing.init(0.0);
    ring.setValue(0.75);
    try testing.expectEqual(@as(f32, 0.75), ring.value);
}

test "ProgressRing setValue allows value > 1.0" {
    var ring = ProgressRing.init(0.0);
    ring.setValue(1.5);
    try testing.expectEqual(@as(f32, 1.5), ring.value);
}

test "ProgressRing setValue allows value < 0.0" {
    var ring = ProgressRing.init(0.5);
    ring.setValue(-0.5);
    try testing.expectEqual(@as(f32, -0.5), ring.value);
}

test "ProgressRing setValue(0.0)" {
    var ring = ProgressRing.init(1.0);
    ring.setValue(0.0);
    try testing.expectEqual(@as(f32, 0.0), ring.value);
}

test "ProgressRing setValue(1.0)" {
    var ring = ProgressRing.init(0.0);
    ring.setValue(1.0);
    try testing.expectEqual(@as(f32, 1.0), ring.value);
}

// ============================================================================
// SETVALUECLAMPED TESTS
// ============================================================================

test "ProgressRing setValueClamped with 0.5 stays 0.5" {
    var ring = ProgressRing.init(0.0);
    ring.setValueClamped(0.5);
    try testing.expectEqual(@as(f32, 0.5), ring.value);
}

test "ProgressRing setValueClamped with 1.5 clamps to 1.0" {
    var ring = ProgressRing.init(0.0);
    ring.setValueClamped(1.5);
    try testing.expectEqual(@as(f32, 1.0), ring.value);
}

test "ProgressRing setValueClamped with -0.5 clamps to 0.0" {
    var ring = ProgressRing.init(0.5);
    ring.setValueClamped(-0.5);
    try testing.expectEqual(@as(f32, 0.0), ring.value);
}

test "ProgressRing setValueClamped exactly 1.0 stays 1.0" {
    var ring = ProgressRing.init(0.0);
    ring.setValueClamped(1.0);
    try testing.expectEqual(@as(f32, 1.0), ring.value);
}

test "ProgressRing setValueClamped exactly 0.0 stays 0.0" {
    var ring = ProgressRing.init(1.0);
    ring.setValueClamped(0.0);
    try testing.expectEqual(@as(f32, 0.0), ring.value);
}

test "ProgressRing setValueClamped with very large value clamps to 1.0" {
    var ring = ProgressRing.init(0.0);
    ring.setValueClamped(999.0);
    try testing.expectEqual(@as(f32, 1.0), ring.value);
}

test "ProgressRing setValueClamped with very small value clamps to 0.0" {
    var ring = ProgressRing.init(0.5);
    ring.setValueClamped(-999.0);
    try testing.expectEqual(@as(f32, 0.0), ring.value);
}

// ============================================================================
// PERCENTAGE TESTS
// ============================================================================

test "ProgressRing percentage at 0.0 returns 0" {
    const ring = ProgressRing.init(0.0);
    try testing.expectEqual(@as(u8, 0), ring.percentage());
}

test "ProgressRing percentage at 1.0 returns 100" {
    const ring = ProgressRing.init(1.0);
    try testing.expectEqual(@as(u8, 100), ring.percentage());
}

test "ProgressRing percentage at 0.5 returns 50" {
    const ring = ProgressRing.init(0.5);
    try testing.expectEqual(@as(u8, 50), ring.percentage());
}

test "ProgressRing percentage at 0.75 returns 75" {
    const ring = ProgressRing.init(0.75);
    try testing.expectEqual(@as(u8, 75), ring.percentage());
}

test "ProgressRing percentage at 0.254 returns 25" {
    const ring = ProgressRing.init(0.254);
    try testing.expectEqual(@as(u8, 25), ring.percentage());
}

test "ProgressRing percentage at 0.999 returns 99" {
    const ring = ProgressRing.init(0.999);
    try testing.expectEqual(@as(u8, 99), ring.percentage());
}

test "ProgressRing percentage clamps value 1.5 to 100" {
    const ring = ProgressRing.init(1.5);
    try testing.expectEqual(@as(u8, 100), ring.percentage());
}

test "ProgressRing percentage clamps value -0.5 to 0" {
    const ring = ProgressRing.init(-0.5);
    try testing.expectEqual(@as(u8, 0), ring.percentage());
}

test "ProgressRing percentage at 0.25 returns 25" {
    const ring = ProgressRing.init(0.25);
    try testing.expectEqual(@as(u8, 25), ring.percentage());
}

// ============================================================================
// BUILDER API - IMMUTABILITY
// ============================================================================

test "ProgressRing withValue preserves immutability" {
    const original = ProgressRing.init(0.0);
    const modified = original.withValue(0.75);
    try testing.expectEqual(@as(f32, 0.0), original.value);
    try testing.expectEqual(@as(f32, 0.75), modified.value);
}

test "ProgressRing withFilledChar preserves immutability" {
    const original = ProgressRing.init(0.0);
    const modified = original.withFilledChar('▓');
    try testing.expectEqual(@as(u21, '█'), original.filled_char);
    try testing.expectEqual(@as(u21, '▓'), modified.filled_char);
}

test "ProgressRing withEmptyChar preserves immutability" {
    const original = ProgressRing.init(0.0);
    const modified = original.withEmptyChar(' ');
    try testing.expectEqual(@as(u21, '░'), original.empty_char);
    try testing.expectEqual(@as(u21, ' '), modified.empty_char);
}

test "ProgressRing withFilledStyle preserves immutability" {
    const original = ProgressRing.init(0.0);
    const style = Style{ .fg = Color.red };
    const modified = original.withFilledStyle(style);
    try testing.expect(original.filled_style.fg == null);
    try testing.expect(modified.filled_style.fg != null);
}

test "ProgressRing withEmptyStyle preserves immutability" {
    const original = ProgressRing.init(0.0);
    const style = Style{ .fg = Color.blue };
    const modified = original.withEmptyStyle(style);
    try testing.expect(original.empty_style.fg == null);
    try testing.expect(modified.empty_style.fg != null);
}

test "ProgressRing withLabel preserves immutability" {
    const original = ProgressRing.init(0.0);
    const modified = original.withLabel("test");
    try testing.expectEqualStrings("", original.label);
    try testing.expectEqualStrings("test", modified.label);
}

test "ProgressRing withLabelStyle preserves immutability" {
    const original = ProgressRing.init(0.0);
    const style = Style{ .fg = Color.green };
    const modified = original.withLabelStyle(style);
    try testing.expect(original.label_style.fg == null);
    try testing.expect(modified.label_style.fg != null);
}

test "ProgressRing withShowPercentage preserves immutability" {
    const original = ProgressRing.init(0.0);
    const modified = original.withShowPercentage(false);
    try testing.expect(original.show_percentage);
    try testing.expect(!modified.show_percentage);
}

test "ProgressRing withThickness preserves immutability" {
    const original = ProgressRing.init(0.0);
    const modified = original.withThickness(4);
    try testing.expectEqual(@as(u8, 2), original.thickness);
    try testing.expectEqual(@as(u8, 4), modified.thickness);
}

test "ProgressRing withBlock preserves immutability" {
    const original = ProgressRing.init(0.0);
    const block = Block{};
    const modified = original.withBlock(block);
    try testing.expect(original.block == null);
    try testing.expect(modified.block != null);
}

test "ProgressRing builder chain multiple methods" {
    const original = ProgressRing.init(0.0);
    const modified = original
        .withValue(0.5)
        .withThickness(4)
        .withShowPercentage(false);
    try testing.expectEqual(@as(f32, 0.0), original.value);
    try testing.expectEqual(@as(u8, 2), original.thickness);
    try testing.expect(original.show_percentage);

    try testing.expectEqual(@as(f32, 0.5), modified.value);
    try testing.expectEqual(@as(u8, 4), modified.thickness);
    try testing.expect(!modified.show_percentage);
}

test "ProgressRing withValue to 0.0" {
    const ring = ProgressRing.init(1.0).withValue(0.0);
    try testing.expectEqual(@as(f32, 0.0), ring.value);
}

test "ProgressRing withThickness to 1" {
    const ring = ProgressRing.init(0.0).withThickness(1);
    try testing.expectEqual(@as(u8, 1), ring.thickness);
}

test "ProgressRing withShowPercentage true then false" {
    const ring1 = ProgressRing.init(0.0).withShowPercentage(true);
    const ring2 = ring1.withShowPercentage(false);
    try testing.expect(!ring2.show_percentage);
}

// ============================================================================
// RENDER - ZERO/MINIMAL AREA
// ============================================================================

// ============================================================================
// RENDER - ZERO/MINIMAL AREA (safety: immediate return on degenerate input)
// ============================================================================

test "ProgressRing render with width 0 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    ProgressRing.init(0.5).render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 10 });
    // Just a crash safety test — no output expected on degenerate input
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "ProgressRing render with height 0 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    ProgressRing.init(0.5).render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 0 });
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "ProgressRing render with 1x1 area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 5);
    defer buf.deinit();
    ProgressRing.init(0.5).render(&buf, Rect{ .x = 0, .y = 0, .width = 1, .height = 1 });
    // outer_r = min(0.5, 1) - 0.5 = 0 → no ring cells, nothing to draw
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "ProgressRing render with 2x2 area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 5);
    defer buf.deinit();
    ProgressRing.init(0.5).render(&buf, Rect{ .x = 0, .y = 0, .width = 2, .height = 2 });
    // No meaningful output at 2x2, just no crash
}

test "ProgressRing render with 3x3 area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 5);
    defer buf.deinit();
    ProgressRing.init(0.5).render(&buf, Rect{ .x = 0, .y = 0, .width = 3, .height = 3 });
}

// ============================================================================
// RENDER - RING DETECTION
// Using 20x10 area: cx=9.5, cy=4.5, outer_r=9.5, inner_r=5.5 (thickness=2)
// Verified ring cell positions by geometry (dx, dy=row_delta*2, dist):
//   (10,0): dx= 0.5, dy=-9.0 → dist≈9.01 → angle≈0.009 (just past 12-o'clock CW)
//   (18,4): dx= 8.5, dy=-1.0 → dist≈8.56 → angle≈0.231 (3-o'clock side)
//   (1, 4): dx=-8.5, dy=-1.0 → dist≈8.56 → angle≈0.769 (9-o'clock side)
//   (9, 0): dx=-0.5, dy=-9.0 → dist≈9.01 → angle≈0.991 (just before 12-o'clock)
// Center (9,4): dist≈1.12 < inner_r=5.5 → NOT a ring cell
// ============================================================================

test "ProgressRing value=1.0 draws filled_char on ring cells" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(1.0).withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // All ring cells have value≤1.0, so all get filled_char
    try testing.expectEqual(@as(u21, '█'), buf.getChar(10, 0)); // angle≈0.009
    try testing.expectEqual(@as(u21, '█'), buf.getChar(18, 4)); // angle≈0.231
    try testing.expectEqual(@as(u21, '█'), buf.getChar(1, 4));  // angle≈0.769
    try testing.expectEqual(@as(u21, '█'), buf.getChar(9, 0));  // angle≈0.991
}

test "ProgressRing value=0.0 draws empty_char on all ring cells" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.0).withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // angle > 0.0 for all ring cells, so all get empty_char
    try testing.expectEqual(@as(u21, '░'), buf.getChar(10, 0)); // angle≈0.009 > 0.0
    try testing.expectEqual(@as(u21, '░'), buf.getChar(18, 4)); // angle≈0.231 > 0.0
    try testing.expectEqual(@as(u21, '░'), buf.getChar(1, 4));  // angle≈0.769 > 0.0
    try testing.expectEqual(@as(u21, '░'), buf.getChar(9, 0));  // angle≈0.991 > 0.0
}

test "ProgressRing value=0.5 fills clockwise first half of ring" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5).withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // (10,0) angle≈0.009 ≤ 0.5 → filled
    try testing.expectEqual(@as(u21, '█'), buf.getChar(10, 0));
    // (18,4) angle≈0.231 ≤ 0.5 → filled
    try testing.expectEqual(@as(u21, '█'), buf.getChar(18, 4));
    // (1,4) angle≈0.769 > 0.5 → empty
    try testing.expectEqual(@as(u21, '░'), buf.getChar(1, 4));
    // (9,0) angle≈0.991 > 0.5 → empty
    try testing.expectEqual(@as(u21, '░'), buf.getChar(9, 0));
}

test "ProgressRing center area cell is not a ring cell" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    // value=1.0 fills all ring cells, but center stays ' ' because dist < inner_r
    const ring = ProgressRing.init(1.0).withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // (9,4): dist≈1.12 < inner_r=5.5 → not a ring cell, stays ' '
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 4));
}

test "ProgressRing far corner is not a ring cell" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(1.0).withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // (0,0): dx=-9.5, dy=-9.0 → dist≈13.1 > outer_r=9.5 → not a ring cell, stays ' '
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

// ============================================================================
// RENDER - CUSTOM CHARS AND STYLES
// ============================================================================

test "ProgressRing withFilledChar renders custom char on filled ring cells" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(1.0).withFilledChar('=').withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // value=1.0 fills all ring cells; (10,0) is a ring cell
    try testing.expectEqual(@as(u21, '='), buf.getChar(10, 0));
    try testing.expectEqual(@as(u21, '='), buf.getChar(18, 4));
}

test "ProgressRing withEmptyChar renders custom char on empty ring cells" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.0).withEmptyChar('-').withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // value=0.0 makes all ring cells empty; (10,0) is a ring cell
    try testing.expectEqual(@as(u21, '-'), buf.getChar(10, 0));
    try testing.expectEqual(@as(u21, '-'), buf.getChar(18, 4));
}

test "ProgressRing withFilledStyle applies style to filled ring cells" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(1.0)
        .withFilledStyle(Style{ .fg = Color.green })
        .withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // (10,0) is a filled ring cell with value=1.0
    const cell_style = buf.getStyle(10, 0);
    try testing.expectEqual(Color.green, cell_style.fg.?);
}

test "ProgressRing withEmptyStyle applies style to empty ring cells" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.0)
        .withEmptyStyle(Style{ .fg = Color.gray })
        .withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // value=0.0: all ring cells are empty; (10,0) is a ring cell
    const cell_style = buf.getStyle(10, 0);
    try testing.expectEqual(Color.gray, cell_style.fg.?);
}

test "ProgressRing withFilledChar and withEmptyChar both used in partial render" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5)
        .withFilledChar('+')
        .withEmptyChar('.')
        .withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // (10,0) angle≈0.009 ≤ 0.5 → filled '+'
    try testing.expectEqual(@as(u21, '+'), buf.getChar(10, 0));
    // (9,0) angle≈0.991 > 0.5 → empty '.'
    try testing.expectEqual(@as(u21, '.'), buf.getChar(9, 0));
}

// ============================================================================
// RENDER - LABEL RENDERING
// 20x10 area: label_y = inner.y + inner.height/2 = 0 + 10/2 = 5
// "0%"   (2 bytes): label_x = 0 + (20-2)/2  = 9  → chars at (9,5) and (10,5)
// "50%"  (3 bytes): label_x = 0 + (20-3)/2  = 8  → chars at (8,5)(9,5)(10,5)
// "100%" (4 bytes): label_x = 0 + (20-4)/2  = 8  → chars at (8,5)(9,5)(10,5)(11,5)
// "X"    (1 byte):  label_x = 0 + (20-1)/2  = 9  → char at (9,5)
// Label cells verified NOT to be ring cells (all have dist < inner_r=5.5)
// ============================================================================

test "ProgressRing show_percentage=true value=0.0 displays 0%" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.0).withShowPercentage(true);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // "0%" at label_x=9, label_y=5
    try testing.expectEqual(@as(u21, '0'), buf.getChar(9, 5));
    try testing.expectEqual(@as(u21, '%'), buf.getChar(10, 5));
}

test "ProgressRing show_percentage=true value=1.0 displays 100%" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(1.0).withShowPercentage(true);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // "100%" at label_x=8, label_y=5
    try testing.expectEqual(@as(u21, '1'), buf.getChar(8, 5));
    try testing.expectEqual(@as(u21, '0'), buf.getChar(9, 5));
    try testing.expectEqual(@as(u21, '%'), buf.getChar(11, 5));
}

test "ProgressRing show_percentage=true value=0.5 displays 50%" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5).withShowPercentage(true);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // "50%" at label_x=8, label_y=5
    try testing.expectEqual(@as(u21, '5'), buf.getChar(8, 5));
    try testing.expectEqual(@as(u21, '0'), buf.getChar(9, 5));
    try testing.expectEqual(@as(u21, '%'), buf.getChar(10, 5));
}

test "ProgressRing custom label 'X' renders at center" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5).withLabel("X").withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // "X" (1 char): label_x = (20-1)/2 = 9, label_y = 5
    try testing.expectEqual(@as(u21, 'X'), buf.getChar(9, 5));
}

test "ProgressRing custom label 'OK' renders both chars at center" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5).withLabel("OK").withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // "OK" (2 chars): label_x = (20-2)/2 = 9, label_y = 5
    try testing.expectEqual(@as(u21, 'O'), buf.getChar(9, 5));
    try testing.expectEqual(@as(u21, 'K'), buf.getChar(10, 5));
}

test "ProgressRing custom label overrides show_percentage" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    // Label "Z" takes precedence over percentage display
    const ring = ProgressRing.init(0.5).withLabel("Z").withShowPercentage(true);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // label_x = (20-1)/2 = 9 → 'Z', not a percentage digit
    try testing.expectEqual(@as(u21, 'Z'), buf.getChar(9, 5));
}

test "ProgressRing show_percentage=false empty label writes nothing to center" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5).withLabel("").withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // No label written; center cell (9,5) is not a ring cell (dist≈1.12) → stays ' '
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 5));
}

test "ProgressRing label_style applies to center label chars" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5)
        .withLabel("X")
        .withLabelStyle(Style{ .fg = Color.red })
        .withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // label_x=9, label_y=5 → style should have red fg
    try testing.expectEqual(@as(u21, 'X'), buf.getChar(9, 5));
    try testing.expectEqual(Color.red, buf.getStyle(9, 5).fg.?);
}

// ============================================================================
// RENDER - BLOCK INTEGRATION
// ============================================================================

test "ProgressRing with block renders single-line border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 20);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5).withBlock(Block{});
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 20 });
    // Block{} uses BoxSet.single: top-left corner is '┌'
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(29, 0));
}

test "ProgressRing with block and offset area renders border at correct position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 25);
    defer buf.deinit();
    const ring = ProgressRing.init(0.75).withBlock(Block{});
    ring.render(&buf, Rect{ .x = 5, .y = 3, .width = 25, .height = 15 });
    // Corner at (area.x, area.y) = (5, 3)
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(5, 3));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(29, 3));
}

test "ProgressRing with block reduces available ring area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 20);
    defer buf.deinit();
    // With block, ring renders in innerArea which is 1 cell smaller on each side
    const ring = ProgressRing.init(0.0).withBlock(Block{}).withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 20 });
    // Block corner present, no crash, ring in inner area
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
}

// ============================================================================
// RENDER - OFFSET AREA RING DETECTION
// Area {x=5, y=3, width=20, height=10}: cx=14.5, cy=7.5, outer_r=9.5, inner_r=5.5
// Ring cell (10+5=15, 0+3=3): dx=0.5, dy=-9.0, dist≈9.01 → ON RING, angle≈0.009
// ============================================================================

test "ProgressRing render at offset position: ring cells at correct location" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 20);
    defer buf.deinit();
    const ring = ProgressRing.init(1.0).withShowPercentage(false);
    ring.render(&buf, Rect{ .x = 5, .y = 3, .width = 20, .height = 10 });
    // Top-center ring cell shifted: was (10,0) in 0-origin → now (15, 3)
    try testing.expectEqual(@as(u21, '█'), buf.getChar(15, 3));
    // Non-ring area origin not touched
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "ProgressRing render with x offset only" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 15);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5);
    ring.render(&buf, Rect{ .x = 10, .y = 0, .width = 20, .height = 10 });
    // No crash; left portion of buffer untouched
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 0));
}

test "ProgressRing render with y offset only" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 20);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5);
    ring.render(&buf, Rect{ .x = 0, .y = 5, .width = 20, .height = 10 });
    // Top rows untouched
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 4));
}

// ============================================================================
// RENDER - THICKNESS VARIATIONS (crash safety)
// ============================================================================

test "ProgressRing render with thickness 1 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 25, 15);
    defer buf.deinit();
    ProgressRing.init(0.5).withThickness(1).withShowPercentage(false)
        .render(&buf, Rect{ .x = 0, .y = 0, .width = 25, .height = 15 });
    // Ring exists, check one expected ring cell
    // 25x15: cx=12, cy=7, outer_r=7.5, inner_r=7.5-2=5.5 → thickness=1: inner_r=7.5-2=5.5
    // Actually thickness=1: inner_r = outer_r - 2.0 = 5.5 (since we subtract t*2)
    // Wait: inner_r = outer_r - thickness*2 = 7.5 - 1*2 = 5.5
    // (13, 0): dx=0.5, dy=-14.0, dist≈14.01 > 7.5? No that's wrong.
    // Let me recalculate: 25x15, outer_r = min(12.5, 15) - 0.5 = 12.0
    // inner_r = 12.0 - 1*2 = 10.0
    // (13, 0): dx=0.5, dy=(0-7)*2=-14, dist=sqrt(0.25+196)≈14.01 > 12.0 → NOT ring
    // Hmm, harder to predict. Just verify no crash.
    _ = buf.getChar(0, 0); // access something to avoid unused warning
}

test "ProgressRing render with thickness 3 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 25, 15);
    defer buf.deinit();
    ProgressRing.init(0.5).withThickness(3).withShowPercentage(false)
        .render(&buf, Rect{ .x = 0, .y = 0, .width = 25, .height = 15 });
}

test "ProgressRing render with thickness 4 does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 25, 15);
    defer buf.deinit();
    ProgressRing.init(0.5).withThickness(4).withShowPercentage(false)
        .render(&buf, Rect{ .x = 0, .y = 0, .width = 25, .height = 15 });
}

test "ProgressRing render with very large thickness clamps inner_r to 0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    // thickness=255: inner_r = max(0, 9.5 - 255*2) = 0 → whole circle is ring
    ProgressRing.init(1.0).withThickness(255).withShowPercentage(false)
        .render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // Center cell is now inside the ring (inner_r=0), gets filled
    try testing.expectEqual(@as(u21, '█'), buf.getChar(9, 4));
}

test "ProgressRing render with thickness 0 renders nothing (no ring)" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    // thickness=0: inner_r = outer_r - 0 = outer_r → inner_r == outer_r, no range → no ring cells
    ProgressRing.init(1.0).withThickness(0).withShowPercentage(false)
        .render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // No ring cells written; label area is center → percentage written if show_percentage=true
    // With show_percentage=false: center stays ' '
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 0)); // was ring cell for t=2, but not for t=0
}

// ============================================================================
// RENDER - SEQUENTIAL CALLS
// ============================================================================

test "ProgressRing sequential render changes output" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    // First render: value=0.0 → empty ring
    ProgressRing.init(0.0).withShowPercentage(false).render(&buf, area);
    try testing.expectEqual(@as(u21, '░'), buf.getChar(10, 0));

    // Second render: value=1.0 → filled ring (overwrites same cells)
    ProgressRing.init(1.0).withShowPercentage(false).render(&buf, area);
    try testing.expectEqual(@as(u21, '█'), buf.getChar(10, 0));
}

test "ProgressRing setValue then render reflects new value" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    var ring = ProgressRing.init(0.0).withShowPercentage(false);

    ring.render(&buf, area);
    try testing.expectEqual(@as(u21, '░'), buf.getChar(10, 0));

    ring.setValue(1.0);
    ring.render(&buf, area);
    try testing.expectEqual(@as(u21, '█'), buf.getChar(10, 0));
}

// ============================================================================
// RENDER - COMBINATIONS
// ============================================================================

test "ProgressRing with block and label: both render correctly" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 20);
    defer buf.deinit();
    const ring = ProgressRing.init(0.75)
        .withBlock(Block{})
        .withLabel("OK");
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 20 });
    // Block corner rendered
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    // "OK" label in inner area center (28x18 inner area):
    // label_y = 1 + 18/2 = 10, label_x = 1 + (28-2)/2 = 14
    try testing.expectEqual(@as(u21, 'O'), buf.getChar(14, 10));
    try testing.expectEqual(@as(u21, 'K'), buf.getChar(15, 10));
}

test "ProgressRing all features combined does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 35, 25);
    defer buf.deinit();
    const ring = ProgressRing.init(0.7)
        .withFilledChar('◆')
        .withEmptyChar('◇')
        .withFilledStyle(Style{ .fg = Color.cyan, .bold = true })
        .withEmptyStyle(Style{ .fg = Color.gray })
        .withLabel("PROG")
        .withLabelStyle(Style{ .fg = Color.yellow })
        .withThickness(2)
        .withBlock(Block{});
    ring.render(&buf, Rect{ .x = 0, .y = 0, .width = 35, .height = 25 });
    // Block corner present
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
}

// ============================================================================
// EDGE CASES
// ============================================================================

test "ProgressRing with value slightly above 1.0 (no clamping in render)" {
    const ring = ProgressRing.init(1.001);
    try testing.expect(ring.value > 1.0);
}

test "ProgressRing with value slightly below 0.0 (no clamping in setValue)" {
    const ring = ProgressRing.init(-0.001);
    try testing.expect(ring.value < 0.0);
}

test "ProgressRing percentage at 0.504 returns 50" {
    const ring = ProgressRing.init(0.504);
    try testing.expectEqual(@as(u8, 50), ring.percentage());
}

test "ProgressRing percentage at 0.994 returns 99" {
    const ring = ProgressRing.init(0.994);
    try testing.expectEqual(@as(u8, 99), ring.percentage());
}

test "ProgressRing render large non-square area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 100, 20);
    defer buf.deinit();
    ProgressRing.init(0.5).render(&buf, Rect{ .x = 0, .y = 0, .width = 100, .height = 20 });
    // outer_r = min(50, 20) - 0.5 = 19.5; ring fits within height
    // No crash
}

test "ProgressRing render tall non-square area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 60);
    defer buf.deinit();
    ProgressRing.init(0.5).render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 60 });
    // outer_r = min(10, 60) - 0.5 = 9.5; constrained by width
    // No crash
}

test "ProgressRing buf.clear() between renders resets state" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    ProgressRing.init(1.0).withShowPercentage(false).render(&buf, area);
    try testing.expectEqual(@as(u21, '█'), buf.getChar(10, 0));

    buf.clear();
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 0));

    ProgressRing.init(0.0).withShowPercentage(false).render(&buf, area);
    try testing.expectEqual(@as(u21, '░'), buf.getChar(10, 0));
}

test "ProgressRing render in large buffer at middle position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 40);
    defer buf.deinit();
    const ring = ProgressRing.init(0.5);
    ring.render(&buf, Rect{ .x = 10, .y = 10, .width = 30, .height = 20 });
    // Cells outside area stay ' '
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 9));
}
