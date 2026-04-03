//! SplitPane widget — resizable panes with drag handle for interactive resizing.
//!
//! SplitPane divides a rectangular area into two sections (horizontal or vertical)
//! with support for fixed or percentage-based sizing, min/max constraints,
//! and optional visual separator.
//!
//! ## Features
//! - Horizontal split (left/right panes) or vertical split (top/bottom panes)
//! - Resizable with drag handle for interactive mouse-based resizing
//! - Fixed size or percentage-based split ratios
//! - Min/max size constraints per pane
//! - Optional visual divider/separator
//! - 2-pane splits only
//!
//! ## Usage
//! ```zig
//! const split = SplitPane{
//!     .direction = .horizontal,
//!     .split_ratio = 0.5, // 50/50 split
//!     .min_first_size = 10,
//!     .max_first_size = 80,
//!     .show_divider = true,
//! };
//! const panes = split.calculatePanes(area);
//! // Render widgets in panes[0] and panes[1]
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const Direction = layout_mod.Direction;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;

/// Split pane widget for dividing area into two resizable sections
pub const SplitPane = struct {
    /// Split direction (horizontal = left/right, vertical = top/bottom)
    direction: Direction = .horizontal,

    /// Split ratio (0.0 to 1.0) — portion allocated to first pane
    split_ratio: f64 = 0.5,

    /// Minimum size for first pane (in cells)
    min_first_size: u16 = 0,

    /// Maximum size for first pane (in cells)
    max_first_size: u16 = std.math.maxInt(u16),

    /// Minimum size for second pane (in cells)
    min_second_size: u16 = 0,

    /// Maximum size for second pane (in cells)
    max_second_size: u16 = std.math.maxInt(u16),

    /// Show visual divider between panes
    show_divider: bool = true,

    /// Divider character
    divider_char: u21 = '│',

    /// Divider style
    divider_style: Style = .{},

    /// Create a new split pane with default settings
    pub fn init() SplitPane {
        return .{};
    }

    /// Set split direction
    pub fn withDirection(self: SplitPane, dir: Direction) SplitPane {
        var result = self;
        result.direction = dir;
        return result;
    }

    /// Set split ratio (clamped to 0.0-1.0)
    pub fn withRatio(self: SplitPane, ratio: f64) SplitPane {
        var result = self;
        result.split_ratio = std.math.clamp(ratio, 0.0, 1.0);
        return result;
    }

    /// Set split from percentage (0-100)
    pub fn withPercent(self: SplitPane, percent: u8) SplitPane {
        var result = self;
        const clamped = @min(percent, 100);
        result.split_ratio = @as(f64, @floatFromInt(clamped)) / 100.0;
        return result;
    }

    /// Set minimum size for first pane
    pub fn withMinFirstSize(self: SplitPane, size: u16) SplitPane {
        var result = self;
        result.min_first_size = size;
        return result;
    }

    /// Set maximum size for first pane
    pub fn withMaxFirstSize(self: SplitPane, size: u16) SplitPane {
        var result = self;
        result.max_first_size = size;
        return result;
    }

    /// Set minimum size for second pane
    pub fn withMinSecondSize(self: SplitPane, size: u16) SplitPane {
        var result = self;
        result.min_second_size = size;
        return result;
    }

    /// Set maximum size for second pane
    pub fn withMaxSecondSize(self: SplitPane, size: u16) SplitPane {
        var result = self;
        result.max_second_size = size;
        return result;
    }

    /// Enable or disable divider
    pub fn withDivider(self: SplitPane, show: bool) SplitPane {
        var result = self;
        result.show_divider = show;
        return result;
    }

    /// Set divider character
    pub fn withDividerChar(self: SplitPane, char: u21) SplitPane {
        var result = self;
        result.divider_char = char;
        return result;
    }

    /// Set divider style
    pub fn withDividerStyle(self: SplitPane, new_style: Style) SplitPane {
        var result = self;
        result.divider_style = new_style;
        return result;
    }

    /// Calculate pane areas from parent area
    /// Returns [2]Rect: [first_pane, second_pane]
    pub fn calculatePanes(self: SplitPane, area: Rect) [2]Rect {
        // Handle zero-size area
        if (area.width == 0 or area.height == 0) {
            return [2]Rect{
                Rect.new(area.x, area.y, 0, 0),
                Rect.new(area.x, area.y, 0, 0),
            };
        }

        // Determine available space
        const available = switch (self.direction) {
            .horizontal => area.width,
            .vertical => area.height,
        };

        // Reserve space for divider if enabled
        const divider_size: u16 = if (self.show_divider) 1 else 0;
        const usable_space = if (available > divider_size) available - divider_size else 0;

        // Calculate raw first pane size from ratio
        var first_size: u16 = @intFromFloat(@as(f64, @floatFromInt(usable_space)) * self.split_ratio);

        // Apply constraints to first pane
        first_size = @max(first_size, self.min_first_size);
        first_size = @min(first_size, self.max_first_size);
        first_size = @min(first_size, usable_space); // Can't exceed total

        // Calculate second pane size
        var second_size: u16 = if (usable_space > first_size) usable_space - first_size else 0;

        // Apply constraints to second pane (may need to adjust first pane)
        if (second_size < self.min_second_size) {
            // Need to shrink first pane to meet second pane minimum
            const needed = self.min_second_size - second_size;
            if (first_size >= needed) {
                first_size -= needed;
                second_size = self.min_second_size;
            } else {
                // Can't satisfy minimum — give what we can
                second_size = usable_space - first_size;
            }
        }
        if (second_size > self.max_second_size) {
            // Need to grow first pane (second exceeded max)
            const excess = second_size - self.max_second_size;
            first_size = @min(first_size + excess, usable_space);
            second_size = self.max_second_size;
        }

        // Build rectangles
        return switch (self.direction) {
            .horizontal => [2]Rect{
                Rect.new(area.x, area.y, first_size, area.height),
                Rect.new(area.x + first_size + divider_size, area.y, second_size, area.height),
            },
            .vertical => [2]Rect{
                Rect.new(area.x, area.y, area.width, first_size),
                Rect.new(area.x, area.y + first_size + divider_size, area.width, second_size),
            },
        };
    }

    /// Render the split pane (just the divider if enabled)
    pub fn render(self: SplitPane, buf: *Buffer, area: Rect) void {
        if (!self.show_divider) return;
        if (area.width == 0 or area.height == 0) return;

        const panes = self.calculatePanes(area);
        const first_pane = panes[0];

        switch (self.direction) {
            .horizontal => {
                // Divider is vertical line between panes
                const divider_x = first_pane.x + first_pane.width;
                if (divider_x >= area.x + area.width) return; // No room

                var y = area.y;
                while (y < area.y + area.height) : (y += 1) {
                    buf.setChar(divider_x, y, self.divider_char, self.divider_style);
                }
            },
            .vertical => {
                // Divider is horizontal line between panes
                const divider_y = first_pane.y + first_pane.height;
                if (divider_y >= area.y + area.height) return; // No room

                var x = area.x;
                while (x < area.x + area.width) : (x += 1) {
                    buf.setChar(x, divider_y, self.divider_char, self.divider_style);
                }
            },
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SplitPane.init default values" {
    const split = SplitPane.init();

    try std.testing.expectEqual(Direction.horizontal, split.direction);
    try std.testing.expectEqual(0.5, split.split_ratio);
    try std.testing.expectEqual(@as(u16, 0), split.min_first_size);
    try std.testing.expectEqual(std.math.maxInt(u16), split.max_first_size);
    try std.testing.expectEqual(@as(u16, 0), split.min_second_size);
    try std.testing.expectEqual(std.math.maxInt(u16), split.max_second_size);
    try std.testing.expectEqual(true, split.show_divider);
    try std.testing.expectEqual('│', split.divider_char);
}

test "SplitPane.withDirection" {
    const split = SplitPane.init().withDirection(.vertical);

    try std.testing.expectEqual(Direction.vertical, split.direction);
}

test "SplitPane.withRatio" {
    const split = SplitPane.init().withRatio(0.7);

    try std.testing.expectEqual(0.7, split.split_ratio);
}

test "SplitPane.withRatio clamps to 0.0-1.0" {
    const split1 = SplitPane.init().withRatio(-0.5);
    try std.testing.expectEqual(0.0, split1.split_ratio);

    const split2 = SplitPane.init().withRatio(1.5);
    try std.testing.expectEqual(1.0, split2.split_ratio);
}

test "SplitPane.withPercent" {
    const split = SplitPane.init().withPercent(30);

    try std.testing.expectEqual(0.3, split.split_ratio);
}

test "SplitPane.withPercent clamps to 100" {
    const split = SplitPane.init().withPercent(150);

    try std.testing.expectEqual(1.0, split.split_ratio);
}

test "SplitPane.withMinFirstSize" {
    const split = SplitPane.init().withMinFirstSize(20);

    try std.testing.expectEqual(@as(u16, 20), split.min_first_size);
}

test "SplitPane.withMaxFirstSize" {
    const split = SplitPane.init().withMaxFirstSize(60);

    try std.testing.expectEqual(@as(u16, 60), split.max_first_size);
}

test "SplitPane.withMinSecondSize" {
    const split = SplitPane.init().withMinSecondSize(15);

    try std.testing.expectEqual(@as(u16, 15), split.min_second_size);
}

test "SplitPane.withMaxSecondSize" {
    const split = SplitPane.init().withMaxSecondSize(50);

    try std.testing.expectEqual(@as(u16, 50), split.max_second_size);
}

test "SplitPane.withDivider" {
    const split = SplitPane.init().withDivider(false);

    try std.testing.expectEqual(false, split.show_divider);
}

test "SplitPane.withDividerChar" {
    const split = SplitPane.init().withDividerChar('|');

    try std.testing.expectEqual('|', split.divider_char);
}

test "SplitPane.withDividerStyle" {
    const style = Style{ .fg = .blue };
    const split = SplitPane.init().withDividerStyle(style);

    try std.testing.expectEqual(Color.blue, split.divider_style.fg);
}

test "SplitPane.calculatePanes horizontal 50/50" {
    const split = SplitPane.init();
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // With divider: 100 - 1 = 99 usable, 50/50 split
    try std.testing.expectEqual(@as(u16, 0), panes[0].x);
    try std.testing.expectEqual(@as(u16, 0), panes[0].y);
    try std.testing.expectEqual(@as(u16, 49), panes[0].width); // floor(99 * 0.5)
    try std.testing.expectEqual(@as(u16, 20), panes[0].height);

    try std.testing.expectEqual(@as(u16, 50), panes[1].x); // 49 + 1 divider
    try std.testing.expectEqual(@as(u16, 0), panes[1].y);
    try std.testing.expectEqual(@as(u16, 50), panes[1].width); // 99 - 49
    try std.testing.expectEqual(@as(u16, 20), panes[1].height);
}

test "SplitPane.calculatePanes horizontal 30/70" {
    const split = SplitPane.init().withPercent(30);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // With divider: 100 - 1 = 99 usable, 30% = 29.7 → 29
    try std.testing.expectEqual(@as(u16, 29), panes[0].width);
    try std.testing.expectEqual(@as(u16, 70), panes[1].width); // 99 - 29
}

test "SplitPane.calculatePanes vertical 50/50" {
    const split = SplitPane.init().withDirection(.vertical);
    const area = Rect.new(0, 0, 80, 40);

    const panes = split.calculatePanes(area);

    // With divider: 40 - 1 = 39 usable, 50/50 split
    try std.testing.expectEqual(@as(u16, 0), panes[0].x);
    try std.testing.expectEqual(@as(u16, 0), panes[0].y);
    try std.testing.expectEqual(@as(u16, 80), panes[0].width);
    try std.testing.expectEqual(@as(u16, 19), panes[0].height); // floor(39 * 0.5)

    try std.testing.expectEqual(@as(u16, 0), panes[1].x);
    try std.testing.expectEqual(@as(u16, 20), panes[1].y); // 19 + 1 divider
    try std.testing.expectEqual(@as(u16, 80), panes[1].width);
    try std.testing.expectEqual(@as(u16, 20), panes[1].height); // 39 - 19
}

test "SplitPane.calculatePanes vertical 60/40" {
    const split = SplitPane.init().withDirection(.vertical).withPercent(60);
    const area = Rect.new(0, 0, 80, 50);

    const panes = split.calculatePanes(area);

    // With divider: 50 - 1 = 49 usable, 60% = 29.4 → 29
    try std.testing.expectEqual(@as(u16, 29), panes[0].height);
    try std.testing.expectEqual(@as(u16, 20), panes[1].height); // 49 - 29
}

test "SplitPane.calculatePanes no divider horizontal" {
    const split = SplitPane.init().withDivider(false);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // No divider: full 100 usable
    try std.testing.expectEqual(@as(u16, 50), panes[0].width);
    try std.testing.expectEqual(@as(u16, 50), panes[1].x);
    try std.testing.expectEqual(@as(u16, 50), panes[1].width);
}

test "SplitPane.calculatePanes no divider vertical" {
    const split = SplitPane.init().withDirection(.vertical).withDivider(false);
    const area = Rect.new(0, 0, 80, 40);

    const panes = split.calculatePanes(area);

    // No divider: full 40 usable
    try std.testing.expectEqual(@as(u16, 20), panes[0].height);
    try std.testing.expectEqual(@as(u16, 20), panes[1].y);
    try std.testing.expectEqual(@as(u16, 20), panes[1].height);
}

test "SplitPane.calculatePanes min first size enforced" {
    const split = SplitPane.init()
        .withPercent(10) // Want 10%, but min will force larger
        .withMinFirstSize(30);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // Min first = 30, should override 10% (which would be ~9)
    try std.testing.expectEqual(@as(u16, 30), panes[0].width);
}

test "SplitPane.calculatePanes max first size enforced" {
    const split = SplitPane.init()
        .withPercent(80) // Want 80%, but max will limit
        .withMaxFirstSize(40);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // Max first = 40, should cap at 40 (80% would be ~79)
    try std.testing.expectEqual(@as(u16, 40), panes[0].width);
}

test "SplitPane.calculatePanes min second size enforced" {
    const split = SplitPane.init()
        .withPercent(95) // Want 95% first, but second needs min
        .withMinSecondSize(20);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // Min second = 20, should force first to shrink
    // Usable = 99, second min = 20, so first max = 79
    try std.testing.expectEqual(@as(u16, 79), panes[0].width);
    try std.testing.expectEqual(@as(u16, 20), panes[1].width);
}

test "SplitPane.calculatePanes max second size enforced" {
    const split = SplitPane.init()
        .withPercent(10) // Want 10% first, gives 90% to second, but limited
        .withMaxSecondSize(30);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // Max second = 30, excess goes to first
    try std.testing.expectEqual(@as(u16, 30), panes[1].width);
    // First should get the rest: 99 - 30 = 69
    try std.testing.expectEqual(@as(u16, 69), panes[0].width);
}

test "SplitPane.calculatePanes zero width area" {
    const split = SplitPane.init();
    const area = Rect.new(0, 0, 0, 20);

    const panes = split.calculatePanes(area);

    try std.testing.expectEqual(@as(u16, 0), panes[0].width);
    try std.testing.expectEqual(@as(u16, 0), panes[1].width);
}

test "SplitPane.calculatePanes zero height area" {
    const split = SplitPane.init().withDirection(.vertical);
    const area = Rect.new(0, 0, 80, 0);

    const panes = split.calculatePanes(area);

    try std.testing.expectEqual(@as(u16, 0), panes[0].height);
    try std.testing.expectEqual(@as(u16, 0), panes[1].height);
}

test "SplitPane.calculatePanes full width to first pane" {
    const split = SplitPane.init()
        .withPercent(100)
        .withDivider(false);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    try std.testing.expectEqual(@as(u16, 100), panes[0].width);
    try std.testing.expectEqual(@as(u16, 0), panes[1].width);
}

test "SplitPane.calculatePanes full width to second pane" {
    const split = SplitPane.init()
        .withPercent(0)
        .withDivider(false);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    try std.testing.expectEqual(@as(u16, 0), panes[0].width);
    try std.testing.expectEqual(@as(u16, 100), panes[1].width);
}

test "SplitPane.calculatePanes min greater than available" {
    const split = SplitPane.init()
        .withMinFirstSize(200); // Min > available
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // Should clamp to available (99 with divider)
    try std.testing.expectEqual(@as(u16, 99), panes[0].width);
    try std.testing.expectEqual(@as(u16, 0), panes[1].width);
}

test "SplitPane.calculatePanes conflicting constraints" {
    // Both panes want more than available
    const split = SplitPane.init()
        .withMinFirstSize(60)
        .withMinSecondSize(60);
    const area = Rect.new(0, 0, 100, 20);

    const panes = split.calculatePanes(area);

    // Should prioritize first pane min, give remainder to second
    try std.testing.expectEqual(@as(u16, 60), panes[0].width);
    // Second gets what's left: 99 - 60 = 39 (below its min)
    try std.testing.expectEqual(@as(u16, 39), panes[1].width);
}

test "SplitPane.render horizontal divider" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 20);
    defer buf.deinit();

    const split = SplitPane.init();
    const area = Rect.new(0, 0, 100, 20);

    split.render(&buf, area);

    // Divider should be at x=49 (after first pane width 49)
    for (0..20) |y| {
        const cell = buf.get(49, @intCast(y));
        try std.testing.expect(cell != null);
        try std.testing.expectEqual('│', cell.?.char);
    }
}

