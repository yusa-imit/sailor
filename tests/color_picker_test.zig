//! ColorPicker Widget Tests
//!
//! Tests for the ColorPicker widget supporting palette_256, palette_16, and rgb_sliders modes.
//! Coverage includes initialization, builder API, palette navigation, RGB slider navigation,
//! color selection, and rendering.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;

// Import ColorPicker and related types
const ColorPicker = sailor.tui.widgets.ColorPicker;
const ColorPickerMode = sailor.tui.widgets.ColorPickerMode;
const RgbComponent = sailor.tui.widgets.RgbComponent;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "ColorPicker init with palette_256 mode" {
    const cp = ColorPicker.init(.palette_256);
    try testing.expectEqual(ColorPickerMode.palette_256, cp.mode);
}

test "ColorPicker init with palette_16 mode" {
    const cp = ColorPicker.init(.palette_16);
    try testing.expectEqual(ColorPickerMode.palette_16, cp.mode);
}

test "ColorPicker init with rgb_sliders mode" {
    const cp = ColorPicker.init(.rgb_sliders);
    try testing.expectEqual(ColorPickerMode.rgb_sliders, cp.mode);
}

test "ColorPicker init cursor starts at zero" {
    const cp = ColorPicker.init(.palette_256);
    try testing.expectEqual(@as(u8, 0), cp.cursor_x);
    try testing.expectEqual(@as(u8, 0), cp.cursor_y);
}

test "ColorPicker init RGB components default to zero" {
    const cp = ColorPicker.init(.rgb_sliders);
    try testing.expectEqual(@as(u8, 0), cp.r);
    try testing.expectEqual(@as(u8, 0), cp.g);
    try testing.expectEqual(@as(u8, 0), cp.b);
}

test "ColorPicker init active_component defaults to r" {
    const cp = ColorPicker.init(.rgb_sliders);
    try testing.expectEqual(RgbComponent.r, cp.active_component);
}

test "ColorPicker init block is null" {
    const cp = ColorPicker.init(.palette_256);
    try testing.expectEqual(null, cp.block);
}

test "ColorPicker init style is default" {
    const cp = ColorPicker.init(.palette_256);
    try testing.expectEqual(false, cp.style.bold);
    try testing.expectEqual(null, cp.style.fg);
}

test "ColorPicker init cursor_style is default" {
    const cp = ColorPicker.init(.palette_256);
    try testing.expectEqual(false, cp.cursor_style.bold);
}

// ============================================================================
// BUILDER PATTERN TESTS
// ============================================================================

test "ColorPicker withMode changes mode to palette_16" {
    var cp = ColorPicker.init(.palette_256);
    cp = cp.withMode(.palette_16);
    try testing.expectEqual(ColorPickerMode.palette_16, cp.mode);
}

test "ColorPicker withMode changes mode to rgb_sliders" {
    var cp = ColorPicker.init(.palette_256);
    cp = cp.withMode(.rgb_sliders);
    try testing.expectEqual(ColorPickerMode.rgb_sliders, cp.mode);
}

test "ColorPicker withBlock sets block" {
    var cp = ColorPicker.init(.palette_256);
    const block = (Block{}).withTitle("Color", .top_left);
    cp = cp.withBlock(block);
    try testing.expect(cp.block != null);
}

test "ColorPicker withStyle sets style" {
    var cp = ColorPicker.init(.palette_256);
    const style = Style{ .fg = Color.blue, .bold = true };
    cp = cp.withStyle(style);
    try testing.expectEqual(true, cp.style.bold);
    try testing.expectEqual(Color.blue, cp.style.fg.?);
}

test "ColorPicker withCursorStyle sets cursor_style" {
    var cp = ColorPicker.init(.palette_256);
    const style = Style{ .fg = Color.yellow, .bold = true };
    cp = cp.withCursorStyle(style);
    try testing.expectEqual(true, cp.cursor_style.bold);
    try testing.expectEqual(Color.yellow, cp.cursor_style.fg.?);
}

test "ColorPicker withColor from indexed sets cursor position" {
    var cp = ColorPicker.init(.palette_256);
    const color = Color{ .indexed = 65 };
    cp = cp.withColor(color);
    // Index 65 = row 4, col 1 (65 / 16 = 4, 65 % 16 = 1)
    try testing.expectEqual(@as(u8, 1), cp.cursor_x);
    try testing.expectEqual(@as(u8, 4), cp.cursor_y);
}

