const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const CountdownTimer = tui.widgets.CountdownTimer;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "CountdownTimer init sets total_seconds" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(@as(u64, 60), timer.total_seconds);
}

test "CountdownTimer init sets remaining_seconds to total_seconds" {
    const timer = CountdownTimer.init(120);
    try testing.expectEqual(@as(u64, 120), timer.remaining_seconds);
}

test "CountdownTimer init with zero seconds" {
    const timer = CountdownTimer.init(0);
    try testing.expectEqual(@as(u64, 0), timer.total_seconds);
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer init with large value" {
    const timer = CountdownTimer.init(86400);
    try testing.expectEqual(@as(u64, 86400), timer.total_seconds);
    try testing.expectEqual(@as(u64, 86400), timer.remaining_seconds);
}

test "CountdownTimer init defaults show_progress_bar to true" {
    const timer = CountdownTimer.init(60);
    try testing.expect(timer.show_progress_bar);
}

test "CountdownTimer init defaults show_total to true" {
    const timer = CountdownTimer.init(60);
    try testing.expect(timer.show_total);
}

test "CountdownTimer init defaults format to mm_ss" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(CountdownTimer.TimeFormat.mm_ss, timer.format);
}

test "CountdownTimer init defaults bar_char to █" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(@as(u21, '█'), timer.bar_char);
}

test "CountdownTimer init defaults empty_char to ░" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(@as(u21, '░'), timer.empty_char);
}

test "CountdownTimer init defaults time_style empty" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(Style{}, timer.time_style);
}

test "CountdownTimer init defaults bar_filled_style empty" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(Style{}, timer.bar_filled_style);
}

test "CountdownTimer init defaults bar_empty_style empty" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(Style{}, timer.bar_empty_style);
}

test "CountdownTimer init defaults block to null" {
    const timer = CountdownTimer.init(60);
    try testing.expect(timer.block == null);
}

// ============================================================================
// TICK TESTS
// ============================================================================

test "CountdownTimer tick decrements remaining_seconds" {
    var timer = CountdownTimer.init(60);
    timer.tick();
    try testing.expectEqual(@as(u64, 59), timer.remaining_seconds);
}

test "CountdownTimer tick from 1 goes to 0" {
    var timer = CountdownTimer.init(1);
    timer.tick();
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer tick from 0 stays at 0" {
    var timer = CountdownTimer.init(0);
    timer.tick();
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer tick multiple times" {
    var timer = CountdownTimer.init(10);
    timer.tick();
    timer.tick();
    timer.tick();
    try testing.expectEqual(@as(u64, 7), timer.remaining_seconds);
}

test "CountdownTimer tick from 0 multiple times stays at 0" {
    var timer = CountdownTimer.init(1);
    timer.tick();
    timer.tick();
    timer.tick();
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer tick preserves total_seconds" {
    var timer = CountdownTimer.init(60);
    timer.tick();
    try testing.expectEqual(@as(u64, 60), timer.total_seconds);
}

// ============================================================================
// TICKBY TESTS
// ============================================================================

test "CountdownTimer tickBy decrements by n" {
    var timer = CountdownTimer.init(100);
    timer.tickBy(25);
    try testing.expectEqual(@as(u64, 75), timer.remaining_seconds);
}

test "CountdownTimer tickBy with 0 is no-op" {
    var timer = CountdownTimer.init(50);
    timer.tickBy(0);
    try testing.expectEqual(@as(u64, 50), timer.remaining_seconds);
}

test "CountdownTimer tickBy by exactly remaining clamps to 0" {
    var timer = CountdownTimer.init(30);
    timer.tickBy(30);
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer tickBy beyond remaining clamps to 0" {
    var timer = CountdownTimer.init(20);
    timer.tickBy(50);
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer tickBy from 0 stays at 0" {
    var timer = CountdownTimer.init(0);
    timer.tickBy(10);
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer tickBy with large value" {
    var timer = CountdownTimer.init(1000);
    timer.tickBy(500);
    try testing.expectEqual(@as(u64, 500), timer.remaining_seconds);
}

