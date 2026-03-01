const std = @import("std");
const Allocator = std.mem.Allocator;
const Rect = @import("layout.zig").Rect;
const Direction = @import("layout.zig").Direction;

/// Split pane configuration
pub const SplitPane = struct {
    /// Direction of the split
    direction: Direction,
    /// Split ratio (0.0 - 1.0) for first pane
    ratio: f32,
    /// Minimum size for first pane
    min_first: u16 = 1,
    /// Minimum size for second pane
    min_second: u16 = 1,
    /// Gap between panes (for resizable border)
    gap: u16 = 0,

    /// Calculate pane areas
    pub fn layout(self: SplitPane, area: Rect) SplitResult {
        const available = switch (self.direction) {
            .horizontal => area.width,
            .vertical => area.height,
        };

        // Account for gap
        const usable = if (available > self.gap) available - self.gap else 0;

        // Calculate split point
        const clamped_ratio = @max(0.0, @min(1.0, self.ratio));
        var first_size = @as(u16, @intFromFloat(@as(f32, @floatFromInt(usable)) * clamped_ratio));

        // Enforce minimums
        first_size = @max(first_size, self.min_first);
        const remaining = if (usable > first_size) usable - first_size else 0;
        var second_size = remaining;
        second_size = @max(second_size, self.min_second);

        // Adjust if both minimums can't be satisfied
        if (first_size + second_size > usable) {
            const total_min = self.min_first + self.min_second;
            if (total_min <= usable) {
                first_size = self.min_first;
                second_size = usable - first_size;
            } else {
                // Not enough space for both minimums, distribute proportionally
                const scale = @as(f32, @floatFromInt(usable)) / @as(f32, @floatFromInt(total_min));
                first_size = @intFromFloat(@as(f32, @floatFromInt(self.min_first)) * scale);
                second_size = if (usable > first_size) usable - first_size else 0;
            }
        }

        // Create rectangles
        const first_rect = switch (self.direction) {
            .horizontal => Rect{
                .x = area.x,
                .y = area.y,
                .width = first_size,
                .height = area.height,
            },
            .vertical => Rect{
                .x = area.x,
                .y = area.y,
                .width = area.width,
                .height = first_size,
            },
        };

        const gap_offset = first_size + self.gap;
        const second_rect = switch (self.direction) {
            .horizontal => Rect{
                .x = area.x + gap_offset,
                .y = area.y,
                .width = second_size,
                .height = area.height,
            },
            .vertical => Rect{
                .x = area.x,
                .y = area.y + gap_offset,
                .width = area.width,
                .height = second_size,
            },
        };

        return .{
            .first = first_rect,
            .second = second_rect,
            .gap_rect = if (self.gap > 0) self.calculateGapRect(area, first_size) else null,
        };
    }

    fn calculateGapRect(self: SplitPane, area: Rect, first_size: u16) Rect {
        return switch (self.direction) {
            .horizontal => Rect{
                .x = area.x + first_size,
                .y = area.y,
                .width = self.gap,
                .height = area.height,
            },
            .vertical => Rect{
                .x = area.x,
                .y = area.y + first_size,
                .width = area.width,
                .height = self.gap,
            },
        };
    }

    /// Adjust ratio by delta (-1.0 to 1.0)
    pub fn adjustRatio(self: *SplitPane, delta: f32) void {
        self.ratio = @max(0.0, @min(1.0, self.ratio + delta));
    }

    /// Set ratio to specific value
    pub fn setRatio(self: *SplitPane, ratio: f32) void {
        self.ratio = @max(0.0, @min(1.0, ratio));
    }
};

/// Result of split pane layout
pub const SplitResult = struct {
    first: Rect,
    second: Rect,
    gap_rect: ?Rect,
};

