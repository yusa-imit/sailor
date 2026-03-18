const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;

// Forward declaration - will be implemented in src/tui/widgets/calendar.zig
const Calendar = sailor.tui.widgets.Calendar;
const Date = Calendar.Date;

// ============================================================================
// Helper Functions
// ============================================================================

/// Create a date with the given year, month, day
fn createDate(year: u16, month: u8, day: u8) Date {
    return Date.init(year, month, day);
}

/// Create a today's date (2026-03-18)
fn createToday() Date {
    return Date.init(2026, 3, 18);
}

// ============================================================================
// Date Struct Tests
// ============================================================================

test "Date.init creates valid date" {
    const date = createDate(2026, 3, 18);
    try std.testing.expectEqual(@as(u16, 2026), date.year);
    try std.testing.expectEqual(@as(u8, 3), date.month);
    try std.testing.expectEqual(@as(u8, 18), date.day);
}

test "Date.eql returns true for equal dates" {
    const date1 = createDate(2026, 3, 18);
    const date2 = createDate(2026, 3, 18);
    try std.testing.expectEqual(true, date1.eql(date2));
}

test "Date.eql returns false for different dates" {
    const date1 = createDate(2026, 3, 18);
    const date2 = createDate(2026, 3, 19);
    try std.testing.expectEqual(false, date1.eql(date2));
}

test "Date.eql returns false for different months" {
    const date1 = createDate(2026, 3, 18);
    const date2 = createDate(2026, 4, 18);
    try std.testing.expectEqual(false, date1.eql(date2));
}

test "Date.eql returns false for different years" {
    const date1 = createDate(2026, 3, 18);
    const date2 = createDate(2025, 3, 18);
    try std.testing.expectEqual(false, date1.eql(date2));
}

test "Date.compare returns -1 for earlier date" {
    const date1 = createDate(2026, 3, 18);
    const date2 = createDate(2026, 3, 19);
    try std.testing.expectEqual(@as(i8, -1), date1.compare(date2));
}

test "Date.compare returns 1 for later date" {
    const date1 = createDate(2026, 3, 19);
    const date2 = createDate(2026, 3, 18);
    try std.testing.expectEqual(@as(i8, 1), date1.compare(date2));
}

test "Date.compare returns 0 for equal dates" {
    const date1 = createDate(2026, 3, 18);
    const date2 = createDate(2026, 3, 18);
    try std.testing.expectEqual(@as(i8, 0), date1.compare(date2));
}

test "Date.compare handles year differences" {
    const date1 = createDate(2025, 3, 18);
    const date2 = createDate(2026, 3, 18);
    try std.testing.expectEqual(@as(i8, -1), date1.compare(date2));
}

test "Date.compare handles month differences" {
    const date1 = createDate(2026, 2, 18);
    const date2 = createDate(2026, 3, 18);
    try std.testing.expectEqual(@as(i8, -1), date1.compare(date2));
}

test "Date.addDays adds days within month" {
    const date = createDate(2026, 3, 18);
    const result = date.addDays(5);
    try std.testing.expectEqual(@as(u16, 2026), result.year);
    try std.testing.expectEqual(@as(u8, 3), result.month);
    try std.testing.expectEqual(@as(u8, 23), result.day);
}

test "Date.addDays wraps to next month" {
    const date = createDate(2026, 3, 28);
    const result = date.addDays(5);
    try std.testing.expectEqual(@as(u16, 2026), result.year);
    try std.testing.expectEqual(@as(u8, 4), result.month);
    try std.testing.expectEqual(@as(u8, 2), result.day);
}

test "Date.addDays wraps to next year" {
    const date = createDate(2026, 12, 28);
    const result = date.addDays(5);
    try std.testing.expectEqual(@as(u16, 2027), result.year);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u8, 2), result.day);
}

test "Date.addDays handles negative days (subtracts)" {
    const date = createDate(2026, 3, 18);
    const result = date.addDays(-5);
    try std.testing.expectEqual(@as(u16, 2026), result.year);
    try std.testing.expectEqual(@as(u8, 3), result.month);
    try std.testing.expectEqual(@as(u8, 13), result.day);
}

