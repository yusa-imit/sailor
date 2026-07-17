//! CalendarHeatmap Widget — GitHub-style contribution/activity heatmap
//!
//! The CalendarHeatmap widget displays date-indexed activity data as a grid of
//! colored cells. Rows represent days of the week, columns represent weeks.
//! Cell intensity (0-4) represents activity level, mapped to glyphs ' ','░','▒','▓','█'.
//!
//! Features:
//! - Up to 371 entries (53 weeks * 7 days, via MAX_ENTRIES)
//! - Date-indexed values via start_date and index offset
//! - Configurable first_day_of_week (0=Sunday..6=Saturday)
//! - Intensity levels 0-4 from min_val/max_val normalization
//! - Optional month labels (3-char abbreviations at month boundaries)
//! - Optional weekday labels (Mon/Wed/Fri rows, GitHub convention)
//! - Focused cell highlighting
//! - Block border support
//! - No heap allocations
//!
//! Usage:
//! ```zig
//! var vals: [50]f32 = undefined;
//! for (0..50) |i| vals[i] = @floatFromInt(i + 1);
//! const start = Date.init(2024, 1, 1);
//! const hm = CalendarHeatmap.init(start)
//!     .withValues(&vals)
//!     .withShowMonthLabels(true)
//!     .withShowWeekdayLabels(true)
//!     .withBlock(.{});
//! hm.render(&buf, area);
//! ```

const std = @import("std");
const math = std.math;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const calendar_mod = @import("calendar.zig");
const Calendar = calendar_mod.Calendar;