test "SplitPane.render vertical divider" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 40);
    defer buf.deinit();

    const split = SplitPane.init().withDirection(.vertical);
    const area = Rect.new(0, 0, 80, 40);

    split.render(&buf, area);

    // Divider should be at y=19 (after first pane height 19)
    for (0..80) |x| {
        const cell = buf.get(@intCast(x), 19);
        try std.testing.expect(cell != null);
        try std.testing.expectEqual('│', cell.?.char);
    }
}

test "SplitPane.render custom divider char" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 20);
    defer buf.deinit();

    const split = SplitPane.init().withDividerChar('|');
    const area = Rect.new(0, 0, 100, 20);

    split.render(&buf, area);

    const cell = buf.get(49, 0);
    try std.testing.expect(cell != null);
    try std.testing.expectEqual('|', cell.?.char);
}

test "SplitPane.render divider with style" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 20);
    defer buf.deinit();

    const style = Style{ .fg = .red };
    const split = SplitPane.init().withDividerStyle(style);
    const area = Rect.new(0, 0, 100, 20);

    split.render(&buf, area);

    const cell = buf.get(49, 0);
    try std.testing.expect(cell != null);
    try std.testing.expectEqual(Color.red, cell.?.style.fg);
}

test "SplitPane.render no divider renders nothing" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 20);
    defer buf.deinit();

    const split = SplitPane.init().withDivider(false);
    const area = Rect.new(0, 0, 100, 20);

    split.render(&buf, area);

    // All cells should be default (space)
    for (0..20) |y| {
        for (0..100) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            try std.testing.expect(cell != null);
            try std.testing.expectEqual(' ', cell.?.char);
        }
    }
}

test "SplitPane.render zero size area does not crash" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const split = SplitPane.init();
    const area = Rect.new(0, 0, 0, 0);

    split.render(&buf, area);

    // Should not crash
}

test "SplitPane.render horizontal divider for vertical split" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 40);
    defer buf.deinit();

    const split = SplitPane.init()
        .withDirection(.vertical)
        .withDividerChar('─');
    const area = Rect.new(0, 0, 80, 40);

    split.render(&buf, area);

    // Horizontal divider at y=19
    for (0..80) |x| {
        const cell = buf.get(@intCast(x), 19);
        try std.testing.expect(cell != null);
        try std.testing.expectEqual('─', cell.?.char);
    }
}
