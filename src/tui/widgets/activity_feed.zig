//! ActivityFeed Widget — activity stream with timestamps, actors, and kind-based styling
//!
//! The ActivityFeed widget displays a scrollable list of activities, each with
//! optional timestamp, actor, and event description. Activities are color-coded
//! by kind (info, success, warning, error, action) with dedicated styles.
//!
//! ## Features
//! - Activity list rendering with icon indicators
//! - Kind-based icon display (·, ●, ⚠, ✗, →)
//! - Timestamp and actor field visibility toggles
//! - Focused item highlighting
//! - Automatic scrolling to keep focused item visible
//! - Block border support
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var activities = [_]Activity{
//!     .{ .timestamp = "10:00", .actor = "alice", .event = "logged in", .kind = .info }
//! };
//! var feed = ActivityFeed.init()
//!     .withItems(&activities)
//!     .withFocused(0);
//! feed.render(&buf, area);
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

/// Activity kind enumeration with visual indicators
pub const Kind = enum {
    info,
    success,
    warning,
    error_kind,
    action,
};

/// A single activity entry
pub const Activity = struct {
    timestamp: []const u8 = "",
    actor: []const u8 = "",
    event: []const u8 = "",
    kind: Kind = .info,
};

/// ActivityFeed widget for displaying activity streams
pub const ActivityFeed = struct {
    /// Maximum number of items to display
    pub const MAX_ITEMS: usize = 64;

    /// Array of activities to display
    items: []const Activity = &.{},

    /// Index of the focused activity
    focused: usize = 0,

    /// Whether to show timestamp field
    show_timestamp: bool = true,

    /// Whether to show actor field
    show_actor: bool = true,

    /// Base style for the entire widget
    style: Style = .{},

    /// Style for timestamp text
    timestamp_style: Style = .{},

    /// Style for actor text
    actor_style: Style = .{},

    /// Style for focused row background
    focused_style: Style = .{},

    /// Style for info kind icon
    info_style: Style = .{},

    /// Style for success kind icon
    success_style: Style = .{},

    /// Style for warning kind icon
    warning_style: Style = .{},

    /// Style for error kind icon
    error_style: Style = .{},

    /// Style for action kind icon
    action_style: Style = .{},

    /// Optional border block
    block: ?Block = null,

    /// Initialize a new ActivityFeed with defaults
    pub fn init() ActivityFeed {
        return .{};
    }

    /// Create a copy with different items
    pub fn withItems(self: ActivityFeed, items: []const Activity) ActivityFeed {
        var result = self;
        result.items = items;
        return result;
    }

    /// Create a copy with different focused index
    pub fn withFocused(self: ActivityFeed, focused: usize) ActivityFeed {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Create a copy with timestamp visibility toggled
    pub fn withShowTimestamp(self: ActivityFeed, show: bool) ActivityFeed {
        var result = self;
        result.show_timestamp = show;
        return result;
    }

    /// Create a copy with actor visibility toggled
    pub fn withShowActor(self: ActivityFeed, show: bool) ActivityFeed {
        var result = self;
        result.show_actor = show;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different timestamp style
    pub fn withTimestampStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.timestamp_style = style;
        return result;
    }

    /// Create a copy with different actor style
    pub fn withActorStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.actor_style = style;
        return result;
    }

    /// Create a copy with different focused style
    pub fn withFocusedStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Create a copy with different info style
    pub fn withInfoStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.info_style = style;
        return result;
    }

    /// Create a copy with different success style
    pub fn withSuccessStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.success_style = style;
        return result;
    }

    /// Create a copy with different warning style
    pub fn withWarningStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.warning_style = style;
        return result;
    }

    /// Create a copy with different error style
    pub fn withErrorStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.error_style = style;
        return result;
    }

    /// Create a copy with different action style
    pub fn withActionStyle(self: ActivityFeed, style: Style) ActivityFeed {
        var result = self;
        result.action_style = style;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: ActivityFeed, block: Block) ActivityFeed {
        var result = self;
        result.block = block;
        return result;
    }

    /// Get the number of items (clamped to MAX_ITEMS)
    pub fn itemCount(self: ActivityFeed) usize {
        return @min(self.items.len, MAX_ITEMS);
    }

    /// Get the icon character for a kind
    fn iconForKind(kind: Kind) u21 {
        return switch (kind) {
            .info => '·',        // U+00B7
            .success => '●',     // U+25CF
            .warning => '⚠',     // U+26A0
            .error_kind => '✗',  // U+2717
            .action => '→',      // U+2192
        };
    }

    /// Get the style for an icon based on kind
    fn styleForKind(self: ActivityFeed, kind: Kind) Style {
        return switch (kind) {
            .info => self.info_style,
            .success => self.success_style,
            .warning => self.warning_style,
            .error_kind => self.error_style,
            .action => self.action_style,
        };
    }

    /// Render the activity feed to the buffer
    pub fn render(self: ActivityFeed, buf: *Buffer, area: Rect) void {
        // Early exit for zero-area
        if (area.width == 0 or area.height == 0) {
            return;
        }

        // Determine the render area (handle block border if present)
        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        // Early exit if inner area is zero
        if (inner.width == 0 or inner.height == 0) {
            return;
        }

        // Early exit if no items
        const count = self.itemCount();
        if (count == 0) {
            return;
        }

        // Calculate scroll offset to keep focused visible
        var scroll_offset: usize = 0;
        if (self.focused < count) {
            if (self.focused < scroll_offset) {
                scroll_offset = self.focused;
            } else if (self.focused >= scroll_offset + inner.height) {
                scroll_offset = @min(self.focused - inner.height + 1, count - 1);
            }
        } else if (count > 0) {
            scroll_offset = count - 1;
        }

        // Render visible items
        var row: u16 = 0;
        while (row < inner.height and scroll_offset + row < count) : (row += 1) {
            const item_idx = scroll_offset + row;
            const item = self.items[item_idx];
            const y = inner.y + row;

            const is_focused = (item_idx == self.focused);

            // If focused, fill row with focused style background
            if (is_focused) {
                var col: u16 = 0;
                while (col < inner.width) : (col += 1) {
                    buf.set(inner.x + col, y, buffer_mod.Cell.init(' ', self.focused_style));
                }
            }

            // Track column position
            var col: u16 = 0;

            // Render icon
            if (col < inner.width) {
                const icon = iconForKind(item.kind);
                const icon_style = self.styleForKind(item.kind);
                buf.set(inner.x + col, y, buffer_mod.Cell.init(icon, icon_style));
                col += 1;
            }

            // Space after icon
            if (col < inner.width) {
                const space_style = if (is_focused) self.focused_style else self.style;
                buf.set(inner.x + col, y, buffer_mod.Cell.init(' ', space_style));
                col += 1;
            }

            // Render timestamp if enabled and not empty
            if (self.show_timestamp and item.timestamp.len > 0 and col < inner.width) {
                const remaining = inner.width - col;
                const to_write = @min(item.timestamp.len, remaining);
                const timestamp = item.timestamp[0..to_write];
                const ts_style = if (is_focused) self.focused_style else self.timestamp_style;
                buf.setString(inner.x + col, y, timestamp, ts_style);
                col += @as(u16, @intCast(to_write));
            }

            // Space after timestamp (if timestamp was shown)
            if (self.show_timestamp and item.timestamp.len > 0 and col < inner.width) {
                const space_style = if (is_focused) self.focused_style else self.style;
                buf.set(inner.x + col, y, buffer_mod.Cell.init(' ', space_style));
                col += 1;
            }

            // Render actor if enabled and not empty
            if (self.show_actor and item.actor.len > 0 and col < inner.width) {
                const remaining = inner.width - col;
                const to_write = @min(item.actor.len, remaining);
                const actor = item.actor[0..to_write];
                const actor_s = if (is_focused) self.focused_style else self.actor_style;
                buf.setString(inner.x + col, y, actor, actor_s);
                col += @as(u16, @intCast(to_write));
            }

            // Space after actor (if actor was shown)
            if (self.show_actor and item.actor.len > 0 and col < inner.width) {
                const space_style = if (is_focused) self.focused_style else self.style;
                buf.set(inner.x + col, y, buffer_mod.Cell.init(' ', space_style));
                col += 1;
            }

            // Render event text for remaining width
            if (item.event.len > 0 and col < inner.width) {
                const remaining = inner.width - col;
                const to_write = @min(item.event.len, remaining);
                const event = item.event[0..to_write];
                const event_style = if (is_focused) self.focused_style else self.style;
                buf.setString(inner.x + col, y, event, event_style);
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ActivityFeed.init has empty items" {
    const af = ActivityFeed.init();
    try testing.expectEqual(@as(usize, 0), af.items.len);
}

test "ActivityFeed.init has focused == 0" {
    const af = ActivityFeed.init();
    try testing.expectEqual(@as(usize, 0), af.focused);
}

test "ActivityFeed.init has show_timestamp == true" {
    const af = ActivityFeed.init();
    try testing.expect(af.show_timestamp == true);
}

test "ActivityFeed.init has show_actor == true" {
    const af = ActivityFeed.init();
    try testing.expect(af.show_actor == true);
}

test "ActivityFeed.init has null block" {
    const af = ActivityFeed.init();
    try testing.expect(af.block == null);
}

test "Kind.info exists" {
    const k: Kind = .info;
    try testing.expect(k == .info);
}

test "Kind.success exists" {
    const k: Kind = .success;
    try testing.expect(k == .success);
}

test "Kind.warning exists" {
    const k: Kind = .warning;
    try testing.expect(k == .warning);
}

test "Kind.error_kind exists" {
    const k: Kind = .error_kind;
    try testing.expect(k == .error_kind);
}

test "Kind.action exists" {
    const k: Kind = .action;
    try testing.expect(k == .action);
}

test "itemCount returns 0 for empty items" {
    const af = ActivityFeed.init();
    try testing.expectEqual(@as(usize, 0), af.itemCount());
}

test "itemCount returns correct count when under MAX_ITEMS" {
    var items = [_]Activity{
        .{ .event = "a" },
        .{ .event = "b" },
        .{ .event = "c" },
    };
    const af = ActivityFeed.init().withItems(&items);
    try testing.expectEqual(@as(usize, 3), af.itemCount());
}

test "itemCount returns MAX_ITEMS (64) when items exceed it" {
    var items: [100]Activity = undefined;
    for (0..100) |i| {
        items[i] = Activity{ .event = "event" };
    }
    const af = ActivityFeed.init().withItems(&items);
    try testing.expectEqual(@as(usize, ActivityFeed.MAX_ITEMS), af.itemCount());
}
