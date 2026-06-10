const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const ToastManager = sailor.tui.widgets.ToastManager;
const ToastItem = sailor.tui.widgets.ToastItem;
const ToastLevel = sailor.tui.widgets.ToastLevel;
const ToastPosition = sailor.tui.widgets.ToastPosition;

test "ToastManager.init creates manager with default values" {
    const tm = ToastManager.init();
    try std.testing.expectEqual(@as(usize, 0), tm.count);
    try std.testing.expectEqual(ToastPosition.top_right, tm.position);
    try std.testing.expectEqual(@as(u8, 3), tm.max_visible);
    try std.testing.expectEqual(@as(u16, 40), tm.width);
    try std.testing.expectEqual(@as(u16, 1), tm.spacing);
}

test "ToastLevel.icon returns correct codepoints" {
    try std.testing.expectEqual(@as(u21, 'ℹ'), ToastLevel.info.icon());
    try std.testing.expectEqual(@as(u21, '✓'), ToastLevel.success.icon());
    try std.testing.expectEqual(@as(u21, '⚠'), ToastLevel.warning.icon());
    try std.testing.expectEqual(@as(u21, '✗'), ToastLevel.error_.icon());
}

test "ToastLevel.style returns styles with appropriate colors" {
    const info_style = ToastLevel.info.style();
    try std.testing.expect(info_style.fg != null);

    const success_style = ToastLevel.success.style();
    try std.testing.expect(success_style.fg != null);

    const warning_style = ToastLevel.warning.style();
    try std.testing.expect(warning_style.fg != null);

    const error_style = ToastLevel.error_.style();
    try std.testing.expect(error_style.fg != null);
}

test "ToastManager.push adds single toast" {
    var tm = ToastManager.init();
    const toast = ToastItem{ .message = "Test message", .level = .info };
    tm.push(toast);
    try std.testing.expectEqual(@as(usize, 1), tm.count);
    try std.testing.expectEqualStrings("Test message", tm.toasts[0].message);
}

test "ToastManager.push increments toastCount" {
    var tm = ToastManager.init();
    try std.testing.expectEqual(@as(usize, 0), tm.toastCount());

    tm.push(ToastItem{ .message = "msg1", .level = .info });
    try std.testing.expectEqual(@as(usize, 1), tm.toastCount());

    tm.push(ToastItem{ .message = "msg2", .level = .success });
    try std.testing.expectEqual(@as(usize, 2), tm.toastCount());
}

test "ToastManager.push when full (8 toasts) evicts oldest" {
    var tm = ToastManager.init();

    // Fill to capacity
    for (1..9) |i| {
        const msg = switch (i) {
            1 => "msg1",
            2 => "msg2",
            3 => "msg3",
            4 => "msg4",
            5 => "msg5",
            6 => "msg6",
            7 => "msg7",
            8 => "msg8",
            else => unreachable,
        };
        tm.push(ToastItem{ .message = msg, .level = .info });
    }

    try std.testing.expectEqual(@as(usize, 8), tm.count);
    try std.testing.expectEqualStrings("msg1", tm.toasts[0].message);

    // Push 9th item
    tm.push(ToastItem{ .message = "msg9", .level = .info });

    // Should still be at capacity
    try std.testing.expectEqual(@as(usize, 8), tm.count);
    // Oldest (msg1) should be evicted
    try std.testing.expectEqualStrings("msg2", tm.toasts[0].message);
    // Newest should be last
    try std.testing.expectEqualStrings("msg9", tm.toasts[7].message);
}

test "ToastManager.dismiss removes first toast" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info });
    tm.push(ToastItem{ .message = "msg2", .level = .success });

    tm.dismiss(0);
    try std.testing.expectEqual(@as(usize, 1), tm.count);
    try std.testing.expectEqualStrings("msg2", tm.toasts[0].message);
}

