//! StatusLine Widget — v2.21.0
//!
//! Renders a styled status bar with left, center, and right sections.
//! Fills the entire width of the given area and automatically handles padding.
//!
//! ## Design
//! - Zero-area safe: early return on zero width or height
//! - Three sections: left, center, right (each optional)
//! - Spans are rendered in their original style, with padding between sections
//! - Builder pattern for fluent API
//!
//! ## Usage
//! ```zig
//! const spans_left = [_]Span{Span.raw("Mode: INSERT")};
//! const spans_right = [_]Span{Span.raw("Line 5:10")};
//! const sl = StatusLine{
//!     .left = &spans_left,
//!     .right = &spans_right,
//!     .style = Style{ .fg = .white, .bg = .blue },
//! };
//! sl.render(&buffer, area);
//! ```

const std = @import("std");
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("style.zig");
const Style = style_mod.Style;
const Span = style_mod.Span;

/// Status line widget with left, center, and right sections
pub const StatusLine = struct {
    /// Left section spans (optional)
    left: []const Span = &.{},
    /// Center section spans (optional)
    center: []const Span = &.{},
    /// Right section spans (optional)
    right: []const Span = &.{},
    /// Background style for the entire status line
    style: Style = .{},

    /// Render the status line to the buffer
    pub fn render(self: StatusLine, buf: *Buffer, area: Rect) void {
        // Early return for zero-area
        if (area.width == 0 or area.height == 0) return;

        const y = area.y;

        // Calculate widths of each section
        const left_width = self.spanSliceWidth(self.left);
        const center_width = self.spanSliceWidth(self.center);
        const right_width = self.spanSliceWidth(self.right);

        // Fill the entire row with background style first
        var x: u16 = 0;
        while (x < area.width) : (x += 1) {
            buf.set(area.x + x, y, Cell{ .char = ' ', .style = self.style });
        }

        // Render left section at the left edge
        var x_pos = area.x;
        x_pos = self.renderSpanSlice(buf, self.left, x_pos, y, area.x + area.width);

        // Render right section at the right edge
        if (right_width > 0 and right_width < area.width) {
            const right_x = area.x + area.width - @as(u16, @intCast(right_width));
            _ = self.renderSpanSlice(buf, self.right, right_x, y, area.x + area.width);
        }

        // Render center section in the middle
        if (center_width > 0) {
            const available_width = if (left_width + right_width < area.width)
                area.width - @as(u16, @intCast(left_width)) - @as(u16, @intCast(right_width))
            else
                0;

            if (available_width > 0 and center_width < available_width) {
                const center_x = area.x + @as(u16, @intCast(left_width)) +
                    (available_width - @as(u16, @intCast(center_width))) / 2;
                _ = self.renderSpanSlice(buf, self.center, center_x, y, area.x + area.width);
            }
        }
    }

    /// Return a copy with left section set
    pub fn withLeft(self: StatusLine, left: []const Span) StatusLine {
        var copy = self;
        copy.left = left;
        return copy;
    }

    /// Return a copy with center section set
    pub fn withCenter(self: StatusLine, center: []const Span) StatusLine {
        var copy = self;
        copy.center = center;
        return copy;
    }

    /// Return a copy with right section set
    pub fn withRight(self: StatusLine, right: []const Span) StatusLine {
        var copy = self;
        copy.right = right;
        return copy;
    }

    /// Return a copy with style set
    pub fn withStyle(self: StatusLine, style: Style) StatusLine {
        var copy = self;
        copy.style = style;
        return copy;
    }

    /// Calculate the display width of a span slice
    fn spanSliceWidth(self: StatusLine, spans: []const Span) usize {
        _ = self;
        var width: usize = 0;
        for (spans) |span| {
            width += span.content.len;
        }
        return width;
    }

    /// Render a span slice starting at the given position
    /// Returns the next x position after rendering
    fn renderSpanSlice(self: StatusLine, buf: *Buffer, spans: []const Span, start_x: u16, y: u16, max_x: u16) u16 {
        _ = self;
        var x_pos = start_x;

        for (spans) |span| {
            for (span.content) |char| {
                if (x_pos >= max_x) break;
                buf.set(x_pos, y, Cell{ .char = char, .style = span.style });
                x_pos += 1;
            }
        }

        return x_pos;
    }
};