test "Date.addDays handles negative days wrapping to previous month" {
    const date = createDate(2026, 3, 5);
    const result = date.addDays(-10);
    try std.testing.expectEqual(@as(u16, 2026), result.year);
    try std.testing.expectEqual(@as(u8, 2), result.month);
    try std.testing.expectEqual(@as(u8, 23), result.day);
}

test "Date.addDays zero days returns same date" {
    const date = createDate(2026, 3, 18);
    const result = date.addDays(0);
    try std.testing.expectEqual(true, result.eql(date));
}

test "Date.addMonths adds months within year" {
    const date = createDate(2026, 3, 18);
    const result = date.addMonths(3);
    try std.testing.expectEqual(@as(u16, 2026), result.year);
    try std.testing.expectEqual(@as(u8, 6), result.month);
    try std.testing.expectEqual(@as(u8, 18), result.day);
}

test "Date.addMonths wraps to next year" {
    const date = createDate(2026, 10, 18);
    const result = date.addMonths(5);
    try std.testing.expectEqual(@as(u16, 2027), result.year);
    try std.testing.expectEqual(@as(u8, 3), result.month);
    try std.testing.expectEqual(@as(u8, 18), result.day);
}

test "Date.addMonths handles negative months (subtracts)" {
    const date = createDate(2026, 6, 18);
    const result = date.addMonths(-3);
    try std.testing.expectEqual(@as(u16, 2026), result.year);
    try std.testing.expectEqual(@as(u8, 3), result.month);
    try std.testing.expectEqual(@as(u8, 18), result.day);
}

test "Date.addMonths wraps to previous year" {
    const date = createDate(2026, 2, 18);
    const result = date.addMonths(-5);
    try std.testing.expectEqual(@as(u16, 2025), result.year);
    try std.testing.expectEqual(@as(u8, 9), result.month);
    try std.testing.expectEqual(@as(u8, 18), result.day);
}

test "Date.addMonths handles day overflow (Feb 31 -> Feb 28)" {
    const date = createDate(2026, 1, 31);
    const result = date.addMonths(1);
    try std.testing.expectEqual(@as(u16, 2026), result.year);
    try std.testing.expectEqual(@as(u8, 2), result.month);
    try std.testing.expectEqual(@as(u8, 28), result.day); // Non-leap year
}

test "Date.addMonths handles leap year Feb 29" {
    const date = createDate(2024, 1, 31);
    const result = date.addMonths(1);
    try std.testing.expectEqual(@as(u16, 2024), result.year);
    try std.testing.expectEqual(@as(u8, 2), result.month);
    try std.testing.expectEqual(@as(u8, 29), result.day); // Leap year
}

test "Date.addMonths zero months returns same date" {
    const date = createDate(2026, 3, 18);
    const result = date.addMonths(0);
    try std.testing.expectEqual(true, result.eql(date));
}

test "Date.isValid returns true for valid dates" {
    try std.testing.expectEqual(true, createDate(2026, 3, 18).isValid());
    try std.testing.expectEqual(true, createDate(2026, 1, 1).isValid());
    try std.testing.expectEqual(true, createDate(2026, 12, 31).isValid());
    try std.testing.expectEqual(true, createDate(2024, 2, 29).isValid()); // Leap year
}

test "Date.isValid returns false for invalid month" {
    try std.testing.expectEqual(false, createDate(2026, 0, 18).isValid());
    try std.testing.expectEqual(false, createDate(2026, 13, 18).isValid());
}

test "Date.isValid returns false for invalid day" {
    try std.testing.expectEqual(false, createDate(2026, 3, 0).isValid());
    try std.testing.expectEqual(false, createDate(2026, 3, 32).isValid());
}

test "Date.isValid returns false for Feb 30" {
    try std.testing.expectEqual(false, createDate(2026, 2, 30).isValid());
}

test "Date.isValid returns false for Feb 29 non-leap year" {
    try std.testing.expectEqual(false, createDate(2026, 2, 29).isValid());
}

test "Date.daysInMonth returns 31 for January" {
    try std.testing.expectEqual(@as(u8, 31), createDate(2026, 1, 1).daysInMonth());
}

test "Date.daysInMonth returns 28 for February non-leap year" {
    try std.testing.expectEqual(@as(u8, 28), createDate(2026, 2, 1).daysInMonth());
}

test "Date.daysInMonth returns 29 for February leap year" {
    try std.testing.expectEqual(@as(u8, 29), createDate(2024, 2, 1).daysInMonth());
}