test "ColorPicker withColor from indexed at boundary (0)" {
    var cp = ColorPicker.init(.palette_256);
    const color = Color{ .indexed = 0 };
    cp = cp.withColor(color);
    try testing.expectEqual(@as(u8, 0), cp.cursor_x);
    try testing.expectEqual(@as(u8, 0), cp.cursor_y);
}

test "ColorPicker withColor from indexed at boundary (255)" {
    var cp = ColorPicker.init(.palette_256);
    const color = Color{ .indexed = 255 };
    cp = cp.withColor(color);
    // Index 255 = row 15, col 15
    try testing.expectEqual(@as(u8, 15), cp.cursor_x);
    try testing.expectEqual(@as(u8, 15), cp.cursor_y);
}

test "ColorPicker withColor from RGB sets r, g, b and switches mode" {
    var cp = ColorPicker.init(.palette_256);
    const color = Color{ .rgb = .{ .r = 100, .g = 150, .b = 200 } };
    cp = cp.withColor(color);
    try testing.expectEqual(@as(u8, 100), cp.r);
    try testing.expectEqual(@as(u8, 150), cp.g);
    try testing.expectEqual(@as(u8, 200), cp.b);
    try testing.expectEqual(ColorPickerMode.rgb_sliders, cp.mode);
}

test "ColorPicker withColor RGB at zero" {
    var cp = ColorPicker.init(.palette_256);
    const color = Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    cp = cp.withColor(color);
    try testing.expectEqual(@as(u8, 0), cp.r);
    try testing.expectEqual(@as(u8, 0), cp.g);
    try testing.expectEqual(@as(u8, 0), cp.b);
}

test "ColorPicker withColor RGB at max (255)" {
    var cp = ColorPicker.init(.palette_256);
    const color = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };
    cp = cp.withColor(color);
    try testing.expectEqual(@as(u8, 255), cp.r);
    try testing.expectEqual(@as(u8, 255), cp.g);
    try testing.expectEqual(@as(u8, 255), cp.b);
}

test "ColorPicker builder pattern chains" {
    var cp = ColorPicker.init(.palette_256);
    cp = cp.withMode(.rgb_sliders).withCursorStyle(Style{ .bold = true });
    try testing.expectEqual(ColorPickerMode.rgb_sliders, cp.mode);
    try testing.expectEqual(true, cp.cursor_style.bold);
}

// ============================================================================
// PALETTE_256 NAVIGATION TESTS
// ============================================================================

test "ColorPicker moveRight in palette_256 increments cursor_x" {
    var cp = ColorPicker.init(.palette_256);
    cp.moveRight();
    try testing.expectEqual(@as(u8, 1), cp.cursor_x);
}

test "ColorPicker moveRight multiple times in palette_256" {
    var cp = ColorPicker.init(.palette_256);
    cp.moveRight();
    cp.moveRight();
    cp.moveRight();
    try testing.expectEqual(@as(u8, 3), cp.cursor_x);
}

test "ColorPicker moveRight clamps at 15 in palette_256" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 15;
    cp.moveRight();
    try testing.expectEqual(@as(u8, 15), cp.cursor_x);
}

test "ColorPicker moveLeft in palette_256 decrements cursor_x" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 5;
    cp.moveLeft();
    try testing.expectEqual(@as(u8, 4), cp.cursor_x);
}

test "ColorPicker moveLeft clamps at 0 in palette_256" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 0;
    cp.moveLeft();
    try testing.expectEqual(@as(u8, 0), cp.cursor_x);
}

test "ColorPicker moveDown in palette_256 increments cursor_y" {
    var cp = ColorPicker.init(.palette_256);
    cp.moveDown();
    try testing.expectEqual(@as(u8, 1), cp.cursor_y);
}

test "ColorPicker moveDown multiple times in palette_256" {
    var cp = ColorPicker.init(.palette_256);
    cp.moveDown();
    cp.moveDown();
    cp.moveDown();
    try testing.expectEqual(@as(u8, 3), cp.cursor_y);
}

test "ColorPicker moveDown clamps at 15 in palette_256" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_y = 15;
    cp.moveDown();
    try testing.expectEqual(@as(u8, 15), cp.cursor_y);
}

test "ColorPicker moveUp in palette_256 decrements cursor_y" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_y = 5;
    cp.moveUp();
    try testing.expectEqual(@as(u8, 4), cp.cursor_y);
}

