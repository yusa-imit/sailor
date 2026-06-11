//! Timeline Widget — Event Timeline with Status Markers
//!
//! A widget that displays a timeline of events with status markers, timestamps,
//! and direction support (vertical/horizontal). Supports scrolling, status tracking,
//! custom connectors, and flexible styling.
//!
//! ## Features
//! - Vertical/horizontal timeline directions
//! - Event status markers (pending, active, completed, failed, skipped)
//! - Customizable timestamps and descriptions
//! - Event navigation (scrolling, top/bottom)
//! - Custom connector characters
//! - Builder pattern API
//! - Optional block border support

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Block = @import("block.zig").Block;

/// Status of a timeline event
pub const TimelineStatus = enum {
    pending,   // ○ marker, default style
    active,    // ● marker, active_style
    completed, // ✓ marker, completed_style
    failed,    // ✗ marker, failed_style
    skipped,   // ⊘ marker, default style dim
};

/// Direction of timeline layout
pub const TimelineDirection = enum {
    vertical,   // events stacked top-to-bottom
    horizontal, // events left-to-right
};

/// A single event in the timeline
pub const TimelineEvent = struct {
    timestamp: []const u8,  // e.g. "2024-01-15 10:30"
    title: []const u8,
    description: []const u8 = "",
    status: TimelineStatus = .pending,
};