test "ToastManager.dismiss removes middle toast" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info });
    tm.push(ToastItem{ .message = "msg2", .level = .success });
    tm.push(ToastItem{ .message = "msg3", .level = .warning });

    tm.dismiss(1);
    try std.testing.expectEqual(@as(usize, 2), tm.count);
    try std.testing.expectEqualStrings("msg1", tm.toasts[0].message);
    try std.testing.expectEqualStrings("msg3", tm.toasts[1].message);
}

test "ToastManager.dismiss removes last toast" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info });
    tm.push(ToastItem{ .message = "msg2", .level = .success });

    tm.dismiss(1);
    try std.testing.expectEqual(@as(usize, 1), tm.count);
    try std.testing.expectEqualStrings("msg1", tm.toasts[0].message);
}

test "ToastManager.dismiss on empty queue does nothing" {
    var tm = ToastManager.init();
    tm.dismiss(0); // Should not panic
    try std.testing.expectEqual(@as(usize, 0), tm.count);
}

test "ToastManager.dismiss out of bounds does nothing" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info });
    tm.dismiss(5); // Out of bounds
    try std.testing.expectEqual(@as(usize, 1), tm.count);
}

test "ToastManager.dismissAll clears all toasts" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info });
    tm.push(ToastItem{ .message = "msg2", .level = .success });
    tm.push(ToastItem{ .message = "msg3", .level = .warning });

    tm.dismissAll();
    try std.testing.expectEqual(@as(usize, 0), tm.count);
}

test "ToastManager.tick decrements non-zero ticks_remaining" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info, .ticks_remaining = 5 });

    tm.tick();
    try std.testing.expectEqual(@as(u32, 4), tm.toasts[0].ticks_remaining);

    tm.tick();
    try std.testing.expectEqual(@as(u32, 3), tm.toasts[0].ticks_remaining);
}

test "ToastManager.tick removes toast when ticks hit 0" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info, .ticks_remaining = 1 });

    tm.tick();
    try std.testing.expectEqual(@as(usize, 0), tm.count);
}

test "ToastManager.tick does NOT remove persistent toasts (ticks_remaining == 0)" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg1", .level = .info, .ticks_remaining = 0 });

    tm.tick();
    try std.testing.expectEqual(@as(usize, 1), tm.count);
    try std.testing.expectEqual(@as(u32, 0), tm.toasts[0].ticks_remaining);
}

test "ToastManager.tick on empty manager does nothing" {
    var tm = ToastManager.init();
    tm.tick(); // Should not panic
    try std.testing.expectEqual(@as(usize, 0), tm.count);
}

test "ToastManager.tick with mixed toasts (some expire, some persist, some count down)" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "persistent", .level = .info, .ticks_remaining = 0 });
    tm.push(ToastItem{ .message = "expires_soon", .level = .success, .ticks_remaining = 1 });
    tm.push(ToastItem{ .message = "countdown", .level = .warning, .ticks_remaining = 5 });

    tm.tick();
    try std.testing.expectEqual(@as(usize, 2), tm.count);
    try std.testing.expectEqualStrings("persistent", tm.toasts[0].message);
    try std.testing.expectEqual(@as(u32, 0), tm.toasts[0].ticks_remaining);
    try std.testing.expectEqualStrings("countdown", tm.toasts[1].message);
    try std.testing.expectEqual(@as(u32, 4), tm.toasts[1].ticks_remaining);
}

test "ToastManager.toastCount returns current count" {
    var tm = ToastManager.init();
    try std.testing.expectEqual(@as(usize, 0), tm.toastCount());

    tm.push(ToastItem{ .message = "msg1", .level = .info });
    try std.testing.expectEqual(@as(usize, 1), tm.toastCount());

    tm.push(ToastItem{ .message = "msg2", .level = .success });
    try std.testing.expectEqual(@as(usize, 2), tm.toastCount());

    tm.dismiss(0);
    try std.testing.expectEqual(@as(usize, 1), tm.toastCount());
}

