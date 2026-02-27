const std = @import("std");
const Allocator = std.mem.Allocator;

/// Rectangle area in terminal coordinates
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    /// Create a new rectangle
    pub fn new(x: u16, y: u16, width: u16, height: u16) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    /// Get area (width × height)
    pub fn area(self: Rect) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    /// Check if rectangle contains a point
    pub fn contains(self: Rect, px: u16, py: u16) bool {
        return px >= self.x and
            px < self.x + self.width and
            py >= self.y and
            py < self.y + self.height;
    }

    /// Get inner rectangle with margin applied
    pub fn inner(self: Rect, margin: u16) Rect {
        const margin2 = margin * 2;
        if (self.width <= margin2 or self.height <= margin2) {
            return .{ .x = self.x, .y = self.y, .width = 0, .height = 0 };
        }
        return .{
            .x = self.x + margin,
            .y = self.y + margin,
            .width = self.width - margin2,
            .height = self.height - margin2,
        };
    }

    /// Check if two rectangles intersect
    pub fn intersects(self: Rect, other: Rect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    /// Get intersection of two rectangles
    pub fn intersection(self: Rect, other: Rect) ?Rect {
        if (!self.intersects(other)) return null;

        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        return Rect.new(x1, y1, x2 - x1, y2 - y1);
    }
};

/// Layout direction
pub const Direction = enum {
    horizontal,
    vertical,
};

/// Layout constraint for splitting areas
pub const Constraint = union(enum) {
    /// Fixed length in cells
    length: u16,
    /// Percentage of available space (0-100)
    percentage: u8,
    /// Minimum length
    min: u16,
    /// Maximum length
    max: u16,
    /// Ratio (numerator/denominator)
    ratio: struct { num: u32, denom: u32 },

    /// Calculate actual size for this constraint given available space
    pub fn apply(self: Constraint, available: u16) u16 {
        return switch (self) {
            .length => |len| @min(len, available),
            .percentage => |pct| blk: {
                const clamped = @min(pct, 100);
                const size = (@as(u32, available) * clamped) / 100;
                break :blk @as(u16, @intCast(@min(size, available)));
            },
            .min => |minimum| @min(minimum, available),
            .max => |maximum| @min(maximum, available),
            .ratio => |r| blk: {
                if (r.denom == 0) break :blk 0;
                const size = (@as(u64, available) * r.num) / r.denom;
                break :blk @as(u16, @intCast(@min(size, available)));
            },
        };
    }
};

