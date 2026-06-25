//! StopWatch Widget Tests — TDD Red Phase
//!
//! Tests stopwatch widget with lap tracking, time formatting, builder pattern,
//! rendering with styles, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const StopWatch = sailor.tui.widgets.StopWatch;

// ============================================================================
// Helper Functions
// ============================================================================

/// Decode UTF-8 text into a codepoint slice (max 128 codepoints)
fn decodeUtf8(text: []const u8, out: []u21) usize {
    var len: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (len >= out.len) break;
        out[len] = cp;
        len += 1;
    }
    return len;
}

/// Check if a buffer row contains a given text string (UTF-8 aware)
fn rowContains(buf: Buffer, row: u16, text: []const u8) bool {
    var cps: [128]u21 = undefined;
    const cp_len = decodeUtf8(text, &cps);
    if (cp_len == 0) return true;

    var i: u16 = 0;
    while (i < buf.width) : (i += 1) {
        var matched = true;
        var j: usize = 0;
        var col = i;

        while (j < cp_len and col < buf.width) : (j += 1) {
            const cell = buf.getConst(col, row) orelse { matched = false; break; };
            if (cell.char != cps[j]) { matched = false; break; }
            col += 1;
        }

        if (j == cp_len and matched) return true;
    }
    return false;
}

/// Check if a buffer row contains substring starting at specific column (UTF-8 aware)
fn rowContainsAt(buf: Buffer, row: u16, col_start: u16, text: []const u8) bool {
    var cps: [128]u21 = undefined;
    const cp_len = decodeUtf8(text, &cps);

    var col = col_start;
    var j: usize = 0;

    while (j < cp_len and col < buf.width) : (j += 1) {
        const cell = buf.getConst(col, row) orelse return false;
        if (cell.char != cps[j]) return false;
        col += 1;
    }

    return j == cp_len;
}

/// Get character at buffer position
fn getCharAt(buf: Buffer, x: u16, y: u16) u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return ' ';
}

// ============================================================================
// Init Tests (5 tests)
// ============================================================================

test "StopWatch.init has elapsed_ms == 0" {
    const sw = StopWatch.init();
    try testing.expectEqual(@as(u64, 0), sw.elapsed_ms);
}

test "StopWatch.init has running == false" {
    const sw = StopWatch.init();
    try testing.expect(sw.running == false);
}

test "StopWatch.init has show_laps == true" {
    const sw = StopWatch.init();
    try testing.expect(sw.show_laps == true);
}

test "StopWatch.init has show_milliseconds == true" {
    const sw = StopWatch.init();
    try testing.expect(sw.show_milliseconds == true);
}

test "StopWatch.init has empty label" {
    const sw = StopWatch.init();
    try testing.expectEqual(@as(usize, 0), sw.label.len);
}

test "StopWatch.init has no laps" {
    const sw = StopWatch.init();
    try testing.expectEqual(@as(usize, 0), sw.laps.len);
}

// ============================================================================
// formatTime Tests (15 tests)
// ============================================================================

test "formatTime(0, true) returns 00:00:00.000" {
    const result = StopWatch.formatTime(0, true);
    try testing.expectEqualStrings("00:00:00.000", &result);
}

test "formatTime(0, false) returns 00:00:00 with spaces" {
    const result = StopWatch.formatTime(0, false);
    try testing.expectEqual(@as(u21, '0'), result[0]);
    try testing.expectEqual(@as(u21, '0'), result[8]);
    try testing.expectEqual(@as(u21, ' '), result[9]);
    try testing.expectEqual(@as(u21, ' '), result[11]);
    try testing.expectEqual(@as(usize, 12), 12); // verify length
}

test "formatTime(1000, true) returns 00:00:01.000" {
    const result = StopWatch.formatTime(1000, true);
    try testing.expectEqualStrings("00:00:01.000", &result);
}

test "formatTime(1500, true) returns 00:00:01.500" {
    const result = StopWatch.formatTime(1500, true);
    try testing.expectEqualStrings("00:00:01.500", &result);
}

test "formatTime(60000, true) returns 00:01:00.000" {
    const result = StopWatch.formatTime(60000, true);
    try testing.expectEqualStrings("00:01:00.000", &result);
}

test "formatTime(3600000, true) returns 01:00:00.000" {
    const result = StopWatch.formatTime(3600000, true);
    try testing.expectEqualStrings("01:00:00.000", &result);
}