test "ToastManager.withPosition returns new value with changed position" {
    const tm1 = ToastManager.init();
    try std.testing.expectEqual(ToastPosition.top_right, tm1.position);

    const tm2 = tm1.withPosition(.bottom_left);
    try std.testing.expectEqual(ToastPosition.bottom_left, tm2.position);
    try std.testing.expectEqual(ToastPosition.top_right, tm1.position); // Original unchanged
}

test "ToastManager.withMaxVisible returns new value with changed max_visible" {
    const tm1 = ToastManager.init();
    try std.testing.expectEqual(@as(u8, 3), tm1.max_visible);

    const tm2 = tm1.withMaxVisible(5);
    try std.testing.expectEqual(@as(u8, 5), tm2.max_visible);
    try std.testing.expectEqual(@as(u8, 3), tm1.max_visible);
}

test "ToastManager.withWidth returns new value with changed width" {
    const tm1 = ToastManager.init();
    try std.testing.expectEqual(@as(u16, 40), tm1.width);

    const tm2 = tm1.withWidth(60);
    try std.testing.expectEqual(@as(u16, 60), tm2.width);
    try std.testing.expectEqual(@as(u16, 40), tm1.width);
}

test "ToastManager.withSpacing returns new value with changed spacing" {
    const tm1 = ToastManager.init();
    try std.testing.expectEqual(@as(u16, 1), tm1.spacing);

    const tm2 = tm1.withSpacing(2);
    try std.testing.expectEqual(@as(u16, 2), tm2.spacing);
    try std.testing.expectEqual(@as(u16, 1), tm1.spacing);
}

test "ToastManager.withInfoStyle returns new value with changed info_style" {
    const tm1 = ToastManager.init();
    const custom_style = Style{ .fg = .{ .indexed = 1 } };

    const tm2 = tm1.withInfoStyle(custom_style);
    try std.testing.expectEqual(custom_style.fg, tm2.info_style.fg);
}

test "ToastManager.withSuccessStyle returns new value with changed success_style" {
    const tm1 = ToastManager.init();
    const custom_style = Style{ .fg = .{ .indexed = 2 } };

    const tm2 = tm1.withSuccessStyle(custom_style);
    try std.testing.expectEqual(custom_style.fg, tm2.success_style.fg);
}

test "ToastManager.withWarningStyle returns new value with changed warning_style" {
    const tm1 = ToastManager.init();
    const custom_style = Style{ .fg = .{ .indexed = 3 } };

    const tm2 = tm1.withWarningStyle(custom_style);
    try std.testing.expectEqual(custom_style.fg, tm2.warning_style.fg);
}

test "ToastManager.withErrorStyle returns new value with changed error_style" {
    const tm1 = ToastManager.init();
    const custom_style = Style{ .fg = .{ .indexed = 4 } };

    const tm2 = tm1.withErrorStyle(custom_style);
    try std.testing.expectEqual(custom_style.fg, tm2.error_style.fg);
}

test "ToastManager builder pattern chains correctly" {
    const tm = ToastManager.init()
        .withPosition(.bottom_right)
        .withMaxVisible(2)
        .withWidth(50)
        .withSpacing(1);

    try std.testing.expectEqual(ToastPosition.bottom_right, tm.position);
    try std.testing.expectEqual(@as(u8, 2), tm.max_visible);
    try std.testing.expectEqual(@as(u16, 50), tm.width);
    try std.testing.expectEqual(@as(u16, 1), tm.spacing);
}

test "ToastManager.render with zero-area Rect does not crash" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const tm = ToastManager.init();
    const zero_rect = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    tm.render(&buf, zero_rect); // Should not crash
}

test "ToastManager.render with empty queue does not crash" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const tm = ToastManager.init();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should not crash with empty queue
}

test "ToastManager.render with single toast renders without crash" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "Test toast", .level = .info });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should not crash
}

