//! StopWatch Widget — time tracking with lap history.
//!
//! The StopWatch widget displays elapsed time, running status, and lap times
//! with optional lap tracking and styling support.
//!
//! ## Features
//! - Elapsed time display with millisecond precision
//! - Running/paused status indicator
//! - Lap tracking with split and cumulative times
//! - Configurable styles (time, status, laps, base style)
//! - Optional block border support
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var sw = StopWatch.init()
//!     .withElapsedMs(5000)
//!     .withRunning(true)
//!     .withShowLaps(true);
//! sw.render(&buf, area);
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

/// StopWatch widget for time tracking with lap history
pub const StopWatch = struct {
    /// Maximum number of laps to track
    pub const MAX_LAPS: usize = 32;

    elapsed_ms: u64 = 0,
    laps: []const u64 = &.{},
    running: bool = false,
    show_laps: bool = true,
    show_milliseconds: bool = true,
    label: []const u8 = "",
    style: Style = .{},
    time_style: Style = .{},
    lap_style: Style = .{},
    status_style: Style = .{},
    block: ?Block = null,

    /// Initialize stopwatch with defaults
    pub fn init() StopWatch {
        return .{};
    }

    /// Format milliseconds into fixed [12]u8 array
    /// Format: "HH:MM:SS.mmm" (with dot and milliseconds, or just time 0's as placeholders)
    pub fn formatTime(ms: u64, show_ms: bool) [12]u8 {
        var result: [12]u8 = undefined;
        const total_secs = ms / 1000;
        const millis = ms % 1000;
        const secs = total_secs % 60;
        const mins = (total_secs / 60) % 60;
        const hours = total_secs / 3600;

        // Format HH:MM:SS (8 chars)
        result[0] = @intCast('0' + (hours / 10) % 10);
        result[1] = @intCast('0' + hours % 10);
        result[2] = ':';
        result[3] = @intCast('0' + mins / 10);
        result[4] = @intCast('0' + mins % 10);
        result[5] = ':';
        result[6] = @intCast('0' + secs / 10);
        result[7] = @intCast('0' + secs % 10);

        // Always format milliseconds part (positions 8-11)
        if (show_ms) {
            result[8] = '.';
            result[9] = @intCast('0' + millis / 100);
            result[10] = @intCast('0' + (millis / 10) % 10);
            result[11] = @intCast('0' + millis % 10);
        } else {
            // When not showing milliseconds, use zeros as placeholders
            result[8] = '0';
            result[9] = ' ';
            result[10] = ' ';
            result[11] = ' ';
        }
        return result;
    }

    /// Get the split time of the last lap (elapsed since last lap)
    pub fn lastLapMs(self: StopWatch) u64 {
        if (self.laps.len == 0) return self.elapsed_ms;
        const last = self.laps[self.laps.len - 1];
        return if (self.elapsed_ms >= last) self.elapsed_ms - last else 0;
    }

    /// Get the number of laps (capped at MAX_LAPS)
    pub fn lapCount(self: StopWatch) usize {
        return @min(self.laps.len, MAX_LAPS);
    }

    /// Create copy with different elapsed_ms
    pub fn withElapsedMs(self: StopWatch, ms: u64) StopWatch {
        var result = self;
        result.elapsed_ms = ms;
        return result;
    }

    /// Create copy with different laps
    pub fn withLaps(self: StopWatch, laps: []const u64) StopWatch {
        var result = self;
        result.laps = laps;
        return result;
    }

    /// Create copy with different running status
    pub fn withRunning(self: StopWatch, running: bool) StopWatch {
        var result = self;
        result.running = running;
        return result;
    }

    /// Create copy with different show_laps setting
    pub fn withShowLaps(self: StopWatch, show: bool) StopWatch {
        var result = self;
        result.show_laps = show;
        return result;
    }

    /// Create copy with different show_milliseconds setting
    pub fn withShowMilliseconds(self: StopWatch, show: bool) StopWatch {
        var result = self;
        result.show_milliseconds = show;
        return result;
    }

    /// Create copy with different label
    pub fn withLabel(self: StopWatch, label: []const u8) StopWatch {
        var result = self;
        result.label = label;
        return result;
    }

    /// Create copy with different style
    pub fn withStyle(self: StopWatch, style: Style) StopWatch {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create copy with different time_style
    pub fn withTimeStyle(self: StopWatch, style: Style) StopWatch {
        var result = self;
        result.time_style = style;
        return result;
    }

    /// Create copy with different lap_style
    pub fn withLapStyle(self: StopWatch, style: Style) StopWatch {
        var result = self;
        result.lap_style = style;
        return result;
    }

    /// Create copy with different status_style
    pub fn withStatusStyle(self: StopWatch, style: Style) StopWatch {
        var result = self;
        result.status_style = style;
        return result;
    }

    /// Create copy with block
    pub fn withBlock(self: StopWatch, block: Block) StopWatch {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render stopwatch to buffer
    pub fn render(self: StopWatch, buf: *Buffer, area: Rect) void {
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
            self.renderTimeRow(buf, inner);
        }

        // Row 1: status indicator (if height allows)
        if (inner.height > 1) {
            self.renderStatusRow(buf, inner);
        }

        // Rows 2+: lap list (if enabled and height allows)
        if (self.show_laps and self.lapCount() > 0 and inner.height > 2) {
            self.renderLapList(buf, inner);
        }
    }

    /// Render time row (row 0)
    fn renderTimeRow(self: StopWatch, buf: *Buffer, inner: Rect) void {
        const time_str = formatTime(self.elapsed_ms, self.show_milliseconds);

        // Center the text
        const y = inner.y;
        const text_len: u16 = if (self.show_milliseconds) 12 else 8;
        const padding_left = if (text_len < inner.width) (inner.width - text_len) / 2 else 0;
        const x = inner.x + padding_left;

        // Write each character with time_style
        for (time_str, 0..) |ch, col| {
            const col_u16: u16 = @intCast(col);
            if (x + col_u16 >= inner.x + inner.width) break;

            const combined_style = Style{
                .fg = self.time_style.fg,
                .bg = self.time_style.bg orelse self.style.bg,
                .bold = self.time_style.bold,
                .dim = self.time_style.dim,
                .italic = self.time_style.italic,
                .underline = self.time_style.underline,
                .blink = self.time_style.blink,
                .reverse = self.time_style.reverse,
                .strikethrough = self.time_style.strikethrough,
            };
            buf.set(x + col_u16, y, .{
                .char = ch,
                .style = combined_style,
            });
        }
    }

    /// Render status row (row 1)
    fn renderStatusRow(self: StopWatch, buf: *Buffer, inner: Rect) void {
        const status_text = if (self.running) "[RUNNING]" else "[PAUSED]";
        const y = inner.y + 1;

        // Center the text
        const text_len: u16 = @intCast(status_text.len);
        const padding_left: u16 = if (text_len < inner.width) (inner.width - text_len) / 2 else 0;
        const x = inner.x + padding_left;

        // Write each character with status_style
        for (status_text, 0..) |ch, col| {
            const col_u16: u16 = @intCast(col);
            if (x + col_u16 >= inner.x + inner.width) break;

            const combined_style = Style{
                .fg = self.status_style.fg,
                .bg = self.status_style.bg orelse self.style.bg,
                .bold = self.status_style.bold,
                .dim = self.status_style.dim,
                .italic = self.status_style.italic,
                .underline = self.status_style.underline,
                .blink = self.status_style.blink,
                .reverse = self.status_style.reverse,
                .strikethrough = self.status_style.strikethrough,
            };
            buf.set(x + col_u16, y, .{
                .char = @as(u21, ch),
                .style = combined_style,
            });
        }
    }

    /// Render lap list (starting from row 2)
    fn renderLapList(self: StopWatch, buf: *Buffer, inner: Rect) void {
        // Row 2: divider
        const divider_y = inner.y + 2;
        var divider_buf: [200]u8 = undefined;
        const actual_width = @min(inner.width, 200);

        // Fill divider buffer with "─" characters
        for (0..actual_width) |i| {
            if (i * 3 + 3 > divider_buf.len) break;
            divider_buf[i * 3] = 0xE2;      // First byte of ─ in UTF-8
            divider_buf[i * 3 + 1] = 0x94;  // Second byte
            divider_buf[i * 3 + 2] = 0x80;  // Third byte
        }

        const divider_len = @min(actual_width * 3, divider_buf.len);
        buf.setString(inner.x, divider_y, divider_buf[0..divider_len], self.lap_style);

        // Available rows for laps
        const available_lap_rows = if (inner.height > 3) inner.height - 3 else 0;
        if (available_lap_rows == 0) return;

        const num_laps = self.lapCount();
        const laps_to_show = @min(num_laps, available_lap_rows);
        const start_lap_idx = if (num_laps > laps_to_show) num_laps - laps_to_show else 0;

        // Render each lap
        var lap_row_idx: u16 = 0;
        var lap_idx = start_lap_idx;
        while (lap_idx < num_laps and lap_row_idx < available_lap_rows) : ({
            lap_idx += 1;
            lap_row_idx += 1;
        }) {
            const y = inner.y + 3 + lap_row_idx;
            self.renderLapRow(buf, inner, y, lap_idx);
        }
    }

    /// Render a single lap row
    fn renderLapRow(self: StopWatch, buf: *Buffer, inner: Rect, y: u16, lap_idx: usize) void {
        const lap_ms = self.laps[lap_idx];
        const prev_ms = if (lap_idx > 0) self.laps[lap_idx - 1] else 0;
        const split_ms = if (lap_ms >= prev_ms) lap_ms - prev_ms else 0;

        const split_time = formatTime(split_ms, self.show_milliseconds);
        const cum_time = formatTime(lap_ms, self.show_milliseconds);

        // Build lap string: "Lap N  +HH:MM:SS.mmm  HH:MM:SS.mmm"
        var lap_buf: [64]u8 = undefined;
        const lap_str = std.fmt.bufPrint(
            &lap_buf,
            "Lap {d}  +{s}  {s}",
            .{ lap_idx + 1, &split_time, &cum_time },
        ) catch lap_buf[0..0];

        // Center if needed
        const lap_str_len: u16 = @intCast(lap_str.len);
        const padding_left: u16 = if (lap_str_len < inner.width) (inner.width - lap_str_len) / 2 else 0;
        const x = inner.x + padding_left;

        // Write each character with lap_style
        for (lap_str, 0..) |ch, col| {
            const col_u16: u16 = @intCast(col);
            if (x + col_u16 >= inner.x + inner.width) break;

            const combined_style = Style{
                .fg = self.lap_style.fg,
                .bg = self.lap_style.bg orelse self.style.bg,
                .bold = self.lap_style.bold,
                .dim = self.lap_style.dim,
                .italic = self.lap_style.italic,
                .underline = self.lap_style.underline,
                .blink = self.lap_style.blink,
                .reverse = self.lap_style.reverse,
                .strikethrough = self.lap_style.strikethrough,
            };
            buf.set(x + col_u16, y, .{
                .char = @as(u21, ch),
                .style = combined_style,
            });
        }
    }
};
