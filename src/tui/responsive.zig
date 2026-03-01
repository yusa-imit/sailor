const std = @import("std");
const Rect = @import("layout.zig").Rect;

/// Screen size category based on breakpoints
pub const ScreenSize = enum {
    tiny, // < 40 cols
    small, // 40-79 cols
    medium, // 80-119 cols
    large, // 120+ cols

    /// Determine screen size from terminal dimensions
    pub fn fromWidth(width: u16) ScreenSize {
        if (width < 40) return .tiny;
        if (width < 80) return .small;
        if (width < 120) return .medium;
        return .large;
    }

    /// Check if this size is at least the given size
    pub fn isAtLeast(self: ScreenSize, min: ScreenSize) bool {
        return @intFromEnum(self) >= @intFromEnum(min);
    }

    /// Check if this size is at most the given size
    pub fn isAtMost(self: ScreenSize, max: ScreenSize) bool {
        return @intFromEnum(self) <= @intFromEnum(max);
    }
};

/// Breakpoint configuration
pub const Breakpoint = struct {
    /// Minimum width for this breakpoint
    min_width: u16,
    /// Minimum height for this breakpoint (optional)
    min_height: ?u16 = null,

    /// Check if area meets this breakpoint
    pub fn matches(self: Breakpoint, area: Rect) bool {
        const width_ok = area.width >= self.min_width;
        const height_ok = if (self.min_height) |h| area.height >= h else true;
        return width_ok and height_ok;
    }
};

/// Responsive layout configuration with multiple breakpoints
pub const ResponsiveLayout = struct {
    breakpoints: []const Breakpoint,

    /// Find the largest matching breakpoint
    pub fn findBreakpoint(self: ResponsiveLayout, area: Rect) ?usize {
        var best: ?usize = null;
        var best_width: u16 = 0;

        for (self.breakpoints, 0..) |bp, i| {
            if (bp.matches(area)) {
                if (best == null or bp.min_width > best_width) {
                    best = i;
                    best_width = bp.min_width;
                }
            }
        }

        return best;
    }

    /// Check if area is mobile-sized (width < 80)
    pub fn isMobile(area: Rect) bool {
        return area.width < 80;
    }

    /// Check if area is desktop-sized (width >= 80)
    pub fn isDesktop(area: Rect) bool {
        return area.width >= 80;
    }
};