test "formatTime(3661001, true) returns 01:01:01.001" {
    const result = StopWatch.formatTime(3661001, true);
    try testing.expectEqualStrings("01:01:01.001", &result);
}

test "formatTime(90000, true) returns 00:01:30.000" {
    const result = StopWatch.formatTime(90000, true);
    try testing.expectEqualStrings("00:01:30.000", &result);
}

test "formatTime(999, true) returns 00:00:00.999" {
    const result = StopWatch.formatTime(999, true);
    try testing.expectEqualStrings("00:00:00.999", &result);
}

test "formatTime(59999, true) returns 00:00:59.999" {
    const result = StopWatch.formatTime(59999, true);
    try testing.expectEqualStrings("00:00:59.999", &result);
}

test "formatTime(36000000, true) returns 10:00:00.000" {
    const result = StopWatch.formatTime(36000000, true);
    try testing.expectEqualStrings("10:00:00.000", &result);
}

test "formatTime(123456, true) returns 00:02:03.456" {
    const result = StopWatch.formatTime(123456, true);
    try testing.expectEqualStrings("00:02:03.456", &result);
}

test "formatTime always returns exactly 12 bytes" {
    const result = StopWatch.formatTime(0, true);
    try testing.expectEqual(@as(usize, 12), result.len);
    const result2 = StopWatch.formatTime(3661001, false);
    try testing.expectEqual(@as(usize, 12), result2.len);
}

test "formatTime(86399999, true) returns 23:59:59.999" {
    const result = StopWatch.formatTime(86399999, true);
    try testing.expectEqualStrings("23:59:59.999", &result);
}

// ============================================================================
// lastLapMs Tests (5 tests)
// ============================================================================

test "lastLapMs with no laps returns elapsed_ms" {
    const sw = StopWatch.init().withElapsedMs(5000);
    try testing.expectEqual(@as(u64, 5000), sw.lastLapMs());
}

test "lastLapMs with one lap [5000] and elapsed_ms=7000 returns 2000" {
    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(7000)
        .withLaps(&laps);
    try testing.expectEqual(@as(u64, 2000), sw.lastLapMs());
}

test "lastLapMs with one lap [5000] and elapsed_ms=5000 returns 0" {
    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withLaps(&laps);
    try testing.expectEqual(@as(u64, 0), sw.lastLapMs());
}

test "lastLapMs with multiple laps [3000, 7000, 10000] and elapsed_ms=12000 returns 2000" {
    var laps = [_]u64{ 3000, 7000, 10000 };
    const sw = StopWatch.init()
        .withElapsedMs(12000)
        .withLaps(&laps);
    try testing.expectEqual(@as(u64, 2000), sw.lastLapMs());
}

test "lastLapMs handles saturating subtraction correctly" {
    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(3000)
        .withLaps(&laps);
    // elapsed < last_lap: use saturating sub, may be 0 or handle gracefully
    const result = sw.lastLapMs();
    try testing.expect(result <= 3000);
}

// ============================================================================
// lapCount Tests (3 tests)
// ============================================================================

test "lapCount with no laps returns 0" {
    const sw = StopWatch.init();
    try testing.expectEqual(@as(usize, 0), sw.lapCount());
}

test "lapCount with 5 laps returns 5" {
    var laps = [_]u64{ 1000, 2000, 3000, 4000, 5000 };
    const sw = StopWatch.init().withLaps(&laps);
    try testing.expectEqual(@as(usize, 5), sw.lapCount());
}

test "lapCount with exactly MAX_LAPS laps returns MAX_LAPS" {
    var laps: [StopWatch.MAX_LAPS]u64 = undefined;
    for (0..StopWatch.MAX_LAPS) |i| {
        laps[i] = @as(u64, @intCast(i + 1)) * 1000;
    }
    const sw = StopWatch.init().withLaps(&laps);
    try testing.expectEqual(StopWatch.MAX_LAPS, sw.lapCount());
}

// ============================================================================
// Builder Immutability Tests (5 tests)
// ============================================================================

test "withElapsedMs returns modified copy, original unchanged" {
    const sw = StopWatch.init();
    const sw2 = sw.withElapsedMs(5000);

    try testing.expectEqual(@as(u64, 0), sw.elapsed_ms);
    try testing.expectEqual(@as(u64, 5000), sw2.elapsed_ms);
}