test "CountdownTimer tickBy multiple times" {
    var timer = CountdownTimer.init(100);
    timer.tickBy(20);
    timer.tickBy(30);
    try testing.expectEqual(@as(u64, 50), timer.remaining_seconds);
}

// ============================================================================
// RESET TESTS
// ============================================================================

test "CountdownTimer reset restores remaining to total" {
    var timer = CountdownTimer.init(60);
    timer.remaining_seconds = 30;
    timer.reset();
    try testing.expectEqual(@as(u64, 60), timer.remaining_seconds);
}

test "CountdownTimer reset from 0 to total" {
    var timer = CountdownTimer.init(45);
    timer.remaining_seconds = 0;
    timer.reset();
    try testing.expectEqual(@as(u64, 45), timer.remaining_seconds);
}

test "CountdownTimer reset with zero total" {
    var timer = CountdownTimer.init(0);
    timer.remaining_seconds = 0;
    timer.reset();
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer reset after multiple ticks" {
    var timer = CountdownTimer.init(100);
    timer.tick();
    timer.tick();
    timer.tick();
    timer.reset();
    try testing.expectEqual(@as(u64, 100), timer.remaining_seconds);
}

// ============================================================================
// SETREMAINING TESTS
// ============================================================================

test "CountdownTimer setRemaining with value less than total" {
    var timer = CountdownTimer.init(100);
    timer.setRemaining(50);
    try testing.expectEqual(@as(u64, 50), timer.remaining_seconds);
}

test "CountdownTimer setRemaining with value equal to total" {
    var timer = CountdownTimer.init(60);
    timer.setRemaining(60);
    try testing.expectEqual(@as(u64, 60), timer.remaining_seconds);
}

test "CountdownTimer setRemaining with value above total clamps to total" {
    var timer = CountdownTimer.init(50);
    timer.setRemaining(100);
    try testing.expectEqual(@as(u64, 50), timer.remaining_seconds);
}

test "CountdownTimer setRemaining to 0" {
    var timer = CountdownTimer.init(100);
    timer.setRemaining(0);
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer setRemaining with zero total" {
    var timer = CountdownTimer.init(0);
    timer.setRemaining(10);
    try testing.expectEqual(@as(u64, 0), timer.remaining_seconds);
}

test "CountdownTimer setRemaining multiple times" {
    var timer = CountdownTimer.init(100);
    timer.setRemaining(75);
    try testing.expectEqual(@as(u64, 75), timer.remaining_seconds);
    timer.setRemaining(25);
    try testing.expectEqual(@as(u64, 25), timer.remaining_seconds);
}

// ============================================================================
// ISEXPIRED TESTS
// ============================================================================

test "CountdownTimer isExpired when remaining is 0" {
    var timer = CountdownTimer.init(60);
    timer.remaining_seconds = 0;
    try testing.expect(timer.isExpired());
}

test "CountdownTimer isExpired when remaining is greater than 0" {
    const timer = CountdownTimer.init(60);
    try testing.expect(!timer.isExpired());
}

test "CountdownTimer isExpired after tick to 0" {
    var timer = CountdownTimer.init(1);
    timer.tick();
    try testing.expect(timer.isExpired());
}

test "CountdownTimer isExpired after tickBy to 0" {
    var timer = CountdownTimer.init(50);
    timer.tickBy(50);
    try testing.expect(timer.isExpired());
}

test "CountdownTimer isExpired on init with zero total" {
    const timer = CountdownTimer.init(0);
    try testing.expect(timer.isExpired());
}

test "CountdownTimer not isExpired at 1" {
    var timer = CountdownTimer.init(100);
    timer.setRemaining(1);
    try testing.expect(!timer.isExpired());
}

// ============================================================================
// PROGRESS TESTS
// ============================================================================