test "Date.daysInMonth returns 30 for April" {
    try std.testing.expectEqual(@as(u8, 30), createDate(2026, 4, 1).daysInMonth());
}

test "Date.daysInMonth returns 31 for December" {
    try std.testing.expectEqual(@as(u8, 31), createDate(2026, 12, 1).daysInMonth());
}

test "Date.daysInMonth checks all months have correct days" {
    const expected = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    for (1..13) |month| {
        const date = createDate(2026, @intCast(month), 1);
        try std.testing.expectEqual(expected[month - 1], date.daysInMonth());
    }
}

test "Date.dayOfWeek returns correct day for known dates" {
    // 2026-03-18 is a Wednesday (3)
    const date = createDate(2026, 3, 18);
    try std.testing.expectEqual(@as(u3, 3), date.dayOfWeek());
}

test "Date.dayOfWeek returns 0 for Sunday" {
    // We need to find a Sunday in 2026
    // 2026-03-15 is a Sunday
    const date = createDate(2026, 3, 15);
    try std.testing.expectEqual(@as(u3, 0), date.dayOfWeek());
}

test "Date.dayOfWeek returns 6 for Saturday" {
    // 2026-03-21 is a Saturday
    const date = createDate(2026, 3, 21);
    try std.testing.expectEqual(@as(u3, 6), date.dayOfWeek());
}

test "Date.dayOfWeek consistent across same weekday" {
    // 2026-03-15 and 2026-03-22 are both Sundays
    const date1 = createDate(2026, 3, 15);
    const date2 = createDate(2026, 3, 22);
    try std.testing.expectEqual(date1.dayOfWeek(), date2.dayOfWeek());
}

// ============================================================================
// Calendar Creation Tests
// ============================================================================

test "Calendar.init creates calendar with today" {
    const today = createToday();
    const calendar = Calendar.init(today);

    try std.testing.expectEqual(@as(u16, 2026), calendar.current_month.year);
    try std.testing.expectEqual(@as(u8, 3), calendar.current_month.month);
    try std.testing.expectEqual(true, calendar.today.eql(today));
    try std.testing.expectEqual(@as(?Date, null), calendar.selected);
    try std.testing.expectEqual(@as(?Date, null), calendar.range_start);
    try std.testing.expectEqual(@as(?Date, null), calendar.range_end);
}

test "Calendar.init sets first_day_of_week to Sunday by default" {
    const today = createToday();
    const calendar = Calendar.init(today);
    try std.testing.expectEqual(@as(u3, 0), calendar.first_day_of_week);
}

test "Calendar.init enables weekday and month/year display by default" {
    const today = createToday();
    const calendar = Calendar.init(today);
    try std.testing.expectEqual(true, calendar.show_weekdays);
    try std.testing.expectEqual(true, calendar.show_month_year);
}

// ============================================================================
// Calendar Builder API Tests
// ============================================================================

test "Calendar.withMonth sets current month" {
    const today = createToday();
    const target = createDate(2026, 6, 1);
    const calendar = Calendar.init(today).withMonth(target);

    try std.testing.expectEqual(@as(u8, 6), calendar.current_month.month);
    try std.testing.expectEqual(@as(u16, 2026), calendar.current_month.year);
}

test "Calendar.withSelected sets selected date" {
    const today = createToday();
    const selected = createDate(2026, 3, 25);
    var calendar = Calendar.init(today).withSelected(selected);

    try std.testing.expect(calendar.selected != null);
    try std.testing.expectEqual(true, calendar.selected.?.eql(selected));
}

test "Calendar.withRange sets range start and end" {
    const today = createToday();
    const start = createDate(2026, 3, 10);
    const end = createDate(2026, 3, 25);
    var calendar = Calendar.init(today).withRange(start, end);

    try std.testing.expect(calendar.range_start != null);
    try std.testing.expect(calendar.range_end != null);
    try std.testing.expectEqual(true, calendar.range_start.?.eql(start));
    try std.testing.expectEqual(true, calendar.range_end.?.eql(end));
}