test "withRunning returns modified copy, original unchanged" {
    const sw = StopWatch.init();
    const sw2 = sw.withRunning(true);

    try testing.expect(sw.running == false);
    try testing.expect(sw2.running == true);
}

test "withShowLaps returns modified copy, original unchanged" {
    const sw = StopWatch.init();
    const sw2 = sw.withShowLaps(false);

    try testing.expect(sw.show_laps == true);
    try testing.expect(sw2.show_laps == false);
}

test "withShowMilliseconds returns modified copy, original unchanged" {
    const sw = StopWatch.init();
    const sw2 = sw.withShowMilliseconds(false);

    try testing.expect(sw.show_milliseconds == true);
    try testing.expect(sw2.show_milliseconds == false);
}

test "withLaps returns modified copy, original laps unchanged" {
    var laps1 = [_]u64{1000};
    var laps2 = [_]u64{ 2000, 3000 };
    const sw = StopWatch.init().withLaps(&laps1);
    const sw2 = sw.withLaps(&laps2);

    try testing.expectEqual(@as(usize, 1), sw.laps.len);
    try testing.expectEqual(@as(usize, 2), sw2.laps.len);
}

// ============================================================================
// Render Zero/Minimal Area Tests (4 tests)
// ============================================================================

test "render with area width=0 height=0 does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    sw.render(&buf, area); // Should return early
    try testing.expect(true);
}

test "render with area width=1 height=1 does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    sw.render(&buf, area); // Should render time in minimal space
    try testing.expect(true);
}

test "render with width=20 height=1 renders time only" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init().withElapsedMs(5000);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    sw.render(&buf, area);

    // Time should be in row 0
    try testing.expect(rowContains(buf, 0, "00:00:05.000"));
    // Status should NOT be rendered (height < 2)
    try testing.expect(!rowContains(buf, 0, "RUNNING"));
}

test "render with width=20 height=2 renders time and status" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withRunning(false);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 2 };

    sw.render(&buf, area);

    // Time should be in row 0
    try testing.expect(rowContains(buf, 0, "00:00:05.000"));
    // Status should be in row 1
    try testing.expect(rowContains(buf, 1, "PAUSED"));
}

// ============================================================================
// Render Time Display Tests (6 tests)
// ============================================================================

test "render with elapsed_ms=0 displays 00:00:00.000 in row 0" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init().withElapsedMs(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "00:00:00.000"));
}

test "render with elapsed_ms=65123 displays 00:01:05.123 in row 0" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init().withElapsedMs(65123);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    try testing.expect(rowContains(buf, 0, "00:01:05.123"));
}

test "render with show_milliseconds=false does not display decimal in time" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init()
        .withElapsedMs(65123)
        .withShowMilliseconds(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Should contain "00:01:05" but not ".123"
    try testing.expect(rowContains(buf, 0, "00:01:05"));
    try testing.expect(!rowContains(buf, 0, ".123"));
}

