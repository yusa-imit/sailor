//! Reactive widgets that auto-bind to Signal values (v2.12.0)
//!
//! Provides TUI widgets that read from Signal values at render time,
//! automatically displaying the current value without manual refresh calls.
//!
//! Widgets:
//! - ReactiveGauge: Progress gauge bound to Signal(f64)
//! - ReactiveText: Text label bound to Signal([]const u8)
//! - ReactiveCounter: Formatted integer counter bound to Signal(i64)

const std = @import("std");
const signal_mod = @import("../../signal.zig");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const paragraph_mod = @import("paragraph.zig");
pub const Alignment = paragraph_mod.Alignment;

/// A gauge widget bound to a Signal(f64) value.
/// Reads the signal's current value at render time and draws a horizontal progress bar.
pub const ReactiveGauge = struct {
    /// The signal providing the ratio (0.0 to 1.0)
    signal: *signal_mod.Signal(f64),

    /// Optional label text to display over the gauge
    label: ?[]const u8 = null,

    /// Character used for the filled portion
    filled_char: u21 = '█',

    /// Character used for the empty portion
    empty_char: u21 = ' ',

    /// Style for the filled portion
    filled_style: Style = .{ .fg = .green },

    /// Style for the empty portion
    empty_style: Style = .{},

    /// Optional block wrapper for borders and title
    block: ?Block = null,

    /// Render the gauge into the buffer at the given area.
    /// Reads the current signal value (clamped to [0.0, 1.0]) at render time.
    pub fn render(self: ReactiveGauge, buf: *Buffer, area: Rect) void {
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        const ratio = std.math.clamp(self.signal.get(), 0.0, 1.0);
        const width = inner_area.width;
        const y = inner_area.y;
        const x_start = inner_area.x;

        const filled_width: usize = @intFromFloat(@as(f64, @floatFromInt(width)) * ratio);

        var offset: usize = 0;
        while (offset < filled_width) : (offset += 1) {
            buf.set(@intCast(@as(usize, x_start) + offset), y, Cell{
                .char = self.filled_char,
                .style = self.filled_style,
            });
        }
        while (offset < width) : (offset += 1) {
            buf.set(@intCast(@as(usize, x_start) + offset), y, Cell{
                .char = self.empty_char,
                .style = self.empty_style,
            });
        }

        if (self.label) |label| {
            if (label.len > 0 and label.len <= width) {
                const label_x: usize = @as(usize, x_start) + (width - label.len) / 2;
                for (label, 0..) |c, i| {
                    if (label_x + i >= @as(usize, x_start) + width) break;
                    buf.set(@intCast(label_x + i), y, Cell{
                        .char = c,
                        .style = .{ .bold = true },
                    });
                }
            }
        }
    }
};

/// A text label widget bound to a Signal([]const u8) value.
/// Reads the signal's current string value at render time and renders it.
pub const ReactiveText = struct {
    /// The signal providing the text content
    signal: *signal_mod.Signal([]const u8),

    /// Horizontal text alignment
    alignment: Alignment = .left,

    /// Text style
    style: Style = .{},

    /// Optional block wrapper for borders and title
    block: ?Block = null,

    /// Render the text into the buffer at the given area.
    /// Reads the current signal value at render time.
    pub fn render(self: ReactiveText, buf: *Buffer, area: Rect) void {
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        const text = self.signal.get();
        const y = inner_area.y;
        const width = inner_area.width;
        const x_start = inner_area.x;

        // Fill the entire row with spaces first
        var col: usize = 0;
        while (col < width) : (col += 1) {
            buf.set(@intCast(@as(usize, x_start) + col), y, Cell{ .char = ' ', .style = self.style });
        }

        if (text.len == 0) return;

        const text_width = @min(text.len, @as(usize, width));
        const x_offset: usize = switch (self.alignment) {
            .left, .justify => 0,
            .center => if (@as(usize, width) > text_width) (@as(usize, width) - text_width) / 2 else 0,
            .right => if (@as(usize, width) > text_width) @as(usize, width) - text_width else 0,
        };

        buf.setString(
            @intCast(@as(usize, x_start) + x_offset),
            y,
            text[0..text_width],
            self.style,
        );
    }
};

/// A formatted counter widget bound to a Signal(i64) value.
/// Renders the integer value as text, with optional prefix and suffix.
pub const ReactiveCounter = struct {
    /// The signal providing the integer value
    signal: *signal_mod.Signal(i64),

    /// Optional prefix text prepended before the value
    prefix: ?[]const u8 = null,

    /// Optional suffix text appended after the value
    suffix: ?[]const u8 = null,

    /// Text style for the entire counter
    style: Style = .{},

    /// Render the counter into the buffer at the given area.
    /// Reads the current signal value at render time.
    pub fn render(self: ReactiveCounter, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        const value = self.signal.get();
        const y = area.y;
        const x_start = area.x;
        const width = area.width;
        var col: usize = 0;

        var num_buf: [32]u8 = undefined;
        const value_str = std.fmt.bufPrint(&num_buf, "{d}", .{value}) catch return;

        const prefix = self.prefix orelse "";
        const suffix = self.suffix orelse "";

        for (prefix) |c| {
            if (col >= width) return;
            buf.set(@intCast(@as(usize, x_start) + col), y, Cell{ .char = c, .style = self.style });
            col += 1;
        }

        for (value_str) |c| {
            if (col >= width) return;
            buf.set(@intCast(@as(usize, x_start) + col), y, Cell{ .char = c, .style = self.style });
            col += 1;
        }

        for (suffix) |c| {
            if (col >= width) return;
            buf.set(@intCast(@as(usize, x_start) + col), y, Cell{ .char = c, .style = self.style });
            col += 1;
        }
    }
};

/// A list widget bound to a Signal([]const T) value.
/// Renders items from the signal's current value, calling a render function per item.
pub fn ReactiveList(comptime T: type) type {
    return struct {
        /// The signal providing the list of items
        signal: *signal_mod.Signal([]const T),

        /// Function to render each item
        render_fn: *const fn (T, *Buffer, Rect) void,

        /// Render the list into the buffer at the given area.
        /// Reads the current signal value at render time and renders each item.
        pub fn render(self: @This(), buf: *Buffer, area: Rect) void {
            if (area.width == 0 or area.height == 0) return;

            const items = self.signal.get();
            var row: u32 = 0;

            for (items) |item| {
                if (row >= area.height) break;

                const item_area = Rect{
                    .x = area.x,
                    .y = area.y + row,
                    .width = area.width,
                    .height = 1,
                };

                self.render_fn(item, buf, item_area);
                row += 1;
            }
        }
    };
}
