//! Scrollbar Widget — v2.19.0
//!
//! Visual scrollbar indicator for vertical/horizontal layouts.
//! Calculates thumb position and size based on total items, viewport, and current position.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;

/// Scrollbar orientation
pub const Orientation = enum {
    vertical,
    horizontal,
};

/// Scrollbar widget for indicating scroll position
pub const Scrollbar = struct {
    total: usize = 0,
    position: usize = 0,
    viewport: usize = 0,
    orientation: Orientation = .vertical,
    track_style: Style = .{ .fg = .bright_black },
    thumb_style: Style = .{ .bold = true },

    /// Set the current scroll position
    pub fn setPosition(self: *Scrollbar, pos: usize) void {
        // Clamp position to valid range: [0, total]
        self.position = @min(pos, self.total);
    }

    /// Set the total number of items
    pub fn setTotal(self: *Scrollbar, total: usize) void {
        self.total = total;
        // Clamp position if it exceeds new total
        self.position = @min(self.position, total);
    }

    /// Set the viewport size (number of visible items)
    pub fn setViewport(self: *Scrollbar, viewport: usize) void {
        self.viewport = viewport;
    }

    /// Calculate thumb size based on track length
    pub fn thumbSize(self: Scrollbar, track_len: usize) usize {
        if (self.total == 0) return 0;
        if (self.viewport >= self.total) return track_len;

        // Proportional calculation: (viewport / total) * track_len
        const thumb = @max(1, (self.viewport * track_len) / self.total);
        return @min(thumb, track_len);
    }

    /// Calculate thumb offset position on track
    pub fn thumbOffset(self: Scrollbar, track_len: usize) usize {
        // If viewport >= total, content fits entirely, no scrolling possible
        if (self.total <= self.viewport) return 0;

        const thumb_sz = self.thumbSize(track_len);
        const track_available = @max(0, track_len - thumb_sz);
        const scrollable = self.total - self.viewport;

        // Proportional calculation: (position / scrollable) * track_available
        const offset = (self.position * track_available) / scrollable;
        return @min(offset, track_available);
    }

    /// Return a copy with modified orientation
    pub fn withOrientation(self: Scrollbar, orientation: Orientation) Scrollbar {
        var copy = self;
        copy.orientation = orientation;
        return copy;
    }

    /// Render the scrollbar to the buffer
    pub fn render(self: Scrollbar, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        switch (self.orientation) {
            .vertical => self.renderVertical(buf, area),
            .horizontal => self.renderHorizontal(buf, area),
        }
    }

    fn renderVertical(self: Scrollbar, buf: *Buffer, area: Rect) void {
        if (area.height == 0) return;

        const track_len = area.height;
        const thumb_sz = self.thumbSize(track_len);
        const offset = self.thumbOffset(track_len);

        var row: u16 = area.y;
        while (row < area.y + area.height and row < buf.height) : (row += 1) {
            const row_in_track = row - area.y;

            // Determine if this row is part of the thumb or track
            const is_thumb = self.total > 0 and
                row_in_track >= offset and
                row_in_track < offset + thumb_sz;

            const style = if (is_thumb) self.thumb_style else self.track_style;
            const char: u21 = if (is_thumb) '█' else '│';

            buf.set(area.x, row, Cell{ .char = char, .style = style });
        }
    }

    fn renderHorizontal(self: Scrollbar, buf: *Buffer, area: Rect) void {
        if (area.width == 0) return;

        const track_len = area.width;
        const thumb_sz = self.thumbSize(track_len);
        const offset = self.thumbOffset(track_len);

        var col: u16 = area.x;
        while (col < area.x + area.width and col < buf.width) : (col += 1) {
            const col_in_track = col - area.x;

            // Determine if this column is part of the thumb or track
            const is_thumb = self.total > 0 and
                col_in_track >= offset and
                col_in_track < offset + thumb_sz;

            const style = if (is_thumb) self.thumb_style else self.track_style;
            const char: u21 = if (is_thumb) '█' else '─';

            buf.set(col, area.y, Cell{ .char = char, .style = style });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Scrollbar can be instantiated" {
    const sb = Scrollbar{};
    _ = sb;
}

test "Scrollbar default state" {
    const sb = Scrollbar{};
    try std.testing.expectEqual(@as(usize, 0), sb.total);
    try std.testing.expectEqual(@as(usize, 0), sb.position);
    try std.testing.expectEqual(@as(usize, 0), sb.viewport);
    try std.testing.expectEqual(Orientation.vertical, sb.orientation);
}

test "thumbSize with zero total returns 0" {
    var sb = Scrollbar{ .total = 0, .viewport = 10 };
    try std.testing.expectEqual(@as(usize, 0), sb.thumbSize(100));
}

test "thumbSize minimum 1 when total > 0" {
    var sb = Scrollbar{ .total = 100, .viewport = 10 };
    const size = sb.thumbSize(100);
    try std.testing.expect(size >= 1);
}

test "thumbOffset returns 0 when position is 0" {
    var sb = Scrollbar{ .total = 100, .viewport = 10, .position = 0 };
    try std.testing.expectEqual(@as(usize, 0), sb.thumbOffset(100));
}

test "thumbOffset returns 0 when viewport >= total" {
    var sb = Scrollbar{ .total = 100, .viewport = 100, .position = 50 };
    try std.testing.expectEqual(@as(usize, 0), sb.thumbOffset(100));
}

test "setPosition clamps to total" {
    var sb = Scrollbar{ .total = 100 };
    sb.setPosition(150);
    try std.testing.expect(sb.position <= sb.total);
}

test "setTotal clamps position" {
    var sb = Scrollbar{ .total = 100, .position = 80 };
    sb.setTotal(50);
    try std.testing.expect(sb.position <= 50);
}

test "withOrientation preserves other fields" {
    const sb = Scrollbar{ .total = 100, .position = 50, .viewport = 10 };
    const updated = sb.withOrientation(.horizontal);
    try std.testing.expectEqual(Orientation.horizontal, updated.orientation);
    try std.testing.expectEqual(@as(usize, 100), updated.total);
    try std.testing.expectEqual(@as(usize, 50), updated.position);
}