test "ColorPicker moveUp clamps at 0 in palette_256" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_y = 0;
    cp.moveUp();
    try testing.expectEqual(@as(u8, 0), cp.cursor_y);
}

// ============================================================================
// PALETTE_16 NAVIGATION TESTS
// ============================================================================

test "ColorPicker moveRight in palette_16 increments cursor_x" {
    var cp = ColorPicker.init(.palette_16);
    cp.moveRight();
    try testing.expectEqual(@as(u8, 1), cp.cursor_x);
}

test "ColorPicker moveRight clamps at 7 in palette_16" {
    var cp = ColorPicker.init(.palette_16);
    cp.cursor_x = 7;
    cp.moveRight();
    try testing.expectEqual(@as(u8, 7), cp.cursor_x);
}

test "ColorPicker moveDown in palette_16 increments cursor_y" {
    var cp = ColorPicker.init(.palette_16);
    cp.moveDown();
    try testing.expectEqual(@as(u8, 1), cp.cursor_y);
}

test "ColorPicker moveDown clamps at 1 in palette_16 (only 2 rows of 8)" {
    var cp = ColorPicker.init(.palette_16);
    cp.cursor_y = 1;
    cp.moveDown();
    try testing.expectEqual(@as(u8, 1), cp.cursor_y);
}

test "ColorPicker moveLeft in palette_16 works" {
    var cp = ColorPicker.init(.palette_16);
    cp.cursor_x = 3;
    cp.moveLeft();
    try testing.expectEqual(@as(u8, 2), cp.cursor_x);
}

test "ColorPicker moveUp in palette_16 decrements cursor_y" {
    var cp = ColorPicker.init(.palette_16);
    cp.cursor_y = 1;
    cp.moveUp();
    try testing.expectEqual(@as(u8, 0), cp.cursor_y);
}

// ============================================================================
// SELECTEDCOLOR PALETTE_256 TESTS
// ============================================================================

test "ColorPicker selectedColor at (0,0) returns index 0" {
    const cp = ColorPicker.init(.palette_256);
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .indexed = 0 }, color);
}

test "ColorPicker selectedColor at (1,0) returns index 1" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 1;
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .indexed = 1 }, color);
}

test "ColorPicker selectedColor at (0,1) returns index 16" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_y = 1;
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .indexed = 16 }, color);
}

test "ColorPicker selectedColor at (5,3) returns index 53" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 5;
    cp.cursor_y = 3;
    const color = cp.selectedColor();
    // 3 * 16 + 5 = 53
    try testing.expectEqual(Color{ .indexed = 53 }, color);
}

test "ColorPicker selectedColor at (15,15) returns index 255" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 15;
    cp.cursor_y = 15;
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .indexed = 255 }, color);
}

// ============================================================================
// SELECTEDCOLOR PALETTE_16 TESTS
// ============================================================================

test "ColorPicker selectedColor palette_16 at (0,0) returns basic 0" {
    const cp = ColorPicker.init(.palette_16);
    const color = cp.selectedColor();
    // palette_16 maps 0,0 -> basic color 0
    try testing.expectEqual(Color.black, color);
}

test "ColorPicker selectedColor palette_16 at (1,0) returns basic 1" {
    var cp = ColorPicker.init(.palette_16);
    cp.cursor_x = 1;
    const color = cp.selectedColor();
    try testing.expectEqual(Color.red, color);
}

test "ColorPicker selectedColor palette_16 at (7,1) returns basic 15" {
    var cp = ColorPicker.init(.palette_16);
    cp.cursor_x = 7;
    cp.cursor_y = 1;
    const color = cp.selectedColor();
    // Row 1, col 7 = 8 + 7 = 15 = bright_white
    try testing.expectEqual(Color.bright_white, color);
}

// ============================================================================
// RGB_SLIDERS MODE TESTS
// ============================================================================

test "ColorPicker nextComponent cycles r -> g" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.nextComponent();
    try testing.expectEqual(RgbComponent.g, cp.active_component);
}

test "ColorPicker nextComponent cycles g -> b" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .g;
    cp.nextComponent();
    try testing.expectEqual(RgbComponent.b, cp.active_component);
}

test "ColorPicker nextComponent cycles b -> r" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .b;
    cp.nextComponent();
    try testing.expectEqual(RgbComponent.r, cp.active_component);
}

test "ColorPicker prevComponent cycles r -> b" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.prevComponent();
    try testing.expectEqual(RgbComponent.b, cp.active_component);
}

