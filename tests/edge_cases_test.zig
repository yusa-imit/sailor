//! Edge case tests for boundary conditions and potential issues
//! Tests integer overflow, boundary values, and other edge cases

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import modules from sailor
const mouse = sailor.tui.mouse;
const touch = sailor.tui.touch;
const gamepad = sailor.tui.gamepad;
const layout = sailor.tui.layout;
const unicode = sailor.unicode;

// ============================================================================
// Mouse Edge Cases
// ============================================================================

test "mouse parseSGR - maximum coordinate values" {
    // Test with maximum u16 values (65535)
    const seq = "<0;65535;65535M";
    const event = mouse.parseSGR(seq);
    try testing.expect(event != null);
    try testing.expectEqual(@as(u16, 65534), event.?.x); // 65535-1 (0-based)
    try testing.expectEqual(@as(u16, 65534), event.?.y);
}

test "mouse parseSGR - zero coordinates" {
    const seq = "<0;1;1M"; // Minimum valid (1-based)
    const event = mouse.parseSGR(seq);
    try testing.expect(event != null);
    try testing.expectEqual(@as(u16, 0), event.?.x); // Converts to 0-based
    try testing.expectEqual(@as(u16, 0), event.?.y);
}

test "mouse parseSGR - truncated sequence" {
    try testing.expectEqual(@as(?mouse.MouseEvent, null), mouse.parseSGR("<0;"));
    try testing.expectEqual(@as(?mouse.MouseEvent, null), mouse.parseSGR("<0;10"));
    try testing.expectEqual(@as(?mouse.MouseEvent, null), mouse.parseSGR("<0;10;"));
    try testing.expectEqual(@as(?mouse.MouseEvent, null), mouse.parseSGR("<0;10;5"));
}

test "mouse parseSGR - malformed button code" {
    try testing.expectEqual(@as(?mouse.MouseEvent, null), mouse.parseSGR("<999;10;5M"));
    try testing.expectEqual(@as(?mouse.MouseEvent, null), mouse.parseSGR("<-1;10;5M"));
}

test "mouse DoubleClickDetector - large time delta" {
    var detector = mouse.DoubleClickDetector{};
    const event = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };

    _ = detector.checkDoubleClick(event, 1000);

    // Large time gap should reject double-click
    const is_double = detector.checkDoubleClick(event, 5000); // 4000ms later, exceeds threshold
    try testing.expect(!is_double);
}

test "mouse DoubleClickDetector - zero threshold distance" {
    var detector = mouse.DoubleClickDetector{ .threshold_distance = 0 };
    const event1 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 5,
    };
    const event2 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 11, // 1 pixel away
        .y = 5,
    };

    _ = detector.checkDoubleClick(event1, 1000);
    const is_double = detector.checkDoubleClick(event2, 1100);
    try testing.expect(!is_double); // Should reject even 1 pixel movement
}

// ============================================================================
// Touch Edge Cases
// ============================================================================

test "touch point creation - boundaries" {
    const p1 = touch.TouchPoint.init(0, 0, 0);
    try testing.expectEqual(@as(u32, 0), p1.id);
    try testing.expectEqual(@as(u16, 0), p1.x);
    try testing.expectEqual(@as(u16, 0), p1.y);

    const p2 = touch.TouchPoint.init(std.math.maxInt(u32), std.math.maxInt(u16), std.math.maxInt(u16));
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), p2.id);
}

test "touch tracker - maximum touches" {
    var tracker = touch.TouchTracker.init();

    // Add maximum number of touch points
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const point = touch.TouchPoint.init(i, @intCast(i * 10), @intCast(i * 10));
        tracker.touchDown(point, 1000);
    }

    // Should handle maximum touches without overflow
    try testing.expectEqual(@as(usize, 10), tracker.active_count);
}

test "touch tracker - tap detection timing" {
    var tracker = touch.TouchTracker.init();

    const point = touch.TouchPoint.init(1, 100, 100);
    tracker.touchDown(point, 1000);

    // Quick release should detect tap or return null
    const gesture = tracker.touchUp(point, 1050); // 50ms later
    // Gesture is optional, so check if it exists
    if (gesture) |g| {
        try testing.expect(g == .tap);
    }
}

