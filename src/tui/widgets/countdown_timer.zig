//! CountdownTimer widget — visual countdown display with progress tracking.
//!
//! The CountdownTimer widget displays a countdown timer with optional progress bar.
//! Tracks remaining seconds, formats time in multiple formats, and provides visual feedback.
//!
//! ## Features
//! - Time formatting in seconds, MM:SS, and HH:MM:SS formats
//! - Progress calculation and visualization
//! - Optional progress bar display
//! - Optional total time display
//! - Configurable characters and styles
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var timer = CountdownTimer.init(300);
//! timer.tick();
//! const prog = timer.progress();
//! // Render timer.render(&buf, area)
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// CountdownTimer widget for visual countdown display
pub const CountdownTimer = struct {
    /// Time format for display
    pub const TimeFormat = enum {
        seconds,  // Just seconds (e.g., "90")
        mm_ss,    // Minutes:Seconds (e.g., "01:30")
        hh_mm_ss, // Hours:Minutes:Seconds (e.g., "01:30:45")
    };
    total_seconds: u64,
    remaining_seconds: u64,
    show_progress_bar: bool = true,
    show_total: bool = true,
    format: TimeFormat = .mm_ss,
    bar_char: u21 = '█',
    empty_char: u21 = '░',
    time_style: Style = .{},
    bar_filled_style: Style = .{},
    bar_empty_style: Style = .{},
    block: ?Block = null,

    /// Initialize countdown timer with total seconds
    pub fn init(total: u64) CountdownTimer {
        return .{
            .total_seconds = total,
            .remaining_seconds = total,
        };
    }

    /// Decrement remaining by 1 second (saturating at 0)
    pub fn tick(self: *CountdownTimer) void {
        if (self.remaining_seconds > 0) {
            self.remaining_seconds -= 1;
        }
    }

    /// Decrement remaining by n seconds (saturating at 0)
    pub fn tickBy(self: *CountdownTimer, n: u64) void {
        if (n >= self.remaining_seconds) {
            self.remaining_seconds = 0;
        } else {
            self.remaining_seconds -= n;
        }
    }

    /// Reset remaining to total
    pub fn reset(self: *CountdownTimer) void {
        self.remaining_seconds = self.total_seconds;
    }

    /// Set remaining seconds (clamped to [0, total_seconds])
    pub fn setRemaining(self: *CountdownTimer, value: u64) void {
        self.remaining_seconds = @min(value, self.total_seconds);
    }

    /// Check if timer is expired (remaining == 0)
    pub fn isExpired(self: CountdownTimer) bool {
        return self.remaining_seconds == 0;
    }

    /// Get progress as f32 in range [0.0, 1.0]
    /// Returns 1.0 if total_seconds == 0
    pub fn progress(self: CountdownTimer) f32 {
        if (self.total_seconds == 0) return 1.0;
        return @as(f32, @floatFromInt(self.remaining_seconds)) / @as(f32, @floatFromInt(self.total_seconds));
    }

    /// Format time into buffer and return slice
    /// Caller must provide buffer of at least 9 bytes
    pub fn formatTime(seconds: u64, format: TimeFormat, buf: *[9]u8) []u8 {
        return switch (format) {
            .seconds => formatSeconds(seconds, buf),
            .mm_ss => formatMmSs(seconds, buf),
            .hh_mm_ss => formatHhMmSs(seconds, buf),
        };
    }

    /// Format as MM:SS
    fn formatMmSs(seconds: u64, buf: *[9]u8) []u8 {
        const mins = seconds / 60;
        const secs = seconds % 60;
        const len = std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}", .{ mins, secs }) catch {
            @panic("formatMmSs buffer write failed");
        };
        return len;
    }

    /// Format as HH:MM:SS
    fn formatHhMmSs(seconds: u64, buf: *[9]u8) []u8 {
        const hours = seconds / 3600;
        const remaining = seconds % 3600;
        const mins = remaining / 60;
        const secs = remaining % 60;
        const len = std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, mins, secs }) catch {
            @panic("formatHhMmSs buffer write failed");
        };
        return len;
    }

    /// Format as plain seconds
    fn formatSeconds(seconds: u64, buf: *[9]u8) []u8 {
        const len = std.fmt.bufPrint(buf, "{d}", .{seconds}) catch {
            @panic("formatSeconds buffer write failed");
        };
        return len;
    }

    /// Get content height (1 if no progress bar, 2 if progress bar shown)
    pub fn contentHeight(self: CountdownTimer) u8 {
        return if (self.show_progress_bar) 2 else 1;
    }

    /// Create copy with different total_seconds
    pub fn withTotalSeconds(self: CountdownTimer, total: u64) CountdownTimer {
        var result = self;
        result.total_seconds = total;
        return result;
    }

    /// Create copy with different show_progress_bar setting
    pub fn withShowProgressBar(self: CountdownTimer, show: bool) CountdownTimer {
        var result = self;
        result.show_progress_bar = show;
        return result;
    }

    /// Create copy with different show_total setting
    pub fn withShowTotal(self: CountdownTimer, show: bool) CountdownTimer {
        var result = self;
        result.show_total = show;
        return result;
    }

    /// Create copy with different format
    pub fn withFormat(self: CountdownTimer, format: TimeFormat) CountdownTimer {
        var result = self;
        result.format = format;
        return result;
    }

    /// Create copy with different bar_char
    pub fn withBarChar(self: CountdownTimer, char: u21) CountdownTimer {
        var result = self;
        result.bar_char = char;
        return result;
    }

    /// Create copy with different empty_char
    pub fn withEmptyChar(self: CountdownTimer, char: u21) CountdownTimer {
        var result = self;
        result.empty_char = char;
        return result;
    }

    /// Create copy with different time_style
    pub fn withTimeStyle(self: CountdownTimer, style: Style) CountdownTimer {
        var result = self;
        result.time_style = style;
        return result;
    }

    /// Create copy with different bar_filled_style
    pub fn withBarFilledStyle(self: CountdownTimer, style: Style) CountdownTimer {
        var result = self;
        result.bar_filled_style = style;
        return result;
    }

    /// Create copy with different bar_empty_style
    pub fn withBarEmptyStyle(self: CountdownTimer, style: Style) CountdownTimer {
        var result = self;
        result.bar_empty_style = style;
        return result;
    }

    /// Create copy with block
    pub fn withBlock(self: CountdownTimer, block: Block) CountdownTimer {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render countdown timer to buffer
    pub fn render(self: CountdownTimer, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            inner = block.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        // Row 0: time display
        if (inner.height > 0) {
            self.renderTimeRow(buf, inner, 0);
        }

        // Row 1: progress bar (if enabled and height allows)
        if (self.show_progress_bar and inner.height > 1) {
            self.renderProgressBar(buf, inner, 1);
        }
    }

    /// Render time row
    fn renderTimeRow(self: CountdownTimer, buf: *Buffer, inner: Rect, row_offset: u16) void {
        var time_buf: [9]u8 = undefined;
        const time_str = formatTime(self.remaining_seconds, self.format, &time_buf);

        // Build display string
        var display_buf: [64]u8 = undefined;
        const display_str = if (self.show_total) blk: {
            var total_buf: [9]u8 = undefined;
            const total_str = formatTime(self.total_seconds, self.format, &total_buf);
            const len = std.fmt.bufPrint(&display_buf, "{s} / {s}", .{ time_str, total_str }) catch {
                break :blk time_str;
            };
            break :blk len;
        } else time_str;

        // Center the text
        const y = inner.y + row_offset;
        const text_width: usize = display_str.len;
        if (text_width <= inner.width) {
            const padding_left = (inner.width - text_width) / 2;
            const x = inner.x + @as(u16, @intCast(padding_left));
            buf.setString(x, y, display_str, self.time_style);
        }
    }

    /// Render progress bar row
    fn renderProgressBar(self: CountdownTimer, buf: *Buffer, inner: Rect, row_offset: u16) void {
        const y = inner.y + row_offset;
        const prog = self.progress();
        const filled_cells: usize = @as(usize, @intFromFloat(@as(f32, @floatFromInt(inner.width)) * prog));
        const empty_cells: usize = inner.width -| filled_cells;

        var x = inner.x;

        // Render filled cells
        var i: usize = 0;
        while (i < filled_cells and x < inner.x + inner.width) : (i += 1) {
            buf.set(x, y, .{
                .char = self.bar_char,
                .style = self.bar_filled_style,
            });
            x += 1;
        }

        // Render empty cells
        i = 0;
        while (i < empty_cells and x < inner.x + inner.width) : (i += 1) {
            buf.set(x, y, .{
                .char = self.empty_char,
                .style = self.bar_empty_style,
            });
            x += 1;
        }
    }
};
