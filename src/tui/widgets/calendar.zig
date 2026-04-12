const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Calendar widget - date picker with range selection and month/year navigation
pub const Calendar = struct {
    /// Date structure for calendar operations
    pub const Date = struct {
        year: u16,
        month: u8,
        day: u8,

        /// Create a new date
        pub fn init(year: u16, month: u8, day: u8) Date {
            return .{
                .year = year,
                .month = month,
                .day = day,
            };
        }

        /// Check if this date equals another date
        pub fn eql(self: Date, other: Date) bool {
            return self.year == other.year and self.month == other.month and self.day == other.day;
        }

        /// Compare two dates: -1 if self < other, 0 if equal, 1 if self > other
        pub fn compare(self: Date, other: Date) i8 {
            if (self.year != other.year) {
                return if (self.year < other.year) -1 else 1;
            }
            if (self.month != other.month) {
                return if (self.month < other.month) -1 else 1;
            }
            if (self.day != other.day) {
                return if (self.day < other.day) -1 else 1;
            }
            return 0;
        }

        /// Check if the year is a leap year
        fn isLeapYear(year: u16) bool {
            return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
        }

        /// Get the number of days in the month
        pub fn daysInMonth(self: Date) u8 {
            return switch (self.month) {
                1, 3, 5, 7, 8, 10, 12 => 31,
                4, 6, 9, 11 => 30,
                2 => if (isLeapYear(self.year)) 29 else 28,
                else => 0,
            };
        }

        /// Check if the date is valid
        pub fn isValid(self: Date) bool {
            if (self.month < 1 or self.month > 12) return false;
            if (self.day < 1 or self.day > self.daysInMonth()) return false;
            return true;
        }

        /// Get the day of week (0 = Sunday, 6 = Saturday)
        /// Uses Zeller's congruence algorithm
        pub fn dayOfWeek(self: Date) u3 {
            var m = self.month;
            var y = self.year;

            // Zeller's congruence: adjust for March = 1, February = 12 of previous year
            if (m < 3) {
                m += 12;
                y -= 1;
            }

            // Zeller formula: (d + (13*(m+1))/5 + y + y/4 - y/100 + y/400) mod 7
            const q = self.day;
            const k = y % 100;
            const j = y / 100;

            const h = (q + (13 * (m + 1)) / 5 + k + k / 4 + j / 4 - 2 * j) % 7;

            // Convert from Zeller's (0=Saturday) to our format (0=Sunday)
            // Zeller: 0=Sat, 1=Sun, 2=Mon, ..., 6=Fri
            // Mine:   0=Sun, 1=Mon, 2=Tue, ..., 6=Sat
            const day_val = @as(i8, @intCast(h)) - 1;
            return @intCast(@mod(day_val, 7));
        }

        /// Add days to this date
        pub fn addDays(self: Date, days: i32) Date {
            var result = self;
            var remaining = days;

            while (remaining > 0) {
                const days_left_in_month = result.daysInMonth() - result.day;
                if (remaining <= days_left_in_month) {
                    result.day += @intCast(remaining);
                    return result;
                }
                remaining -= (days_left_in_month + 1);
                result.day = 1;
                if (result.month == 12) {
                    result.month = 1;
                    result.year += 1;
                } else {
                    result.month += 1;
                }
            }

            while (remaining < 0) {
                if (result.day + remaining > 0) {
                    result.day = @intCast(@as(i32, result.day) + remaining);
                    return result;
                }
                remaining += result.day;
                if (result.month == 1) {
                    result.month = 12;
                    result.year -= 1;
                } else {
                    result.month -= 1;
                }
                result.day = result.daysInMonth();
            }

            return result;
        }

        /// Add months to this date, clamping day to valid range
        pub fn addMonths(self: Date, months: i32) Date {
            var result = self;
            var remaining = months;

            while (remaining > 0) {
                if (result.month + @as(u8, @intCast(remaining)) <= 12) {
                    result.month += @intCast(remaining);
                    remaining = 0;
                } else {
                    // Jump to next year's January
                    // If we're at month 10 and add 5 months:
                    // - We consume (12 - 10 + 1) = 3 months to get to next January
                    // - Remaining = 5 - 3 = 2, then add to January → month 3
                    remaining -= (12 - result.month + 1);
                    result.month = 1;
                    result.year += 1;
                }
            }

            while (remaining < 0) {
                if (@as(i32, result.month) + remaining > 0) {
                    result.month = @intCast(@as(i32, result.month) + remaining);
                    remaining = 0;
                } else {
                    // Jump to previous year's December
                    // If we're at month 3 and subtract 5 months:
                    // - We consume -3 months to get to previous December
                    // - Remaining = -5 + 3 = -2, then add to December → month 10
                    remaining += @as(i32, result.month);
                    result.month = 12;
                    result.year -= 1;
                }
            }

            // Clamp day to valid range for the new month
            const max_day = result.daysInMonth();
            if (result.day > max_day) {
                result.day = max_day;
            }

            return result;
        }
    };

    // Calendar fields
    current_month: Date,
    today: Date,
    selected: ?Date = null,
    range_start: ?Date = null,
    range_end: ?Date = null,
    min_date: ?Date = null,
    max_date: ?Date = null,
    block: ?Block = null,
    first_day_of_week: u3 = 0, // 0 = Sunday, 1 = Monday, etc.
    show_weekdays: bool = true,
    show_month_year: bool = true,
    style_default: Style = .{},
    style_selected: Style = .{},
    style_today: Style = .{},
    style_in_range: Style = .{},
    style_out_of_bounds: Style = .{},

    /// Create a calendar with today's date
    pub fn init(today: Date) Calendar {
        return .{
            .current_month = today,
            .today = today,
        };
    }

    /// Set the current month to display
    pub fn withMonth(self: Calendar, date: Date) Calendar {
        var result = self;
        result.current_month = .{
            .year = date.year,
            .month = date.month,
            .day = 1,
        };
        return result;
    }

    /// Set the selected date
    pub fn withSelected(self: Calendar, date: Date) Calendar {
        var result = self;
        result.selected = date;
        return result;
    }

    /// Set the date range (start and end)
    pub fn withRange(self: Calendar, start: Date, end: Date) Calendar {
        var result = self;
        result.range_start = start;
        result.range_end = end;
        return result;
    }

    /// Set min and max date constraints
    pub fn withConstraints(self: Calendar, min_date: ?Date, max_date: ?Date) Calendar {
        var result = self;
        result.min_date = min_date;
        result.max_date = max_date;
        return result;
    }

    /// Set the block (border) for this calendar
    pub fn withBlock(self: Calendar, new_block: Block) Calendar {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set the first day of week (0 = Sunday, 1 = Monday, etc.)
    pub fn withFirstDayOfWeek(self: Calendar, first_day: u3) Calendar {
        var result = self;
        result.first_day_of_week = first_day;
        return result;
    }

    /// Set all styles at once
    pub fn withStyles(self: Calendar, default: Style, selected: Style, today: Style, in_range: Style, out_of_bounds: Style) Calendar {
        var result = self;
        result.style_default = default;
        result.style_selected = selected;
        result.style_today = today;
        result.style_in_range = in_range;
        result.style_out_of_bounds = out_of_bounds;
        return result;
    }

    /// Move to next month
    pub fn nextMonth(self: *Calendar) void {
        // Calculate next month
        var next = self.current_month;
        if (next.month == 12) {
            next.month = 1;
            next.year += 1;
        } else {
            next.month += 1;
        }

        // Check if next month exceeds max_date constraint
        if (self.max_date) |max| {
            // Compare using first day of next month
            const next_first = Date.init(next.year, next.month, 1);
            if (next_first.compare(max) > 0) {
                return; // Don't navigate beyond max_date
            }
        }

        self.current_month = next;
        // Clamp day if necessary (e.g., Jan 31 -> Feb 28)
        const max_day = self.current_month.daysInMonth();
        if (self.current_month.day > max_day) {
            self.current_month.day = max_day;
        }
    }

    /// Move to previous month
    pub fn prevMonth(self: *Calendar) void {
        // Calculate previous month
        var prev = self.current_month;
        if (prev.month == 1) {
            prev.month = 12;
            prev.year -= 1;
        } else {
            prev.month -= 1;
        }

        // Check if previous month is before min_date constraint
        if (self.min_date) |min| {
            // Compare using last day of previous month
            const prev_last = Date.init(prev.year, prev.month, Date.init(prev.year, prev.month, 1).daysInMonth());
            if (prev_last.compare(min) < 0) {
                return; // Don't navigate before min_date
            }
        }

        self.current_month = prev;
        // Clamp day if necessary
        const max_day = self.current_month.daysInMonth();
        if (self.current_month.day > max_day) {
            self.current_month.day = max_day;
        }
    }

    /// Move to next year
    pub fn nextYear(self: *Calendar) void {
        // Check if next year exceeds max_date constraint
        if (self.max_date) |max| {
            if (self.current_month.year + 1 > max.year) {
                return; // Don't navigate beyond max_date
            }
        }

        self.current_month.year += 1;
        // Clamp day if necessary (for leap year changes)
        const max_day = self.current_month.daysInMonth();
        if (self.current_month.day > max_day) {
            self.current_month.day = max_day;
        }
    }

    /// Move to previous year
    pub fn prevYear(self: *Calendar) void {
        // Check if previous year is before min_date constraint
        if (self.min_date) |min| {
            if (self.current_month.year - 1 < min.year) {
                return; // Don't navigate before min_date
            }
        }

        self.current_month.year -= 1;
        // Clamp day if necessary
        const max_day = self.current_month.daysInMonth();
        if (self.current_month.day > max_day) {
            self.current_month.day = max_day;
        }
    }

    /// Select a date (if it's selectable)
    pub fn selectDate(self: *Calendar, date: Date) void {
        if (self.isDateSelectable(date)) {
            self.selected = date;
        }
    }

    /// Select today's date
    pub fn selectToday(self: *Calendar) void {
        self.selected = self.today;
    }

    /// Clear the selected date
    pub fn clearSelection(self: *Calendar) void {
        self.selected = null;
    }

    /// Set the range start date
    pub fn setRangeStart(self: *Calendar, date: Date) void {
        self.range_start = date;
    }

    /// Set the range end date
    pub fn setRangeEnd(self: *Calendar, date: Date) void {
        self.range_end = date;
    }

    /// Clear the date range
    pub fn clearRange(self: *Calendar) void {
        self.range_start = null;
        self.range_end = null;
    }

    /// Check if a date is within the selected range
    pub fn isDateInRange(self: Calendar, date: Date) bool {
        const start = self.range_start orelse return false;
        const end = self.range_end orelse return false;

        // Handle both forward and reverse ranges
        const min_date = if (start.compare(end) <= 0) start else end;
        const max_date = if (start.compare(end) <= 0) end else start;

        return date.compare(min_date) >= 0 and date.compare(max_date) <= 0;
    }

    /// Check if a date is selectable (within min/max constraints)
    pub fn isDateSelectable(self: Calendar, date: Date) bool {
        if (self.min_date) |min| {
            if (date.compare(min) < 0) return false;
        }
        if (self.max_date) |max| {
            if (date.compare(max) > 0) return false;
        }
        return true;
    }

    /// Render the calendar widget
    pub fn render(self: Calendar, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        var y = inner_area.y;

        // Render month/year title
        if (self.show_month_year) {
            const month_names = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
            const month_name = month_names[self.current_month.month - 1];

            var title_buf: [32]u8 = undefined;
            const title = try std.fmt.bufPrint(&title_buf, "{s} {}", .{ month_name, self.current_month.year });

            // Center the title
            const title_x = if (inner_area.width > title.len) inner_area.x + (inner_area.width - @as(u16, @intCast(title.len))) / 2 else inner_area.x;
            for (title, 0..) |ch, i| {
                if (title_x + @as(u16, @intCast(i)) >= inner_area.x + inner_area.width) break;
                buf.set(title_x + @as(u16, @intCast(i)), y, .{ .char = ch, .style = self.style_default });
            }
            y += 1;
        }

        // Render weekday header
        if (self.show_weekdays) {
            const weekday_names = [_]u8{ 'S', 'M', 'T', 'W', 'T', 'F', 'S' };
            var x = inner_area.x;

            // Render weekdays starting from first_day_of_week
            for (0..7) |i| {
                if (x >= inner_area.x + inner_area.width) break;
                const day_idx = (i + self.first_day_of_week) % 7;
                buf.set(x, y, .{ .char = weekday_names[day_idx], .style = self.style_default });
                x += 1;
                if (x < inner_area.x + inner_area.width) {
                    buf.set(x, y, .{ .char = ' ', .style = self.style_default });
                    x += 1;
                }
            }
            y += 1;
        }

        // Render calendar grid
        const first_day_of_month = Date.init(self.current_month.year, self.current_month.month, 1).dayOfWeek();
        const days_in_month = self.current_month.daysInMonth();

        // Calculate offset based on first_day_of_week setting
        // offset = number of columns to skip before the 1st of the month
        // Add 7 before subtraction to avoid underflow
        const offset = (@as(u32, first_day_of_month) + 7 - @as(u32, self.first_day_of_week)) % 7;

        // Render 6 weeks (enough for any month)
        for (0..6) |week| {
            if (y >= inner_area.y + inner_area.height) break;

            var x = inner_area.x;

            for (0..7) |day_of_week| {
                if (x >= inner_area.x + inner_area.width) break;

                // Calculate which day to display at this position
                // Position 0 would be 1 - offset if offset > 0 (showing previous month)
                // Total cells from start = week * 7 + day_of_week
                // Day to display = (1 - offset) + total_cells = total_cells + 1 - offset
                const total_cells = @as(i32, @intCast(week)) * 7 + @as(i32, @intCast(day_of_week));
                const day_to_show = total_cells + 1 - @as(i32, @intCast(offset));

                if (day_to_show >= 1 and day_to_show <= days_in_month) {
                    // Current month
                    const day = @as(u8, @intCast(day_to_show));
                    const date = Date.init(self.current_month.year, self.current_month.month, day);

                    // Determine style (priority: selected > today > in_range > out_of_bounds > default)
                    var cell_style = self.style_default;

                    if (!self.isDateSelectable(date)) {
                        cell_style = self.style_out_of_bounds;
                    }

                    if (self.isDateInRange(date)) {
                        cell_style = self.style_in_range;
                    }

                    if (date.eql(self.today)) {
                        cell_style = self.style_today;
                    }

                    if (self.selected) |sel| {
                        if (date.eql(sel)) {
                            cell_style = self.style_selected;
                        }
                    }

                    // Render day number (right-aligned in 2-char cell)
                    if (day < 10) {
                        buf.set(x, y, .{ .char = ' ', .style = cell_style });
                        x += 1;
                        buf.set(x, y, .{ .char = @as(u8, '0' + day), .style = cell_style });
                        x += 1;
                    } else {
                        const tens = day / 10;
                        const ones = day % 10;
                        buf.set(x, y, .{ .char = @as(u8, '0' + tens), .style = cell_style });
                        x += 1;
                        buf.set(x, y, .{ .char = @as(u8, '0' + ones), .style = cell_style });
                        x += 1;
                    }
                } else if (day_to_show < 1) {
                    // Previous month - just render the day number grayed out
                    const prev_month = self.current_month.addMonths(-1);
                    const days_in_prev = prev_month.daysInMonth();
                    const prev_day = days_in_prev + day_to_show;

                    if (prev_day >= 1 and prev_day <= days_in_prev) {
                        const prev_day_u8 = @as(u8, @intCast(prev_day));
                        if (prev_day_u8 < 10) {
                            buf.set(x, y, .{ .char = ' ', .style = self.style_out_of_bounds });
                            x += 1;
                            buf.set(x, y, .{ .char = @as(u8, '0' + prev_day_u8), .style = self.style_out_of_bounds });
                            x += 1;
                        } else {
                            const tens = prev_day_u8 / 10;
                            const ones = prev_day_u8 % 10;
                            buf.set(x, y, .{ .char = @as(u8, '0' + tens), .style = self.style_out_of_bounds });
                            x += 1;
                            buf.set(x, y, .{ .char = @as(u8, '0' + ones), .style = self.style_out_of_bounds });
                            x += 1;
                        }
                    } else {
                        buf.set(x, y, .{ .char = ' ', .style = self.style_default });
                        x += 1;
                        buf.set(x, y, .{ .char = ' ', .style = self.style_default });
                        x += 1;
                    }
                } else {
                    // Next month
                    _ = self.current_month.addMonths(1);
                    const next_day = @as(u8, @intCast(day_to_show - days_in_month));

                    if (next_day >= 1 and next_day <= 31) { // 31 is max days in any month
                        if (next_day < 10) {
                            buf.set(x, y, .{ .char = ' ', .style = self.style_out_of_bounds });
                            x += 1;
                            buf.set(x, y, .{ .char = @as(u8, '0' + next_day), .style = self.style_out_of_bounds });
                            x += 1;
                        } else {
                            const tens = next_day / 10;
                            const ones = next_day % 10;
                            buf.set(x, y, .{ .char = @as(u8, '0' + tens), .style = self.style_out_of_bounds });
                            x += 1;
                            buf.set(x, y, .{ .char = @as(u8, '0' + ones), .style = self.style_out_of_bounds });
                            x += 1;
                        }
                    } else {
                        buf.set(x, y, .{ .char = ' ', .style = self.style_default });
                        x += 1;
                        buf.set(x, y, .{ .char = ' ', .style = self.style_default });
                        x += 1;
                    }
                }

                // Add spacing between columns
                if (x < inner_area.x + inner_area.width) {
                    buf.set(x, y, .{ .char = ' ', .style = self.style_default });
                    x += 1;
                }
            }

            y += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test {
    std.testing.refAllDecls(@This());
}

// ============================================================================
// Tests for Date API
// ============================================================================

test "Date: init and equality" {
    const date1 = Calendar.Date.init(2024, 3, 15);
    const date2 = Calendar.Date.init(2024, 3, 15);
    const date3 = Calendar.Date.init(2024, 3, 16);

    try std.testing.expect(date1.eql(date2));
    try std.testing.expect(!date1.eql(date3));
}

test "Date: compare dates" {
    const early = Calendar.Date.init(2023, 12, 31);
    const mid = Calendar.Date.init(2024, 1, 1);
    const late = Calendar.Date.init(2024, 1, 2);

    try std.testing.expectEqual(@as(i8, -1), early.compare(mid));
    try std.testing.expectEqual(@as(i8, 0), mid.compare(mid));
    try std.testing.expectEqual(@as(i8, 1), late.compare(mid));
}

test "Date: leap year detection" {
    // Standard leap year (divisible by 4)
    try std.testing.expect(Calendar.Date.isLeapYear(2024));
    try std.testing.expect(!Calendar.Date.isLeapYear(2023));

    // Century year not divisible by 400 (not leap)
    try std.testing.expect(!Calendar.Date.isLeapYear(1900));
    try std.testing.expect(!Calendar.Date.isLeapYear(2100));

    // Century year divisible by 400 (leap)
    try std.testing.expect(Calendar.Date.isLeapYear(2000));
    try std.testing.expect(Calendar.Date.isLeapYear(2400));
}

test "Date: days in month" {
    // 31-day months
    try std.testing.expectEqual(@as(u8, 31), Calendar.Date.init(2024, 1, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 31), Calendar.Date.init(2024, 3, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 31), Calendar.Date.init(2024, 5, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 31), Calendar.Date.init(2024, 7, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 31), Calendar.Date.init(2024, 8, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 31), Calendar.Date.init(2024, 10, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 31), Calendar.Date.init(2024, 12, 1).daysInMonth());

    // 30-day months
    try std.testing.expectEqual(@as(u8, 30), Calendar.Date.init(2024, 4, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 30), Calendar.Date.init(2024, 6, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 30), Calendar.Date.init(2024, 9, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 30), Calendar.Date.init(2024, 11, 1).daysInMonth());

    // February: leap year vs non-leap year
    try std.testing.expectEqual(@as(u8, 29), Calendar.Date.init(2024, 2, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 28), Calendar.Date.init(2023, 2, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 28), Calendar.Date.init(1900, 2, 1).daysInMonth());
    try std.testing.expectEqual(@as(u8, 29), Calendar.Date.init(2000, 2, 1).daysInMonth());
}

test "Date: isValid" {
    // Valid dates
    try std.testing.expect(Calendar.Date.init(2024, 1, 31).isValid());
    try std.testing.expect(Calendar.Date.init(2024, 2, 29).isValid());
    try std.testing.expect(Calendar.Date.init(2023, 2, 28).isValid());

    // Invalid month
    try std.testing.expect(!Calendar.Date.init(2024, 0, 15).isValid());
    try std.testing.expect(!Calendar.Date.init(2024, 13, 15).isValid());

    // Invalid day
    try std.testing.expect(!Calendar.Date.init(2024, 1, 0).isValid());
    try std.testing.expect(!Calendar.Date.init(2024, 1, 32).isValid());
    try std.testing.expect(!Calendar.Date.init(2023, 2, 29).isValid()); // Not a leap year
    try std.testing.expect(!Calendar.Date.init(2024, 4, 31).isValid()); // April has 30 days
}

test "Date: dayOfWeek known dates" {
    // 2024-01-01 is Monday (1)
    try std.testing.expectEqual(@as(u3, 1), Calendar.Date.init(2024, 1, 1).dayOfWeek());

    // 2024-12-25 is Wednesday (3)
    try std.testing.expectEqual(@as(u3, 3), Calendar.Date.init(2024, 12, 25).dayOfWeek());

    // 2000-01-01 is Saturday (6)
    try std.testing.expectEqual(@as(u3, 6), Calendar.Date.init(2000, 1, 1).dayOfWeek());

    // 1900-01-01 is Monday (1)
    try std.testing.expectEqual(@as(u3, 1), Calendar.Date.init(1900, 1, 1).dayOfWeek());
}

test "Date: addDays positive" {
    // Add within same month
    const d1 = Calendar.Date.init(2024, 3, 15);
    const d2 = d1.addDays(10);
    try std.testing.expect(d2.eql(Calendar.Date.init(2024, 3, 25)));

    // Add across month boundary
    const d3 = Calendar.Date.init(2024, 3, 28);
    const d4 = d3.addDays(5);
    try std.testing.expect(d4.eql(Calendar.Date.init(2024, 4, 2)));

    // Add across year boundary
    const d5 = Calendar.Date.init(2023, 12, 30);
    const d6 = d5.addDays(5);
    try std.testing.expect(d6.eql(Calendar.Date.init(2024, 1, 4)));

    // Add large number of days
    const d7 = Calendar.Date.init(2024, 1, 1);
    const d8 = d7.addDays(366); // Leap year has 366 days
    try std.testing.expect(d8.eql(Calendar.Date.init(2025, 1, 1)));
}

test "Date: addDays negative" {
    // Subtract within same month
    const d1 = Calendar.Date.init(2024, 3, 15);
    const d2 = d1.addDays(-10);
    try std.testing.expect(d2.eql(Calendar.Date.init(2024, 3, 5)));

    // Subtract across month boundary
    const d3 = Calendar.Date.init(2024, 4, 2);
    const d4 = d3.addDays(-5);
    try std.testing.expect(d4.eql(Calendar.Date.init(2024, 3, 28)));

    // Subtract across year boundary
    const d5 = Calendar.Date.init(2024, 1, 4);
    const d6 = d5.addDays(-5);
    try std.testing.expect(d6.eql(Calendar.Date.init(2023, 12, 30)));
}

test "Date: addDays zero" {
    const d = Calendar.Date.init(2024, 6, 15);
    const result = d.addDays(0);
    try std.testing.expect(d.eql(result));
}

test "Date: addMonths positive" {
    // Add within same year
    const d1 = Calendar.Date.init(2024, 3, 15);
    const d2 = d1.addMonths(2);
    try std.testing.expect(d2.eql(Calendar.Date.init(2024, 5, 15)));

    // Add across year boundary
    const d3 = Calendar.Date.init(2023, 11, 15);
    const d4 = d3.addMonths(3);
    try std.testing.expect(d4.eql(Calendar.Date.init(2024, 2, 15)));

    // Day clamping: Jan 31 + 1 month → Feb 28/29
    const d5 = Calendar.Date.init(2024, 1, 31);
    const d6 = d5.addMonths(1);
    try std.testing.expect(d6.eql(Calendar.Date.init(2024, 2, 29))); // 2024 is leap year

    const d7 = Calendar.Date.init(2023, 1, 31);
    const d8 = d7.addMonths(1);
    try std.testing.expect(d8.eql(Calendar.Date.init(2023, 2, 28))); // 2023 is not leap year
}

test "Date: addMonths negative" {
    // Subtract within same year
    const d1 = Calendar.Date.init(2024, 5, 15);
    const d2 = d1.addMonths(-2);
    try std.testing.expect(d2.eql(Calendar.Date.init(2024, 3, 15)));

    // Subtract across year boundary
    const d3 = Calendar.Date.init(2024, 2, 15);
    const d4 = d3.addMonths(-3);
    try std.testing.expect(d4.eql(Calendar.Date.init(2023, 11, 15)));

    // Day clamping: Mar 31 - 1 month → Feb 28/29
    const d5 = Calendar.Date.init(2024, 3, 31);
    const d6 = d5.addMonths(-1);
    try std.testing.expect(d6.eql(Calendar.Date.init(2024, 2, 29))); // 2024 is leap year
}

test "Date: addMonths zero" {
    const d = Calendar.Date.init(2024, 6, 15);
    const result = d.addMonths(0);
    try std.testing.expect(d.eql(result));
}

test "Date: addMonths large values" {
    // Add 12 months = 1 year
    const d1 = Calendar.Date.init(2024, 6, 15);
    const d2 = d1.addMonths(12);
    try std.testing.expect(d2.eql(Calendar.Date.init(2025, 6, 15)));

    // Add 25 months
    const d3 = Calendar.Date.init(2023, 10, 10);
    const d4 = d3.addMonths(25);
    try std.testing.expect(d4.eql(Calendar.Date.init(2025, 11, 10)));

    // Subtract 15 months
    const d5 = Calendar.Date.init(2024, 3, 5);
    const d6 = d5.addMonths(-15);
    try std.testing.expect(d6.eql(Calendar.Date.init(2022, 12, 5)));
}

test "Calendar: init" {
    const today = Calendar.Date.init(2024, 3, 28);
    const cal = Calendar.init(today);

    try std.testing.expect(cal.current_month.eql(today));
    try std.testing.expect(cal.today.eql(today));
    try std.testing.expect(cal.selected == null);
    try std.testing.expect(cal.show_weekdays);
}

test "Calendar: selectDate" {
    const today = Calendar.Date.init(2024, 3, 28);
    var cal = Calendar.init(today);

    const target = Calendar.Date.init(2024, 3, 15);
    cal.selectDate(target);

    try std.testing.expect(cal.selected != null);
    try std.testing.expect(cal.selected.?.eql(target));
}

test "Calendar: setRange" {
    const today = Calendar.Date.init(2024, 3, 28);
    var cal = Calendar.init(today);

    const start = Calendar.Date.init(2024, 3, 10);
    const end = Calendar.Date.init(2024, 3, 20);
    cal.setRange(start, end);

    try std.testing.expect(cal.range_start != null);
    try std.testing.expect(cal.range_end != null);
    try std.testing.expect(cal.range_start.?.eql(start));
    try std.testing.expect(cal.range_end.?.eql(end));
}

test "Calendar: nextMonth and prevMonth" {
    const today = Calendar.Date.init(2024, 3, 28);
    var cal = Calendar.init(today);

    // Next month
    cal.nextMonth();
    try std.testing.expectEqual(@as(u16, 2024), cal.current_month.year);
    try std.testing.expectEqual(@as(u8, 4), cal.current_month.month);

    // Previous month (back to March)
    cal.prevMonth();
    try std.testing.expectEqual(@as(u16, 2024), cal.current_month.year);
    try std.testing.expectEqual(@as(u8, 3), cal.current_month.month);

    // Cross year boundary forward (Dec → Jan)
    cal.current_month = Calendar.Date.init(2024, 12, 15);
    cal.nextMonth();
    try std.testing.expectEqual(@as(u16, 2025), cal.current_month.year);
    try std.testing.expectEqual(@as(u8, 1), cal.current_month.month);

    // Cross year boundary backward (Jan → Dec)
    cal.current_month = Calendar.Date.init(2024, 1, 15);
    cal.prevMonth();
    try std.testing.expectEqual(@as(u16, 2023), cal.current_month.year);
    try std.testing.expectEqual(@as(u8, 12), cal.current_month.month);
}