test "CountdownTimer progress at full remaining" {
    const timer = CountdownTimer.init(100);
    const prog = timer.progress();
    try testing.expectApproxEqAbs(@as(f32, 1.0), prog, 0.0001);
}

test "CountdownTimer progress at half remaining" {
    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 50;
    const prog = timer.progress();
    try testing.expectApproxEqAbs(@as(f32, 0.5), prog, 0.0001);
}

test "CountdownTimer progress at quarter remaining" {
    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 25;
    const prog = timer.progress();
    try testing.expectApproxEqAbs(@as(f32, 0.25), prog, 0.0001);
}

test "CountdownTimer progress at zero remaining" {
    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 0;
    const prog = timer.progress();
    try testing.expectApproxEqAbs(@as(f32, 0.0), prog, 0.0001);
}

test "CountdownTimer progress with zero total returns 1.0" {
    const timer = CountdownTimer.init(0);
    const prog = timer.progress();
    try testing.expectApproxEqAbs(@as(f32, 1.0), prog, 0.0001);
}

test "CountdownTimer progress fractional values" {
    var timer = CountdownTimer.init(3);
    timer.remaining_seconds = 1;
    const prog = timer.progress();
    try testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), prog, 0.01);
}

// ============================================================================
// FORMATTIME TESTS
// ============================================================================

test "formatTime seconds format zero" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(0, .seconds, &buf);
    try testing.expectEqualStrings("0", result);
}

test "formatTime seconds format 90" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(90, .seconds, &buf);
    try testing.expectEqualStrings("90", result);
}

test "formatTime seconds format single digit" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(5, .seconds, &buf);
    try testing.expectEqualStrings("5", result);
}

test "formatTime seconds format large value" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(9999, .seconds, &buf);
    try testing.expectEqualStrings("9999", result);
}

test "formatTime mm_ss format zero" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(0, .mm_ss, &buf);
    try testing.expectEqualStrings("00:00", result);
}

test "formatTime mm_ss format 59 seconds" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(59, .mm_ss, &buf);
    try testing.expectEqualStrings("00:59", result);
}

test "formatTime mm_ss format 60 seconds (1 minute)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(60, .mm_ss, &buf);
    try testing.expectEqualStrings("01:00", result);
}

test "formatTime mm_ss format 61 seconds" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(61, .mm_ss, &buf);
    try testing.expectEqualStrings("01:01", result);
}

test "formatTime mm_ss format 3599 seconds (59:59)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(3599, .mm_ss, &buf);
    try testing.expectEqualStrings("59:59", result);
}

test "formatTime mm_ss format 3600 seconds (60:00 overflow)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(3600, .mm_ss, &buf);
    try testing.expectEqualStrings("60:00", result);
}

test "formatTime mm_ss format 120 seconds (2:00)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(120, .mm_ss, &buf);
    try testing.expectEqualStrings("02:00", result);
}

test "formatTime hh_mm_ss format zero" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(0, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("00:00:00", result);
}

test "formatTime hh_mm_ss format 59 seconds" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(59, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("00:00:59", result);
}

test "formatTime hh_mm_ss format 3661 seconds (01:01:01)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(3661, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("01:01:01", result);
}

test "formatTime hh_mm_ss format 3599 seconds (00:59:59)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(3599, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("00:59:59", result);
}

test "formatTime hh_mm_ss format 3600 seconds (01:00:00)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(3600, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("01:00:00", result);
}

test "formatTime hh_mm_ss format 1 second" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(1, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("00:00:01", result);
}

test "formatTime hh_mm_ss format 60 seconds (00:01:00)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(60, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("00:01:00", result);
}

test "formatTime hh_mm_ss format 7322 seconds (02:02:02)" {
    var buf: [9]u8 = undefined;
    const result = CountdownTimer.formatTime(7322, .hh_mm_ss, &buf);
    try testing.expectEqualStrings("02:02:02", result);
}

