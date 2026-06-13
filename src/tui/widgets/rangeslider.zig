//! RangeSlider Widget — Dual-handle horizontal slider for range selection
//!
//! A single-row widget for selecting a range [low, high] with two independent handles.
//! Features:
//! - Two handles (low/high) that can be moved with constraints to prevent crossing
//! - Proportional positioning on a horizontal track
//! - Configurable range bounds (min/max), step size, and display precision
//! - Visual distinction between selected range and unselected portions
//! - Optional label and numeric value overlay
//! - Focused handle tracking for interactive state
//! - Block border support (optional)
//! - Builder API for configuration

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// Which handle is currently focused for interactive control
pub const FocusedHandle = enum { low, high, none };

/// RangeSlider widget for selecting a range [low, high]
pub const RangeSlider = struct {
    low: f64 = 0,
    high: f64 = 100,
    min: f64 = 0,
    max: f64 = 100,
    step: f64 = 1,
    decimal_places: u8 = 0,
    focused_handle: FocusedHandle = .none,
    label: []const u8 = "",
    show_values: bool = true,
    style: Style = .{},
    selected_style: Style = .{ .fg = .cyan },
    handle_style: Style = .{ .bold = true },
    focused_style: Style = .{ .fg = .cyan, .bold = true },
    label_style: Style = .{ .bold = true },
    unselected_char: u21 = '─',
    selected_char: u21 = '═',
    low_handle_char: u21 = '◄',
    high_handle_char: u21 = '►',
    block: ?Block = null,

    /// Initialize RangeSlider with default values
    pub fn init() RangeSlider {
        return RangeSlider{};
    }

    /// Decrement low value by step (clamped to min)
    pub fn moveLowLeft(self: *RangeSlider) void {
        self.low = @max(self.low - self.step, self.min);
    }

    /// Increment low value by step (clamped to high)
    pub fn moveLowRight(self: *RangeSlider) void {
        self.low = @min(self.low + self.step, self.high);
    }

    /// Decrement high value by step (clamped to low)
    pub fn moveHighLeft(self: *RangeSlider) void {
        self.high = @max(self.high - self.step, self.low);
    }

    /// Increment high value by step (clamped to max)
    pub fn moveHighRight(self: *RangeSlider) void {
        self.high = @min(self.high + self.step, self.max);
    }

    /// Set low value (clamped to [min, high])
    pub fn setLow(self: *RangeSlider, v: f64) void {
        const clamped_to_min = @max(v, self.min);
        self.low = @min(clamped_to_min, self.high);
    }

    /// Set high value (clamped to [low, max])
    pub fn setHigh(self: *RangeSlider, v: f64) void {
        const clamped_to_max = @min(v, self.max);
        self.high = @max(clamped_to_max, self.low);
    }

    /// Set both low and high (with proper clamping)
    pub fn setRange(self: *RangeSlider, lo: f64, hi: f64) void {
        const clamped_lo = std.math.clamp(lo, self.min, self.max);
        const clamped_hi = std.math.clamp(hi, clamped_lo, self.max);
        self.low = clamped_lo;
        self.high = clamped_hi;
    }

    /// Check if low value is at minimum
    pub fn isLowAtMin(self: RangeSlider) bool {
        return self.low <= self.min;
    }

    /// Check if high value is at maximum
    pub fn isHighAtMax(self: RangeSlider) bool {
        return self.high >= self.max;
    }

    /// Calculate the size of the selected range
    pub fn rangeSize(self: RangeSlider) f64 {
        return self.high - self.low;
    }

    /// Calculate proportional position of low handle (0.0 to 1.0)
    pub fn lowRatio(self: RangeSlider) f64 {
        if (self.max == self.min) return 0.0;
        return (self.low - self.min) / (self.max - self.min);
    }

    /// Calculate proportional position of high handle (0.0 to 1.0)
    pub fn highRatio(self: RangeSlider) f64 {
        if (self.max == self.min) return 1.0;
        return (self.high - self.min) / (self.max - self.min);
    }

    /// Builder: set min value
    pub fn withMin(self: RangeSlider, min: f64) RangeSlider {
        var result = self;
        result.min = min;
        return result;
    }

    /// Builder: set max value
    pub fn withMax(self: RangeSlider, max: f64) RangeSlider {
        var result = self;
        result.max = max;
        return result;
    }

    /// Builder: set step value
    pub fn withStep(self: RangeSlider, step: f64) RangeSlider {
        var result = self;
        result.step = step;
        return result;
    }

    /// Builder: set low value
    pub fn withLow(self: RangeSlider, low: f64) RangeSlider {
        var result = self;
        result.low = std.math.clamp(low, result.min, result.high);
        return result;
    }

    /// Builder: set high value
    pub fn withHigh(self: RangeSlider, high: f64) RangeSlider {
        var result = self;
        result.high = std.math.clamp(high, result.low, result.max);
        return result;
    }

    /// Builder: set decimal places for display
    pub fn withDecimalPlaces(self: RangeSlider, places: u8) RangeSlider {
        var result = self;
        result.decimal_places = places;
        return result;
    }

    /// Builder: set label text
    pub fn withLabel(self: RangeSlider, label: []const u8) RangeSlider {
        var result = self;
        result.label = label;
        return result;
    }

    /// Builder: set show_values flag
    pub fn withShowValues(self: RangeSlider, show: bool) RangeSlider {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Builder: set base style
    pub fn withStyle(self: RangeSlider, style: Style) RangeSlider {
        var result = self;
        result.style = style;
        return result;
    }

    /// Builder: set selected range style
    pub fn withSelectedStyle(self: RangeSlider, style: Style) RangeSlider {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Builder: set handle style
    pub fn withHandleStyle(self: RangeSlider, style: Style) RangeSlider {
        var result = self;
        result.handle_style = style;
        return result;
    }

    /// Builder: set focused handle style
    pub fn withFocusedStyle(self: RangeSlider, style: Style) RangeSlider {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Builder: set label style
    pub fn withLabelStyle(self: RangeSlider, style: Style) RangeSlider {
        var result = self;
        result.label_style = style;
        return result;
    }

    /// Builder: set unselected track character
    pub fn withUnselectedChar(self: RangeSlider, char: u21) RangeSlider {
        var result = self;
        result.unselected_char = char;
        return result;
    }

    /// Builder: set selected track character
    pub fn withSelectedChar(self: RangeSlider, char: u21) RangeSlider {
        var result = self;
        result.selected_char = char;
        return result;
    }

    /// Builder: set low handle character
    pub fn withLowHandleChar(self: RangeSlider, char: u21) RangeSlider {
        var result = self;
        result.low_handle_char = char;
        return result;
    }

    /// Builder: set high handle character
    pub fn withHighHandleChar(self: RangeSlider, char: u21) RangeSlider {
        var result = self;
        result.high_handle_char = char;
        return result;
    }

    /// Builder: set block border
    pub fn withBlock(self: RangeSlider, block: Block) RangeSlider {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set which handle is focused
    pub fn withFocusedHandle(self: RangeSlider, handle: FocusedHandle) RangeSlider {
        var result = self;
        result.focused_handle = handle;
        return result;
    }

    /// Format a float value as string for display
    fn formatValue(self: RangeSlider, buf: []u8, value: f64) []const u8 {
        return switch (self.decimal_places) {
            0 => std.fmt.bufPrint(buf, "{d:.0}", .{value}) catch "?",
            1 => std.fmt.bufPrint(buf, "{d:.1}", .{value}) catch "?",
            2 => std.fmt.bufPrint(buf, "{d:.2}", .{value}) catch "?",
            3 => std.fmt.bufPrint(buf, "{d:.3}", .{value}) catch "?",
            else => std.fmt.bufPrint(buf, "{d:.4}", .{value}) catch "?",
        };
    }

    /// Render RangeSlider to buffer
    pub fn render(self: RangeSlider, buf: *Buffer, area: Rect) void {
        // Early return for zero-size areas
        if (area.width == 0 or area.height == 0) return;

        // Determine render area (apply block border if set)
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            if (area.x + 1 < area.x + area.width and area.y + 1 < area.y + area.height) {
                inner_area = Rect{
                    .x = area.x + 1,
                    .y = area.y + 1,
                    .width = if (area.width > 2) area.width - 2 else 0,
                    .height = if (area.height > 2) area.height - 2 else 0,
                };
            } else {
                return; // No space for content
            }
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        var x_cursor: u16 = inner_area.x;
        const y: u16 = inner_area.y;
        const max_x: u16 = inner_area.x + inner_area.width;

        // Render label if present
        if (self.label.len > 0) {
            buf.setString(x_cursor, y, self.label, self.label_style);
            x_cursor += @intCast(self.label.len);
            if (x_cursor < max_x) {
                x_cursor += 1; // Space after label
            }
        }

        // Calculate track dimensions
        const track_x: u16 = x_cursor;
        const track_width: u16 = max_x - track_x;
        if (track_width == 0) return;

        // Calculate handle positions (0-indexed within track)
        const low_p: usize = if (track_width == 1)
            0
        else
            @intFromFloat(@floor(self.lowRatio() * @as(f64, @floatFromInt(track_width - 1))));

        var high_p: usize = if (track_width == 1)
            0
        else
            @intFromFloat(@floor(self.highRatio() * @as(f64, @floatFromInt(track_width - 1))));

        // Ensure handles don't overlap
        if (high_p <= low_p and track_width >= 2) {
            high_p = low_p + 1;
        }
        if (high_p >= track_width) {
            high_p = track_width - 1;
        }

        // Render track character by character
        var i: usize = 0;
        while (i < track_width) : (i += 1) {
            const cx: u16 = @intCast(track_x + i);
            const cell: Cell = if (i < low_p)
                Cell.init(self.unselected_char, self.style)
            else if (i == low_p)
                Cell.init(self.low_handle_char, if (self.focused_handle == .low) self.focused_style else self.handle_style)
            else if (i < high_p)
                Cell.init(self.selected_char, self.selected_style)
            else if (i == high_p)
                Cell.init(self.high_handle_char, if (self.focused_handle == .high) self.focused_style else self.handle_style)
            else
                Cell.init(self.unselected_char, self.style);

            buf.set(cx, y, cell);
        }

        // Value overlay (if show_values and there's space)
        if (self.show_values and track_width >= 4) {
            var val_buf_lo: [32]u8 = undefined;
            var val_buf_hi: [32]u8 = undefined;

            const lo_str = self.formatValue(&val_buf_lo, self.low);
            const hi_str = self.formatValue(&val_buf_hi, self.high);

            // Try to render low value
            const lo_start: usize = low_p + 1;
            if (lo_start + lo_str.len < high_p) {
                buf.setString(@intCast(track_x + lo_start), y, lo_str, self.handle_style);
            }

            // Try to render high value
            if (hi_str.len <= high_p and high_p > 0) {
                const hi_start: usize = high_p - hi_str.len;
                if (hi_start > lo_start + lo_str.len) {
                    buf.setString(@intCast(track_x + hi_start), y, hi_str, self.handle_style);
                }
            }
        }
    }
};