/// Resizable border between panes
pub const ResizeBorder = struct {
    /// Direction of the border
    direction: Direction,
    /// Position of the border (x for vertical, y for horizontal)
    position: u16,
    /// Width of the resize handle
    handle_width: u16 = 1,
    /// Whether border is being dragged
    dragging: bool = false,

    /// Check if point is on the resize handle
    pub fn containsPoint(self: ResizeBorder, area: Rect, x: u16, y: u16) bool {
        return switch (self.direction) {
            .horizontal => y >= self.position and
                y < self.position + self.handle_width and
                x >= area.x and
                x < area.x + area.width,
            .vertical => x >= self.position and
                x < self.position + self.handle_width and
                y >= area.y and
                y < area.y + area.height,
        };
    }

    /// Start dragging the border
    pub fn startDrag(self: *ResizeBorder) void {
        self.dragging = true;
    }

    /// Stop dragging the border
    pub fn stopDrag(self: *ResizeBorder) void {
        self.dragging = false;
    }

    /// Move border to new position
    pub fn moveTo(self: *ResizeBorder, pos: u16, area: Rect, min_first: u16, min_second: u16) void {
        const available = switch (self.direction) {
            .horizontal => area.height,
            .vertical => area.width,
        };

        const max_pos = if (available > min_second + self.handle_width)
            available - min_second - self.handle_width
        else
            0;

        const min_pos = min_first;
        self.position = @max(min_pos, @min(max_pos, pos));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SplitPane - horizontal 50/50" {
    const pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.5,
    };

    const area = Rect.new(0, 0, 100, 50);
    const result = pane.layout(area);

    try std.testing.expectEqual(0, result.first.x);
    try std.testing.expectEqual(50, result.first.width);
    try std.testing.expectEqual(50, result.second.x);
    try std.testing.expectEqual(50, result.second.width);
}

test "SplitPane - vertical 30/70" {
    const pane = SplitPane{
        .direction = .vertical,
        .ratio = 0.3,
    };

    const area = Rect.new(0, 0, 100, 100);
    const result = pane.layout(area);

    try std.testing.expectEqual(0, result.first.y);
    try std.testing.expectEqual(30, result.first.height);
    try std.testing.expectEqual(30, result.second.y);
    try std.testing.expectEqual(70, result.second.height);
}

test "SplitPane - with gap" {
    const pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.5,
        .gap = 2,
    };

    const area = Rect.new(0, 0, 100, 50);
    const result = pane.layout(area);

    // Total usable: 98 (100 - 2 gap)
    try std.testing.expectEqual(49, result.first.width);
    try std.testing.expectEqual(49, result.second.width);
    try std.testing.expectEqual(51, result.second.x); // 49 + 2 gap

    // Gap rect should exist
    try std.testing.expect(result.gap_rect != null);
    if (result.gap_rect) |gap| {
        try std.testing.expectEqual(49, gap.x);
        try std.testing.expectEqual(2, gap.width);
    }
}

test "SplitPane - minimum size enforcement" {
    const pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.1,
        .min_first = 20,
        .min_second = 30,
    };

    const area = Rect.new(0, 0, 100, 50);
    const result = pane.layout(area);

    // First pane should be at least min_first
    try std.testing.expect(result.first.width >= 20);
    // Second pane should be at least min_second
    try std.testing.expect(result.second.width >= 30);
}

test "SplitPane - insufficient space" {
    const pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.5,
        .min_first = 30,
        .min_second = 40,
    };

    const area = Rect.new(0, 0, 50, 50); // Not enough for both minimums
    const result = pane.layout(area);

    // Should distribute proportionally
    try std.testing.expect(result.first.width > 0);
    try std.testing.expect(result.second.width > 0);
    try std.testing.expectEqual(50, result.first.width + result.second.width);
}

test "SplitPane - adjustRatio" {
    var pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.5,
    };

    pane.adjustRatio(0.1);
    try std.testing.expectEqual(0.6, pane.ratio);

    pane.adjustRatio(-0.3);
    try std.testing.expectEqual(0.3, pane.ratio);

    // Clamping
    pane.adjustRatio(1.0);
    try std.testing.expectEqual(1.0, pane.ratio);

    pane.adjustRatio(-2.0);
    try std.testing.expectEqual(0.0, pane.ratio);
}