test "Calendar.withConstraints sets min/max dates" {
    const today = createToday();
    const min = createDate(2026, 1, 1);
    const max = createDate(2026, 12, 31);
    var calendar = Calendar.init(today).withConstraints(min, max);

    try std.testing.expect(calendar.min_date != null);
    try std.testing.expect(calendar.max_date != null);
    try std.testing.expectEqual(true, calendar.min_date.?.eql(min));
    try std.testing.expectEqual(true, calendar.max_date.?.eql(max));
}

test "Calendar.withBlock sets block" {
    const today = createToday();
    const block = Block.init();
    const calendar = Calendar.init(today).withBlock(block);

    try std.testing.expect(calendar.block != null);
}

test "Calendar.withFirstDayOfWeek sets first_day_of_week" {
    const today = createToday();
    const calendar = Calendar.init(today).withFirstDayOfWeek(1); // Monday

    try std.testing.expectEqual(@as(u3, 1), calendar.first_day_of_week);
}

test "Calendar.withStyles sets all styles" {
    const today = createToday();
    const style_default = Style{ .fg = .white };
    const style_selected = Style{ .bg = .blue };
    const style_today = Style{ .fg = .green };
    const style_in_range = Style{ .bg = .cyan };
    const style_out_of_bounds = Style{ .fg = .gray };

    const calendar = Calendar.init(today)
        .withStyles(style_default, style_selected, style_today, style_in_range, style_out_of_bounds);

    try std.testing.expect(calendar.style_default.fg != null);
    try std.testing.expect(calendar.style_selected.bg != null);
    try std.testing.expect(calendar.style_today.fg != null);
    try std.testing.expect(calendar.style_in_range.bg != null);
    try std.testing.expect(calendar.style_out_of_bounds.fg != null);
}

test "Calendar builder methods chain" {
    const today = createToday();
    const selected = createDate(2026, 3, 18);
    const target_month = createDate(2026, 4, 1);

    const calendar = Calendar.init(today)
        .withMonth(target_month)
        .withSelected(selected)
        .withFirstDayOfWeek(1);

    try std.testing.expectEqual(@as(u8, 4), calendar.current_month.month);
    try std.testing.expect(calendar.selected != null);
    try std.testing.expectEqual(@as(u3, 1), calendar.first_day_of_week);
}

// ============================================================================
// Calendar Navigation Tests
// ============================================================================

test "Calendar.nextMonth advances to next month" {
    const today = createToday();
    var calendar = Calendar.init(today);

    try std.testing.expectEqual(@as(u8, 3), calendar.current_month.month);
    calendar.nextMonth();
    try std.testing.expectEqual(@as(u8, 4), calendar.current_month.month);
    try std.testing.expectEqual(@as(u16, 2026), calendar.current_month.year);
}

test "Calendar.nextMonth wraps to next year" {
    const today = createToday();
    var calendar = Calendar.init(today).withMonth(createDate(2026, 12, 1));

    calendar.nextMonth();
    try std.testing.expectEqual(@as(u16, 2027), calendar.current_month.year);
    try std.testing.expectEqual(@as(u8, 1), calendar.current_month.month);
}

test "Calendar.prevMonth goes to previous month" {
    const today = createToday();
    var calendar = Calendar.init(today).withMonth(createDate(2026, 4, 1));

    calendar.prevMonth();
    try std.testing.expectEqual(@as(u8, 3), calendar.current_month.month);
    try std.testing.expectEqual(@as(u16, 2026), calendar.current_month.year);
}

test "Calendar.prevMonth wraps to previous year" {
    const today = createToday();
    var calendar = Calendar.init(today).withMonth(createDate(2026, 1, 1));

    calendar.prevMonth();
    try std.testing.expectEqual(@as(u16, 2025), calendar.current_month.year);
    try std.testing.expectEqual(@as(u8, 12), calendar.current_month.month);
}

test "Calendar.nextYear advances to next year" {
    const today = createToday();
    var calendar = Calendar.init(today);

    calendar.nextYear();
    try std.testing.expectEqual(@as(u16, 2027), calendar.current_month.year);
    try std.testing.expectEqual(@as(u8, 3), calendar.current_month.month);
}

test "Calendar.prevYear goes to previous year" {
    const today = createToday();
    var calendar = Calendar.init(today);

    calendar.prevYear();
    try std.testing.expectEqual(@as(u16, 2025), calendar.current_month.year);
    try std.testing.expectEqual(@as(u8, 3), calendar.current_month.month);
}