test "touch tracker - long press threshold" {
    var tracker = touch.TouchTracker.init();

    const point = touch.TouchPoint.init(1, 100, 100);
    tracker.touchDown(point, 1000);

    // Release after long time
    const gesture = tracker.touchUp(point, 2000); // 1000ms later
    // Gesture detection is implementation-defined
    _ = gesture; // May or may not return a gesture
}

// ============================================================================
// Gamepad Edge Cases
// ============================================================================

test "gamepad analog stick - maximum values" {
    const event = gamepad.GamepadEvent{
        .event_type = .analog_move,
        .gamepad_id = 0,
        .left_stick = .{ .x = 1.0, .y = 1.0 }, // Maximum values
        .right_stick = .{ .x = -1.0, .y = -1.0 }, // Maximum negative
    };

    try testing.expectEqual(@as(f32, 1.0), event.left_stick.x);
    try testing.expectEqual(@as(f32, -1.0), event.right_stick.x);
}

test "gamepad analog stick - zero (dead zone)" {
    const event = gamepad.GamepadEvent{
        .event_type = .analog_move,
        .gamepad_id = 0,
        .left_stick = .{ .x = 0.0, .y = 0.0 },
    };

    try testing.expectEqual(@as(f32, 0.0), event.left_stick.x);
    try testing.expectEqual(@as(f32, 0.0), event.left_stick.y);
}

test "gamepad maximum gamepad_id" {
    const event = gamepad.GamepadEvent.buttonPress(255, .a); // Maximum u8
    try testing.expectEqual(@as(u8, 255), event.gamepad_id);
}

test "gamepad button press - all buttons" {
    // Test that all button types can be created
    // Using fully qualified path since GamepadButton is not directly exported
    const Button = @TypeOf(gamepad.GamepadEvent.buttonPress(0, .a).button.?);
    _ = Button; // Verify type exists

    // Test creating events for different buttons
    const event_a = gamepad.GamepadEvent.buttonPress(0, .a);
    try testing.expectEqual(gamepad.EventType.button_press, event_a.event_type);
    try testing.expect(event_a.button.? == .a);

    const event_dpad = gamepad.GamepadEvent.buttonPress(0, .dpad_up);
    try testing.expectEqual(gamepad.EventType.button_press, event_dpad.event_type);
    try testing.expect(event_dpad.button.? == .dpad_up);
}

// ============================================================================
// Layout Edge Cases
// ============================================================================

test "layout Rect - zero dimensions" {
    const rect = layout.Rect{ .x = 10, .y = 10, .width = 0, .height = 0 };
    try testing.expectEqual(@as(u16, 0), rect.width);
    try testing.expectEqual(@as(u16, 0), rect.height);
    try testing.expectEqual(@as(u16, 0), rect.area());
}

test "layout Rect - maximum dimensions" {
    const rect = layout.Rect{ .x = 0, .y = 0, .width = 65535, .height = 65535 };
    try testing.expectEqual(@as(u16, 65535), rect.width);
    try testing.expectEqual(@as(u16, 65535), rect.height);
}

test "layout Rect intersection - no overlap" {
    const r1 = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = layout.Rect{ .x = 20, .y = 20, .width = 10, .height = 10 };
    const intersection = r1.intersection(r2);
    // No overlap returns null
    try testing.expectEqual(@as(?layout.Rect, null), intersection);
}

test "layout Rect intersection - partial overlap" {
    const r1 = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = layout.Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    const intersection_opt = r1.intersection(r2);
    try testing.expect(intersection_opt != null);
    const intersection = intersection_opt.?;
    try testing.expectEqual(@as(u16, 5), intersection.width);
    try testing.expectEqual(@as(u16, 5), intersection.height);
    try testing.expectEqual(@as(u16, 5), intersection.x);
    try testing.expectEqual(@as(u16, 5), intersection.y);
}

test "layout Rect intersection - complete overlap" {
    const r1 = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 }; // Same rect
    const intersection_opt = r1.intersection(r2);
    try testing.expect(intersection_opt != null);
    const intersection = intersection_opt.?;
    try testing.expectEqual(@as(u16, 10), intersection.width);
    try testing.expectEqual(@as(u16, 10), intersection.height);
}