/// CalendarHeatmap widget for activity visualization
pub const CalendarHeatmap = struct {
    /// Maximum number of entries (53 weeks * 7 days = 371)
    pub const MAX_ENTRIES: usize = 371;

    /// Activity values indexed by days from start_date (0 = start_date, 1 = start_date+1 day, etc.)
    values: []const f32 = &.{},

    /// First day to display (used as reference for grid layout)
    start_date: Calendar.Date = Calendar.Date.init(1970, 1, 1),

    /// First day of week for row layout (0=Sunday, 1=Monday, ..., 6=Saturday)
    first_day_of_week: u3 = 0,

    /// Optional focused entry index
    focused: ?usize = null,

    /// Whether to show month labels in a row above the grid
    show_month_labels: bool = true,

    /// Whether to show weekday labels in a left gutter
    show_weekday_labels: bool = true,

    /// Minimum value for intensity normalization
    min_val: f32 = 0.0,

    /// Maximum value for intensity normalization (null = auto-detect from values)
    max_val: ?f32 = null,

    /// Style applied to intensity levels 1-4
    style: Style = .{},

    /// Style applied to level 0 cells (empty/below min_val)
    empty_style: Style = .{},

    /// Style applied to focused cell
    focused_style: Style = .{},

    /// Style applied to labels
    label_style: Style = .{},

    /// Optional block border
    block: ?Block = null,

    /// Initialize a CalendarHeatmap with a start date
    pub fn init(start_date: Calendar.Date) CalendarHeatmap {
        return .{
            .start_date = start_date,
        };
    }

    /// Number of entries to render (capped at MAX_ENTRIES)
    pub fn entryCount(self: CalendarHeatmap) usize {
        return @min(self.values.len, MAX_ENTRIES);
    }

    /// Builder: set values array
    pub fn withValues(self: CalendarHeatmap, vals: []const f32) CalendarHeatmap {
        var result = self;
        result.values = vals;
        return result;
    }

    /// Builder: set start_date
    pub fn withStartDate(self: CalendarHeatmap, date: Calendar.Date) CalendarHeatmap {
        var result = self;
        result.start_date = date;
        return result;
    }

    /// Builder: set first_day_of_week
    pub fn withFirstDayOfWeek(self: CalendarHeatmap, dow: u3) CalendarHeatmap {
        var result = self;
        result.first_day_of_week = dow;
        return result;
    }

    /// Builder: set focused index
    pub fn withFocused(self: CalendarHeatmap, idx: ?usize) CalendarHeatmap {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Builder: set show_month_labels
    pub fn withShowMonthLabels(self: CalendarHeatmap, show: bool) CalendarHeatmap {
        var result = self;
        result.show_month_labels = show;
        return result;
    }

    /// Builder: set show_weekday_labels
    pub fn withShowWeekdayLabels(self: CalendarHeatmap, show: bool) CalendarHeatmap {
        var result = self;
        result.show_weekday_labels = show;
        return result;
    }

    /// Builder: set min_val
    pub fn withMinVal(self: CalendarHeatmap, val: f32) CalendarHeatmap {
        var result = self;
        result.min_val = val;
        return result;
    }

    /// Builder: set max_val
    pub fn withMaxVal(self: CalendarHeatmap, val: ?f32) CalendarHeatmap {
        var result = self;
        result.max_val = val;
        return result;
    }

    /// Builder: set style
    pub fn withStyle(self: CalendarHeatmap, s: Style) CalendarHeatmap {
        var result = self;
        result.style = s;
        return result;
    }

    /// Builder: set empty_style
    pub fn withEmptyStyle(self: CalendarHeatmap, s: Style) CalendarHeatmap {
        var result = self;
        result.empty_style = s;
        return result;
    }

    /// Builder: set focused_style
    pub fn withFocusedStyle(self: CalendarHeatmap, s: Style) CalendarHeatmap {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Builder: set label_style
    pub fn withLabelStyle(self: CalendarHeatmap, s: Style) CalendarHeatmap {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Builder: set block
    pub fn withBlock(self: CalendarHeatmap, b: ?Block) CalendarHeatmap {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the calendar heatmap to the buffer
    pub fn render(self: CalendarHeatmap, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need valid inner area
        if (inner.width == 0 or inner.height == 0) return;

        const entry_count = self.entryCount();

        // Early exit if no entries
        if (entry_count == 0) return;

        // Calculate effective max value
        var effective_max = self.max_val;
        if (effective_max == null) {
            var max_found: f32 = self.min_val;
            for (0..entry_count) |i| {
                max_found = @max(max_found, self.values[i]);
            }
            effective_max = max_found;
        }

        // Reserve space for labels
        var content_area = inner;

        // Reserve month label row if enabled
        var month_label_row: ?u16 = null;
        if (self.show_month_labels and content_area.height > 0) {
            month_label_row = content_area.y;
            content_area.y += 1;
            if (content_area.height > 0) content_area.height -= 1;
        }

        // Reserve weekday label column if enabled
        var weekday_label_width: u16 = 0;
        if (self.show_weekday_labels) {
            weekday_label_width = 4; // space for "Mon", "Wed", "Fri" (3 chars + 1 gap)
            if (content_area.width > weekday_label_width) {
                content_area.width -= weekday_label_width;
                content_area.x += weekday_label_width;
            } else {
                weekday_label_width = 0;
            }
        }

        // No space for actual grid
        if (content_area.width == 0 or content_area.height == 0) return;

        // Calculate first weekday offset
        const dow = @as(u32, self.start_date.dayOfWeek());
        const first_dow = @as(u32, self.first_day_of_week);
        const first_weekday_offset = (@as(usize, (dow + 7 - first_dow) % 7));

        // Calculate grid dimensions
        const total_cells = first_weekday_offset + entry_count;
        const grid_cols = (total_cells + 6) / 7; // ceil division
        const grid_rows = 7; // always 7 rows (one per day of week)

        // Clamp grid to available space
        const max_cols = content_area.width;
        const actual_cols = @min(@as(u16, @intCast(grid_cols)), max_cols);
        const actual_rows = @min(@as(u16, @intCast(grid_rows)), content_area.height);

        // Calculate how many entries can actually be rendered
        const renderable_entries = @min(entry_count, @as(usize, @intCast(actual_cols * actual_rows)) -| first_weekday_offset);

        // Render weekday labels
        if (self.show_weekday_labels and weekday_label_width > 0) {
            renderWeekdayLabels(buf, inner, self);
        }

        // Render month labels
        if (self.show_month_labels and month_label_row != null) {
            renderMonthLabels(buf, month_label_row.?, content_area, entry_count, self);
        }

        // Render heatmap cells
        for (0..renderable_entries) |entry_idx| {
            const col = (first_weekday_offset + entry_idx) / 7;
            const row = (first_weekday_offset + entry_idx) % 7;

            // Check bounds
            if (col >= actual_cols or row >= actual_rows) continue;

            const cell_x = content_area.x + @as(u16, @intCast(col));
            const cell_y = content_area.y + @as(u16, @intCast(row));

            if (cell_x >= buf.width or cell_y >= buf.height) continue;

            const value = self.values[entry_idx];
            const level = calculateLevel(value, self.min_val, effective_max.?);

            // Determine glyph and style
            const glyph_chars = [_]u21{ ' ', '░', '▒', '▓', '█' };
            const glyph = glyph_chars[@min(level, 4)];

            const is_focused = self.focused != null and self.focused.? == entry_idx;
            const cell_style = if (is_focused) self.focused_style else if (level == 0) self.empty_style else self.style;

            buf.set(cell_x, cell_y, Cell.init(glyph, cell_style));
        }
    }
};

/// Calculate intensity level (0-4) for a value
fn calculateLevel(value: f32, min_val: f32, max_val: f32) u8 {
    if (value <= min_val) {
        return 0;
    }

    if (max_val <= min_val) {
        // Degenerate case: max <= min
        // Any value > min_val gets level 4
        return if (value > min_val) 4 else 0;
    }

    // Normal case: max > min
    // t = (value - min_val) / (max_val - min_val), clamped to [0, 1]
    const normalized = (value - min_val) / (max_val - min_val);
    const t = @min(@max(normalized, 0.0), 1.0);

    // level = ceil(t * 4), clamped to [1, 4]
    const level_float = @ceil(t * 4.0);
    const level_int = @as(u8, @intFromFloat(level_float));
    return @min(@max(level_int, 1), 4);
}

/// 3-letter month abbreviations (January = index 0)
fn getMonthAbbr(month: u8) []const u8 {
    return switch (month) {
        1 => "Jan",
        2 => "Feb",
        3 => "Mar",
        4 => "Apr",
        5 => "May",
        6 => "Jun",
        7 => "Jul",
        8 => "Aug",
        9 => "Sep",
        10 => "Oct",
        11 => "Nov",
        12 => "Dec",
        else => "",
    };
}

/// 3-letter weekday abbreviations (Sunday = index 0)
fn getWeekdayAbbr(dow: u3) []const u8 {
    return switch (dow) {
        0 => "Sun",
        1 => "Mon",
        2 => "Tue",
        3 => "Wed",
        4 => "Thu",
        5 => "Fri",
        6 => "Sat",
        7 => "", // unreachable for valid u3, but required for completeness
    };
}

/// Render weekday labels in the left gutter (Mon/Wed/Fri rows only)
fn renderWeekdayLabels(buf: *Buffer, area: Rect, self: CalendarHeatmap) void {
    // Weekday labels go in rows for Mon (1), Wed (3), Fri (5) relative to first_day_of_week
    // We need to map the relative row position

    // Calculate month label offset
    var label_row_y: u16 = area.y;
    if (self.show_month_labels) {
        label_row_y += 1;
    }

    // Render labels on specific rows: Monday, Wednesday, Friday (relative to first_day_of_week)
    // Monday is weekday 1, Wednesday is 3, Friday is 5 in standard 0=Sunday encoding
    const label_rows = [_]u3{ 1, 3, 5 }; // Mon, Wed, Fri in standard encoding

    for (label_rows) |weekday| {
        // Calculate relative row based on first_day_of_week
        const wd = @as(u32, weekday);
        const first_dow = @as(u32, self.first_day_of_week);
        const row_offset = @as(u16, @intCast((wd + 7 - first_dow) % 7));

        // Calculate y position in grid (accounting for month label row)
        const grid_y = if (self.show_month_labels) label_row_y + row_offset else area.y + row_offset;

        if (grid_y >= buf.height) continue;

        const abbr = getWeekdayAbbr(weekday);
        if (abbr.len >= 3) {
            // Render first 3 characters at gutter position
            for (0..3) |i| {
                const x = area.x + @as(u16, @intCast(i));
                if (x < buf.width) {
                    buf.set(x, grid_y, Cell.init(abbr[i], self.label_style));
                }
            }
        }
    }
}

/// Render month labels at the top of each month's first week column
fn renderMonthLabels(
    buf: *Buffer,
    label_row: u16,
    content_area: Rect,
    entry_count: usize,
    self: CalendarHeatmap,
) void {
    if (label_row >= buf.height) return;

    const dow = @as(u32, self.start_date.dayOfWeek());
    const first_dow = @as(u32, self.first_day_of_week);
    const first_weekday_offset = @as(usize, (dow + 7 - first_dow) % 7);

    // Track which month we've already labeled
    var last_labeled_month: u8 = 0;
    var last_labeled_year: u16 = 0;

    for (0..entry_count) |entry_idx| {
        const date = self.start_date.addDays(@intCast(entry_idx));

        // Check if this is a new month
        const is_new_month = (date.day == 1) or (entry_idx == 0 and self.start_date.day != 1);

        if (is_new_month and (date.month != last_labeled_month or date.year != last_labeled_year)) {
            // Calculate column position
            const col = (first_weekday_offset + entry_idx) / 7;

            // Calculate x position
            const label_x = content_area.x + @as(u16, @intCast(col));

            if (label_x + 3 <= buf.width) {
                const abbr = getMonthAbbr(date.month);
                for (0..3) |i| {
                    if (i < abbr.len) {
                        buf.set(label_x + @as(u16, @intCast(i)), label_row, Cell.init(abbr[i], self.label_style));
                    }
                }
            }

            last_labeled_month = date.month;
            last_labeled_year = date.year;
        }
    }
}

// ============================================================================
// Tests (placeholder for unit tests)
// ============================================================================

test "CalendarHeatmap.init with date creates heatmap" {
    const start = Calendar.Date.init(2024, 1, 15);
    const hm = CalendarHeatmap.init(start);
    try std.testing.expectEqual(@as(u16, 2024), hm.start_date.year);
}

test "CalendarHeatmap.MAX_ENTRIES equals 371" {
    try std.testing.expectEqual(@as(usize, 371), CalendarHeatmap.MAX_ENTRIES);
}

test "entryCount with 50 values returns 50" {
    var vals: [50]f32 = undefined;
    for (0..50) |i| {
        vals[i] = @as(f32, @floatFromInt(i + 1));
    }
    const start = Calendar.Date.init(2024, 1, 1);
    const hm = CalendarHeatmap.init(start).withValues(&vals);
    try std.testing.expectEqual(@as(usize, 50), hm.entryCount());
}