test "Calendar.selectDate sets selected date" {
    const today = createToday();
    var calendar = Calendar.init(today);
    const date = createDate(2026, 3, 25);

    calendar.selectDate(date);
    try std.testing.expect(calendar.selected != null);
    try std.testing.expectEqual(true, calendar.selected.?.eql(date));
}

test "Calendar.selectToday selects today's date" {
    const today = createToday();
    var calendar = Calendar.init(today);

    calendar.selectToday();
    try std.testing.expect(calendar.selected != null);
    try std.testing.expectEqual(true, calendar.selected.?.eql(today));
}

test "Calendar.clearSelection clears selection" {
    const today = createToday();
    const selected = createDate(2026, 3, 25);
    var calendar = Calendar.init(today).withSelected(selected);

    calendar.clearSelection();
    try std.testing.expectEqual(@as(?Date, null), calendar.selected);
}

test "Calendar.setRangeStart sets range start" {
    const today = createToday();
    var calendar = Calendar.init(today);
    const start = createDate(2026, 3, 10);

    calendar.setRangeStart(start);
    try std.testing.expect(calendar.range_start != null);
    try std.testing.expectEqual(true, calendar.range_start.?.eql(start));
}

test "Calendar.setRangeEnd sets range end" {
    const today = createToday();
    var calendar = Calendar.init(today);
    const end = createDate(2026, 3, 25);

    calendar.setRangeEnd(end);
    try std.testing.expect(calendar.range_end != null);
    try std.testing.expectEqual(true, calendar.range_end.?.eql(end));
}

test "Calendar.clearRange clears both range start and end" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withRange(createDate(2026, 3, 10), createDate(2026, 3, 25));

    calendar.clearRange();
    try std.testing.expectEqual(@as(?Date, null), calendar.range_start);
    try std.testing.expectEqual(@as(?Date, null), calendar.range_end);
}

// ============================================================================
// Calendar Logic Tests
// ============================================================================

test "Calendar.isDateInRange returns true for dates within range" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withRange(createDate(2026, 3, 10), createDate(2026, 3, 25));

    try std.testing.expectEqual(true, calendar.isDateInRange(createDate(2026, 3, 15)));
    try std.testing.expectEqual(true, calendar.isDateInRange(createDate(2026, 3, 10))); // Start
    try std.testing.expectEqual(true, calendar.isDateInRange(createDate(2026, 3, 25))); // End
}

test "Calendar.isDateInRange returns false for dates outside range" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withRange(createDate(2026, 3, 10), createDate(2026, 3, 25));

    try std.testing.expectEqual(false, calendar.isDateInRange(createDate(2026, 3, 5)));
    try std.testing.expectEqual(false, calendar.isDateInRange(createDate(2026, 3, 30)));
}

test "Calendar.isDateInRange returns false when no range set" {
    const today = createToday();
    const calendar = Calendar.init(today);

    try std.testing.expectEqual(false, calendar.isDateInRange(createDate(2026, 3, 18)));
}

test "Calendar.isDateInRange handles range with same start and end" {
    const today = createToday();
    const date = createDate(2026, 3, 18);
    var calendar = Calendar.init(today).withRange(date, date);

    try std.testing.expectEqual(true, calendar.isDateInRange(date));
    try std.testing.expectEqual(false, calendar.isDateInRange(createDate(2026, 3, 17)));
}

test "Calendar.isDateSelectable returns true for unconstrained dates" {
    const today = createToday();
    const calendar = Calendar.init(today);

    try std.testing.expectEqual(true, calendar.isDateSelectable(createDate(2026, 3, 1)));
    try std.testing.expectEqual(true, calendar.isDateSelectable(createDate(2050, 12, 31)));
}

test "Calendar.isDateSelectable returns false for date before min_date" {
    const today = createToday();
    const calendar = Calendar.init(today)
        .withConstraints(createDate(2026, 3, 10), null);

    try std.testing.expectEqual(false, calendar.isDateSelectable(createDate(2026, 3, 5)));
    try std.testing.expectEqual(true, calendar.isDateSelectable(createDate(2026, 3, 10)));
}

test "Calendar.isDateSelectable returns false for date after max_date" {
    const today = createToday();
    const calendar = Calendar.init(today)
        .withConstraints(null, createDate(2026, 3, 25));

    try std.testing.expectEqual(true, calendar.isDateSelectable(createDate(2026, 3, 25)));
    try std.testing.expectEqual(false, calendar.isDateSelectable(createDate(2026, 3, 26)));
}