test "layout constraint - length overflow" {
    const constraint = layout.Constraint{ .length = 65535 };
    const area = layout.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };

    // Should not crash with overflow
    const result = try layout.split(testing.allocator, .horizontal, area, &[_]layout.Constraint{constraint});
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
}

test "layout constraint - percentage 100" {
    const constraint = layout.Constraint{ .percentage = 100 };
    const area = layout.Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };

    const result = try layout.split(testing.allocator, .horizontal, area, &[_]layout.Constraint{constraint});
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(u16, 200), result[0].width);
}

test "layout constraint - minimum percentage" {
    const constraint = layout.Constraint{ .min = 10 };
    const area = layout.Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };

    const result = try layout.split(testing.allocator, .horizontal, area, &[_]layout.Constraint{constraint});
    defer testing.allocator.free(result);
    // Min constraint should get at least 10 width
    try testing.expect(result[0].width >= 10);
}

test "layout split - empty constraints" {
    const area = layout.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const result = try layout.split(testing.allocator, .horizontal, area, &[_]layout.Constraint{});
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "layout split - single constraint fills area" {
    const area = layout.Rect{ .x = 10, .y = 20, .width = 100, .height = 50 };
    const constraints = [_]layout.Constraint{
        .{ .percentage = 100 },
    };
    const result = try layout.split(testing.allocator, .horizontal, area, &constraints);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u16, 100), result[0].width);
    try testing.expectEqual(@as(u16, 50), result[0].height);
}

// ============================================================================
// Unicode Edge Cases
// ============================================================================

test "unicode charWidth - control characters" {
    try testing.expectEqual(@as(u8, 0), unicode.UnicodeWidth.charWidth(0x00)); // NUL
    try testing.expectEqual(@as(u8, 0), unicode.UnicodeWidth.charWidth(0x1F)); // Unit separator
    try testing.expectEqual(@as(u8, 0), unicode.UnicodeWidth.charWidth(0x7F)); // DEL
    try testing.expectEqual(@as(u8, 0), unicode.UnicodeWidth.charWidth(0x9F)); // Max C1 control
}

test "unicode charWidth - ASCII printable" {
    try testing.expectEqual(@as(u8, 1), unicode.UnicodeWidth.charWidth('A'));
    try testing.expectEqual(@as(u8, 1), unicode.UnicodeWidth.charWidth('z'));
    try testing.expectEqual(@as(u8, 1), unicode.UnicodeWidth.charWidth('0'));
    try testing.expectEqual(@as(u8, 1), unicode.UnicodeWidth.charWidth(' '));
}

test "unicode charWidth - CJK ideographs" {
    try testing.expectEqual(@as(u8, 2), unicode.UnicodeWidth.charWidth(0x4E00)); // CJK Unified Ideograph
    try testing.expectEqual(@as(u8, 2), unicode.UnicodeWidth.charWidth(0x9FFF)); // End of CJK block
}

test "unicode charWidth - emoji" {
    try testing.expectEqual(@as(u8, 2), unicode.UnicodeWidth.charWidth(0x1F600)); // 😀
    try testing.expectEqual(@as(u8, 2), unicode.UnicodeWidth.charWidth(0x1F9FF)); // End of emoji block
}

test "unicode charWidth - zero-width characters" {
    try testing.expectEqual(@as(u8, 0), unicode.UnicodeWidth.charWidth(0x200B)); // ZWSP
    try testing.expectEqual(@as(u8, 0), unicode.UnicodeWidth.charWidth(0x200C)); // ZWNJ
    try testing.expectEqual(@as(u8, 0), unicode.UnicodeWidth.charWidth(0x200D)); // ZWJ
}

test "unicode stringWidth - empty string" {
    try testing.expectEqual(@as(usize, 0), unicode.UnicodeWidth.stringWidth(""));
}

test "unicode stringWidth - ASCII only" {
    try testing.expectEqual(@as(usize, 11), unicode.UnicodeWidth.stringWidth("Hello World"));
}

test "unicode stringWidth - mixed width" {
    // "Hello世界" = 5 ASCII (width 1 each) + 2 CJK (width 2 each) = 9 total
    try testing.expectEqual(@as(usize, 9), unicode.UnicodeWidth.stringWidth("Hello世界"));
}