test "ColorPicker prevComponent cycles b -> g" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .b;
    cp.prevComponent();
    try testing.expectEqual(RgbComponent.g, cp.active_component);
}

test "ColorPicker prevComponent cycles g -> r" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .g;
    cp.prevComponent();
    try testing.expectEqual(RgbComponent.r, cp.active_component);
}

test "ColorPicker incrementComponent adds to active component" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 100;
    cp.incrementComponent(50);
    try testing.expectEqual(@as(u8, 150), cp.r);
}

test "ColorPicker incrementComponent on g" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .g;
    cp.g = 200;
    cp.incrementComponent(30);
    try testing.expectEqual(@as(u8, 230), cp.g);
}

test "ColorPicker incrementComponent on b" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .b;
    cp.b = 100;
    cp.incrementComponent(25);
    try testing.expectEqual(@as(u8, 125), cp.b);
}

test "ColorPicker incrementComponent clamps to 255" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 250;
    cp.incrementComponent(10);
    try testing.expectEqual(@as(u8, 255), cp.r);
}

test "ColorPicker incrementComponent adding 0 does nothing" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 100;
    cp.incrementComponent(0);
    try testing.expectEqual(@as(u8, 100), cp.r);
}

test "ColorPicker decrementComponent subtracts from active component" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 100;
    cp.decrementComponent(30);
    try testing.expectEqual(@as(u8, 70), cp.r);
}

test "ColorPicker decrementComponent on g" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .g;
    cp.g = 150;
    cp.decrementComponent(50);
    try testing.expectEqual(@as(u8, 100), cp.g);
}

test "ColorPicker decrementComponent on b" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .b;
    cp.b = 80;
    cp.decrementComponent(25);
    try testing.expectEqual(@as(u8, 55), cp.b);
}

test "ColorPicker decrementComponent clamps to 0" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 10;
    cp.decrementComponent(20);
    try testing.expectEqual(@as(u8, 0), cp.r);
}

test "ColorPicker decrementComponent subtracting 0 does nothing" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 100;
    cp.decrementComponent(0);
    try testing.expectEqual(@as(u8, 100), cp.r);
}

// ============================================================================
// SELECTEDCOLOR RGB_SLIDERS TESTS
// ============================================================================

test "ColorPicker selectedColor rgb_sliders returns matching r, g, b" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.r = 100;
    cp.g = 150;
    cp.b = 200;
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .rgb = .{ .r = 100, .g = 150, .b = 200 } }, color);
}

test "ColorPicker selectedColor rgb_sliders at (0,0,0)" {
    const cp = ColorPicker.init(.rgb_sliders);
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } }, color);
}

test "ColorPicker selectedColor rgb_sliders at (255,255,255)" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.r = 255;
    cp.g = 255;
    cp.b = 255;
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }, color);
}

// ============================================================================
// RENDERING TESTS
// ============================================================================

test "ColorPicker render palette_256 with valid area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_256);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    cp.render(&buf, area);
}

test "ColorPicker render palette_16 with valid area does not crash" {
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_16);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    cp.render(&buf, area);
}

test "ColorPicker render rgb_sliders with valid area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();

    var cp = ColorPicker.init(.rgb_sliders);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    cp.render(&buf, area);
}

test "ColorPicker render zero area does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_256);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    cp.render(&buf, area);
}

test "ColorPicker render zero width does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_256);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 25 };
    cp.render(&buf, area);
}

test "ColorPicker render zero height does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_256);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };
    cp.render(&buf, area);
}

test "ColorPicker render with block does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_256);
    const block = (Block{}).withTitle("Colors", .top_left);
    cp = cp.withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    cp.render(&buf, area);
}

test "ColorPicker render palette_256 with offset area does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_256);
    const area = Rect{ .x = 5, .y = 5, .width = 30, .height = 20 };
    cp.render(&buf, area);
}

test "ColorPicker render palette_256 cursor cell has indexed bg color" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();

    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 2;
    cp.cursor_y = 1;
    cp = cp.withCursorStyle(Style{ .bold = true, .fg = Color.red });

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    cp.render(&buf, area);

    // Cursor is at (2,1) → color index 1*16+2 = 18. Each swatch is 2 chars wide.
    // bx = 2*2 = 4, by = 1
    const cell = buf.getConst(4, 1) orelse return error.CellNotFound;
    // The cursor cell background should be indexed color 18
    try testing.expectEqual(Color{ .indexed = 18 }, cell.style.bg);
}