/// Adaptive value that changes based on screen size
pub fn AdaptiveValue(comptime T: type) type {
    return struct {
        tiny: T,
        small: T,
        medium: T,
        large: T,

        const Self = @This();

        /// Get value for given screen size
        pub fn get(self: Self, size: ScreenSize) T {
            return switch (size) {
                .tiny => self.tiny,
                .small => self.small,
                .medium => self.medium,
                .large => self.large,
            };
        }

        /// Get value for given area
        pub fn getFor(self: Self, area: Rect) T {
            return self.get(ScreenSize.fromWidth(area.width));
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ScreenSize.fromWidth - tiny" {
    const size = ScreenSize.fromWidth(30);
    try std.testing.expectEqual(ScreenSize.tiny, size);
}

test "ScreenSize.fromWidth - small" {
    const size = ScreenSize.fromWidth(60);
    try std.testing.expectEqual(ScreenSize.small, size);

    const size2 = ScreenSize.fromWidth(40); // exactly 40
    try std.testing.expectEqual(ScreenSize.small, size2);
}

test "ScreenSize.fromWidth - medium" {
    const size = ScreenSize.fromWidth(100);
    try std.testing.expectEqual(ScreenSize.medium, size);

    const size2 = ScreenSize.fromWidth(80); // exactly 80
    try std.testing.expectEqual(ScreenSize.medium, size2);
}

test "ScreenSize.fromWidth - large" {
    const size = ScreenSize.fromWidth(150);
    try std.testing.expectEqual(ScreenSize.large, size);

    const size2 = ScreenSize.fromWidth(120); // exactly 120
    try std.testing.expectEqual(ScreenSize.large, size2);
}

test "ScreenSize.isAtLeast" {
    const medium = ScreenSize.medium;

    try std.testing.expect(medium.isAtLeast(.tiny));
    try std.testing.expect(medium.isAtLeast(.small));
    try std.testing.expect(medium.isAtLeast(.medium));
    try std.testing.expect(!medium.isAtLeast(.large));
}

test "ScreenSize.isAtMost" {
    const medium = ScreenSize.medium;

    try std.testing.expect(!medium.isAtMost(.tiny));
    try std.testing.expect(!medium.isAtMost(.small));
    try std.testing.expect(medium.isAtMost(.medium));
    try std.testing.expect(medium.isAtMost(.large));
}

test "Breakpoint.matches - width only" {
    const bp = Breakpoint{
        .min_width = 80,
    };

    try std.testing.expect(bp.matches(Rect.new(0, 0, 80, 24)));
    try std.testing.expect(bp.matches(Rect.new(0, 0, 100, 10)));
    try std.testing.expect(!bp.matches(Rect.new(0, 0, 79, 50)));
}

test "Breakpoint.matches - width and height" {
    const bp = Breakpoint{
        .min_width = 80,
        .min_height = 24,
    };

    try std.testing.expect(bp.matches(Rect.new(0, 0, 80, 24)));
    try std.testing.expect(bp.matches(Rect.new(0, 0, 100, 30)));
    try std.testing.expect(!bp.matches(Rect.new(0, 0, 80, 20)));
    try std.testing.expect(!bp.matches(Rect.new(0, 0, 79, 24)));
}

test "ResponsiveLayout.findBreakpoint" {
    const breakpoints = [_]Breakpoint{
        .{ .min_width = 40 }, // small
        .{ .min_width = 80 }, // medium
        .{ .min_width = 120 }, // large
    };

    const layout = ResponsiveLayout{
        .breakpoints = &breakpoints,
    };

    // Tiny screen - no breakpoint matches
    const tiny_area = Rect.new(0, 0, 30, 24);
    try std.testing.expectEqual(null, layout.findBreakpoint(tiny_area));

    // Small screen
    const small_area = Rect.new(0, 0, 60, 24);
    const small_bp = layout.findBreakpoint(small_area);
    try std.testing.expect(small_bp != null);
    try std.testing.expectEqual(40, breakpoints[small_bp.?].min_width);

    // Medium screen
    const medium_area = Rect.new(0, 0, 100, 24);
    const medium_bp = layout.findBreakpoint(medium_area);
    try std.testing.expect(medium_bp != null);
    try std.testing.expectEqual(80, breakpoints[medium_bp.?].min_width);

    // Large screen
    const large_area = Rect.new(0, 0, 150, 24);
    const large_bp = layout.findBreakpoint(large_area);
    try std.testing.expect(large_bp != null);
    try std.testing.expectEqual(120, breakpoints[large_bp.?].min_width);
}

test "ResponsiveLayout.isMobile" {
    try std.testing.expect(ResponsiveLayout.isMobile(Rect.new(0, 0, 79, 24)));
    try std.testing.expect(ResponsiveLayout.isMobile(Rect.new(0, 0, 40, 24)));
    try std.testing.expect(!ResponsiveLayout.isMobile(Rect.new(0, 0, 80, 24)));
}

test "ResponsiveLayout.isDesktop" {
    try std.testing.expect(!ResponsiveLayout.isDesktop(Rect.new(0, 0, 79, 24)));
    try std.testing.expect(ResponsiveLayout.isDesktop(Rect.new(0, 0, 80, 24)));
    try std.testing.expect(ResponsiveLayout.isDesktop(Rect.new(0, 0, 120, 24)));
}

test "AdaptiveValue - u16" {
    const cols = AdaptiveValue(u16){
        .tiny = 1,
        .small = 2,
        .medium = 3,
        .large = 4,
    };

    try std.testing.expectEqual(1, cols.get(.tiny));
    try std.testing.expectEqual(2, cols.get(.small));
    try std.testing.expectEqual(3, cols.get(.medium));
    try std.testing.expectEqual(4, cols.get(.large));
}

test "AdaptiveValue - getFor" {
    const padding = AdaptiveValue(u16){
        .tiny = 0,
        .small = 1,
        .medium = 2,
        .large = 3,
    };

    try std.testing.expectEqual(0, padding.getFor(Rect.new(0, 0, 30, 24)));
    try std.testing.expectEqual(1, padding.getFor(Rect.new(0, 0, 60, 24)));
    try std.testing.expectEqual(2, padding.getFor(Rect.new(0, 0, 100, 24)));
    try std.testing.expectEqual(3, padding.getFor(Rect.new(0, 0, 150, 24)));
}

test "AdaptiveValue - bool" {
    const show_sidebar = AdaptiveValue(bool){
        .tiny = false,
        .small = false,
        .medium = true,
        .large = true,
    };

    try std.testing.expect(!show_sidebar.get(.tiny));
    try std.testing.expect(!show_sidebar.get(.small));
    try std.testing.expect(show_sidebar.get(.medium));
    try std.testing.expect(show_sidebar.get(.large));
}

test "ResponsiveLayout - multiple matching breakpoints" {
    const breakpoints = [_]Breakpoint{
        .{ .min_width = 40 },
        .{ .min_width = 60 },
        .{ .min_width = 80 },
    };

    const layout = ResponsiveLayout{
        .breakpoints = &breakpoints,
    };

    // Area that matches all breakpoints - should return the largest
    const area = Rect.new(0, 0, 100, 24);
    const bp = layout.findBreakpoint(area);
    try std.testing.expect(bp != null);
    try std.testing.expectEqual(80, breakpoints[bp.?].min_width);
}

test "ResponsiveLayout - empty breakpoints" {
    const breakpoints = [_]Breakpoint{};
    const layout = ResponsiveLayout{
        .breakpoints = &breakpoints,
    };

    const area = Rect.new(0, 0, 100, 24);
    try std.testing.expectEqual(null, layout.findBreakpoint(area));
}

test "Breakpoint - height constraint only" {
    const bp = Breakpoint{
        .min_width = 0,
        .min_height = 30,
    };

    try std.testing.expect(bp.matches(Rect.new(0, 0, 10, 30)));
    try std.testing.expect(bp.matches(Rect.new(0, 0, 10, 50)));
    try std.testing.expect(!bp.matches(Rect.new(0, 0, 100, 20)));
}

test "ScreenSize - enum ordering" {
    // Verify that enum ordering is tiny < small < medium < large
    try std.testing.expect(@intFromEnum(ScreenSize.tiny) < @intFromEnum(ScreenSize.small));
    try std.testing.expect(@intFromEnum(ScreenSize.small) < @intFromEnum(ScreenSize.medium));
    try std.testing.expect(@intFromEnum(ScreenSize.medium) < @intFromEnum(ScreenSize.large));
}

test "Breakpoint - exact boundary matching" {
    const bp = Breakpoint{
        .min_width = 80,
        .min_height = 24,
    };

    // Exactly at boundary
    try std.testing.expect(bp.matches(Rect.new(0, 0, 80, 24)));

    // One below boundary
    try std.testing.expect(!bp.matches(Rect.new(0, 0, 79, 24)));
    try std.testing.expect(!bp.matches(Rect.new(0, 0, 80, 23)));
}