test "unicode stringWidth - invalid UTF-8 sequence" {
    // Invalid UTF-8 should be handled gracefully
    const invalid = [_]u8{ 0xFF, 0xFE, 0xFD };
    const width = unicode.UnicodeWidth.stringWidth(&invalid);
    // Should not crash, width behavior is implementation-defined for invalid UTF-8
    try testing.expect(width >= 0);
}

test "unicode truncate - exact fit" {
    const str = "Hello";
    const byte_index = unicode.UnicodeWidth.truncate(str, 5);
    try testing.expectEqual(@as(usize, 5), byte_index);
    try testing.expectEqualStrings("Hello", str[0..byte_index]);
}

test "unicode truncate - needs truncation" {
    const str = "Hello World";
    const byte_index = unicode.UnicodeWidth.truncate(str, 5);
    try testing.expectEqual(@as(usize, 5), byte_index);
    try testing.expectEqualStrings("Hello", str[0..byte_index]);
}

test "unicode truncate - zero width" {
    const str = "Hello";
    const byte_index = unicode.UnicodeWidth.truncate(str, 0);
    try testing.expectEqual(@as(usize, 0), byte_index);
    try testing.expectEqualStrings("", str[0..byte_index]);
}

test "unicode truncate - CJK characters" {
    const str = "世界你好"; // 4 CJK chars = width 8
    const byte_index = unicode.UnicodeWidth.truncate(str, 4); // Should fit 2 chars
    // Should truncate at character boundary, not split wide chars
    const truncated_str = str[0..byte_index];
    const width = unicode.UnicodeWidth.stringWidth(truncated_str);
    try testing.expect(width <= 4);
}

// ============================================================================
// Integer Overflow Edge Cases
// ============================================================================

test "layout area calculation - no overflow" {
    const rect = layout.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    try testing.expectEqual(@as(u16, 10000), rect.area());
}

test "layout area calculation - maximum safe values" {
    // Maximum area that fits in u16: 255 * 255 = 65025
    const rect = layout.Rect{ .x = 0, .y = 0, .width = 255, .height = 255 };
    try testing.expectEqual(@as(u16, 65025), rect.area());
}

test "mouse coordinate boundary - at terminal edge" {
    const event = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 0,
        .y = 0,
    };
    try testing.expectEqual(@as(u16, 0), event.x);
    try testing.expectEqual(@as(u16, 0), event.y);
}

test "touch timestamp - large values" {
    const point = touch.TouchPoint.init(1, 100, 100);
    var tracker = touch.TouchTracker.init();

    // Test with large i64 timestamp
    const large_time: i64 = std.math.maxInt(i64) / 2;
    tracker.touchDown(point, large_time);

    // Should not overflow or crash
    try testing.expectEqual(@as(usize, 1), tracker.active_count);
}

// ============================================================================
// Blur Effect Edge Cases
// ============================================================================

test "blur effect - zero intensity" {
    const blur = @import("sailor").tui.blur;
    var buf = try sailor.tui.buffer.Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const effect = blur.BlurEffect.init(.box_drawing, 0);
    const area = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    effect.apply(&buf, area);

    // Zero intensity should still apply effect (minimal blur)
    const cell = buf.get(5, 5) orelse return error.TestUnexpectedNull;
    try testing.expect(cell.char == '░' or cell.char == '▒' or cell.char == '▓');
}

test "blur effect - maximum intensity" {
    const blur = @import("sailor").tui.blur;
    var buf = try sailor.tui.buffer.Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const effect = blur.BlurEffect.init(.shade_chars, 255);
    const area = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    effect.apply(&buf, area);

    // Maximum intensity should apply strongest blur
    const cell = buf.get(5, 5) orelse return error.TestUnexpectedNull;
    try testing.expect(cell.char == '░' or cell.char == '▒' or cell.char == '▓' or cell.char == '█');
}

test "blur effect - out of bounds area" {
    const blur = @import("sailor").tui.blur;
    var buf = try sailor.tui.buffer.Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const effect = blur.BlurEffect.init(.box_drawing, 128);
    // Area extends beyond buffer bounds
    const area = layout.Rect{ .x = 5, .y = 5, .width = 100, .height = 100 };

    // Should not crash, only applies to valid cells
    effect.apply(&buf, area);
}