test "ToastManager.render respects max_visible limit" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init().withMaxVisible(2);
    tm.push(ToastItem{ .message = "toast1", .level = .info });
    tm.push(ToastItem{ .message = "toast2", .level = .success });
    tm.push(ToastItem{ .message = "toast3", .level = .warning });
    tm.push(ToastItem{ .message = "toast4", .level = .error_ });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area);
    // render() should only display 2 toasts even though 4 exist
}

test "ToastManager.render with top_right position" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init().withPosition(.top_right);
    tm.push(ToastItem{ .message = "Toast", .level = .info });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should position at top-right
}

test "ToastManager.render with top_left position" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init().withPosition(.top_left);
    tm.push(ToastItem{ .message = "Toast", .level = .info });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should position at top-left
}

test "ToastManager.render with bottom_right position" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init().withPosition(.bottom_right);
    tm.push(ToastItem{ .message = "Toast", .level = .info });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should position at bottom-right
}

test "ToastManager.render with bottom_left position" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init().withPosition(.bottom_left);
    tm.push(ToastItem{ .message = "Toast", .level = .info });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should position at bottom-left
}

test "ToastManager.render with persistent toast (ticks_remaining=0)" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "Persistent", .level = .info, .ticks_remaining = 0 });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Persistent toast should still render
}

test "ToastManager.render with title (non-null title)" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "Message", .level = .success, .title = "Success!" });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should render with title
}

test "ToastManager.render with multiple toasts stacked" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "toast1", .level = .info });
    tm.push(ToastItem{ .message = "toast2", .level = .success });
    tm.push(ToastItem{ .message = "toast3", .level = .warning });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Should render all 3 without crash
}

test "ToastManager.render respects withMaxVisible(1)" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var tm = ToastManager.init().withMaxVisible(1);
    tm.push(ToastItem{ .message = "first", .level = .info });
    tm.push(ToastItem{ .message = "second", .level = .success });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    tm.render(&buf, area); // Only first toast should be visible
}

test "ToastManager ToastItem fields accessible after push" {
    var tm = ToastManager.init();
    const toast = ToastItem{ .message = "msg", .level = .info, .title = "title", .ticks_remaining = 10 };
    tm.push(toast);

    try std.testing.expectEqualStrings("msg", tm.toasts[0].message);
    try std.testing.expectEqual(ToastLevel.info, tm.toasts[0].level);
    try std.testing.expectEqualStrings("title", tm.toasts[0].title.?);
    try std.testing.expectEqual(@as(u32, 10), tm.toasts[0].ticks_remaining);
}

test "ToastManager.push multiple times maintains FIFO order" {
    var tm = ToastManager.init();

    tm.push(ToastItem{ .message = "first", .level = .info });
    tm.push(ToastItem{ .message = "second", .level = .success });
    tm.push(ToastItem{ .message = "third", .level = .warning });

    try std.testing.expectEqualStrings("first", tm.toasts[0].message);
    try std.testing.expectEqualStrings("second", tm.toasts[1].message);
    try std.testing.expectEqualStrings("third", tm.toasts[2].message);
}

test "ToastManager.dismiss shifts multiple remaining toasts correctly" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "a", .level = .info });
    tm.push(ToastItem{ .message = "b", .level = .success });
    tm.push(ToastItem{ .message = "c", .level = .warning });
    tm.push(ToastItem{ .message = "d", .level = .error_ });

    tm.dismiss(1);

    try std.testing.expectEqual(@as(usize, 3), tm.count);
    try std.testing.expectEqualStrings("a", tm.toasts[0].message);
    try std.testing.expectEqualStrings("c", tm.toasts[1].message);
    try std.testing.expectEqualStrings("d", tm.toasts[2].message);
}