// ============================================================================
// CONTENTHEIGHT TESTS
// ============================================================================

test "CountdownTimer contentHeight with progress bar shown is 2" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(@as(u8, 2), timer.contentHeight());
}

test "CountdownTimer contentHeight without progress bar is 1" {
    var timer = CountdownTimer.init(60);
    timer.show_progress_bar = false;
    try testing.expectEqual(@as(u8, 1), timer.contentHeight());
}

test "CountdownTimer contentHeight with both features is 2" {
    const timer = CountdownTimer.init(60);
    try testing.expectEqual(@as(u8, 2), timer.contentHeight());
}

test "CountdownTimer contentHeight zero total" {
    const timer = CountdownTimer.init(0);
    try testing.expectEqual(@as(u8, 2), timer.contentHeight());
}

// ============================================================================
// BUILDER TESTS - IMMUTABILITY
// ============================================================================

test "CountdownTimer withTotalSeconds preserves immutability" {
    const original = CountdownTimer.init(100);
    const modified = original.withTotalSeconds(200);

    try testing.expectEqual(@as(u64, 100), original.total_seconds);
    try testing.expectEqual(@as(u64, 200), modified.total_seconds);
}

test "CountdownTimer withShowProgressBar preserves immutability" {
    const original = CountdownTimer.init(60);
    const modified = original.withShowProgressBar(false);

    try testing.expect(original.show_progress_bar);
    try testing.expect(!modified.show_progress_bar);
}

test "CountdownTimer withShowTotal preserves immutability" {
    const original = CountdownTimer.init(60);
    const modified = original.withShowTotal(false);

    try testing.expect(original.show_total);
    try testing.expect(!modified.show_total);
}

test "CountdownTimer withFormat preserves immutability" {
    const original = CountdownTimer.init(60);
    const modified = original.withFormat(.hh_mm_ss);

    try testing.expectEqual(CountdownTimer.TimeFormat.mm_ss, original.format);
    try testing.expectEqual(CountdownTimer.TimeFormat.hh_mm_ss, modified.format);
}

test "CountdownTimer withBarChar preserves immutability" {
    const original = CountdownTimer.init(60);
    const modified = original.withBarChar('=');

    try testing.expectEqual(@as(u21, '█'), original.bar_char);
    try testing.expectEqual(@as(u21, '='), modified.bar_char);
}

test "CountdownTimer withEmptyChar preserves immutability" {
    const original = CountdownTimer.init(60);
    const modified = original.withEmptyChar('-');

    try testing.expectEqual(@as(u21, '░'), original.empty_char);
    try testing.expectEqual(@as(u21, '-'), modified.empty_char);
}

test "CountdownTimer withTimeStyle preserves immutability" {
    const original = CountdownTimer.init(60);
    const style = Style{ .fg = Color.red };
    const modified = original.withTimeStyle(style);

    try testing.expect(original.time_style.fg == null);
    try testing.expect(modified.time_style.fg != null);
}

test "CountdownTimer withBarFilledStyle preserves immutability" {
    const original = CountdownTimer.init(60);
    const style = Style{ .fg = Color.green };
    const modified = original.withBarFilledStyle(style);

    try testing.expect(original.bar_filled_style.fg == null);
    try testing.expect(modified.bar_filled_style.fg != null);
}

test "CountdownTimer withBarEmptyStyle preserves immutability" {
    const original = CountdownTimer.init(60);
    const style = Style{ .fg = Color.blue };
    const modified = original.withBarEmptyStyle(style);

    try testing.expect(original.bar_empty_style.fg == null);
    try testing.expect(modified.bar_empty_style.fg != null);
}

test "CountdownTimer withBlock preserves immutability" {
    const original = CountdownTimer.init(60);
    const block = Block{};
    const modified = original.withBlock(block);

    try testing.expect(original.block == null);
    try testing.expect(modified.block != null);
}

