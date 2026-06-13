//! NumberInput Widget — Numeric input with min/max/step constraints
//!
//! A single-row widget for numeric input with keyboard-friendly increment/decrement buttons.
//! Supports:
//! - Numeric value with min/max constraints and step increments/decrements
//! - Optional label, prefix, and suffix text
//! - Decimal place formatting (0 = integer display)
//! - Focused state for styling
//! - Block borders (optional)
//! - Builder API for configuration

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// NumberInput widget for numeric value input
pub const NumberInput = struct {
    value: f64 = 0,
    min: f64 = 0,
    max: f64 = 100,
    step: f64 = 1,
    decimal_places: u8 = 0,
    focused: bool = false,
    label: []const u8 = "",
    prefix: []const u8 = "",
    suffix: []const u8 = "",
    style: Style = .{},
    focused_style: Style = .{ .fg = .cyan },
    label_style: Style = .{ .bold = true },
    block: ?Block = null,

    /// Initialize NumberInput with default values
    pub fn init() NumberInput {
        return NumberInput{
            .value = 0,
            .min = 0,
            .max = 100,
            .step = 1,
            .decimal_places = 0,
            .focused = false,
            .label = "",
            .prefix = "",
            .suffix = "",
            .style = .{},
            .focused_style = .{ .fg = .cyan },
            .label_style = .{ .bold = true },
            .block = null,
        };
    }

    /// Increment value by step (clamped to max)
    pub fn increment(self: *NumberInput) void {
        self.value = @min(self.value + self.step, self.max);
    }

    /// Decrement value by step (clamped to min)
    pub fn decrement(self: *NumberInput) void {
        self.value = @max(self.value - self.step, self.min);
    }

    /// Set value directly (clamped to [min, max])
    pub fn setValue(self: *NumberInput, v: f64) void {
        self.value = std.math.clamp(v, self.min, self.max);
    }

    /// Check if value is at minimum
    pub fn isAtMin(self: NumberInput) bool {
        return self.value <= self.min;
    }

    /// Check if value is at maximum
    pub fn isAtMax(self: NumberInput) bool {
        return self.value >= self.max;
    }

    /// Builder: set min value
    pub fn withMin(self: NumberInput, min: f64) NumberInput {
        var result = self;
        result.min = min;
        return result;
    }

    /// Builder: set max value
    pub fn withMax(self: NumberInput, max: f64) NumberInput {
        var result = self;
        result.max = max;
        return result;
    }

    /// Builder: set step value
    pub fn withStep(self: NumberInput, step: f64) NumberInput {
        var result = self;
        result.step = step;
        return result;
    }

    /// Builder: set decimal places for display
    pub fn withDecimalPlaces(self: NumberInput, places: u8) NumberInput {
        var result = self;
        result.decimal_places = places;
        return result;
    }

    /// Builder: set value (clamped to [min, max])
    pub fn withValue(self: NumberInput, v: f64) NumberInput {
        var result = self;
        result.value = std.math.clamp(v, result.min, result.max);
        return result;
    }

    /// Builder: set label text
    pub fn withLabel(self: NumberInput, label: []const u8) NumberInput {
        var result = self;
        result.label = label;
        return result;
    }

    /// Builder: set prefix text
    pub fn withPrefix(self: NumberInput, prefix: []const u8) NumberInput {
        var result = self;
        result.prefix = prefix;
        return result;
    }

    /// Builder: set suffix text
    pub fn withSuffix(self: NumberInput, suffix: []const u8) NumberInput {
        var result = self;
        result.suffix = suffix;
        return result;
    }

    /// Builder: set style
    pub fn withStyle(self: NumberInput, style: Style) NumberInput {
        var result = self;
        result.style = style;
        return result;
    }

    /// Builder: set focused_style
    pub fn withFocusedStyle(self: NumberInput, style: Style) NumberInput {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Builder: set label_style
    pub fn withLabelStyle(self: NumberInput, style: Style) NumberInput {
        var result = self;
        result.label_style = style;
        return result;
    }

    /// Builder: set block
    pub fn withBlock(self: NumberInput, block: Block) NumberInput {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set focused state
    pub fn withFocused(self: NumberInput, focused: bool) NumberInput {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Render NumberInput to buffer
    pub fn render(self: NumberInput, buf: *Buffer, area: Rect) void {
        // Early returns for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Determine render area (apply block border if set)
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            // Apply block inner area calculation
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

        var x: u16 = inner_area.x;
        const y: u16 = inner_area.y;
        const max_x = inner_area.x + inner_area.width;

        // Render label if present
        if (self.label.len > 0) {
            if (x < max_x) {
                buf.setString(x, y, self.label, self.label_style);
                x += @intCast(self.label.len);
                if (x < max_x) {
                    x += 1; // Space after label
                }
            }
        }

        // Render decrement button [-]
        if (x < max_x) {
            const dec_style = if (self.isAtMin()) Style{ .fg = .bright_black } else self.style;
            buf.setString(x, y, "[", dec_style);
            x += 1;
            if (x < max_x) {
                buf.setString(x, y, "-", dec_style);
                x += 1;
            }
            if (x < max_x) {
                buf.setString(x, y, "]", dec_style);
                x += 1;
            }
        }

        // Space before value
        if (x < max_x) {
            x += 1;
        }

        // Format and render value with prefix/suffix
        var val_buf: [64]u8 = undefined;
        const val_str = switch (self.decimal_places) {
            0 => std.fmt.bufPrint(&val_buf, "{d:.0}", .{self.value}) catch "?",
            1 => std.fmt.bufPrint(&val_buf, "{d:.1}", .{self.value}) catch "?",
            2 => std.fmt.bufPrint(&val_buf, "{d:.2}", .{self.value}) catch "?",
            3 => std.fmt.bufPrint(&val_buf, "{d:.3}", .{self.value}) catch "?",
            else => std.fmt.bufPrint(&val_buf, "{d:.4}", .{self.value}) catch "?",
        };

        const value_style = if (self.focused) self.focused_style else self.style;

        // Render prefix
        if (x < max_x and self.prefix.len > 0) {
            buf.setString(x, y, self.prefix, value_style);
            x += @intCast(self.prefix.len);
        }

        // Render value
        if (x < max_x) {
            buf.setString(x, y, val_str, value_style);
            x += @intCast(val_str.len);
        }

        // Render suffix
        if (x < max_x and self.suffix.len > 0) {
            buf.setString(x, y, self.suffix, value_style);
            x += @intCast(self.suffix.len);
        }

        // Space before increment button
        if (x < max_x) {
            x += 1;
        }

        // Render increment button [+]
        if (x < max_x) {
            const inc_style = if (self.isAtMax()) Style{ .fg = .bright_black } else self.style;
            buf.setString(x, y, "[", inc_style);
            x += 1;
            if (x < max_x) {
                buf.setString(x, y, "+", inc_style);
                x += 1;
            }
            if (x < max_x) {
                buf.setString(x, y, "]", inc_style);
            }
        }
    }
};