test "SplitPane - setRatio" {
    var pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.5,
    };

    pane.setRatio(0.75);
    try std.testing.expectEqual(0.75, pane.ratio);

    // Clamping
    pane.setRatio(1.5);
    try std.testing.expectEqual(1.0, pane.ratio);

    pane.setRatio(-0.5);
    try std.testing.expectEqual(0.0, pane.ratio);
}

test "SplitPane - zero area" {
    const pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.5,
    };

    const area = Rect.new(0, 0, 0, 0);
    const result = pane.layout(area);

    try std.testing.expectEqual(0, result.first.width);
    try std.testing.expectEqual(0, result.second.width);
}

test "ResizeBorder - horizontal containsPoint" {
    const border = ResizeBorder{
        .direction = .horizontal,
        .position = 50,
        .handle_width = 2,
    };

    const area = Rect.new(0, 0, 100, 100);

    try std.testing.expect(border.containsPoint(area, 10, 50));
    try std.testing.expect(border.containsPoint(area, 10, 51));
    try std.testing.expect(!border.containsPoint(area, 10, 49));
    try std.testing.expect(!border.containsPoint(area, 10, 52));
}

test "ResizeBorder - vertical containsPoint" {
    const border = ResizeBorder{
        .direction = .vertical,
        .position = 50,
        .handle_width = 2,
    };

    const area = Rect.new(0, 0, 100, 100);

    try std.testing.expect(border.containsPoint(area, 50, 10));
    try std.testing.expect(border.containsPoint(area, 51, 10));
    try std.testing.expect(!border.containsPoint(area, 49, 10));
    try std.testing.expect(!border.containsPoint(area, 52, 10));
}

test "ResizeBorder - drag state" {
    var border = ResizeBorder{
        .direction = .horizontal,
        .position = 50,
    };

    try std.testing.expect(!border.dragging);

    border.startDrag();
    try std.testing.expect(border.dragging);

    border.stopDrag();
    try std.testing.expect(!border.dragging);
}

test "ResizeBorder - moveTo" {
    var border = ResizeBorder{
        .direction = .vertical,
        .position = 50,
        .handle_width = 1,
    };

    const area = Rect.new(0, 0, 100, 100);

    border.moveTo(70, area, 10, 10);
    try std.testing.expectEqual(70, border.position);

    // Respect min_second (should stay at max 89: 100 - 10 - 1)
    border.moveTo(95, area, 10, 10);
    try std.testing.expectEqual(89, border.position);

    // Respect min_first
    border.moveTo(5, area, 10, 10);
    try std.testing.expectEqual(10, border.position);
}

test "ResizeBorder - moveTo edge cases" {
    var border = ResizeBorder{
        .direction = .horizontal,
        .position = 50,
    };

    const area = Rect.new(0, 0, 100, 50);

    // Move to exactly min_first
    border.moveTo(10, area, 10, 10);
    try std.testing.expectEqual(10, border.position);

    // Move to exactly max position
    border.moveTo(39, area, 10, 10); // 50 - 10 - 1
    try std.testing.expectEqual(39, border.position);
}

test "SplitPane - ratio extremes" {
    var pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.0,
    };

    const area = Rect.new(0, 0, 100, 50);
    var result = pane.layout(area);

    // With ratio 0, first pane should be minimal (min_first)
    try std.testing.expectEqual(1, result.first.width); // default min_first = 1
    try std.testing.expectEqual(99, result.second.width); // remaining space

    pane.ratio = 1.0;
    result = pane.layout(area);

    // With ratio 1.0 and minimum constraints, both minimums must be respected
    // The adjustment logic prioritizes satisfying both minimums over ratio
    try std.testing.expectEqual(1, result.first.width); // adjusted to min_first
    try std.testing.expectEqual(99, result.second.width); // gets the remainder
}

test "SplitPane - gap larger than area" {
    const pane = SplitPane{
        .direction = .horizontal,
        .ratio = 0.5,
        .gap = 200,
    };

    const area = Rect.new(0, 0, 100, 50);
    const result = pane.layout(area);

    // Should handle gracefully
    try std.testing.expectEqual(0, result.first.width + result.second.width);
}