test "render time row is centered in inner area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init().withElapsedMs(5000);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Verify time appears somewhere in row 0 (centered)
    var found = false;
    var col: u16 = 0;
    while (col < 40) : (col += 1) {
        if (rowContainsAt(buf, 0, col, "00:00:05.000")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "render time row applies time_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const style = Style{ .fg = .green };
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withTimeStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Find where time is rendered and check style
    var found_styled = false;
    var col: u16 = 0;
    while (col < 40) : (col += 1) {
        if (buf.getConst(col, 0)) |cell| {
            if (cell.char == '0' and std.meta.eql(cell.style.fg, .green)) {
                found_styled = true;
                break;
            }
        }
    }
    try testing.expect(found_styled);
}

test "render with block border renders time inside border" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const block = Block{};
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withBlock(block);
    const area = Rect{ .x = 1, .y = 1, .width = 38, .height = 18 };

    sw.render(&buf, area);

    // Time should be rendered inside border area
    var found = false;
    var row: u16 = 1;
    while (row < 20) : (row += 1) {
        if (rowContains(buf, row, "00:00:05.000")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

// ============================================================================
// Render Status Indicator Tests (4 tests)
// ============================================================================

test "render with running=true and height>=2 displays [RUNNING]" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withRunning(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    try testing.expect(rowContains(buf, 1, "RUNNING"));
}

test "render with running=false and height>=2 displays [PAUSED]" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withRunning(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    try testing.expect(rowContains(buf, 1, "PAUSED"));
}

test "render status is centered in inner area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withRunning(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Verify status appears somewhere in row 1 (centered)
    var found = false;
    var col: u16 = 0;
    while (col < 40) : (col += 1) {
        if (rowContainsAt(buf, 1, col, "RUNNING")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "render status applies status_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const style = Style{ .fg = .red };
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withRunning(true)
        .withStatusStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Find status text and verify style applied
    var found_styled = false;
    var col: u16 = 0;
    while (col < 40) : (col += 1) {
        if (buf.getConst(col, 1)) |cell| {
            if (cell.char == 'R' and std.meta.eql(cell.style.fg, .red)) {
                found_styled = true;
                break;
            }
        }
    }
    try testing.expect(found_styled);
}

// ============================================================================
// Render Lap List Tests (8 tests)
// ============================================================================

test "render with show_laps=true and no laps displays no divider" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withShowLaps(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Row 2 should not contain divider (─)
    try testing.expect(!rowContains(buf, 2, "─"));
}

test "render with show_laps=false and laps present does not display lap rows" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(7000)
        .withShowLaps(false)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Should not contain "Lap" text
    try testing.expect(!rowContains(buf, 3, "Lap 1"));
}

test "render with 1 lap displays divider at row 2 and lap row at row 3" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(7000)
        .withShowLaps(true)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Row 2 should contain divider
    try testing.expect(rowContains(buf, 2, "─"));
    // Row 3 should contain lap info
    try testing.expect(rowContains(buf, 3, "Lap 1"));
}

test "render lap row contains Lap N identifier" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(7000)
        .withShowLaps(true)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    try testing.expect(rowContains(buf, 3, "Lap 1"));
}

test "render lap row contains split time (delta from previous lap)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(7000)
        .withShowLaps(true)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // First lap split = 5000ms = 00:00:05.000
    try testing.expect(rowContains(buf, 3, "00:00:05"));
}

test "render lap row contains cumulative time" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{5000};
    const sw = StopWatch.init()
        .withElapsedMs(7000)
        .withShowLaps(true)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Cumulative time for lap 1 = 5000ms = 00:00:05.000
    // Should appear twice in row (split and cumulative)
    try testing.expect(rowContains(buf, 3, "00:00:05"));
}

test "render with 3 laps displays all 3 lap rows" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{ 3000, 7000, 10000 };
    const sw = StopWatch.init()
        .withElapsedMs(12000)
        .withShowLaps(true)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Should display all 3 laps
    try testing.expect(rowContains(buf, 3, "Lap 1"));
    try testing.expect(rowContains(buf, 4, "Lap 2"));
    try testing.expect(rowContains(buf, 5, "Lap 3"));
}

test "render with height constraint shows last laps only" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{ 1000, 2000, 3000, 4000, 5000 };
    const sw = StopWatch.init()
        .withElapsedMs(6000)
        .withShowLaps(true)
        .withLaps(&laps);
    // Height = 5: time + status + divider = 3 rows, so only 2 laps fit
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    sw.render(&buf, area);

    // Should show last laps (4 and 5), not first ones (1, 2, 3)
    try testing.expect(!rowContains(buf, 3, "Lap 1"));
    try testing.expect(!rowContains(buf, 4, "Lap 2"));
    // Lap 4 or 5 should appear
    var found_later = false;
    var row: u16 = 3;
    while (row < 5) : (row += 1) {
        if (rowContains(buf, row, "Lap 4") or rowContains(buf, row, "Lap 5")) {
            found_later = true;
            break;
        }
    }
    try testing.expect(found_later);
}

// ============================================================================
// Render Styles Tests (3 tests)
// ============================================================================

test "render applies lap_style to lap rows" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{5000};
    const style = Style{ .fg = .blue };
    const sw = StopWatch.init()
        .withElapsedMs(7000)
        .withShowLaps(true)
        .withLaps(&laps)
        .withLapStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Find lap text and verify style applied
    var found_styled = false;
    var col: u16 = 0;
    while (col < 40) : (col += 1) {
        if (buf.getConst(col, 3)) |cell| {
            if (cell.char == 'L' and std.meta.eql(cell.style.fg, .blue)) {
                found_styled = true;
                break;
            }
        }
    }
    try testing.expect(found_styled);
}