/// Timeline widget — displays events in chronological order
pub const Timeline = struct {
    events: []const TimelineEvent,
    scroll_offset: usize = 0,
    direction: TimelineDirection = .vertical,
    show_timestamps: bool = false,
    connector_char: u21 = '│',  // vertical: '│', horizontal: '─'
    block: ?Block = null,
    style: Style = .{},
    active_style: Style = .{ .bold = true },
    completed_style: Style = .{ .fg = .green },
    failed_style: Style = .{ .fg = .red },
    skipped_style: Style = .{ .fg = .bright_black },

    /// Initialize a new timeline with events
    pub fn init(events: []const TimelineEvent) Timeline {
        return Timeline{
            .events = events,
            .scroll_offset = 0,
            .direction = .vertical,
            .show_timestamps = false,
            .connector_char = '│',
            .block = null,
            .style = .{},
            .active_style = .{ .bold = true },
            .completed_style = .{ .fg = .green },
            .failed_style = .{ .fg = .red },
            .skipped_style = .{ .fg = .bright_black },
        };
    }

    /// Scroll down one event (clamps to last event)
    pub fn scrollDown(self: *Timeline) void {
        if (self.events.len == 0) return;
        if (self.scroll_offset < self.events.len - 1) {
            self.scroll_offset += 1;
        }
    }

    /// Scroll up one event (clamps to 0)
    pub fn scrollUp(self: *Timeline) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }

    /// Go to first event
    pub fn goToTop(self: *Timeline) void {
        self.scroll_offset = 0;
    }

    /// Go to last event
    pub fn goToBottom(self: *Timeline) void {
        if (self.events.len > 0) {
            self.scroll_offset = self.events.len - 1;
        } else {
            self.scroll_offset = 0;
        }
    }

    /// Get marker character for a status
    pub fn marker(status: TimelineStatus) u21 {
        return switch (status) {
            .pending => '○',   // U+25CB
            .active => '●',    // U+25CF
            .completed => '✓', // U+2713
            .failed => '✗',    // U+2717
            .skipped => '⊘',   // U+2298
        };
    }

    /// Builder: set direction
    pub fn withDirection(self: Timeline, dir: TimelineDirection) Timeline {
        var result = self;
        result.direction = dir;
        return result;
    }

    /// Builder: set block border
    pub fn withBlock(self: Timeline, block: Block) Timeline {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set base style
    pub fn withStyle(self: Timeline, style: Style) Timeline {
        var result = self;
        result.style = style;
        return result;
    }

    /// Builder: set active event style
    pub fn withActiveStyle(self: Timeline, style: Style) Timeline {
        var result = self;
        result.active_style = style;
        return result;
    }

    /// Builder: set completed event style
    pub fn withCompletedStyle(self: Timeline, style: Style) Timeline {
        var result = self;
        result.completed_style = style;
        return result;
    }

    /// Builder: set failed event style
    pub fn withFailedStyle(self: Timeline, style: Style) Timeline {
        var result = self;
        result.failed_style = style;
        return result;
    }

    /// Builder: set skipped event style
    pub fn withSkippedStyle(self: Timeline, style: Style) Timeline {
        var result = self;
        result.skipped_style = style;
        return result;
    }

    /// Builder: show/hide timestamps
    pub fn withShowTimestamps(self: Timeline, show: bool) Timeline {
        var result = self;
        result.show_timestamps = show;
        return result;
    }

    /// Builder: set connector character
    pub fn withConnectorChar(self: Timeline, ch: u21) Timeline {
        var result = self;
        result.connector_char = ch;
        return result;
    }

    /// Render timeline to buffer in given area
    pub fn render(self: *Timeline, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        if (self.events.len == 0) return;

        var content_area = area;
        if (self.block) |*blk| {
            blk.render(buf, area);
            if (content_area.width <= 2 or content_area.height <= 2) return;
            content_area.x += 1;
            content_area.y += 1;
            content_area.width -= 2;
            content_area.height -= 2;
        }

        switch (self.direction) {
            .vertical => self.renderVertical(buf, content_area),
            .horizontal => self.renderHorizontal(buf, content_area),
        }
    }

    fn eventStyle(self: Timeline, event: TimelineEvent) Style {
        return switch (event.status) {
            .active => self.active_style,
            .completed => self.completed_style,
            .failed => self.failed_style,
            .skipped => self.skipped_style,
            .pending => self.style,
        };
    }

    fn renderVertical(self: *Timeline, buf: *Buffer, area: Rect) void {
        const ts_col_width: u16 = if (self.show_timestamps) 18 else 0;
        // marker_col is where ○/●/✓/✗/⊘ is drawn
        const marker_col: u16 = area.x + ts_col_width;
        // title starts 2 columns after marker
        const title_col: u16 = if (marker_col + 2 < area.x + area.width) marker_col + 2 else return;

        var row: u16 = area.y;
        const max_row = area.y + area.height;
        var idx: usize = self.scroll_offset;

        while (idx < self.events.len and row < max_row) : (idx += 1) {
            const event = self.events[idx];
            const s = self.eventStyle(event);
            const m = marker(event.status);

            if (self.show_timestamps and marker_col > area.x) {
                buf.setString(area.x, row, event.timestamp, self.style);
            }

            buf.set(marker_col, row, .{ .char = m, .style = s });

            if (title_col < area.x + area.width) {
                buf.setString(title_col, row, event.title, s);
            }

            row += 1;

            // Draw connector between events (not after the last one)
            if (idx + 1 < self.events.len and row < max_row) {
                buf.set(marker_col, row, .{ .char = self.connector_char, .style = self.style });
                row += 1;
            }
        }
    }

    fn renderHorizontal(self: *Timeline, buf: *Buffer, area: Rect) void {
        if (area.height == 0) return;

        const center_y: u16 = area.y + area.height / 2;
        var col: u16 = area.x;
        const max_col = area.x + area.width;
        var idx: usize = self.scroll_offset;

        while (idx < self.events.len and col < max_col) : (idx += 1) {
            const event = self.events[idx];
            const s = self.eventStyle(event);
            const m = marker(event.status);

            buf.set(col, center_y, .{ .char = m, .style = s });

            // Draw title above/below marker
            const title_row: u16 = if (center_y + 1 < area.y + area.height) center_y + 1 else center_y;
            if (title_row < area.y + area.height) {
                buf.setString(col, title_row, event.title, s);
            }

            col += 1;

            // Draw connector
            if (idx + 1 < self.events.len and col < max_col) {
                buf.set(col, center_y, .{ .char = self.connector_char, .style = self.style });
                col += 1;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Timeline stub compiles" {
    var events = [_]TimelineEvent{
        .{ .timestamp = "T1", .title = "Event 1" },
    };
    const tl = Timeline.init(&events);
    _ = tl;
}