test "ColorPicker render rgb_sliders shows R, G, B labels" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();

    var cp = ColorPicker.init(.rgb_sliders);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    cp.render(&buf, area);

    // Row 0: R label, row 1: G label, row 2: B label
    const r_cell = buf.getConst(0, 0) orelse return error.CellNotFound;
    try testing.expectEqual(@as(u21, 'R'), r_cell.char);
    const g_cell = buf.getConst(0, 1) orelse return error.CellNotFound;
    try testing.expectEqual(@as(u21, 'G'), g_cell.char);
    const b_cell = buf.getConst(0, 2) orelse return error.CellNotFound;
    try testing.expectEqual(@as(u21, 'B'), b_cell.char);
}

// ============================================================================
// EDGE CASES & BOUNDARY TESTS
// ============================================================================

test "ColorPicker palette cursor at max boundaries (15,15)" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 15;
    cp.cursor_y = 15;
    try testing.expectEqual(@as(u8, 15), cp.cursor_x);
    try testing.expectEqual(@as(u8, 15), cp.cursor_y);
    const color = cp.selectedColor();
    try testing.expectEqual(Color{ .indexed = 255 }, color);
}

test "ColorPicker multiple navigation operations sequence" {
    var cp = ColorPicker.init(.palette_256);
    cp.moveRight();
    cp.moveRight();
    cp.moveDown();
    cp.moveDown();
    cp.moveLeft();
    try testing.expectEqual(@as(u8, 1), cp.cursor_x);
    try testing.expectEqual(@as(u8, 2), cp.cursor_y);
}

test "ColorPicker RGB increment/decrement sequence" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.r = 50;
    cp.incrementComponent(25);
    try testing.expectEqual(@as(u8, 75), cp.r);
    cp.decrementComponent(30);
    try testing.expectEqual(@as(u8, 45), cp.r);
}

test "ColorPicker RGB component cycling sequence" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.nextComponent();
    cp.nextComponent();
    cp.nextComponent(); // Should cycle back to r
    try testing.expectEqual(RgbComponent.r, cp.active_component);
}

test "ColorPicker prev and next component cycle correctly" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.nextComponent();
    try testing.expectEqual(RgbComponent.g, cp.active_component);
    cp.prevComponent();
    try testing.expectEqual(RgbComponent.r, cp.active_component);
}

test "ColorPicker mode switching preserves cursor position" {
    var cp = ColorPicker.init(.palette_256);
    cp.cursor_x = 5;
    cp.cursor_y = 3;
    cp = cp.withMode(.palette_16);
    try testing.expectEqual(@as(u8, 5), cp.cursor_x);
    try testing.expectEqual(@as(u8, 3), cp.cursor_y);
}

test "ColorPicker mode switching preserves RGB values" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.r = 100;
    cp.g = 150;
    cp.b = 200;
    cp = cp.withMode(.palette_256);
    try testing.expectEqual(@as(u8, 100), cp.r);
    try testing.expectEqual(@as(u8, 150), cp.g);
    try testing.expectEqual(@as(u8, 200), cp.b);
}

test "ColorPicker incrementComponent at max stays at max" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 255;
    cp.incrementComponent(100);
    try testing.expectEqual(@as(u8, 255), cp.r);
}

test "ColorPicker decrementComponent at zero stays at zero" {
    var cp = ColorPicker.init(.rgb_sliders);
    cp.active_component = .r;
    cp.r = 0;
    cp.decrementComponent(100);
    try testing.expectEqual(@as(u8, 0), cp.r);
}

test "ColorPicker withColor on indexed 128 (middle)" {
    var cp = ColorPicker.init(.palette_256);
    const color = Color{ .indexed = 128 };
    cp = cp.withColor(color);
    // 128 / 16 = 8, 128 % 16 = 0
    try testing.expectEqual(@as(u8, 0), cp.cursor_x);
    try testing.expectEqual(@as(u8, 8), cp.cursor_y);
}

test "ColorPicker selectedColor sequence after navigation" {
    var cp = ColorPicker.init(.palette_256);
    cp.moveRight();
    cp.moveRight();
    cp.moveDown();
    const color = cp.selectedColor();
    // Cursor at (2, 1) = 1*16 + 2 = 18
    try testing.expectEqual(Color{ .indexed = 18 }, color);
}