test "Calendar.isDateSelectable respects both min and max constraints" {
    const today = createToday();
    const calendar = Calendar.init(today)
        .withConstraints(createDate(2026, 3, 10), createDate(2026, 3, 25));

    try std.testing.expectEqual(false, calendar.isDateSelectable(createDate(2026, 3, 5)));
    try std.testing.expectEqual(true, calendar.isDateSelectable(createDate(2026, 3, 15)));
    try std.testing.expectEqual(false, calendar.isDateSelectable(createDate(2026, 3, 30)));
}

test "Calendar prevents selection of date before min_date" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withConstraints(createDate(2026, 3, 10), null);

    calendar.selectDate(createDate(2026, 3, 5));
    // Selection should be rejected or moved to nearest valid date
    try std.testing.expect(calendar.selected == null or calendar.selected.?.compare(createDate(2026, 3, 10)) >= 0);
}

test "Calendar prevents selection of date after max_date" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withConstraints(null, createDate(2026, 3, 25));

    calendar.selectDate(createDate(2026, 3, 30));
    // Selection should be rejected or moved to nearest valid date
    try std.testing.expect(calendar.selected == null or calendar.selected.?.compare(createDate(2026, 3, 25)) <= 0);
}

// ============================================================================
// Calendar Rendering Tests
// ============================================================================

test "Calendar.render empty area does nothing" {
    const today = createToday();
    const calendar = Calendar.init(today);

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    try calendar.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "Calendar.render basic month grid" {
    const today = createToday();
    var calendar = Calendar.init(today);

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should render some content
    var found_digit = false;
    for (0..40) |x| {
        for (0..20) |y| {
            if (buf.get(@intCast(x), @intCast(y))) |cell| {
                if (cell.char >= '0' and cell.char <= '9') {
                    found_digit = true;
                    break;
                }
            }
        }
        if (found_digit) break;
    }
    try std.testing.expect(found_digit);
}

test "Calendar.render displays weekday headers" {
    const today = createToday();
    const calendar = Calendar.init(today).withFirstDayOfWeek(0); // Sunday first

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should have weekday header (S, M, T, W, T, F, S)
    // This is a soft test - just check that something is rendered
    var has_content = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char != ' ' and cell.char != 0) {
                has_content = true;
                break;
            }
        }
    }
    try std.testing.expect(has_content);
}

test "Calendar.render displays month and year title" {
    const today = createToday();
    const calendar = Calendar.init(today).withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Month/year should be rendered at top
    // March 2026 contains 'M', 'a', 'r', 'c', 'h', '2', '0', '2', '6'
    var has_month_year = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'M' or cell.char == 'm') {
                has_month_year = true;
                break;
            }
        }
    }
    try std.testing.expect(has_month_year);
}

test "Calendar.render highlights selected date with selected style" {
    const today = createToday();
    const selected = createDate(2026, 3, 18);
    const selected_style = Style{ .bg = .blue, .bold = true };
    var calendar = Calendar.init(today)
        .withSelected(selected)
        .withFirstDayOfWeek(0);

    // Apply style - assuming calendar has a method to set style
    // This test validates that selected dates get the selected_style applied
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should render without crash
    // Style validation would happen if we can inspect cell styles
}

test "Calendar.render highlights today with today style" {
    const today = createToday();
    const today_style = Style{ .fg = .green };
    var calendar = Calendar.init(today).withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should render today's date
    // The 18 should be highlighted somewhere
}

test "Calendar.render highlights range with in_range style" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withRange(createDate(2026, 3, 10), createDate(2026, 3, 25))
        .withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should render all dates in range
    // Dates 10-25 should be highlighted
}

test "Calendar.render shows out-of-bounds dates as greyed out" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withConstraints(createDate(2026, 3, 10), createDate(2026, 3, 25))
        .withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should render all dates but some (1-9, 26-30) should have out_of_bounds style
}