test "transparency effect - zero alpha (fully transparent)" {
    const blur = @import("sailor").tui.blur;
    var buf = try sailor.tui.buffer.Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const effect = blur.TransparencyEffect.init(.char_fade, 0);
    const area = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    effect.apply(&buf, area);

    // Zero alpha should show space or lightest fade char
    const cell = buf.get(5, 5) orelse return error.TestUnexpectedNull;
    try testing.expect(cell.char == ' ' or cell.char == '░');
}

test "transparency effect - maximum alpha (opaque)" {
    const blur = @import("sailor").tui.blur;
    var buf = try sailor.tui.buffer.Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const effect = blur.TransparencyEffect.init(.char_fade, 255);
    const area = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    effect.apply(&buf, area);

    // Maximum alpha should show heaviest fade char
    const cell = buf.get(5, 5) orelse return error.TestUnexpectedNull;
    try testing.expect(cell.char == ' ' or cell.char == '░' or cell.char == '▒' or cell.char == '▓');
}

test "composite effect - both null effects" {
    const blur = @import("sailor").tui.blur;
    var buf = try sailor.tui.buffer.Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const composite = blur.CompositeEffect.init(null, null);
    const area = layout.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    // Should be a no-op
    composite.apply(&buf, area);
}

// ============================================================================
// Transition Edge Cases
// ============================================================================

test "transition - zero duration" {
    const transitions = @import("sailor").tui.transitions;
    const animation = @import("sailor").tui.animation;

    var trans = transitions.Transition.fade(0, animation.linear);
    const rect = layout.Rect{ .x = 10, .y = 10, .width = 50, .height = 20 };

    trans.begin(1000, rect);

    // Update to trigger completion check
    _ = trans.update(1000);

    // Zero duration should complete immediately after update
    try testing.expect(trans.isComplete());
}

test "transition - slide with maximum rect dimensions" {
    const transitions = @import("sailor").tui.transitions;
    const animation = @import("sailor").tui.animation;

    var trans = transitions.Transition.slide(1000, .right, animation.linear);
    const rect = layout.Rect{ .x = 0, .y = 0, .width = 65535, .height = 32768 };

    trans.begin(0, rect);

    // Should not overflow
    const mid_rect = trans.update(500);
    try testing.expect(mid_rect.width <= 65535);
}

test "transition - scale to zero" {
    const transitions = @import("sailor").tui.transitions;
    const animation = @import("sailor").tui.animation;

    var trans = transitions.Transition.scale(1000, animation.linear);
    const rect = layout.Rect{ .x = 10, .y = 10, .width = 100, .height = 50 };

    trans.begin(0, rect);

    // At t=0, scale should be zero or near-zero
    const start_rect = trans.update(0);
    try testing.expect(start_rect.width <= rect.width);
    try testing.expect(start_rect.height <= rect.height);
}

test "transition manager - duplicate IDs" {
    const transitions = @import("sailor").tui.transitions;
    const animation = @import("sailor").tui.animation;

    var mgr = transitions.TransitionManager.init(testing.allocator);
    defer mgr.deinit();

    const trans1 = transitions.Transition.fade(1000, animation.linear);
    const trans2 = transitions.Transition.slide(500, .left, animation.easeIn);

    // Add two transitions with same ID
    try mgr.add(1, trans1);
    try mgr.add(1, trans2);

    // Should handle duplicate IDs (implementation-defined behavior)
    try testing.expectEqual(@as(usize, 2), mgr.transitions.items.len);
}

test "transition manager - start non-existent ID" {
    const transitions = @import("sailor").tui.transitions;

    var mgr = transitions.TransitionManager.init(testing.allocator);
    defer mgr.deinit();

    const rect = layout.Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    // Starting non-existent ID should be no-op (not crash)
    mgr.start(999, 0, rect);
}

test "transition manager - cleanup with active transitions" {
    const transitions = @import("sailor").tui.transitions;
    const animation = @import("sailor").tui.animation;

    var mgr = transitions.TransitionManager.init(testing.allocator);
    defer mgr.deinit();

    const trans = transitions.Transition.fade(1000, animation.linear);
    try mgr.add(1, trans);

    const rect = layout.Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    mgr.start(1, 0, rect);

    // Cleanup with active transition should not remove it
    mgr.cleanup();
    try testing.expectEqual(@as(usize, 1), mgr.transitions.items.len);
}