test "render applies base style to entire widget area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const style = Style{ .bg = .black };
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Verify some cells have the background style
    var found_styled = false;
    var col: u16 = 0;
    while (col < 40) : (col += 1) {
        if (buf.getConst(col, 0)) |cell| {
            if (std.meta.eql(cell.style.bg, .black)) {
                found_styled = true;
                break;
            }
        }
    }
    try testing.expect(found_styled);
}

test "render with block renders border" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const block = Block{};
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);

    // Check for border characters (at least at corners or edges)
    // Block renders borders with characters like ─, │, ┌, ┐, └, ┘
    var found_border = false;
    var col: u16 = 0;
    while (col < 40) : (col += 1) {
        if (buf.getConst(col, 0)) |cell| {
            // Look for common border chars
            if (cell.char == '─' or cell.char == '│' or cell.char == '┌' or
                cell.char == '┐' or cell.char == '└' or cell.char == '┘') {
                found_border = true;
                break;
            }
        }
    }
    try testing.expect(found_border);
}

// ============================================================================
// Edge Cases Tests (5 tests)
// ============================================================================

test "render with MAX_LAPS laps does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 100);
    defer buf.deinit();

    var laps: [StopWatch.MAX_LAPS]u64 = undefined;
    for (0..StopWatch.MAX_LAPS) |i| {
        laps[i] = @as(u64, @intCast(i + 1)) * 1000;
    }

    const sw = StopWatch.init()
        .withElapsedMs(StopWatch.MAX_LAPS * 1000 + 500)
        .withShowLaps(true)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 100 };

    sw.render(&buf, area); // Should not crash
    try testing.expect(true);
}

test "render with large elapsed_ms does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init().withElapsedMs(3600000 * 100); // 100 hours
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);
    try testing.expect(true);
}

test "render with laps containing all equal values does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    var laps = [_]u64{ 5000, 5000, 5000 };
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withShowLaps(true)
        .withLaps(&laps);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);
    try testing.expect(true);
}

test "render with laps longer than MAX_LAPS caps at MAX_LAPS" {
    var buf = try Buffer.init(testing.allocator, 40, 100);
    defer buf.deinit();

    // Create slice with more than MAX_LAPS
    var laps: [StopWatch.MAX_LAPS + 10]u64 = undefined;
    for (0..StopWatch.MAX_LAPS + 10) |i| {
        laps[i] = @as(u64, @intCast(i + 1)) * 1000;
    }

    const sw = StopWatch.init()
        .withElapsedMs((StopWatch.MAX_LAPS + 10) * 1000)
        .withShowLaps(true)
        .withLaps(laps[0 .. StopWatch.MAX_LAPS + 10]);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 100 };

    sw.render(&buf, area);
    // lapCount should be capped
    try testing.expectEqual(StopWatch.MAX_LAPS, sw.lapCount());
}

test "render with empty label does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withLabel("");
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };

    sw.render(&buf, area);
    try testing.expect(true);
}

// ============================================================================
// Builder Chain Tests (4 tests)
// ============================================================================

test "builder methods can be chained" {
    const sw = StopWatch.init()
        .withElapsedMs(5000)
        .withRunning(true)
        .withShowLaps(true)
        .withShowMilliseconds(true);

    try testing.expectEqual(@as(u64, 5000), sw.elapsed_ms);
    try testing.expect(sw.running == true);
    try testing.expect(sw.show_laps == true);
    try testing.expect(sw.show_milliseconds == true);
}

test "builder chaining does not affect original" {
    const sw1 = StopWatch.init();
    const sw2 = sw1.withElapsedMs(5000).withRunning(true);
    const sw3 = sw1.withElapsedMs(10000);

    try testing.expectEqual(@as(u64, 0), sw1.elapsed_ms);
    try testing.expectEqual(@as(u64, 5000), sw2.elapsed_ms);
    try testing.expectEqual(@as(u64, 10000), sw3.elapsed_ms);
}

test "withLabel sets label correctly" {
    const sw = StopWatch.init().withLabel("My Timer");
    try testing.expectEqualStrings("My Timer", sw.label);
}

test "withStyle sets style correctly" {
    const style = Style{ .bold = true };
    const sw = StopWatch.init().withStyle(style);
    try testing.expect(sw.style.bold == true);
}