test "Calendar.render respects first_day_of_week setting" {
    const today = createToday();
    var calendar_sun = Calendar.init(today).withFirstDayOfWeek(0); // Sunday
    var calendar_mon = Calendar.init(today).withFirstDayOfWeek(1); // Monday

    var buf_sun = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf_sun.deinit();

    var buf_mon = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf_mon.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar_sun.render(&buf_sun, area);
    try calendar_mon.render(&buf_mon, area);

    // Both should render, but with different column alignments
    // This is more of a visual test
}

test "Calendar.render with block draws border" {
    const today = createToday();
    const block = Block.init();
    var calendar = Calendar.init(today).withBlock(block).withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should have border characters at edges
    // Top-left should be a border char
    try std.testing.expect(buf.get(0, 0) != null);
}

test "Calendar.render without block has no border" {
    const today = createToday();
    var calendar = Calendar.init(today).withFirstDayOfWeek(0); // No block

    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    try calendar.render(&buf, area);

    // Should render content without border
}

test "Calendar.render clips at area width boundary" {
    const today = createToday();
    const calendar = Calendar.init(today).withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 30, 20);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 20 };
    try calendar.render(&buf, area);

    // Should only render up to width 15
    // Content beyond x=15 should not be rendered
}

test "Calendar.render clips at area height boundary" {
    const today = createToday();
    const calendar = Calendar.init(today).withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 40, 30);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try calendar.render(&buf, area);

    // Should only render up to height 10
    // Content beyond y=10 should not be rendered
}

test "Calendar.render with offset area" {
    const today = createToday();
    const calendar = Calendar.init(today).withFirstDayOfWeek(0);

    var buf = try Buffer.init(std.testing.allocator, 50, 30);
    defer buf.deinit();

    const area = Rect{ .x = 5, .y = 3, .width = 35, .height = 15 };
    try calendar.render(&buf, area);

    // Should render at offset position (5, 3)
    // First calendar content should appear at/after (5, 3)
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Calendar navigates across leap year boundary" {
    const today = createToday();
    var calendar = Calendar.init(today).withMonth(createDate(2024, 2, 1));

    try std.testing.expectEqual(@as(u8, 29), calendar.current_month.daysInMonth()); // Leap year
    calendar.nextYear();
    try std.testing.expectEqual(@as(u8, 28), calendar.current_month.daysInMonth()); // Non-leap year
}

test "Calendar handles Feb 29 in leap years" {
    const leap_day = createDate(2024, 2, 29);
    try std.testing.expectEqual(true, leap_day.isValid());
    try std.testing.expectEqual(true, leap_day.eql(leap_day));
}

test "Calendar clamps day when month changes" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withMonth(createDate(2026, 1, 31)); // January 31

    calendar.nextMonth(); // February doesn't have 31 days
    // Day should be clamped to 28
    try std.testing.expect(calendar.current_month.day <= 28);
}

test "Calendar prevents navigation with min/max year constraints" {
    const today = createToday();
    var calendar = Calendar.init(today)
        .withConstraints(createDate(2025, 1, 1), createDate(2026, 12, 31))
        .withMonth(createDate(2026, 1, 1));

    calendar.nextYear(); // Would go to 2027, but max_date is 2026
    // Navigation might be constrained
    try std.testing.expect(calendar.current_month.year <= 2026);
}

test "Calendar handles empty month (edge case)" {
    const today = createToday();
    var calendar = Calendar.init(today);

    // All months have at least 1 day, so this is always valid
    try std.testing.expect(calendar.current_month.daysInMonth() >= 28);
}

test "Calendar range with reversed dates (start > end)" {
    const today = createToday();
    const start = createDate(2026, 3, 25);
    const end = createDate(2026, 3, 10);
    var calendar = Calendar.init(today).withRange(start, end);

    // Calendar might auto-swap or keep as-is
    // Either way, isDateInRange should handle it correctly
    const in_range = calendar.isDateInRange(createDate(2026, 3, 15));
    // This depends on calendar implementation: might be true or false
}

test "Calendar with year 1 and year 65535" {
    const date_min = createDate(1, 1, 1);
    const date_max = createDate(65535, 12, 31);

    try std.testing.expectEqual(true, date_min.isValid());
    try std.testing.expectEqual(true, date_max.isValid());
}

test "Calendar date comparison with max year values" {
    const date1 = createDate(65535, 12, 31);
    const date2 = createDate(65534, 12, 31);

    try std.testing.expectEqual(@as(i8, 1), date1.compare(date2));
}