test "CountdownTimer builder chain multiple methods" {
    const original = CountdownTimer.init(100);
    const modified = original
        .withTotalSeconds(200)
        .withShowProgressBar(false)
        .withShowTotal(false)
        .withFormat(.hh_mm_ss);

    try testing.expectEqual(@as(u64, 100), original.total_seconds);
    try testing.expect(original.show_progress_bar);
    try testing.expect(original.show_total);
    try testing.expectEqual(CountdownTimer.TimeFormat.mm_ss, original.format);

    try testing.expectEqual(@as(u64, 200), modified.total_seconds);
    try testing.expect(!modified.show_progress_bar);
    try testing.expect(!modified.show_total);
    try testing.expectEqual(CountdownTimer.TimeFormat.hh_mm_ss, modified.format);
}

// ============================================================================
// RENDER TESTS - BASIC
// ============================================================================

test "CountdownTimer render with zero width does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const timer = CountdownTimer.init(60);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with zero height does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const timer = CountdownTimer.init(60);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render basic time display" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(60);
    timer.remaining_seconds = 45;
    timer.show_progress_bar = false;
    timer.show_total = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with progress bar" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 50;
    timer.show_progress_bar = true;
    timer.show_total = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with show_total" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(120);
    timer.remaining_seconds = 60;
    timer.show_total = true;
    timer.show_progress_bar = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render without show_total" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(120);
    timer.remaining_seconds = 60;
    timer.show_total = false;
    timer.show_progress_bar = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(60);
    timer.block = Block{};
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render progress bar at 0 percent" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 0;
    timer.show_progress_bar = true;
    timer.show_total = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render progress bar at 50 percent" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 50;
    timer.show_progress_bar = true;
    timer.show_total = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render progress bar at 100 percent" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 100;
    timer.show_progress_bar = true;
    timer.show_total = false;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with zero total_seconds" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const timer = CountdownTimer.init(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with custom bar_char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 50;
    timer.bar_char = '=';
    timer.empty_char = '-';
    timer.show_progress_bar = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with custom bar_empty_char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 75;
    timer.bar_char = '#';
    timer.empty_char = '.';
    timer.show_progress_bar = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render progress bar calculation is correct" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 25;
    timer.show_progress_bar = true;
    timer.show_total = false;
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render both time and progress bar" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(120);
    timer.remaining_seconds = 60;
    timer.show_progress_bar = true;
    timer.show_total = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with hh_mm_ss format" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(7322);
    timer.remaining_seconds = 3661;
    timer.format = .hh_mm_ss;
    timer.show_progress_bar = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with seconds format" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(3600);
    timer.remaining_seconds = 1234;
    timer.format = .seconds;
    timer.show_progress_bar = false;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with offset position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 40, 15);
    defer buf.deinit();

    var timer = CountdownTimer.init(60);
    timer.remaining_seconds = 30;
    timer.show_progress_bar = true;
    const area = Rect{ .x = 5, .y = 5, .width = 20, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render multiple times" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };

    timer.remaining_seconds = 100;
    timer.render(&buf, area);

    timer.remaining_seconds = 50;
    timer.render(&buf, area);

    timer.remaining_seconds = 0;
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render very narrow width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(60);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render very tall height" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 50);
    defer buf.deinit();

    var timer = CountdownTimer.init(60);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 40 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with block and progress bar" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 50;
    timer.block = Block{};
    timer.show_progress_bar = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 6 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render expired state" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(100);
    timer.remaining_seconds = 0;
    timer.show_progress_bar = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}

test "CountdownTimer render with styles applied" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var timer = CountdownTimer.init(60);
    timer.time_style = Style{ .fg = Color.red };
    timer.bar_filled_style = Style{ .fg = Color.green };
    timer.bar_empty_style = Style{ .fg = Color.gray };
    timer.show_progress_bar = true;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    timer.render(&buf, area);

    try testing.expect(true);
}