/// Split area into multiple chunks based on constraints
pub fn split(
    allocator: Allocator,
    direction: Direction,
    area: Rect,
    constraints: []const Constraint,
) ![]Rect {
    if (constraints.len == 0) {
        return &[_]Rect{};
    }

    const result = try allocator.alloc(Rect, constraints.len);
    errdefer allocator.free(result);

    // Available space to distribute
    const available = switch (direction) {
        .horizontal => area.width,
        .vertical => area.height,
    };

    // First pass: calculate fixed sizes and collect flexible constraints
    var fixed_size: u32 = 0;
    var has_flexible = false;

    for (constraints) |constraint| {
        switch (constraint) {
            .length => |len| {
                fixed_size += @min(len, available);
            },
            .percentage, .ratio => {
                has_flexible = true;
            },
            .min, .max => {
                // Min/max are treated as flexible with bounds
                has_flexible = true;
            },
        }
    }

    // Calculate sizes for each constraint
    const sizes = try allocator.alloc(u16, constraints.len);
    defer allocator.free(sizes);

    var total_size: u32 = 0;
    for (constraints, 0..) |constraint, i| {
        const size = constraint.apply(available);
        sizes[i] = size;
        total_size += size;
    }

    // If total exceeds available, proportionally reduce
    if (total_size > available) {
        const scale = @as(f64, @floatFromInt(available)) / @as(f64, @floatFromInt(total_size));
        total_size = 0;
        for (sizes, 0..) |size, i| {
            const scaled = @as(u16, @intFromFloat(@as(f64, @floatFromInt(size)) * scale));
            sizes[i] = scaled;
            total_size += scaled;
        }
    }

    // Distribute remaining space to last flexible constraint
    if (total_size < available and has_flexible) {
        const remaining = available - @as(u16, @intCast(total_size));
        // Find last flexible constraint
        var last_flexible: ?usize = null;
        var i = constraints.len;
        while (i > 0) {
            i -= 1;
            switch (constraints[i]) {
                .percentage, .ratio, .min, .max => {
                    last_flexible = i;
                    break;
                },
                else => {},
            }
        }
        if (last_flexible) |idx| {
            sizes[idx] += remaining;
        }
    }

    // Create rectangles
    var offset: u16 = 0;
    for (sizes, 0..) |size, i| {
        result[i] = switch (direction) {
            .horizontal => Rect.new(area.x + offset, area.y, size, area.height),
            .vertical => Rect.new(area.x, area.y + offset, area.width, size),
        };
        offset += size;
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "Rect.new" {
    const r = Rect.new(10, 20, 30, 40);
    try std.testing.expectEqual(10, r.x);
    try std.testing.expectEqual(20, r.y);
    try std.testing.expectEqual(30, r.width);
    try std.testing.expectEqual(40, r.height);
}

test "Rect.area" {
    const r = Rect.new(0, 0, 10, 5);
    try std.testing.expectEqual(50, r.area());
}

test "Rect.contains" {
    const r = Rect.new(10, 10, 20, 20);
    try std.testing.expect(r.contains(10, 10));
    try std.testing.expect(r.contains(20, 20));
    try std.testing.expect(r.contains(29, 29));
    try std.testing.expect(!r.contains(30, 30));
    try std.testing.expect(!r.contains(5, 15));
}

test "Rect.inner" {
    const r = Rect.new(10, 10, 20, 20);
    const inner_rect = r.inner(2);
    try std.testing.expectEqual(12, inner_rect.x);
    try std.testing.expectEqual(12, inner_rect.y);
    try std.testing.expectEqual(16, inner_rect.width);
    try std.testing.expectEqual(16, inner_rect.height);
}

test "Rect.inner - margin too large" {
    const r = Rect.new(0, 0, 10, 10);
    const inner_rect = r.inner(10);
    try std.testing.expectEqual(0, inner_rect.width);
    try std.testing.expectEqual(0, inner_rect.height);
}

test "Rect.intersects" {
    const r1 = Rect.new(0, 0, 10, 10);
    const r2 = Rect.new(5, 5, 10, 10);
    const r3 = Rect.new(20, 20, 10, 10);

    try std.testing.expect(r1.intersects(r2));
    try std.testing.expect(r2.intersects(r1));
    try std.testing.expect(!r1.intersects(r3));
}

test "Rect.intersection" {
    const r1 = Rect.new(0, 0, 10, 10);
    const r2 = Rect.new(5, 5, 10, 10);

    const inter = r1.intersection(r2).?;
    try std.testing.expectEqual(5, inter.x);
    try std.testing.expectEqual(5, inter.y);
    try std.testing.expectEqual(5, inter.width);
    try std.testing.expectEqual(5, inter.height);
}

test "Rect.intersection - no overlap" {
    const r1 = Rect.new(0, 0, 10, 10);
    const r2 = Rect.new(20, 20, 10, 10);

    try std.testing.expectEqual(null, r1.intersection(r2));
}

test "Constraint.apply - length" {
    const c = Constraint{ .length = 50 };
    try std.testing.expectEqual(50, c.apply(100));
    try std.testing.expectEqual(80, c.apply(80)); // clamped
}

test "Constraint.apply - percentage" {
    const c = Constraint{ .percentage = 50 };
    try std.testing.expectEqual(50, c.apply(100));
    try std.testing.expectEqual(25, c.apply(50));
}

test "Constraint.apply - percentage over 100" {
    const c = Constraint{ .percentage = 150 };
    try std.testing.expectEqual(100, c.apply(100)); // clamped to 100%
}

test "Constraint.apply - min" {
    const c = Constraint{ .min = 50 };
    try std.testing.expectEqual(50, c.apply(100));
    try std.testing.expectEqual(30, c.apply(30)); // clamped to available
}

test "Constraint.apply - max" {
    const c = Constraint{ .max = 50 };
    try std.testing.expectEqual(50, c.apply(100));
    try std.testing.expectEqual(30, c.apply(30));
}

test "Constraint.apply - ratio" {
    const c = Constraint{ .ratio = .{ .num = 1, .denom = 2 } };
    try std.testing.expectEqual(50, c.apply(100));
    try std.testing.expectEqual(25, c.apply(50));
}

test "Constraint.apply - ratio zero denominator" {
    const c = Constraint{ .ratio = .{ .num = 1, .denom = 0 } };
    try std.testing.expectEqual(0, c.apply(100));
}

test "split - horizontal with fixed lengths" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 100, 50);
    const constraints = [_]Constraint{
        .{ .length = 30 },
        .{ .length = 70 },
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    try std.testing.expectEqual(0, result[0].x);
    try std.testing.expectEqual(30, result[0].width);
    try std.testing.expectEqual(30, result[1].x);
    try std.testing.expectEqual(70, result[1].width);
}

test "split - vertical with percentages" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 100, 100);
    const constraints = [_]Constraint{
        .{ .percentage = 25 },
        .{ .percentage = 75 },
    };

    const result = try split(allocator, .vertical, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    try std.testing.expectEqual(0, result[0].y);
    try std.testing.expectEqual(25, result[0].height);
    try std.testing.expectEqual(25, result[1].y);
    try std.testing.expectEqual(75, result[1].height);
}

test "split - mixed constraints" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 100, 50);
    const constraints = [_]Constraint{
        .{ .length = 20 },
        .{ .percentage = 50 },
        .{ .ratio = .{ .num = 1, .denom = 4 } },
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(3, result.len);
    try std.testing.expectEqual(20, result[0].width);
    // Remaining space: 80, 50% = 40, ratio 1/4 = 20, total = 60
    // But we have 80 available, so last flexible gets the extra 20
}

test "split - empty constraints" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 100, 50);
    const constraints = [_]Constraint{};

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(0, result.len);
}

test "split - exceeding available space" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 100, 50);
    const constraints = [_]Constraint{
        .{ .length = 60 },
        .{ .length = 60 },
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    // Should be proportionally reduced to fit in 100
    const total_width = result[0].width + result[1].width;
    try std.testing.expectEqual(100, total_width);
}

test "split - vertical three-way" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 80, 60);
    const constraints = [_]Constraint{
        .{ .length = 10 },
        .{ .percentage = 50 },
        .{ .length = 10 },
    };

    const result = try split(allocator, .vertical, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(3, result.len);
    try std.testing.expectEqual(10, result[0].height);
    try std.testing.expectEqual(10, result[0].y);
    try std.testing.expectEqual(30, result[1].height); // 50% of 60
    try std.testing.expectEqual(20, result[1].y);
    try std.testing.expectEqual(10, result[2].height);
    try std.testing.expectEqual(50, result[2].y);
}
