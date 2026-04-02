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

    /// Calculate a rectangle with the given aspect ratio that fits within self
    /// Preserves x, y position and maintains the width:height ratio while
    /// fitting the largest possible rectangle within the available bounds.
    pub fn withAspectRatio(self: Rect, ratio: struct { width: u32, height: u32 }) Rect {
        // Handle zero ratio safely
        if (ratio.width == 0 or ratio.height == 0) {
            return Rect.new(self.x, self.y, 0, 0);
        }

        const width_u64 = @as(u64, self.width);
        const height_u64 = @as(u64, self.height);
        const ratio_w = @as(u64, ratio.width);
        const ratio_h = @as(u64, ratio.height);

        // Try width-constrained first: use full width, calculate height
        const calc_height = (width_u64 * ratio_h) / ratio_w;

        if (calc_height <= height_u64) {
            // Width-constrained fits: use full width
            return Rect.new(
                self.x,
                self.y,
                self.width,
                @as(u16, @intCast(calc_height)),
            );
        } else {
            // Width-constrained exceeds height: use full height instead
            const calc_width = (height_u64 * ratio_w) / ratio_h;
            return Rect.new(
                self.x,
                self.y,
                @as(u16, @intCast(@min(calc_width, width_u64))),
                self.height,
            );
        }
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
    /// Aspect ratio (width:height)
    aspect_ratio: struct { width: u32, height: u32 },

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
            .aspect_ratio => |ar| blk: {
                // Aspect ratio applies to one dimension at a time
                // Return the available space as-is; the caller will use Rect.withAspectRatio()
                // to compute the actual 2D constraints
                if (ar.width == 0 or ar.height == 0) break :blk 0;
                break :blk available;
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
            .percentage, .ratio, .aspect_ratio => {
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

    // If total exceeds available, reduce flexible constraints proportionally
    if (total_size > available) {
        // Calculate total size from fixed and percentage/ratio constraints
        var fixed_and_pct_total: u32 = 0;
        for (constraints, 0..) |constraint, i| {
            switch (constraint) {
                .length, .percentage, .ratio => fixed_and_pct_total += sizes[i],
                else => {},
            }
        }

        // If fixed+percentage alone exceeds available, scale everything
        if (fixed_and_pct_total >= available) {
            const scale = @as(f64, @floatFromInt(available)) / @as(f64, @floatFromInt(total_size));
            total_size = 0;
            for (sizes, 0..) |size, i| {
                const scaled = @as(u16, @intFromFloat(@as(f64, @floatFromInt(size)) * scale));
                sizes[i] = scaled;
                total_size += scaled;
            }
        } else {
            // Reduce flexible (min/max/aspect_ratio) constraints
            var flexible_total: u32 = 0;
            for (constraints, 0..) |constraint, i| {
                switch (constraint) {
                    .min, .max, .aspect_ratio => flexible_total += sizes[i],
                    else => {},
                }
            }

            if (flexible_total > 0) {
                const available_for_flexible = available - @as(u32, fixed_and_pct_total);
                const scale = @as(f64, @floatFromInt(available_for_flexible)) / @as(f64, @floatFromInt(flexible_total));
                total_size = fixed_and_pct_total;
                for (constraints, 0..) |constraint, i| {
                    switch (constraint) {
                        .min, .max, .aspect_ratio => {
                            const scaled = @as(u16, @intFromFloat(@as(f64, @floatFromInt(sizes[i])) * scale));
                            sizes[i] = scaled;
                            total_size += scaled;
                        },
                        else => {}, // Keep other sizes as-is
                    }
                }
            }
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
                .percentage, .ratio, .aspect_ratio, .min, .max => {
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
    try std.testing.expectEqual(50, c.apply(80)); // min of length and available
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
    try std.testing.expectEqual(0, result[0].y); // starts at area.y (0)
    try std.testing.expectEqual(40, result[1].height); // 50% of 60 + remaining space
    try std.testing.expectEqual(10, result[1].y); // after first block
    try std.testing.expectEqual(10, result[2].height);
    try std.testing.expectEqual(50, result[2].y); // after first two blocks
}

test "split - min constraint enforcement" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 100, 50);
    const constraints = [_]Constraint{
        .{ .min = 30 },
        .{ .min = 40 },
        .{ .min = 20 },
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(3, result.len);
    // Each should get at least its minimum
    try std.testing.expect(result[0].width >= 30);
    try std.testing.expect(result[1].width >= 40);
    try std.testing.expect(result[2].width >= 20);
}

test "split - max constraint with tight space" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 40, 50);
    const constraints = [_]Constraint{
        .{ .max = 20 },
        .{ .max = 30 },
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    // With 40 pixels available, max constraints should limit allocation
    // Each max is applied but space is distributed proportionally
    const total = result[0].width + result[1].width;
    try std.testing.expectEqual(40, total);
}

test "split - ratio with small denominators" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 100, 50);
    const constraints = [_]Constraint{
        .{ .ratio = .{ .num = 1, .denom = 2 } }, // 50%
        .{ .ratio = .{ .num = 1, .denom = 2 } }, // 50%
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    // Should split evenly
    try std.testing.expectEqual(50, result[0].width);
    try std.testing.expectEqual(50, result[1].width);
}

test "Rect.intersection with partial overlap" {
    const r1 = Rect.new(0, 0, 10, 10);
    const r2 = Rect.new(5, 5, 10, 10);

    const result = r1.intersection(r2);
    try std.testing.expect(result != null);
    const inter = result.?;
    try std.testing.expectEqual(@as(u16, 5), inter.x);
    try std.testing.expectEqual(@as(u16, 5), inter.y);
    try std.testing.expectEqual(@as(u16, 5), inter.width);
    try std.testing.expectEqual(@as(u16, 5), inter.height);
}

test "Rect.intersection with no overlap" {
    const r1 = Rect.new(0, 0, 10, 10);
    const r2 = Rect.new(20, 20, 10, 10);

    const result = r1.intersection(r2);
    try std.testing.expectEqual(@as(?Rect, null), result);
}

// ============================================================================
// Aspect Ratio Constraint Tests
// ============================================================================

test "Constraint - aspect ratio 16:9 wide available space" {
    const c = Constraint{ .aspect_ratio = .{ .width = 16, .height = 9 } };
    // With 1600 available width and unlimited height
    // Result should use full width: 1600 * 9 / 16 = 900 height
    const size = c.apply(1600);
    try std.testing.expectEqual(1600, size);
}

test "Constraint - aspect ratio 4:3 narrow available space" {
    const c = Constraint{ .aspect_ratio = .{ .width = 4, .height = 3 } };
    // With 400 available width
    // Result: 400 * 3 / 4 = 300 height
    const size = c.apply(400);
    try std.testing.expectEqual(400, size);
}

test "Constraint - aspect ratio 1:1 square" {
    const c = Constraint{ .aspect_ratio = .{ .width = 1, .height = 1 } };
    // Square ratio should preserve equal dimensions
    try std.testing.expectEqual(100, c.apply(100));
    try std.testing.expectEqual(50, c.apply(50));
    try std.testing.expectEqual(200, c.apply(200));
}

test "Constraint - aspect ratio portrait 9:16" {
    const c = Constraint{ .aspect_ratio = .{ .width = 9, .height = 16 } };
    // Portrait ratio: width-constrained
    // With 450 available: height = 450 * 16 / 9 = 800
    const size = c.apply(450);
    try std.testing.expectEqual(450, size);
}

test "Constraint - aspect ratio clamped to available" {
    const c = Constraint{ .aspect_ratio = .{ .width = 16, .height = 9 } };
    // With only 100 pixels available
    // Should still respect the ratio but clamp to available
    const size = c.apply(100);
    try std.testing.expectEqual(100, size);
}

test "aspect ratio helper - Rect.withAspectRatio basic" {
    const area = Rect.new(0, 0, 1600, 900);
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // Should fill the full width (1600) and calculate height (900)
    try std.testing.expectEqual(1600, constrained.width);
    try std.testing.expectEqual(900, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio portrait in landscape area" {
    const area = Rect.new(0, 0, 800, 600);
    const constrained = area.withAspectRatio(.{ .width = 9, .height = 16 });
    // Portrait ratio (9:16) in landscape area
    // Width-constrained: 800 available, height = 800 * 16 / 9 = 1422
    // But must fit in 600 height available, so height-constrained
    // Height: 600 available, width = 600 * 9 / 16 = 337.5 → 337
    try std.testing.expectEqual(337, constrained.width);
    try std.testing.expectEqual(600, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio exact fit" {
    const area = Rect.new(10, 20, 1920, 1080);
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // Exact 16:9 match: 1920 x 1080
    try std.testing.expectEqual(1920, constrained.width);
    try std.testing.expectEqual(1080, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio preserves position" {
    const area = Rect.new(100, 200, 400, 300);
    const constrained = area.withAspectRatio(.{ .width = 4, .height = 3 });
    // Position should be preserved
    try std.testing.expectEqual(100, constrained.x);
    try std.testing.expectEqual(200, constrained.y);
    // Dimensions: 4:3 ratio in 400x300 space
    try std.testing.expectEqual(400, constrained.width);
    try std.testing.expectEqual(300, constrained.height);
}

test "aspect ratio helper - Rect.withAspectRatio small area" {
    const area = Rect.new(0, 0, 20, 30);
    const constrained = area.withAspectRatio(.{ .width = 2, .height = 3 });
    // 2:3 portrait ratio in 20x30 area
    // Width-constrained: 20 * 3 / 2 = 30, fits in 30 height
    try std.testing.expectEqual(20, constrained.width);
    try std.testing.expectEqual(30, constrained.height);
}

test "split - aspect ratio constraint in layout" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 1600, 1200);
    const constraints = [_]Constraint{
        .{ .aspect_ratio = .{ .width = 16, .height = 9 } },
        .{ .length = 0 },
    };

    const result = try split(allocator, .horizontal, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(2, result.len);
    // First constraint: 16:9 in 1600 width = 1600 x 900
    try std.testing.expectEqual(1600, result[0].width);
    // Second gets remaining (if any)
}

test "split - aspect ratio with multiple constraints" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 800, 600);
    const constraints = [_]Constraint{
        .{ .length = 200 },
        .{ .aspect_ratio = .{ .width = 16, .height = 9 } },
        .{ .percentage = 25 },
    };

    const result = try split(allocator, .vertical, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(3, result.len);
    try std.testing.expectEqual(200, result[0].height); // fixed 200
    // Aspect ratio gets: ~411 (16:9 of remaining 400)
    // Percentage: ~25% of remaining
}

test "aspect ratio constraint - zero ratio should be safe" {
    const c = Constraint{ .aspect_ratio = .{ .width = 0, .height = 0 } };
    const size = c.apply(100);
    try std.testing.expectEqual(0, size);
}

test "aspect ratio constraint - width greater than height landscape" {
    const c = Constraint{ .aspect_ratio = .{ .width = 21, .height = 9 } };
    // Ultra-wide 21:9 (cinema scope)
    const size = c.apply(2100);
    try std.testing.expectEqual(2100, size);
}

test "aspect ratio constraint - height much greater than width tall" {
    const c = Constraint{ .aspect_ratio = .{ .width = 1, .height = 100 } };
    // Very tall ratio 1:100
    const size = c.apply(1000);
    try std.testing.expectEqual(1000, size);
}

test "Rect.withAspectRatio - width-constrained landscape" {
    const area = Rect.new(0, 0, 2000, 500);
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // 16:9 in 2000x500 space
    // Width-constrained would need 1111 height, but only 500 available
    // So height-constrained: 500 height needs 500 * 16 / 9 = 888 width
    try std.testing.expectEqual(888, constrained.width);
    try std.testing.expectEqual(500, constrained.height);
}

test "Rect.withAspectRatio - height-constrained portrait" {
    const area = Rect.new(0, 0, 300, 2000);
    const constrained = area.withAspectRatio(.{ .width = 16, .height = 9 });
    // 16:9 landscape in 300x2000 space
    // Height-constrained would need 3555 width, but only 300 available
    // So width-constrained: 300 width gives 300 * 9 / 16 = 168 height
    try std.testing.expectEqual(300, constrained.width);
    try std.testing.expectEqual(168, constrained.height);
}

test "Rect.withAspectRatio - square in rectangular area" {
    const area = Rect.new(50, 75, 1000, 400);
    const constrained = area.withAspectRatio(.{ .width = 1, .height = 1 });
    // 1:1 square in 1000x400 space = 400x400 (height-constrained)
    try std.testing.expectEqual(50, constrained.x);
    try std.testing.expectEqual(75, constrained.y);
    try std.testing.expectEqual(400, constrained.width);
    try std.testing.expectEqual(400, constrained.height);
}

test "Rect.withAspectRatio - common mobile aspect ratios" {
    // iPhone 14 Pro: 1170 x 2532 = 9:19.6 (roughly 9:20)
    const area = Rect.new(0, 0, 1170, 2532);
    const constrained = area.withAspectRatio(.{ .width = 9, .height = 20 });
    try std.testing.expectEqual(1170, constrained.width);
    try std.testing.expectEqual(2600, constrained.height); // 1170 * 20 / 9 = 2600
}

test "split - aspect ratio in three-way vertical split" {
    const allocator = std.testing.allocator;
    const area = Rect.new(0, 0, 400, 600);
    const constraints = [_]Constraint{
        .{ .percentage = 20 },
        .{ .aspect_ratio = .{ .width = 1, .height = 1 } },
        .{ .percentage = 20 },
    };

    const result = try split(allocator, .vertical, area, &constraints);
    defer allocator.free(result);

    try std.testing.expectEqual(3, result.len);
    try std.testing.expectEqual(120, result[0].height); // 20% of 600
    // Middle aspect ratio in remaining 360: 1:1 square = min(360, 360) = 360
    try std.testing.expectEqual(360, result[1].height);
    try std.testing.expectEqual(120, result[2].height); // 20% of remaining
}