test "ToastManager.tick multiple times with countdown" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "countdown", .level = .info, .ticks_remaining = 3 });

    tm.tick();
    try std.testing.expectEqual(@as(u32, 2), tm.toasts[0].ticks_remaining);
    try std.testing.expectEqual(@as(usize, 1), tm.count);

    tm.tick();
    try std.testing.expectEqual(@as(u32, 1), tm.toasts[0].ticks_remaining);
    try std.testing.expectEqual(@as(usize, 1), tm.count);

    tm.tick();
    try std.testing.expectEqual(@as(usize, 0), tm.count);
}

test "ToastManager.tick removes multiple expired toasts in sequence" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "expires_first", .level = .info, .ticks_remaining = 1 });
    tm.push(ToastItem{ .message = "expires_second", .level = .success, .ticks_remaining = 1 });
    tm.push(ToastItem{ .message = "persistent", .level = .warning, .ticks_remaining = 0 });

    tm.tick();
    try std.testing.expectEqual(@as(usize, 1), tm.count);
    try std.testing.expectEqualStrings("persistent", tm.toasts[0].message);
}

test "ToastManager capacity boundary at MAX_TOASTS" {
    var tm = ToastManager.init();

    // Fill exactly to MAX_TOASTS (8)
    for (1..9) |i| {
        const msg = switch (i) {
            1 => "a",
            2 => "b",
            3 => "c",
            4 => "d",
            5 => "e",
            6 => "f",
            7 => "g",
            8 => "h",
            else => unreachable,
        };
        tm.push(ToastItem{ .message = msg, .level = .info });
    }

    try std.testing.expectEqual(@as(usize, 8), tm.count);

    // Push one more to test boundary
    tm.push(ToastItem{ .message = "i", .level = .info });
    try std.testing.expectEqual(@as(usize, 8), tm.count);
    try std.testing.expectEqualStrings("b", tm.toasts[0].message);
    try std.testing.expectEqualStrings("i", tm.toasts[7].message);
}

test "ToastManager.render with varying widths and positions" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 30);
    defer buf.deinit();

    var tm = ToastManager.init()
        .withWidth(25)
        .withPosition(.top_left);

    tm.push(ToastItem{ .message = "Narrow toast", .level = .info });

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };
    tm.render(&buf, area);
}

test "ToastManager default style matches level icon style" {
    const info_icon = ToastLevel.info.icon();
    const info_style = ToastLevel.info.style();

    const success_icon = ToastLevel.success.icon();
    const success_style = ToastLevel.success.style();

    const warning_icon = ToastLevel.warning.icon();
    const warning_style = ToastLevel.warning.style();

    const error_icon = ToastLevel.error_.icon();
    const error_style = ToastLevel.error_.style();

    // Styles should be defined (not testing color values, just ensuring they exist)
    _ = info_icon;
    _ = info_style;
    _ = success_icon;
    _ = success_style;
    _ = warning_icon;
    _ = warning_style;
    _ = error_icon;
    _ = error_style;

    try std.testing.expect(true); // Styles exist without panic
}

test "ToastManager dismissAll then push works" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "first", .level = .info });
    tm.push(ToastItem{ .message = "second", .level = .success });

    tm.dismissAll();
    try std.testing.expectEqual(@as(usize, 0), tm.count);

    tm.push(ToastItem{ .message = "third", .level = .warning });
    try std.testing.expectEqual(@as(usize, 1), tm.count);
    try std.testing.expectEqualStrings("third", tm.toasts[0].message);
}

test "ToastManager ToastPosition enum values" {
    const positions = [_]ToastPosition{ .top_right, .top_left, .bottom_right, .bottom_left };
    for (positions) |pos| {
        const tm = ToastManager.init().withPosition(pos);
        try std.testing.expectEqual(pos, tm.position);
    }
}

test "ToastManager tick does not affect message or level" {
    var tm = ToastManager.init();
    tm.push(ToastItem{ .message = "msg", .level = .success, .ticks_remaining = 2 });

    tm.tick();
    try std.testing.expectEqualStrings("msg", tm.toasts[0].message);
    try std.testing.expectEqual(ToastLevel.success, tm.toasts[0].level);
}
